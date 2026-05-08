import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

class ContextAwareSuggestions {
  static const int _maxSuggestions = 10;
  static const int _contextHistorySize = 50;
  static const int _suggestionUpdateInterval = 2000; // 2 seconds
  
  final List<CommandContext> _contextHistory = [];
  final Map<String, CommandPattern> _commandPatterns = {};
  final Map<String, FileContext> _fileContexts = {};
  final Map<String, ProjectContext> _projectContexts = {};
  
  Timer? _suggestionTimer;
  String? _currentDirectory;
  String? _currentSession;
  List<String> _recentFiles = [];
  
  final StreamController<SuggestionEvent> _suggestionController = 
      StreamController<SuggestionEvent>.broadcast();

  void initialize() {
    _startSuggestionTimer();
    _initializeCommandPatterns();
    developer.log('🧠 Context-Aware Suggestions initialized');
  }

  void _startSuggestionTimer() {
    _suggestionTimer = Timer.periodic(
      Duration(milliseconds: _suggestionUpdateInterval),
      (_) => _updateSuggestions(),
    );
  }

  void _initializeCommandPatterns() {
    // Initialize common command patterns
    _commandPatterns['git'] = CommandPattern(
      command: 'git',
      subcommands: ['status', 'add', 'commit', 'push', 'pull', 'branch', 'checkout', 'merge', 'log', 'diff'],
      contextPatterns: {
        'status': ['after changes', 'before commit'],
        'add': ['new files', 'modified files'],
        'commit': ['after add', 'before push'],
        'push': ['after commit', 'before pull'],
        'pull': ['before work', 'after push'],
      },
    );
    
    _commandPatterns['docker'] = CommandPattern(
      command: 'docker',
      subcommands: ['build', 'run', 'ps', 'stop', 'rm', 'images', 'exec'],
      contextPatterns: {
        'build': ['Dockerfile present', 'before run'],
        'run': ['after build', 'for testing'],
        'ps': ['check running containers'],
        'stop': ['cleanup', 'before rebuild'],
      },
    );
    
    _commandPatterns['npm'] = CommandPattern(
      command: 'npm',
      subcommands: ['install', 'run', 'test', 'build', 'start', 'dev'],
      contextPatterns: {
        'install': ['package.json present', 'new dependencies'],
        'run': ['after install', 'for scripts'],
        'test': ['before commit', 'quality check'],
      },
    );
  }

  void updateContext({
    String? currentDirectory,
    String? currentSession,
    List<String>? recentFiles,
    String? lastCommand,
    String? commandOutput,
  }) {
    if (currentDirectory != null) {
      _currentDirectory = currentDirectory;
      _analyzeDirectoryContext(currentDirectory);
    }
    
    if (currentSession != null) {
      _currentSession = currentSession;
    }
    
    if (recentFiles != null) {
      _recentFiles = recentFiles;
    }
    
    if (lastCommand != null) {
      _recordCommandContext(lastCommand, commandOutput);
    }
  }

  void _analyzeDirectoryContext(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return;
    
    // Check for project indicators
    final hasPackageJson = File('$directory/package.json').existsSync();
    final hasDockerfile = File('$directory/Dockerfile').existsSync();
    final hasGit = Directory('$directory/.git').existsSync();
    final hasCargo = File('$directory/Cargo.toml').existsSync();
    final hasPubspec = File('$directory/pubspec.yaml').existsSync();
    
    final projectType = _determineProjectType(
      hasPackageJson, hasDockerfile, hasGit, hasCargo, hasPubspec
    );
    
    final projectContext = ProjectContext(
      path: directory,
      type: projectType,
      hasGit: hasGit,
      hasDocker: hasDockerfile,
      hasPackageJson: hasPackageJson,
      hasCargo: hasCargo,
      hasPubspec: hasPubspec,
      lastAnalyzed: DateTime.now(),
    );
    
    _projectContexts[directory] = projectContext;
  }

  ProjectType _determineProjectType(bool hasPackageJson, bool hasDockerfile, 
                                   bool hasGit, bool hasCargo, bool hasPubspec) {
    if (hasPubspec) return ProjectType.dart;
    if (hasCargo) return ProjectType.rust;
    if (hasPackageJson) return ProjectType.nodejs;
    if (hasDockerfile) return ProjectType.docker;
    if (hasGit) return ProjectType.git;
    return ProjectType.general;
  }

  void _recordCommandContext(String command, String? output) {
    final context = CommandContext(
      command: command,
      output: output ?? '',
      timestamp: DateTime.now(),
      directory: _currentDirectory,
      session: _currentSession,
    );
    
    _contextHistory.add(context);
    
    if (_contextHistory.length > _contextHistorySize) {
      _contextHistory.removeAt(0);
    }
    
    _updateCommandPatterns(context);
  }

