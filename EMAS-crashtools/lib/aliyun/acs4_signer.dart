import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _algo = 'ACS4-HMAC-SHA256';

/// 阿里云 OpenAPI POP 网关（ACS4-HMAC-SHA256），与 @alicloud/gateway-pop 行为对齐。
class Acs4Signer {
  static Uint8List _hmacSha256(Uint8List key, List<int> data) {
    final mac = Hmac(sha256, key);
    return Uint8List.fromList(mac.convert(data).bytes);
  }

  static Uint8List _hmacSha256Utf8(Uint8List key, String s) => _hmacSha256(key, utf8.encode(s));

  static Uint8List signingKey(String accessKeySecret, String dateStamp, String region, String product) {
    final k0 = Uint8List.fromList(utf8.encode('aliyun_v4$accessKeySecret'));
    final k1 = _hmacSha256Utf8(k0, dateStamp);
    final k2 = _hmacSha256Utf8(k1, region);
    final k3 = _hmacSha256Utf8(k2, product);
    return _hmacSha256Utf8(k3, 'aliyun_v4_request');
  }

  /// 从 host 解析 region，例如 emas-appmonitor.cn-shanghai.aliyuncs.com -> cn-shanghai
  static String regionFromEndpoint(String host) {
    final h = host.split(':').first;
    final withoutSuffix = h.replaceAll('.aliyuncs.com', '');
    final parts = withoutSuffix.split('.');
    if (parts.length >= 2) {
      return parts.last;
    }
    return 'cn-shanghai';
  }

  static String utcTimestamp() {
    final now = DateTime.now().toUtc();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${p2(now.month)}-${p2(now.day)}T${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}Z';
  }

  static String dateStampFromTimestamp(String ts) {
    return ts.substring(0, 10).replaceAll('-', '');
  }

  static List<String> signedHeaderKeys(Map<String, String> headers) {
    final set = <String>{};
    headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower.startsWith('x-acs-') || lower == 'host' || lower == 'content-type') {
        set.add(lower);
      }
    });
    final list = set.toList()..sort();
    return list;
  }

  static String canonicalHeaders(Map<String, String> headers, List<String> signedKeys) {
    final buf = StringBuffer();
    for (final key in signedKeys) {
      String? val;
      headers.forEach((k, v) {
        if (k.toLowerCase() == key) val = v.trim();
      });
      buf.write('$key:${val ?? ''}\n');
    }
    return buf.toString();
  }

  static String hexSha256Bytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// [formBody] 已为 urlencoded 的 ASCII/UTF8 字节序列（与网关哈希一致）。
  static Map<String, String> buildAuthorizedHeaders({
    required String host,
    required String method,
    required String pathname,
    required String action,
    required String version,
    required String accessKeyId,
    required String accessKeySecret,
    required String formBody,
    required String productId,
  }) {
    final ts = utcTimestamp();
    final dateStamp = dateStampFromTimestamp(ts);
    final region = regionFromEndpoint(host);
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    final payloadHash = hexSha256Bytes(utf8.encode(formBody));

    final headers = <String, String>{
      'host': host,
      'x-acs-action': action,
      'x-acs-version': version,
      'x-acs-date': ts,
      'x-acs-signature-nonce': nonce,
      'accept': 'application/json',
      'content-type': 'application/x-www-form-urlencoded',
      'user-agent': 'crash_emas_tool/1.0 (Flutter)',
    };

    final signedKeys = signedHeaderKeys(headers);
    final canonH = canonicalHeaders(headers, signedKeys);
    final signedHeadersStr = signedKeys.join(';');

    final canonicalRequest = [
      method.toUpperCase(),
      pathname.isEmpty ? '/' : pathname,
      '',
      canonH,
      signedHeadersStr,
      payloadHash,
    ].join('\n');

    final stringToSign = '$_algo\n${hexSha256Bytes(utf8.encode(canonicalRequest))}';

    final sk = signingKey(accessKeySecret, dateStamp, region, productId);
    final sigBytes = _hmacSha256Utf8(sk, stringToSign);
    final signature = sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final credential = '$accessKeyId/$dateStamp/$region/$productId/aliyun_v4_request';
    final auth = '$_algo Credential=$credential,SignedHeaders=$signedHeadersStr,Signature=$signature';

    headers['Authorization'] = auth;
    return headers;
  }
}
