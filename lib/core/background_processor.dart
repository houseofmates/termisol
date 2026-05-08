import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// Background processor for handling CPU-intensive tasks off the main thread.
/// Uses isolates for true parallelism and manages task prioritization.
class BackgroundProcessor {
  static const int maxConcurrentTasks = 4;
  static const Duration taskTimeout = Duration(seconds: 30);

  final Queue<BackgroundTask> _taskQueue = Queue();
  final Map<String, TaskResult> _completedTasks = {};
  final StreamController<TaskEvent> _eventController = StreamController.broadcast();
  final Map<String, Isolate> _activeIsolates = {};
  final Map<String, SendPort> _isolatePorts = {};

  bool _isProcessing = false;
  int _activeTaskCount = 0;
  Timer? _processingTimer;

  /// Stream of task events (queued, started, completed, failed)
  Stream<TaskEvent> get events => _eventController.stream;

  /// Number of currently active tasks
  int get activeTaskCount => _activeTaskCount;

  /// Number of queued tasks
  int get queuedTaskCount => _taskQueue.length;

  /// Whether the processor is currently running
  bool get isProcessing => _isProcessing;

  BackgroundProcessor() {
    _initialize();
  }

  void _initialize() {
    // Start processing loop
    _processingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processQueue();
    });

    debugPrint('BackgroundProcessor initialized');
  }

  /// Submit a task for background processing
  Future<TaskResult> submitTask(
    String taskId,
    BackgroundTaskFunction function,
    dynamic data, {
    TaskPriority priority = TaskPriority.normal,
    Duration? timeout,
    Map<String, dynamic>? metadata,
  }) async {
    final task = BackgroundTask(
      id: taskId,
      function: function,
      data: data,
      priority: priority,
      timeout: timeout ?? taskTimeout,
      metadata: metadata,
      submittedAt: DateTime.now(),
    );

    // Add to appropriate position based on priority
    _insertTaskByPriority(task);

    _eventController.add(TaskEvent.queued(taskId, task.priority));

    // Return future that completes when task is done
    final completer = Completer<TaskResult>();
    task.completer = completer;

    return completer.future;
  }

  void _insertTaskByPriority(BackgroundTask task) {
    if (_taskQueue.isEmpty) {
      _taskQueue.add(task);
      return;
    }

    // Find insertion point based on priority
    int insertIndex = 0;
    for (int i = 0; i < _taskQueue.length; i++) {
      if (task.priority.value >= _taskQueue.elementAt(i).priority.value) {
        insertIndex = i;
        break;
      }
      insertIndex = i + 1;
    }

    // Insert at the found position
    final list = _taskQueue.toList();
    list.insert(insertIndex, task);
    _taskQueue.clear();
    _taskQueue.addAll(list);
  }

  void _processQueue() {
    if (_taskQueue.isEmpty || _activeTaskCount >= maxConcurrentTasks) {
      return;
    }

    final task = _taskQueue.removeFirst();
    _executeTask(task);
  }

  Future<void> _executeTask(BackgroundTask task) async {
    _activeTaskCount++;
    _isProcessing = true;

    _eventController.add(TaskEvent.started(task.id));

    try {
      // Create isolate for the task
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _IsolateMessage(task.id, task.function, task.data, receivePort.sendPort),
        onExit: receivePort.sendPort,
        onError: receivePort.sendPort,
      );

      _activeIsolates[task.id] = isolate;

      // Wait for result with timeout
      final result = await receivePort.first.timeout(task.timeout);

      if (result is TaskResult) {
        _completedTasks[task.id] = result;
        task.completer?.complete(result);
        _eventController.add(TaskEvent.completed(task.id, result));
      } else if (result is String && result.startsWith('error:')) {
        final error = result.substring(6);
        final errorResult = TaskResult.failure(task.id, error);
        _completedTasks[task.id] = errorResult;
        task.completer?.complete(errorResult);
        _eventController.add(TaskEvent.failed(task.id, error));
      }

    } catch (e) {
      final errorMessage = e.toString();
      final errorResult = TaskResult.failure(task.id, errorMessage);
      _completedTasks[task.id] = errorResult;
      task.completer?.complete(errorResult);
      _eventController.add(TaskEvent.failed(task.id, errorMessage));
    } finally {
      _activeIsolates.remove(task.id);
      _activeTaskCount--;
      _isProcessing = _activeTaskCount > 0;
    }
  }

  static void _isolateEntryPoint(_IsolateMessage message) {
    final sendPort = message.sendPort;

    try {
      // Execute the task function
      final result = message.function(message.data);

      if (result is Future) {
        result.then((value) {
          sendPort.send(TaskResult.success(message.taskId, value));
        }).catchError((error) {
          sendPort.send('error:$error');
        });
      } else {
        sendPort.send(TaskResult.success(message.taskId, result));
      }
    } catch (e) {
      sendPort.send('error:$e');
    }
  }

  /// Cancel a queued or running task
  Future<void> cancelTask(String taskId) async {
    // Remove from queue if not started
    _taskQueue.removeWhere((task) => task.id == taskId);

    // Kill isolate if running
    final isolate = _activeIsolates[taskId];
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
      _activeIsolates.remove(taskId);
      _activeTaskCount--;

      final cancelledResult = TaskResult.cancelled(taskId);
      _completedTasks[taskId] = cancelledResult;

      _eventController.add(TaskEvent.cancelled(taskId));
    }
  }

  /// Get the result of a completed task
  TaskResult? getTaskResult(String taskId) {
    return _completedTasks[taskId];
  }

  /// Clear completed tasks from memory
  void clearCompletedTasks() {
    _completedTasks.clear();
    debugPrint('Completed tasks cleared');
  }

  /// Get current processor status
  Map<String, dynamic> getStatus() {
    return {
      'isProcessing': _isProcessing,
      'activeTaskCount': _activeTaskCount,
      'queuedTaskCount': _queuedTaskCount,
      'maxConcurrentTasks': maxConcurrentTasks,
      'completedTaskCount': _completedTasks.length,
      'activeTaskIds': _activeIsolates.keys.toList(),
    };
  }

  /// Submit a high-priority task that should run immediately
  Future<TaskResult> submitHighPriorityTask(
    String taskId,
    BackgroundTaskFunction function,
    dynamic data, {
    Duration? timeout,
    Map<String, dynamic>? metadata,
  }) {
    return submitTask(
      taskId,
      function,
      data,
      priority: TaskPriority.high,
      timeout: timeout,
      metadata: metadata,
    );
  }

  /// Submit a low-priority task for background processing
  Future<TaskResult> submitLowPriorityTask(
    String taskId,
    BackgroundTaskFunction function,
    dynamic data, {
    Duration? timeout,
    Map<String, dynamic>? metadata,
  }) {
    return submitTask(
      taskId,
      function,
      data,
      priority: TaskPriority.low,
      timeout: timeout,
      metadata: metadata,
    );
  }

  /// Batch submit multiple tasks
  Future<List<TaskResult>> submitBatch(
    List<BackgroundTaskSpec> specs, {
    TaskPriority defaultPriority = TaskPriority.normal,
  }) async {
    final futures = <Future<TaskResult>>[];

    for (final spec in specs) {
      final future = submitTask(
        spec.id,
        spec.function,
        spec.data,
        priority: spec.priority ?? defaultPriority,
        timeout: spec.timeout,
        metadata: spec.metadata,
      );
      futures.add(future);
    }

    return Future.wait(futures);
  }

  /// Shutdown the processor and cancel all tasks
  Future<void> shutdown() async {
    _processingTimer?.cancel();

    // Cancel all queued tasks
    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      task.completer?.complete(TaskResult.cancelled(task.id));
    }

    // Kill all active isolates
    for (final isolate in _activeIsolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    _activeIsolates.clear();

    _eventController.close();
    debugPrint('BackgroundProcessor shutdown');
  }

  /// Dispose resources
  void dispose() {
    shutdown();
  }
}

