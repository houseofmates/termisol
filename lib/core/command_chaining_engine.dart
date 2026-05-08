import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Command Chaining Engine - Intelligent command sequence suggestions
class CommandChainingEngine {
  static final CommandChainingEngine _instance = CommandChainingEngine._internal();
  factory CommandChainingEngine() => _instance;
  CommandChainingEngine._internal();

  final Map<String, CommandChain> _chains = {};
  final Queue<CommandSequence> _history = Queue();
  final Map<String, double> _chainFrequency = {};
  final Map<String, List<String>> _contextualChains = {};
  
  bool _isInitialized = false;
  Timer? _learningTimer;
  
  static const Duration _learningInterval = Duration(minutes: 3);
  static const int _maxHistory = 2000;
  static const int _maxChainLength = 10;
  static const int _maxSuggestions = 5;
  
  final _chainingController = StreamController<ChainingEvent>.broadcast();
  Stream<ChainingEvent> get events => _chainingController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _loadPredefinedChains();
    _startLearningTimer();
    _isInitialized = true;
    debugPrint('🔗 Command Chaining Engine initialized');
  }

  List<CommandChain> suggestChains(String lastCommand, String currentDirectory) {
    final suggestions = <CommandChain>[];
    
    // Direct chain matches
    final directChains = _getDirectChains(lastCommand);
    suggestions.addAll(directChains);
    
    // Contextual chains
    final contextualSuggestions = _getContextualChains(lastCommand, currentDirectory);
    suggestions.addAll(contextualSuggestions);
    
    // Pattern-based chains
    final patternChains = _getPatternChains(lastCommand, currentDirectory);
    suggestions.addAll(patternChains);
    
    // ML-predicted chains
    final mlChains = _getMLPredictedChains(lastCommand, currentDirectory);
    suggestions.addAll(mlChains);
    
    // Sort by confidence and deduplicate
    final uniqueChains = <String, CommandChain>{};
    for (final chain in suggestions) {
      final key = chain.commands.join('|');
      if (!uniqueChains.containsKey(key)) {
        uniqueChains[key] = chain;
      }
    }
    
    final sortedChains = uniqueChains.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return sortedChains.take(_maxSuggestions).toList();
  }

  void recordCommandSequence(List<String> commands, String directory, bool successful) {
    if (commands.length < 2) return;
    
    final sequence = CommandSequence(
      commands: commands,
      directory: directory,
      timestamp: DateTime.now(),
      successful: successful,
    );
    
    _history.add(sequence);
    if (_history.length > _maxHistory) {
      _history.removeFirst();
    }
    
    // Update chain frequency
    for (int i = 0; i < commands.length - 1; i++) {
      final key = '${commands[i]}|${commands[i + 1]}';
      _chainFrequency[key] = (_chainFrequency[key] ?? 0.0) + 1.0;
    }
    
    // Learn longer chains
    _learnLongerChains(commands, directory);
    
    _chainingController.add(ChainingEvent(
      type: ChainingEventType.sequenceRecorded,
      data: {
        'commands': commands,
        'directory': directory,
        'successful': successful,
      },
    ));
  }

  List<CommandChain> _getDirectChains(String lastCommand) {
    final chains = <CommandChain>[];
    
    for (final entry in _chains.entries) {
      if (entry.value.commands.isNotEmpty && 
          entry.value.commands.first == lastCommand) {
        chains.add(entry.value);
      }
    }
    
    return chains;
  }

  List<CommandChain> _getContextualChains(String lastCommand, String currentDirectory) {
    final chains = <CommandChain>[];
    final context = _detectContext(currentDirectory);
    
    final contextualKeys = _contextualChains[context] ?? [];
    for (final key in contextualKeys) {
      final chain = _chains[key];
      if (chain != null && chain.commands.contains(lastCommand)) {
        chains.add(chain);
      }
    }
    
    return chains;
  }

  List<CommandChain> _getPatternChains(String lastCommand, String currentDirectory) {
    final chains = <CommandChain>[];
    
    // Git workflow patterns
    if (lastCommand.startsWith('git')) {
      chains.addAll(_getGitWorkflowChains(lastCommand));
    }
    
    // Build/deploy patterns
    if (_isBuildCommand(lastCommand)) {
      chains.addAll(_getBuildWorkflowChains(lastCommand));
    }
    
    // Development patterns
    if (_isDevelopmentCommand(lastCommand)) {
      chains.addAll(_getDevelopmentWorkflowChains(lastCommand));
    }
    
    return chains;
  }

  List<CommandChain> _getMLPredictedChains(String lastCommand, String currentDirectory) {
    final chains = <CommandChain>[];
    
    // Analyze recent successful sequences
    final recentSequences = _history.reversed
        .where((seq) => seq.successful && seq.commands.contains(lastCommand))
        .take(20)
        .toList();
    
    for (final sequence in recentSequences) {
      final commandIndex = sequence.commands.indexOf(lastCommand);
      if (commandIndex >= 0 && commandIndex < sequence.commands.length - 1) {
        final remainingCommands = sequence.commands.sublist(commandIndex + 1);
        
        if (remainingCommands.isNotEmpty) {
          final confidence = _calculateMLConfidence(sequence, lastCommand);
          chains.add(CommandChain(
            commands: remainingCommands,
            confidence: confidence,
            source: ChainSource.ml,
            description: 'Based on recent usage',
            context: sequence.directory,
          ));
        }
      }
    }
    
    return chains;
  }

  List<CommandChain> _getGitWorkflowChains(String lastCommand) {
    final gitChains = <CommandChain>[];
    
    switch (lastCommand) {
      case 'git status':
        gitChains.add(CommandChain(
          commands: ['git add .', 'git commit -m "Update"', 'git push'],
          confidence: 0.9,
          source: ChainSource.pattern,
          description: 'Commit and push changes',
          context: 'git',
        ));
        break;
      case 'git add .':
        gitChains.add(CommandChain(
          commands: ['git commit -m "Update"', 'git status'],
          confidence: 0.8,
          source: ChainSource.pattern,
          description: 'Commit and check status',
          context: 'git',
        ));
        break;
      case 'git commit':
        gitChains.add(CommandChain(
          commands: ['git push', 'git status'],
          confidence: 0.85,
          source: ChainSource.pattern,
          description: 'Push and verify',
          context: 'git',
        ));
        break;
      case 'git pull':
        gitChains.add(CommandChain(
          commands: ['git status', 'npm install'],
          confidence: 0.7,
          source: ChainSource.pattern,
          description: 'Update dependencies',
          context: 'git',
        ));
        break;
    }
    
    return gitChains;
  }

  List<CommandChain> _getBuildWorkflowChains(String lastCommand) {
    final buildChains = <CommandChain>[];
    
    if (lastCommand.contains('build') || lastCommand.contains('compile')) {
      buildChains.add(CommandChain(
        commands: ['npm test', 'npm run deploy'],
        confidence: 0.8,
        source: ChainSource.pattern,
        description: 'Test and deploy after build',
        context: 'build',
      ));
      
      buildChains.add(CommandChain(
        commands: ['docker build -t app .', 'docker run app'],
        confidence: 0.7,
        source: ChainSource.pattern,
        description: 'Docker build and run',
        context: 'docker',
      ));
    }
    
    return buildChains;
  }

  List<CommandChain> _getDevelopmentWorkflowChains(String lastCommand) {
    final devChains = <CommandChain>[];
    
    if (lastCommand.contains('npm install')) {
      devChains.add(CommandChain(
        commands: ['npm run dev', 'npm test'],
        confidence: 0.85,
        source: ChainSource.pattern,
        description: 'Start development and test',
        context: 'development',
      ));
    }
    
    if (lastCommand.contains('pip install')) {
      devChains.add(CommandChain(
        commands: ['python -m pytest', 'python app.py'],
        confidence: 0.8,
        source: ChainSource.pattern,
        description: 'Test and run Python app',
        context: 'python',
      ));
    }
    
    return devChains;
  }

  void _learnLongerChains(List<String> commands, String directory) {
    for (int length = 3; length <= math.min(commands.length, _maxChainLength); length++) {
      for (int i = 0; i <= commands.length - length; i++) {
        final subChain = commands.sublist(i, i + length);
        final key = subChain.join('|');
        
        if (!_chains.containsKey(key)) {
          final confidence = _calculateChainConfidence(subChain);
          final chain = CommandChain(
            commands: subChain,
            confidence: confidence,
            source: ChainSource.learned,
            description: 'Learned chain',
            context: directory,
          );
          
          _chains[key] = chain;
          
          // Add to contextual chains
          final context = _detectContext(directory);
          _contextualChains.putIfAbsent(context, () => []).add(key);
        }
      }
    }
  }

  double _calculateChainConfidence(List<String> commands) {
    double confidence = 0.0;
    int validPairs = 0;
    
    for (int i = 0; i < commands.length - 1; i++) {
      final key = '${commands[i]}|${commands[i + 1]}';
      final frequency = _chainFrequency[key] ?? 0.0;
      if (frequency > 0) {
        confidence += frequency;
        validPairs++;
      }
    }
    
    return validPairs > 0 ? confidence / validPairs : 0.1;
  }

  double _calculateMLConfidence(CommandSequence sequence, String lastCommand) {
    final age = DateTime.now().difference(sequence.timestamp).inMinutes;
    final ageWeight = math.max(0.1, 1.0 - (age / 1440.0)); // Decay over 24 hours
    
    final successWeight = sequence.successful ? 1.0 : 0.3;
    final directoryWeight = sequence.directory == _getCurrentDirectory() ? 1.2 : 0.8;
    
    return ageWeight * successWeight * directoryWeight * 0.5;
  }

  bool _isBuildCommand(String command) {
    final buildKeywords = ['build', 'compile', 'make', 'cmake', 'gradle', 'maven'];
    return buildKeywords.any((keyword) => command.contains(keyword));
  }

  bool _isDevelopmentCommand(String command) {
    final devKeywords = ['npm', 'yarn', 'pip', 'poetry', 'cargo', 'go run'];
    return devKeywords.any((keyword) => command.contains(keyword));
  }

  String _detectContext(String directory) {
    if (directory.contains('node_modules')) return 'nodejs';
    if (directory.contains('requirements.txt') || directory.contains('venv')) return 'python';
    if (directory.contains('Cargo.toml')) return 'rust';
    if (directory.contains('go.mod')) return 'go';
    if (directory.contains('.git')) return 'git';
    return 'general';
  }

  String _getCurrentDirectory() {
    // This would get the current working directory
    return '/home/house/termisol';
  }

  void _loadPredefinedChains() {
    // Git workflow chains
    _chains['git_workflow'] = CommandChain(
      commands: ['git status', 'git add .', 'git commit -m "Update"', 'git push'],
      confidence: 0.9,
      source: ChainSource.predefined,
      description: 'Complete git workflow',
      context: 'git',
    );
    
    // Development chains
    _chains['dev_workflow'] = CommandChain(
      commands: ['npm install', 'npm run dev', 'npm test'],
      confidence: 0.85,
      source: ChainSource.predefined,
      description: 'Development workflow',
      context: 'development',
    );
    
    // Docker chains
    _chains['docker_workflow'] = CommandChain(
      commands: ['docker build -t app .', 'docker run app', 'docker logs'],
      confidence: 0.8,
      source: ChainSource.predefined,
      description: 'Docker workflow',
      context: 'docker',
    );
  }

  void _startLearningTimer() {
    _learningTimer = Timer.periodic(_learningInterval, (_) {
      _optimizeChains();
    });
  }

  void _optimizeChains() {
    // Remove low-confidence chains
    final chainsToRemove = <String>[];
    
    for (final entry in _chains.entries) {
      if (entry.value.confidence < 0.2 && entry.value.source == ChainSource.learned) {
        chainsToRemove.add(entry.key);
      }
    }
    
    for (final key in chainsToRemove) {
      _chains.remove(key);
    }
    
    // Update contextual chains
    for (final entry in _contextualChains.entries) {
      final validKeys = entry.value.where((key) => _chains.containsKey(key)).toList();
      _contextualChains[entry.key] = validKeys;
    }
    
    if (chainsToRemove.isNotEmpty) {
      debugPrint('🔗 Optimized chains: removed ${chainsToRemove.length} low-confidence chains');
    }
    
    _chainingController.add(ChainingEvent(
      type: ChainingEventType.chainsOptimized,
      data: {
        'chains_removed': chainsToRemove.length,
        'total_chains': _chains.length,
      },
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'total_chains': _chains.length,
      'chain_history': _history.length,
      'chain_frequency': _chainFrequency.length,
      'contextual_chains': _contextualChains.length,
      'predefined_chains': _chains.values.where((c) => c.source == ChainSource.predefined).length,
      'learned_chains': _chains.values.where((c) => c.source == ChainSource.learned).length,
    };
  }

  Future<void> dispose() async {
    _learningTimer?.cancel();
    _chainingController.close();
    _chains.clear();
    _history.clear();
    _chainFrequency.clear();
    _contextualChains.clear();
  }
}

class CommandChain {
  final List<String> commands;
  final double confidence;
  final ChainSource source;
  final String description;
  final String context;
  
  CommandChain({
    required this.commands,
    required this.confidence,
    required this.source,
    required this.description,
    required this.context,
  });
}

class CommandSequence {
  final List<String> commands;
  final String directory;
  final DateTime timestamp;
  final bool successful;
  
  CommandSequence({
    required this.commands,
    required this.directory,
    required this.timestamp,
    required this.successful,
  });
}

class ChainingEvent {
  final ChainingEventType type;
  final Map<String, dynamic>? data;
  
  ChainingEvent({
    required this.type,
    this.data,
  });
}

enum ChainSource {
  predefined,
  learned,
  pattern,
  ml,
}

enum ChainingEventType {
  sequenceRecorded,
  chainsOptimized,
}
