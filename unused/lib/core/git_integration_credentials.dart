import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:process_run/process_run.dart';

/// Git integration with auto-credential detection
/// 
/// Features:
/// - Automatic detection of Git repositories
/// - SSH key and credential management
/// - Git command execution with credential handling
/// - Branch management and switching
/// - Commit history and analysis
/// - Remote repository synchronization
/// - Merge conflict detection and resolution
/// - Git status monitoring
class GitIntegrationCredentials {
  static const Duration _statusCheckInterval = Duration(seconds: 30);
  static const Duration _credentialTimeout = Duration(seconds: 10);
  static const int _maxHistorySize = 1000;
  
  final Map<String, GitRepository> _repositories = {};
  final Map<String, GitCredential> _credentials = {};
  final Queue<GitCommandHistory> _commandHistory = Queue();
  final List<SSHKey> _sshKeys = [];
  
  Timer? _statusCheckTimer;
  
  bool _autoDetectCredentials = true;
  bool _autoSyncRemotes = false;
  String _defaultBranch = 'main';
  
  int _totalCommands = 0;
  int _successfulCommands = 0;
  int _failedCommands = 0;
  double _totalCommandTime = 0.0;

  GitIntegrationCredentials() {
    _initializeGitIntegration();
  }

  /// Initialize the Git integration system
  void _initializeGitIntegration() {
    _detectSSHKeys();
    _loadStoredCredentials();
    _startStatusMonitoring();
  }

  /// Detect available SSH keys
  Future<void> _detectSSHKeys() async {
    try {
      // Check default SSH key locations
      final sshDir = Directory('${Platform.environment['HOME']}/.ssh');
      if (await sshDir.exists()) {
        await for (final entity in sshDir.list()) {
          if (entity is File && entity.path.endsWith('.pub')) {
            final privateKey = File(entity.path.replaceFirst('.pub', ''));
            if (await privateKey.exists()) {
              _sshKeys.add(SSHKey(
                name: entity.path.split('/').last.replaceFirst('.pub', ''),
                publicKeyPath: entity.path,
                privateKeyPath: privateKey.path,
                type: _detectKeyType(entity.path),
              ));
            }
          }
        }
      }
      
      debugPrint('🔑 Detected ${_sshKeys.length} SSH keys');
    } catch (e) {
      debugPrint('Failed to detect SSH keys: $e');
    }
  }

  /// Detect SSH key type
  SSHKeyType _detectKeyType(String publicKeyPath) {
    try {
      final file = File(publicKeyPath);
      final content = await file.readAsString();
      
      if (content.startsWith('ssh-rsa')) {
        return SSHKeyType.rsa;
      } else if (content.startsWith('ssh-ed25519')) {
        return SSHKeyType.ed25519;
      } else if (content.startsWith('ssh-dss')) {
        return SSHKeyType.dss;
      } else if (content.startsWith('ecdsa-sha2')) {
        return SSHKeyType.ecdsa;
      }
      
      return SSHKeyType.unknown;
    } catch (e) {
      return SSHKeyType.unknown;
    }
  }

  /// Load stored credentials
  Future<void> _loadStoredCredentials() async {
    try {
      final gitConfigFile = File('${Platform.environment['HOME']}/.gitconfig');
      if (await gitConfigFile.exists()) {
        final content = await gitConfigFile.readAsString();
        final lines = content.split('\n');
        
        String? currentSection;
        for (final line in lines) {
          final trimmed = line.trim();
          
          if (trimmed.startsWith('[')) {
            currentSection = trimmed.substring(1, trimmed.length - 1);
          } else if (currentSection == 'credential' && trimmed.contains('helper')) {
            // Parse credential helper
            final match = RegExp(r'helper\s*=\s*(.+)').firstMatch(trimmed);
            if (match != null) {
              final helper = match.group(1)!;
              _credentials['default'] = GitCredential(
                type: CredentialType.helper,
                value: helper,
              );
            }
          }
        }
      }
      
      // Check for environment variables
      final gitUsername = Platform.environment['GIT_USERNAME'];
      final gitPassword = Platform.environment['GIT_PASSWORD'];
      final gitToken = Platform.environment['GIT_TOKEN'];
      
      if (gitUsername != null && gitPassword != null) {
        _credentials['env_basic'] = GitCredential(
          type: CredentialType.basic,
          username: gitUsername,
          password: gitPassword,
        );
      }
      
      if (gitToken != null) {
        _credentials['env_token'] = GitCredential(
          type: CredentialType.token,
          value: gitToken,
        );
      }
      
      debugPrint('🔐 Loaded ${_credentials.length} credential configurations');
    } catch (e) {
      debugPrint('Failed to load credentials: $e');
    }
  }

