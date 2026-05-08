import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';

class SmartCommandQueue {
  static const int _maxQueueSize = 1000;
  static const int _processingBatchSize = 10;
  static const int _priorityBoostThreshold = 5; // consecutive requeues
  
  final Queue<QueuedCommand> _commandQueue = Queue();
  final Map<String, CommandProfile> _commandProfiles = {};
  final List<CommandExecution> _executionHistory = [];
  final Map<String, Queue<QueuedCommand>> _categoryQueues = {};
  
  Timer? _processingTimer;
  bool _isProcessing = false;
  int _totalCommandsProcessed = 0;
  int _totalCommandsQueued = 0;
  
  final StreamController<CommandEvent> _commandEventController = 
      StreamController<CommandEvent>.broadcast();

  void initialize() {
    _startProcessing();
    _initializeCategoryQueues();
    developer.log('📋 Smart Command Queue initialized');
  }

  void _startProcessing() {
    _processingTimer = Timer.periodic(
      Duration(milliseconds: 50), // 20Hz processing
      (_) => _processCommandBatch(),
    );
  }

  void _initializeCategoryQueues() {
    _categoryQueues['system'] = Queue();
    _categoryQueues['user'] = Queue();
    _categoryQueues['background'] = Queue();
    _categoryQueues['urgent'] = Queue();
    _categoryQueues['ai'] = Queue();
  }

  String enqueueCommand(String command, {
    CommandPriority priority = CommandPriority.normal,
    String category = 'user',
    Map<String, dynamic>? context,
    String? sessionId,
    bool allowBatching = true,
  }) {
    final commandId = _generateCommandId();
    
    // Check if we should batch this command
    if (allowBatching && _shouldBatchCommand(command, category)) {
      return _batchCommand(command, priority, category, context, sessionId);
    }
    
    final queuedCommand = QueuedCommand(
      id: commandId,
      command: command,
      priority: priority,
      category: category,
      context: context ?? {},
      sessionId: sessionId,
      queuedAt: DateTime.now(),
      allowBatching: allowBatching,
    );

    // Add to appropriate queue
    _addToQueue(queuedCommand);
    _totalCommandsQueued++;
    
    developer.log('📋 Enqueued command: $command (ID: $commandId, Priority: ${priority.name})');
    
    _emitEvent(CommandEvent(
      type: CommandEventType.queued,
      commandId: commandId,
      command: command,
      priority: priority,
    ));

    return commandId;
  }

  bool _shouldBatchCommand(String command, String category) {
    // Don't batch urgent or system commands
    if (category == 'urgent' || category == 'system') return false;
    
    // Batch similar commands
    final profile = _commandProfiles[_normalizeCommand(command)];
    if (profile != null && profile.isBatchable) {
      return true;
    }
    
    // Batch common repetitive commands
    final batchablePatterns = [
      r'^cd\s+',
      r'^ls\s*',
      r'^pwd\s*',
      r'^echo\s+',
      r'^cat\s+',
    ];
    
    for (final pattern in batchablePatterns) {
      if (RegExp(pattern).hasMatch(command)) {
        return true;
      }
    }
    
    return false;
  }

  String _batchCommand(String command, CommandPriority priority, String category, 
                     Map<String, dynamic>? context, String? sessionId) {
    final normalizedCommand = _normalizeCommand(command);
    final existingBatch = _findExistingBatch(normalizedCommand, category);
    
    if (existingBatch != null) {
      // Add to existing batch
      existingBatch.batchedCommands.add(command);
      existingBatch.lastUpdated = DateTime.now();
      return existingBatch.id;
    } else {
      // Create new batch
      final batchId = _generateCommandId();
      final batchedCommand = QueuedCommand(
        id: batchId,
        command: command,
        priority: priority,
        category: category,
        context: context ?? {},
        sessionId: sessionId,
        queuedAt: DateTime.now(),
        isBatched: true,
        batchedCommands: [command],
      );
      
      _addToQueue(batchedCommand);
      _totalCommandsQueued++;
      
      developer.log('📋 Created batch: $command (Batch ID: $batchId)');
      return batchId;
    }
  }

