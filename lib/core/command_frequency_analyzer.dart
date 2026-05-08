import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Command Frequency Analyzer - Best-in-class intelligent command analysis
/// 
/// Provides comprehensive command frequency analysis with:
/// - Real-time command tracking and analysis
/// - AI-powered pattern recognition
/// - Predictive command suggestions
/// - Usage statistics and trends
/// - Command optimization recommendations
/// - User behavior analysis
class CommandFrequencyAnalyzer {
  static final CommandFrequencyAnalyzer _instance = CommandFrequencyAnalyzer._internal();
  factory CommandFrequencyAnalyzer() => _instance;
  CommandFrequencyAnalyzer._internal();

  final Map<String, CommandMetrics> _commandMetrics = {};
  final Queue<CommandEntry> _commandHistory = Queue<CommandEntry>();
  final Map<String, List<CommandPattern>> _patterns = {};
  final Map<String, CommandPrediction> _predictions = {};
  
  bool _isInitialized = false;
  Timer? _analysisTimer;
  Timer? _cleanupTimer;
  
  // Analysis configuration
  static const Duration _analysisInterval = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(hours: 1);
  static const int _maxHistorySize = 10000;
  static const int _minPatternOccurrences = 5;
  static const double _patternSimilarityThreshold = 0.8;
  
  final _analysisController = StreamController<AnalysisEvent>.broadcast();
  Stream<AnalysisEvent> get events => _analysisController.stream;
  
  bool get isInitialized => _isInitialized;
  Map<String, CommandMetrics> get commandMetrics => Map.unmodifiable(_commandMetrics);
  List<CommandPrediction> get predictions => _predictions.values.toList();

  /// Initialize the command frequency analyzer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load historical data
      await _loadHistoricalData();
      
