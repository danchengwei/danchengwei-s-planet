import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 表示「可退避重试」的暂态 HTTP 状态（网关、限速、服务端忙等），非业务逻辑错误。
class TransientHttpStatusException implements Exception {
  TransientHttpStatusException(this.statusCode);
  final int statusCode;
}

/// 已达最大重试次数；[cause] 为最后一次失败（供脱敏展示）。
class ApiRetryExhaustedException implements Exception {
  ApiRetryExhaustedException({required this.attempts, required this.cause});
  final int attempts;
  final Object cause;
}

/// EMAS / GitLab / LLM 等 HTTP 调用的**有限次退避重试**（网络抖动、429、5xx）。
class HttpRetryPolicy {
  HttpRetryPolicy._();

  static const int defaultMaxAttempts = 4;
  static const Duration defaultPerAttemptTimeout = Duration(seconds: 55);

  static final Random _rng = Random();

  /// 适合重试的 HTTP 状态码：超时、限速、服务端暂态。
  static bool isRetriableHttpStatus(int code) {
    if (code == 408 || code == 429) return true;
    if (code >= 500 && code <= 599) return true;
    return false;
  }

  static bool _isNetworkLayer(Object e) {
    if (e is TimeoutException) return true;
    if (e is http.ClientException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;
    return false;
  }

  /// 默认可重试：网络类异常 + [TransientHttpStatusException]。
  static bool defaultIsRetryable(Object e) {
    if (e is ApiRetryExhaustedException) return false;
    if (e is TransientHttpStatusException) return true;
    return _isNetworkLayer(e);
  }

  /// 第 1 次失败后等待约 400ms，之后指数退避，并加少量抖动避免齐刷刷重试。
  static Duration delayBeforeAttempt(int failedAttemptIndex) {
    final baseMs = 400 * (1 << (failedAttemptIndex - 1).clamp(0, 8));
    final jitter = _rng.nextInt(200);
    return Duration(milliseconds: baseMs + jitter);
  }

  /// 执行 [action]，失败时若 [isRetryable] 为 true 则退避后重试，直至 [maxAttempts]。
  static Future<T> run<T>(
    Future<T> Function() action, {
    int maxAttempts = defaultMaxAttempts,
    Duration? perAttemptTimeout,
    bool Function(Object error)? isRetryable,
  }) async {
    final timeout = perAttemptTimeout ?? defaultPerAttemptTimeout;
    final retryable = isRetryable ?? defaultIsRetryable;
    Object? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action().timeout(timeout);
      } catch (e, st) {
        last = e;
        final canRetry = retryable(e);
        if (!canRetry || attempt >= maxAttempts) {
          if (canRetry && attempt >= maxAttempts && maxAttempts > 1) {
            Error.throwWithStackTrace(
              ApiRetryExhaustedException(attempts: maxAttempts, cause: e),
              st,
            );
          }
          rethrow;
        }
        await Future<void>.delayed(delayBeforeAttempt(attempt));
      }
    }
    // 理论不可达
    throw last ?? StateError('HttpRetryPolicy: empty error');
  }
}
