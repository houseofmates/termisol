import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'git_integration.dart';
import 'conversational_ai.dart';
import 'semantic_search_engine.dart';

/// GitHub Integration for Termisol
///
/// Provides comprehensive GitHub integration including:
/// - Repository management and cloning
/// - Pull request creation and management
/// - Issue tracking and management
/// - GitHub Actions workflow management
/// - Code review integration
/// - Collaborative features
/// - GitHub API integration
class GitHubIntegration {
  final GitIntegration _gitIntegration;
  final ConversationalAI _conversationalAI;
  final SemanticSearchEngine _searchEngine;

  final StreamController<GitHubEvent> _githubEventController =
      StreamController<GitHubEvent>.broadcast();

  Stream<GitHubEvent> get events => _githubEventController.stream;

  String? _accessToken;
  String? _username;
  final Map<String, GitHubRepository> _repositories = {};
  final Map<String, GitHubPullRequest> _pullRequests = {};
  final Map<String, GitHubIssue> _issues = {};
  final List<GitHubWorkflow> _workflows = [];

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  GitHubIntegration(this._gitIntegration, this._conversationalAI, this._searchEngine);

  /// Initialize GitHub integration
  Future<void> initialize() async {
    await _gitIntegration.initialize();
    debugPrint('🐙 GitHub Integration initialized');
  }

  /// Authenticate with GitHub
  Future<bool> authenticate(String token) async {
    try {
      _accessToken = token;

      // Validate token and get user info
      final userInfo = await _apiCall('GET', '/user');
      _username = userInfo['login'];
      _isAuthenticated = true;

      _githubEventController.add(GitHubEvent(
        type: GitHubEventType.authenticated,
        data: {'username': _username},
      ));

      debugPrint('✅ GitHub authentication successful: $_username');
      return true;
    } catch (e) {
      debugPrint('❌ GitHub authentication failed: $e');
      _isAuthenticated = false;
      return false;
    }
  }

  /// Clone repository from GitHub
  Future<bool> cloneRepository(String repoUrl, {String? localPath}) async {
    if (!_isAuthenticated) {
      throw Exception('Not authenticated with GitHub');
    }

    try {
      final result = await _gitIntegration.cloneRepository(
        repoUrl,
        directory: localPath,
      );

      if (result.success) {
        // Get repository info
        final repoInfo = await _getRepositoryInfo(repoUrl);
        if (repoInfo != null) {
          _repositories[repoInfo.fullName] = repoInfo;

          _githubEventController.add(GitHubEvent(
            type: GitHubEventType.repository_cloned,
            data: {'repository': repoInfo.fullName, 'localPath': localPath},
          ));
        }
      }

      return result.success;
    } catch (e) {
      debugPrint('❌ Failed to clone repository: $e');
      return false;
    }
  }

  /// Create and push changes to GitHub
  Future<GitHubPullRequest?> createPullRequest({
    required String repoName,
    required String title,
    required String body,
    required String headBranch,
    required String baseBranch,
    List<String>? reviewers,
    List<String>? labels,
  }) async {
    if (!_isAuthenticated) {
      throw Exception('Not authenticated with GitHub');
    }

    try {
      // First, push the branch if it doesn't exist remotely
      await _gitIntegration.push(remote: 'origin', branch: headBranch);

      // Create PR via API
      final prData = {
        'title': title,
        'body': body,
        'head': headBranch,
        'base': baseBranch,
        'draft': false,
      };

      final response = await _apiCall('POST', '/repos/$repoName/pulls', body: prData);

      final pullRequest = GitHubPullRequest.fromJson(response);

      // Add reviewers if specified
      if (reviewers != null && reviewers.isNotEmpty) {
        await _requestReviewers(repoName, pullRequest.number, reviewers);
      }

      // Add labels if specified
      if (labels != null && labels.isNotEmpty) {
        await _addLabels(repoName, pullRequest.number, labels);
      }

      _pullRequests['$repoName#${pullRequest.number}'] = pullRequest;

      _githubEventController.add(GitHubEvent(
        type: GitHubEventType.pull_request_created,
        data: {'pullRequest': pullRequest},
      ));

      debugPrint('✅ Pull request created: ${pullRequest.htmlUrl}');
      return pullRequest;
    } catch (e) {
      debugPrint('❌ Failed to create pull request: $e');
      return null;
    }
  }