  QueuedCommand? _findExistingBatch(String normalizedCommand, String category) {
    for (final command in _commandQueue) {
      if (command.isBatched && 
          command.category == category &&
          _normalizeCommand(command.command) == normalizedCommand) {
        return command;
      }
    }
    
    // Check category queues
    final categoryQueue = _categoryQueues[category];
    if (categoryQueue != null) {
      for (final command in categoryQueue) {
        if (command.isBatched && 
            _normalizeCommand(command.command) == normalizedCommand) {
          return command;
        }
      }
    }
    
    return null;
  }

  void _addToQueue(QueuedCommand command) {
    if (_commandQueue.length >= _maxQueueSize) {
      _evictOldestCommand();
    }
    
    // Add to category queue if applicable
    if (_categoryQueues.containsKey(command.category)) {
      _categoryQueues[command.category]!.add(command);
    } else {
      _commandQueue.add(command);
    }
    
    // Update command profile
    _updateCommandProfile(command);
  }

  void _evictOldestCommand() {
    QueuedCommand? oldest;
    
    // Find oldest low-priority command
    for (final command in _commandQueue) {
      if (command.priority == CommandPriority.low) {
        if (oldest == null || command.queuedAt.isBefore(oldest.queuedAt)) {
          oldest = command;
        }
      }
    }
    
    if (oldest != null) {
      _removeFromQueue(oldest.id);
      developer.log('📋 Evicted old command: ${oldest.command}');
    }
  }

  void _processCommandBatch() {
    if (_isProcessing) return;
    
    final commandsToProcess = _selectCommandsForProcessing();
    if (commandsToProcess.isEmpty) return;
    
    _isProcessing = true;
    
    for (final command in commandsToProcess) {
      _executeCommand(command);
    }
    
    _isProcessing = false;
  }

  List<QueuedCommand> _selectCommandsForProcessing() {
    final commands = <QueuedCommand>[];
    
    // Priority order: urgent > system > ai > user > background
    final priorityOrder = ['urgent', 'system', 'ai', 'user', 'background'];
    
    for (final category in priorityOrder) {
      final categoryQueue = _categoryQueues[category];
      if (categoryQueue != null && categoryQueue.isNotEmpty) {
        // Take up to batch size from this category
        final toTake = categoryQueue.length.clamp(0, _processingBatchSize - commands.length);
        for (int i = 0; i < toTake; i++) {
          commands.add(categoryQueue.removeFirst());
        }
      }
      
      if (commands.length >= _processingBatchSize) break;
    }
    
    // If still need more, take from general queue
    if (commands.length < _processingBatchSize) {
      final toTake = _commandQueue.length.clamp(0, _processingBatchSize - commands.length);
      for (int i = 0; i < toTake; i++) {
        commands.add(_commandQueue.removeFirst());
      }
    }
    
    return commands;
  }

  Future<void> _executeCommand(QueuedCommand command) async {
    final execution = CommandExecution(
      id: _generateExecutionId(),
      commandId: command.id,
      command: command.command,
      startedAt: DateTime.now(),
      category: command.category,
    );

    try {
      developer.log('📋 Executing: ${command.command}');
      
      _emitEvent(CommandEvent(
        type: CommandEventType.started,
        commandId: command.id,
        executionId: execution.id,
        command: command.command,
      ));

      // Simulate command execution
      await _simulateCommandExecution(command);
      
      execution.completedAt = DateTime.now();
      execution.success = true;
      
      _totalCommandsProcessed++;
      _updateCommandExecutionHistory(execution);
      
      developer.log('📋 Completed: ${command.command} in ${execution.duration}ms');
      
      _emitEvent(CommandEvent(
        type: CommandEventType.completed,
        commandId: command.id,
        executionId: execution.id,
        command: command.command,
        duration: execution.duration,
        success: true,
      ));

    } catch (e) {
      execution.completedAt = DateTime.now();
      execution.success = false;
      execution.error = e.toString();
      
      developer.log('📋 Failed: ${command.command} - $e');
      
      _emitEvent(CommandEvent(
        type: CommandEventType.failed,
        commandId: command.id,
        executionId: execution.id,
        command: command.command,
        error: e.toString(),
      ));

      // Consider retrying
      if (_shouldRetryCommand(command, e)) {
        _retryCommand(command);
      }
    }
  }

