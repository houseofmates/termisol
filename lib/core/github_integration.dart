import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub Integration
///
/// Provides GitHub API integration for repository management, issue
/// tracking, pull request operations, and GitHub Actions workflow
/// monitoring within the terminal.
class GitHubIntegration {
  final String? _token;
  final Map<String, GitHubRepo> _repos = {};
  final Map<String, GitHubIssue> _issues = {};
  final Map<String, GitHubPR> _prs = {};
  Timer? _syncTimer;
  String _apiBase = 'https://api.github.com';
  int _rateLimitRemaining = 5000;
  DateTime? _rateLimitReset;

  static const Duration _syncInterval = Duration(minutes: 5);

  GitHubIntegration({String? token}) : _token = token ?? Platform.environment['GITHUB_TOKEN'];

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  int get rateLimitRemaining => _rateLimitRemaining;

  Future<void> initialize() async {
    if (_token == null) {
      debugPrint('GitHubIntegration: No token found, running in limited mode');
    } else {
      final valid = await validateToken();
      if (valid) {
        _syncTimer = Timer.periodic(_syncInterval, (_) => _syncStarredRepos());
      }
    }
    await _loadCachedRepos();
    debugPrint('GitHubIntegration initialized (auth: $isAuthenticated)');
  }

  Future<bool> validateToken() async {
    if (!isAuthenticated) return false;
    try {
      final response = await _apiGet('/user');
      if (response.statusCode == 200) {
        _parseRateLimits(response);
        return true;
      }
    } catch (e) {
      debugPrint('GitHub token validation failed: $e');
    }
    return false;
  }