  /// Create issue on GitHub
  Future<GitHubIssue?> createIssue({
    required String repoName,
    required String title,
    required String body,
    List<String>? labels,
    List<String>? assignees,
  }) async {
    if (!_isAuthenticated) {
      throw Exception('Not authenticated with GitHub');
    }

    try {
      final issueData = {
        'title': title,
        'body': body,
        'labels': labels ?? [],
        'assignees': assignees ?? [],
      };

      final response = await _apiCall('POST', '/repos/$repoName/issues', body: issueData);
      final issue = GitHubIssue.fromJson(response);

      _issues['$repoName#${issue.number}'] = issue;

      _githubEventController.add(GitHubEvent(
        type: GitHubEventType.issue_created,
        data: {'issue': issue},
      ));

      debugPrint('✅ Issue created: ${issue.htmlUrl}');
      return issue;
    } catch (e) {
      debugPrint('❌ Failed to create issue: $e');
      return null;
    }
  }

  /// Get repository information
  Future<GitHubRepository?> _getRepositoryInfo(String repoUrl) async {
    try {
      // Extract owner/repo from URL
      final uri = Uri.parse(repoUrl);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2) {
        final owner = pathSegments[pathSegments.length - 2];
        final repo = pathSegments.last.replaceAll('.git', '');

        final response = await _apiCall('GET', '/repos/$owner/$repo');
        return GitHubRepository.fromJson(response);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get repository info: $e');
    }
    return null;
  }

  /// Request reviewers for PR
  Future<void> _requestReviewers(String repoName, int prNumber, List<String> reviewers) async {
    try {
      final data = {'reviewers': reviewers};
      await _apiCall('POST', '/repos/$repoName/pulls/$prNumber/requested_reviewers', body: data);
    } catch (e) {
      debugPrint('⚠️ Failed to request reviewers: $e');
    }
  }

  /// Add labels to PR/issue
  Future<void> _addLabels(String repoName, int number, List<String> labels) async {
    try {
      final data = {'labels': labels};
      await _apiCall('POST', '/repos/$repoName/issues/$number/labels', body: data);
    } catch (e) {
      debugPrint('⚠️ Failed to add labels: $e');
    }
  }

  /// Get GitHub workflows for repository
  Future<List<GitHubWorkflow>> getWorkflows(String repoName) async {
    try {
      final response = await _apiCall('GET', '/repos/$repoName/actions/workflows');
      final workflows = (response['workflows'] as List)
          .map((w) => GitHubWorkflow.fromJson(w))
          .toList();

      _workflows.clear();
      _workflows.addAll(workflows);

      return workflows;
    } catch (e) {
      debugPrint('❌ Failed to get workflows: $e');
      return [];
    }
  }

  /// Run GitHub workflow
  Future<bool> runWorkflow(String repoName, String workflowId, {Map<String, dynamic>? inputs}) async {
    try {
      final data = {
        'ref': 'main', // or current branch
        'inputs': inputs ?? {},
      };

      await _apiCall('POST', '/repos/$repoName/actions/workflows/$workflowId/dispatches', body: data);
      debugPrint('✅ Workflow triggered: $workflowId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to run workflow: $e');
      return false;
    }
  }

  /// Get pull requests for repository
  Future<List<GitHubPullRequest>> getPullRequests(String repoName, {String? state}) async {
    try {
      final queryParams = state != null ? '?state=$state' : '';
      final response = await _apiCall('GET', '/repos/$repoName/pulls$queryParams');

      final prs = (response as List)
          .map((pr) => GitHubPullRequest.fromJson(pr))
          .toList();

      // Cache PRs
      for (final pr in prs) {
        _pullRequests['$repoName#${pr.number}'] = pr;
      }

      return prs;
    } catch (e) {
      debugPrint('❌ Failed to get pull requests: $e');
      return [];
    }
  }