  Future<void> _simulateCommandExecution(QueuedCommand command) async {
    // Simulate different execution times based on command type
    final baseDelay = _getCommandDelay(command.command);
    final complexity = _getCommandComplexity(command.command);
    final actualDelay = baseDelay * complexity;
    
    await Future.delayed(Duration(milliseconds: actualDelay));
  }

  int _getCommandDelay(String command) {
    if (command.startsWith('cd')) return 10;
    if (command.startsWith('ls')) return 50;
    if (command.startsWith('pwd')) return 5;
    if (command.startsWith('echo')) return 10;
    if (command.startsWith('cat')) return 100;
    if (command.startsWith('grep')) return 200;
    if (command.startsWith('find')) return 500;
    return 100; // Default
  }

  double _getCommandComplexity(String command) {
    // Simple complexity estimation
    final parts = command.split(' ');
    final argCount = parts.length - 1;
    
    return 1.0 + (argCount * 0.2); // More args = more complex
  }

  bool _shouldRetryCommand(QueuedCommand command, dynamic error) {
    // Don't retry certain types of errors
    if (error.toString().contains('permission denied')) return false;
    if (error.toString().contains('not found')) return false;
    
    // Retry up to 3 times
    return command.retryCount < 3;
  }

  void _retryCommand(QueuedCommand command) {
    command.retryCount++;
    command.priority = _boostPriority(command.priority);
    
    // Add back to queue with higher priority
    _addToQueue(command);
    
    developer.log('📋 Retrying command: ${command.command} (attempt ${command.retryCount})');
  }

  CommandPriority _boostPriority(CommandPriority current) {
    switch (current) {
      case CommandPriority.low:
        return CommandPriority.normal;
      case CommandPriority.normal:
        return CommandPriority.high;
      case CommandPriority.high:
        return CommandPriority.urgent;
      case CommandPriority.urgent:
        return CommandPriority.urgent; // Can't boost higher
    }
  }

  String _normalizeCommand(String command) {
    // Remove extra whitespace and normalize
    return command.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _generateCommandId() {
    return 'cmd_${DateTime.now().millisecondsSinceEpoch}_${_totalCommandsQueued}';
  }

  String _generateExecutionId() {
    return 'exec_${DateTime.now().millisecondsSinceEpoch}_${_totalCommandsProcessed}';
  }

  void _updateCommandProfile(QueuedCommand command) {
    final normalized = _normalizeCommand(command.command);
    final profile = _commandProfiles.putIfAbsent(
      normalized,
      () => CommandProfile(command: normalized),
    );
    
    profile.recordExecution(command);
  }

  void _updateCommandExecutionHistory(CommandExecution execution) {
    _executionHistory.add(execution);
    
    if (_executionHistory.length > 1000) {
      _executionHistory.removeAt(0);
    }
  }

  void _removeFromQueue(String commandId) {
    _commandQueue.removeWhere((cmd) => cmd.id == commandId);
    
    for (final queue in _categoryQueues.values) {
      queue.removeWhere((cmd) => cmd.id == commandId);
    }
  }

  void _emitEvent(CommandEvent event) {
    _commandEventController.add(event);
  }

  Stream<CommandEvent> get commandEventStream => _commandEventController.stream;

  CommandQueueStats getStats() {
    final queueSizes = <String, int>{};
    for (final entry in _categoryQueues.entries) {
      queueSizes[entry.key] = entry.value.length;
    }
    
    return CommandQueueStats(
      totalQueued: _totalCommandsQueued,
      totalProcessed: _totalCommandsProcessed,
      queueSize: _commandQueue.length,
      categoryQueueSizes: queueSizes,
      executionHistory: _executionHistory.toList(),
      commandProfiles: _commandProfiles.values.toList(),
    );
  }

  void dispose() {
    _processingTimer?.cancel();
    _commandQueue.clear();
    _categoryQueues.clear();
    _commandProfiles.clear();
    _executionHistory.clear();
    _commandEventController.close();
    developer.log('📋 Smart Command Queue disposed');
  }
}

class QueuedCommand {
  final String id;
  final String command;
  CommandPriority priority;
  final String category;
  final Map<String, dynamic> context;
  final String? sessionId;
  final DateTime queuedAt;
  final bool allowBatching;
  
