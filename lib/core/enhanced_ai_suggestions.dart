import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../ai/ai_terminal_assistant.dart';
import 'terminal_session.dart';

/// Enhanced AI Suggestions System
///
/// Provides proactive command predictions, context-aware recommendations,
/// and intelligent completions based on user behavior and project context.
class EnhancedAISuggestions {
  final AITerminalAssistant _aiAssistant;
  final StreamController<AISuggestion> _suggestionController =
      StreamController<AISuggestion>.broadcast();

  Stream<AISuggestion> get suggestions => _suggestionController.stream;

  final List<String> _commandHistory = [];
  final Map<String, CommandPattern> _learnedPatterns = {};
  final Map<String, ProjectContext> _projectContexts = {};
  final Map<String, UserBehavior> _userBehavior = {};

  bool _isActive = false;
  bool get isActive => _isActive;

  String? _currentProject;
  String? _currentDirectory;
  List<String>? _recentFiles;

  EnhancedAISuggestions(this._aiAssistant);

  /// Initialize the enhanced AI suggestions system
  Future<void> initialize() async {
    if (_isActive) return;

    await _aiAssistant.initialize();

    _isActive = true;
    debugPrint('🧠 Enhanced AI Suggestions initialized');
  }

  /// Get proactive suggestions for current context
  Future<List<AISuggestion>> getProactiveSuggestions({
    String? currentInput,
    String? currentDirectory,
    String? projectType,
    List<String>? recentCommands,
    List<String>? openFiles,
  }) async {
    if (!_isActive) return [];

    final suggestions = <AISuggestion>[];

    // Update context
    _currentDirectory = currentDirectory;
    _recentFiles = openFiles;

    // Pattern-based suggestions
    final patternSuggestions = await _getPatternSuggestions(currentInput);
    suggestions.addAll(patternSuggestions);

    // Context-aware suggestions
    final contextSuggestions = await _getContextSuggestions(
      currentInput,
      projectType,
      recentCommands,
    );
    suggestions.addAll(contextSuggestions);

    // AI-powered predictions
    final aiSuggestions = await _getAIPredictions(currentInput, recentCommands);
    suggestions.addAll(aiSuggestions);

    // Behavioral suggestions
    final behaviorSuggestions = _getBehavioralSuggestions(currentInput);
    suggestions.addAll(behaviorSuggestions);

    // Rank and filter suggestions
    final rankedSuggestions = _rankAndFilterSuggestions(suggestions);

    return rankedSuggestions.take(5).toList();
  }

  /// Get pattern-based suggestions
  Future<List<AISuggestion>> _getPatternSuggestions(String? currentInput) async {
    final suggestions = <AISuggestion>[];

    if (currentInput == null || currentInput.isEmpty) {
      // Suggest common starting commands
      suggestions.addAll([
        AISuggestion(
          type: SuggestionType.command,
          content: 'git status',
          confidence: 0.8,
          reason: 'Check repository status',
          category: 'git',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'ls -la',
          confidence: 0.7,
          reason: 'List all files with details',
          category: 'filesystem',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'pwd',
          confidence: 0.6,
          reason: 'Show current directory',
          category: 'filesystem',
        ),
      ]);
      return suggestions;
    }

    // Command completion patterns
    final lowerInput = currentInput.toLowerCase();

    if (lowerInput.startsWith('git ')) {
      suggestions.addAll(await _getGitSuggestions(currentInput));
    } else if (lowerInput.startsWith('npm ')) {
      suggestions.addAll(await _getNpmSuggestions(currentInput));
    } else if (lowerInput.startsWith('docker ')) {
      suggestions.addAll(await _getDockerSuggestions(currentInput));
    } else if (lowerInput.startsWith('cd ')) {
      suggestions.addAll(_getDirectorySuggestions(currentInput));
    }

    return suggestions;
  }