  Future<void> _parseRateLimits(http.Response response) async {
    try {
      _rateLimitRemaining = int.tryParse(response.headers['x-ratelimit-remaining'] ?? '5000') ?? 5000;
      final resetEpoch = int.tryParse(response.headers['x-ratelimit-reset'] ?? '0') ?? 0;
      if (resetEpoch > 0) {
        _rateLimitReset = DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000);
      }
    } catch (_) {}
  }

  Future<GitHubRepo?> getRepo(String owner, String repo) async {
    try {
      if (!isAuthenticated) return null;
      final response = await _apiGet('/repos/$owner/$repo');
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final ghRepo = GitHubRepo.fromJson(data);
      _repos[ghRepo.fullName] = ghRepo;
      return ghRepo;
    } catch (e) {
      debugPrint('Failed to get repo $owner/$repo: $e');
      return null;
    }
  }

  Future<List<GitHubRepo>> listUserRepos({int perPage = 30, String? type, String? sort}) async {
    try {
      if (!isAuthenticated) return _repos.values.toList();
      final params = <String, String>{'per_page': perPage.toString()};
      if (type != null) params['type'] = type;
      if (sort != null) params['sort'] = sort;
      final response = await _apiGet('/user/repos', queryParams: params);
      if (response.statusCode != 200) return _repos.values.toList();
      final data = json.decode(response.body) as List;
      final repos = data.map((d) => GitHubRepo.fromJson(d as Map<String, dynamic>)).toList();
      for (final repo in repos) { _repos[repo.fullName] = repo; }
      return repos;
    } catch (e) {
      debugPrint('Failed to list repos: $e');
      return [];
    }
  }

  Future<GitHubRepo?> createRepo({
    required String name,
    String? description,
    bool private = false,
    bool autoInit = false,
  }) async {
    if (!isAuthenticated) return null;
    try {
      final response = await _apiPost('/user/repos', body: json.encode({
        'name': name,
        'description': description ?? '',
        'private': private,
        'auto_init': autoInit,
      }));
      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final repo = GitHubRepo.fromJson(data);
        _repos[repo.fullName] = repo;
        return repo;
      }
    } catch (e) {
      debugPrint('Failed to create repo: $e');
    }
    return null;
  }

  Future<List<GitHubIssue>> listIssues(String owner, String repo, {String state = 'open'}) async {
    try {
      if (!isAuthenticated) return [];
      final response = await _apiGet('/repos/$owner/$repo/issues', queryParams: {'state': state});
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as List;
      return data.map((d) => GitHubIssue.fromJson(d as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Failed to list issues: $e');
      return [];
    }
  }

  Future<GitHubIssue?> createIssue(String owner, String repo, String title, {String? body, List<String>? labels}) async {
    if (!isAuthenticated) return null;
    try {
      final payload = <String, dynamic>{'title': title};
      if (body != null) payload['body'] = body;
      if (labels != null) payload['labels'] = labels;
      final response = await _apiPost('/repos/$owner/$repo/issues', body: json.encode(payload));
      if (response.statusCode == 201) {
        return GitHubIssue.fromJson(json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to create issue: $e');
    }
    return null;
  }

  Future<List<GitHubPR>> listPullRequests(String owner, String repo, {String state = 'open'}) async {
    try {
      if (!isAuthenticated) return [];
      final response = await _apiGet('/repos/$owner/$repo/pulls', queryParams: {'state': state});
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as List;
      return data.map((d) => GitHubPR.fromJson(d as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Failed to list PRs: $e');
      return [];
    }
  }

  Future<GitHubPR?> createPullRequest(
    String owner, String repo, String title, String head, String base, {String? body}) async {
    if (!isAuthenticated) return null;
    try {
      final payload = <String, dynamic>{
        'title': title, 'head': head, 'base': base,
      };
      if (body != null) payload['body'] = body;
      final response = await _apiPost('/repos/$owner/$repo/pulls', body: json.encode(payload));
      if (response.statusCode == 201) {
        return GitHubPR.fromJson(json.decode(response.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to create PR: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getUser() async {
    if (!isAuthenticated) return null;
    try {
      final response = await _apiGet('/user');
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Failed to get user: $e');
    }
    return null;
  }

  Future<List<dynamic>> listWorkflowRuns(String owner, String repo) async {
    if (!isAuthenticated) return [];
    try {
      final response = await _apiGet('/repos/$owner/$repo/actions/runs');
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['workflow_runs'] as List? ?? [];
      }
    } catch (e) {
      debugPrint('Failed to list workflow runs: $e');
    }
    return [];
  }

  Future<bool> dispatchWorkflow(String owner, String repo, String workflowId, String ref, {Map<String, dynamic>? inputs}) async {
    if (!isAuthenticated) return false;
    try {
      final response = await _apiPost('/repos/$owner/$repo/actions/workflows/$workflowId/dispatches', body: json.encode({
        'ref': ref,
        'inputs': inputs ?? {},
      }));
      return response.statusCode == 204;
    } catch (e) {
      debugPrint('Failed to dispatch workflow: $e');
      return false;
    }
  }

  Future<String> cloneRepo(String owner, String repo, String targetDir) async {
    final url = 'https://github.com/$owner/$repo.git';
    try {
      final result = await Process.run('git', ['clone', url, targetDir]);
      if (result.exitCode == 0) return targetDir;
      return '';
    } catch (e) {
      debugPrint('Failed to clone repo: $e');
      return '';
    }
  }

  Future<bool> starRepo(String owner, String repo) async {
    if (!isAuthenticated) return false;
    try {
      final response = await _apiPut('/user/starred/$owner/$repo');
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  Future<bool> unstarRepo(String owner, String repo) async {
    if (!isAuthenticated) return false;
    try {
      final response = await _apiDelete('/user/starred/$owner/$repo');
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  Future<List<GitHubRepo>> _syncStarredRepos() async {
    if (!isAuthenticated) return [];
    try {
      final response = await _apiGet('/user/starred', queryParams: {'per_page': '50'});
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as List;
      final repos = data.map((d) => GitHubRepo.fromJson(d as Map<String, dynamic>)).toList();
      for (final repo in repos) { _repos[repo.fullName] = repo; }
      await _cacheRepos();
      return repos;
    } catch (e) {
      return [];
    }
  }

  Future<void> _cacheRepos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _repos.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString('github_cached_repos', json.encode(data));
    } catch (_) {}
  }

  Future<void> _loadCachedRepos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('github_cached_repos');
      if (data != null) {
        final decoded = json.decode(data) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _repos[entry.key] = GitHubRepo.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (_) {}
  }

  Future<http.Response> _apiGet(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$_apiBase$path').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _defaultHeaders());
    _parseRateLimits(response);
    return response;
  }

  Future<http.Response> _apiPost(String path, {String? body}) async {
    final uri = Uri.parse('$_apiBase$path');
    return http.post(uri, headers: _defaultHeaders(), body: body);
  }

  Future<http.Response> _apiPut(String path) async {
    final uri = Uri.parse('$_apiBase$path');
    return http.put(uri, headers: _defaultHeaders());
  }

  Future<http.Response> _apiDelete(String path) async {
    final uri = Uri.parse('$_apiBase$path');
    return http.delete(uri, headers: _defaultHeaders());
  }

  dynamic _createClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }

  Map<String, String> _defaultHeaders() => {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Termisol/1.0',
    if (_token != null) 'Authorization': 'token $_token',
  };

  void dispose() {
    _syncTimer?.cancel();
    _repos.clear();
    _issues.clear();
    _prs.clear();
  }
}

class GitHubRepo {
  final int id;
  final String name;
  final String fullName;
  final String? description;
  final bool private;
  final int stargazersCount;
  final int forksCount;
  final String? language;
  final String? cloneUrl;
  final String? htmlUrl;
  final DateTime updatedAt;

  GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    this.description,
    this.private = false,
    this.stargazersCount = 0,
    this.forksCount = 0,
    this.language,
    this.cloneUrl,
    this.htmlUrl,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'fullName': fullName, 'description': description,
    'private': private, 'stargazersCount': stargazersCount, 'forksCount': forksCount,
    'language': language, 'cloneUrl': cloneUrl, 'htmlUrl': htmlUrl,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      id: json['id'] as int,
      name: json['name'] as String,
      fullName: json['full_name'] as String,
      description: json['description'] as String?,
      private: json['private'] as bool? ?? false,
      stargazersCount: json['stargazers_count'] as int? ?? 0,
      forksCount: json['forks_count'] as int? ?? 0,
      language: json['language'] as String?,
      cloneUrl: json['clone_url'] as String?,
      htmlUrl: json['html_url'] as String?,
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class GitHubIssue {
  final int number;
  final String title;
  final String? body;
  final String state;
  final String? assignee;
  final List<String> labels;
  final DateTime createdAt;

  GitHubIssue({
    required this.number,
    required this.title,
    this.body,
    required this.state,
    this.assignee,
    this.labels = const [],
    required this.createdAt,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    return GitHubIssue(
      number: json['number'] as int,
      title: json['title'] as String,
      body: json['body'] as String?,
      state: json['state'] as String,
      assignee: (json['assignee'] as Map<String, dynamic>?)?['login'] as String?,
      labels: (json['labels'] as List?)?.map((l) => (l as Map<String, dynamic>)['name'] as String).toList() ?? [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class GitHubPR {
  final int number;
  final String title;
  final String? body;
  final String state;
  final String headRef;
  final String baseRef;
  final String? author;
  final DateTime createdAt;

  GitHubPR({
    required this.number,
    required this.title,
    this.body,
    required this.state,
    required this.headRef,
    required this.baseRef,
    this.author,
    required this.createdAt,
  });

  factory GitHubPR.fromJson(Map<String, dynamic> json) {
    return GitHubPR(
      number: json['number'] as int,
      title: json['title'] as String,
      body: json['body'] as String?,
      state: json['state'] as String,
      headRef: json['head']?['ref'] as String? ?? '',
      baseRef: json['base']?['ref'] as String? ?? '',
      author: json['user']?['login'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}