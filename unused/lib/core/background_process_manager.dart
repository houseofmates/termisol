import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

class BackgroundProcessManager {
  static const int _maxConcurrentProcesses = 10;
  static const int _processTimeout = 300000; // 5 minutes
  static const int _cleanupInterval = 60000; // 1 minute
  
  final Map<String, BackgroundProcess> _runningProcesses = {};
  final Queue<BackgroundProcess> _processQueue = Queue();
  final List<ProcessExecution> _executionHistory = [];
  final Map<String, ProcessProfile> _processProfiles = {};
  
  Timer? _cleanupTimer;
  Timer? _monitoringTimer;
  int _totalProcessesStarted = 0;
  int _totalProcessesCompleted = 0;
  
  final StreamController<ProcessEvent> _processEventController = 
      StreamController<ProcessEvent>.broadcast();

  void initialize() {
    _startCleanupTimer();
    _startMonitoringTimer();
    developer.log('🔄 Background Process Manager initialized');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      Duration(milliseconds: _cleanupInterval),
      (_) => _cleanupProcesses(),
    );
  }

  void _startMonitoringTimer() {
    _monitoringTimer = Timer.periodic(
      Duration(milliseconds: 5000), // Check every 5 seconds
      (_) => _monitorProcesses(),
    );
  }

  String startBackgroundProcess(String command, {
    ProcessPriority priority = ProcessPriority.normal,
    Map<String, dynamic>? environment,
    String? workingDirectory,
    Duration? timeout,
    bool persistent = false,
    Function(String)? onOutput,
    Function(String)? onError,
    Function(int)? onComplete,
  }) {
    final processId = _generateProcessId();
    
    final process = BackgroundProcess(
      id: processId,
      command: command,
      priority: priority,
      environment: environment ?? {},
      workingDirectory: workingDirectory,
      timeout: timeout ?? Duration(milliseconds: _processTimeout),
      persistent: persistent,
      onOutput: onOutput,
      onError: onError,
      onComplete: onComplete,
      createdAt: DateTime.now(),
    );

    if (_runningProcesses.length < _maxConcurrentProcesses) {
      _startProcess(process);
    } else {
      _queueProcess(process);
    }

    _totalProcessesStarted++;
    developer.log('🔄 Started background process: $command (ID: $processId)');
    
    _emitEvent(ProcessEvent(
      type: ProcessEventType.started,
      processId: processId,
      command: command,
      priority: priority,
    ));

    return processId;
  }

  void _startProcess(BackgroundProcess process) {
    process.status = ProcessStatus.running;
    process.startedAt = DateTime.now();
    _runningProcesses[process.id] = process;

    // Simulate process execution
    _simulateProcessExecution(process);
  }

  void _queueProcess(BackgroundProcess process) {
    process.status = ProcessStatus.queued;
    _processQueue.add(process);
    
    // Sort queue by priority
    _processQueue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    
    developer.log('🔄 Queued background process: ${process.command} (ID: ${process.id})');
  }

  Future<void> _simulateProcessExecution(BackgroundProcess process) async {
    try {
      developer.log('🔄 Executing: ${process.command}');
      
      _emitEvent(ProcessEvent(
        type: ProcessEventType.executing,
        processId: process.id,
        command: process.command,
      ));

      // Simulate process with different durations based on command type
      final duration = _estimateProcessDuration(process.command);
      
      // Simulate output during execution
      _simulateProcessOutput(process, duration);
      
      await Future.delayed(duration);
      
      // Check for timeout
      if (DateTime.now().difference(process.startedAt!) > process.timeout) {
        throw TimeoutException('Process timed out', process.timeout);
      }
      
      process.status = ProcessStatus.completed;
      process.completedAt = DateTime.now();
      process.exitCode = 0;
      
      _totalProcessesCompleted++;
      _updateProcessExecutionHistory(process);
      
      if (process.onComplete != null) {
        process.onComplete!(0);
      }
      
      developer.log('🔄 Completed: ${process.command} in ${process.duration}ms');
      
      _emitEvent(ProcessEvent(
        type: ProcessEventType.completed,
        processId: process.id,
        command: process.command,
        exitCode: 0,
        duration: process.duration,
      ));

    } catch (e) {
      process.status = ProcessStatus.failed;
      process.completedAt = DateTime.now();
      process.error = e.toString();
      
      if (process.onError != null) {
        process.onError!(e.toString());
      }
      
      developer.log('🔄 Failed: ${process.command} - $e');
      
      _emitEvent(ProcessEvent(
        type: ProcessEventType.failed,
        processId: process.id,
        command: process.command,
        error: e.toString(),
      ));

      // Consider retrying if not persistent and error is retryable
      if (!process.persistent && _shouldRetryProcess(process, e)) {
        _retryProcess(process);
      }
    } finally {
      _runningProcesses.remove(process.id);
      
      // Start next queued process
      if (_processQueue.isNotEmpty) {
        final nextProcess = _processQueue.removeFirst();
        _startProcess(nextProcess);
      }
    }
  }

  void _simulateProcessOutput(BackgroundProcess process, Duration duration) {
    // Simulate periodic output for long-running processes
    if (duration.inMilliseconds > 1000) {
      Timer.periodic(Duration(milliseconds: 500), (timer) {
        if (process.status != ProcessStatus.running) {
          timer.cancel();
          return;
        }
        
        final output = _generateSimulatedOutput(process.command);
        if (process.onOutput != null) {
          process.onOutput!(output);
        }
        
        _emitEvent(ProcessEvent(
          type: ProcessEventType.output,
          processId: process.id,
          command: process.command,
          output: output,
        ));
      });
    }
  }

  String _generateSimulatedOutput(String command) {
    // Generate realistic output based on command type
    if (command.contains('git')) {
      return 'Processing git operation...';
    } else if (command.contains('npm') || command.contains('yarn')) {
      return 'Installing dependencies...';
    } else if (command.contains('docker')) {
      return 'Building Docker image...';
    } else if (command.contains('find') || command.contains('grep')) {
      return 'Searching files...';
    } else {
      return 'Processing...';
    }
  }

  Duration _estimateProcessDuration(String command) {
    // Estimate duration based on command type
    if (command.startsWith('ls')) return Duration(milliseconds: 100);
    if (command.startsWith('pwd')) return Duration(milliseconds: 50);
    if (command.startsWith('echo')) return Duration(milliseconds: 10);
    if (command.contains('git')) return Duration(seconds: 2);
    if (command.contains('npm') || command.contains('yarn')) return Duration(seconds: 30);
    if (command.contains('docker')) return Duration(seconds: 60);
    if (command.contains('find')) return Duration(seconds: 10);
    if (command.contains('grep')) return Duration(seconds: 5);
    
    return Duration(seconds: 1); // Default
  }

  bool _shouldRetryProcess(BackgroundProcess process, dynamic error) {
    // Don't retry certain types of errors
    if (error.toString().contains('permission denied')) return false;
    if (error.toString().contains('not found')) return false;
    if (error.toString().contains('timeout')) return false;
    
    // Retry up to 3 times
    return process.retryCount < 3;
  }

  void _retryProcess(BackgroundProcess process) {
    process.retryCount++;
    process.priority = _boostPriority(process.priority);
    
    developer.log('🔄 Retrying process: ${process.command} (attempt ${process.retryCount})');
    
    // Add back to queue with higher priority
    _queueProcess(process);
  }

  ProcessPriority _boostPriority(ProcessPriority current) {
    switch (current) {
      case ProcessPriority.low:
        return ProcessPriority.normal;
      case ProcessPriority.normal:
        return ProcessPriority.high;
      case ProcessPriority.high:
        return ProcessPriority.critical;
      case ProcessPriority.critical:
        return ProcessPriority.critical; // Can't boost higher
    }
  }

  void _monitorProcesses() {
    final now = DateTime.now();
    final processesToTimeout = <String>[];
    
    for (final entry in _runningProcesses.entries) {
      final processId = entry.key;
      final process = entry.value;
      
      // Check for timeout
      if (process.startedAt != null && 
          now.difference(process.startedAt!) > process.timeout) {
        processesToTimeout.add(processId);
      }
      
      // Update process profile
      _updateProcessProfile(process);
    }
    
    // Handle timeouts
    for (final processId in processesToTimeout) {
      _timeoutProcess(processId);
    }
  }

  void _timeoutProcess(String processId) {
    final process = _runningProcesses[processId];
    if (process == null) return;
    
    process.status = ProcessStatus.failed;
    process.completedAt = DateTime.now();
    process.error = 'Process timed out';
    
    if (process.onError != null) {
      process.onError!('Process timed out');
    }
    
    developer.log('🔄 Process timed out: ${process.command} (ID: $processId)');
    
    _emitEvent(ProcessEvent(
      type: ProcessEventType.failed,
      processId: processId,
      command: process.command,
      error: 'Process timed out',
    ));
    
    _runningProcesses.remove(processId);
  }

  void _cleanupProcesses() {
    final now = DateTime.now();
    final processesToCleanup = <String>[];
    
    // Clean up completed processes
    for (final entry in _runningProcesses.entries) {
      final processId = entry.key;
      final process = entry.value;
      
      if ((process.status == ProcessStatus.completed || 
           process.status == ProcessStatus.failed) &&
          process.completedAt != null &&
          now.difference(process.completedAt!).inMinutes > 5) {
        processesToCleanup.add(processId);
      }
    }
    
    // Remove old processes
    for (final processId in processesToCleanup) {
      final process = _runningProcesses.remove(processId);
      if (process != null) {
        developer.log('🔄 Cleaned up process: ${process.command} (ID: $processId)');
      }
    }
    
    // Clean up execution history
    _executionHistory.removeWhere((execution) => 
        now.difference(execution.completedAt).inHours > 24);
  }

  void _updateProcessProfile(BackgroundProcess process) {
    final profile = _processProfiles.putIfAbsent(
      process.command,
      () => ProcessProfile(command: process.command),
    );
    
    profile.recordExecution(process);
  }

  void _updateProcessExecutionHistory(BackgroundProcess process) {
    final execution = ProcessExecution(
      id: _generateExecutionId(),
      processId: process.id,
      command: process.command,
      startedAt: process.startedAt!,
      completedAt: process.completedAt!,
      exitCode: process.exitCode ?? -1,
      priority: process.priority,
    );
    
    _executionHistory.add(execution);
    
    if (_executionHistory.length > 1000) {
      _executionHistory.removeAt(0);
    }
  }

  bool stopProcess(String processId) {
    final process = _runningProcesses[processId];
    if (process == null) return false;
    
    process.status = ProcessStatus.cancelled;
    process.completedAt = DateTime.now();
    
    _runningProcesses.remove(processId);
    
    developer.log('🔄 Stopped process: ${process.command} (ID: $processId)');
    
    _emitEvent(ProcessEvent(
      type: ProcessEventType.cancelled,
      processId: processId,
      command: process.command,
    ));
    
    return true;
  }

  BackgroundProcess? getProcess(String processId) {
    return _runningProcesses[processId];
  }

  List<BackgroundProcess> getRunningProcesses() {
    return _runningProcesses.values.toList();
  }

  String _generateProcessId() {
    return 'proc_${DateTime.now().millisecondsSinceEpoch}_${_totalProcessesStarted}';
  }

  String _generateExecutionId() {
    return 'exec_${DateTime.now().millisecondsSinceEpoch}_${_totalProcessesCompleted}';
  }

  void _emitEvent(ProcessEvent event) {
    _processEventController.add(event);
  }

  Stream<ProcessEvent> get processEventStream => _processEventController.stream;

  BackgroundProcessManagerStats getStats() {
    return BackgroundProcessManagerStats(
      totalProcessesStarted: _totalProcessesStarted,
      totalProcessesCompleted: _totalProcessesCompleted,
      runningProcesses: _runningProcesses.length,
      queuedProcesses: _processQueue.length,
      executionHistory: _executionHistory.toList(),
      processProfiles: _processProfiles.values.toList(),
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _monitoringTimer?.cancel();
    
    // Stop all running processes
    for (final processId in _runningProcesses.keys.toList()) {
      stopProcess(processId);
    }
    
    _runningProcesses.clear();
    _processQueue.clear();
    _executionHistory.clear();
    _processProfiles.clear();
    _processEventController.close();
    
    developer.log('🔄 Background Process Manager disposed');
  }
}

