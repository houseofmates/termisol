import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:math';

class CommandHistoryIntelligence {
  static const int _maxHistorySize = 10000;
  static const int _analysisWindowSize = 100;
  static const int _patternMinFrequency = 3;
  static const int _semanticSearchLimit = 20;
  
  final List<CommandEntry> _commandHistory = [];
  final Map<String, CommandPattern> _commandPatterns = {};
  final Map<String, CommandSequence> _commandSequences = {};
  final Map<String, SemanticVector> _semanticVectors = {};
  
  Timer? _analysisTimer;
  bool _isAnalyzing = false;
  int _totalCommands = 0;
  
  final StreamController<HistoryEvent> _historyEventController = 
      StreamController<HistoryEvent>.broadcast();

  void initialize() {
    _startAnalysisTimer();
    _initializeSemanticVectors();
    developer.log('🧠 Command History Intelligence initialized');
  }

  void _startAnalysisTimer() {
    _analysisTimer = Timer.periodic(
      Duration(minutes: 5), // Analyze every 5 minutes
      (_) => _analyzeCommandHistory(),
    );
  }

  void _initializeSemanticVectors() {
    // Initialize semantic vectors for common command categories
    _semanticVectors['file_operations'] = SemanticVector(
      category: 'file_operations',
      keywords: ['ls', 'cd', 'mkdir', 'rm', 'cp', 'mv', 'find', 'locate'],
      vector: _generateVector(['file', 'directory', 'navigate', 'create', 'delete', 'copy', 'move']),
    );
    
    _semanticVectors['git_operations'] = SemanticVector(
      category: 'git_operations',
      keywords: ['git', 'status', 'add', 'commit', 'push', 'pull', 'branch', 'merge'],
      vector: _generateVector(['git', 'version', 'control', 'commit', 'push', 'pull', 'branch']),
    );
    
    _semanticVectors['development'] = SemanticVector(
      category: 'development',
      keywords: ['npm', 'yarn', 'pip', 'cargo', 'flutter', 'dart', 'python', 'node'],
      vector: _generateVector(['build', 'test', 'run', 'install', 'package', 'dependency']),
    );
    
    _semanticVectors['system'] = SemanticVector(
      category: 'system',
      keywords: ['ps', 'top', 'kill', 'systemctl', 'service', 'journalctl', 'dmesg'],
      vector: _generateVector(['system', 'process', 'service', 'log', 'monitor', 'kill']),
    );
    
    _semanticVectors['network'] = SemanticVector(
      category: 'network',
      keywords: ['ssh', 'scp', 'rsync', 'wget', 'curl', 'ping', 'netstat'],
      vector: _generateVector(['network', 'ssh', 'download', 'upload', 'connect', 'transfer']),
    );
  }

  List<double> _generateVector(List<String> keywords) {
    // Simple vector generation - in practice, use word embeddings
    final vector = List<double>.filled(50, 0.0);
    final random = Random();
    
    for (int i = 0; i < keywords.length; i++) {
      final index = random.nextInt(50);
      vector[index] += 1.0;
    }
    
    // Normalize vector
    final magnitude = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    if (magnitude > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= magnitude;
      }
    }
    