  /// Get Git-specific suggestions
  Future<List<AISuggestion>> _getGitSuggestions(String input) async {
    final suggestions = <AISuggestion>[];

    if (input == 'git ') {
      suggestions.addAll([
        AISuggestion(
          type: SuggestionType.command,
          content: 'git status',
          confidence: 0.9,
          reason: 'Check working directory status',
          category: 'git',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'git add .',
          confidence: 0.8,
          reason: 'Stage all changes',
          category: 'git',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'git commit -m ""',
          confidence: 0.8,
          reason: 'Commit staged changes',
          category: 'git',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'git pull',
          confidence: 0.7,
          reason: 'Pull latest changes',
          category: 'git',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'git push',
          confidence: 0.7,
          reason: 'Push local commits',
          category: 'git',
        ),
      ]);
    } else if (input == 'git add ') {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: 'git add .',
        confidence: 0.9,
        reason: 'Stage all changes in current directory',
        category: 'git',
      ));
    } else if (input == 'git commit ') {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: 'git commit -m "feat: add new feature"',
        confidence: 0.8,
        reason: 'Commit with conventional message',
        category: 'git',
      ));
    }

    return suggestions;
  }

  /// Get NPM-specific suggestions
  Future<List<AISuggestion>> _getNpmSuggestions(String input) async {
    final suggestions = <AISuggestion>[];

    if (input == 'npm ') {
      suggestions.addAll([
        AISuggestion(
          type: SuggestionType.command,
          content: 'npm install',
          confidence: 0.9,
          reason: 'Install dependencies',
          category: 'npm',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'npm run dev',
          confidence: 0.8,
          reason: 'Start development server',
          category: 'npm',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'npm test',
          confidence: 0.8,
          reason: 'Run test suite',
          category: 'npm',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'npm run build',
          confidence: 0.7,
          reason: 'Build for production',
          category: 'npm',
        ),
      ]);
    }

    return suggestions;
  }

  /// Get Docker-specific suggestions
  Future<List<AISuggestion>> _getDockerSuggestions(String input) async {
    final suggestions = <AISuggestion>[];

    if (input == 'docker ') {
      suggestions.addAll([
        AISuggestion(
          type: SuggestionType.command,
          content: 'docker ps',
          confidence: 0.9,
          reason: 'List running containers',
          category: 'docker',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'docker images',
          confidence: 0.8,
          reason: 'List Docker images',
          category: 'docker',
        ),
        AISuggestion(
          type: SuggestionType.command,
          content: 'docker build -t myapp .',
          confidence: 0.7,
          reason: 'Build Docker image',
          category: 'docker',
        ),
      ]);
    }

    return suggestions;
  }

  /// Get directory navigation suggestions
  List<AISuggestion> _getDirectorySuggestions(String input) {
    final suggestions = <AISuggestion>[];

    // Common directory patterns
    suggestions.addAll([
      AISuggestion(
        type: SuggestionType.command,
        content: 'cd ..',
        confidence: 0.8,
        reason: 'Go up one directory',
        category: 'filesystem',
      ),
      AISuggestion(
        type: SuggestionType.command,
        content: 'cd ~',
        confidence: 0.7,
        reason: 'Go to home directory',
        category: 'filesystem',
      ),
    ]);

    // Add recent directories if available
    if (_recentFiles != null) {
      final dirs = _recentFiles!
          .map((file) => file.substring(0, file.lastIndexOf('/')))
          .where((dir) => dir.isNotEmpty)
          .toSet()
          .take(3);

      for (final dir in dirs) {
        suggestions.add(AISuggestion(
          type: SuggestionType.command,
          content: 'cd $dir',
          confidence: 0.6,
          reason: 'Navigate to recently used directory',
          category: 'filesystem',
        ));
      }
    }

    return suggestions;
  }

  /// Get context-aware suggestions
  Future<List<AISuggestion>> _getContextSuggestions(
    String? currentInput,
    String? projectType,
    List<String>? recentCommands,
  ) async {
    final suggestions = <AISuggestion>[];

    // Project-specific suggestions
    if (projectType != null) {
      final projectSuggestions = await _getProjectSuggestions(projectType, currentInput);
      suggestions.addAll(projectSuggestions);
    }

    // Workflow continuation suggestions
    if (recentCommands != null && recentCommands.isNotEmpty) {
      final workflowSuggestions = _getWorkflowSuggestions(recentCommands, currentInput);
      suggestions.addAll(workflowSuggestions);
    }

    return suggestions;
  }

  /// Get project-specific suggestions
  Future<List<AISuggestion>> _getProjectSuggestions(String projectType, String? currentInput) async {
    final suggestions = <AISuggestion>[];

    switch (projectType.toLowerCase()) {
      case 'flutter':
        if (currentInput == null || currentInput.isEmpty) {
          suggestions.addAll([
            AISuggestion(
              type: SuggestionType.command,
              content: 'flutter run',
              confidence: 0.9,
              reason: 'Run Flutter app',
              category: 'flutter',
            ),
            AISuggestion(
              type: SuggestionType.command,
              content: 'flutter build apk',
              confidence: 0.8,
              reason: 'Build Android APK',
              category: 'flutter',
            ),
            AISuggestion(
              type: SuggestionType.command,
              content: 'flutter pub get',
              confidence: 0.8,
              reason: 'Get dependencies',
              category: 'flutter',
            ),
          ]);
        }
        break;

      case 'react':
      case 'nodejs':
        if (currentInput == null || currentInput.isEmpty) {
          suggestions.addAll([
            AISuggestion(
              type: SuggestionType.command,
              content: 'npm start',
              confidence: 0.9,
              reason: 'Start development server',
              category: 'nodejs',
            ),
            AISuggestion(
              type: SuggestionType.command,
              content: 'npm run build',
              confidence: 0.8,
              reason: 'Build for production',
              category: 'nodejs',
            ),
          ]);
        }
        break;

      case 'python':
        if (currentInput == null || currentInput.isEmpty) {
          suggestions.addAll([
            AISuggestion(
              type: SuggestionType.command,
              content: 'python main.py',
              confidence: 0.8,
              reason: 'Run main Python script',
              category: 'python',
            ),
            AISuggestion(
              type: SuggestionType.command,
              content: 'pip install -r requirements.txt',
              confidence: 0.8,
              reason: 'Install Python dependencies',
              category: 'python',
            ),
          ]);
        }
        break;
    }

    return suggestions;
  }

  /// Get workflow continuation suggestions
  List<AISuggestion> _getWorkflowSuggestions(List<String> recentCommands, String? currentInput) {
    final suggestions = <AISuggestion>[];

    if (recentCommands.length < 2) return suggestions;

    // Look for common workflow patterns
    final lastCommand = recentCommands.last.toLowerCase();

    if (lastCommand.contains('git add') && !recentCommands.any((c) => c.contains('git commit'))) {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: 'git commit -m "feat: update files"',
        confidence: 0.9,
        reason: 'Continue git workflow after staging',
        category: 'git',
      ));
    }

    if (lastCommand.contains('git commit') && !recentCommands.any((c) => c.contains('git push'))) {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: 'git push',
        confidence: 0.8,
        reason: 'Push committed changes',
        category: 'git',
      ));
    }

    if (lastCommand.contains('npm install') && !recentCommands.any((c) => c.contains('npm run'))) {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: 'npm run dev',
        confidence: 0.7,
        reason: 'Start development after installing dependencies',
        category: 'npm',
      ));
    }

    return suggestions;
  }

  /// Get AI-powered predictions
  Future<List<AISuggestion>> _getAIPredictions(String? currentInput, List<String>? recentCommands) async {
    final suggestions = <AISuggestion>[];

    if (currentInput == null || currentInput.isEmpty) return suggestions;

    try {
      // Use AI to predict next command
      final prediction = await _aiAssistant.predictCommand(currentInput, recentCommands ?? []);

      if (prediction.isNotEmpty && prediction != currentInput) {
        suggestions.add(AISuggestion(
          type: SuggestionType.command,
          content: prediction,
          confidence: 0.7,
          reason: 'AI-predicted next command',
          category: 'ai',
        ));
      }

      // Get AI-powered explanation for current input
      if (currentInput.length > 3) {
        final explanation = await _aiAssistant.explainCommand(currentInput);
        if (explanation.isNotEmpty) {
          suggestions.add(AISuggestion(
            type: SuggestionType.explanation,
            content: explanation,
            confidence: 0.6,
            reason: 'Command explanation',
            category: 'ai',
          ));
        }
      }
    } catch (e) {
      debugPrint('⚠️ AI prediction failed: $e');
    }

    return suggestions;
  }

  /// Get behavioral suggestions based on user patterns
  List<AISuggestion> _getBehavioralSuggestions(String? currentInput) {
    final suggestions = <AISuggestion>[];

    if (_userBehavior.isEmpty) return suggestions;

    // Find patterns in user behavior
    final userPatterns = _userBehavior.values
        .where((behavior) => behavior.favoriteCommands.isNotEmpty)
        .expand((behavior) => behavior.favoriteCommands)
        .toList();

    // Suggest frequently used commands
    final frequentCommands = <String, int>{};
    for (final cmd in userPatterns) {
      frequentCommands[cmd] = (frequentCommands[cmd] ?? 0) + 1;
    }

    final sortedCommands = frequentCommands.entries
        .where((entry) => entry.value > 2) // Used more than twice
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedCommands.take(3)) {
      suggestions.add(AISuggestion(
        type: SuggestionType.command,
        content: entry.key,
        confidence: 0.6,
        reason: 'Frequently used command',
        category: 'behavior',
      ));
    }

    return suggestions;
  }

  /// Rank and filter suggestions
  List<AISuggestion> _rankAndFilterSuggestions(List<AISuggestion> suggestions) {
    // Remove duplicates
    final uniqueSuggestions = <String, AISuggestion>{};
    for (final suggestion in suggestions) {
      final key = '${suggestion.type}_${suggestion.content}';
      if (!uniqueSuggestions.containsKey(key) ||
          uniqueSuggestions[key]!.confidence < suggestion.confidence) {
        uniqueSuggestions[key] = suggestion;
      }
    }

    // Sort by confidence
    final sorted = uniqueSuggestions.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return sorted;
  }

  /// Add command to history and learn patterns
  void addCommandToHistory(String command) {
    _commandHistory.add(command);
    if (_commandHistory.length > 1000) {
      _commandHistory.removeAt(0);
    }

    // Learn user behavior
    _learnUserBehavior(command);
  }

  /// Learn user behavior patterns
  void _learnUserBehavior(String command) {
    final userId = 'default'; // Could be based on session/user

    if (!_userBehavior.containsKey(userId)) {
      _userBehavior[userId] = UserBehavior();
    }

    final behavior = _userBehavior[userId]!;
    behavior.addCommand(command);
  }

  /// Update project context
  void updateProjectContext(String projectType, {String? rootDirectory, List<String>? keyFiles}) {
    _projectContexts[projectType] = ProjectContext(
      type: projectType,
      rootDirectory: rootDirectory,
      keyFiles: keyFiles ?? [],
      lastUsed: DateTime.now(),
    );
  }

  /// Get suggestion statistics
  Map<String, dynamic> getSuggestionStats() {
    return {
      'total_suggestions_generated': _suggestionController.stream.length,
      'learned_patterns': _learnedPatterns.length,
      'project_contexts': _projectContexts.length,
      'command_history_size': _commandHistory.length,
    };
  }

  /// Dispose resources
  void dispose() {
    _suggestionController.close();
    _isActive = false;
  }
}

