import 'package:http/http.dart' as http;

/// Web 等平台无 dart:io，退化为默认 [http.Client]。
http.Client createOutboundHttpClient() => http.Client();
