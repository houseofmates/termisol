import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Command pattern recognition system
class CommandPatternRecognizer {
  final Map<String, CommandPattern> _patterns = {};
  final List<CommandSequence> _sequences = [];
  final Map<String, double> _contextScores = {};
  
  Timer? _learningTimer;
  StreamController<CommandEvent> _eventController = StreamController<CommandEvent>.broadcast();
  Stream<CommandEvent> get events => _eventController.stream;
  
  void initialize() {
    _setupLearning();
    _loadKnownPatterns();
    developer.log('Command Pattern Recognizer initialized');
  }
  
  void _setupLearning() {
    _learningTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _analyzeCurrentContext();
    });
  }
  
  void _loadKnownPatterns() {
    // Load common command patterns
    _patterns['git'] = CommandPattern(
      context: 'git repository',
      commands: ['status', 'add', 'commit', 'push', 'pull'],
      sequences: [
        CommandSequence(
          trigger: 'git status',
          likelihood: 0.8,
          nextCommands: ['git add .', 'git commit'],
        ),
        CommandSequence(
          trigger: 'git add',
          likelihood: 0.9,
          nextCommands: ['git commit -m ""'],
        ),
        CommandSequence(
          trigger: 'git commit',
          likelihood: 0.7,
          nextCommands: ['git push'],
        ),
      ],
    );
    
    _patterns['docker'] = CommandPattern(
      context: 'docker containers',
      commands: ['ps', 'run', 'build', 'push'],
      sequences: [
        CommandSequence(
          trigger: 'docker ps',
          likelihood: 0.8,
          nextCommands: ['docker run', 'docker build'],
        ),
        CommandSequence(
          trigger: 'docker build',
          likelihood: 0.9,
          nextCommands: ['docker push'],
        ),
      ],
    );
    
    _patterns['flutter'] = CommandPattern(
      context: 'flutter development',
      commands: ['run', 'build', 'test', 'pub get'],
      sequences: [
        CommandSequence(
          trigger: 'flutter run',
          likelihood: 0.7,
          nextCommands: ['flutter build apk'],
        ),
        CommandSequence(
          trigger: 'flutter build',
          likelihood: 0.8,
          nextCommands: ['flutter install'],
        ),
      ],
    );
  }
  
  void _analyzeCurrentContext() {
    final context = _getCurrentContext();
    final recentCommands = _getRecentCommands();
    
    // Analyze command sequences
    final sequences = _extractSequences(recentCommands);
    for (final sequence in sequences) {
      _learnSequence(sequence, context);
    }
    
    // Update context scores
    _updateContextScores(context);
  }
  
  String _getCurrentContext() {
    // Simulate context detection
    // In real implementation, this would analyze current directory and recent commands
    final contexts = ['git', 'docker', 'flutter', 'debugging', 'testing'];
    return contexts[math.Random().nextInt(contexts.length)];
  }
  
  List<String> _getRecentCommands() {
    // Simulate getting recent commands
    // In real implementation, this would read from command history
    return [
      'git status',
      'ls -la',
      'docker ps',
      'flutter run',
      'git add .',
    ];
  }
  
  List<CommandSequence> _extractSequences(List<String> commands) {
    final sequences = <CommandSequence>[];
    
    for (int i = 0; i < commands.length - 2; i++) {
      final sequence = CommandSequence(
        commands: commands.sublist(i, i + 3),
        context: _getCurrentContext(),
        timestamp: DateTime.now(),
      );
      sequences.add(sequence);
    }
    
    return sequences;
  }
  
  void _learnSequence(CommandSequence sequence, String context) {
    final pattern = _patterns[context];
    if (pattern == null) {
      _createNewPattern(sequence, context);
      return;
    }
    
    // Add sequence to existing pattern
    pattern.sequences.add(sequence);
    
    // Update likelihoods
    _updateSequenceLikelihoods(pattern);
    
    _eventController.add(CommandEvent(
      type: CommandEventType.sequenceLearned,
      data: {
        'context': context,
        'sequence': sequence.commands,
        'timestamp': sequence.timestamp.toIso8601String(),
      },
    ));
  }
  
  void _createNewPattern(CommandSequence sequence, String context) {
    final pattern = CommandPattern(
      context: context,
      commands: sequence.commands.toSet(),
      sequences: [sequence],
    );
    
    _patterns[context] = pattern;
    
    _eventController.add(CommandEvent(
      type: CommandEventType.patternCreated,
      data: {
        'context': context,
        'commands': pattern.commands,
      },
    ));
  }
  
  void _updateSequenceLikelihoods(CommandPattern pattern) {
    for (final sequence in pattern.sequences) {
      sequence.likelihood = _calculateSequenceLikelihood(sequence, pattern);
    }
  }
  
  double _calculateSequenceLikelihood(CommandSequence sequence, CommandPattern pattern) {
    // Calculate likelihood based on frequency and context
    final frequency = _getSequenceFrequency(sequence, pattern);
    final recency = _getSequenceRecency(sequence);
    final contextMatch = _getContextMatch(sequence, pattern);
    
    return (frequency * 0.4 + recency * 0.4 + contextMatch * 0.2).clamp(0.0, 1.0);
  }
  
  double _getSequenceFrequency(CommandSequence sequence, CommandPattern pattern) {
    int count = 0;
    for (final seq in pattern.sequences) {
      if (_sequencesMatch(sequence.commands, seq.commands)) {
        count++;
      }
    }
    return count / pattern.sequences.length;
  }
  
  double _getSequenceRecency(CommandSequence sequence) {
    final hoursSince = DateTime.now().difference(sequence.timestamp).inHours;
    return math.max(0.0, 1.0 - (hoursSince / 24.0));
  }
  
  double _getContextMatch(CommandSequence sequence, CommandPattern pattern) {
    final sequenceContext = pattern.context;
    final currentContext = _getCurrentContext();
    
    return sequenceContext == currentContext ? 1.0 : 0.0;
  }
  
  bool _sequencesMatch(List<String> seq1, List<String> seq2) {
    if (seq1.length != seq2.length) return false;
    
    for (int i = 0; i < seq1.length; i++) {
      if (seq1[i] != seq2[i]) return false;
    }
    
    return true;
  }
  
  void _updateContextScores(String context) {
    _contextScores[context] = (_contextScores[context] ?? 0.0) + 0.1;
    
    // Decay scores over time
    for (final key in _contextScores.keys.toList()) {
      _contextScores[key] = _contextScores[key]! * 0.95;
    }
  }
  
  List<String> getNextCommands(String lastCommand) {
    final context = _getCurrentContext();
    final pattern = _patterns[context];
    
    if (pattern == null) {
      return [];
    }
    
    // Find matching sequences
    for (final sequence in pattern.sequences) {
      if (sequence.commands.isNotEmpty && sequence.commands.first == lastCommand) {
        return sequence.commands.skip(1).toList();
      }
    }
    
    return [];
  }
  
  CommandPattern? getPatternForContext(String context) {
    return _patterns[context];
  }
  
  List<CommandPattern> getPatterns() {
    return _patterns.values.toList();
  }
  
  void dispose() {
    _learningTimer?.cancel();
    _eventController.close();
  }
}

class CommandPattern {
  final String context;
  final Set<String> commands;
  final List<CommandSequence> sequences;
  
  CommandPattern({
    required this.context,
    required this.commands,
    required this.sequences,
  });
}

class CommandSequence {
  final List<String> commands;
  final String context;
  final DateTime timestamp;
  double likelihood;
  
  CommandSequence({
    required this.commands,
    required this.context,
    required this.timestamp,
    this.likelihood = 0.5,
  });
}

enum CommandEventType {
  sequenceLearned,
  patternCreated,
}

class CommandEvent {
  final CommandEventType type;
  final Map<String, dynamic> data;
  
  CommandEvent({
    required this.type,
    required this.data,
  });
}
