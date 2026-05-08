import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class GitIntegration {
  static const String _gitDir = '.git';
  static const int _maxCommitHistory = 100;
  static const int _maxBranches = 50;
  static const int _maxRemotes = 20;
  
  final Map<String, GitRepository> _repositories = {};
  final Map<String, List<GitCommit>> _commitHistory = {};
  final Map<String, List<GitBranch>> _branches = {};
  final Map<String, List<GitRemote>> _remotes = {};
  final Map<String, GitStatus> _status = {};
  
  String? _currentRepo;
  int _totalOperations = 0;
  
  final StreamController<GitEvent> _gitController = 
      StreamController<GitEvent>.broadcast();

  void initialize() {
    _scanForRepositories();
    developer.log('🔀 Git Integration initialized');
  }

  void _scanForRepositories() {
    final currentDir = Directory.current;
    final repo = _findRepository(currentDir);
    
    if (repo != null) {
      _currentRepo = repo.path;
      _repositories[repo.path] = repo;
      _loadRepositoryData(repo);
      
      developer.log('🔀 Found Git repository: ${repo.path}');
      
      _emitEvent(GitEvent(
        type: GitEventType.repositoryFound,
        repository: repo,
      ));
    }
  }

  GitRepository? _findRepository(Directory dir) {
    Directory? currentDir = dir;
    
    while (currentDir != null) {
      final gitDir = Directory('${currentDir.path}/$_gitDir');
      
      if (gitDir.existsSync()) {
        return GitRepository(
          path: currentDir.path,
          gitDir: gitDir.path,
          name: path.basename(currentDir.path),
        );
      }
      
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) {
        break; // Reached root directory
      }
      
      currentDir = parent;
    }
    
    return null;
  }

  Future<void> _loadRepositoryData(GitRepository repository) async {
    try {
      // Load commit history
      await _loadCommitHistory(repository);
      
      // Load branches
      await _loadBranches(repository);
      
      // Load remotes
      await _loadRemotes(repository);
      
      // Load status
      await _loadStatus(repository);
      
    } catch (e) {
      developer.log('🔀 Failed to load repository data: $e');
    }
  }

  Future<void> _loadCommitHistory(GitRepository repository) async {
    try {
      final result = await _executeGitCommand(['log', '--oneline', '-n', '$_maxCommitHistory'], repository.path);
      final lines = result.split('\n');
      
      final commits = <GitCommit>[];
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split(' ');
        if (parts.length >= 2) {
          final hash = parts[0];
          final message = parts.sublist(1).join(' ');
          
          commits.add(GitCommit(
            hash: hash,
            message: message,
            author: '',
            date: DateTime.now(),
            files: [],
          ));
        }
      }
      
      _commitHistory[repository.path] = commits;
      
      developer.log('🔀 Loaded ${commits.length} commits for ${repository.name}');
      
    } catch (e) {
      developer.log('🔀 Failed to load commit history: $e');
    }
  }

  Future<void> _loadBranches(GitRepository repository) async {
    try {
      final result = await _executeGitCommand(['branch', '-a'], repository.path);
      final lines = result.split('\n');
      
      final branches = <GitBranch>[];
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final isCurrent = line.startsWith('*');
        final name = line.substring(isCurrent ? 2 : 2).trim();
        
        branches.add(GitBranch(
          name: name,
          isCurrent: isCurrent,
          isRemote: false,
        ));
      }
      
      _branches[repository.path] = branches;
      
      developer.log('🔀 Loaded ${branches.length} branches for ${repository.name}');
      
    } catch (e) {
      developer.log('🔀 Failed to load branches: $e');
    }
  }

  Future<void> _loadRemotes(GitRepository repository) async {
    try {
      final result = await _executeGitCommand(['remote', '-v'], repository.path);
      final lines = result.split('\n');
      
      final remotes = <GitRemote>[];
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final name = parts[0];
          final url = parts[1];
          
          remotes.add(GitRemote(
            name: name,
            url: url,
            type: _detectRemoteType(url),
          ));
        }
      }
      
      _remotes[repository.path] = remotes;
      
      developer.log('🔀 Loaded ${remotes.length} remotes for ${repository.name}');
      
    } catch (e) {
      developer.log('🔀 Failed to load remotes: $e');
    }
  }

  RemoteType _detectRemoteType(String url) {
    if (url.startsWith('https://github.com/')) {
      return RemoteType.github;
    } else if (url.startsWith('git@github.com:')) {
      return RemoteType.github;
    } else if (url.startsWith('https://gitlab.com/')) {
      return RemoteType.gitlab;
    } else if (url.startsWith('git@gitlab.com:')) {
      return RemoteType.gitlab;
    } else if (url.startsWith('https://bitbucket.org/')) {
      return RemoteType.bitbucket;
    } else if (url.startsWith('git@bitbucket.org:')) {
      return RemoteType.bitbucket;
    } else {
      return RemoteType.other;
    }
  }

  Future<void> _loadStatus(GitRepository repository) async {
    try {
      final result = await _executeGitCommand(['status', '--porcelain'], repository.path);
      final lines = result.split('\n');
      
      final status = GitStatus(
        modified: [],
        added: [],
        deleted: [],
        untracked: [],
        renamed: [],
        conflicted: [],
        isClean: true,
      );
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final statusCode = line.substring(0, 2);
        final filePath = line.substring(3);
        
        switch (statusCode) {
          case ' M':
            status.modified.add(filePath);
            status.isClean = false;
            break;
          case 'A ':
            status.added.add(filePath);
            status.isClean = false;
            break;
          case 'D ':
            status.deleted.add(filePath);
            status.isClean = false;
            break;
          case '??':
            status.untracked.add(filePath);
            status.isClean = false;
            break;
          case 'R ':
            status.renamed.add(filePath);
            status.isClean = false;
            break;
          case 'UU':
          case 'AA':
          case 'DD':
            status.conflicted.add(filePath);
            status.isClean = false;
            break;
        }
      }
      
      _status[repository.path] = status;
      
      developer.log('🔀 Loaded status for ${repository.name}: ${status.isClean ? 'clean' : 'dirty'}');
      
    } catch (e) {
      developer.log('🔀 Failed to load status: $e');
    }
  }

  Future<String> _executeGitCommand(List<String> args, String workingDir) async {
    final process = await Process.start('git', args, workingDirectory: workingDir);
    
    final result = await process.stdout.transform(utf8.decoder).join();
    final error = await process.stderr.transform(utf8.decoder).join();
    
    final exitCode = await process.exitCode;
    
    if (exitCode != 0) {
      throw Exception('Git command failed: $error');
    }
    
    return result;
  }

  Future<bool> isGitRepository(String path) async {
    final repo = _findRepository(Directory(path));
    return repo != null;
  }

  Future<void> initRepository(String path) async {
    try {
      await _executeGitCommand(['init'], path);
      
      final repository = GitRepository(
        path: path,
        gitDir: '$path/$_gitDir',
        name: path.basename(path),
      );
      
      _repositories[path] = repository;
      _currentRepo = path;
      
      await _loadRepositoryData(repository);
      
      developer.log('🔀 Initialized repository: $path');
      
      _emitEvent(GitEvent(
        type: GitEventType.repositoryInitialized,
        repository: repository,
      ));
      
    } catch (e) {
      developer.log('🔀 Failed to initialize repository: $e');
      rethrow;
    }
  }

  Future<void> addFiles(List<String> files, {String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = ['add']..addAll(files);
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Added ${files.length} files to repository');
      
      _emitEvent(GitEvent(
        type: GitEventType.filesAdded,
        repositoryPath: repoPath,
        files: files,
      ));
      
      // Refresh status
      await _loadStatus(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to add files: $e');
      rethrow;
    }
  }

  Future<void> commit(String message, {List<String>? files, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      // Add files if specified
      if (files != null && files!.isNotEmpty) {
        await addFiles(files!, repositoryPath: repoPath);
      }
      
      await _executeGitCommand(['commit', '-m', message], repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Committed changes: $message');
      
      _emitEvent(GitEvent(
        type: GitEventType.committed,
        repositoryPath: repoPath,
        message: message,
        files: files,
      ));
      
      // Refresh data
      await _loadRepositoryData(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to commit: $e');
      rethrow;
    }
  }

  Future<void> push(String? remote, String? branch, {String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      String remoteName = remote ?? 'origin';
      String branchName = branch ?? 'main';
      
      final args = ['push', '$remoteName/$branchName'];
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Pushed to $remoteName/$branchName');
      
      _emitEvent(GitEvent(
        type: GitEventType.pushed,
        repositoryPath: repoPath,
        remote: remoteName,
        branch: branchName,
      ));
      
    } catch (e) {
      developer.log('🔀 Failed to push: $e');
      rethrow;
    }
  }

  Future<void> pull(String? remote, String? branch, {String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      String remoteName = remote ?? 'origin';
      String branchName = branch ?? 'main';
      
      final args = ['pull', '$remoteName/$branchName'];
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Pulled from $remoteName/$branchName');
      
      _emitEvent(GitEvent(
        type: GitEventType.pulled,
        repositoryPath: repoPath,
        remote: remoteName,
        branch: branchName,
      ));
      
      // Refresh data
      await _loadRepositoryData(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to pull: $e');
      rethrow;
    }
  }

  Future<void> checkout(String branch, {String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      await _executeGitCommand(['checkout', branch], repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Checked out branch: $branch');
      
      _emitEvent(GitEvent(
        type: GitEventType.checkedOut,
        repositoryPath: repoPath,
        branch: branch,
      ));
      
      // Refresh data
      await _loadRepositoryData(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to checkout: $e');
      rethrow;
    }
  }

  Future<void> createBranch(String branchName, {String? baseBranch, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = baseBranch != null 
          ? ['branch', branchName, baseBranch]
          : ['branch', branchName];
      
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Created branch: $branchName');
      
      _emitEvent(GitEvent(
        type: GitEventType.branchCreated,
        repositoryPath: repoPath,
        branch: branchName,
        baseBranch: baseBranch,
      ));
      
      // Refresh branches
      await _loadBranches(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to create branch: $e');
      rethrow;
    }
  }

  Future<void> deleteBranch(String branchName, {bool force = false, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = force 
          ? ['branch', '-D', branchName]
          : ['branch', '-d', branchName];
      
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Deleted branch: $branchName');
      
      _emitEvent(GitEvent(
        type: GitEventType.branchDeleted,
        repositoryPath: repoPath,
        branch: branchName,
        force: force,
      ));
      
      // Refresh branches
      await _loadBranches(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to delete branch: $e');
      rethrow;
    }
  }

  Future<void> merge(String branchName, {String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      await _executeGitCommand(['merge', branchName], repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Merged branch: $branchName');
      
      _emitEvent(GitEvent(
        type: GitEventType.merged,
        repositoryPath: repoPath,
        branch: branchName,
      ));
      
      // Refresh data
      await _loadRepositoryData(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to merge: $e');
      rethrow;
    }
  }

  Future<void> stash({String? message, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = message != null 
          ? ['stash', 'push', '-m', message]
          : ['stash'];
      
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Stashed changes${message != null ? ': $message' : ''}');
      
      _emitEvent(GitEvent(
        type: GitEventType.stashed,
        repositoryPath: repoPath,
        message: message,
      ));
      
      // Refresh status
      await _loadStatus(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to stash: $e');
      rethrow;
    }
  }

  Future<void> stashPop({String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      await _executeGitCommand(['stash', 'pop'], repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Popped stashed changes');
      
      _emitEvent(GitEvent(
        type: GitEventType.stashPopped,
        repositoryPath: repoPath,
      ));
      
      // Refresh status
      await _loadStatus(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to pop stash: $e');
      rethrow;
    }
  }

  Future<void> reset(String commit, {bool hard = false, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = hard 
          ? ['reset', '--hard', commit]
          : ['reset', commit];
      
      await _executeGitCommand(args, repoPath);
      
      _totalOperations++;
      
      developer.log('🔀 Reset to ${hard ? 'hard' : 'soft'}: $commit');
      
      _emitEvent(GitEvent(
        type: GitEventType.reset,
        repositoryPath: repoPath,
        commit: commit,
        hard: hard,
      ));
      
      // Refresh data
      await _loadRepositoryData(_repositories[repoPath]!);
      
    } catch (e) {
      developer.log('🔀 Failed to reset: $e');
      rethrow;
    }
  }

  GitRepository? getCurrentRepository() {
    if (_currentRepo == null) return null;
    return _repositories[_currentRepo!];
  }

  List<GitCommit> getCommitHistory({String? repositoryPath}) {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) return [];
    return _commitHistory[repoPath] ?? [];
  }

  List<GitBranch> getBranches({String? repositoryPath}) {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) return [];
    return _branches[repoPath] ?? [];
  }

  List<GitRemote> getRemotes({String? repositoryPath}) {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) return [];
    return _remotes[repoPath] ?? [];
  }

  GitStatus? getStatus({String? repositoryPath}) {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) return null;
    return _status[repoPath];
  }

  Future<String> getDiff({String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      return await _executeGitCommand(['diff'], repoPath);
    } catch (e) {
      developer.log('🔀 Failed to get diff: $e');
      rethrow;
    }
  }

  Future<String> getLog({int? limit, String? repositoryPath}) async {
    final repoPath = repositoryPath ?? _currentRepo;
    if (repoPath == null) {
      throw Exception('No repository selected');
    }
    
    try {
      final args = ['log', '--oneline'];
      if (limit != null) {
        args.addAll(['-n', limit.toString()]);
      }
      
      return await _executeGitCommand(args, repoPath);
    } catch (e) {
      developer.log('🔀 Failed to get log: $e');
      rethrow;
    }
  }

  void _emitEvent(GitEvent event) {
    _gitController.add(event);
  }

  Stream<GitEvent> get gitEventStream => _gitController.stream;

  GitIntegrationStats getStats() {
    return GitIntegrationStats(
      totalRepositories: _repositories.length,
      currentRepository: _currentRepo,
      totalOperations: _totalOperations,
      totalCommits: _commitHistory.values
          .fold(0, (sum, commits) => sum + commits.length),
      totalBranches: _branches.values
          .fold(0, (sum, branches) => sum + branches.length),
      totalRemotes: _remotes.values
          .fold(0, (sum, remotes) => sum + remotes.length),
    );
  }

  void dispose() {
    _repositories.clear();
    _commitHistory.clear();
    _branches.clear();
    _remotes.clear();
    _status.clear();
    _gitController.close();
    
    developer.log('🔀 Git Integration disposed');
  }
}

class GitRepository {
  final String path;
  final String gitDir;
  final String name;

  GitRepository({
    required this.path,
    required this.gitDir,
    required this.name,
  });
}

class GitCommit {
  final String hash;
  final String message;
  final String author;
  final DateTime date;
  final List<String> files;

  GitCommit({
    required this.hash,
    required this.message,
    required this.author,
    required this.date,
    required this.files,
  });
}

class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;

  GitBranch({
    required this.name,
    required this.isCurrent,
    required this.isRemote,
  });
}

class GitRemote {
  final String name;
  final String url;
  final RemoteType type;

  GitRemote({
    required this.name,
    required this.url,
    required this.type,
  });
}

class GitStatus {
  final List<String> modified;
  final List<String> added;
  final List<String> deleted;
  final List<String> untracked;
  final List<String> renamed;
  final List<String> conflicted;
  final bool isClean;

  GitStatus({
    required this.modified,
    required this.added,
    required this.deleted,
    required this.untracked,
    required this.renamed,
    required this.conflicted,
    required this.isClean,
  });
}

enum GitEventType {
  repositoryFound,
  repositoryInitialized,
  filesAdded,
  committed,
  pushed,
  pulled,
  checkedOut,
  branchCreated,
  branchDeleted,
  merged,
  stashed,
  stashPopped,
  reset,
}

enum RemoteType {
  github,
  gitlab,
  bitbucket,
  other,
}

class GitEvent {
  final GitEventType type;
  final GitRepository? repository;
  final String? repositoryPath;
  final String? branch;
  final String? baseBranch;
  final String? remote;
  final List<String>? files;
  final String? message;
  final String? commit;
  final bool? force;
  final bool? hard;

  GitEvent({
    required this.type,
    this.repository,
    this.repositoryPath,
    this.branch,
    this.baseBranch,
    this.remote,
    this.files,
    this.message,
    this.commit,
    this.force,
    this.hard,
  });
}

class GitIntegrationStats {
  final int totalRepositories;
  final String? currentRepository;
  final int totalOperations;
  final int totalCommits;
  final int totalBranches;
  final int totalRemotes;

  GitIntegrationStats({
    required this.totalRepositories,
    this.currentRepository,
    required this.totalOperations,
    required this.totalCommits,
    required this.totalBranches,
    required this.totalRemotes,
  });
}
