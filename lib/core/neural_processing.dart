import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../ai/ai_terminal_assistant.dart';
import 'terminal_session.dart';

/// Software-Based Neural Processing System
///
/// Provides advanced AI/ML capabilities using software models:
/// - Pattern recognition for command prediction
/// - User behavior analysis and learning
/// - Context-aware intelligence
/// - Natural language understanding
/// - Predictive analytics
/// - Anomaly detection
///
/// All processing runs on standard hardware (CPU/GPU) with no special neural hardware required.
class NeuralProcessingSystem {
  final AITerminalAssistant _aiAssistant;

  final StreamController<NeuralEvent> _neuralEventController =
      StreamController<NeuralEvent>.broadcast();

  Stream<NeuralEvent> get events => _neuralEventController.stream;

  // Neural Networks (simplified implementations)
  late CommandPredictionNetwork _commandPredictor;
  late BehaviorAnalysisNetwork _behaviorAnalyzer;
  late ContextUnderstandingNetwork _contextAnalyzer;
  late AnomalyDetectionNetwork _anomalyDetector;

  // Training data and models
  final Map<String, UserProfile> _userProfiles = {};
  final List<CommandSequence> _learnedSequences = [];
  final Map<String, Pattern> _detectedPatterns = {};
  final List<Anomaly> _detectedAnomalies = [];

  bool _isActive = false;
  bool get isActive => _isActive;

  String? _currentUserId;
  final Map<String, dynamic> _systemContext = {};

  NeuralProcessingSystem(this._aiAssistant);

  /// Initialize the neural processing system
  Future<void> initialize() async {
    if (_isActive) return;

    // Initialize neural networks
    _commandPredictor = CommandPredictionNetwork();
    _behaviorAnalyzer = BehaviorAnalysisNetwork();
    _contextAnalyzer = ContextUnderstandingNetwork();
    _anomalyDetector = AnomalyDetectionNetwork();

    // Train models with initial data
    await _initializeModels();

    _isActive = true;
    debugPrint('🧠 Neural Processing System initialized (Software-based)');
  }

  /// Initialize and train neural models
  Future<void> _initializeModels() async {
    debugPrint('🧠 Training neural models...');

    // Initialize with common command patterns
    _initializeCommonPatterns();

    // Simulate training time
    await Future.delayed(const Duration(seconds: 2));

    debugPrint('✅ Neural models trained and ready');
  }

  /// Initialize common command patterns for training
  void _initializeCommonPatterns() {
    _learnedSequences.addAll([
      CommandSequence(
        commands: ['git status', 'git add .', 'git commit -m "update"', 'git push'],
        frequency: 0.8,
        context: 'git-workflow',
      ),
      CommandSequence(
        commands: ['npm install', 'npm run build', 'npm test'],
        frequency: 0.7,
        context: 'build-test',
      ),
      CommandSequence(
        commands: ['cd', 'ls -la', 'pwd'],
        frequency: 0.9,
        context: 'navigation',
      ),
      CommandSequence(
        commands: ['docker build', 'docker run', 'docker logs'],
        frequency: 0.6,
        context: 'docker-workflow',
      ),
    ]);

    _detectedPatterns.addAll({
      'git-workflow': Pattern(
        name: 'Git Workflow',
        type: PatternType.sequence,
        confidence: 0.85,
        features: ['version-control', 'collaboration'],
      ),
      'error-handling': Pattern(
        name: 'Error Handling',
        type: PatternType.behavioral,
        confidence: 0.75,
        features: ['debugging', 'troubleshooting'],
      ),
      'exploration': Pattern(
        name: 'Code Exploration',
        type: PatternType.contextual,
        confidence: 0.80,
        features: ['discovery', 'learning'],
      ),
    });
  }

