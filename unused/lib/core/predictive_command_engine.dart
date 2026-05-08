import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Predictive Command Engine - ML-based command prediction and completion
class PredictiveCommandEngine {
  static final PredictiveCommandEngine _instance = PredictiveCommandEngine._internal();
  factory PredictiveCommandEngine() => _instance;
  PredictiveCommandEngine._internal();

  final Map<String, CommandPattern> _patterns = {};
  final Queue<CommandHistory> _history = Queue();
  final Map<String, double> _commandFrequency = {};
  final Map<String, List<String>> _commandChains = {};
  
  bool _isInitialized = false;
  Timer? _trainingTimer;
  
  static const Duration _trainingInterval = Duration(minutes: 5);
  static const int _maxHistory = 1000;
  static const int _maxSuggestions = 10;
  
  final _predictionController = StreamController<PredictionEvent>.broadcast();
  Stream<PredictionEvent> get events => _predictionController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _loadCommandPatterns();
    _startTrainingTimer();
    _isInitialized = true;
    debugPrint('🤖 Predictive Command Engine initialized');
  }

  List<CommandSuggestion> predictCommand(String input, String currentDirectory) {
    final suggestions = <CommandSuggestion>[];
    
    // Pattern-based predictions
    final patternSuggestions = _predictFromPatterns(input);
    suggestions.addAll(patternSuggestions);
    
    // Frequency-based predictions
    final frequencySuggestions = _predictFromFrequency(input);
    suggestions.addAll(frequencySuggestions);
    
    // Context-aware predictions
    final contextSuggestions = _predictFromContext(input, currentDirectory);
    suggestions.addAll(contextSuggestions);
    
    // Chain-based predictions
    final chainSuggestions = _predictFromChains(input);
    suggestions.addAll(chainSuggestions);
    
    // Sort by confidence and deduplicate
    final uniqueSuggestions = <String, CommandSuggestion>{};
    for (final suggestion in suggestions) {
      if (!uniqueSuggestions.containsKey(suggestion.command)) {
        uniqueSuggestions[suggestion.command] = suggestion;
      }
    }
    
    final sortedSuggestions = uniqueSuggestions.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return sortedSuggestions.take(_maxSuggestions).toList();
  }

  List<String> suggestCommandChain(String lastCommand) {
    return _commandChains[lastCommand] ?? [];
  }

  void recordCommand(String command, String directory, bool successful) {
    final history = CommandHistory(
      command: command,
      directory: directory,
      timestamp: DateTime.now(),
      successful: successful,
    );
    
    _history.add(history);
    if (_history.length > _maxHistory) {
      _history.removeFirst();
    }
    
    // Update frequency
    _commandFrequency[command] = (_commandFrequency[command] ?? 0.0) + 1.0;
    
    // Update chains
    if (_history.length > 1) {
      final previousCommand = _history.elementAt(_history.length - 2).command;
      _commandChains.putIfAbsent(previousCommand, () => []).add(command);
    }
    
    _predictionController.add(PredictionEvent(
      type: PredictionEventType.commandRecorded,
      data: {'command': command, 'directory': directory},
    ));
  }

  List<CommandSuggestion> _predictFromPatterns(String input) {
    final suggestions = <CommandSuggestion>[];
    
    for (final pattern in _patterns.values) {
      final match = pattern.regex.firstMatch(input);
      if (match != null) {
        final confidence = pattern.confidence;
        suggestions.add(CommandSuggestion(
          command: pattern.suggestion,
          confidence: confidence,
          source: SuggestionSource.pattern,
          description: pattern.description,
        ));
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _predictFromFrequency(String input) {
    final suggestions = <CommandSuggestion>[];
    
    for (final entry in _commandFrequency.entries) {
      if (entry.key.startsWith(input)) {
        final confidence = math.min(entry.value / 100.0, 1.0);
        suggestions.add(CommandSuggestion(
          command: entry.key,
          confidence: confidence,
          source: SuggestionSource.frequency,
          description: 'Used ${entry.value.toInt()} times',
        ));
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _predictFromContext(String input, String directory) {
    final suggestions = <CommandSuggestion>[];
    
    // Directory-specific suggestions
    if (directory.contains('git')) {
      suggestions.addAll(_getGitSuggestions(input));
    } else if (directory.contains('node_modules')) {
      suggestions.addAll(_getNodeSuggestions(input));
    } else if (directory.contains('docker')) {
      suggestions.addAll(_getDockerSuggestions(input));
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _predictFromChains(String input) {
    final suggestions = <CommandSuggestion>[];
    
    // Find recent commands that match input
    final recentCommands = _history.reversed
        .where((h) => h.command.startsWith(input) && h.successful)
        .take(5)
        .map((h) => h.command)
        .toList();
    
    for (final command in recentCommands) {
      final chains = _commandChains[command] ?? [];
      for (final nextCommand in chains.take(3)) {
        suggestions.add(CommandSuggestion(
          command: nextCommand,
          confidence: 0.7,
          source: SuggestionSource.chain,
          description: 'Often follows: $command',
        ));
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getGitSuggestions(String input) {
    final gitCommands = [
      'git status', 'git add .', 'git commit -m', 'git push',
      'git pull', 'git branch', 'git checkout', 'git merge',
      'git log --oneline', 'git diff', 'git stash', 'git reset'
    ];
    
    return gitCommands
        .where((cmd) => cmd.startsWith(input))
        .map((cmd) => CommandSuggestion(
          command: cmd,
          confidence: 0.8,
          source: SuggestionSource.context,
          description: 'Git command',
        ))
        .toList();
  }

  List<CommandSuggestion> _getNodeSuggestions(String input) {
    final nodeCommands = [
      'npm install', 'npm run', 'npm test', 'npm build',
      'yarn install', 'yarn start', 'yarn test', 'yarn build',
      'node index.js', 'npm run dev', 'yarn dev'
    ];
    
    return nodeCommands
        .where((cmd) => cmd.startsWith(input))
        .map((cmd) => CommandSuggestion(
          command: cmd,
          confidence: 0.8,
          source: SuggestionSource.context,
          description: 'Node.js command',
        ))
        .toList();
  }

  List<CommandSuggestion> _getDockerSuggestions(String input) {
    final dockerCommands = [
      'docker ps', 'docker images', 'docker build -t', 'docker run',
      'docker-compose up', 'docker-compose down', 'docker logs',
      'docker exec -it', 'docker stop', 'docker rm'
    ];
    
    return dockerCommands
        .where((cmd) => cmd.startsWith(input))
        .map((cmd) => CommandSuggestion(
          command: cmd,
          confidence: 0.8,
          source: SuggestionSource.context,
          description: 'Docker command',
        ))
        .toList();
  }

  void _loadCommandPatterns() {
    _patterns['git'] = CommandPattern(
      regex: RegExp(r'^git\s*'),
      suggestion: 'git status',
      confidence: 0.9,
      description: 'Show git repository status',
    );
    
    _patterns['ls'] = CommandPattern(
      regex: RegExp(r'^ls\s*'),
      suggestion: 'ls -la',
      confidence: 0.8,
      description: 'List files with details',
    );
    
    _patterns['cd'] = CommandPattern(
      regex: RegExp(r'^cd\s*'),
      suggestion: 'cd ..',
      confidence: 0.7,
      description: 'Go to parent directory',
    );
  }

  void _startTrainingTimer() {
    _trainingTimer = Timer.periodic(_trainingInterval, (_) {
      _retrainModel();
    });
  }

  void _retrainModel() {
    // Simplified ML training - update frequencies and patterns
    for (final entry in _commandFrequency.entries) {
      // Decay old frequencies
      _commandFrequency[entry.key] = entry.value * 0.95;
    }
    
    _predictionController.add(PredictionEvent(
      type: PredictionEventType.modelRetrained,
      data: {'patterns': _patterns.length, 'history': _history.length},
    ));
  }

  Future<void> dispose() async {
    _trainingTimer?.cancel();
    _predictionController.close();
    _patterns.clear();
    _history.clear();
    _commandFrequency.clear();
    _commandChains.clear();
  }
}

class CommandPattern {
  final RegExp regex;
  final String suggestion;
  final double confidence;
  final String description;
  
  CommandPattern({
    required this.regex,
    required this.suggestion,
    required this.confidence,
    required this.description,
  });
}

class CommandHistory {
  final String command;
  final String directory;
  final DateTime timestamp;
  final bool successful;
  
  CommandHistory({
    required this.command,
    required this.directory,
    required this.timestamp,
    required this.successful,
  });
}

class CommandSuggestion {
  final String command;
  final double confidence;
  final SuggestionSource source;
  final String description;
  
  CommandSuggestion({
    required this.command,
    required this.confidence,
    required this.source,
    required this.description,
  });
}

class PredictionEvent {
  final PredictionEventType type;
  final Map<String, dynamic>? data;
  
  PredictionEvent({
    required this.type,
    this.data,
  });
}

enum PredictionEventType {
  commandRecorded,
  modelRetrained,
}

enum SuggestionSource {
  pattern,
  frequency,
  context,
  chain,
}
