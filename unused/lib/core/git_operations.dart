import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';

/// Git operations integration for Termisol
/// 
/// Features:
/// - Complete Git command integration
/// - Repository status monitoring
/// - Branch management
/// - Commit and push operations
/// - Merge and rebase support
/// - Stash management
/// - Remote operations
class GitOperations {
  String? _currentRepoPath;
  GitRepository? _currentRepository;
  final StreamController<GitEvent> _eventController = StreamController<GitEvent>.broadcast();
  
  Stream<GitEvent> get events => _eventController.stream;
  GitRepository? get currentRepository => _currentRepository;
  
  /// Initialize Git operations for a directory
  Future<bool> initializeRepository(String path) async {
    try {
      final gitDir = await _findGitDirectory(path);
      if (gitDir == null) {
        _eventController.add(GitEvent(
          type: GitEventType.error,
          message: 'Not a Git repository',
          data: {'path': path},
        ));
        return false;
      }
      
      _currentRepoPath = gitDir;
      _currentRepository = await GitRepository.fromPath(gitDir);
      
      _eventController.add(GitEvent(
        type: GitEventType.repository_initialized,
        message: 'Git repository initialized',
        data: {'path': gitDir, 'repository': _currentRepository},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to initialize repository: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Find .git directory
  Future<String?> _findGitDirectory(String path) async {
    var current = Directory(path);
    
    while (current.parent.path != current.path) {
      final gitDir = Directory(path.join(current.path, '.git'));
      if (await gitDir.exists()) {
        return current.path;
      }
      current = current.parent;
    }
    
    return null;
  }
  
  /// Get repository status
  Future<GitStatus?> getStatus() async {
    if (_currentRepoPath == null) return null;
    
    try {
      final result = await run('git', ['status', '--porcelain=v1'], workingDirectory: _currentRepoPath);
      
      final status = GitStatus();
      final lines = result.stdout.toString().split('\n');
      
      for (final line in lines) {
        if (line.isEmpty) continue;
        
        final index = line[0];
        final worktree = line[1];
        final filePath = line.substring(3);
        
        final statusType = _parseStatusType(index, worktree);
        status.addFile(GitFileStatus(
          path: filePath,
          indexStatus: index,
          worktreeStatus: worktree,
          statusType: statusType,
        ));
      }
      
      return status;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to get status: $e',
        data: {'error': e.toString()},
      ));
      return null;
    }
  }
  
  GitStatusType _parseStatusType(String index, String worktree) {
    if (index == 'M' || worktree == 'M') return GitStatusType.modified;
    if (index == 'A' || worktree == 'A') return GitStatusType.added;
    if (index == 'D' || worktree == 'D') return GitStatusType.deleted;
    if (index == 'R' || worktree == 'R') return GitStatusType.renamed;
    if (index == 'C' || worktree == 'C') return GitStatusType.copied;
    if (index == 'U' || worktree == 'U') return GitStatusType.unmerged;
    if (index == '?' || worktree == '?') return GitStatusType.untracked;
    if (index == '!' || worktree == '!') return GitStatusType.ignored;
    return GitStatusType.unchanged;
  }
  
  /// Get current branch
  Future<String?> getCurrentBranch() async {
    if (_currentRepoPath == null) return null;
    
    try {
      final result = await run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], workingDirectory: _currentRepoPath);
      return result.stdout.toString().trim();
    } catch (e) {
      return null;
    }
  }
  
