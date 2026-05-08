import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Personal command fingerprint system for AI
/// 
/// Features:
/// - Analyzes user's specific command patterns
/// - Learns from usage history
/// - Personalized AI training data
/// - Amnesia-proof persistence
/// - Context-aware suggestions
class PersonalCommandFingerprint {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<FingerprintEvent> _eventController = StreamController<FingerprintEvent>.broadcast();
  
  final List<CommandUsage> _commandHistory = [];
  final Map<String, CommandPattern> _patterns = {};
  final Map<String, double> _commandFrequency = {};
  final Map<String, List<TimeOfDay>> _timePatterns = {};
  final Map<String, ProjectContext> _projectContexts = {};
  
  Timer? _analysisTimer;
  Timer? _persistenceTimer;
  late SharedPreferences _prefs;
  
  Stream<FingerprintEvent> get events => _eventController.stream;
  bool _isInitialized = false;
  
  PersonalCommandFingerprint({this.aiAssistant});
  
  /// Initialize the fingerprint system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Start analysis timer
      _analysisTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _analyzePatterns();
      });
      
      // Start persistence timer
      _persistenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _persistData();
      });
      
      _isInitialized = true;
      
      _eventController.add(FingerprintEvent(
        type: FingerprintEventType.initialized,
        message: 'Personal command fingerprint system initialized',
        data: {'patterns_count': _patterns.length},
      ));
    } catch (e) {
      _eventController.add(FingerprintEvent(
        type: FingerprintEventType.error,
        message: 'Failed to initialize fingerprint system: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Record command usage
  void recordCommand(String command, String? workingDirectory, {String? project}) {
    final usage = CommandUsage(
      command: command,
      timestamp: DateTime.now(),
      workingDirectory: workingDirectory,
      project: project,
      context: _extractContext(command, workingDirectory),
    );
    
    _commandHistory.insert(0, usage);
    if (_commandHistory.length > 10000) {
      _commandHistory.removeLast();
    }
    
    // Update frequency
    _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
    
    // Update time patterns
    final now = TimeOfDay.fromDateTime(usage.timestamp);
    _timePatterns[command] = (_timePatterns[command] ?? [])..add(now);
    
    // Update project context
    if (project != null) {
      _projectContexts[project!] = ProjectContext(
        name: project!,
        lastUsed: usage.timestamp,
        commandCount: (_projectContexts[project!]?.commandCount ?? 0) + 1,
        commonCommands: _getProjectCommands(project!),
      );
    }
    
    _eventController.add(FingerprintEvent(
      type: FingerprintEventType.command_recorded,
      message: 'Command recorded for fingerprinting',
      data: {'command': command, 'project': project},
    ));
  }
  
  /// Extract context from command and directory
  CommandContext _extractContext(String command, String? workingDirectory) {
    final context = CommandContext();
    
    // Determine command type
    if (command.startsWith('git ')) {
      context.type = CommandType.git;
      context.subtype = _extractGitSubtype(command);
    } else if (command.startsWith('docker ')) {
      context.type = CommandType.docker;
      context.subtype = _extractDockerSubtype(command);
    } else if (command.startsWith('ssh ')) {
      context.type = CommandType.ssh;
      context.subtype = 'remote_access';
    } else if (command.contains('.py') || command.contains('python')) {
      context.type = CommandType.python;
    } else if (command.contains('.js') || command.contains('node')) {
      context.type = CommandType.node;
    } else if (command.contains('cd ')) {
      context.type = CommandType.navigation;
    } else if (RegExp(r'^\s*(ls|la|ll|dir)\s*$').hasMatch(command)) {
      context.type = CommandType.listing;
    } else {
      context.type = CommandType.system;
    }
    
    // Extract project from working directory
    if (workingDirectory != null) {
      context.project = _extractProjectFromPath(workingDirectory!);
      context.environment = _extractEnvironment(workingDirectory!);
    }
    
    return context;
  }
  
  String _extractGitSubtype(String command) {
    if (command.contains('commit')) return 'commit';
    if (command.contains('push')) return 'push';
    if (command.contains('pull')) return 'pull';
    if (command.contains('branch')) return 'branch';
    if (command.contains('merge')) return 'merge';
    if (command.contains('status')) return 'status';
    return 'other';
  }
  
  String _extractDockerSubtype(String command) {
    if (command.contains('run')) return 'run';
    if (command.contains('build')) return 'build';
    if (command.contains('push')) return 'push';
    if (command.contains('ps')) return 'list';
    if (command.contains('logs')) return 'logs';
    return 'other';
  }
  
  String _extractProjectFromPath(String path) {
    final parts = path.split('/');
    for (int i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part.isNotEmpty && !part.startsWith('.')) {
        // Check if it's a known project directory
        if (File('$path/pubspec.yaml').existsSync() ||
            File('$path/package.json').existsSync() ||
            File('$path/requirements.txt').existsSync() ||
            File('$path/go.mod').existsSync()) {
          return part;
        }
      }
    }
    return 'unknown';
  }
  
  String _extractEnvironment(String path) {
    if (path.contains('/home/house/termisol')) return 'development';
    if (path.contains('/home/house/Documents')) return 'documents';
    if (path.contains('/home/house/Downloads')) return 'downloads';
    if (path.contains('/tmp')) return 'temporary';
    if (path.contains('.233')) return 'server_233';
    if (path.contains('.250')) return 'server_250';
    return 'unknown';
  }
  
  /// Analyze patterns from command history
  void _analyzePatterns() {
    if (_commandHistory.isEmpty) return;
    
    // Analyze command sequences
    _analyzeCommandSequences();
    
    // Analyze time patterns
    _analyzeTimePatterns();
    
    // Analyze project patterns
    _analyzeProjectPatterns();
    
    // Update AI training data
    _updateAITrainingData();
  }
  
  void _analyzeCommandSequences() {
    final recentCommands = _commandHistory.take(50).toList();
    
    for (int i = 0; i < recentCommands.length - 2; i++) {
      final cmd1 = recentCommands[i].command;
      final cmd2 = recentCommands[i + 1].command;
      final cmd3 = recentCommands[i + 2].command;
      
      final sequence = '$cmd1 -> $cmd2 -> $cmd3';
      final pattern = CommandPattern(
        sequence: sequence,
        frequency: (_patterns[sequence]?.frequency ?? 0) + 1,
        confidence: _calculateSequenceConfidence(cmd1, cmd2, cmd3),
        context: recentCommands[i].context,
      );
      
      _patterns[sequence] = pattern;
    }
  }
  
  void _analyzeTimePatterns() {
    for (final entry in _commandFrequency.entries) {
      final command = entry.key;
      final times = _timePatterns[command] ?? [];
      
      if (times.isEmpty) continue;
      
      // Find most common time
      final hourCounts = <int, int>{};
      for (final time in times) {
        hourCounts[time.hour] = (hourCounts[time.hour] ?? 0) + 1;
      }
      
      final mostCommonHour = hourCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
      
      // Update pattern with time preference
      final existingPattern = _patterns[command];
      if (existingPattern != null) {
        existingPattern.preferredHour = mostCommonHour;
        existingPattern.timeConfidence = hourCounts[mostCommonHour]! / times.length;
      }
    }
  }
  
  void _analyzeProjectPatterns() {
    for (final entry in _projectContexts.entries) {
      final project = entry.key;
      final context = entry.value;
      
      // Analyze project-specific patterns
      final projectCommands = _getProjectCommands(project);
      final commonCommands = _findMostCommonCommands(projectCommands);
      
      context.commonCommands = commonCommands;
      context.commandPatterns = _analyzeProjectCommandPatterns(projectCommands);
    }
  }
  
  List<String> _getProjectCommands(String project) {
    return _commandHistory
        .where((usage) => usage.project == project)
        .map((usage) => usage.command)
        .take(100)
        .toList();
  }
  
  List<String> _findMostCommonCommands(List<String> commands) {
    final frequency = <String, int>{};
    for (final command in commands) {
      frequency[command] = (frequency[command] ?? 0) + 1;
    }
    
    return frequency.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        .take(10)
        .map((e) => e.key)
        .toList();
  }
  
  List<CommandPattern> _analyzeProjectCommandPatterns(List<String> commands) {
    final patterns = <CommandPattern>[];
    
    // Find common command pairs
    for (int i = 0; i < commands.length - 1; i++) {
      final pair = '${commands[i]} -> ${commands[i + 1]}';
      patterns.add(CommandPattern(
        sequence: pair,
        frequency: 1,
        confidence: 0.8,
        context: CommandContext(),
      ));
    }
    
    return patterns;
  }
  
  double _calculateSequenceConfidence(String cmd1, String cmd2, String cmd3) {
    double confidence = 0.0;
    
    // Check if commands are related
    if (_areCommandsRelated(cmd1, cmd2)) confidence += 0.3;
    if (_areCommandsRelated(cmd2, cmd3)) confidence += 0.3;
    
    // Check if sequence makes sense
    if (_isLogicalSequence(cmd1, cmd2, cmd3)) confidence += 0.4;
    
    return confidence.clamp(0.0, 1.0);
  }
  
  bool _areCommandsRelated(String cmd1, String cmd2) {
    // Check if commands are in the same domain
    final domains = [
      ['git', 'github', 'gitlab'],
      ['docker', 'podman', 'kubernetes'],
      ['python', 'pip', 'virtualenv'],
      ['node', 'npm', 'yarn'],
      ['cd', 'ls', 'pwd'],
    ];
    
    for (final domain in domains) {
      if (domain.any((cmd) => cmd1.contains(cmd)) &&
          domain.any((cmd) => cmd2.contains(cmd))) {
        return true;
      }
    }
    
    return false;
  }
  
  bool _isLogicalSequence(String cmd1, String cmd2, String cmd3) {
    // Check if the sequence makes logical sense
    if (cmd1.startsWith('cd ') && cmd2.startsWith('ls')) return true;
    if (cmd1.startsWith('git add ') && cmd2.startsWith('git commit')) return true;
    if (cmd1.startsWith('docker build') && cmd2.startsWith('docker run')) return true;
    if (cmd1.startsWith('ssh ') && cmd2.contains('cd ')) return true;
    
    return false;
  }
  
  /// Update AI training data
  void _updateAITrainingData() {
    if (aiAssistant == null) return;
    
    // Create personalized training data
    final trainingData = PersonalizedTrainingData(
      commandPatterns: _patterns.values.toList(),
      preferredCommands: _commandFrequency.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value))
          .take(50)
          .map((e) => e.key)
          .toList(),
      timePatterns: _timePatterns,
      projectContexts: _projectContexts,
      errorPatterns: _extractErrorPatterns(),
      successPatterns: _extractSuccessPatterns(),
    );
    
    // Send to AI for personalization
    _sendPersonalizationData(trainingData);
  }
  
  List<ErrorPattern> _extractErrorPatterns() {
    final errors = <ErrorPattern>[];
    
    for (final usage in _commandHistory) {
      if (usage.success == false) {
        errors.add(ErrorPattern(
          command: usage.command,
          error: usage.error ?? 'Unknown error',
          context: usage.context,
          frequency: 1,
          suggestedFix: _suggestFix(usage.command, usage.error),
        ));
      }
    }
    
    return errors;
  }
  
  List<SuccessPattern> _extractSuccessPatterns() {
    final successes = <SuccessPattern>[];
    
    for (final usage in _commandHistory) {
      if (usage.success == true) {
        successes.add(SuccessPattern(
          command: usage.command,
          context: usage.context,
          executionTime: usage.executionTime,
          frequency: 1,
        ));
      }
    }
    
    return successes;
  }
  
  String _suggestFix(String command, String? error) {
    // Suggest fixes based on personal patterns
    if (error?.contains('permission denied') == true) {
      return 'Try: sudo $command';
    }
    if (error?.contains('command not found') == true) {
      return 'Check if command is installed or in PATH';
    }
    if (error?.contains('No such file') == true) {
      return 'Check file path and permissions';
    }
    
    return 'Review command syntax and arguments';
  }
  
  void _sendPersonalizationData(PersonalizedTrainingData data) {
    // This would send data to AI for personalization
    _eventController.add(FingerprintEvent(
      type: FingerprintEventType.personalization_updated,
      message: 'Personalization data sent to AI',
      data: {'patterns_count': data.commandPatterns.length},
    ));
  }
  
  /// Get personalized command suggestions
  Future<List<String>> getPersonalizedSuggestions(String partialCommand, {String? project}) async {
    final suggestions = <String>[];
    
    // Get frequency-based suggestions
    final frequencySuggestions = _commandFrequency.keys
        .where((cmd) => cmd.startsWith(partialCommand))
        .toList()
      ..sort((a, b) => (_commandFrequency[b] ?? 0).compareTo(_commandFrequency[a] ?? 0));
    
    suggestions.addAll(frequencySuggestions.take(5));
    
    // Get pattern-based suggestions
    final patternSuggestions = _patterns.values
        .where((pattern) => pattern.sequence.startsWith(partialCommand))
        .map((pattern) => pattern.sequence.split(' -> ').first)
        .toList();
    
    suggestions.addAll(patternSuggestions.take(3));
    
    // Get project-specific suggestions
    if (project != null && _projectContexts.containsKey(project)) {
      final projectSuggestions = _projectContexts[project]!.commonCommands
          .where((cmd) => cmd.startsWith(partialCommand))
          .take(3);
      suggestions.addAll(projectSuggestions);
    }
    
    // Get AI-powered suggestions
    if (aiAssistant != null) {
      try {
        final aiSuggestions = await _getAISuggestions(partialCommand, project);
        suggestions.addAll(aiSuggestions.take(2));
      } catch (e) {
        debugPrint('❌ AI suggestions failed: $e');
      }
    }
    
    // Remove duplicates and return
    return suggestions.toSet().toList();
  }
  
  Future<List<String>> _getAISuggestions(String partialCommand, String? project) async {
    if (aiAssistant == null) return [];
    
    final prompt = '''Based on my personal command patterns and preferences:

Current partial command: $partialCommand
Current project: ${project ?? 'None'}

My most used commands: ${_commandFrequency.entries.take(10).map((e) => '${e.key} (${e.value} times)').join(', ')}

My common patterns: ${_patterns.values.take(5).map((p) => p.sequence).join(', ')}

Suggest 2-3 commands that would complete this partial command based on MY personal usage patterns.''';
    
    try {
      final response = await aiAssistant!.explainCommand(prompt);
      return response.split('\n').where((line) => line.trim().isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Get personal statistics
  Map<String, dynamic> getPersonalStatistics() {
    return {
      'total_commands': _commandHistory.length,
      'unique_commands': _commandFrequency.length,
      'most_used_command': _commandFrequency.entries.isNotEmpty 
          ? _commandFrequency.entries.reduce((a, b) => a.value > b.value ? a : b).key 
          : null,
      'patterns_count': _patterns.length,
      'projects_count': _projectContexts.length,
      'peak_usage_hour': _getPeakUsageHour(),
      'preferred_worktimes': _getPreferredWorkTimes(),
      'command_categories': _getCommandCategories(),
    };
  }
  
  int _getPeakUsageHour() {
    final hourCounts = <int, int>{};
    
    for (final usage in _commandHistory) {
      final hour = usage.timestamp.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
    
    return hourCounts.entries.isNotEmpty
        ? hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : 12; // Default to noon
  }
  
  List<String> _getPreferredWorkTimes() {
    final hourCounts = <int, int>{};
    
    for (final usage in _commandHistory) {
      final hour = usage.timestamp.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
    
    return hourCounts.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        .take(3)
        .map((e) => '${e.key}:00-${e.key + 1}:00')
        .toList();
  }
  
  Map<String, int> _getCommandCategories() {
    final categories = <String, int>{};
    
    for (final usage in _commandHistory) {
      final category = usage.context.type.toString();
      categories[category] = (categories[category] ?? 0) + 1;
    }
    
    return categories;
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load command history
      final historyJson = _prefs.getString('command_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      _commandHistory.clear();
      for (final item in historyList) {
        _commandHistory.add(CommandUsage.fromJson(item));
      }
      
      // Load patterns
      final patternsJson = _prefs.getString('command_patterns') ?? '{}';
      final patternsMap = jsonDecode(patternsJson) as Map;
      _patterns.clear();
      for (final entry in patternsMap.entries) {
        _patterns[entry.key] = CommandPattern.fromJson(entry.value);
      }
      
      // Load frequency
      final frequencyJson = _prefs.getString('command_frequency') ?? '{}';
      final frequencyMap = jsonDecode(frequencyJson) as Map;
      _commandFrequency.clear();
      for (final entry in frequencyMap.entries) {
        _commandFrequency[entry.key] = entry.value as double;
      }
      
      // Load project contexts
      final projectsJson = _prefs.getString('project_contexts') ?? '{}';
      final projectsMap = jsonDecode(projectsJson) as Map;
      _projectContexts.clear();
      for (final entry in projectsMap.entries) {
        _projectContexts[entry.key] = ProjectContext.fromJson(entry.value);
      }
      
      _eventController.add(FingerprintEvent(
        type: FingerprintEventType.data_loaded,
        message: 'Persisted fingerprint data loaded',
        data: {
          'commands_loaded': _commandHistory.length,
          'patterns_loaded': _patterns.length,
        },
      ));
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save command history
      final historyJson = jsonEncode(_commandHistory.take(1000).map((u) => u.toJson()).toList());
      await _prefs.setString('command_history', historyJson);
      
      // Save patterns
      final patternsJson = jsonEncode(_patterns.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('command_patterns', patternsJson);
      
      // Save frequency
      final frequencyJson = jsonEncode(_commandFrequency);
      await _prefs.setString('command_frequency', frequencyJson);
      
      // Save project contexts
      final projectsJson = jsonEncode(_projectContexts.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('project_contexts', projectsJson);
      
    } catch (e) {
      debugPrint('❌ Failed to persist data: $e');
    }
  }
  
  /// Clear all personal data
  Future<void> clearPersonalData() async {
    _commandHistory.clear();
    _patterns.clear();
    _commandFrequency.clear();
    _timePatterns.clear();
    _projectContexts.clear();
    
    await _prefs.clear();
    
    _eventController.add(FingerprintEvent(
      type: FingerprintEventType.data_cleared,
      message: 'All personal fingerprint data cleared',
      data: {},
    ));
  }
  
  /// Dispose
  void dispose() {
    _analysisTimer?.cancel();
    _persistenceTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Command usage record
class CommandUsage {
  final String command;
  final DateTime timestamp;
  final String? workingDirectory;
  final String? project;
  final CommandContext context;
  final bool? success;
  final String? error;
  final Duration? executionTime;
  
  CommandUsage({
    required this.command,
    required this.timestamp,
    this.workingDirectory,
    this.project,
    required this.context,
    this.success,
    this.error,
    this.executionTime,
  });
  
  Map<String, dynamic> toJson() => {
    'command': command,
    'timestamp': timestamp.toIso8601String(),
    'working_directory': workingDirectory,
    'project': project,
    'context': context.toJson(),
    'success': success,
    'error': error,
    'execution_time_ms': executionTime?.inMilliseconds,
  };
  
  factory CommandUsage.fromJson(Map<String, dynamic> json) {
    return CommandUsage(
      command: json['command'],
      timestamp: DateTime.parse(json['timestamp']),
      workingDirectory: json['working_directory'],
      project: json['project'],
      context: CommandContext.fromJson(json['context']),
      success: json['success'],
      error: json['error'],
      executionTime: json['execution_time_ms'] != null 
          ? Duration(milliseconds: json['execution_time_ms'])
          : null,
    );
  }
}

/// Command context
class CommandContext {
  CommandType type = CommandType.system;
  String? subtype;
  String? project;
  String? environment;
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'subtype': subtype,
    'project': project,
    'environment': environment,
  };
  
  factory CommandContext.fromJson(Map<String, dynamic> json) {
    return CommandContext()
      ..type = CommandType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => CommandType.system,
      )
      ..subtype = json['subtype']
      ..project = json['project']
      ..environment = json['environment'];
  }
}

/// Command types
enum CommandType {
  git,
  docker,
  ssh,
  python,
  node,
  navigation,
  listing,
  system,
}

/// Command pattern
class CommandPattern {
  final String sequence;
  double frequency;
  double confidence;
  CommandContext context;
  int? preferredHour;
  double? timeConfidence;
  
  CommandPattern({
    required this.sequence,
    required this.frequency,
    required this.confidence,
    required this.context,
    this.preferredHour,
    this.timeConfidence,
  });
  
  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'frequency': frequency,
    'confidence': confidence,
    'context': context.toJson(),
    'preferred_hour': preferredHour,
    'time_confidence': timeConfidence,
  };
  
  factory CommandPattern.fromJson(Map<String, dynamic> json) {
    return CommandPattern(
      sequence: json['sequence'],
      frequency: json['frequency'],
      confidence: json['confidence'],
      context: CommandContext.fromJson(json['context']),
      preferredHour: json['preferred_hour'],
      timeConfidence: json['time_confidence'],
    );
  }
}

/// Project context
class ProjectContext {
  final String name;
  final DateTime lastUsed;
  final int commandCount;
  List<String> commonCommands = [];
  List<CommandPattern> commandPatterns = [];
  
  ProjectContext({
    required this.name,
    required this.lastUsed,
    required this.commandCount,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'last_used': lastUsed.toIso8601String(),
    'command_count': commandCount,
    'common_commands': commonCommands,
    'command_patterns': commandPatterns.map((p) => p.toJson()).toList(),
  };
  
  factory ProjectContext.fromJson(Map<String, dynamic> json) {
    return ProjectContext(
      name: json['name'],
      lastUsed: DateTime.parse(json['last_used']),
      commandCount: json['command_count'],
    )
      ..commonCommands = List<String>.from(json['common_commands'] ?? [])
      ..commandPatterns = (json['command_patterns'] as List?)
          ?.map((p) => CommandPattern.fromJson(p))
          .toList() ?? [];
  }
}

/// Error pattern
class ErrorPattern {
  final String command;
  final String error;
  final CommandContext context;
  int frequency;
  String suggestedFix;
  
  ErrorPattern({
    required this.command,
    required this.error,
    required this.context,
    required this.frequency,
    required this.suggestedFix,
  });
}

/// Success pattern
class SuccessPattern {
  final String command;
  final CommandContext context;
  final Duration executionTime;
  int frequency;
  
  SuccessPattern({
    required this.command,
    required this.context,
    required this.executionTime,
    required this.frequency,
  });
}

/// Personalized training data
class PersonalizedTrainingData {
  final List<CommandPattern> commandPatterns;
  final List<String> preferredCommands;
  final Map<String, List<TimeOfDay>> timePatterns;
  final Map<String, ProjectContext> projectContexts;
  final List<ErrorPattern> errorPatterns;
  final List<SuccessPattern> successPatterns;
  
  PersonalizedTrainingData({
    required this.commandPatterns,
    required this.preferredCommands,
    required this.timePatterns,
    required this.projectContexts,
    required this.errorPatterns,
    required this.successPatterns,
  });
}

/// Fingerprint event types
enum FingerprintEventType {
  initialized,
  command_recorded,
  data_loaded,
  data_cleared,
  personalization_updated,
  error,
}

/// Fingerprint event
class FingerprintEvent {
  final FingerprintEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  FingerprintEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