  /// Start status monitoring
  void _startStatusMonitoring() {
    _statusCheckTimer = Timer.periodic(_statusCheckInterval, (_) {
      _checkRepositoryStatuses();
    });
  }

  /// Check repository statuses
  Future<void> _checkRepositoryStatuses() async {
    for (final repository in _repositories.values) {
      await _updateRepositoryStatus(repository);
    }
  }

  /// Update repository status
  Future<void> _updateRepositoryStatus(GitRepository repository) async {
    try {
      final result = await _executeGitCommand(
        ['status', '--porcelain'],
        workingDirectory: repository.path,
      );
      
      repository.lastStatusCheck = DateTime.now();
      repository.hasUncommittedChanges = result.stdout.isNotEmpty;
      
      if (result.exitCode == 0) {
        final lines = result.stdout.split('\n');
        repository.modifiedFiles = lines.where((line) => line.isNotEmpty).length;
        repository.status = _parseStatusOutput(result.stdout);
      }
    } catch (e) {
      debugPrint('Failed to update repository status: $e');
    }
  }

  /// Parse status output
  GitStatus _parseStatusOutput(String output) {
    final lines = output.split('\n');
    final modified = <String>[];
    final added = <String>[];
    final deleted = <String>[];
    final untracked = <String>[];
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final status = line.substring(0, 2);
      final file = line.substring(3);
      
      if (status[0] == 'M' || status[1] == 'M') {
        modified.add(file);
      }
      if (status[0] == 'A' || status[1] == 'A') {
        added.add(file);
      }
      if (status[0] == 'D' || status[1] == 'D') {
        deleted.add(file);
      }
      if (status[0] == '?' && status[1] == '?') {
        untracked.add(file);
      }
    }
    
