/// 携带密钥、Token 的出站 API 须使用 HTTPS，避免明文传输。
abstract final class NetworkTransportPolicy {
  /// [raw] 已 trim；非空且非 https 时抛出 [FormatException]。
  static void requireHttpsApiBase(String raw, String label) {
    final t = raw.trim();
    if (t.isEmpty) {
      throw FormatException('$label 不能为空');
    }
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      throw FormatException('$label 格式无效，请填写完整地址（须含 https:// 与主机名）');
    }
    if (u.scheme != 'https') {
      throw FormatException('$label 必须使用 HTTPS，禁止以明文传输密钥（当前为 ${u.scheme}://）');
    }
  }
}
