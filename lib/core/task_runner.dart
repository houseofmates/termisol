import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

/// Task Runner
///
/// Manages and executes background tasks with priority scheduling,
/// cancellation support, rate limiting, and progress tracking.
class TaskRunner {
  final Queue<RunnerTask> _pendingTasks = Queue();
  final Map<String, RunnerTask> _runningTasks = {};
  final Map<String, TaskResult> _completedTasks = {};
  final Map<String, TaskProgress> _progress = {};
  int _maxConcurrent = 4;
  bool _isRunning = false;
  final StreamController<TaskEvent> _eventController = StreamController<TaskEvent>.broadcast();
  Timer? _watchdogTimer;

  Stream<TaskEvent> get events => _eventController.stream;
  int get pendingCount => _pendingTasks.length;
  int get runningCount => _runningTasks.length;

  Future<void> initialize({int maxConcurrent = 4}) async {
    _maxConcurrent = maxConcurrent;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) => _watchdogCheck());
    _startProcessing();
    debugPrint('TaskRunner initialized (max concurrent: $_maxConcurrent)');
  }

  Future<String> submit(Future<dynamic> Function(TaskProgressCallback) taskFn, {
    String? id,
    int priority = 0,
    String? name,
    Duration? timeout,
    Map<String, dynamic>? metadata,
  }) async {
    final taskId = id ?? 'task_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    final task = RunnerTask(
      id: taskId,
      name: name ?? 'Task ${_runningTasks.length + _pendingTasks.length + 1}',
      taskFn: taskFn,
      priority: priority,
      timeout: timeout ?? const Duration(minutes: 30),
      metadata: metadata ?? {},
      status: TaskStatus.pending,
    );

    _pendingTasks.add(task);
    _pendingTasks.toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    _rebalanceQueue();

    _startProcessing();

    return taskId;
  }

  Future<bool> cancel(String taskId) async {
    final running = _runningTasks[taskId];
    if (running != null) {
      running.cancelToken?.cancel();
      running.status = TaskStatus.cancelled;
      _runningTasks.remove(taskId);
      _eventController.add(TaskEvent(taskId: taskId, type: TaskEventType.cancelled));
      _startProcessing();
      return true;
    }

    final pending = _pendingTasks.firstWhereOrNull((t) => t.id == taskId);
    if (pending != null) {
      _pendingTasks.remove(pending);
      pending.status = TaskStatus.cancelled;
      _eventController.add(TaskEvent(taskId: taskId, type: TaskEventType.cancelled));
      return true;
    }

    return false;
  }

  Future<bool> pause(String taskId) async {
    final running = _runningTasks[taskId];
    if (running == null || running.status != TaskStatus.running) return false;
    running.status = TaskStatus.paused;
    _eventController.add(TaskEvent(taskId: taskId, type: TaskEventType.paused));
    return true;
  }

  Future<bool> resume(String taskId) async {
    final running = _runningTasks[taskId];
    if (running == null || running.status != TaskStatus.paused) return false;
    running.status = TaskStatus.running;
    _eventController.add(TaskEvent(taskId: taskId, type: TaskEventType.resumed));
    return true;
  }

  TaskStatus getStatus(String taskId) {
    return _runningTasks[taskId]?.status ??
        _completedTasks[taskId]?.status ??
        TaskStatus.unknown;
  }

  TaskProgress getProgress(String taskId) {
    return _progress[taskId] ?? TaskProgress(taskId: taskId, percent: 0.0);
  }

  TaskResult? getResult(String taskId) => _completedTasks[taskId];

  void setMaxConcurrent(int max) {
    _maxConcurrent = max.clamp(1, 16);
    _startProcessing();
  }

  Future<void> _startProcessing() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      while (_pendingTasks.isNotEmpty || _runningTasks.isNotEmpty) {
        while (_runningTasks.length < _maxConcurrent && _pendingTasks.isNotEmpty) {
          final task = _pendingTasks.removeFirst();
          await _executeTask(task);
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _executeTask(RunnerTask task) async {
    task.status = TaskStatus.running;
    task.startedAt = DateTime.now();
    _runningTasks[task.id] = task;
    _eventController.add(TaskEvent(taskId: task.id, type: TaskEventType.started));

    final cancelToken = CancelToken();
    task.cancelToken = cancelToken;

    try {
      final result = await task.taskFn((double percent, {String? message}) {
        _progress[task.id] = TaskProgress(taskId: task.id, percent: percent, message: message);
      }).timeout(task.timeout);

      task.status = TaskStatus.completed;
      task.completedAt = DateTime.now();
      _completedTasks[task.id] = TaskResult(
        taskId: task.id,
        success: true,
        value: result,
        duration: task.completedAt!.difference(task.startedAt!),
      );
      _runningTasks.remove(task.id);
      _eventController.add(TaskEvent(taskId: task.id, type: TaskEventType.completed));
    } catch (e) {
      if (e is TimeoutException || cancelToken.isCancelled) {
        task.status = TaskStatus.cancelled;
      } else {
        task.status = TaskStatus.failed;

        if (task.retries > 0) {
          task.retries--;
          _pendingTasks.add(task);
          _runningTasks.remove(task.id);
          _eventController.add(TaskEvent(taskId: task.id, type: TaskEventType.retrying));
          return;
        }
      }

      task.completedAt = DateTime.now();
      _completedTasks[task.id] = TaskResult(
        taskId: task.id,
        success: false,
        error: e.toString(),
        duration: task.startedAt != null ? task.completedAt!.difference(task.startedAt!) : Duration.zero,
      );
      _runningTasks.remove(task.id);
      _eventController.add(TaskEvent(taskId: task.id, type: TaskEventType.failed, message: e.toString()));
    }
  }

  void _rebalanceQueue() {
    final list = _pendingTasks.toList()..sort((a, b) => b.priority.compareTo(a.priority));
    _pendingTasks.clear();
    for (final task in list) {
      _pendingTasks.add(task);
    }
  }

  void _watchdogCheck() {
    final now = DateTime.now();
    for (final entry in _runningTasks.entries.toList()) {
      final task = entry.value;
      if (task.startedAt != null && task.timeout != Duration.zero) {
        final elapsed = now.difference(task.startedAt!);
        if (elapsed >= task.timeout) {
          cancel(entry.key);
        }
      }
    }
  }

  Future<void> dispose() async {
    _watchdogTimer?.cancel();
    await _eventController.close();
    _runningTasks.clear();
    _pendingTasks.clear();
    _completedTasks.clear();
  }
}

typedef TaskProgressCallback = void Function(double percent, {String? message});

enum TaskStatus { pending, running, paused, completed, failed, cancelled, unknown }

class RunnerTask {
  final String id;
  final String name;
  final Function taskFn;
  int priority;
  final Duration timeout;
  final Map<String, dynamic> metadata;
  TaskStatus status;
  int retries;
  DateTime? startedAt;
  DateTime? completedAt;
  CancelToken? cancelToken;

  RunnerTask({
    required this.id,
    required this.name,
    required this.taskFn,
    this.priority = 0,
    this.timeout = const Duration(minutes: 30),
    this.metadata = const {},
    this.status = TaskStatus.pending,
    this.retries = 0,
    this.startedAt,
    this.completedAt,
    this.cancelToken,
  });
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class TaskResult {
  final String taskId;
  final bool success;
  final dynamic value;
  final String? error;
  final Duration duration;

  TaskResult({required this.taskId, this.success = false, this.value, this.error, this.duration = Duration.zero});
  TaskStatus get status => success ? TaskStatus.completed : (error?.contains('cancelled') == true ? TaskStatus.cancelled : TaskStatus.failed);
}

class TaskProgress {
  final String taskId;
  final double percent;
  final String? message;

  TaskProgress({required this.taskId, required this.percent, this.message});
}

class TaskEvent {
  final String taskId;
  final TaskEventType type;
  final String? message;
  final DateTime timestamp;

  TaskEvent({required this.taskId, required this.type, this.message}) : timestamp = DateTime.now();
}

enum TaskEventType { started, completed, failed, cancelled, paused, resumed, retrying }
