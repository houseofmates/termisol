import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'terminal_session.dart';

/// Shell Integration - Smart terminal features and shell awareness
/// 
/// Implements advanced shell integration:
/// - Smart completions and suggestions
/// - Command hints and documentation
/// - Git integration and status
/// - Directory tracking and bookmarks
/// - Command history with intelligence
class ShellIntegration {
  bool _isInitialized = false;
  String? _currentShell;
  String? _currentWorkingDirectory;
  String? _gitBranch;
  GitStatus _gitStatus = GitStatus();
  
  // Command completion
  final Map<String, List<String>> _commandCache = {};
  final Map<String, CommandInfo> _commandDatabase = {};
  
  // Smart suggestions
  final List<String> _commandHistory = [];
  final Map<String, int> _commandFrequency = {};
  final Map<String, DateTime> _lastUsedCommands = {};
  
  // Directory bookmarks
  final Map<String, String> _bookmarks = {};
  
  // Git state
  final Map<String, GitRepository> _gitRepositories = {};
  
  // Shell hooks
  final Map<String, ShellHook> _hooks = {};
  
  ShellIntegration();
  
  bool get isInitialized => _isInitialized;
  String? get currentShell => _currentShell;
  String? get currentWorkingDirectory => _currentWorkingDirectory;
  String? get gitBranch => _gitBranch;
  GitStatus get gitStatus => _gitStatus;
  
  /// Initialize shell integration
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Detect current shell
      await _detectShell();
      
      // Load command database
      await _loadCommandDatabase();
      
      // Load user preferences
      await _loadUserPreferences();
      
      // Setup shell hooks
      _setupShellHooks();
      
