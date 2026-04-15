import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 桌面端出站 [http.Client]：底层 `HttpClient` 使用 [HttpClient.findProxyFromEnvironment]（可读 `HTTPS_PROXY` / `https_proxy` 等环境变量）。
http.Client createOutboundHttpClient() {
  final inner = HttpClient();
  inner.findProxy = HttpClient.findProxyFromEnvironment;
  return IOClient(inner);
}