  /// Get all branches
  Future<List<GitBranch>> getBranches() async {
    if (_currentRepoPath == null) return [];
    
    try {
      final result = await run('git', ['branch', '-a', '--format=%(refname:short)%(HEAD)'], workingDirectory: _currentRepoPath);
      final lines = result.stdout.toString().split('\n');
      
      final branches = <GitBranch>[];
      final currentBranch = await getCurrentBranch();
      
      for (final line in lines) {
        if (line.isEmpty) continue;
        
        final isCurrent = line.endsWith('*');
        final name = isCurrent ? line.substring(0, line.length - 1) : line;
        
        branches.add(GitBranch(
          name: name,
          isCurrent: name == currentBranch,
          isRemote: name.startsWith('origin/'),
        ));
      }
      
      return branches;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to get branches: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Add files to staging
  Future<bool> addFiles(List<String> files) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = ['add'];
      args.addAll(files);
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.files_staged,
        message: 'Files staged successfully',
        data: {'files': files},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to stage files: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Commit changes
  Future<bool> commit(String message, {List<String>? files}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      // Stage files if provided
      if (files != null && files.isNotEmpty) {
        await addFiles(files);
      }
      
      // Create commit
      await run('git', ['commit', '-m', message], workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.committed,
        message: 'Changes committed successfully',
        data: {'message': message},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to commit: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Push changes to remote
  Future<bool> push({String? remote, String? branch}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = ['push'];
      if (remote != null) args.add(remote);
      if (branch != null) args.add(branch);
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.pushed,
        message: 'Changes pushed successfully',
        data: {'remote': remote, 'branch': branch},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to push: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Pull changes from remote
  Future<bool> pull({String? remote, String? branch}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = ['pull'];
      if (remote != null) args.add(remote);
      if (branch != null) args.add(branch);
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.pulled,
        message: 'Changes pulled successfully',
        data: {'remote': remote, 'branch': branch},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to pull: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Create new branch
  Future<bool> createBranch(String branchName, {bool checkout = true}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = checkout ? ['checkout', '-b', branchName] : ['branch', branchName];
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.branch_created,
        message: 'Branch created successfully',
        data: {'branch': branchName, 'checkout': checkout},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to create branch: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Switch branch
  Future<bool> checkoutBranch(String branchName) async {
    if (_currentRepoPath == null) return false;
    
    try {
      await run('git', ['checkout', branchName], workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.branch_switched,
        message: 'Switched to branch: $branchName',
        data: {'branch': branchName},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to switch branch: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Get commit history
  Future<List<GitCommit>> getCommitHistory({int limit = 50}) async {
    if (_currentRepoPath == null) return [];
    
    try {
      final result = await run(
        'git',
        ['log', '--oneline', '--format=%H|%h|%an|%ad|%s', '--date=iso', '-$limit'],
        workingDirectory: _currentRepoPath,
      );
      
      final lines = result.stdout.toString().split('\n');
      final commits = <GitCommit>[];
      
      for (final line in lines) {
        if (line.isEmpty) continue;
        
        final parts = line.split('|');
        if (parts.length >= 5) {
          commits.add(GitCommit(
            hash: parts[0],
            shortHash: parts[1],
            author: parts[2],
            date: DateTime.parse(parts[3]),
            message: parts[4],
          ));
        }
      }
      
      return commits;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to get commit history: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Stash changes
  Future<bool> stashChanges({String? message}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = ['stash'];
      if (message != null) {
        args.addAll(['push', '-m', message]);
      }
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.stashed,
        message: 'Changes stashed successfully',
        data: {'message': message},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to stash: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Apply stash
  Future<bool> applyStash({int? stashIndex}) async {
    if (_currentRepoPath == null) return false;
    
    try {
      final args = ['stash', 'apply'];
      if (stashIndex != null) {
        args.add('stash@{$stashIndex}');
      }
      
      await run('git', args, workingDirectory: _currentRepoPath);
      
      _eventController.add(GitEvent(
        type: GitEventType.stash_applied,
        message: 'Stash applied successfully',
        data: {'stash_index': stashIndex},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(GitEvent(
        type: GitEventType.error,
        message: 'Failed to apply stash: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Get stash list
  Future<List<GitStash>> getStashList() async {
    if (_currentRepoPath == null) return [];
    
    try {
      final result = await run('git', ['stash', 'list', '--format=%gd|%gs|%gD'], workingDirectory: _currentRepoPath);
      final lines = result.stdout.toString().split('\n');
      
      final stashes = <GitStash>[];
      
      for (final line in lines) {
        if (line.isEmpty) continue;
        
        final parts = line.split('|');
        if (parts.length >= 3) {
          stashes.add(GitStash(
            ref: parts[0],
            message: parts[1],
            date: parts[2],
          ));
        }
      }
      
      return stashes;
    } catch (e) {
      return [];
    }
  }
  
  /// Dispose
  void dispose() {
    _eventController.close();
  }
}

/// Git repository information
class GitRepository {
  final String path;
  final String? remoteUrl;
  final String? defaultBranch;
  
  GitRepository({
    required this.path,
    this.remoteUrl,
    this.defaultBranch,
  });
  
  static Future<GitRepository> fromPath(String path) async {
    // Get remote URL
    String? remoteUrl;
    try {
      final result = await run('git', ['config', '--get', 'remote.origin.url'], workingDirectory: path);
      remoteUrl = result.stdout.toString().trim();
      if (remoteUrl.isEmpty) remoteUrl = null;
    } catch (e) {
      // No remote or not configured
    }
    
    // Get default branch
    String? defaultBranch;
    try {
      final result = await run('git', ['symbolic-ref', 'refs/remotes/origin/HEAD'], workingDirectory: path);
      final ref = result.stdout.toString().trim();
      if (ref.isNotEmpty) {
        defaultBranch = ref.replaceFirst('refs/remotes/origin/', '');
      }
    } catch (e) {
      // No default branch or not configured
    }
    
    return GitRepository(
      path: path,
      remoteUrl: remoteUrl,
      defaultBranch: defaultBranch,
    );
  }
}

/// Git status information
class GitStatus {
  final List<GitFileStatus> files = [];
  
  void addFile(GitFileStatus file) {
    files.add(file);
  }
  
  bool get hasChanges => files.isNotEmpty;
  int get stagedCount => files.where((f) => f.indexStatus != ' ' && f.indexStatus != '?').length;
  int get modifiedCount => files.where((f) => f.statusType == GitStatusType.modified).length;
  int get untrackedCount => files.where((f) => f.statusType == GitStatusType.untracked).length;
}

/// Git file status
class GitFileStatus {
  final String path;
  final String indexStatus;
  final String worktreeStatus;
  final GitStatusType statusType;
  
  GitFileStatus({
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
    required this.statusType,
  });
}

/// Git status types
enum GitStatusType {
  modified,
  added,
  deleted,
  renamed,
  copied,
  unmerged,
  untracked,
  ignored,
  unchanged,
}

/// Git branch information
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

/// Git commit information
class GitCommit {
  final String hash;
  final String shortHash;
  final String author;
  final DateTime date;
  final String message;
  
  GitCommit({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.date,
    required this.message,
  });
}

/// Git stash information
class GitStash {
  final String ref;
  final String message;
  final String date;
  
  GitStash({
    required this.ref,
    required this.message,
    required this.date,
  });
}

/// Git event types
enum GitEventType {
  repository_initialized,
  files_staged,
  committed,
  pushed,
  pulled,
  branch_created,
  branch_switched,
  stashed,
  stash_applied,
  error,
}

/// Git event
class GitEvent {
  final GitEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  GitEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