  bool isBatched = false;
  List<String> batchedCommands = [];
  DateTime lastUpdated = DateTime.now();
  int retryCount = 0;

  QueuedCommand({
    required this.id,
    required this.command,
    required this.priority,
    required this.category,
    required this.context,
    this.sessionId,
    required this.queuedAt,
    required this.allowBatching,
  });
}

enum CommandPriority {
  low,
  normal,
  high,
  urgent,
}

class CommandProfile {
  final String command;
  int executionCount = 0;
  int totalDuration = 0;
  int successCount = 0;
  int failureCount = 0;
  DateTime lastExecuted = DateTime.now();
  bool isBatchable = false;

  CommandProfile({required this.command});

  void recordExecution(QueuedCommand queuedCommand) {
    executionCount++;
    lastExecuted = DateTime.now();
    
    // Determine if command is batchable based on patterns
    isBatchable = _isBatchableCommand(queuedCommand.command);
  }

  bool _isBatchableCommand(String command) {
    final batchablePatterns = [
      r'^cd\s+',
      r'^ls\s*',
      r'^pwd\s*',
      r'^echo\s+',
    ];
    
    for (final pattern in batchablePatterns) {
      if (RegExp(pattern).hasMatch(command)) {
        return true;
      }
    }
    
    return false;
  }

  double getAverageDuration() {
    return executionCount > 0 ? totalDuration / executionCount : 0.0;
  }

  double getSuccessRate() {
    return executionCount > 0 ? successCount / executionCount : 0.0;
  }
}

class CommandExecution {
  final String id;
  final String commandId;
  final String command;
  final DateTime startedAt;
  final String category;
  
  DateTime? completedAt;
  bool? success;
  String? error;

  CommandExecution({
    required this.id,
    required this.commandId,
    required this.command,
    required this.startedAt,
    required this.category,
  });

  int? get duration {
    if (completedAt == null) return null;
    return completedAt!.difference(startedAt).inMilliseconds;
  }
}

enum CommandEventType {
  queued,
  started,
  completed,
  failed,
  cancelled,
}

class CommandEvent {
  final CommandEventType type;
  final String commandId;
  final String? executionId;
  final String command;
  final CommandPriority? priority;
  final int? duration;
  final bool? success;
  final String? error;

  CommandEvent({
    required this.type,
    required this.commandId,
    this.executionId,
    required this.command,
    this.priority,
    this.duration,
    this.success,
    this.error,
  });
}

class CommandQueueStats {
  final int totalQueued;
  final int totalProcessed;
  final int queueSize;
  final Map<String, int> categoryQueueSizes;
  final List<CommandExecution> executionHistory;
  final List<CommandProfile> commandProfiles;

  CommandQueueStats({
    required this.totalQueued,
    required this.totalProcessed,
    required this.queueSize,
    required this.categoryQueueSizes,
    required this.executionHistory,
    required this.commandProfiles,
  });
}