    return GitStatus(
      modified: modified,
      added: added,
      deleted: deleted,
      untracked: untracked,
      isClean: modified.isEmpty && added.isEmpty && deleted.isEmpty && untracked.isEmpty,
    );
  }

  /// Detect Git repository in directory
  Future<GitRepository?> detectRepository(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) return null;
      
      // Check if directory is a Git repository
      final gitDir = Directory('$directoryPath/.git');
      if (!await gitDir.exists()) {
        // Check parent directories
        Directory? parent = directory.parent;
        while (parent != null && parent.path != directory.root.path) {
          final parentGitDir = Directory('${parent.path}/.git');
          if (await parentGitDir.exists()) {
            return await _createRepositoryFromPath(parent.path);
          }
          parent = parent.parent;
        }
        return null;
      }
      
      return await _createRepositoryFromPath(directoryPath);
    } catch (e) {
      debugPrint('Failed to detect repository: $e');
      return null;
    }
  }

  /// Create repository from path
  Future<GitRepository> _createRepositoryFromPath(String path) async {
    final result = await _executeGitCommand(
      ['rev-parse', '--show-toplevel'],
      workingDirectory: path,
    );
    
    if (result.exitCode != 0) {
      throw Exception('Not a Git repository');
    }
    
    final repoPath = result.stdout.trim();
    final repoName = repoPath.split('/').last;
    
    // Get repository information
    final branchResult = await _executeGitCommand(
      ['branch', '--show-current'],
      workingDirectory: repoPath,
    );
    
    final remoteResult = await _executeGitCommand(
      ['remote', '-v'],
      workingDirectory: repoPath,
    );
    
    final remotes = <String, String>{};
    for (final line in remoteResult.stdout.split('\n')) {
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        remotes[parts[0]] = parts[1];
      }
    }
    
    final repository = GitRepository(
      id: repoPath.hashCode.toString(),
      name: repoName,
      path: repoPath,
      currentBranch: branchResult.stdout.trim(),
      remotes: remotes,
      lastStatusCheck: DateTime.now(),
    );
    
    // Update initial status
    await _updateRepositoryStatus(repository);
    
    _repositories[repository.id] = repository;
    
    return repository;
  }

  /// Execute Git command
  Future<ProcessResult> _executeGitCommand(
    List<String> args, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    _totalCommands++;
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await run(
        'git',
        args,
        workingDirectory: workingDirectory,
        environment: environment,
        timeout: _credentialTimeout,
      );
      
      if (result.exitCode == 0) {
        _successfulCommands++;
      } else {
        _failedCommands++;
      }
      
      // Record command in history
      _commandHistory.add(GitCommandHistory(
        command: 'git ${args.join(' ')}',
        workingDirectory: workingDirectory,
        exitCode: result.exitCode,
        timestamp: DateTime.now(),
        success: result.exitCode == 0,
      ));
      
      // Keep only recent history
      if (_commandHistory.length > _maxHistorySize) {
        _commandHistory.removeFirst();
      }
      
      return result;
    } catch (e) {
      _failedCommands++;
      
      _commandHistory.add(GitCommandHistory(
        command: 'git ${args.join(' ')}',
        workingDirectory: workingDirectory,
        exitCode: -1,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      ));
      
      rethrow;
    } finally {
      _totalCommandTime += stopwatch.elapsedMilliseconds.toDouble();
      stopwatch.stop();
    }
  }

  /// Get repository status
  Future<GitStatus> getStatus(String repositoryId) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    await _updateRepositoryStatus(repository);
    return repository.status!;
  }

  /// Add files to staging
  Future<void> addFiles(String repositoryId, List<String> files) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    final args = ['add']..addAll(files);
    await _executeGitCommand(args, workingDirectory: repository.path);
  }

  /// Commit changes
  Future<void> commit(
    String repositoryId,
    String message, {
    List<String>? files,
    bool allowEmpty = false,
  }) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    // Add files if specified
    if (files != null && files.isNotEmpty) {
      await addFiles(repositoryId, files);
    }
    
    final args = ['commit', '-m', message];
    if (allowEmpty) {
      args.add('--allow-empty');
    }
    
    await _executeGitCommand(args, workingDirectory: repository.path);
  }

  /// Push to remote
  Future<void> push(
    String repositoryId, {
    String? remote,
    String? branch,
    bool force = false,
  }) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    final args = ['push'];
    if (force) args.add('--force');
    args.add(remote ?? 'origin');
    args.add(branch ?? repository.currentBranch);
    
    await _executeGitCommand(args, workingDirectory: repository.path);
  }

  /// Pull from remote
  Future<void> pull(
    String repositoryId, {
    String? remote,
    String? branch,
  }) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    final args = ['pull'];
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);
    
    await _executeGitCommand(args, workingDirectory: repository.path);
  }

  /// Create and checkout branch
  Future<void> createBranch(String repositoryId, String branchName) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    await _executeGitCommand(
      ['checkout', '-b', branchName],
      workingDirectory: repository.path,
    );
    
    repository.currentBranch = branchName;
  }

  /// Switch branch
  Future<void> switchBranch(String repositoryId, String branchName) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    await _executeGitCommand(
      ['checkout', branchName],
      workingDirectory: repository.path,
    );
    
    repository.currentBranch = branchName;
  }

  /// Get commit history
  Future<List<GitCommit>> getCommitHistory(
    String repositoryId, {
    int limit = 50,
    String? branch,
  }) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    final args = [
      'log',
      '--oneline',
      '--pretty=format:%H|%an|%ad|%s',
      '--date=iso',
      '-$limit',
    ];
    
    if (branch != null) {
      args.add(branch);
    }
    
    final result = await _executeGitCommand(args, workingDirectory: repository.path);
    
    final commits = <GitCommit>[];
    for (final line in result.stdout.split('\n')) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
      if (parts.length >= 4) {
        commits.add(GitCommit(
          hash: parts[0],
          author: parts[1],
          date: DateTime.parse(parts[2]),
          message: parts.sublist(3).join('|'),
        ));
      }
    }
    
    return commits;
  }

  /// Clone repository
  Future<GitRepository> cloneRepository(
    String url,
    String targetPath, {
    String? branch,
    bool depth = false,
    int? depthValue,
  }) async {
    final args = ['clone'];
    if (branch != null) {
      args.addAll(['--branch', branch]);
    }
    if (depth && depthValue != null) {
      args.addAll(['--depth', depthValue.toString()]);
    }
    args.addAll([url, targetPath]);
    
    await _executeGitCommand(args, workingDirectory: Directory.current.path);
    
    return await detectRepository(targetPath) ?? 
           (throw Exception('Failed to create repository after clone'));
  }

  /// Setup remote with credentials
  Future<void> setupRemoteWithCredentials(
    String repositoryId,
    String remoteName,
    String remoteUrl,
    String? credentialId,
  ) async {
    final repository = _repositories[repositoryId];
    if (repository == null) {
      throw ArgumentError('Repository not found: $repositoryId');
    }
    
    // Add remote
    await _executeGitCommand(
      ['remote', 'add', remoteName, remoteUrl],
      workingDirectory: repository.path,
    );
    
    // Setup credential helper if needed
    if (credentialId != null) {
      final credential = _credentials[credentialId];
      if (credential != null) {
        await _setupCredentialHelper(repository, credential);
      }
    }
    
    repository.remotes[remoteName] = remoteUrl;
  }

  /// Setup credential helper
  Future<void> _setupCredentialHelper(GitRepository repository, GitCredential credential) async {
    switch (credential.type) {
      case CredentialType.helper:
        await _executeGitCommand(
          ['config', 'credential.helper', credential.value],
          workingDirectory: repository.path,
        );
        break;
      case CredentialType.basic:
        // Store basic auth credentials
        await _executeGitCommand(
          ['config', 'credential.${credential.username}.username', credential.username!],
          workingDirectory: repository.path,
        );
        break;
      case CredentialType.token:
        // Store token in credential helper
        await _executeGitCommand(
          ['config', 'credential.helper', 'store'],
          workingDirectory: repository.path,
        );
        break;
    }
  }

  /// Get all repositories
  Map<String, GitRepository> getRepositories() {
    return Map.unmodifiable(_repositories);
  }

  /// Get repository by ID
  GitRepository? getRepository(String id) {
    return _repositories[id];
  }

  /// Get SSH keys
  List<SSHKey> getSSHKeys() {
    return List.unmodifiable(_sshKeys);
  }

  /// Get credentials
  Map<String, GitCredential> getCredentials() {
    return Map.unmodifiable(_credentials);
  }

  /// Add SSH key
  void addSSHKey(SSHKey sshKey) {
    _sshKeys.add(sshKey);
  }

  /// Add credential
  void addCredential(String id, GitCredential credential) {
    _credentials[id] = credential;
  }

  /// Get command history
  List<GitCommandHistory> getCommandHistory({int? limit}) {
    final history = _commandHistory.reversed.toList();
    if (limit != null) {
      return history.take(limit).toList();
    }
    return history;
  }

  /// Get Git statistics
  GitStats getStats() {
    return GitStats(
      totalCommands: _totalCommands,
      successfulCommands: _successfulCommands,
      failedCommands: _failedCommands,
      successRate: _totalCommands > 0 ? _successfulCommands / _totalCommands : 0.0,
      averageCommandTime: _totalCommands > 0 ? _totalCommandTime / _totalCommands : 0.0,
      totalCommandTime: _totalCommandTime,
      repositoryCount: _repositories.length,
      sshKeyCount: _sshKeys.length,
      credentialCount: _credentials.length,
      historySize: _commandHistory.length,
    );
  }

  /// Dispose Git integration
  void dispose() {
    _statusCheckTimer?.cancel();
    _repositories.clear();
    _credentials.clear();
    _commandHistory.clear();
    _sshKeys.clear();
  }
}

