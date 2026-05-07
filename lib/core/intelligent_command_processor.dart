import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Intelligent command processor with smart queueing and context awareness
/// 
/// Features:
/// - Smart command queueing with batching
/// - Context-aware suggestions
/// - Fuzzy command matching without over-matching
/// - Command history intelligence with semantic search
/// - Background process management
class IntelligentCommandProcessor {
  final Queue<FileOperation> _operationQueue = Queue<FileOperation>();
  final List<CommandHistory> _commandHistory = [];
  final Map<String, CommandPattern> _commandPatterns = {};
  final Map<String, List<CommandSuggestion>> _contextSuggestions = {};
  
  Timer? _batchTimer;
  Timer? _suggestionTimer;
  Timer? _backgroundProcessTimer;
  
  bool _isProcessing = false;
  String _currentContext = '';
  String _currentDirectory = '';
  List<BackgroundProcess> _backgroundProcesses = [];
  
  StreamController<CommandEvent> _eventController = StreamController<CommandEvent>.broadcast();
  Stream<CommandEvent> get events => _eventController.stream;
  
  void initialize() {
    _setupBatching();
    _setupSuggestionEngine();
    _setupBackgroundProcessManager();
    _loadCommandPatterns();
    developer.log('IntelligentCommandProcessor initialized');
  }
  
  void _setupBatching() {
    _batchTimer = Timer.periodic(Duration(milliseconds: 50), (_) {
      _processBatchedCommands();
    });
  }
  
  void _setupSuggestionEngine() {
    _suggestionTimer = Timer.periodic(Duration(milliseconds: 200), (_) {
      _updateSuggestions();
    });
  }
  