/// Background task specification for batch operations
class BackgroundTaskSpec {
  final String id;
  final BackgroundTaskFunction function;
  final dynamic data;
  final TaskPriority? priority;
  final Duration? timeout;
  final Map<String, dynamic>? metadata;

  const BackgroundTaskSpec({
    required this.id,
    required this.function,
    required this.data,
    this.priority,
    this.timeout,
    this.metadata,
  });
}

/// Background task function type
typedef BackgroundTaskFunction = dynamic Function(dynamic data);

/// Internal message for isolate communication
class _IsolateMessage {
  final String taskId;
  final BackgroundTaskFunction function;
  final dynamic data;
  final SendPort sendPort;

  const _IsolateMessage(this.taskId, this.function, this.data, this.sendPort);
}

/// Background task representation
class BackgroundTask {
  final String id;
  final BackgroundTaskFunction function;
  final dynamic data;
  final TaskPriority priority;
  final Duration timeout;
  final Map<String, dynamic>? metadata;
  final DateTime submittedAt;
  Completer<TaskResult>? completer;

  const BackgroundTask({
    required this.id,
    required this.function,
    required this.data,
    required this.priority,
    required this.timeout,
    required this.submittedAt,
    this.metadata,
    this.completer,
  });
}

/// Task execution result
class TaskResult {
  final String taskId;
  final TaskStatus status;
  final dynamic result;
  final String? error;
  final DateTime completedAt;

