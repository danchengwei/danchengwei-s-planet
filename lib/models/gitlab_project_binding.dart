/// 一条 GitLab 仓库绑定：API 用的 [projectId] + 界面展示的 [repoName]（仓库名/备注）。
class GitlabProjectBinding {
  const GitlabProjectBinding({
    this.projectId = '',
    this.repoName = '',
  });

  final String projectId;
  final String repoName;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'repoName': repoName,
      };

  factory GitlabProjectBinding.fromJson(Map<String, dynamic> j) {
    return GitlabProjectBinding(
      projectId: j['projectId']?.toString() ?? '',
      repoName: j['repoName']?.toString() ?? '',
    );
  }
}
