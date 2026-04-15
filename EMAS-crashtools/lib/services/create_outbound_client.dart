import 'package:http/http.dart' as http;

import 'create_outbound_client_stub.dart'
    if (dart.library.io) 'create_outbound_client_io.dart' as impl;

/// 创建出站 [http.Client]（EMAS / GitLab / 大模型共用）。
http.Client createOutboundHttpClient() => impl.createOutboundHttpClient();