  const TaskResult._({
    required this.taskId,
    required this.status,
    this.result,
    this.error,
    required this.completedAt,
  });

  factory TaskResult.success(String taskId, dynamic result) {
    return TaskResult._(
      taskId: taskId,
      status: TaskStatus.success,
      result: result,
      completedAt: DateTime.now(),
    );
  }

  factory TaskResult.failure(String taskId, String error) {
    return TaskResult._(
      taskId: taskId,
      status: TaskStatus.failure,
      error: error,
      completedAt: DateTime.now(),
    );
  }

  factory TaskResult.cancelled(String taskId) {
    return TaskResult._(
      taskId: taskId,
      status: TaskStatus.cancelled,
      completedAt: DateTime.now(),
    );
  }

  bool get isSuccess => status == TaskStatus.success;
  bool get isFailure => status == TaskStatus.failure;
  bool get isCancelled => status == TaskStatus.cancelled;

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'status': status.name,
    'result': result,
    'error': error,
    'completedAt': completedAt.toIso8601String(),
  };
}

/// Task event for monitoring
class TaskEvent {
  final String taskId;
  final TaskEventType type;
  final TaskPriority? priority;
  final TaskResult? result;
  final String? error;

  const TaskEvent._(this.taskId, this.type, {this.priority, this.result, this.error});

  factory TaskEvent.queued(String taskId, TaskPriority priority) {
    return TaskEvent._(taskId, TaskEventType.queued, priority: priority);
  }

  factory TaskEvent.started(String taskId) {
    return TaskEvent._(taskId, TaskEventType.started);
  }

  factory TaskEvent.completed(String taskId, TaskResult result) {
    return TaskEvent._(taskId, TaskEventType.completed, result: result);
  }

  factory TaskEvent.failed(String taskId, String error) {
    return TaskEvent._(taskId, TaskEventType.failed, error: error);
  }

  factory TaskEvent.cancelled(String taskId) {
    return TaskEvent._(taskId, TaskEventType.cancelled);
  }
}

/// Task priority levels
enum TaskPriority {
  low(0),
  normal(1),
  high(2),
  critical(3);

  const TaskPriority(this.value);
  final int value;
}

/// Task status
enum TaskStatus {
  success,
  failure,
  cancelled,
}

/// Task event types
enum TaskEventType {
  queued,
  started,
  completed,
  failed,
  cancelled,
}