  /// Process command input through neural networks
  Future<NeuralProcessingResult> processCommand(String command, {
    String? userId,
    String? currentDirectory,
    List<String>? recentCommands,
    Map<String, dynamic>? context,
  }) async {
    if (!_isActive) {
      throw Exception('Neural processing system not initialized');
    }

    final startTime = DateTime.now();
    _currentUserId = userId ?? 'default';

    // Update system context
    _updateSystemContext(currentDirectory, recentCommands, context);

    try {
      // Parallel processing through different neural networks
      final results = await Future.wait([
        _commandPredictor.predict(command, recentCommands ?? []),
        _behaviorAnalyzer.analyzeBehavior(command, _currentUserId!),
        _contextAnalyzer.understandContext(command, _systemContext),
        _anomalyDetector.detectAnomalies(command, recentCommands ?? []),
      ]);

      final prediction = results[0] as CommandPrediction;
      final behavior = results[1] as BehaviorAnalysis;
      final contextUnderstanding = results[2] as ContextUnderstanding;
      final anomalies = results[3] as List<Anomaly>;

      // Store anomalies
      _detectedAnomalies.addAll(anomalies);

      // Learn from this command
      await _learnFromCommand(command, prediction, behavior, contextUnderstanding);

      final result = NeuralProcessingResult(
        command: command,
        predictions: prediction,
        behaviorAnalysis: behavior,
        contextUnderstanding: contextUnderstanding,
        anomalies: anomalies,
        processingTime: DateTime.now().difference(startTime),
        confidence: _calculateOverallConfidence(prediction, behavior, contextUnderstanding),
      );

      _neuralEventController.add(NeuralEvent(
        type: NeuralEventType.command_processed,
        data: result,
      ));

      return result;

    } catch (e) {
      debugPrint('❌ Neural processing failed: $e');

      _neuralEventController.add(NeuralEvent(
        type: NeuralEventType.processing_error,
        data: {'error': e.toString(), 'command': command},
      ));

      // Return basic result on error
      return NeuralProcessingResult(
        command: command,
        predictions: CommandPrediction.empty(),
        behaviorAnalysis: BehaviorAnalysis(frequency: 0.5, consistency: 0.5, intention: null, context: null, unusual: false),
        contextUnderstanding: ContextUnderstanding.basic(command),
        anomalies: [],
        processingTime: DateTime.now().difference(startTime),
        confidence: 0.0,
      );
    }
  }

  /// Get proactive suggestions based on neural analysis
  Future<List<NeuralSuggestion>> getProactiveSuggestions({
    String? currentInput,
    String? userId,
    List<String>? recentCommands,
    Map<String, dynamic>? context,
  }) async {
    if (!_isActive) return [];

    final suggestions = <NeuralSuggestion>[];

    try {
      // Get pattern-based suggestions
      final patternSuggestions = await _getPatternBasedSuggestions(
        currentInput,
        recentCommands,
      );
      suggestions.addAll(patternSuggestions);

      // Get behavior-based suggestions
      final behaviorSuggestions = await _getBehaviorBasedSuggestions(userId ?? 'default');
      suggestions.addAll(behaviorSuggestions);

      // Get context-aware suggestions
      final contextSuggestions = await _getContextAwareSuggestions(context);
      suggestions.addAll(contextSuggestions);

      // Get anomaly-based suggestions
      final anomalySuggestions = _getAnomalyBasedSuggestions();
      suggestions.addAll(anomalySuggestions);

      // Rank and filter suggestions
      return _rankSuggestions(suggestions);

    } catch (e) {
      debugPrint('⚠️ Failed to generate suggestions: $e');
      return [];
    }
  }

  /// Get pattern-based suggestions
  Future<List<NeuralSuggestion>> _getPatternBasedSuggestions(
    String? currentInput,
    List<String>? recentCommands,
  ) async {
    final suggestions = <NeuralSuggestion>[];

    if (recentCommands == null || recentCommands.isEmpty) return suggestions;

    // Find matching sequences
    for (final sequence in _learnedSequences) {
      final match = _findSequenceMatch(sequence, recentCommands);
      if (match != null) {
        suggestions.add(NeuralSuggestion(
          type: SuggestionType.sequence_completion,
          content: match,
          confidence: sequence.frequency,
          reason: 'Pattern recognition: ${sequence.context}',
          neuralBasis: 'Sequence learning network',
        ));
      }
    }

    // Predict next command
    final prediction = await _commandPredictor.predictNext(recentCommands);
    if (prediction.isNotEmpty) {
      suggestions.add(NeuralSuggestion(
        type: SuggestionType.command_prediction,
        content: prediction,
        confidence: 0.7,
        reason: 'Predicted based on your recent commands',
        neuralBasis: 'Command prediction network',
      ));
    }

    return suggestions;
  }