    return vector;
  }

  void addCommand(String command, {
    String? directory,
    String? session,
    int? exitCode,
    Duration? duration,
    String? output,
    bool isBackground = false,
  }) {
    final entry = CommandEntry(
      id: _generateCommandId(),
      command: command,
      timestamp: DateTime.now(),
      directory: directory,
      session: session,
      exitCode: exitCode ?? 0,
      duration: duration,
      output: output,
      isBackground: isBackground,
    );

    _commandHistory.add(entry);
    _totalCommands++;
    
    if (_commandHistory.length > _maxHistorySize) {
      _commandHistory.removeAt(0);
    }
    
    _updateCommandPatterns(entry);
    _updateCommandSequences(entry);
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.commandAdded,
      commandId: entry.id,
      command: command,
      timestamp: entry.timestamp,
    ));
  }

  String _generateCommandId() {
    return 'hist_${DateTime.now().millisecondsSinceEpoch}_$_totalCommands';
  }

  void _updateCommandPatterns(CommandEntry entry) {
    final normalizedCommand = _normalizeCommand(entry.command);
    final pattern = _commandPatterns.putIfAbsent(
      normalizedCommand,
      () => CommandPattern(command: normalizedCommand),
    );
    
    pattern.recordExecution(entry);
  }

  void _updateCommandSequences(CommandEntry entry) {
    if (_commandHistory.length < 2) return;
    
    final previousEntry = _commandHistory[_commandHistory.length - 2];
    final sequenceKey = '${previousEntry.command} -> ${entry.command}';
    
    final sequence = _commandSequences.putIfAbsent(
      sequenceKey,
      () => CommandSequence(
        firstCommand: previousEntry.command,
        secondCommand: entry.command,
      ),
    );
    
    sequence.incrementFrequency();
  }

  String _normalizeCommand(String command) {
    // Remove arguments and normalize
    final parts = command.split(' ');
    if (parts.isEmpty) return '';
    
    final baseCommand = parts[0].toLowerCase();
    return baseCommand.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  void _analyzeCommandHistory() {
    if (_isAnalyzing || _commandHistory.length < _analysisWindowSize) return;
    
    _isAnalyzing = true;
    
    try {
      _analyzePatterns();
      _analyzeSequences();
      _analyzeTemporalPatterns();
      _analyzePerformancePatterns();
      
      developer.log('🧠 Command history analysis completed');
      
      _emitEvent(HistoryEvent(
        type: HistoryEventType.analysisCompleted,
        timestamp: DateTime.now(),
      ));
      
    } catch (e) {
      developer.log('🧠 Command history analysis failed: $e');
    } finally {
      _isAnalyzing = false;
    }
  }

  void _analyzePatterns() {
    // Identify frequently used command patterns
    final frequentPatterns = _commandPatterns.entries
        .where((entry) => entry.value.frequency >= _patternMinFrequency)
        .toList()
      ..sort((a, b) => b.value.frequency.compareTo(a.value.frequency));
    
    for (final entry in frequentPatterns.take(20)) {
      developer.log('🧠 Frequent pattern: ${entry.key} (${entry.value.frequency} times)');
    }
  }

  void _analyzeSequences() {
    // Identify common command sequences
    final frequentSequences = _commandSequences.entries
        .where((entry) => entry.value.frequency >= _patternMinFrequency)
        .toList()
      ..sort((a, b) => b.value.frequency.compareTo(a.value.frequency));
    
    for (final entry in frequentSequences.take(10)) {
      developer.log('🧠 Common sequence: ${entry.key} (${entry.value.frequency} times)');
    }
  }

  void _analyzeTemporalPatterns() {
    // Analyze time-based patterns
    final now = DateTime.now();
    final recentCommands = _commandHistory.where((entry) => 
        now.difference(entry.timestamp).inHours <= 24).toList();
    
    // Group by hour
    final hourlyUsage = <int, int>{};
    for (final entry in recentCommands) {
      final hour = entry.timestamp.hour;
      hourlyUsage[hour] = (hourlyUsage[hour] ?? 0) + 1;
    }
    
    // Find peak usage hours
    final sortedHours = hourlyUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    if (sortedHours.isNotEmpty) {
      final peakHour = sortedHours.first.key;
      developer.log('🧠 Peak usage hour: $peakHour:00');
    }
  }

  void _analyzePerformancePatterns() {
    // Analyze command performance patterns
    final commandPerformance = <String, List<Duration>>{};
    
    for (final entry in _commandHistory) {
      if (entry.duration != null) {
        final normalizedCommand = _normalizeCommand(entry.command);
        commandPerformance.putIfAbsent(normalizedCommand, () => []).add(entry.duration!);
      }
    }
    
    // Calculate average durations
    for (final entry in commandPerformance.entries) {
      final durations = entry.value;
      final avgDuration = Duration(
        milliseconds: durations
            .map((d) => d.inMilliseconds)
            .reduce((a, b) => a + b) ~/ durations.length,
      );
      
      developer.log('🧠 ${entry.key}: average ${avgDuration.inMilliseconds}ms');
    }
  }

  List<CommandEntry> semanticSearch(String query, {int? limit}) {
    if (query.isEmpty) return [];
    
    final queryVector = _generateVector(query.split(' '));
    final results = <SemanticSearchResult>[];
    
    // Search through command history
    for (final entry in _commandHistory.reversed.take(_semanticSearchLimit)) {
      final score = _calculateSemanticSimilarity(queryVector, entry.command);
      if (score > 0.3) { // Threshold for semantic similarity
        results.add(SemanticSearchResult(
          entry: entry,
          score: score,
        ));
      }
    }
    
    // Sort by score and return top results
    results.sort((a, b) => b.score.compareTo(a.score));
    
    return results
        .take(limit ?? 10)
        .map((result) => result.entry)
        .toList();
  }

  double _calculateSemanticSimilarity(List<double> queryVector, String command) {
    // Find the best matching semantic category
    double bestScore = 0.0;
    
    for (final entry in _semanticVectors.entries) {
      final category = entry.value;
      
      // Check if command contains keywords
      final keywordMatch = category.keywords.any((keyword) => 
          command.toLowerCase().contains(keyword));
      
      if (keywordMatch) {
        // Calculate cosine similarity
        final similarity = _cosineSimilarity(queryVector, category.vector);
        bestScore = max(bestScore, similarity);
      }
    }
    
    return bestScore;
  }

  double _cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) return 0.0;
    
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      norm1 += vec1[i] * vec1[i];
      norm2 += vec2[i] * vec2[i];
    }
    
    norm1 = sqrt(norm1);
    norm2 = sqrt(norm2);
    
    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;
    
    return dotProduct / (norm1 * norm2);
  }

  List<CommandEntry> getSimilarCommands(String command, {int? limit}) {
    final normalizedCommand = _normalizeCommand(command);
    final pattern = _commandPatterns[normalizedCommand];
    
    if (pattern == null) return [];
    
    // Find commands with similar patterns
    final similarCommands = <CommandEntry>[];
    
    for (final entry in _commandHistory.reversed) {
      final entryNormalized = _normalizeCommand(entry.command);
      final entryPattern = _commandPatterns[entryNormalized];
      
      if (entryPattern != null && _arePatternsSimilar(pattern, entryPattern)) {
        similarCommands.add(entry);
      }
    }
    
    return similarCommands.take(limit ?? 10).toList();
  }

  bool _arePatternsSimilar(CommandPattern pattern1, CommandPattern pattern2) {
    // Simple similarity check based on common prefixes and usage patterns
    final command1 = pattern1.command;
    final command2 = pattern2.command;
    
    // Same first letter
    if (command1.isNotEmpty && command2.isNotEmpty && 
        command1[0] == command2[0]) {
      return true;
    }
    
    // Similar length
    final lengthDiff = (command1.length - command2.length).abs();
    if (lengthDiff <= 2) {
      return true;
    }
    
    return false;
  }

  List<CommandSequence> getCommandSequences(String command) {
    final sequences = <CommandSequence>[];
    
    for (final entry in _commandSequences.entries) {
      if (entry.value.firstCommand == command) {
        sequences.add(entry.value);
      }
    }
    
    sequences.sort((a, b) => b.frequency.compareTo(a.frequency));
    return sequences.take(5).toList();
  }

  Map<String, dynamic> getCommandStatistics() {
    final stats = <String, dynamic>{};
    
    // Most used commands
    final topCommands = _commandPatterns.entries.toList()
      ..sort((a, b) => b.value.frequency.compareTo(a.value.frequency));
    
    stats['topCommands'] = topCommands
        .take(10)
        .map((entry) => {
            'command': entry.key,
            'frequency': entry.value.frequency,
            'avgDuration': entry.value.averageDuration?.inMilliseconds,
          })
        .toList();
    
    // Command categories
    final categories = <String, int>{};
    for (final entry in _commandHistory) {
      final category = _categorizeCommand(entry.command);
      categories[category] = (categories[category] ?? 0) + 1;
    }
    
    stats['categories'] = categories;
    
    // Success rate
    final totalCommands = _commandHistory.length;
    final successfulCommands = _commandHistory
        .where((entry) => entry.exitCode == 0)
        .length;
    
    stats['successRate'] = totalCommands > 0 ? successfulCommands / totalCommands : 0.0;
    
    return stats;
  }

  String _categorizeCommand(String command) {
    final normalizedCommand = command.toLowerCase();
    
    if (_semanticVectors['file_operations']!.keywords.any((keyword) => 
        normalizedCommand.contains(keyword))) {
      return 'file_operations';
    }
    
    if (_semanticVectors['git_operations']!.keywords.any((keyword) => 
        normalizedCommand.contains(keyword))) {
      return 'git_operations';
    }
    
    if (_semanticVectors['development']!.keywords.any((keyword) => 
        normalizedCommand.contains(keyword))) {
      return 'development';
    }
    
    if (_semanticVectors['system']!.keywords.any((keyword) => 
        normalizedCommand.contains(keyword))) {
      return 'system';
    }
    
    if (_semanticVectors['network']!.keywords.any((keyword) => 
        normalizedCommand.contains(keyword))) {
      return 'network';
    }
    
    return 'other';
  }

  void _emitEvent(HistoryEvent event) {
    _historyEventController.add(event);
  }

  Stream<HistoryEvent> get historyEventStream => _historyEventController.stream;

  CommandHistoryIntelligenceStats getStats() {
    return CommandHistoryIntelligenceStats(
      totalCommands: _totalCommands,
      historySize: _commandHistory.length,
      patternCount: _commandPatterns.length,
      sequenceCount: _commandSequences.length,
      isAnalyzing: _isAnalyzing,
    );
  }

  void dispose() {
    _analysisTimer?.cancel();
    _commandHistory.clear();
    _commandPatterns.clear();
    _commandSequences.clear();
    _semanticVectors.clear();
    _historyEventController.close();
    developer.log('🧠 Command History Intelligence disposed');
  }
}