  void _updateCommandPatterns(CommandContext context) {
    final parts = context.command.split(' ');
    if (parts.isEmpty) return;
    
    final baseCommand = parts[0];
    final pattern = _commandPatterns[baseCommand];
    
    if (pattern != null) {
      pattern.recordUsage(context);
    }
  }

  List<CommandSuggestion> getSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    // Get directory-based suggestions
    suggestions.addAll(_getDirectorySuggestions(partialCommand));
    
    // Get pattern-based suggestions
    suggestions.addAll(_getPatternSuggestions(partialCommand));
    
    // Get file-based suggestions
    suggestions.addAll(_getFileSuggestions(partialCommand));
    
    // Get history-based suggestions
    suggestions.addAll(_getHistorySuggestions(partialCommand));
    
    // Sort by relevance and limit
    suggestions.sort((a, b) => b.relevance.compareTo(a.relevance));
    
    return suggestions.take(_maxSuggestions).toList();
  }

  List<CommandSuggestion> _getDirectorySuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    final projectContext = _currentDirectory != null 
        ? _projectContexts[_currentDirectory!] 
        : null;
    
    if (projectContext == null) return suggestions;
    
    // Project-specific suggestions
    switch (projectContext.type) {
      case ProjectType.nodejs:
        suggestions.addAll(_getNodeJSSuggestions(partialCommand));
        break;
      case ProjectType.dart:
        suggestions.addAll(_getDartSuggestions(partialCommand));
        break;
      case ProjectType.rust:
        suggestions.addAll(_getRustSuggestions(partialCommand));
        break;
      case ProjectType.docker:
        suggestions.addAll(_getDockerSuggestions(partialCommand));
        break;
      case ProjectType.git:
        suggestions.addAll(_getGitSuggestions(partialCommand));
        break;
      case ProjectType.general:
        suggestions.addAll(_getGeneralSuggestions(partialCommand));
        break;
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getNodeJSSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.startsWith('npm')) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'npm install',
          description: 'Install dependencies',
          relevance: 0.9,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'npm run dev',
          description: 'Start development server',
          relevance: 0.85,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'npm test',
          description: 'Run tests',
          relevance: 0.8,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'npm build',
          description: 'Build project',
          relevance: 0.75,
          type: SuggestionType.projectSpecific,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getDartSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.startsWith('flutter')) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'flutter run',
          description: 'Run Flutter app',
          relevance: 0.9,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'flutter build',
          description: 'Build Flutter app',
          relevance: 0.85,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'flutter test',
          description: 'Run Flutter tests',
          relevance: 0.8,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'dart pub get',
          description: 'Get dependencies',
          relevance: 0.75,
          type: SuggestionType.projectSpecific,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getRustSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.startsWith('cargo')) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'cargo build',
          description: 'Build Rust project',
          relevance: 0.9,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'cargo run',
          description: 'Run Rust project',
          relevance: 0.85,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'cargo test',
          description: 'Run Rust tests',
          relevance: 0.8,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'cargo check',
          description: 'Check Rust code',
          relevance: 0.75,
          type: SuggestionType.projectSpecific,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getDockerSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.startsWith('docker')) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'docker build -t app .',
          description: 'Build Docker image',
          relevance: 0.9,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'docker run -p 3000:3000 app',
          description: 'Run Docker container',
          relevance: 0.85,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'docker ps',
          description: 'List running containers',
          relevance: 0.8,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'docker-compose up',
          description: 'Start services with docker-compose',
          relevance: 0.75,
          type: SuggestionType.projectSpecific,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getGitSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.startsWith('git')) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'git status',
          description: 'Check git status',
          relevance: 0.9,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'git add .',
          description: 'Stage all changes',
          relevance: 0.85,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'git commit -m "message"',
          description: 'Commit changes',
          relevance: 0.8,
          type: SuggestionType.projectSpecific,
        ),
        CommandSuggestion(
          command: 'git push',
          description: 'Push to remote',
          relevance: 0.75,
          type: SuggestionType.projectSpecific,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getGeneralSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    if (partialCommand.isEmpty) {
      suggestions.addAll([
        CommandSuggestion(
          command: 'ls -la',
          description: 'List files with details',
          relevance: 0.8,
          type: SuggestionType.general,
        ),
        CommandSuggestion(
          command: 'pwd',
          description: 'Print working directory',
          relevance: 0.7,
          type: SuggestionType.general,
        ),
        CommandSuggestion(
          command: 'cd ..',
          description: 'Go to parent directory',
          relevance: 0.6,
          type: SuggestionType.general,
        ),
      ]);
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getPatternSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    // Get suggestions based on command patterns
    for (final entry in _commandPatterns.entries) {
      final pattern = entry.value;
      
      if (partialCommand.startsWith(pattern.command)) {
        suggestions.addAll(pattern.getSuggestions(partialCommand));
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getFileSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    // File completion suggestions
    if (_recentFiles.isNotEmpty) {
      for (final file in _recentFiles.take(5)) {
        if (file.toLowerCase().contains(partialCommand.toLowerCase())) {
          suggestions.add(CommandSuggestion(
            command: file,
            description: 'Recent file: $file',
            relevance: 0.6,
            type: SuggestionType.file,
          ));
        }
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getHistorySuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    // Get recent commands that match
    final recentCommands = _contextHistory.reversed
        .where((ctx) => ctx.command.toLowerCase().contains(partialCommand.toLowerCase()))
        .take(10);
    
    for (final context in recentCommands) {
      suggestions.add(CommandSuggestion(
        command: context.command,
        description: 'Recent command',
        relevance: 0.5,
        type: SuggestionType.history,
      ));
    }
    
    return suggestions;
  }

  void _updateSuggestions() {
    // Emit suggestion update event
    _suggestionController.add(SuggestionEvent(
      type: SuggestionEventType.updated,
      timestamp: DateTime.now(),
    ));
  }

  Stream<SuggestionEvent> get suggestionStream => _suggestionController.stream;

  ContextAwareSuggestionsStats getStats() {
    return ContextAwareSuggestionsStats(
      contextHistorySize: _contextHistory.length,
      commandPatternsCount: _commandPatterns.length,
      projectContextsCount: _projectContexts.length,
      fileContextsCount: _fileContexts.length,
      currentDirectory: _currentDirectory,
      currentSession: _currentSession,
    );
  }

  void dispose() {
    _suggestionTimer?.cancel();
    _suggestionController.close();
    _contextHistory.clear();
    _commandPatterns.clear();
    _fileContexts.clear();
    _projectContexts.clear();
    developer.log('🧠 Context-Aware Suggestions disposed');
  }
}

class CommandContext {
  final String command;
  final String output;
  final DateTime timestamp;
  final String? directory;
  final String? session;

  CommandContext({
    required this.command,
    required this.output,
    required this.timestamp,
    this.directory,
    this.session,
  });
}

class CommandPattern {
  final String command;
  final List<String> subcommands;
  final Map<String, List<String>> contextPatterns;
  int usageCount = 0;
  DateTime lastUsed = DateTime.now();

  CommandPattern({
    required this.command,
    required this.subcommands,
    required this.contextPatterns,
  });

  void recordUsage(CommandContext context) {
    usageCount++;
    lastUsed = context.timestamp;
  }

  List<CommandSuggestion> getSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    for (final subcommand in subcommands) {
      final fullCommand = '$command $subcommand';
      if (fullCommand.startsWith(partialCommand)) {
        suggestions.add(CommandSuggestion(
          command: fullCommand,
          description: 'Git $subcommand',
          relevance: 0.7,
          type: SuggestionType.pattern,
        ));
      }
    }
    
    return suggestions;
  }
}

class FileContext {
  final String path;
  final String type;
  final DateTime lastAccessed;
  final int accessCount;

  FileContext({
    required this.path,
    required this.type,
    required this.lastAccessed,
    required this.accessCount,
  });
}

class ProjectContext {
  final String path;
  final ProjectType type;
  final bool hasGit;
  final bool hasDocker;
  final bool hasPackageJson;
  final bool hasCargo;
  final bool hasPubspec;
  final DateTime lastAnalyzed;

  ProjectContext({
    required this.path,
    required this.type,
    required this.hasGit,
    required this.hasDocker,
    required this.hasPackageJson,
    required this.hasCargo,
    required this.hasPubspec,
    required this.lastAnalyzed,
  });
}

enum ProjectType {
  nodejs,
  dart,
  rust,
  docker,
  git,
  general,
}

class CommandSuggestion {
  final String command;
  final String description;
  final double relevance;
  final SuggestionType type;

  CommandSuggestion({
    required this.command,
    required this.description,
    required this.relevance,
    required this.type,
  });
}

enum SuggestionType {
  projectSpecific,
  pattern,
  file,
  history,
  general,
}

enum SuggestionEventType {
  updated,
  selected,
  dismissed,
}

class SuggestionEvent {
  final SuggestionEventType type;
  final DateTime timestamp;

  SuggestionEvent({
    required this.type,
    required this.timestamp,
  });
}

class ContextAwareSuggestionsStats {
  final int contextHistorySize;
  final int commandPatternsCount;
  final int projectContextsCount;
  final int fileContextsCount;
  final String? currentDirectory;
  final String? currentSession;

  ContextAwareSuggestionsStats({
    required this.contextHistorySize,
    required this.commandPatternsCount,
    required this.projectContextsCount,
    required this.fileContextsCount,
    this.currentDirectory,
    this.currentSession,
  });
}