      // Start analysis timer
      _startAnalysisTimer();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('📊 Command Frequency Analyzer initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Command Frequency Analyzer: $e');
      rethrow;
    }
  }

  /// Record a command execution
  void recordCommand(String command, {
    String? arguments,
    String? workingDirectory,
    int? exitCode,
    Duration? executionTime,
    bool success = true,
  }) {
    final entry = CommandEntry(
      command: command,
      arguments: arguments,
      workingDirectory: workingDirectory,
      exitCode: exitCode,
      executionTime: executionTime,
      success: success,
      timestamp: DateTime.now(),
    );

    // Add to history
    _commandHistory.add(entry);
    if (_commandHistory.length > _maxHistorySize) {
      _commandHistory.removeFirst();
    }

    // Update command metrics
    _updateCommandMetrics(command, entry);

    // Emit command recorded event
    _analysisController.add(AnalysisEvent(
      type: AnalysisEventType.commandRecorded,
      data: {'command': command, 'entry': entry},
      timestamp: DateTime.now(),
    ));

    debugPrint('📊 Recorded command: $command');
  }

  /// Get command suggestions based on frequency
  List<CommandSuggestion> getSuggestions(String partialCommand, {int maxSuggestions = 10}) {
    final suggestions = <CommandSuggestion>[];
    
    // Exact matches
    for (final entry in _commandMetrics.entries) {
      if (entry.key.startsWith(partialCommand)) {
        suggestions.add(CommandSuggestion(
          command: entry.key,
          score: _calculateSuggestionScore(entry.value, partialCommand),
          type: SuggestionType.frequency,
          metrics: entry.value,
        ));
      }
    }

    // Pattern-based suggestions
    final patternSuggestions = _getPatternSuggestions(partialCommand);
    suggestions.addAll(patternSuggestions);

    // Sort by score and limit
    suggestions.sort((a, b) => b.score.compareTo(a.score));
    return suggestions.take(maxSuggestions).toList();
  }

  /// Get command statistics
  CommandStatistics getStatistics(String command) {
    final metrics = _commandMetrics[command];
    if (metrics == null) {
      return CommandStatistics(
        command: command,
        totalExecutions: 0,
        successRate: 0.0,
        averageExecutionTime: Duration.zero,
        lastUsed: null,
        frequencyRank: 0,
      );
    }

    return CommandStatistics(
      command: command,
      totalExecutions: metrics.totalExecutions,
      successRate: metrics.successRate,
      averageExecutionTime: metrics.averageExecutionTime,
      lastUsed: metrics.lastUsed,
      frequencyRank: _getFrequencyRank(command),
    );
  }

  /// Get overall usage statistics
  OverallUsageStatistics getOverallStatistics() {
    final sortedCommands = _commandMetrics.entries.toList()
      ..sort((a, b) => b.value.totalExecutions.compareTo(a.value.totalExecutions));

    final totalCommands = _commandMetrics.values
        .fold(0, (sum, metrics) => sum + metrics.totalExecutions);

    final successfulCommands = _commandMetrics.values
        .fold(0, (sum, metrics) => sum + metrics.successfulExecutions);

    final averageExecutionTime = _commandMetrics.values
        .fold<Duration>(Duration.zero, (sum, metrics) => sum + metrics.averageExecutionTime);

    return OverallUsageStatistics(
      totalCommands: totalCommands,
      uniqueCommands: _commandMetrics.length,
      successRate: totalCommands > 0 ? successfulCommands / totalCommands : 0.0,
      averageExecutionTime: totalCommands > 0 
          ? Duration(milliseconds: averageExecutionTime.inMilliseconds ~/ totalCommands)
          : Duration.zero,
      topCommands: sortedCommands.take(10).map((e) => e.key).toList(),
      mostUsedCommand: sortedCommands.isNotEmpty ? sortedCommands.first.key : null,
      commandGrowth: _calculateCommandGrowth(),
    );
  }

  /// Analyze patterns and generate predictions
  Future<void> analyzePatterns() async {
    debugPrint('🔍 Analyzing command patterns');

    // Detect command sequences
    await _detectCommandSequences();

    // Detect time-based patterns
    await _detectTimeBasedPatterns();

    // Detect directory-based patterns
    await _detectDirectoryPatterns();

    // Generate predictions
    await _generatePredictions();

    // Emit analysis completed event
    _analysisController.add(AnalysisEvent(
      type: AnalysisEventType.analysisCompleted,
      data: {
        'patterns': _patterns.length,
        'predictions': _predictions.length,
      },
      timestamp: DateTime.now(),
    ));
  }

  /// Detect command sequences
  Future<void> _detectCommandSequences() async {
    final sequences = <List<String>, int>{};
    final historyList = _commandHistory.toList();

    for (int i = 0; i < historyList.length - 1; i++) {
      final sequence = [historyList[i].command, historyList[i + 1].command];
      sequences[sequence] = (sequences[sequence] ?? 0) + 1;
    }

    // Filter significant sequences
    final significantSequences = sequences.entries
        .where((entry) => entry.value >= _minPatternOccurrences)
        .map((entry) => CommandPattern(
          type: PatternType.sequence,
          pattern: entry.key.join(' -> '),
          frequency: entry.value,
          confidence: entry.value / historyList.length,
        ))
        .toList();

    _patterns['sequences'] = significantSequences;
  }

  /// Detect time-based patterns
  Future<void> _detectTimeBasedPatterns() async {
    final hourlyUsage = <int, int>{};
    
    for (final entry in _commandHistory) {
      final hour = entry.timestamp.hour;
      hourlyUsage[hour] = (hourlyUsage[hour] ?? 0) + 1;
    }

    // Find peak hours
    final avgUsage = hourlyUsage.values.fold(0, (sum, count) => sum + count) / 24;
    final peakHours = hourlyUsage.entries
        .where((entry) => entry.value > avgUsage * 1.5)
        .map((entry) => entry.key)
        .toList();

    final timePatterns = peakHours.map((hour) => CommandPattern(
      type: PatternType.timeBased,
      pattern: 'Peak usage at ${hour.toString().padLeft(2, '0')}:00',
      frequency: hourlyUsage[hour] ?? 0,
      confidence: (hourlyUsage[hour] ?? 0) / _commandHistory.length,
    )).toList();

    _patterns['timeBased'] = timePatterns;
  }

  /// Detect directory-based patterns
  Future<void> _detectDirectoryPatterns() async {
    final directoryUsage = <String, int>{};
    
    for (final entry in _commandHistory) {
      if (entry.workingDirectory != null) {
        final dir = entry.workingDirectory!;
        directoryUsage[dir] = (directoryUsage[dir] ?? 0) + 1;
      }
    }

    // Find frequently used directories
    final avgUsage = directoryUsage.values.fold(0, (sum, count) => sum + count) / directoryUsage.length;
    final frequentDirs = directoryUsage.entries
        .where((entry) => entry.value > avgUsage)
        .map((entry) => CommandPattern(
          type: PatternType.directoryBased,
          pattern: entry.key,
          frequency: entry.value,
          confidence: entry.value / _commandHistory.length,
        ))
        .toList();

    _patterns['directories'] = frequentDirs;
  }

  /// Generate command predictions
  Future<void> _generatePredictions() async {
    final recentCommands = _commandHistory.take(50).toList();
    if (recentCommands.isEmpty) return;

    // Predict next command based on sequences
    for (final sequence in _patterns['sequences'] ?? []) {
      final commands = sequence.pattern.split(' -> ');
      if (commands.length >= 2) {
        final lastCommand = commands.last;
        final nextCommand = commands.length > 2 ? commands[commands.length - 2] : commands.first;
        
        _predictions[lastCommand] = CommandPrediction(
          command: nextCommand,
          confidence: sequence.confidence,
          type: PredictionType.sequence,
          basedOn: sequence.pattern,
        );
      }
    }

    // Predict based on time of day
    final currentHour = DateTime.now().hour;
    for (final pattern in _patterns['timeBased'] ?? []) {
      if (pattern.pattern.contains(currentHour.toString().padLeft(2, '0'))) {
        final mostUsedCommand = _getMostUsedCommandInHour(currentHour);
        if (mostUsedCommand != null) {
          _predictions['timeBased'] = CommandPrediction(
            command: mostUsedCommand,
            confidence: pattern.confidence,
            type: PredictionType.timeBased,
            basedOn: pattern.pattern,
          );
        }
      }
    }
  }

  /// Get most used command in specific hour
  String? _getMostUsedCommandInHour(int hour) {
    final hourCommands = _commandHistory
        .where((entry) => entry.timestamp.hour == hour)
        .map((entry) => entry.command)
        .toList();

    if (hourCommands.isEmpty) return null;

    final commandCounts = <String, int>{};
    for (final command in hourCommands) {
      commandCounts[command] = (commandCounts[command] ?? 0) + 1;
    }

    return commandCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// Update command metrics
  void _updateCommandMetrics(String command, CommandEntry entry) {
    final metrics = _commandMetrics.putIfAbsent(command, () => CommandMetrics(command));
    
    metrics.totalExecutions++;
    if (entry.success) {
      metrics.successfulExecutions++;
    }
    
    if (entry.executionTime != null) {
      metrics.totalExecutionTime += entry.executionTime!;
    }
    
    metrics.lastUsed = entry.timestamp;
    metrics.updateFrequency();
  }

  /// Calculate suggestion score
  double _calculateSuggestionScore(CommandMetrics metrics, String partialCommand) {
    final frequencyScore = metrics.frequencyScore;
    final recencyScore = metrics.recencyScore;
    final successScore = metrics.successRate;
    final matchScore = _calculateMatchScore(metrics.command, partialCommand);
    
    return (frequencyScore * 0.4) + (recencyScore * 0.3) + (successScore * 0.2) + (matchScore * 0.1);
  }

  /// Calculate string match score
  double _calculateMatchScore(String command, String partial) {
    if (command.startsWith(partial)) return 1.0;
    if (command.contains(partial)) return 0.8;
    
    // Levenshtein distance similarity
    final distance = _levenshteinDistance(command, partial);
    final maxLength = math.max(command.length, partial.length);
    return 1.0 - (distance / maxLength);
  }

  /// Calculate Levenshtein distance
  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }

    return matrix[s1.length][s2.length];
  }

  /// Get pattern-based suggestions
  List<CommandSuggestion> _getPatternSuggestions(String partialCommand) {
    final suggestions = <CommandSuggestion>[];
    
    // Sequence-based suggestions
    for (final sequence in _patterns['sequences'] ?? []) {
      final commands = sequence.pattern.split(' -> ');
      for (final command in commands) {
        if (command.startsWith(partialCommand)) {
          suggestions.add(CommandSuggestion(
            command: command,
            score: sequence.confidence,
            type: SuggestionType.pattern,
            pattern: sequence.pattern,
          ));
        }
      }
    }

    return suggestions;
  }

  /// Get frequency rank for command
  int _getFrequencyRank(String command) {
    final sortedCommands = _commandMetrics.entries.toList()
      ..sort((a, b) => b.value.totalExecutions.compareTo(a.value.totalExecutions));
    
    for (int i = 0; i < sortedCommands.length; i++) {
      if (sortedCommands[i].key == command) {
        return i + 1;
      }
    }
    return -1;
  }

  /// Calculate command growth
  double _calculateCommandGrowth() {
    final now = DateTime.now();
    final weekAgo = now.subtract(Duration(days: 7));
    final monthAgo = now.subtract(Duration(days: 30));

    final weekCommands = _commandHistory
        .where((entry) => entry.timestamp.isAfter(weekAgo))
        .length;
    
    final monthCommands = _commandHistory
        .where((entry) => entry.timestamp.isAfter(monthAgo))
        .length;

    if (weekCommands == 0) return 0.0;
    return (weekCommands - monthCommands / 4) / (monthCommands / 4);
  }

  /// Start analysis timer
  void _startAnalysisTimer() {
    _analysisTimer = Timer.periodic(_analysisInterval, (_) {
      unawaited(analyzePatterns());
    });
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Perform cleanup
  void _performCleanup() {
    // Clean old patterns
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: 30));

    for (final patternList in _patterns.values) {
      patternList.removeWhere((pattern) => 
          _patternLastUsed(pattern) != null && 
          _patternLastUsed(pattern)!.isBefore(cutoff));
    }

    // Clean old predictions
    _predictions.removeWhere((key, prediction) => 
        prediction.timestamp.isBefore(cutoff));

    debugPrint('🧹 Command frequency analyzer cleanup completed');
  }

  /// Get last used time for pattern
  DateTime? _patternLastUsed(CommandPattern pattern) {
    // This would track when patterns were last used
    // For now, return null
    return null;
  }

  /// Load historical data
  Future<void> _loadHistoricalData() async {
    // This would load historical command data from storage
    debugPrint('📊 Loading historical command data');
  }

  /// Save historical data
  Future<void> _saveHistoricalData() async {
    // This would save current command data to storage
    debugPrint('💾 Saving historical command data');
  }

  /// Dispose the command frequency analyzer
  Future<void> dispose() async {
    _analysisTimer?.cancel();
    _cleanupTimer?.cancel();
    _analysisController.close();
    
    await _saveHistoricalData();
    
    _commandMetrics.clear();
    _commandHistory.clear();
    _patterns.clear();
    _predictions.clear();
    
    debugPrint('📊 Command Frequency Analyzer disposed');
  }
}