/// Suggestion types
enum SuggestionType {
  command,
  explanation,
  correction,
  workflow,
}

/// AI suggestion data structure
class AISuggestion {
  final SuggestionType type;
  final String content;
  final double confidence;
  final String reason;
  final String category;
  final DateTime timestamp;

  AISuggestion({
    required this.type,
    required this.content,
    required this.confidence,
    required this.reason,
    required this.category,
  }) : timestamp = DateTime.now();

  @override
  String toString() => '$content (confidence: ${(confidence * 100).round()}%)';
}

/// Command pattern for learning
class CommandPattern {
  final String trigger;
  final List<String> followUps;
  final int frequency;

  CommandPattern({
    required this.trigger,
    required this.followUps,
    required this.frequency,
  });
}

/// Project context information
class ProjectContext {
  final String type;
  final String? rootDirectory;
  final List<String> keyFiles;
  final DateTime lastUsed;

  ProjectContext({
    required this.type,
    this.rootDirectory,
    required this.keyFiles,
    required this.lastUsed,
  });
}

/// User behavior tracking
class UserBehavior {
  final Map<String, int> commandFrequency = {};
  final List<String> recentCommands = [];
  final Map<String, DateTime> lastUsedCommands = {};

  List<String> get favoriteCommands {
    return commandFrequency.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) => commandFrequency[b]!.compareTo(commandFrequency[a]!));
  }

  void addCommand(String command) {
    commandFrequency[command] = (commandFrequency[command] ?? 0) + 1;
    lastUsedCommands[command] = DateTime.now();

    recentCommands.add(command);
    if (recentCommands.length > 50) {
      recentCommands.removeAt(0);
    }
  }
}