  void _setupBackgroundProcessManager() {
    _backgroundProcessTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _manageBackgroundProcesses();
    });
  }
  
  void _loadCommandPatterns() {
    // Load common command patterns
    _commandPatterns['git'] = CommandPattern(
      commands: ['status', 'add', 'commit', 'push', 'pull'],
      context: 'git repository',
      suggestions: ['git status', 'git add .', 'git commit -m ""'],
    );
    
    _commandPatterns['docker'] = CommandPattern(
      commands: ['ps', 'run', 'build', 'push'],
      context: 'docker containers',
      suggestions: ['docker ps -a', 'docker run -it', 'docker build -t .'],
    );
    
    _commandPatterns['npm'] = CommandPattern(
      commands: ['install', 'run', 'build', 'test'],
      context: 'node.js project',
      suggestions: ['npm install', 'npm run dev', 'npm run build'],
    );
    
    _commandPatterns['flutter'] = CommandPattern(
      commands: ['run', 'build', 'test', 'pub get'],
      context: 'flutter project',
      suggestions: ['flutter run', 'flutter build apk', 'flutter test'],
    );
  }
  
  void updateContext(String context, String directory) {
    _currentContext = context;
    _currentDirectory = directory;
    _updateContextSuggestions();
  }
  
  void queueCommand(String command, {bool priority = false}) {
    final request = CommandRequest(
      command: command,
      timestamp: DateTime.now(),
      priority: priority,
      context: _currentContext,
      directory: _currentDirectory,
    );
    
    if (priority) {
      _commandQueue.addFirst(request);
    } else {
      _commandQueue.add(request);
    }
  }
  
  void _processBatchedCommands() {
    if (_isProcessing || _commandQueue.isEmpty) return;
    
    _isProcessing = true;
    final batch = <CommandRequest>[];
    
    // Process up to 5 commands per batch
    while (batch.length < 5 && _commandQueue.isNotEmpty) {
      batch.add(_commandQueue.removeFirst());
    }
    
    for (final request in batch) {
      _executeCommand(request);
    }
    
    _isProcessing = false;
  }
  
  Future<void> _executeCommand(CommandRequest request) async {
    try {
      developer.log('Executing command: ${request.command}');
      
      // Check if command should run in background
      if (_isBackgroundCommand(request.command)) {
        _startBackgroundProcess(request);
      } else {
        _executeForegroundCommand(request);
      }
      
      // Add to history
      _addToHistory(request);
      
      _eventController.add(CommandEvent(
        type: CommandEventType.executed,
        data: {
          'command': request.command,
          'context': request.context,
          'directory': request.directory,
          'timestamp': request.timestamp.toIso8601String(),
        },
      ));
      
    } catch (e) {
      developer.log('Command execution failed: $e');
      _eventController.add(CommandEvent(
        type: CommandEventType.error,
        data: {
          'command': request.command,
          'error': e.toString(),
        },
      ));
    }
  }
  
  void _executeForegroundCommand(CommandRequest request) {
    // Execute command synchronously for foreground
    // In real implementation, this would interact with terminal
    developer.log('Foreground command: ${request.command}');
  }
  
  void _startBackgroundProcess(CommandRequest request) {
    final process = BackgroundProcess(
      id: _backgroundProcesses.length,
      command: request.command,
      startTime: DateTime.now(),
      status: ProcessStatus.running,
    );
    
    _backgroundProcesses.add(process);
    
    _eventController.add(CommandEvent(
      type: CommandEventType.backgroundProcessStarted,
      data: {
        'processId': process.id,
        'command': request.command,
      },
    ));
  }
  
  bool _isBackgroundCommand(String command) {
    final backgroundCommands = ['&', 'nohup', 'screen', 'tmux'];
    return backgroundCommands.any((bg) => command.contains(bg));
  }
  
  void _addToHistory(CommandRequest request) {
    final history = CommandHistory(
      command: request.command,
      timestamp: request.timestamp,
      context: request.context,
      directory: request.directory,
    );
    
    _commandHistory.add(history);
    
    // Keep only last 1000 commands
    if (_commandHistory.length > 1000) {
      _commandHistory.removeAt(0);
    }
  }
  
  void _updateSuggestions() {
    final currentInput = _getCurrentInput();
    if (currentInput.isEmpty) return;
    
    final suggestions = _generateSuggestions(currentInput);
    _contextSuggestions[_currentContext] = suggestions;
    
    _eventController.add(CommandEvent(
      type: CommandEventType.suggestionsUpdated,
      data: {
        'input': currentInput,
        'suggestions': suggestions.map((s) => s.toJson()).toList(),
      },
    ));
  }
  
  void _updateContextSuggestions() {
    final context = _currentContext;
    final pattern = _commandPatterns[context];
    
    if (pattern != null) {
      _contextSuggestions[context] = pattern.suggestions.map((s) => 
          CommandSuggestion(text: s, type: SuggestionType.contextual)
      ).toList();
    }
  }
  
  List<CommandSuggestion> _generateSuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    
    // Fuzzy matching with confidence scoring
    suggestions.addAll(_fuzzyMatchCommands(input));
    
    // Context-aware suggestions
    suggestions.addAll(_getContextualSuggestions(input));
    
    // History-based suggestions
    suggestions.addAll(_getHistorySuggestions(input));
    
    // Sort by confidence and remove duplicates
    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return suggestions.take(10).toList();
  }
  
  List<CommandSuggestion> _fuzzyMatchCommands(String input) {
    final suggestions = <CommandSuggestion>[];
    final inputLower = input.toLowerCase();
    
    for (final history in _commandHistory.take(100)) {
      final command = history.command.toLowerCase();
      final similarity = _calculateSimilarity(inputLower, command);
      
      if (similarity > 0.6 && similarity < 1.0) {
        suggestions.add(CommandSuggestion(
          text: history.command,
          type: SuggestionType.fuzzy,
          confidence: similarity,
          description: 'Recent command',
        ));
      }
    }
    
    return suggestions;
  }
  
  List<CommandSuggestion> _getContextualSuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    final contextSuggestions = _contextSuggestions[_currentContext] ?? [];
    
    for (final suggestion in contextSuggestions) {
      final suggestionLower = suggestion.text.toLowerCase();
      final inputLower = input.toLowerCase();
      
      if (suggestionLower.contains(inputLower)) {
        suggestions.add(CommandSuggestion(
          text: suggestion.text,
          type: SuggestionType.contextual,
          confidence: 0.9,
          description: 'Contextual suggestion',
        ));
      }
    }
    
    return suggestions;
  }
  
  List<CommandSuggestion> _getHistorySuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    final inputLower = input.toLowerCase();
    
    // Get recent commands with semantic relevance
    final recentCommands = _commandHistory.take(20).where((history) {
      final command = history.command.toLowerCase();
      return command.contains(inputLower) && 
             _isSemanticallyRelevant(input, command, history.context);
    }).toList();
    
    for (final history in recentCommands) {
      suggestions.add(CommandSuggestion(
        text: history.command,
        type: SuggestionType.history,
        confidence: 0.8,
        description: 'Recent command (${history.context})',
      ));
    }
    
    return suggestions;
  }
  
  double _calculateSimilarity(String a, String b) {
    // Levenshtein distance for fuzzy matching
    final distance = _levenshteinDistance(a, b);
    final maxLength = math.max(a.length, b.length);
    
    if (maxLength == 0) return 1.0;
    return 1.0 - (distance / maxLength);
  }
  
  int _levenshteinDistance(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : 0),
    );
    
    for (int i = 1; i <= a.length; i++) {
      matrix[i][0] = i;
      
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    
    return matrix[a.length][b.length];
  }
  
  bool _isSemanticallyRelevant(String input, String command, String context) {
    // Simple semantic relevance check
    final inputWords = input.split(' ');
    final commandWords = command.split(' ');
    
    // Check if they share key terms
    final commonWords = inputWords.where((word) => 
        commandWords.any((cmdWord) => cmdWord.contains(word)));
    
    return commonWords.isNotEmpty || context.toLowerCase().contains(input.toLowerCase());
  }
  
  String _getCurrentInput() {
    // In real implementation, this would get current terminal input
    return '';
  }
  
  void _manageBackgroundProcesses() {
    final now = DateTime.now();
    final completedProcesses = <BackgroundProcess>[];
    
    for (final process in _backgroundProcesses) {
      if (process.status == ProcessStatus.running && 
          process.startTime.isBefore(now.subtract(Duration(minutes: 30)))) {
        // Mark long-running processes
        process.status = ProcessStatus.longRunning;
        
        _eventController.add(CommandEvent(
          type: CommandEventType.longRunningProcess,
          data: {
            'processId': process.id,
            'command': process.command,
            'duration': now.difference(process.startTime).inMinutes,
          },
        ));
      }
      
      if (process.status == ProcessStatus.completed || 
          process.status == ProcessStatus.failed) {
        completedProcesses.add(process);
      }
    }
    
    // Remove completed processes
    for (final process in completedProcesses) {
      _backgroundProcesses.remove(process);
    }
  }
  
  List<CommandSuggestion> getCurrentSuggestions() {
    return _contextSuggestions[_currentContext] ?? [];
  }
  
  List<CommandHistory> getCommandHistory({int limit = 50}) {
    return _commandHistory.reversed.take(limit).toList();
  }
  
  List<BackgroundProcess> getBackgroundProcesses() {
    return List.from(_backgroundProcesses);
  }
  
  void dispose() {
    _batchTimer?.cancel();
    _suggestionTimer?.cancel();
    _backgroundProcessTimer?.cancel();
    _eventController.close();
  }
}