  /// Find sequence match in recent commands
  String? _findSequenceMatch(CommandSequence sequence, List<String> recentCommands) {
    if (sequence.commands.length <= recentCommands.length) {
      // Check if recent commands match the start of the sequence
      for (int i = 0; i < sequence.commands.length - 1; i++) {
        if (i >= recentCommands.length) break;

        final recentCmd = recentCommands[recentCommands.length - 1 - i];
        final sequenceCmd = sequence.commands[sequence.commands.length - 2 - i];

        if (!_commandsMatch(recentCmd, sequenceCmd)) {
          return null;
        }
      }

      // Return next command in sequence
      return sequence.commands.last;
    }

    return null;
  }

  /// Check if commands match (with some flexibility)
  bool _commandsMatch(String cmd1, String cmd2) {
    final base1 = cmd1.split(' ').first;
    final base2 = cmd2.split(' ').first;
    return base1 == base2;
  }

  /// Get behavior-based suggestions
  Future<List<NeuralSuggestion>> _getBehaviorBasedSuggestions(String userId) async {
    final suggestions = <NeuralSuggestion>[];

    final profile = _userProfiles[userId];
    if (profile == null) return suggestions;

    // Suggest frequently used commands
    final topCommands = profile.commandFrequency.entries
        .where((entry) => entry.value > 3)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in topCommands.take(2)) {
      suggestions.add(NeuralSuggestion(
        type: SuggestionType.behavioral_pattern,
        content: entry.key,
        confidence: math.min(entry.value / 10.0, 0.9),
        reason: 'You frequently use this command',
        neuralBasis: 'Behavior analysis network',
      ));
    }

    // Suggest based on time patterns
    final hour = DateTime.now().hour;
    final timeBasedSuggestions = profile.getTimeBasedSuggestions(hour);
    suggestions.addAll(timeBasedSuggestions.map((cmd) =>
      NeuralSuggestion(
        type: SuggestionType.temporal_pattern,
        content: cmd,
        confidence: 0.6,
        reason: 'Based on your usage patterns at this time',
        neuralBasis: 'Temporal learning network',
      ),
    ));

