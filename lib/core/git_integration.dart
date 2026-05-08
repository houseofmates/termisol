import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Git Integration - Git status and quick actions
/// 
/// Implements comprehensive Git integration:
/// - Real-time Git status monitoring
/// - Quick Git actions and shortcuts
/// - Branch management and switching
/// - Commit history and visualization
/// - Stash management
/// - Remote repository management
class GitIntegration {
  bool _isInitialized = false;
  
  // Git state
  GitStatus? _currentStatus;
  GitRepository? _currentRepository;
  List<GitBranch> _branches = [];
  List<GitCommit> _commits = [];
  List<GitStash> _stashes = [];
  
  // Monitoring
  Timer? _statusMonitor;
  final Map<String, DateTime> _lastStatusUpdate = {};
  
  // Configuration
  GitIntegrationConfig _config = GitIntegrationConfig();
  
  // Quick actions
  final Map<String, GitQuickAction> _quickActions = {};
  
  GitIntegration();
  
  bool get isInitialized => _isInitialized;
  GitStatus? get currentStatus => _currentStatus;
  GitRepository? get currentRepository => _currentRepository;
  List<GitBranch> get branches => List.unmodifiable(_branches);
  List<GitCommit> get commits => List.unmodifiable(_commits);
  List<GitStash> get stashes => List.unmodifiable(_stashes);
  
  /// Initialize Git integration
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Setup quick actions
      _setupQuickActions();
      
      // Detect current repository
      await _detectRepository();
      
      // Setup status monitoring
      _setupStatusMonitoring();
      