class CommandRequest {
  final String command;
  final DateTime timestamp;
  final bool priority;
  final String context;
  final String directory;
  
  CommandRequest({
    required this.command,
    required this.timestamp,
    this.priority = false,
    required this.context,
    required this.directory,
  });
}

class CommandHistory {
  final String command;
  final DateTime timestamp;
  final String context;
  final String directory;
  
  CommandHistory({
    required this.command,
    required this.timestamp,
    required this.context,
    required this.directory,
  });
}

class CommandPattern {
  final List<String> commands;
  final String context;
  final List<String> suggestions;
  
  CommandPattern({
    required this.commands,
    required this.context,
    required this.suggestions,
  });
}

class CommandSuggestion {
  final String text;
  final SuggestionType type;
  final double confidence;
  final String description;
  
  CommandSuggestion({
    required this.text,
    required this.type,
    required this.confidence,
    this.description = '',
  });
  
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.toString(),
      'confidence': confidence,
      'description': description,
    };
  }
}

class BackgroundProcess {
  final int id;
  final String command;
  final DateTime startTime;
  ProcessStatus status;
  
  BackgroundProcess({
    required this.id,
    required this.command,
    required this.startTime,
    required this.status,
  });
}

enum SuggestionType {
  fuzzy,
  contextual,
  history,
  pattern,
}

enum ProcessStatus {
  running,
  completed,
  failed,
  longRunning,
}

enum CommandEventType {
  executed,
  error,
  suggestionsUpdated,
  backgroundProcessStarted,
  longRunningProcess,
}

class CommandEvent {
  final CommandEventType type;
  final Map<String, dynamic> data;
  
  CommandEvent({required this.type, required this.data});
}