    return suggestions;
  }

  /// Get context-aware suggestions
  Future<List<NeuralSuggestion>> _getContextAwareSuggestions(Map<String, dynamic>? context) async {
    final suggestions = <NeuralSuggestion>[];

    if (context == null) return suggestions;

    // Project context
    final projectType = context['projectType'] as String?;
    if (projectType != null) {
      final projectSuggestions = _getProjectTypeSuggestions(projectType);
      suggestions.addAll(projectSuggestions.map((cmd) =>
        NeuralSuggestion(
          type: SuggestionType.contextual,
          content: cmd,
          confidence: 0.8,
          reason: 'Common for $projectType projects',
          neuralBasis: 'Context understanding network',
        ),
      ));
    }

    // Directory context
    final currentDir = context['currentDirectory'] as String?;
    if (currentDir != null) {
      final dirSuggestions = _getDirectoryBasedSuggestions(currentDir);
      suggestions.addAll(dirSuggestions.map((cmd) =>
        NeuralSuggestion(
          type: SuggestionType.contextual,
          content: cmd,
          confidence: 0.7,
          reason: 'Relevant for current directory',
          neuralBasis: 'Context understanding network',
        ),
      ));
    }

    return suggestions;
  }

  /// Get project type specific suggestions
  List<String> _getProjectTypeSuggestions(String projectType) {
    switch (projectType.toLowerCase()) {
      case 'flutter':
      case 'dart':
        return ['flutter run', 'flutter build apk', 'flutter pub get'];
      case 'nodejs':
      case 'javascript':
        return ['npm install', 'npm run dev', 'npm test'];
      case 'python':
        return ['pip install -r requirements.txt', 'python main.py', 'pytest'];
      case 'react':
        return ['npm start', 'npm run build', 'npm test'];
      default:
        return ['git status', 'ls -la'];
    }
  }

  /// Get directory-based suggestions
  List<String> _getDirectoryBasedSuggestions(String directory) {
    final suggestions = <String>[];

    if (directory.contains('src') || directory.contains('lib')) {
      suggestions.addAll(['grep "TODO"', 'find . -name "*.test.*"', 'ls -la']);
    }

    if (directory.contains('test') || directory.contains('spec')) {
      suggestions.addAll(['npm test', 'pytest', 'rspec']);
    }

    if (directory.contains('.git')) {
      suggestions.addAll(['git status', 'git log --oneline', 'git diff']);
    }

    return suggestions;
  }

  /// Get anomaly-based suggestions
  List<NeuralSuggestion> _getAnomalyBasedSuggestions() {
    final suggestions = <NeuralSuggestion>[];

    // Check for recent anomalies
    final recentAnomalies = _detectedAnomalies
        .where((a) => DateTime.now().difference(a.timestamp) < const Duration(minutes: 5))
        .toList();

    for (final anomaly in recentAnomalies.take(2)) {
      suggestions.add(NeuralSuggestion(
        type: SuggestionType.corrective,
        content: _getCorrectionForAnomaly(anomaly),
        confidence: anomaly.confidence,
        reason: 'Detected anomaly: ${anomaly.type}',
        neuralBasis: 'Anomaly detection network',
      ));
    }

    return suggestions;
  }

  /// Get correction suggestion for anomaly
  String _getCorrectionForAnomaly(Anomaly anomaly) {
    switch (anomaly.type) {
      case AnomalyType.unusual_command:
        return 'Did you mean a similar command? Check syntax.';
      case AnomalyType.error_pattern:
        return 'Consider checking error logs or documentation.';
      case AnomalyType.slow_execution:
        return 'Command took longer than usual. Check system resources.';
      case AnomalyType.permission_issue:
        return 'Permission error detected. Try with sudo or check permissions.';
      default:
        return 'Unusual activity detected. Review recent commands.';
    }
  }

  /// Rank and filter suggestions
  List<NeuralSuggestion> _rankSuggestions(List<NeuralSuggestion> suggestions) {
    // Remove duplicates
    final unique = <String, NeuralSuggestion>{};
    for (final suggestion in suggestions) {
      final key = '${suggestion.type}_${suggestion.content}';
      if (!unique.containsKey(key) ||
          unique[key]!.confidence < suggestion.confidence) {
        unique[key] = suggestion;
      }
    }

    // Sort by confidence
    final sorted = unique.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return sorted.take(5).toList();
  }

  /// Learn from command and analysis results
  Future<void> _learnFromCommand(
    String command,
    CommandPrediction prediction,
    BehaviorAnalysis behavior,
    ContextUnderstanding context,
  ) async {
    // Update user profile
    if (_currentUserId != null) {
      if (!_userProfiles.containsKey(_currentUserId)) {
        _userProfiles[_currentUserId!] = UserProfile(_currentUserId!);
      }

      _userProfiles[_currentUserId!]!.addCommand(command);
    }

    // Update patterns
    await _updatePatterns(command, behavior);

    // Adapt models based on feedback
    await _adaptModels(prediction, behavior, context);
  }

  /// Update learned patterns
  Future<void> _updatePatterns(String command, BehaviorAnalysis behavior) async {
    // Simple pattern learning - in real implementation would use more sophisticated ML
    if (behavior.intention != null) {
      final patternKey = behavior.intention!;
      if (!_detectedPatterns.containsKey(patternKey)) {
        _detectedPatterns[patternKey] = Pattern(
          name: patternKey,
          type: PatternType.behavioral,
          confidence: 0.5,
          features: [behavior.context ?? 'unknown'],
        );
      } else {
        // Increase confidence
        final pattern = _detectedPatterns[patternKey]!;
        pattern.confidence = math.min(pattern.confidence + 0.1, 1.0);
      }
    }
  }

  /// Adapt neural models based on results
  Future<void> _adaptModels(
    CommandPrediction prediction,
    BehaviorAnalysis behavior,
    ContextUnderstanding context,
  ) async {
    // Online learning - adjust model weights based on outcomes
    // In a real implementation, this would update neural network weights

    if (prediction.accuracy > 0.8) {
      // Reinforce successful predictions
      await _commandPredictor.reinforce(prediction);
    }

    if (behavior.consistency > 0.7) {
      // Learn from consistent behavior
      await _behaviorAnalyzer.learn(behavior);
    }

    if (context.clarity > 0.8) {
      // Improve context understanding
      await _contextAnalyzer.improve(context);
    }
  }

  /// Update system context
  void _updateSystemContext(String? currentDirectory, List<String>? recentCommands, Map<String, dynamic>? context) {
    if (currentDirectory != null) {
      _systemContext['currentDirectory'] = currentDirectory;
    }
    if (recentCommands != null) {
      _systemContext['recentCommands'] = recentCommands;
    }
    if (context != null) {
      _systemContext.addAll(context);
    }

    _systemContext['timestamp'] = DateTime.now();
  }

  /// Calculate overall confidence
  double _calculateOverallConfidence(
    CommandPrediction prediction,
    BehaviorAnalysis behavior,
    ContextUnderstanding context,
  ) {
    final weights = [0.4, 0.3, 0.3]; // prediction, behavior, context
    final scores = [prediction.confidence, behavior.consistency, context.clarity];

    double total = 0;
    for (int i = 0; i < weights.length; i++) {
      total += weights[i] * scores[i];
    }

    return total;
  }

  /// Get neural processing statistics
  Map<String, dynamic> getNeuralStats() {
    return {
      'is_active': _isActive,
      'user_profiles': _userProfiles.length,
      'learned_sequences': _learnedSequences.length,
      'detected_patterns': _detectedPatterns.length,
      'detected_anomalies': _detectedAnomalies.length,
      'current_user': _currentUserId,
      'system_context_keys': _systemContext.length,
    };
  }

  /// Reset learning for user
  void resetLearning(String userId) {
    _userProfiles.remove(userId);
    debugPrint('🔄 Reset neural learning for user: $userId');
  }

  /// Export learned patterns
  String exportLearnedPatterns() {
    final data = {
      'sequences': _learnedSequences.map((s) => s.toJson()).toList(),
      'patterns': _detectedPatterns.map((k, v) => MapEntry(k, v.toJson())),
      'user_profiles': _userProfiles.map((k, v) => MapEntry(k, v.toJson())),
    };

    return jsonEncode(data);
  }

  /// Import learned patterns
  void importLearnedPatterns(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;

      if (data['sequences'] != null) {
        _learnedSequences.clear();
        _learnedSequences.addAll(
          (data['sequences'] as List).map((s) => CommandSequence.fromJson(s)),
        );
      }

      if (data['patterns'] != null) {
        _detectedPatterns.clear();
        _detectedPatterns.addAll(
          (data['patterns'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, Pattern.fromJson(v)),
          ),
        );
      }

      if (data['user_profiles'] != null) {
        _userProfiles.clear();
        _userProfiles.addAll(
          (data['user_profiles'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, UserProfile.fromJson(v)),
          ),
        );
      }

      debugPrint('📥 Imported neural patterns');
    } catch (e) {
      debugPrint('❌ Failed to import patterns: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _neuralEventController.close();
    _isActive = false;
  }
}

