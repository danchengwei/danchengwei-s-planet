import 'dart:async';
import 'dart:io' show HandshakeException, SocketException;

import 'package:http/http.dart' as http;

import '../aliyun/emas_appmonitor_client.dart';
import 'gitlab_client.dart';
import 'http_retry_policy.dart';
import 'llm_client.dart';

/// 将异常转为可展示文案：不附带完整响应体，降低密钥或业务数据经界面/日志外泄风险。
String userFacingNetworkError(Object error) {
  if (error is ApiRetryExhaustedException) {
    return '${userFacingNetworkError(error.cause)}（已在客户端自动重试 ${error.attempts} 次）';
  }
  if (error is TransientHttpStatusException) {
    if (error.statusCode == 429) {
      return '请求过于频繁或服务限速（HTTP 429），请稍后再试';
    }
    if (error.statusCode >= 500) {
      return '服务端暂时不可用（HTTP ${error.statusCode}），请稍后再试';
    }
    return '网络或服务暂态异常（HTTP ${error.statusCode}），请稍后再试';
  }
  if (error is LlmException) {
    if (error.statusCode == 429) {
      return '大模型接口限速（HTTP 429），请稍后再试';
    }
    if (error.statusCode >= 500) {
      return '大模型服务端异常（HTTP ${error.statusCode}），请稍后再试';
    }
    return error.userMessage;
  }
  if (error is GitLabException) {
    if (error.statusCode == 429) {
      return 'GitLab 请求频率受限（HTTP 429），请稍后再试';
    }
    if (error.statusCode >= 500) {
      return 'GitLab 服务暂时异常（HTTP ${error.statusCode}），请稍后再试';
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return 'GitLab 鉴权失败（HTTP ${error.statusCode}），请检查 Token 与权限';
    }
    if (error.statusCode == 404) {
      return 'GitLab 资源不存在（HTTP 404），请检查 Project Id 与仓库路径';
    }
    return error.userMessage;
  }
  if (error is TimeoutException) {
    return '请求超时，请检查网络或稍后再试';
  }
  if (error is http.ClientException) {
    return '网络连接异常，请检查网络或代理设置';
  }
  if (error is SocketException) {
    return '网络不可达或连接被中断，请检查网络';
  }
  if (error is HandshakeException) {
    return '安全连接（TLS）失败，请检查网络、系统时间或代理';
  }
  if (error is EmasApiException) {
    final codeLower = error.code?.toLowerCase() ?? '';
    if (codeLower.contains('throttl')) {
      return 'EMAS 请求过于频繁，请稍后再试';
    }
    if (codeLower.contains('invalidaccesskey') ||
        codeLower.contains('signature') ||
        codeLower.contains('forbidden')) {
      return 'EMAS 鉴权失败，请检查 AccessKey 与签名相关配置';
    }
    final m = error.message;
    final short = m.length > 280 ? '${m.substring(0, 280)}…' : m;
    final c = error.code;
    if (c != null && c.isNotEmpty) {
      return 'EMAS 错误 [$c]：$short';
    }
    return 'EMAS 错误：$short';
  }
  if (error is FormatException) {
    final m = error.message;
    return m.isNotEmpty ? m : '请求参数无效';
  }
  final s = error.toString();
  if (s.length > 400) {
    return '${s.substring(0, 400)}…';
  }
  return s;
}