class BackgroundProcess {
  final String id;
  final String command;
  ProcessPriority priority;
  final Map<String, dynamic> environment;
  final String? workingDirectory;
  final Duration timeout;
  final bool persistent;
  final Function(String)? onOutput;
  final Function(String)? onError;
  final Function(int)? onComplete;
  final DateTime createdAt;
  
  ProcessStatus status = ProcessStatus.created;
  DateTime? startedAt;
  DateTime? completedAt;
  int? exitCode;
  String? error;
  int retryCount = 0;

  BackgroundProcess({
    required this.id,
    required this.command,
    required this.priority,
    required this.environment,
    this.workingDirectory,
    required this.timeout,
    required this.persistent,
    this.onOutput,
    this.onError,
    this.onComplete,
    required this.createdAt,
  });

  int? get duration {
    if (startedAt == null || completedAt == null) return null;
    return completedAt!.difference(startedAt!).inMilliseconds;
  }
}

enum ProcessStatus {
  created,
  queued,
  running,
  completed,
  failed,
  cancelled,
}

enum ProcessPriority {
  low,
  normal,
  high,
  critical,
}

class ProcessProfile {
  final String command;
  int executionCount = 0;
  int totalDuration = 0;
  int successCount = 0;
  int failureCount = 0;
  DateTime lastExecuted = DateTime.now();