class CommandEntry {
  final String id;
  final String command;
  final DateTime timestamp;
  final String? directory;
  final String? session;
  final int exitCode;
  final Duration? duration;
  final String? output;
  final bool isBackground;

  CommandEntry({
    required this.id,
    required this.command,
    required this.timestamp,
    this.directory,
    this.session,
    required this.exitCode,
    this.duration,
    this.output,
    required this.isBackground,
  });
}

class CommandPattern {
  final String command;
  int frequency = 0;
  int totalDuration = 0;
  int successCount = 0;
  DateTime lastUsed = DateTime.now();

  CommandPattern({required this.command});

  void recordExecution(CommandEntry entry) {
    frequency++;
    lastUsed = entry.timestamp;
    
    if (entry.duration != null) {
      totalDuration += entry.duration!.inMilliseconds;
    }
    
    if (entry.exitCode == 0) {
      successCount++;
    }
  }

  Duration? get averageDuration {
    return frequency > 0 ? Duration(milliseconds: totalDuration ~/ frequency) : null;
  }

  double get successRate {
    return frequency > 0 ? successCount / frequency : 0.0;
  }
}

class CommandSequence {
  final String firstCommand;
  final String secondCommand;
  int frequency = 0;
  DateTime lastUsed = DateTime.now();

  CommandSequence({
    required this.firstCommand,
    required this.secondCommand,
  });

  void incrementFrequency() {
    frequency++;
    lastUsed = DateTime.now();
  }
}

class SemanticVector {
  final String category;
  final List<String> keywords;
  final List<double> vector;

  SemanticVector({
    required this.category,
    required this.keywords,
    required this.vector,
  });
}

class SemanticSearchResult {
  final CommandEntry entry;
  final double score;

  SemanticSearchResult({
    required this.entry,
    required this.score,
  });
}

enum HistoryEventType {
  commandAdded,
  analysisCompleted,
  patternDetected,
  sequenceDetected,
}

class HistoryEvent {
  final HistoryEventType type;
  final String? commandId;
  final String? command;
  final DateTime timestamp;

  HistoryEvent({
    required this.type,
    this.commandId,
    this.command,
    required this.timestamp,
  });
}

class CommandHistoryIntelligenceStats {
  final int totalCommands;
  final int historySize;
  final int patternCount;
  final int sequenceCount;
  final bool isAnalyzing;

  CommandHistoryIntelligenceStats({
    required this.totalCommands,
    required this.historySize,
    required this.patternCount,
    required this.sequenceCount,
    required this.isAnalyzing,
  });
}
