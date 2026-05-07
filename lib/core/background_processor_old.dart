import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Background Processor - Asynchronous command processing
/// 
/// Implements comprehensive background processing:
/// - Asynchronous command execution
/// - Isolate-based processing
/// - Task queue management
/// - Progress tracking and notifications
/// - Resource monitoring
class BackgroundProcessor {
  bool _isInitialized = false;
  
  // Processing state
  final Map<String, BackgroundTask> _tasks = {};
  final Queue<BackgroundCommand> _commandQueue = Queue();
  final Map<String, Isolate> _isolates = {};
  final Map<String, ReceivePort> _receivePorts = {};
  
  // Performance monitoring
  final Map<String, TaskPerformance> _performance = {};
  final Map<String, ResourceUsage> _resourceUsage = {};
  
  // Configuration
  BackgroundProcessorConfig _config = BackgroundProcessorConfig();
  
  BackgroundProcessor();
  
  bool get isInitialized => _isInitialized;
  Map<String, BackgroundTask> get tasks => Map.unmodifiable(_tasks);
  Map<String, TaskPerformance> get performance => Map.unmodifiable(_performance);
  
  /// Initialize background processor
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Setup isolates
      await _setupIsolates();
      
      // Start task monitoring
      _startTaskMonitoring();
      
      _isInitialized = true;
      debugPrint('⚙️ Background Processor initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Background Processor: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/background_processor_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = BackgroundProcessorConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load background processor config: $e');
    }
  }
  
  /// Setup isolates
  Future<void> _setupIsolates() async {
    try {
      // Create isolates for different task types
      await _createIsolate('shell', _shellIsolateEntry);
      await _createIsolate('file', _fileIsolateEntry);
      await _createIsolate('network', _networkIsolateEntry);
      await _createIsolate('computation', _computationIsolateEntry);
      
      debugPrint('🔧 Background isolates setup');
    } catch (e) {
      debugPrint('⚠️ Failed to setup isolates: $e');
    }
  }
  
  /// Create isolate
  Future<void> _createIsolate(String name, void Function(SendPort) entryPoint) async {
    try {
      final receivePort = ReceivePort();
      final sendPort = receivePort.sendPort;
      
      _receivePorts[name] = receivePort;
      
      final isolate = await Isolate.spawn(entryPoint, sendPort);
      _isolates[name] = isolate;
      
      // Setup message handling
      receivePort.listen((message) {
        _handleIsolateMessage(name, message);
      });
      
      debugPrint('🔧 Created isolate: $name');
    } catch (e) {
      debugPrint('⚠️ Failed to create isolate $name: $e');
    }
  }
  
  /// Start task monitoring
  void _startTaskMonitoring() {
    Timer.periodic(const Duration(seconds: 1), (_) {
      _updateResourceUsage();
      _checkTaskTimeouts();
      _cleanupCompletedTasks();
    });
    debugPrint('⏱️ Task monitoring started');
  }
  
  /// Handle isolate message
  void _handleIsolateMessage(String isolateName, dynamic message) {
    try {
      final messageData = message as Map<String, dynamic>;
      final type = messageData['type'] as String;
      
      switch (type) {
        case 'task_result':
          _handleTaskResult(messageData);
          break;
        case 'task_progress':
          _handleTaskProgress(messageData);
          break;
        case 'task_error':
          _handleTaskError(messageData);
          break;
        case 'resource_usage':
          _handleResourceUsage(isolateName, messageData);
          break;
        case 'performance_metrics':
          _handlePerformanceMetrics(isolateName, messageData);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle isolate message: $e');
    }
  }
  
  /// Handle task result
  void _handleTaskResult(Map<String, dynamic> messageData) {
    final taskId = messageData['taskId'] as String;
    final result = messageData['result'];
    final timestamp = DateTime.parse(messageData['timestamp'] as String);
    
    final task = _tasks[taskId];
    if (task != null) {
      task.status = TaskStatus.completed;
      task.result = result;
      task.completedAt = timestamp;
      
      // Update performance metrics
      if (task.performance != null) {
        task.performance!.completedAt = timestamp;
        task.performance!.duration = timestamp.difference(task.performance!.startedAt).inMicroseconds;
      }
      
      debugPrint('✅ Background task completed: $taskId');
    }
  }
  
  /// Handle task progress
  void _handleTaskProgress(Map<String, dynamic> messageData) {
    final taskId = messageData['taskId'] as String;
    final progress = messageData['progress'] as double;
    final message = messageData['message'] as String?;
    
    final task = _tasks[taskId];
    if (task != null) {
      task.progress = progress;
      task.statusMessage = message;
      
      debugPrint('📊 Task progress: $taskId - $progress%');
    }
  }
  
  /// Handle task error
  void _handleTaskError(Map<String, dynamic> messageData) {
    final taskId = messageData['taskId'] as String;
    final error = messageData['error'] as String;
    final timestamp = DateTime.parse(messageData['timestamp'] as String);
    
    final task = _tasks[taskId];
    if (task != null) {
      task.status = TaskStatus.failed;
      task.error = error;
      task.completedAt = timestamp;
      
      debugPrint('❌ Background task failed: $taskId - $error');
    }
  }
  
  /// Handle resource usage
  void _handleResourceUsage(String isolateName, Map<String, dynamic> messageData) {
    final cpuUsage = messageData['cpu'] as double;
    final memoryUsage = messageData['memory'] as int;
    
    _resourceUsage[isolateName] = ResourceUsage(
      cpuUsage: cpuUsage,
      memoryUsage: memoryUsage,
      timestamp: DateTime.now(),
    );
  }
  
  /// Handle performance metrics
  void _handlePerformanceMetrics(String isolateName, Map<String, dynamic> messageData) {
    final metrics = messageData['metrics'] as Map<String, dynamic>;
    
    _performance[isolateName] = TaskPerformance.fromJson(metrics);
  }
  
  /// Execute shell command in background
  String executeShellCommand(String command, {List<String>? args, String? workingDirectory, Map<String, String>? environment}) {
    final taskId = 'shell_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = BackgroundTask(
      id: taskId,
      type: TaskType.shell,
      command: command,
      args: args ?? [],
      workingDirectory: workingDirectory,
      environment: environment ?? {},
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      performance: TaskPerformance(
        startedAt: DateTime.now(),
        isolate: 'shell',
      ),
    );
    
    _tasks[taskId] = task;
    
    // Send command to shell isolate
    _sendToIsolate('shell', {
      'type': 'execute_command',
      'taskId': taskId,
      'command': command,
      'args': args ?? [],
      'workingDirectory': workingDirectory,
      'environment': environment ?? {},
    });
    
    debugPrint('🚀 Queued shell command: $command');
    return taskId;
  }
  
  /// Execute file operation in background
  String executeFileOperation(String operation, String filePath, {dynamic data}) {
    final taskId = 'file_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = BackgroundTask(
      id: taskId,
      type: TaskType.file,
      command: operation,
      args: [filePath],
      data: data,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      performance: TaskPerformance(
        startedAt: DateTime.now(),
        isolate: 'file',
      ),
    );
    
    _tasks[taskId] = task;
    
    // Send operation to file isolate
    _sendToIsolate('file', {
      'type': 'execute_operation',
      'taskId': taskId,
      'operation': operation,
      'filePath': filePath,
      'data': data,
    });
    
    debugPrint('🚀 Queued file operation: $operation on $filePath');
    return taskId;
  }
  
  /// Execute network request in background
  String executeNetworkRequest(String url, {String? method, Map<String, String>? headers, String? body, Duration? timeout}) {
    final taskId = 'network_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = BackgroundTask(
      id: taskId,
      type: TaskType.network,
      command: url,
      args: [],
      data: {
        'method': method ?? 'GET',
        'headers': headers ?? {},
        'body': body,
        'timeout': timeout?.inMilliseconds,
      },
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      performance: TaskPerformance(
        startedAt: DateTime.now(),
        isolate: 'network',
      ),
    );
    
    _tasks[taskId] = task;
    
    // Send request to network isolate
    _sendToIsolate('network', {
      'type': 'execute_request',
      'taskId': taskId,
      'url': url,
      'method': method ?? 'GET',
      'headers': headers ?? {},
      'body': body,
      'timeout': timeout?.inMilliseconds,
    });
    
    debugPrint('🚀 Queued network request: $method $url');
    return taskId;
  }
  
  /// Execute computation in background
  String executeComputation(String function, List<dynamic> parameters, {int? timeout}) {
    final taskId = 'computation_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = BackgroundTask(
      id: taskId,
      type: TaskType.computation,
      command: function,
      args: parameters,
      data: {'timeout': timeout?.inMilliseconds},
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      performance: TaskPerformance(
        startedAt: DateTime.now(),
        isolate: 'computation',
      ),
    );
    
    _tasks[taskId] = task;
    
    // Send computation to computation isolate
    _sendToIsolate('computation', {
      'type': 'execute_computation',
      'taskId': taskId,
      'function': function,
      'parameters': parameters,
      'timeout': timeout?.inMilliseconds,
    });
    
    debugPrint('🚀 Queued computation: $function');
    return taskId;
  }
  
  /// Send message to isolate
  void _sendToIsolate(String isolateName, Map<String, dynamic> message) {
    final isolate = _isolates[isolateName];
    if (isolate != null) {
      isolate.send(message);
    }
  }
  
  /// Get task by ID
  BackgroundTask? getTask(String taskId) {
    return _tasks[taskId];
  }
  
  /// Get tasks by type
  List<BackgroundTask> getTasksByType(TaskType type) {
    return _tasks.values.where((task) => task.type == type).toList();
  }
  
  /// Get tasks by status
  List<BackgroundTask> getTasksByStatus(TaskStatus status) {
    return _tasks.values.where((task) => task.status == status).toList();
  }
  
  /// Cancel task
  bool cancelTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return false;
    
    if (task.status == TaskStatus.pending || task.status == TaskStatus.running) {
      task.status = TaskStatus.cancelled;
      task.completedAt = DateTime.now();
      
      // Send cancel message to isolate
      _sendToIsolate(task.performance!.isolate, {
        'type': 'cancel_task',
        'taskId': taskId,
      });
      
      debugPrint('🚫 Cancelled task: $taskId');
      return true;
    }
    
    return false;
  }
  
  /// Retry task
  String retryTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return '';
    
    // Create new task with same parameters
    String newTaskId;
    switch (task.type) {
      case TaskType.shell:
        newTaskId = executeShellCommand(
          task.command,
          args: task.args,
          workingDirectory: task.workingDirectory,
          environment: task.environment,
        );
        break;
      case TaskType.file:
        newTaskId = executeFileOperation(
          task.command,
          task.args.first,
          data: task.data,
        );
        break;
      case TaskType.network:
        final data = task.data as Map<String, dynamic>;
        newTaskId = executeNetworkRequest(
          task.command,
          method: data['method'] as String?,
          headers: data['headers'] as Map<String, String>?,
          body: data['body'] as String?,
          timeout: data['timeout'] != null ? Duration(milliseconds: data['timeout']) : null,
        );
        break;
      case TaskType.computation:
        final data = task.data as Map<String, dynamic>;
        newTaskId = executeComputation(
          task.command,
          task.args,
          timeout: data['timeout'] != null ? Duration(milliseconds: data['timeout']) : null,
        );
        break;
      default:
        return '';
    }
    
    debugPrint('🔄 Retrying task: $taskId -> $newTaskId');
    return newTaskId;
  }
  
  /// Get task status
  TaskStatus getTaskStatus(String taskId) {
    final task = _tasks[taskId];
    return task?.status ?? TaskStatus.notFound;
  }
  
  /// Get task result
  dynamic getTaskResult(String taskId) {
    final task = _tasks[taskId];
    return task?.result;
  }
  
  /// Get task progress
  double getTaskProgress(String taskId) {
    final task = _tasks[taskId];
    return task?.progress ?? 0.0;
  }
  
  /// Update resource usage
  void _updateResourceUsage() {
    try {
      // Get current process resource usage
      final result = Process.runSync('ps', ['-o', '%cpu,%mem', '-p', Platform.pid.toString()]);
      
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final parts = output.trim().split(',');
        
        if (parts.length >= 2) {
          final cpuUsage = double.tryParse(parts[0]) ?? 0.0;
          final memoryUsage = int.tryParse(parts[1]) ?? 0;
          
          _resourceUsage['main'] = ResourceUsage(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            timestamp: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update resource usage: $e');
    }
  }
  
  /// Check task timeouts
  void _checkTaskTimeouts() {
    final now = DateTime.now();
    
    for (final task in _tasks.values) {
      if (task.status == TaskStatus.running || task.status == TaskStatus.pending) {
        final timeout = Duration(minutes: _config.taskTimeoutMinutes);
        
        if (now.difference(task.createdAt).compareTo(timeout) > 0) {
          task.status = TaskStatus.timeout;
          task.error = 'Task timeout';
          task.completedAt = now;
          
          debugPrint('⏰ Task timeout: ${task.id}');
        }
      }
    }
  }
  
  /// Cleanup completed tasks
  void _cleanupCompletedTasks() {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(hours: _config.completedTaskRetentionHours));
    
    final tasksToRemove = <String>[];
    for (final entry in _tasks.entries) {
      final task = entry.value;
      
      if ((task.status == TaskStatus.completed || task.status == TaskStatus.failed || task.status == TaskStatus.cancelled || task.status == TaskStatus.timeout) &&
          task.completedAt != null &&
          task.completedAt!.isBefore(cutoff)) {
        tasksToRemove.add(entry.key);
      }
    }
    
    for (final taskId in tasksToRemove) {
      _tasks.remove(taskId);
    }
    
    if (tasksToRemove.isNotEmpty) {
      debugPrint('🗑️ Cleaned up ${tasksToRemove.length} completed tasks');
    }
  }
  
  /// Get processor statistics
  ProcessorStatistics getStatistics() {
    final now = DateTime.now();
    
    final totalTasks = _tasks.length;
    final pendingTasks = _tasks.values.where((t) => t.status == TaskStatus.pending).length;
    final runningTasks = _tasks.values.where((t) => t.status == TaskStatus.running).length;
    final completedTasks = _tasks.values.where((t) => t.status == TaskStatus.completed).length;
    final failedTasks = _tasks.values.where((t) => t.status == TaskStatus.failed).length;
    
    final averageCompletionTime = _calculateAverageCompletionTime();
    
    return ProcessorStatistics(
      totalTasks: totalTasks,
      pendingTasks: pendingTasks,
      runningTasks: runningTasks,
      completedTasks: completedTasks,
      failedTasks: failedTasks,
      averageCompletionTime: averageCompletionTime,
      activeIsolates: _isolates.length,
      resourceUsage: _resourceUsage,
      performance: _performance,
      lastUpdated: now,
    );
  }
  
  /// Calculate average completion time
  Duration _calculateAverageCompletionTime() {
    final completedTasks = _tasks.values
        .where((t) => t.status == TaskStatus.completed && t.performance != null)
        .toList();
    
    if (completedTasks.isEmpty) return Duration.zero;
    
    final totalDuration = completedTasks
        .map((t) => t.performance!.duration)
        .reduce((sum, duration) => sum + duration, 0);
    
    return Duration(microseconds: totalDuration ~/ completedTasks.length);
  }
  
  /// Export task data
  String exportTaskData() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'tasks': _tasks.map((id, task) => MapEntry(id, task.toJson())).toMap(),
      'config': _config.toJson(),
      'statistics': getStatistics().toJson(),
    };
    
    return jsonEncode(data);
  }
  
  /// Import task data
  bool importTaskData(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Validate version
      final version = data['version'] as String?;
      if (version != null && !version.startsWith('1.')) {
        debugPrint('⚠️ Unsupported task data version: $version');
        return false;
      }
      
      // Import tasks
      final tasksData = data['tasks'] as Map<String, dynamic>?;
      if (tasksData != null) {
        for (final entry in tasksData.entries) {
          _tasks[entry.key] = BackgroundTask.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      debugPrint('📥 Imported task data successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import task data: $e');
      return false;
    }
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    // Cancel all running tasks
    for (final task in _tasks.values) {
      if (task.status == TaskStatus.running || task.status == TaskStatus.pending) {
        cancelTask(task.id);
      }
    }
    
    // Kill isolates
    for (final isolate in _isolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    
    _tasks.clear();
    _commandQueue.clear();
    _isolates.clear();
    _receivePorts.clear();
    _performance.clear();
    _resourceUsage.clear();
    
    _isInitialized = false;
    debugPrint('⚙️ Background Processor disposed');
  }
}

/// Shell isolate entry point
void shellIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  
  receivePort.listen((message) async {
    final messageData = message as Map<String, dynamic>;
    final type = messageData['type'] as String;
    
    switch (type) {
      case 'execute_command':
        await _executeShellCommand(messageData, receivePort);
        break;
      case 'cancel_task':
        // Handle task cancellation
        break;
    }
  });
}