  /// Get issues for repository
  Future<List<GitHubIssue>> getIssues(String repoName, {String? state, List<String>? labels}) async {
    try {
      var queryParams = '';
      if (state != null || (labels != null && labels.isNotEmpty)) {
        final params = <String>[];
        if (state != null) params.add('state=$state');
        if (labels != null && labels.isNotEmpty) {
          params.add('labels=${labels.join(',')}');
        }
        queryParams = '?${params.join('&')}';
      }

      final response = await _apiCall('GET', '/repos/$repoName/issues$queryParams');

      final issues = (response as List)
          .map((issue) => GitHubIssue.fromJson(issue))
          .toList();

      // Cache issues
      for (final issue in issues) {
        _issues['$repoName#${issue.number}'] = issue;
      }

      return issues;
    } catch (e) {
      debugPrint('❌ Failed to get issues: $e');
      return [];
    }
  }

  /// Search GitHub repositories
  Future<List<GitHubRepository>> searchRepositories(String query, {
    String? language,
    String? sort,
    int perPage = 30,
  }) async {
    try {
      var searchQuery = query;
      if (language != null) {
        searchQuery += ' language:$language';
      }

      final params = {
        'q': searchQuery,
        'sort': sort ?? 'stars',
        'per_page': perPage.toString(),
      };

      final response = await _apiCall('GET', '/search/repositories', queryParams: params);
      final repos = (response['items'] as List)
          .map((repo) => GitHubRepository.fromJson(repo))
          .toList();

      return repos;
    } catch (e) {
      debugPrint('❌ Failed to search repositories: $e');
      return [];
    }
  }

  /// Fork repository
  Future<GitHubRepository?> forkRepository(String repoName) async {
    try {
      final response = await _apiCall('POST', '/repos/$repoName/forks');
      final forkedRepo = GitHubRepository.fromJson(response);

      _repositories[forkedRepo.fullName] = forkedRepo;

      _githubEventController.add(GitHubEvent(
        type: GitHubEventType.repository_forked,
        data: {'repository': forkedRepo},
      ));

      debugPrint('✅ Repository forked: ${forkedRepo.fullName}');
      return forkedRepo;
    } catch (e) {
      debugPrint('❌ Failed to fork repository: $e');
      return null;
    }
  }

  /// Create repository
  Future<GitHubRepository?> createRepository({
    required String name,
    String? description,
    bool isPrivate = false,
    bool autoInit = true,
  }) async {
    try {
      final repoData = {
        'name': name,
        'description': description ?? '',
        'private': isPrivate,
        'auto_init': autoInit,
      };

      final response = await _apiCall('POST', '/user/repos', body: repoData);
      final repository = GitHubRepository.fromJson(response);

      _repositories[repository.fullName] = repository;

      _githubEventController.add(GitHubEvent(
        type: GitHubEventType.repository_created,
        data: {'repository': repository},
      ));

      debugPrint('✅ Repository created: ${repository.fullName}');
      return repository;
    } catch (e) {
      debugPrint('❌ Failed to create repository: $e');
      return null;
    }
  }

  /// Get repository collaborators
  Future<List<GitHubUser>> getCollaborators(String repoName) async {
    try {
      final response = await _apiCall('GET', '/repos/$repoName/collaborators');
      return (response as List)
          .map((user) => GitHubUser.fromJson(user))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to get collaborators: $e');
      return [];
    }
  }

  /// Add collaborator to repository
  Future<bool> addCollaborator(String repoName, String username, {String permission = 'push'}) async {
    try {
      final data = {'permission': permission};
      await _apiCall('PUT', '/repos/$repoName/collaborators/$username', body: data);
      debugPrint('✅ Collaborator added: $username');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to add collaborator: $e');
      return false;
    }
  }

  /// Get repository statistics
  Future<RepositoryStats?> getRepositoryStats(String repoName) async {
    try {
      final contributors = await _apiCall('GET', '/repos/$repoName/contributors');
      final commits = await _apiCall('GET', '/repos/$repoName/commits?per_page=1');
      final releases = await _apiCall('GET', '/repos/$repoName/releases?per_page=1');

      return RepositoryStats(
        contributorCount: (contributors as List).length,
        commitCount: commits.length, // This is approximate
        releaseCount: (releases as List).length,
        openIssues: await _getOpenIssueCount(repoName),
        openPullRequests: await _getOpenPRCount(repoName),
      );
    } catch (e) {
      debugPrint('❌ Failed to get repository stats: $e');
      return null;
    }
  }

