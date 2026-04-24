import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_retry_policy.dart';
import 'network_transport_policy.dart';

/// GitLab REST API v4（与官方文档一致的路径与鉴权）。
///
/// **第一步 · 在仓库内搜类名/关键词（blobs）**  
/// `GET /api/v4/projects/{项目ID}/search?scope=blobs&search=...`  
/// 请求头：`PRIVATE-TOKEN: <token>`。本客户端额外传 `ref`、`per_page`（GitLab Search API 支持）。
/// 响应中含文件名、路径、代码片段（`data`）等字段。
///
/// **第二步 · 拉取某文件全文（raw）**（本工具**未调用**，供对照文档或自行脚本使用）  
/// `GET /api/v4/projects/{项目ID}/repository/files/{URL编码后的文件路径}/raw?ref=main`  
/// 请求头：`PRIVATE-TOKEN: <token>`。
///
/// **本应用实际用法**：[searchBlobs] 走第一步；分析流程用返回的片段 + [commitsForPath]
///（`GET .../repository/commits?path=...&ref_name=...`）取该路径最近提交，写入提示词。
class GitLabClient {
  GitLabClient({required this.baseUrl, required this.privateToken, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String privateToken;
  final http.Client _http;

  Uri _api(String path, [Map<String, String>? query]) {
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root/api/v4$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'PRIVATE-TOKEN': privateToken,
        'Content-Type': 'application/json',
      };

  void _ensureHttpsBase() {
    NetworkTransportPolicy.requireHttpsApiBase(baseUrl, 'GitLab Base URL');
  }

  static bool _gitlabRetryable(Object e) => HttpRetryPolicy.defaultIsRetryable(e);

  Future<http.Response> _get(Uri uri) async {
    return HttpRetryPolicy.run(
      () async {
        final res = await _http.get(uri, headers: _headers);
        if (HttpRetryPolicy.isRetriableHttpStatus(res.statusCode)) {
          throw TransientHttpStatusException(res.statusCode);
        }
        return res;
      },
      isRetryable: _gitlabRetryable,
    );
  }

  /// [projectId] 可为数字 id 或 URL 编码路径 group%2Fproject。
  Future<List<GitLabBlobHit>> searchBlobs({
    required String projectId,
    required String search,
    required String ref,
    int perPage = 10,
  }) async {
    _ensureHttpsBase();
    final enc = Uri.encodeComponent(projectId);
    final uri = _api('/projects/$enc/search', {
      'scope': 'blobs',
      'search': search,
      'ref': ref,
      'per_page': '$perPage',
    });
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GitLabException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes));
    if (list is! List) return const [];
    return list.map((e) => GitLabBlobHit.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<GitLabCommitInfo>> commitsForPath({
    required String projectId,
    required String filePath,
    required String ref,
    int perPage = 5,
  }) async {
    _ensureHttpsBase();
    final enc = Uri.encodeComponent(projectId);
    final uri = _api('/projects/$enc/repository/commits', {
      'path': filePath,
      'ref_name': ref,
      'per_page': '$perPage',
    });
    final res = await _get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GitLabException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes));
    if (list is! List) return const [];
    return list.map((e) => GitLabCommitInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 校验 Token 能否访问项目（轻量 GET，不拉代码）。
  Future<String> fetchProjectLabel({required String projectId}) async {
    _ensureHttpsBase();
    final enc = Uri.encodeComponent(projectId);
    final uri = _api('/projects/$enc');
    final res = await _get(uri);
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GitLabException(res.statusCode, text);
    }
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      return 'ok';
    }
    return j['path_with_namespace']?.toString() ?? j['name']?.toString() ?? 'ok';
  }

  void close() => _http.close();
}

class GitLabBlobHit {
  GitLabBlobHit({
    this.basename,
    this.path,
    this.data,
    this.ref,
    this.projectId,
    this.startline,
    this.configRepoLabel,
    this.searchProjectId,
  });

  factory GitLabBlobHit.fromJson(Map<String, dynamic> j) {
    return GitLabBlobHit(
      basename: j['basename']?.toString(),
      path: j['path']?.toString(),
      data: j['data']?.toString(),
      ref: j['ref']?.toString(),
      projectId: j['project_id'] is int ? j['project_id'] as int : int.tryParse('${j['project_id']}'),
      startline: j['startline'] is int ? j['startline'] as int : int.tryParse('${j['startline']}'),
    );
  }

  /// 配置里的仓库名（或备注）；多仓库合并命中时用于区分来源。
  final String? configRepoLabel;
  /// 发起 API 时使用的 Project Id 字符串（与配置一致）。
  final String? searchProjectId;

  final String? basename;
  final String? path;
  final String? data;
  final String? ref;
  final int? projectId;
  final int? startline;
}

class GitLabCommitInfo {
  GitLabCommitInfo({this.id, this.title, this.authorName, this.committedDate, this.webUrl});

  factory GitLabCommitInfo.fromJson(Map<String, dynamic> j) {
    final author = j['author_name'] ?? j['commit_author_name'];
    return GitLabCommitInfo(
      id: j['id']?.toString(),
      title: j['title']?.toString() ?? j['message']?.toString(),
      authorName: author?.toString(),
      committedDate: j['committed_date']?.toString() ?? j['created_at']?.toString(),
      webUrl: j['web_url']?.toString(),
    );
  }

  final String? id;
  final String? title;
  final String? authorName;
  final String? committedDate;
  final String? webUrl;
}

class GitLabException implements Exception {
  GitLabException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  /// 可与 [HttpRetryPolicy.isRetriableHttpStatus] 配合；401/403/404 等不重试。
  bool get isTransientStatus => HttpRetryPolicy.isRetriableHttpStatus(statusCode);

  String get userMessage => 'GitLab 接口错误（HTTP $statusCode）';

  @override
  String toString() => userMessage;
}