  ProcessProfile({required this.command});

  void recordExecution(BackgroundProcess process) {
    executionCount++;
    lastExecuted = DateTime.now();
    
    if (process.duration != null) {
      totalDuration += process.duration!;
    }
    
    if (process.status == ProcessStatus.completed) {
      successCount++;
    } else if (process.status == ProcessStatus.failed) {
      failureCount++;
    }
  }

  double getAverageDuration() {
    return executionCount > 0 ? totalDuration / executionCount : 0.0;
  }

  double getSuccessRate() {
    return executionCount > 0 ? successCount / executionCount : 0.0;
  }
}

class ProcessExecution {
  final String id;
  final String processId;
  final String command;
  final DateTime startedAt;
  final DateTime completedAt;
  final int exitCode;
  final ProcessPriority priority;

  ProcessExecution({
    required this.id,
    required this.processId,
    required this.command,
    required this.startedAt,
    required this.completedAt,
    required this.exitCode,
    required this.priority,
  });

  int get duration => completedAt.difference(startedAt).inMilliseconds;
}

enum ProcessEventType {
  started,
  executing,
  output,
  completed,
  failed,
  cancelled,
}

class ProcessEvent {
  final ProcessEventType type;
  final String processId;
  final String command;
  final ProcessPriority? priority;
  final String? output;
  final String? error;
  final int? exitCode;
  final int? duration;

  ProcessEvent({
    required this.type,
    required this.processId,
    required this.command,
    this.priority,
    this.output,
    this.error,
    this.exitCode,
    this.duration,
  });
}

class BackgroundProcessManagerStats {
  final int totalProcessesStarted;
  final int totalProcessesCompleted;
  final int runningProcesses;
  final int queuedProcesses;
  final List<ProcessExecution> executionHistory;
  final List<ProcessProfile> processProfiles;

  BackgroundProcessManagerStats({
    required this.totalProcessesStarted,
    required this.totalProcessesCompleted,
    required this.runningProcesses,
    required this.queuedProcesses,
    required this.executionHistory,
    required this.processProfiles,
  });
}