  /// Get open issue count
  Future<int> _getOpenIssueCount(String repoName) async {
    try {
      final response = await _apiCall('GET', '/repos/$repoName');
      return response['open_issues_count'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get open PR count
  Future<int> _getOpenPRCount(String repoName) async {
    try {
      final response = await _apiCall('GET', '/repos/$repoName/pulls?state=open');
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// GitHub API call helper
  Future<dynamic> _apiCall(String method, String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    if (_accessToken == null) {
      throw Exception('No access token available');
    }

    final url = 'https://api.github.com$endpoint';
    final uri = Uri.parse(url).replace(queryParameters: queryParams);

    final headers = {
      'Authorization': 'token $_accessToken',
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Termisol/1.0',
    };

    // Simulate API call (in real implementation, use http package)
    await Future.delayed(Duration(milliseconds: 100 + (endpoint.length * 2)));

    // Mock responses for demonstration
    return _mockApiResponse(endpoint, body);
  }

  /// Mock API responses for demonstration
  dynamic _mockApiResponse(String endpoint, Map<String, dynamic>? body) {
    if (endpoint == '/user') {
      return {
        'login': 'testuser',
        'id': 12345,
        'name': 'Test User',
        'email': 'test@example.com',
      };
    }

    if (endpoint.startsWith('/repos/') && endpoint.endsWith('/pulls') && body != null) {
      return {
        'number': 42,
        'title': body['title'],
        'body': body['body'],
        'html_url': 'https://github.com/test/repo/pull/42',
        'state': 'open',
        'created_at': DateTime.now().toIso8601String(),
      };
    }

    if (endpoint.startsWith('/repos/') && endpoint.contains('/issues') && body != null) {
      return {
        'number': 24,
        'title': body['title'],
        'body': body['body'],
        'html_url': 'https://github.com/test/repo/issues/24',
        'state': 'open',
        'created_at': DateTime.now().toIso8601String(),
      };
    }

    if (endpoint.startsWith('/repos/')) {
      return {
        'name': 'test-repo',
        'full_name': 'testuser/test-repo',
        'html_url': 'https://github.com/testuser/test-repo',
        'description': 'Test repository',
        'language': 'Dart',
        'forks_count': 5,
        'stargazers_count': 42,
        'open_issues_count': 3,
      };
    }

    return {};
  }

  /// Get integration statistics
  Map<String, dynamic> getIntegrationStats() {
    return {
      'is_authenticated': _isAuthenticated,
      'username': _username,
      'repositories_count': _repositories.length,
      'pull_requests_count': _pullRequests.length,
      'issues_count': _issues.length,
      'workflows_count': _workflows.length,
    };
  }

  /// Logout from GitHub
  void logout() {
    _accessToken = null;
    _username = null;
    _isAuthenticated = false;
    _repositories.clear();
    _pullRequests.clear();
    _issues.clear();
    _workflows.clear();

    _githubEventController.add(GitHubEvent(
      type: GitHubEventType.logged_out,
      data: {},
    ));

    debugPrint('👋 Logged out from GitHub');
  }

  /// Dispose resources
  void dispose() {
    _githubEventController.close();
  }
}

/// GitHub Event Types
enum GitHubEventType {
  authenticated,
  logged_out,
  repository_cloned,
  repository_created,
  repository_forked,
  pull_request_created,
  pull_request_merged,
  issue_created,
  issue_closed,
  workflow_triggered,
}

/// GitHub Event
class GitHubEvent {
  final GitHubEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  GitHubEvent({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// GitHub Repository
class GitHubRepository {
  final int id;
  final String name;
  final String fullName;
  final String htmlUrl;
  final String? description;
  final String? language;
  final int forksCount;
  final int stargazersCount;
  final int openIssuesCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  GitHubRepository({
    required this.id,
    required this.name,
    required this.fullName,
    required this.htmlUrl,
    this.description,
    this.language,
    required this.forksCount,
    required this.stargazersCount,
    required this.openIssuesCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GitHubRepository.fromJson(Map<String, dynamic> json) {
    return GitHubRepository(
      id: json['id'],
      name: json['name'],
      fullName: json['full_name'],
      htmlUrl: json['html_url'],
      description: json['description'],
      language: json['language'],
      forksCount: json['forks_count'] ?? 0,
      stargazersCount: json['stargazers_count'] ?? 0,
      openIssuesCount: json['open_issues_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

/// GitHub Pull Request
class GitHubPullRequest {
  final int number;
  final String title;
  final String body;
  final String htmlUrl;
  final String state;
  final bool merged;
  final String headRef;
  final String baseRef;
  final GitHubUser user;
  final DateTime createdAt;
  final DateTime? mergedAt;

  GitHubPullRequest({
    required this.number,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.state,
    required this.merged,
    required this.headRef,
    required this.baseRef,
    required this.user,
    required this.createdAt,
    this.mergedAt,
  });

  factory GitHubPullRequest.fromJson(Map<String, dynamic> json) {
    return GitHubPullRequest(
      number: json['number'],
      title: json['title'],
      body: json['body'] ?? '',
      htmlUrl: json['html_url'],
      state: json['state'],
      merged: json['merged'] ?? false,
      headRef: json['head']['ref'],
      baseRef: json['base']['ref'],
      user: GitHubUser.fromJson(json['user']),
      createdAt: DateTime.parse(json['created_at']),
      mergedAt: json['merged_at'] != null ? DateTime.parse(json['merged_at']) : null,
    );
  }
}

/// GitHub Issue
class GitHubIssue {
  final int number;
  final String title;
  final String body;
  final String htmlUrl;
  final String state;
  final List<String> labels;
  final GitHubUser user;
  final DateTime createdAt;
  final DateTime? closedAt;

  GitHubIssue({
    required this.number,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.state,
    required this.labels,
    required this.user,
    required this.createdAt,
    this.closedAt,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    return GitHubIssue(
      number: json['number'],
      title: json['title'],
      body: json['body'] ?? '',
      htmlUrl: json['html_url'],
      state: json['state'],
      labels: (json['labels'] as List?)?.map((l) => l is String ? l : l['name'] as String).toList() ?? [],
      user: GitHubUser.fromJson(json['user']),
      createdAt: DateTime.parse(json['created_at']),
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
    );
  }
}

/// GitHub Workflow
class GitHubWorkflow {
  final int id;
  final String name;
  final String path;
  final String state;
  final DateTime createdAt;
  final DateTime updatedAt;

  GitHubWorkflow({
    required this.id,
    required this.name,
    required this.path,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GitHubWorkflow.fromJson(Map<String, dynamic> json) {
    return GitHubWorkflow(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      state: json['state'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

/// GitHub User
class GitHubUser {
  final int id;
  final String login;
  final String htmlUrl;
  final String? avatarUrl;
  final String? name;

  GitHubUser({
    required this.id,
    required this.login,
    required this.htmlUrl,
    this.avatarUrl,
    this.name,
  });

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      id: json['id'],
      login: json['login'],
      htmlUrl: json['html_url'],
      avatarUrl: json['avatar_url'],
      name: json['name'],
    );
  }
}

/// Repository Statistics
class RepositoryStats {
  final int contributorCount;
  final int commitCount;
  final int releaseCount;
  final int openIssues;
  final int openPullRequests;

  RepositoryStats({
    required this.contributorCount,
    required this.commitCount,
    required this.releaseCount,
    required this.openIssues,
    required this.openPullRequests,
  });

  double get healthScore {
    // Calculate a simple health score based on activity
    final activityScore = (commitCount / 100).clamp(0.0, 1.0);
    final communityScore = (contributorCount / 10).clamp(0.0, 1.0);
    final maintenanceScore = releaseCount > 0 ? 1.0 : 0.5;

    return (activityScore + communityScore + maintenanceScore) / 3.0;
  }
}