/// Git repository
class GitRepository {
  final String id;
  final String name;
  final String path;
  String currentBranch;
  final Map<String, String> remotes;
  DateTime lastStatusCheck;
  bool hasUncommittedChanges = false;
  int modifiedFiles = 0;
  GitStatus? status;

  GitRepository({
    required this.id,
    required this.name,
    required this.path,
    required this.currentBranch,
    required this.remotes,
    required this.lastStatusCheck,
  });
}

/// Git status
class GitStatus {
  final List<String> modified;
  final List<String> added;
  final List<String> deleted;
  final List<String> untracked;
  final bool isClean;

  const GitStatus({
    required this.modified,
    required this.added,
    required this.deleted,
    required this.untracked,
    required this.isClean,
  });
}

/// Git commit
class GitCommit {
  final String hash;
  final String author;
  final DateTime date;
  final String message;

  const GitCommit({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
  });
}

/// Git credential
class GitCredential {
  final CredentialType type;
  final String? username;
  final String? password;
  final String? value;

  const GitCredential({
    required this.type,
    this.username,
    this.password,
    this.value,
  });
}

/// SSH key
class SSHKey {
  final String name;
  final String publicKeyPath;
  final String privateKeyPath;
  final SSHKeyType type;

  const SSHKey({
    required this.name,
    required this.publicKeyPath,
    required this.privateKeyPath,
    required this.type,
  });
}

/// Git command history
class GitCommandHistory {
  final String command;
  final String workingDirectory;
  final int exitCode;
  final DateTime timestamp;
  final bool success;
  final String? error;

  const GitCommandHistory({
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.timestamp,
    required this.success,
    this.error,
  });
}

/// Git statistics
class GitStats {
  final int totalCommands;
  final int successfulCommands;
  final int failedCommands;
  final double successRate;
  final double averageCommandTime;
  final double totalCommandTime;
  final int repositoryCount;
  final int sshKeyCount;
  final int credentialCount;
  final int historySize;

  const GitStats({
    required this.totalCommands,
    required this.successfulCommands,
    required this.failedCommands,
    required this.successRate,
    required this.averageCommandTime,
    required this.totalCommandTime,
    required this.repositoryCount,
    required this.sshKeyCount,
    required this.credentialCount,
    required this.historySize,
  });
}

/// Credential types
enum CredentialType {
  helper,
  basic,
  token,
  ssh,
}

/// SSH key types
enum SSHKeyType {
  rsa,
  ed25519,
  dss,
  ecdsa,
  unknown,
}
