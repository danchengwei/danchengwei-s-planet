import 'package:http/http.dart' as http;

import 'create_outbound_client.dart';

/// 创建出站 [http.Client]，供 **EMAS / GitLab / 大模型** 共用。
///
/// 与 `tool/emas_openapi_probe.dart` 一致：桌面端为 IO 版 `HttpClient`（遵循环境变量中的代理设置）。
/// 新增访问上述接口的代码时须传入此处创建的 Client，并在 `finally` 中 [http.Client.close]。
http.Client newOutboundHttpClient() => createOutboundHttpClient();
