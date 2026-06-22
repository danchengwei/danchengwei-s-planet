import 'dart:math';

import '../models/tool_config.dart';
import 'gitlab_client.dart';
import 'outbound_http_client_for_config.dart';
import 'stack_keywords.dart';

/// 在配置的多个 GitLab 项目中搜索关键词，合并 Blob 命中；对**合并结果中首条**有路径的命中在其所属项目中拉取 commits。
Future<GitlabMergedSearchOutcome> searchGitlabMergedForKeyword({
  required ToolConfig config,
  required String searchKeyword,
  int maxTotalHits = 16,
  int perProjectLimit = 8,
}) async {
  final refRaw = config.gitlabRef.trim();
  final ref = refRaw.isEmpty ? 'main' : refRaw;
  final bindings = config.gitlabBindingsResolved;
  final merged = <GitLabBlobHit>[];

  final client = GitLabClient(
    baseUrl: config.gitlabBaseUrl.trim(),
    privateToken: config.gitlabToken.trim(),
    httpClient: newOutboundHttpClient(),
  );
  try {
    for (final b in bindings) {
      if (merged.length >= maxTotalHits) break;
      final pid = b.projectId.trim();
      if (pid.isEmpty) continue;
      final room = maxTotalHits - merged.length;
      final take = min(perProjectLimit, room);
      final hits = await client.searchBlobs(
        projectId: pid,
        search: searchKeyword,
        ref: ref,
        perPage: take,
      );
      final label = b.repoName.trim().isNotEmpty ? b.repoName.trim() : pid;
      for (final h in hits) {
        merged.add(GitLabBlobHit(
          basename: h.basename,
          path: h.path,
          data: h.data,
          ref: h.ref,
          projectId: h.projectId,
          startline: h.startline,
          configRepoLabel: label,
          searchProjectId: pid,
        ));
      }
    }
    var commits = <GitLabCommitInfo>[];
    GitLabBlobHit? firstWithPath;
    for (final h in merged) {
      final p = h.path?.trim() ?? '';
      if (p.isNotEmpty) {
        firstWithPath = h;
        break;
      }
    }
    final sp = firstWithPath?.searchProjectId?.trim() ?? '';
    final fp = firstWithPath?.path?.trim() ?? '';
    if (sp.isNotEmpty && fp.isNotEmpty) {
      commits = await client.commitsForPath(
        projectId: sp,
        filePath: fp,
        ref: ref,
      );
    }
    return GitlabMergedSearchOutcome(hits: merged, commits: commits);
  } finally {
    client.close();
  }
}

/// 根据堆栈关键词搜索 GitLab Blob（多仓库合并），并拉取首条命中路径的最近提交。
Future<GitlabStackSearchResult> searchGitlabForStack({
  required ToolConfig config,
  required String stack,
  int perPage = 8,
}) async {
  final miss = config.validateGitlab();
  if (miss.isNotEmpty) {
    return GitlabStackSearchResult(
      hits: const [],
      commits: const [],
      skippedReason: 'GitLab 未配置：${miss.join('、')}',
    );
  }
  final kw = extractStackKeywords(stack);
  if (kw.isEmpty) {
    return const GitlabStackSearchResult(
      hits: [],
      commits: [],
      skippedReason: '未能从堆栈提取关键词',
    );
  }

  final q = kw.first;
  final out = await searchGitlabMergedForKeyword(
    config: config,
    searchKeyword: q,
    maxTotalHits: perPage * 2,
    perProjectLimit: perPage,
  );
  return GitlabStackSearchResult(hits: out.hits, commits: out.commits, searchKeyword: q);
}

class GitlabMergedSearchOutcome {
  const GitlabMergedSearchOutcome({
    required this.hits,
    required this.commits,
  });

  final List<GitLabBlobHit> hits;
  final List<GitLabCommitInfo> commits;
}

class GitlabStackSearchResult {
  const GitlabStackSearchResult({
    required this.hits,
    required this.commits,
    this.skippedReason,
    this.searchKeyword,
  });

  final List<GitLabBlobHit> hits;
  final List<GitLabCommitInfo> commits;
  final String? skippedReason;
  final String? searchKeyword;
}