/// Execute shell command in isolate
Future<void> _executeShellCommand(Map<String, dynamic> messageData, ReceivePort receivePort) async {
  final taskId = messageData['taskId'] as String;
  final command = messageData['command'] as String;
  final args = messageData['args'] as List<String>;
  final workingDirectory = messageData['workingDirectory'] as String?;
  final environment = messageData['environment'] as Map<String, String>;
  
  try {
    // Send task started notification
    receivePort.send({
      'type': 'task_progress',
      'taskId': taskId,
      'progress': 0.0,
      'message': 'Starting command...',
    });
    
    // Execute command
    final result = await Process.run(command, args, 
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );
    
    // Send completion notification
    receivePort.send({
      'type': 'task_result',
      'taskId': taskId,
      'result': {
        'exitCode': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      },
      'timestamp': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Send error notification
    receivePort.send({
      'type': 'task_error',
      'taskId': taskId,
      'error': e.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// File isolate entry point
void fileIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  
  receivePort.listen((message) async {
    final messageData = message as Map<String, dynamic>;
    final type = messageData['type'] as String;
    
    switch (type) {
      case 'execute_operation':
        await _executeFileOperation(messageData, receivePort);
        break;
      case 'cancel_task':
        // Handle task cancellation
        break;
    }
  });
}

/// Execute file operation in isolate
Future<void> _executeFileOperation(Map<String, dynamic> messageData, ReceivePort receivePort) async {
  final taskId = messageData['taskId'] as String;
  final operation = messageData['operation'] as String;
  final filePath = messageData['filePath'] as String;
  final data = messageData['data'];
  
  try {
    // Send task started notification
    receivePort.send({
      'type': 'task_progress',
      'taskId': taskId,
      'progress': 0.0,
      'message': 'Starting file operation...',
    });
    
    dynamic result;
    
    switch (operation) {
      case 'copy':
        result = await _copyFile(filePath, data['destination'] as String);
        break;
      case 'move':
        result = await _moveFile(filePath, data['destination'] as String);
        break;
      case 'delete':
        result = await _deleteFile(filePath);
        break;
      case 'read':
        result = await _readFile(filePath);
        break;
      case 'write':
        result = await _writeFile(filePath, data['content'] as String);
        break;
      case 'exists':
        result = await _fileExists(filePath);
        break;
      case 'stat':
        result = await _getFileStats(filePath);
        break;
      default:
        throw UnsupportedError('Unsupported file operation: $operation');
    }
    
    // Send completion notification
    receivePort.send({
      'type': 'task_result',
      'taskId': taskId,
      'result': result,
      'timestamp': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Send error notification
    receivePort.send({
      'type': 'task_error',
      'taskId': taskId,
      'error': e.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// Network isolate entry point
void networkIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  
  receivePort.listen((message) async {
    final messageData = message as Map<String, dynamic>;
    final type = messageData['type'] as String;
    
    switch (type) {
      case 'execute_request':
        await _executeNetworkRequest(messageData, receivePort);
        break;
      case 'cancel_task':
        // Handle task cancellation
        break;
    }
  });
}

/// Execute network request in isolate
Future<void> _executeNetworkRequest(Map<String, dynamic> messageData, ReceivePort receivePort) async {
  final taskId = messageData['taskId'] as String;
  final url = messageData['url'] as String;
  final method = messageData['method'] as String?;
  final headers = messageData['headers'] as Map<String, String>?;
  final body = messageData['body'] as String?;
  final timeout = messageData['timeout'] as int?;
  
  try {
    // Send task started notification
    receivePort.send({
      'type': 'task_progress',
      'taskId': taskId,
      'progress': 0.0,
      'message': 'Starting network request...',
    });
    
    // Create HTTP client
    final client = HttpClient();
    
    // Make request
    final request = await client.getUrl(Uri.parse(url));
    
    if (method != null) {
      request.headers.method = method;
    }
    
    if (headers != null) {
      request.headers.addAll(headers);
    }
    
    if (body != null) {
      request.add(body);
    }
    
    final response = await request.close().timeout(
      Duration(milliseconds: timeout ?? 30000),
    );
    
    // Read response body
    final responseBody = await response.transform(utf8.decoder).join();
    
    // Send completion notification
    receivePort.send({
      'type': 'task_result',
      'taskId': taskId,
      'result': {
        'statusCode': response.statusCode,
        'headers': response.headers,
        'body': responseBody,
      },
      'timestamp': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Send error notification
    receivePort.send({
      'type': 'task_error',
      'taskId': taskId,
      'error': e.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// Computation isolate entry point
void computationIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  
  receivePort.listen((message) async {
    final messageData = message as Map<String, dynamic>;
    final type = messageData['type'] as String;
    
    switch (type) {
      case 'execute_computation':
        await _executeComputation(messageData, receivePort);
        break;
      case 'cancel_task':
        // Handle task cancellation
        break;
    }
  });
}

/// Execute computation in isolate
Future<void> _executeComputation(Map<String, dynamic> messageData, ReceivePort receivePort) async {
  final taskId = messageData['taskId'] as String;
  final function = messageData['function'] as String;
  final parameters = messageData['parameters'] as List<dynamic>;
  final timeout = messageData['timeout'] as int?;
  
  try {
    // Send task started notification
    receivePort.send({
      'type': 'task_progress',
      'taskId': taskId,
      'progress': 0.0,
      'message': 'Starting computation...',
    });
    
    // Execute computation
    dynamic result;
    
    // This would need a proper function evaluation system
    // For now, just return the parameters
    result = {
      'function': function,
      'parameters': parameters,
      'result': 'Computation completed',
    };
    
    // Send completion notification
    receivePort.send({
      'type': 'task_result',
      'taskId': taskId,
      'result': result,
      'timestamp': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Send error notification
    receivePort.send({
      'type': 'task_error',
      'taskId': taskId,
      'error': e.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

/// File operation helpers
Future<dynamic> _copyFile(String source, String destination) async {
  final sourceFile = File(source);
  await sourceFile.copy(destination);
  return {'success': true};
}

Future<dynamic> _moveFile(String source, String destination) async {
  final sourceFile = File(source);
  await sourceFile.rename(destination);
  return {'success': true};
}

Future<dynamic> _deleteFile(String path) async {
  final file = File(path);
  await file.delete();
  return {'success': true};
}

Future<dynamic> _readFile(String path) async {
  final file = File(path);
  return await file.readAsString();
}

Future<dynamic> _writeFile(String path, String content) async {
  final file = File(path);
  await file.writeAsString(content);
  return {'success': true, 'bytesWritten': content.length};
}

Future<bool> _fileExists(String path) async {
  final file = File(path);
  return await file.exists();
}

Future<Map<String, dynamic>> _getFileStats(String path) async {
  final file = File(path);
  final stat = await file.stat();
  return {
    'size': stat.size,
    'modified': stat.modified.toIso8601String(),
    'accessed': stat.accessed.toIso8601String(),
    'type': stat.type,
  };
}

/// Background task data structure
class BackgroundTask {
  final String id;
  final TaskType type;
  final String command;
  final List<String> args;
  final String? workingDirectory;
  final Map<String, String> environment;
  final dynamic data;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;
  final dynamic result;
  final double progress;
  final String? statusMessage;
  final TaskPerformance? performance;
  
  BackgroundTask({
    required this.id,
    required this.type,
    required this.command,
    required this.args,
    this.workingDirectory,
    required this.environment,
    this.data,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.error,
    this.result,
    this.progress = 0.0,
    this.statusMessage,
    this.performance,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'command': command,
    'args': args,
    'workingDirectory': workingDirectory,
    'environment': environment,
    'data': data,
    'status': status.toString(),
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'error': error,
    'result': result,
    'progress': progress,
    'statusMessage': statusMessage,
    'performance': performance?.toJson(),
  };
  
  factory BackgroundTask.fromJson(Map<String, dynamic> json) {
    return BackgroundTask(
      id: json['id'] as String,
      type: TaskType.values.firstWhere((t) => t.toString() == json['type']),
      command: json['command'] as String,
      args: List<String>.from(json['args'] as List? ?? []),
      workingDirectory: json['workingDirectory'] as String?,
      environment: Map<String, String>.from(json['environment'] as Map<String, dynamic>? ?? {}),
      data: json['data'],
      status: TaskStatus.values.firstWhere((s) => s.toString() == json['status']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
      error: json['error'] as String?,
      result: json['result'],
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      statusMessage: json['statusMessage'] as String?,
      performance: json['performance'] != null ? TaskPerformance.fromJson(json['performance'] as Map<String, dynamic>) : null,
    );
  }
}

/// Task performance data structure
class TaskPerformance {
  final DateTime startedAt;
  final DateTime? completedAt;
  final int duration;
  final String isolate;
  
  TaskPerformance({
    required this.startedAt,
    this.completedAt,
    required this.duration,
    required this.isolate,
  });
  
  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'duration': duration,
    'isolate': isolate,
  };
  
  factory TaskPerformance.fromJson(Map<String, dynamic> json) {
    return TaskPerformance(
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
      duration: json['duration'] as int,
      isolate: json['isolate'] as String,
    );
  }
}

/// Resource usage data structure
class ResourceUsage {
  final double cpuUsage;
  final int memoryUsage;
  final DateTime timestamp;
  
  ResourceUsage({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.timestamp,
  });
}

/// Background processor configuration
class BackgroundProcessorConfig {
  final int maxConcurrentTasks;
  final int taskTimeoutMinutes;
  final int completedTaskRetentionHours;
  final bool enableResourceMonitoring;
  final Duration resourceUpdateInterval;
  final bool enablePerformanceMonitoring;
  
  BackgroundProcessorConfig({
    this.maxConcurrentTasks = 10,
    this.taskTimeoutMinutes = 30,
    this.completedTaskRetentionHours = 24,
    this.enableResourceMonitoring = true,
    this.resourceUpdateInterval = const Duration(seconds: 5),
    this.enablePerformanceMonitoring = true,
  });
  
  Map<String, dynamic> toJson() => {
    'maxConcurrentTasks': maxConcurrentTasks,
    'taskTimeoutMinutes': taskTimeoutMinutes,
    'completedTaskRetentionHours': completedTaskRetentionHours,
    'enableResourceMonitoring': enableResourceMonitoring,
    'resourceUpdateInterval': resourceUpdateInterval.inMilliseconds,
    'enablePerformanceMonitoring': enablePerformanceMonitoring,
  };
  
  factory BackgroundProcessorConfig.fromJson(Map<String, dynamic> json) {
    return BackgroundProcessorConfig(
      maxConcurrentTasks: json['maxConcurrentTasks'] as int? ?? 10,
      taskTimeoutMinutes: json['taskTimeoutMinutes'] as int? ?? 30,
      completedTaskRetentionHours: json['completedTaskRetentionHours'] as int? ?? 24,
      enableResourceMonitoring: json['enableResourceMonitoring'] as bool? ?? true,
      resourceUpdateInterval: Duration(milliseconds: json['resourceUpdateInterval'] as int? ?? 5000),
      enablePerformanceMonitoring: json['enablePerformanceMonitoring'] as bool? ?? true,
    );
  }
}

/// Processor statistics data structure
class ProcessorStatistics {
  final int totalTasks;
  final int pendingTasks;
  final int runningTasks;
  final int completedTasks;
  final int failedTasks;
  final Duration averageCompletionTime;
  final int activeIsolates;
  final Map<String, ResourceUsage> resourceUsage;
  final Map<String, TaskPerformance> performance;
  final DateTime lastUpdated;
  
  ProcessorStatistics({
    required this.totalTasks,
    required this.pendingTasks,
    required this.runningTasks,
    required this.completedTasks,
    required this.failedTasks,
    required this.averageCompletionTime,
    required this.activeIsolates,
    required this.resourceUsage,
    required this.performance,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'totalTasks': totalTasks,
    'pendingTasks': pendingTasks,
    'runningTasks': runningTasks,
    'completedTasks': completedTasks,
    'failedTasks': failedTasks,
    'averageCompletionTime': averageCompletionTime.inMicroseconds,
    'activeIsolates': activeIsolates,
    'resourceUsage': resourceUsage.map((k, v) => MapEntry(k, {
      'cpuUsage': v.cpuUsage,
      'memoryUsage': v.memoryUsage,
      'timestamp': v.timestamp.toIso8601String(),
    })),
    'performance': performance.map((k, v) => MapEntry(k, v.toJson())),
    'lastUpdated': lastUpdated.toIso8601String(),
  };
}

/// Task type enumeration
enum TaskType {
  shell,
  file,
  network,
  computation,
}

/// Task status enumeration
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
  timeout,
  notFound,
}