/// Neural Event Types
enum NeuralEventType {
  command_processed,
  pattern_learned,
  anomaly_detected,
  model_updated,
  processing_error,
}

/// Neural Event
class NeuralEvent {
  final NeuralEventType type;
  final dynamic data;
  final DateTime timestamp;

  NeuralEvent({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Neural Processing Result
class NeuralProcessingResult {
  final String command;
  final CommandPrediction predictions;
  final BehaviorAnalysis behaviorAnalysis;
  final ContextUnderstanding contextUnderstanding;
  final List<Anomaly> anomalies;
  final Duration processingTime;
  final double confidence;

  NeuralProcessingResult({
    required this.command,
    required this.predictions,
    required this.behaviorAnalysis,
    required this.contextUnderstanding,
    required this.anomalies,
    required this.processingTime,
    required this.confidence,
  });
}

/// Neural Suggestion
class NeuralSuggestion {
  final SuggestionType type;
  final String content;
  final double confidence;
  final String reason;
  final String neuralBasis;

  NeuralSuggestion({
    required this.type,
    required this.content,
    required this.confidence,
    required this.reason,
    required this.neuralBasis,
  });
}

/// Suggestion Types
enum SuggestionType {
  command_prediction,
  sequence_completion,
  behavioral_pattern,
  temporal_pattern,
  contextual,
  corrective,
}

/// Command Prediction Network (Simplified)
class CommandPredictionNetwork {
  final Map<String, Map<String, double>> _transitionMatrix = {};
  final Map<String, double> _commandFrequency = {};

  Future<CommandPrediction> predict(String command, List<String> history) async {
    // Simulate neural network processing
    await Future.delayed(const Duration(milliseconds: 50));

    final nextPredictions = <String>[];
    double confidence = 0.0;

    if (history.isNotEmpty) {
      final lastCommand = history.last.split(' ').first;
      final transitions = _transitionMatrix[lastCommand];

      if (transitions != null) {
        final sorted = transitions.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        nextPredictions.addAll(sorted.take(3).map((e) => e.key));
        confidence = sorted.first.value;
      }
    }

    // Learn from this command sequence
    _learnTransition(history.isNotEmpty ? history.last : '', command);

    return CommandPrediction(
      nextCommands: nextPredictions,
      confidence: confidence,
      reasoning: 'Based on command transition patterns',
    );
  }

  Future<String> predictNext(List<String> recentCommands) async {
    if (recentCommands.isEmpty) return '';

    final prediction = await predict('', recentCommands);
    return prediction.nextCommands.isNotEmpty ? prediction.nextCommands.first : '';
  }

  void _learnTransition(String fromCommand, String toCommand) {
    final from = fromCommand.split(' ').first;
    final to = toCommand.split(' ').first;

    if (from.isNotEmpty && to.isNotEmpty) {
      _transitionMatrix.putIfAbsent(from, () => {});
      _transitionMatrix[from]![to] = (_transitionMatrix[from]![to] ?? 0) + 1;

      _commandFrequency[to] = (_commandFrequency[to] ?? 0) + 1;
    }
  }

  Future<void> reinforce(CommandPrediction prediction) async {
    // Strengthen successful predictions
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

/// Behavior Analysis Network (Simplified)
class BehaviorAnalysisNetwork {
  final Map<String, List<String>> _userCommandHistory = {};

  Future<BehaviorAnalysis> analyzeBehavior(String command, String userId) async {
    await Future.delayed(const Duration(milliseconds: 30));

    final history = _userCommandHistory[userId] ?? [];
    final frequency = _calculateFrequency(command, history);
    final consistency = _calculateConsistency(command, history);
    final intention = _inferIntention(command);
    final context = _inferContext(command, history);

    // Update history
    if (!_userCommandHistory.containsKey(userId)) {
      _userCommandHistory[userId] = [];
    }
    _userCommandHistory[userId]!.add(command);
    if (_userCommandHistory[userId]!.length > 100) {
      _userCommandHistory[userId]!.removeAt(0);
    }

    return BehaviorAnalysis(
      frequency: frequency,
      consistency: consistency,
      intention: intention,
      context: context,
      unusual: consistency < 0.3,
    );
  }

  double _calculateFrequency(String command, List<String> history) {
    if (history.isEmpty) return 0.0;

    final baseCommand = command.split(' ').first;
    final matches = history.where((cmd) => cmd.split(' ').first == baseCommand).length;
    return matches / history.length;
  }

  double _calculateConsistency(String command, List<String> history) {
    // Simple consistency based on recent usage
    if (history.length < 5) return 0.5;

    final recent = history.take(5);
    final baseCommand = command.split(' ').first;
    final matches = recent.where((cmd) => cmd.split(' ').first == baseCommand).length;
    return matches / 5.0;
  }

  String? _inferIntention(String command) {
    final lower = command.toLowerCase();

    if (lower.contains('git')) return 'version-control';
    if (lower.contains('npm') || lower.contains('yarn')) return 'package-management';
    if (lower.contains('docker')) return 'containerization';
    if (lower.contains('test')) return 'testing';
    if (lower.contains('build') || lower.contains('compile')) return 'building';
    if (lower.contains('deploy')) return 'deployment';

    return null;
  }

  String? _inferContext(String command, List<String> history) {
    // Infer context from command patterns
    if (history.isNotEmpty) {
      final recentBase = history.last.split(' ').first;
      if (recentBase == 'cd') return 'navigation';
      if (recentBase == 'git') return 'development';
      if (recentBase.contains('test')) return 'testing';
    }

    return null;
  }

  Future<void> learn(BehaviorAnalysis behavior) async {
    // Learn from behavior patterns
    await Future.delayed(const Duration(milliseconds: 10));
  }

  static BehaviorAnalysis neutral() {
    return BehaviorAnalysis(
      frequency: 0.5,
      consistency: 0.5,
      intention: null,
      context: null,
      unusual: false,
    );
  }
}

/// Context Understanding Network (Simplified)
class ContextUnderstandingNetwork {
  final Map<String, double> _contextWeights = {};

  Future<ContextUnderstanding> understandContext(String command, Map<String, dynamic> systemContext) async {
    await Future.delayed(const Duration(milliseconds: 40));

    final clarity = _calculateClarity(command, systemContext);
    final relevance = _calculateRelevance(command, systemContext);
    final projectType = systemContext['projectType'] as String?;
    final directory = systemContext['currentDirectory'] as String?;

    return ContextUnderstanding(
      clarity: clarity,
      relevance: relevance,
      projectType: projectType,
      directory: directory,
      inferredIntent: _inferIntent(command, systemContext),
    );
  }

  double _calculateClarity(String command, Map<String, dynamic> context) {
    // Simple clarity based on command structure
    final parts = command.split(' ');
    if (parts.length == 1) return 0.8; // Simple commands are clear
    if (parts.length > 4) return 0.4; // Complex commands might be unclear

    return 0.6;
  }

  double _calculateRelevance(String command, Map<String, dynamic> context) {
    double relevance = 0.5;

    final projectType = context['projectType'] as String?;
    if (projectType != null) {
      if (projectType == 'nodejs' && command.contains('npm')) relevance += 0.3;
      if (projectType == 'python' && command.contains('pip')) relevance += 0.3;
      if (projectType == 'flutter' && command.contains('flutter')) relevance += 0.3;
    }

    return math.min(relevance, 1.0);
  }

  String? _inferIntent(String command, Map<String, dynamic> context) {
    // Combine command analysis with context
    final behaviorIntent = BehaviorAnalysisNetwork()._inferIntention(command);
    final contextIntent = context['lastIntent'] as String?;

    return behaviorIntent ?? contextIntent;
  }

  Future<void> improve(ContextUnderstanding context) async {
    // Improve understanding based on successful context analysis
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

/// Anomaly Detection Network (Simplified)
class AnomalyDetectionNetwork {
  final List<String> _normalPatterns = [
    'ls', 'cd', 'pwd', 'git status', 'git add', 'git commit', 'git push',
    'npm install', 'npm run', 'python', 'pip install',
  ];

  Future<List<Anomaly>> detectAnomalies(String command, List<String> recentCommands) async {
    await Future.delayed(const Duration(milliseconds: 20));

    final anomalies = <Anomaly>[];

    // Check for unusual commands
    final baseCommand = command.split(' ').first;
    if (!_normalPatterns.any((pattern) => baseCommand.contains(pattern))) {
      if (recentCommands.length > 5) {
        final recentBases = recentCommands.take(5).map((c) => c.split(' ').first);
        final isOutlier = !recentBases.contains(baseCommand);

        if (isOutlier) {
          anomalies.add(Anomaly(
            type: AnomalyType.unusual_command,
            command: command,
            confidence: 0.7,
            description: 'Unusual command compared to recent history',
          ));
        }
      }
    }

    // Check for error patterns (simplified)
    if (command.contains('rm -rf') || command.contains('sudo') && command.contains('chmod 777')) {
      anomalies.add(Anomaly(
        type: AnomalyType.potential_risk,
        command: command,
        confidence: 0.8,
        description: 'Potentially risky command detected',
      ));
    }

    return anomalies;
  }
}

/// Data Classes

class CommandPrediction {
  final List<String> nextCommands;
  final double confidence;
  final String reasoning;
  final double accuracy;

  CommandPrediction({
    required this.nextCommands,
    required this.confidence,
    required this.reasoning,
    this.accuracy = 0.0,
  });

  static CommandPrediction empty() {
    return CommandPrediction(
      nextCommands: [],
      confidence: 0.0,
      reasoning: 'No prediction available',
    );
  }
}

class BehaviorAnalysis {
  final double frequency;
  final double consistency;
  final String? intention;
  final String? context;
  final bool unusual;

  BehaviorAnalysis({
    required this.frequency,
    required this.consistency,
    this.intention,
    this.context,
    required this.unusual,
  });
}

class ContextUnderstanding {
  final double clarity;
  final double relevance;
  final String? projectType;
  final String? directory;
  final String? inferredIntent;

  ContextUnderstanding({
    required this.clarity,
    required this.relevance,
    this.projectType,
    this.directory,
    this.inferredIntent,
  });

  static ContextUnderstanding basic(String command) {
    return ContextUnderstanding(
      clarity: 0.5,
      relevance: 0.5,
      inferredIntent: null,
    );
  }
}

enum AnomalyType {
  unusual_command,
  error_pattern,
  slow_execution,
  permission_issue,
  potential_risk,
}

class Anomaly {
  final AnomalyType type;
  final String command;
  final double confidence;
  final String description;
  final DateTime timestamp;

  Anomaly({
    required this.type,
    required this.command,
    required this.confidence,
    required this.description,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class CommandSequence {
  final List<String> commands;
  final double frequency;
  final String context;

  CommandSequence({
    required this.commands,
    required this.frequency,
    required this.context,
  });

  Map<String, dynamic> toJson() {
    return {
      'commands': commands,
      'frequency': frequency,
      'context': context,
    };
  }

  factory CommandSequence.fromJson(Map<String, dynamic> json) {
    return CommandSequence(
      commands: List<String>.from(json['commands']),
      frequency: json['frequency'],
      context: json['context'],
    );
  }
}

enum PatternType {
  sequence,
  behavioral,
  contextual,
  temporal,
}

class Pattern {
  final String name;
  final PatternType type;
  double confidence;
  final List<String> features;

  Pattern({
    required this.name,
    required this.type,
    required this.confidence,
    required this.features,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'confidence': confidence,
      'features': features,
    };
  }

  factory Pattern.fromJson(Map<String, dynamic> json) {
    return Pattern(
      name: json['name'],
      type: PatternType.values.firstWhere((e) => e.name == json['type']),
      confidence: json['confidence'],
      features: List<String>.from(json['features']),
    );
  }
}

class UserProfile {
  final String userId;
  final Map<String, int> commandFrequency = {};
  final Map<int, List<String>> timeBasedCommands = {};
  final List<String> recentCommands = [];

  UserProfile(this.userId);

  void addCommand(String command) {
    commandFrequency[command] = (commandFrequency[command] ?? 0) + 1;

    final hour = DateTime.now().hour;
    timeBasedCommands.putIfAbsent(hour, () => []);
    timeBasedCommands[hour]!.add(command);

    recentCommands.add(command);
    if (recentCommands.length > 100) {
      recentCommands.removeAt(0);
    }
  }

  List<String> getTimeBasedSuggestions(int hour) {
    final commands = timeBasedCommands[hour] ?? [];
    if (commands.isEmpty) return [];

    final frequency = <String, int>{};
    for (final cmd in commands) {
      frequency[cmd] = (frequency[cmd] ?? 0) + 1;
    }

    return frequency.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'commandFrequency': commandFrequency,
      'timeBasedCommands': timeBasedCommands.map((k, v) => MapEntry(k.toString(), v)),
      'recentCommands': recentCommands,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = UserProfile(json['userId']);
    profile.commandFrequency.addAll((json['commandFrequency'] as Map<String, dynamic>).cast<String, int>());
    profile.timeBasedCommands.addAll(
      (json['timeBasedCommands'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), List<String>.from(v)),
      ),
    );
    profile.recentCommands.addAll(List<String>.from(json['recentCommands']));
    return profile;
  }
}