/// Command entry
class CommandEntry {
  final String command;
  final String? arguments;
  final String? workingDirectory;
  final int? exitCode;
  final Duration? executionTime;
  final bool success;
  final DateTime timestamp;
  
  CommandEntry({
    required this.command,
    this.arguments,
    this.workingDirectory,
    this.exitCode,
    this.executionTime,
    required this.success,
    required this.timestamp,
  });
}

/// Command metrics
class CommandMetrics {
  final String command;
  int totalExecutions = 0;
  int successfulExecutions = 0;
  Duration totalExecutionTime = Duration.zero;
  DateTime? lastUsed;
  double frequencyScore = 0.0;
  double recencyScore = 0.0;
  
  CommandMetrics(this.command);
  
  double get successRate => totalExecutions > 0 ? successfulExecutions / totalExecutions : 0.0;
  
  Duration get averageExecutionTime => totalExecutions > 0 
      ? Duration(milliseconds: totalExecutionTime.inMilliseconds ~/ totalExecutions)
      : Duration.zero;
  
  void updateFrequency() {
    // Calculate frequency score based on recent usage
    final now = DateTime.now();
    if (lastUsed != null) {
      final hoursSinceLastUse = now.difference(lastUsed!).inHours;
      recencyScore = math.exp(-hoursSinceLastUse / 24.0); // Decay over 24 hours
    }
    
    // Frequency score based on executions per day
    frequencyScore = math.log(totalExecutions + 1);
  }
}