      _isInitialized = true;
      debugPrint('🐚 Shell Integration initialized with shell: $_currentShell');
    } catch (e) {
      debugPrint('❌ Failed to initialize Shell Integration: $e');
    }
  }
  
  /// Detect current shell
  Future<void> _detectShell() async {
    try {
      // Check environment variables
      final shellEnv = Platform.environment['SHELL'] ?? '';
      if (shellEnv.contains('bash')) {
        _currentShell = 'bash';
      } else if (shellEnv.contains('zsh')) {
        _currentShell = 'zsh';
      } else if (shellEnv.contains('fish')) {
        _currentShell = 'fish';
      } else if (shellEnv.contains('powershell')) {
        _currentShell = 'powershell';
      } else if (Platform.isWindows) {
        _currentShell = 'cmd';
      } else {
        _currentShell = 'bash'; // Default fallback
      }
      
      debugPrint('🔍 Detected shell: $_currentShell');
    } catch (e) {
      debugPrint('⚠️ Failed to detect shell: $e');
      _currentShell = 'bash';
    }
  }
  
  /// Load command database
  Future<void> _loadCommandDatabase() async {
    try {
      // Common Unix commands
      _commandDatabase.addAll({
        'ls': CommandInfo(
          name: 'ls',
          description: 'List directory contents',
          usage: 'ls [options] [directory]',
          examples: ['ls -la', 'ls /home/user'],
          category: CommandCategory.fileSystem,
          completionType: CompletionType.file,
        ),
        'cd': CommandInfo(
          name: 'cd',
          description: 'Change directory',
          usage: 'cd [directory]',
          examples: ['cd /home', 'cd ..', 'cd ~/Documents'],
          category: CommandCategory.fileSystem,
          completionType: CompletionType.directory,
        ),
        'git': CommandInfo(
          name: 'git',
          description: 'Distributed version control system',
          usage: 'git <command> [options]',
          examples: ['git status', 'git add .', 'git commit -m "message"'],
          category: CommandCategory.versionControl,
          completionType: CompletionType.git,
        ),
        'docker': CommandInfo(
          name: 'docker',
          description: 'Container platform',
          usage: 'docker <command> [options]',
          examples: ['docker ps', 'docker run ubuntu', 'docker build -t app .'],
          category: CommandCategory.containerization,
          completionType: CompletionType.docker,
        ),
        'npm': CommandInfo(
          name: 'npm',
          description: 'Node.js package manager',
          usage: 'npm <command> [package]',
          examples: ['npm install', 'npm run start', 'npm test'],
          category: CommandCategory.packageManager,
          completionType: CompletionType.npm,
        ),
        'kubectl': CommandInfo(
          name: 'kubectl',
          description: 'Kubernetes command line tool',
          usage: 'kubectl <command> [options]',
          examples: ['kubectl get pods', 'kubectl apply -f deployment.yaml'],
          category: CommandCategory.kubernetes,
          completionType: CompletionType.kubernetes,
        ),
      });
      
      // Load shell-specific completions
      await _loadShellCompletions();
      
      debugPrint('📚 Loaded ${_commandDatabase.length} commands in database');
    } catch (e) {
      debugPrint('⚠️ Failed to load command database: $e');
    }
  }
  
  /// Load shell-specific completions
  Future<void> _loadShellCompletions() async {
    try {
      switch (_currentShell) {
        case 'bash':
          await _loadBashCompletions();
          break;
        case 'zsh':
          await _loadZshCompletions();
          break;
        case 'fish':
          await _loadFishCompletions();
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load shell completions: $e');
    }
  }
  
  /// Load bash completions
  Future<void> _loadBashCompletions() async {
    try {
      // Try to read bash completion files
      final completionDirs = [
        '/usr/share/bash-completion/completions',
        '/etc/bash_completion.d',
        '${Platform.environment['HOME']}/.local/share/bash-completion/completions',
      ];
      
      for (final dir in completionDirs) {
        final directory = Directory(dir);
        if (await directory.exists()) {
          await _scanCompletionDirectory(directory);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load bash completions: $e');
    }
  }
  
  /// Load zsh completions
  Future<void> _loadZshCompletions() async {
    try {
      // Try to read zsh completion files
      final completionDirs = [
        '/usr/share/zsh/site-functions',
        '/usr/share/zsh/functions/Completion',
        '${Platform.environment['HOME']}/.zsh/completions',
      ];
      
      for (final dir in completionDirs) {
        final directory = Directory(dir);
        if (await directory.exists()) {
          await _scanCompletionDirectory(directory);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load zsh completions: $e');
    }
  }
  
  /// Load fish completions
  Future<void> _loadFishCompletions() async {
    try {
      // Try to read fish completion files
      final completionDir = Directory('${Platform.environment['HOME']}/.config/fish/completions');
      if (await completionDir.exists()) {
        await _scanCompletionDirectory(completionDir);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load fish completions: $e');
    }
  }
  
  /// Scan completion directory for completion files
  Future<void> _scanCompletionDirectory(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.completion')) {
          final completions = await _parseCompletionFile(entity);
          _commandCache.addAll(completions);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to scan completion directory: $e');
    }
  }
  
  /// Parse completion file
  Future<Map<String, List<String>>> _parseCompletionFile(File file) async {
    final completions = <String, List<String>>{};
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');
      
      String? currentCommand;
      for (final line in lines) {
        if (line.startsWith('complete ')) {
          final parts = line.split(' ');
          if (parts.length > 2) {
            currentCommand = parts[1];
            completions[currentCommand] = [];
          }
        } else if (currentCommand != null && line.trim().isNotEmpty) {
          completions[currentCommand]!.add(line.trim());
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to parse completion file: $e');
    }
    
    return completions;
  }
  
  /// Load user preferences
  Future<void> _loadUserPreferences() async {
    try {
      final prefsFile = File('${Platform.environment['HOME']}/.termisol_shell_prefs.json');
      if (await prefsFile.exists()) {
        final content = await prefsFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        // Load bookmarks
        final bookmarksData = data['bookmarks'] as Map<String, dynamic>?;
        if (bookmarksData != null) {
          _bookmarks.addAll(bookmarksData.cast<String, String>());
        }
        
        // Load command history
        final historyData = data['commandHistory'] as List<dynamic>?;
        if (historyData != null) {
          _commandHistory.addAll(historyData.cast<String>());
        }
        
        debugPrint('📂 Loaded user preferences');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load user preferences: $e');
    }
  }
  
  /// Setup shell hooks
  void _setupShellHooks() {
    _hooks['preexec'] = ShellHook(
      name: 'preexec',
      description: 'Executed before command',
      callback: _onPreExec,
    );
    
    _hooks['precmd'] = ShellHook(
      name: 'precmd',
      description: 'Executed before prompt',
      callback: _onPreCmd,
    );
    
    _hooks['chpwd'] = ShellHook(
      name: 'chpwd',
      description: 'Executed when directory changes',
      callback: _onChPwd,
    );
  }
  
  /// Get smart completions for current input
  Future<List<Completion>> getCompletions(String input) async {
    final completions = <Completion>[];
    
    try {
      final words = input.split(' ');
      final lastWord = words.isNotEmpty ? words.last : '';
      final command = words.isNotEmpty ? words.first : '';
      
      // Command completions
      if (words.length == 1 || (words.length == 2 && lastWord.isEmpty)) {
        completions.addAll(await _getCommandCompletions(command));
      }
      
      // Argument completions
      if (words.length > 1) {
        completions.addAll(await _getArgumentCompletions(command, words));
      }
      
      // File/directory completions
      if (_shouldCompleteFiles(command, words)) {
        completions.addAll(await _getFileCompletions(lastWord));
      }
      
      // Sort by relevance
      completions.sort((a, b) => _compareCompletions(a, b, input));
      
    } catch (e) {
      debugPrint('⚠️ Failed to get completions: $e');
    }
    
    return completions;
  }
  
  /// Get command completions
  Future<List<Completion>> _getCommandCompletions(String partial) async {
    final completions = <Completion>[];
    
    // Search command database
    for (final entry in _commandDatabase.entries) {
      if (entry.key.startsWith(partial)) {
        completions.add(Completion(
          text: entry.key,
          type: CompletionType.command,
          description: entry.value.description,
          category: entry.value.category,
        ));
      }
    }
    
    // Search command cache
    for (final entry in _commandCache.entries) {
      if (entry.key.startsWith(partial)) {
        for (final completion in entry.value) {
          completions.add(Completion(
            text: completion,
            type: CompletionType.argument,
          ));
        }
      }
    }
    
    return completions;
  }
  
  /// Get argument completions
  Future<List<Completion>> _getArgumentCompletions(String command, List<String> args) async {
    final completions = <Completion>[];
    final commandInfo = _commandDatabase[command];
    
    if (commandInfo != null) {
      switch (commandInfo.completionType) {
        case CompletionType.git:
          completions.addAll(await _getGitCompletions(args));
          break;
        case CompletionType.docker:
          completions.addAll(await _getDockerCompletions(args));
          break;
        case CompletionType.npm:
          completions.addAll(await _getNpmCompletions(args));
          break;
        case CompletionType.kubernetes:
          completions.addAll(await _getKubernetesCompletions(args));
          break;
        case CompletionType.file:
          completions.addAll(await _getFileCompletions(args.last));
          break;
        case CompletionType.directory:
          completions.addAll(await _getDirectoryCompletions(args.last));
          break;
        default:
          break;
      }
    }
    
    return completions;
  }
  
  /// Get Git completions
  Future<List<Completion>> _getGitCompletions(List<String> args) async {
    final completions = <Completion>[];
    
    if (args.length == 2) {
      // Git subcommands
      final gitCommands = [
        'status', 'add', 'commit', 'push', 'pull', 'branch', 'checkout',
        'merge', 'rebase', 'log', 'diff', 'stash', 'fetch', 'clone',
      ];
      
      for (final cmd in gitCommands) {
        if (cmd.startsWith(args.last)) {
          completions.add(Completion(
            text: cmd,
            type: CompletionType.git,
            description: 'Git $cmd command',
          ));
        }
      }
    }
    
    return completions;
  }
  
  /// Get Docker completions
  Future<List<Completion>> _getDockerCompletions(List<String> args) async {
    final completions = <Completion>[];
    
    if (args.length == 2) {
      // Docker subcommands
      final dockerCommands = [
        'ps', 'run', 'build', 'push', 'pull', 'images', 'rmi', 'rm',
        'exec', 'logs', 'stop', 'start', 'restart', 'network', 'volume',
      ];
      
      for (final cmd in dockerCommands) {
        if (cmd.startsWith(args.last)) {
          completions.add(Completion(
            text: cmd,
            type: CompletionType.docker,
            description: 'Docker $cmd command',
          ));
        }
      }
    }
    
    return completions;
  }
  
  /// Get npm completions
  Future<List<Completion>> _getNpmCompletions(List<String> args) async {
    final completions = <Completion>[];
    
    if (args.length == 2) {
      // npm subcommands
      final npmCommands = [
        'install', 'run', 'test', 'start', 'build', 'publish', 'update',
        'uninstall', 'ls', 'search', 'info', 'init', 'config',
      ];
      
      for (final cmd in npmCommands) {
        if (cmd.startsWith(args.last)) {
          completions.add(Completion(
            text: cmd,
            type: CompletionType.npm,
            description: 'npm $cmd command',
          ));
        }
      }
    }
    
    return completions;
  }
  
  /// Get Kubernetes completions
  Future<List<Completion>> _getKubernetesCompletions(List<String> args) async {
    final completions = <Completion>[];
    
    if (args.length == 2) {
      // kubectl subcommands
      final kubectlCommands = [
        'get', 'apply', 'delete', 'create', 'edit', 'replace', 'patch',
        'logs', 'exec', 'port-forward', 'proxy', 'cp', 'auth',
        'config', 'version', 'cluster-info', 'top', 'cordon', 'drain',
      ];
      
      for (final cmd in kubectlCommands) {
        if (cmd.startsWith(args.last)) {
          completions.add(Completion(
            text: cmd,
            type: CompletionType.kubernetes,
            description: 'kubectl $cmd command',
          ));
        }
      }
    }
    
    return completions;
  }
  
  /// Get file completions
  Future<List<Completion>> _getFileCompletions(String partial) async {
    final completions = <Completion>[];
    
    try {
      final currentDir = Directory(_currentWorkingDirectory ?? '.');
      await for (final entity in currentDir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith(partial)) {
          final isDirectory = entity is Directory;
          completions.add(Completion(
            text: name + (isDirectory ? '/' : ''),
            type: isDirectory ? CompletionType.directory : CompletionType.file,
            description: isDirectory ? 'Directory' : 'File',
          ));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get file completions: $e');
    }
    
    return completions;
  }
  
  /// Get directory completions
  Future<List<Completion>> _getDirectoryCompletions(String partial) async {
    final completions = <Completion>[];
    
    try {
      final currentDir = Directory(_currentWorkingDirectory ?? '.');
      await for (final entity in currentDir.list()) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          if (name.startsWith(partial)) {
            completions.add(Completion(
              text: name + '/',
              type: CompletionType.directory,
              description: 'Directory',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get directory completions: $e');
    }
    
    return completions;
  }
  
  /// Check if should complete files
  bool _shouldCompleteFiles(String command, List<String> args) {
    final commandInfo = _commandDatabase[command];
    return commandInfo?.completionType == CompletionType.file ||
           commandInfo?.completionType == CompletionType.directory;
  }
  
  /// Compare completions for sorting
  int _compareCompletions(Completion a, Completion b, String input) {
    // Priority by type
    final typePriority = {
      CompletionType.command: 1,
      CompletionType.argument: 2,
      CompletionType.file: 3,
      CompletionType.directory: 4,
    };
    
    final aPriority = typePriority[a.type] ?? 999;
    final bPriority = typePriority[b.type] ?? 999;
    
    if (aPriority != bPriority) {
      return aPriority.compareTo(bPriority);
    }
    
    // Then by frequency
    final aFreq = _commandFrequency[a.text] ?? 0;
    final bFreq = _commandFrequency[b.text] ?? 0;
    
    if (aFreq != bFreq) {
      return bFreq.compareTo(aFreq);
    }
    
    // Finally alphabetically
    return a.text.compareTo(b.text);
  }
  
  /// Get command suggestions based on history and frequency
  List<String> getCommandSuggestions(String partial) {
    final suggestions = <String>[];
    
    // Get from history
    for (final cmd in _commandHistory) {
      if (cmd.startsWith(partial) && !suggestions.contains(cmd)) {
        suggestions.add(cmd);
      }
    }
    
    // Sort by frequency and recency
    suggestions.sort((a, b) {
      final aFreq = _commandFrequency[a] ?? 0;
      final bFreq = _commandFrequency[b] ?? 0;
      
      if (aFreq != bFreq) {
        return bFreq.compareTo(aFreq);
      }
      
      final aTime = _lastUsedCommands[a] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = _lastUsedCommands[b] ?? DateTime.fromMillisecondsSinceEpoch(0);
      
      return bTime.compareTo(aTime);
    });
    
    return suggestions.take(10).toList();
  }
  
  /// Record command execution
  void recordCommand(String command) {
    // Add to history
    _commandHistory.add(command);
    if (_commandHistory.length > 1000) {
      _commandHistory.removeAt(0);
    }
    
    // Update frequency
    _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
    
    // Update last used
    _lastUsedCommands[command] = DateTime.now();
    
    debugPrint('📝 Recorded command: $command');
  }
  
  /// Update Git status
  Future<void> updateGitStatus() async {
    try {
      if (_currentWorkingDirectory == null) return;
      
      final result = await Process.run('git', ['status', '--porcelain'], 
        workingDirectory: _currentWorkingDirectory);
      
      if (result.exitCode == 0) {
        _parseGitStatus(result.stdout as String);
        
        // Get current branch
        final branchResult = await Process.run('git', ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: _currentWorkingDirectory);
        
        if (branchResult.exitCode == 0) {
          _gitBranch = (branchResult.stdout as String).trim();
        }
      } else {
        _gitStatus = GitStatus();
        _gitBranch = null;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update Git status: $e');
    }
  }
  
  /// Parse Git status output
  void _parseGitStatus(String output) {
    final lines = output.split('\n');
    int modified = 0;
    int added = 0;
    int deleted = 0;
    int untracked = 0;
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final status = line.substring(0, 2);
      if (status[0] == 'M' || status[1] == 'M') modified++;
      if (status[0] == 'A' || status[1] == 'A') added++;
      if (status[0] == 'D' || status[1] == 'D') deleted++;
      if (status[0] == '?' || status[1] == '?') untracked++;
    }
    
    _gitStatus = GitStatus(
      modified: modified,
      added: added,
      deleted: deleted,
      untracked: untracked,
      ahead: 0, // Would need 'git status --branch' for this
      behind: 0,
    );
  }
  
  /// Add directory bookmark
  void addBookmark(String name, String path) {
    _bookmarks[name] = path;
    debugPrint('📍 Added bookmark: $name -> $path');
  }
  
  /// Get directory bookmark
  String? getBookmark(String name) {
    return _bookmarks[name];
  }
  
  /// Remove directory bookmark
  void removeBookmark(String name) {
    _bookmarks.remove(name);
    debugPrint('🗑️ Removed bookmark: $name');
  }
  
  /// Get all bookmarks
  Map<String, String> getBookmarks() {
    return Map.unmodifiable(_bookmarks);
  }
  
  /// Execute shell hook
  void executeHook(String hookName, Map<String, dynamic> context) {
    final hook = _hooks[hookName];
    if (hook != null) {
      hook.callback(context);
    }
  }
  
  /// Hook callbacks
  void _onPreExec(Map<String, dynamic> context) {
    final command = context['command'] as String?;
    if (command != null) {
      recordCommand(command);
    }
  }
  
  void _onPreCmd(Map<String, dynamic> context) {
    // Update working directory
    updateWorkingDirectory();
    
    // Update Git status
    updateGitStatus();
  }
  
  void _onChPwd(Map<String, dynamic> context) {
    final newDir = context['directory'] as String?;
    if (newDir != null) {
      _currentWorkingDirectory = newDir;
      updateGitStatus();
    }
  }
  
  /// Update current working directory
  Future<void> updateWorkingDirectory() async {
    try {
      final result = await Process.run('pwd', []);
      if (result.exitCode == 0) {
        _currentWorkingDirectory = (result.stdout as String).trim();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update working directory: $e');
    }
  }
  
  /// Get command information
  CommandInfo? getCommandInfo(String command) {
    return _commandDatabase[command];
  }
  
  /// Save user preferences
  Future<void> saveUserPreferences() async {
    try {
      final prefsFile = File('${Platform.environment['HOME']}/.termisol_shell_prefs.json');
      final data = {
        'bookmarks': _bookmarks,
        'commandHistory': _commandHistory.take(1000).toList(),
        'commandFrequency': _commandFrequency,
        'lastUsedCommands': _lastUsedCommands.map((k, v) => MapEntry(k, v.toIso8601String())),
      };
      
      await prefsFile.writeAsString(jsonEncode(data));
      debugPrint('💾 Saved user preferences');
    } catch (e) {
      debugPrint('⚠️ Failed to save user preferences: $e');
    }
  }
  
  /// Dispose resources
  void dispose() {
    saveUserPreferences();
    _commandCache.clear();
    _commandDatabase.clear();
    _commandHistory.clear();
    _commandFrequency.clear();
    _lastUsedCommands.clear();
    _bookmarks.clear();
    _gitRepositories.clear();
    _hooks.clear();
    _isInitialized = false;
    debugPrint('🐚 Shell Integration disposed');
  }
}

/// Command information data structure
class CommandInfo {
  final String name;
  final String description;
  final String usage;
  final List<String> examples;
  final CommandCategory category;
  final CompletionType completionType;
  
  CommandInfo({
    required this.name,
    required this.description,
    required this.usage,
    required this.examples,
    required this.category,
    required this.completionType,
  });
}

/// Completion data structure
class Completion {
  final String text;
  final CompletionType type;
  final String? description;
  final CommandCategory? category;
  final int? priority;
  
  Completion({
    required this.text,
    required this.type,
    this.description,
    this.category,
    this.priority,
  });
}

/// Git status data structure
class GitStatus {
  int modified = 0;
  int added = 0;
  int deleted = 0;
  int untracked = 0;
  int ahead = 0;
  int behind = 0;
  bool hasConflicts = false;
  
  GitStatus({
    this.modified = 0,
    this.added = 0,
    this.deleted = 0,
    this.untracked = 0,
    this.ahead = 0,
    this.behind = 0,
    this.hasConflicts = false,
  });
  
  bool get hasChanges => modified + added + deleted + untracked > 0;
  bool get isClean => !hasChanges && !hasConflicts;
}

/// Git repository data structure
class GitRepository {
  final String path;
  final String remoteUrl;
  final String defaultBranch;
  final Map<String, GitBranch> branches;
  
  GitRepository({
    required this.path,
    required this.remoteUrl,
    required this.defaultBranch,
    required this.branches,
  });
}

/// Git branch data structure
class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;
  final String? upstream;
  
  GitBranch({
    required this.name,
    required this.isCurrent,
    required this.isRemote,
    this.upstream,
  });
}

/// Shell hook data structure
class ShellHook {
  final String name;
  final String description;
  final void Function(Map<String, dynamic>) callback;
  
  ShellHook({
    required this.name,
    required this.description,
    required this.callback,
  });
}

/// Command category enumeration
enum CommandCategory {
  fileSystem,
  textProcessing,
  network,
  system,
  development,
  versionControl,
  containerization,
  packageManager,
  kubernetes,
  database,
  security,
  monitoring,
}

/// Completion type enumeration
enum CompletionType {
  command,
  argument,
  file,
  directory,
  git,
  docker,
  npm,
  kubernetes,
  user,
  host,
  variable,
}