      _isInitialized = true;
      debugPrint('🔀 Git Integration initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Git Integration: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/git_integration_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = GitIntegrationConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load Git integration config: $e');
    }
  }
  
  /// Setup quick actions
  void _setupQuickActions() {
    _quickActions.addAll({
      'status': GitQuickAction(
        name: 'status',
        description: 'Show repository status',
        command: 'git status',
        category: GitActionCategory.status,
      ),
      'add': GitQuickAction(
        name: 'add',
        description: 'Add files to staging area',
        command: 'git add',
        category: GitActionCategory.staging,
      ),
      'commit': GitQuickAction(
        name: 'commit',
        description: 'Create a commit',
        command: 'git commit',
        category: GitActionCategory.commit,
      ),
      'push': GitQuickAction(
        name: 'push',
        description: 'Push changes to remote',
        command: 'git push',
        category: GitActionCategory.remote,
      ),
      'pull': GitQuickAction(
        name: 'pull',
        description: 'Pull changes from remote',
        command: 'git pull',
        category: GitActionCategory.remote,
      ),
      'branch': GitQuickAction(
        name: 'branch',
        description: 'Manage branches',
        command: 'git branch',
        category: GitActionCategory.branch,
      ),
      'checkout': GitQuickAction(
        name: 'checkout',
        description: 'Switch branches or restore files',
        command: 'git checkout',
        category: GitActionCategory.branch,
      ),
      'merge': GitQuickAction(
        name: 'merge',
        description: 'Merge branches',
        command: 'git merge',
        category: GitActionCategory.branch,
      ),
      'rebase': GitQuickAction(
        name: 'rebase',
        description: 'Rebase current branch',
        command: 'git rebase',
        category: GitActionCategory.branch,
      ),
      'stash': GitQuickAction(
        name: 'stash',
        description: 'Stash changes',
        command: 'git stash',
        category: GitActionCategory.stash,
      ),
      'log': GitQuickAction(
        name: 'log',
        description: 'Show commit history',
        command: 'git log',
        category: GitActionCategory.history,
      ),
      'diff': GitQuickAction(
        name: 'diff',
        description: 'Show differences',
        command: 'git diff',
        category: GitActionCategory.diff,
      ),
      'reset': GitQuickAction(
        name: 'reset',
        description: 'Reset changes',
        command: 'git reset',
        category: GitActionCategory.reset,
      ),
      'clean': GitQuickAction(
        name: 'clean',
        description: 'Remove untracked files',
        command: 'git clean',
        category: GitActionCategory.cleanup,
      ),
      'fetch': GitQuickAction(
        name: 'fetch',
        description: 'Fetch from remote',
        command: 'git fetch',
        category: GitActionCategory.remote,
      ),
      'clone': GitQuickAction(
        name: 'clone',
        description: 'Clone repository',
        command: 'git clone',
        category: GitActionCategory.remote,
      ),
      'init': GitQuickAction(
        name: 'init',
        description: 'Initialize repository',
        command: 'git init',
        category: GitActionCategory.init,
      ),
    });
  }
  
  /// Detect current repository
  Future<void> _detectRepository() async {
    try {
      // Check if we're in a Git repository
      final result = await Process.run('git', ['rev-parse', '--git-dir'], runInShell: true);
      
      if (result.exitCode == 0) {
        final gitDir = (result.stdout as String).trim();
        final workingDir = Directory.current.path;
        
        _currentRepository = GitRepository(
          path: workingDir,
          gitDir: gitDir,
          name: workingDir.split('/').last,
          detectedAt: DateTime.now(),
        );
        
        // Load repository information
        await _loadRepositoryInfo();
        
        debugPrint('📦 Git repository detected: ${_currentRepository!.name}');
      } else {
        _currentRepository = null;
        _currentStatus = null;
        _branches.clear();
        _commits.clear();
        _stashes.clear();
        
        debugPrint('📦 No Git repository detected');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detect Git repository: $e');
    }
  }
  
  /// Load repository information
  Future<void> _loadRepositoryInfo() async {
    if (_currentRepository == null) return;
    
    try {
      // Load current status
      await _updateStatus();
      
      // Load branches
      await _loadBranches();
      
      // Load recent commits
      await _loadCommits();
      
      // Load stashes
      await _loadStashes();
    } catch (e) {
      debugPrint('⚠️ Failed to load repository info: $e');
    }
  }
  
  /// Update Git status
  Future<void> _updateStatus() async {
    if (_currentRepository == null) return;
    
    try {
      final result = await Process.run('git', ['status', '--porcelain', '-b'], runInShell: true);
      
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        _currentStatus = _parseGitStatus(output);
        
        debugPrint('📊 Git status updated');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update Git status: $e');
    }
  }
  
  /// Parse Git status output
  GitStatus _parseGitStatus(String output) {
    final lines = output.split('\n');
    final stagedFiles = <GitFileStatus>[];
    final unstagedFiles = <GitFileStatus>[];
    final untrackedFiles = <String>[];
    String? currentBranch;
    bool isClean = true;
    
    for (final line in lines) {
      if (line.startsWith('##')) {
        // Branch information
        final match = RegExp(r'## ([^\s]+)').firstMatch(line);
        if (match != null) {
          currentBranch = match.group(1);
        }
        
        // Check if ahead/behind
        if (line.contains('ahead')) {
          final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(line);
          if (aheadMatch != null) {
            // TODO: Parse ahead count
          }
        }
      } else if (line.isNotEmpty && !line.startsWith('??')) {
        // Modified files
        final statusCode = line.substring(0, 2);
        final filePath = line.substring(3);
        
        final fileStatus = GitFileStatus(
          path: filePath,
          status: _parseFileStatus(statusCode),
          staged: statusCode[0] != ' ' && statusCode[0] != '?',
        );
        
        if (fileStatus.staged) {
          stagedFiles.add(fileStatus);
        } else {
          unstagedFiles.add(fileStatus);
        }
        
        isClean = false;
      } else if (line.startsWith('??')) {
        // Untracked files
        final filePath = line.substring(3);
        untrackedFiles.add(filePath);
        isClean = false;
      }
    }
    
    return GitStatus(
      currentBranch: currentBranch ?? 'unknown',
      isClean: isClean,
      stagedFiles: stagedFiles,
      unstagedFiles: unstagedFiles,
      untrackedFiles: untrackedFiles,
      updatedAt: DateTime.now(),
    );
  }
  
  /// Parse file status from status code
  GitFileStatusType _parseFileStatus(String statusCode) {
    final indexStatus = statusCode[0];
    final worktreeStatus = statusCode[1];
    
    if (indexStatus == 'M' || worktreeStatus == 'M') {
      return GitFileStatusType.modified;
    } else if (indexStatus == 'A' || worktreeStatus == 'A') {
      return GitFileStatusType.added;
    } else if (indexStatus == 'D' || worktreeStatus == 'D') {
      return GitFileStatusType.deleted;
    } else if (indexStatus == 'R' || worktreeStatus == 'R') {
      return GitFileStatusType.renamed;
    } else if (indexStatus == 'C' || worktreeStatus == 'C') {
      return GitFileStatusType.copied;
    } else if (indexStatus == 'U' || worktreeStatus == 'U') {
      return GitFileStatusType.unmerged;
    }
    
    return GitFileStatusType.modified;
  }
  
  /// Load branches
  Future<void> _loadBranches() async {
    try {
      final result = await Process.run('git', ['branch', '-a', '--format=%(refname:short)|%(HEAD)|%(upstream:track)'], runInShell: true);
      
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        _branches.clear();
        
        for (final line in output.split('\n')) {
          if (line.trim().isEmpty) continue;
          
          final parts = line.split('|');
          if (parts.length >= 3) {
            final branchName = parts[0];
            final isCurrent = parts[1] == '*';
            final trackingInfo = parts[2];
            
            _branches.add(GitBranch(
              name: branchName,
              isCurrent: isCurrent,
              isRemote: branchName.startsWith('origin/'),
              trackingInfo: trackingInfo,
              lastCommit: null, // TODO: Get last commit
            ));
          }
        }
        
        debugPrint('🌿 Loaded ${_branches.length} branches');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load branches: $e');
    }
  }
  
  /// Load recent commits
  Future<void> _loadCommits() async {
    try {
      final result = await Process.run('git', ['log', '--oneline', '--graph', '-20'], runInShell: true);
      
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        _commits.clear();
        
        for (final line in output.split('\n')) {
          if (line.trim().isEmpty) continue;
          
          final match = RegExp(r'\* ([a-f0-9]+) (.+)').firstMatch(line);
          if (match != null) {
            final hash = match.group(1)!;
            final message = match.group(2)!;
            
            _commits.add(GitCommit(
              hash: hash,
              shortHash: hash.substring(0, 7),
              message: message,
              author: '', // TODO: Get author
              date: DateTime.now(), // TODO: Get date
            ));
          }
        }
        
        debugPrint('📝 Loaded ${_commits.length} commits');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load commits: $e');
    }
  }
  
  /// Load stashes
  Future<void> _loadStashes() async {
    try {
      final result = await Process.run('git', ['stash', 'list'], runInShell: true);
      
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        _stashes.clear();
        
        for (final line in output.split('\n')) {
          if (line.trim().isEmpty) continue;
          
          final match = RegExp(r'sash@{(\d+)}: (.+)').firstMatch(line);
          if (match != null) {
            final index = int.parse(match.group(1)!);
            final message = match.group(2)!;
            
            _stashes.add(GitStash(
              index: index,
              message: message,
              createdAt: DateTime.now(), // TODO: Get actual date
            ));
          }
        }
        
        debugPrint('📦 Loaded ${_stashes.length} stashes');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load stashes: $e');
    }
  }
  
  /// Setup status monitoring
  void _setupStatusMonitoring() {
    if (_config.enableStatusMonitoring) {
      _statusMonitor = Timer.periodic(Duration(seconds: _config.statusUpdateInterval), (_) {
        _updateStatus();
      });
      debugPrint('👁️ Git status monitoring enabled');
    }
  }
  
  /// Execute Git command
  Future<GitCommandResult> executeCommand(String command, {List<String>? args}) async {
    try {
      final fullCommand = 'git $command${args?.map((a) => ' $a').join('') ?? ''}';
      final result = await Process.run('bash', ['-c', fullCommand], runInShell: true);
      
      final commandResult = GitCommandResult(
        command: command,
        args: args ?? [],
        exitCode: result.exitCode,
        stdout: result.stdout as String,
        stderr: result.stderr as String,
        success: result.exitCode == 0,
        timestamp: DateTime.now(),
      );
      
      // Update repository info after command
      if (commandResult.success) {
        await _loadRepositoryInfo();
      }
      
      debugPrint('🔀 Git command executed: $command (exit: ${result.exitCode})');
      return commandResult;
    } catch (e) {
      debugPrint('⚠️ Failed to execute Git command: $e');
      return GitCommandResult(
        command: command,
        args: args ?? [],
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
        success: false,
        timestamp: DateTime.now(),
      );
    }
  }
  
  /// Quick action: Add files
  Future<GitCommandResult> addFiles(List<String> files) async {
    final args = ['add'] + files;
    return await executeCommand('add', args: args);
  }
  
  /// Quick action: Add all files
  Future<GitCommandResult> addAllFiles() async {
    return await executeCommand('add', args: ['.']);
  }
  
  /// Quick action: Commit changes
  Future<GitCommandResult> commit(String message, {bool sign = false}) async {
    final args = <String>['commit', '-m', message];
    if (sign) {
      args.add('-S');
    }
    return await executeCommand('commit', args: args);
  }
  
  /// Quick action: Push changes
  Future<GitCommandResult> push({String? remote, String? branch}) async {
    final args = <String>['push'];
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);
    return await executeCommand('push', args: args);
  }
  
  /// Quick action: Pull changes
  Future<GitCommandResult> pull({String? remote, String? branch}) async {
    final args = <String>['pull'];
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);
    return await executeCommand('pull', args: args);
  }
  
  /// Quick action: Create branch
  Future<GitCommandResult> createBranch(String name, {String? baseBranch}) async {
    final args = <String>['branch', name];
    if (baseBranch != null) {
      args.insert(1, baseBranch);
    }
    return await executeCommand('branch', args: args);
  }
  
  /// Quick action: Switch branch
  Future<GitCommandResult> switchBranch(String name) async {
    return await executeCommand('checkout', args: [name]);
  }
  
  /// Quick action: Delete branch
  Future<GitCommandResult> deleteBranch(String name, {bool force = false}) async {
    final args = <String>['branch', '-d'];
    if (force) args.add('-f');
    args.add(name);
    return await executeCommand('branch', args: args);
  }
  
  /// Quick action: Merge branch
  Future<GitCommandResult> mergeBranch(String name, {bool noFastForward = false}) async {
    final args = <String>['merge'];
    if (noFastForward) args.add('--no-ff');
    args.add(name);
    return await executeCommand('merge', args: args);
  }
  
  /// Quick action: Rebase branch
  Future<GitCommandResult> rebaseBranch(String name, {bool interactive = false}) async {
    final args = <String>['rebase'];
    if (interactive) args.add('-i');
    args.add(name);
    return await executeCommand('rebase', args: args);
  }
  
  /// Quick action: Stash changes
  Future<GitCommandResult> stashChanges({String? message}) async {
    final args = <String>['stash'];
    if (message != null) {
      args.addAll(['push', '-m', message]);
    }
    return await executeCommand('stash', args: args);
  }
  
  /// Quick action: Apply stash
  Future<GitCommandResult> applyStash(int index) async {
    return await executeCommand('stash', args: ['apply', 'stash@{$index}']);
  }
  
  /// Quick action: Pop stash
  Future<GitCommandResult> popStash() async {
    return await executeCommand('stash', args: ['pop']);
  }
  
  /// Quick action: Drop stash
  Future<GitCommandResult> dropStash(int index) async {
    return await executeCommand('stash', args: ['drop', 'stash@{$index}']);
  }
  
  /// Quick action: Reset changes
  Future<GitCommandResult> resetChanges({String? mode, String? commit}) async {
    final args = <String>['reset'];
    if (mode != null) args.add(mode);
    if (commit != null) args.add(commit);
    return await executeCommand('reset', args: args);
  }
  
  /// Quick action: Clean untracked files
  Future<GitCommandResult> cleanUntracked({bool force = false, bool directories = false}) async {
    final args = <String>['clean'];
    if (force) args.add('-f');
    if (directories) args.add('-d');
    return await executeCommand('clean', args: args);
  }
  
  /// Quick action: Fetch from remote
  Future<GitCommandResult> fetch({String? remote}) async {
    final args = <String>['fetch'];
    if (remote != null) args.add(remote);
    return await executeCommand('fetch', args: args);
  }
  
  /// Quick action: Clone repository
  Future<GitCommandResult> cloneRepository(String url, {String? directory, bool depth = false}) async {
    final args = <String>['clone'];
    if (depth) args.add('--depth 1');
    if (directory != null) args.add(directory);
    args.add(url);
    return await executeCommand('clone', args: args);
  }
  
  /// Quick action: Initialize repository
  Future<GitCommandResult> initializeRepository() async {
    return await executeCommand('init');
  }
  
  /// Get file diff
  Future<String> getFileDiff(String filePath) async {
    try {
      final result = await Process.run('git', ['diff', filePath], runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout as String;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get file diff: $e');
    }
    return '';
  }
  
  /// Get visual diff between commits or branches
  Future<VisualDiffResult> getVisualDiff({
    String? commit1,
    String? commit2,
    String? branch1,
    String? branch2,
    List<String>? filePaths,
    DiffType diffType = DiffType.unified,
    int contextLines = 3,
  }) async {
    try {
      final args = <String>['diff'];
      
      // Add diff type
      switch (diffType) {
        case DiffType.unified:
          args.add('--unified=$contextLines');
          break;
        case DiffType.sideBySide:
          args.add('--word-diff=color');
          break;
        case DiffType.minimal:
          args.add('--minimal');
          break;
        case DiffType.patience:
          args.add('--patience');
          break;
      }
      
      // Add commit/branch references
      if (commit1 != null && commit2 != null) {
        args.addAll([commit1, commit2]);
      } else if (branch1 != null && branch2 != null) {
        args.addAll([branch1, branch2]);
      } else if (commit1 != null) {
        args.add(commit1);
      }
      
      // Add file paths
      if (filePaths != null && filePaths.isNotEmpty) {
        args.addAll(['--'] + filePaths);
      }
      
      final result = await Process.run('git', args, runInShell: true);
      
      if (result.exitCode == 0) {
        return await _parseVisualDiff(result.stdout as String, diffType);
      } else {
        return VisualDiffResult(
          success: false,
          error: result.stderr as String,
          diffType: diffType,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get visual diff: $e');
      return VisualDiffResult(
        success: false,
        error: e.toString(),
        diffType: diffType,
      );
    }
  }
  
  /// Get staged diff
  Future<VisualDiffResult> getStagedDiff({
    List<String>? filePaths,
    DiffType diffType = DiffType.unified,
    int contextLines = 3,
  }) async {
    try {
      final args = <String>['diff', '--staged'];
      
      // Add diff type
      switch (diffType) {
        case DiffType.unified:
          args.add('--unified=$contextLines');
          break;
        case DiffType.sideBySide:
          args.add('--word-diff=color');
          break;
        case DiffType.minimal:
          args.add('--minimal');
          break;
        case DiffType.patience:
          args.add('--patience');
          break;
      }
      
      // Add file paths
      if (filePaths != null && filePaths.isNotEmpty) {
        args.addAll(['--'] + filePaths);
      }
      
      final result = await Process.run('git', args, runInShell: true);
      
      if (result.exitCode == 0) {
        return await _parseVisualDiff(result.stdout as String, diffType);
      } else {
        return VisualDiffResult(
          success: false,
          error: result.stderr as String,
          diffType: diffType,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get staged diff: $e');
      return VisualDiffResult(
        success: false,
        error: e.toString(),
        diffType: diffType,
      );
    }
  }
  
  /// Get diff statistics
  Future<DiffStatistics> getDiffStatistics({
    String? commit1,
    String? commit2,
    String? branch1,
    String? branch2,
  }) async {
    try {
      final args = <String>['diff', '--stat'];
      
      // Add commit/branch references
      if (commit1 != null && commit2 != null) {
        args.addAll([commit1, commit2]);
      } else if (branch1 != null && branch2 != null) {
        args.addAll([branch1, branch2]);
      }
      
      final result = await Process.run('git', args, runInShell: true);
      
      if (result.exitCode == 0) {
        return _parseDiffStatistics(result.stdout as String);
      } else {
        return DiffStatistics(
          filesChanged: 0,
          insertions: 0,
          deletions: 0,
          success: false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get diff statistics: $e');
      return DiffStatistics(
        filesChanged: 0,
        insertions: 0,
        deletions: 0,
        success: false,
      );
    }
  }
  
  /// Parse visual diff output
  Future<VisualDiffResult> _parseVisualDiff(String diffOutput, DiffType diffType) async {
    final lines = diffOutput.split('\n');
    final hunks = <DiffHunk>[];
    final files = <DiffFile>[];
    
    DiffFile? currentFile;
    DiffHunk? currentHunk;
    List<String> currentLines = [];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.startsWith('diff --git')) {
        // New file diff
        if (currentFile != null) {
          files.add(currentFile);
        }
        
        final match = RegExp(r'diff --git a/(.*) b/(.*)').firstMatch(line);
        if (match != null) {
          currentFile = DiffFile(
            oldPath: match.group(1)!,
            newPath: match.group(2)!,
            hunks: [],
          );
        }
        
        currentLines.clear();
      } else if (line.startsWith('@@')) {
        // New hunk
        if (currentHunk != null && currentFile != null) {
          currentFile.hunks.add(currentHunk);
        }
        
        final match = RegExp(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)').firstMatch(line);
        if (match != null) {
          currentHunk = DiffHunk(
            oldStart: int.parse(match.group(1)!),
            oldLines: int.parse(match.group(2) ?? '1'),
            newStart: int.parse(match.group(3)!),
            newLines: int.parse(match.group(4) ?? '1'),
            header: match.group(5) ?? '',
            lines: [],
          );
        }
        
        currentLines.clear();
      } else if (line.isNotEmpty) {
        // Diff line
        final diffLine = DiffLine(
          content: line.substring(1),
          type: _getDiffLineType(line[0]),
          lineNumber: _calculateLineNumber(line, currentHunk, currentLines.length),
        );
        
        currentLines.add(line);
        if (currentHunk != null) {
          currentHunk.lines.add(diffLine);
        }
      }
    }
    
    // Add last hunk and file
    if (currentHunk != null && currentFile != null) {
      currentFile.hunks.add(currentHunk);
    }
    if (currentFile != null) {
      files.add(currentFile);
    }
    
    return VisualDiffResult(
      success: true,
      files: files,
      diffType: diffType,
      rawOutput: diffOutput,
    );
  }
  
  /// Parse diff statistics
  DiffStatistics _parseDiffStatistics(String statsOutput) {
    final lines = statsOutput.split('\n');
    int filesChanged = 0;
    int insertions = 0;
    int deletions = 0;
    
    for (final line in lines) {
      if (line.contains('|')) {
        final parts = line.split('|');
        if (parts.length >= 2) {
          filesChanged++;
          
          final stats = parts[1].trim();
          final match = RegExp(r'(\d+) insertion(?:s)?\(\+\), (\d+) deletion(?:s)?\(-\)').firstMatch(stats);
          if (match != null) {
            insertions += int.parse(match.group(1)!);
            deletions += int.parse(match.group(2)!);
          }
        }
      }
    }
    
    return DiffStatistics(
      filesChanged: filesChanged,
      insertions: insertions,
      deletions: deletions,
      success: true,
    );
  }
  
  /// Get diff line type
  DiffLineType _getDiffLineType(String prefix) {
    switch (prefix) {
      case '+':
        return DiffLineType.added;
      case '-':
        return DiffLineType.removed;
      case ' ':
        return DiffLineType.context;
      default:
        return DiffLineType.context;
    }
  }
  
  /// Calculate line number for diff line
  int _calculateLineNumber(String line, DiffHunk? hunk, int lineIndex) {
    if (hunk == null) return 0;
    
    if (line.startsWith('+')) {
      return hunk.newStart + lineIndex;
    } else if (line.startsWith('-')) {
      return hunk.oldStart + lineIndex;
    } else {
      return hunk.newStart + lineIndex;
    }
  }
  
  /// Generate HTML for visual diff viewer
  String generateDiffHTML(VisualDiffResult diffResult) {
    if (!diffResult.success) {
      return '<div class="error">Error: ${diffResult.error}</div>';
    }
    
    final html = StringBuffer();
    html.write('<div class="diff-viewer">');
    
    for (final file in diffResult.files) {
      html.write('<div class="diff-file">');
      html.write('<div class="file-header">');
      html.write('<span class="file-path">${file.oldPath} → ${file.newPath}</span>');
      html.write('</div>');
      
      for (final hunk in file.hunks) {
        html.write('<div class="diff-hunk">');
        html.write('<div class="hunk-header">');
        html.write('<code>${hunk.header}</code>');
        html.write('</div>');
        
        for (final line in hunk.lines) {
          final cssClass = _getLineCSSClass(line.type);
          html.write('<div class="diff-line $cssClass">');
          html.write('<span class="line-number">${line.lineNumber}</span>');
          html.write('<span class="line-content">${_escapeHtml(line.content)}</span>');
          html.write('</div>');
        }
        
        html.write('</div>');
      }
      
      html.write('</div>');
    }
    
    html.write('</div>');
    return html.toString();
  }
  
  /// Get CSS class for diff line
  String _getLineCSSClass(DiffLineType type) {
    switch (type) {
      case DiffLineType.added:
        return 'added';
      case DiffLineType.removed:
        return 'removed';
      case DiffLineType.context:
        return 'context';
    }
  }
  
  /// Escape HTML characters
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }
  
  /// Get commit details
  Future<GitCommit?> getCommitDetails(String hash) async {
    try {
      final result = await Process.run('git', ['show', '--format=fuller', hash], runInShell: true);
      if (result.exitCode == 0) {
        return _parseCommitDetails(hash, result.stdout as String);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get commit details: $e');
    }
    return null;
  }
  
  /// Parse commit details
  GitCommit _parseCommitDetails(String hash, String output) {
    final lines = output.split('\n');
    String author = '';
    String date = '';
    String message = '';
    
    for (final line in lines) {
      if (line.startsWith('Author:')) {
        author = line.substring(8).trim();
      } else if (line.startsWith('Date:')) {
        date = line.substring(6).trim();
      } else if (line.startsWith('    ') && message.isEmpty) {
        message = line.trim();
      }
    }
    
    return GitCommit(
      hash: hash,
      shortHash: hash.substring(0, 7),
      message: message,
      author: author,
      date: DateTime.tryParse(date) ?? DateTime.now(),
    );
  }
  
  /// Get quick action
  GitQuickAction? getQuickAction(String name) {
    return _quickActions[name];
  }
  
  /// Get all quick actions
  Map<String, GitQuickAction> getAllQuickActions() {
    return Map.unmodifiable(_quickActions);
  }
  
  /// Get quick actions by category
  List<GitQuickAction> getQuickActionsByCategory(GitActionCategory category) {
    return _quickActions.values
        .where((action) => action.category == category)
        .toList();
  }
  
  /// Get repository statistics
  GitStatistics getStatistics() {
    if (_currentRepository == null) {
      return GitStatistics(
        totalBranches: 0,
        totalCommits: 0,
        totalStashes: 0,
        untrackedFiles: 0,
        modifiedFiles: 0,
        stagedFiles: 0,
        isClean: true,
        currentBranch: 'none',
      );
    }
    
    final status = _currentStatus;
    
    return GitStatistics(
      totalBranches: _branches.length,
      totalCommits: _commits.length,
      totalStashes: _stashes.length,
      untrackedFiles: status?.untrackedFiles.length ?? 0,
      modifiedFiles: status?.unstagedFiles.length ?? 0,
      stagedFiles: status?.stagedFiles.length ?? 0,
      isClean: status?.isClean ?? true,
      currentBranch: status?.currentBranch ?? 'unknown',
    );
  }
  
  /// Export Git data
  String exportGitData() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'repository': _currentRepository?.toJson(),
      'status': _currentStatus?.toJson(),
      'branches': _branches.map((b) => b.toJson()).toList(),
      'commits': _commits.map((c) => c.toJson()).toList(),
      'stashes': _stashes.map((s) => s.toJson()).toList(),
    };
    
    return jsonEncode(data);
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    _statusMonitor?.cancel();
    _currentRepository = null;
    _currentStatus = null;
    _branches.clear();
    _commits.clear();
    _stashes.clear();
    _quickActions.clear();
    _lastStatusUpdate.clear();
    
    _isInitialized = false;
    debugPrint('🔀 Git Integration disposed');
  }
}

/// Git repository data structure
class GitRepository {
  final String path;
  final String gitDir;
  final String name;
  final DateTime detectedAt;
  
  GitRepository({
    required this.path,
    required this.gitDir,
    required this.name,
    required this.detectedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'path': path,
    'gitDir': gitDir,
    'name': name,
    'detectedAt': detectedAt.toIso8601String(),
  };
}

/// Git status data structure
class GitStatus {
  final String currentBranch;
  final bool isClean;
  final List<GitFileStatus> stagedFiles;
  final List<GitFileStatus> unstagedFiles;
  final List<String> untrackedFiles;
  final DateTime updatedAt;
  
  GitStatus({
    required this.currentBranch,
    required this.isClean,
    required this.stagedFiles,
    required this.unstagedFiles,
    required this.untrackedFiles,
    required this.updatedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'currentBranch': currentBranch,
    'isClean': isClean,
    'stagedFiles': stagedFiles.map((f) => f.toJson()).toList(),
    'unstagedFiles': unstagedFiles.map((f) => f.toJson()).toList(),
    'untrackedFiles': untrackedFiles,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Git file status data structure
class GitFileStatus {
  final String path;
  final GitFileStatusType status;
  final bool staged;
  
  GitFileStatus({
    required this.path,
    required this.status,
    required this.staged,
  });
  
  Map<String, dynamic> toJson() => {
    'path': path,
    'status': status.toString(),
    'staged': staged,
  };
}

/// Git branch data structure
class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;
  final String trackingInfo;
  final String? lastCommit;
  
  GitBranch({
    required this.name,
    required this.isCurrent,
    required this.isRemote,
    required this.trackingInfo,
    this.lastCommit,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'isCurrent': isCurrent,
    'isRemote': isRemote,
    'trackingInfo': trackingInfo,
    'lastCommit': lastCommit,
  };
}

/// Git commit data structure
class GitCommit {
  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final DateTime date;
  
  GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.date,
  });
  
  Map<String, dynamic> toJson() => {
    'hash': hash,
    'shortHash': shortHash,
    'message': message,
    'author': author,
    'date': date.toIso8601String(),
  };
}

/// Git stash data structure
class GitStash {
  final int index;
  final String message;
  final DateTime createdAt;
  
  GitStash({
    required this.index,
    required this.message,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'index': index,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Git quick action data structure
class GitQuickAction {
  final String name;
  final String description;
  final String command;
  final GitActionCategory category;
  
  GitQuickAction({
    required this.name,
    required this.description,
    required this.command,
    required this.category,
  });
}

/// Git command result data structure
class GitCommandResult {
  final String command;
  final List<String> args;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;
  final DateTime timestamp;
  
  GitCommandResult({
    required this.command,
    required this.args,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.success,
    required this.timestamp,
  });
}

/// Git statistics data structure
class GitStatistics {
  final int totalBranches;
  final int totalCommits;
  final int totalStashes;
  final int untrackedFiles;
  final int modifiedFiles;
  final int stagedFiles;
  final bool isClean;
  final String currentBranch;
  
  GitStatistics({
    required this.totalBranches,
    required this.totalCommits,
    required this.totalStashes,
    required this.untrackedFiles,
    required this.modifiedFiles,
    required this.stagedFiles,
    required this.isClean,
    required this.currentBranch,
  });
}

/// Git integration configuration
class GitIntegrationConfig {
  final bool enableStatusMonitoring;
  final int statusUpdateInterval;
  final bool enableQuickActions;
  final bool enableAutoRefresh;
  final int maxCommitsToLoad;
  final int maxBranchesToLoad;
  
  GitIntegrationConfig({
    this.enableStatusMonitoring = true,
    this.statusUpdateInterval = 30,
    this.enableQuickActions = true,
    this.enableAutoRefresh = true,
    this.maxCommitsToLoad = 50,
    this.maxBranchesToLoad = 20,
  });
  
  Map<String, dynamic> toJson() => {
    'enableStatusMonitoring': enableStatusMonitoring,
    'statusUpdateInterval': statusUpdateInterval,
    'enableQuickActions': enableQuickActions,
    'enableAutoRefresh': enableAutoRefresh,
    'maxCommitsToLoad': maxCommitsToLoad,
    'maxBranchesToLoad': maxBranchesToLoad,
  };
  
  factory GitIntegrationConfig.fromJson(Map<String, dynamic> json) {
    return GitIntegrationConfig(
      enableStatusMonitoring: json['enableStatusMonitoring'] as bool? ?? true,
      statusUpdateInterval: json['statusUpdateInterval'] as int? ?? 30,
      enableQuickActions: json['enableQuickActions'] as bool? ?? true,
      enableAutoRefresh: json['enableAutoRefresh'] as bool? ?? true,
      maxCommitsToLoad: json['maxCommitsToLoad'] as int? ?? 50,
      maxBranchesToLoad: json['maxBranchesToLoad'] as int? ?? 20,
    );
  }
}

/// Git file status type enumeration
enum GitFileStatusType {
  modified,
  added,
  deleted,
  renamed,
  copied,
  unmerged,
}

/// Git action category enumeration
enum GitActionCategory {
  status,
  staging,
  commit,
  remote,
  branch,
  stash,
  history,
  diff,
  reset,
  cleanup,
  init,
}

/// Visual diff result data structure
class VisualDiffResult {
  final bool success;
  final List<DiffFile> files;
  final DiffType diffType;
  final String? error;
  final String? rawOutput;
  
  VisualDiffResult({
    required this.success,
    required this.diffType,
    this.files = const [],
    this.error,
    this.rawOutput,
  });
}

/// Diff file data structure
class DiffFile {
  final String oldPath;
  final String newPath;
  final List<DiffHunk> hunks;
  
  DiffFile({
    required this.oldPath,
    required this.newPath,
    required this.hunks,
  });
}

/// Diff hunk data structure
class DiffHunk {
  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final String header;
  final List<DiffLine> lines;
  
  DiffHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.header,
    required this.lines,
  });
}

/// Diff line data structure
class DiffLine {
  final String content;
  final DiffLineType type;
  final int lineNumber;
  
  DiffLine({
    required this.content,
    required this.type,
    required this.lineNumber,
  });
}

/// Diff statistics data structure
class DiffStatistics {
  final int filesChanged;
  final int insertions;
  final int deletions;
  final bool success;
  
  DiffStatistics({
    required this.filesChanged,
    required this.insertions,
    required this.deletions,
    required this.success,
  });
}

/// Diff type enumeration
enum DiffType {
  unified,
  sideBySide,
  minimal,
  patience,
}

/// Diff line type enumeration
enum DiffLineType {
  added,
  removed,
  context,
}