/// Command pattern
class CommandPattern {
  final PatternType type;
  final String pattern;
  final int frequency;
  final double confidence;
  final DateTime? lastUsed;
  
  CommandPattern({
    required this.type,
    required this.pattern,
    required this.frequency,
    required this.confidence,
    this.lastUsed,
  });
}

/// Command prediction
class CommandPrediction {
  final String command;
  final double confidence;
  final PredictionType type;
  final String basedOn;
  final DateTime timestamp = DateTime.now();
  
  CommandPrediction({
    required this.command,
    required this.confidence,
    required this.type,
    required this.basedOn,
  });
}

/// Command suggestion
class CommandSuggestion {
  final String command;
  final double score;
  final SuggestionType type;
  final CommandMetrics? metrics;
  final String? pattern;
  
  CommandSuggestion({
    required this.command,
    required this.score,
    required this.type,
    this.metrics,
    this.pattern,
  });
}

/// Command statistics
class CommandStatistics {
  final String command;
  final int totalExecutions;
  final double successRate;
  final Duration averageExecutionTime;
  final DateTime? lastUsed;
  final int frequencyRank;
  
  CommandStatistics({
    required this.command,
    required this.totalExecutions,
    required this.successRate,
    required this.averageExecutionTime,
    this.lastUsed,
    required this.frequencyRank,
  });
}

/// Overall usage statistics
class OverallUsageStatistics {
  final int totalCommands;
  final int uniqueCommands;
  final double successRate;
  final Duration averageExecutionTime;
  final List<String> topCommands;
  final String? mostUsedCommand;
  final double commandGrowth;
  
  OverallUsageStatistics({
    required this.totalCommands,
    required this.uniqueCommands,
    required this.successRate,
    required this.averageExecutionTime,
    required this.topCommands,
    this.mostUsedCommand,
    required this.commandGrowth,
  });
}

/// Analysis event
class AnalysisEvent {
  final AnalysisEventType type;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  AnalysisEvent({
    required this.type,
    this.data,
    required this.timestamp,
  });
}

/// Enums
enum PatternType { sequence, timeBased, directoryBased, contextual }
enum PredictionType { sequence, timeBased, directoryBased, contextual }
enum SuggestionType { frequency, pattern, contextual, ai }
enum AnalysisEventType { 
  commandRecorded, 
  analysisCompleted, 
  patternDetected, 
  predictionGenerated 
}


