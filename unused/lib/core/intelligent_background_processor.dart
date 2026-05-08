import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Intelligent background processing for Termisol
/// 
/// Features:
/// - Smart background task management
/// - AI-powered task optimization
/// - Resource-aware processing
/// - Priority-based execution
/// - Performance monitoring
class IntelligentBackgroundProcessor {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<BackgroundEvent> _eventController = StreamController<BackgroundEvent>.broadcast();
  
  final List<BackgroundTask> _taskQueue = [];
  final Map<String, BackgroundTask> _runningTasks = {};
  final Map<String, TaskPerformance> _taskPerformance = {};
  final Map<String, double> _resourceUsage = {};
  
  Timer? _processingTimer;
  Timer? _optimizationTimer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  int _maxConcurrentTasks = 3;
  double _resourceLimit = 0.8; // 80% of resources for background
  
  late SharedPreferences _prefs;
  
  Stream<BackgroundEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  
  IntelligentBackgroundProcessor({this.aiAssistant});
  
  /// Initialize background processor
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Start processing timer
      _processingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _processTaskQueue();
      });
      
      // Start optimization timer
      _optimizationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _optimizeTaskExecution();
      });
      
      _isInitialized = true;
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.initialized,
        message: 'Intelligent background processor initialized',
        data: {'max_concurrent_tasks': _maxConcurrentTasks},
      ));
    } catch (e) {
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.error,
        message: 'Failed to initialize background processor: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Add task to queue
  String addTask(BackgroundTask task) {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final queuedTask = BackgroundTask(
      id: taskId,
      type: task.type,
      command: task.command,
      arguments: task.arguments,
      priority: task.priority,
      status: TaskStatus.queued,
      createdAt: DateTime.now(),
      estimatedDuration: task.estimatedDuration,
      resourceUsage: task.resourceUsage,
      retryCount: 0,
      maxRetries: task.maxRetries,
    );
    
    _taskQueue.add(queuedTask);
    
    // Persist immediately for amnesia protection
    _persistTaskImmediately(queuedTask);
    
    _eventController.add(BackgroundEvent(
      type: BackgroundEventType.task_queued,
      message: 'Task queued: ${task.command}',
      data: {'task': queuedTask.toJson()},
    ));
    
    return taskId;
  }
  
  /// Process task queue
  void _processTaskQueue() {
    if (_isProcessing || _taskQueue.isEmpty) return;
    
    _isProcessing = true;
    
    try {
      // Sort tasks by priority and creation time
      _taskQueue.sort((a, b) {
        if (a.priority != b.priority) {
          return b.priority.index.compareTo(a.priority.index);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
      
      // Get available resources
      final availableResources = _getAvailableResources();
      
      // Process tasks while resources available
      while (_taskQueue.isNotEmpty && _canProcessTask(availableResources)) {
        final task = _taskQueue.removeAt(0);
        _executeTask(task);
      }
      
    } catch (e) {
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.error,
        message: 'Error processing task queue: $e',
        data: {'error': e.toString()},
      ));
    } finally {
      _isProcessing = false;
    }
  }
  
  bool _canProcessTask(Map<String, double> availableResources) {
    // Check if we have enough resources for another task
    final totalUsage = _runningTasks.values
        .fold(0.0, (sum, task) => sum + task.resourceUsage);
    
    return totalUsage < _resourceLimit && _runningTasks.length < _maxConcurrentTasks;
  }
  
  Map<String, double> _getAvailableResources() {
    // Calculate available resources
    final cpuUsage = _resourceUsage['cpu'] ?? 0.0;
    final memoryUsage = _resourceUsage['memory'] ?? 0.0;
    final diskIO = _resourceUsage['disk'] ?? 0.0;
    final networkBandwidth = _resourceUsage['network'] ?? 0.0;
    
    return {
      'cpu': max(0.0, 1.0 - cpuUsage),
      'memory': max(0.0, 1.0 - memoryUsage),
      'disk': max(0.0, 1.0 - diskIO),
      'network': max(0.0, 1.0 - networkBandwidth),
    };
  }
  
  Future<void> _executeTask(BackgroundTask task) async {
    _runningTasks[task.id] = task;
    
    try {
      // Update task status
      task.status = TaskStatus.running;
      task.startedAt = DateTime.now();
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.task_started,
        message: 'Task started: ${task.command}',
        data: {'task': task.toJson()},
      ));
      
      // Update resource usage
      _updateResourceUsage(task.resourceUsage, true);
      
      // Execute task
      final result = await _executeCommand(task.command, task.arguments);
      
      // Update task completion
      task.status = result.success ? TaskStatus.completed : TaskStatus.failed;
      task.completedAt = DateTime.now();
      task.output = result.output;
      task.error = result.error;
      task.executionTime = task.completedAt!.difference(task.startedAt!);
      
      // Update performance metrics
      _updateTaskPerformance(task);
      
      // Clean up
      _runningTasks.remove(task.id);
      _updateResourceUsage(task.resourceUsage, false);
      
      _eventController.add(BackgroundEvent(
        type: result.success ? BackgroundEventType.task_completed : BackgroundEventType.task_failed,
        message: 'Task ${result.success ? 'completed' : 'failed'}: ${task.command}',
        data: {'task': task.toJson()},
      ));
      
      // Persist task completion
      _persistTaskCompletion(task);
      
    } catch (e) {
      task.status = TaskStatus.failed;
      task.error = e.toString();
      task.completedAt = DateTime.now();
      
      _runningTasks.remove(task.id);
      _updateResourceUsage(task.resourceUsage, false);
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.task_failed,
        message: 'Task execution failed: ${task.command}',
        data: {'task': task.toJson(), 'error': e.toString()},
      ));
    }
  }
  
  Future<TaskResult> _executeCommand(String command, List<String> arguments) async {
    try {
      final result = await run(command, arguments);
      
      return TaskResult(
        success: result.exitCode == 0,
        output: result.stdout,
        error: result.stderr,
        exitCode: result.exitCode,
      );
    } catch (e) {
      return TaskResult(
        success: false,
        output: '',
        error: e.toString(),
        exitCode: -1,
      );
    }
  }
  
  void _updateResourceUsage(double usage, bool isAdding) {
    // Update resource usage tracking
    _resourceUsage['cpu'] = (_resourceUsage['cpu'] ?? 0.0) + (isAdding ? usage : -usage);
    _resourceUsage['memory'] = (_resourceUsage['memory'] ?? 0.0) + (isAdding ? usage : -usage);
    _resourceUsage['disk'] = (_resourceUsage['disk'] ?? 0.0) + (isAdding ? usage : -usage);
    _resourceUsage['network'] = (_resourceUsage['network'] ?? 0.0) + (isAdding ? usage : -usage);
    
    // Ensure values stay within bounds
    _resourceUsage['cpu'] = _resourceUsage['cpu']!.clamp(0.0, 1.0);
    _resourceUsage['memory'] = _resourceUsage['memory']!.clamp(0.0, 1.0);
    _resourceUsage['disk'] = _resourceUsage['disk']!.clamp(0.0, 1.0);
    _resourceUsage['network'] = _resourceUsage['network']!.clamp(0.0, 1.0);
  }
  
  void _updateTaskPerformance(BackgroundTask task) {
    final performance = _taskPerformance[task.type] ?? TaskPerformance();
    
    performance.executionCount++;
    performance.totalExecutionTime += task.executionTime?.inMilliseconds ?? 0;
    performance.averageExecutionTime = performance.totalExecutionTime / performance.executionCount;
    
    // Update success rate
    if (task.status == TaskStatus.completed) {
      performance.successCount++;
      performance.successRate = performance.successCount / performance.executionCount;
    } else {
      performance.failureCount++;
      performance.successRate = performance.successCount / performance.executionCount;
    }
    
    // Update last execution
    performance.lastExecution = task.executionTime;
    performance.lastExecutionTime = DateTime.now();
    
    _taskPerformance[task.type] = performance;
  }
  
  /// Optimize task execution with AI
  Future<void> _optimizeTaskExecution() async {
    if (aiAssistant == null) return;
    
    try {
      final prompt = '''Analyze current background task performance and provide optimization recommendations:

Current Running Tasks: ${_runningTasks.length}
Current Resource Usage: ${_resourceUsage.toString()}
Task Queue Size: ${_taskQueue.length}
Max Concurrent Tasks: $_maxConcurrentTasks
Resource Limit: ${_resourceLimit}

Task Performance Metrics:
${_taskPerformance.entries.map((entry) => '${entry.key}: ${entry.value.toJson()}').join('\n')}

Provide optimization recommendations for:
1. Task scheduling improvements
2. Resource allocation optimization
3. Priority queue adjustments
4. Performance bottlenecks identification
5. AI-powered task optimization

Use these NVIDIA AI models for best results:
- deepseek-ai/deepseek-v4-pro for comprehensive analysis
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for performance tuning
- minimaxai/minimax-m2.7 for resource management''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      // Apply AI optimization recommendations
      await _applyAIOptimizations(response);
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.optimization_completed,
        message: 'Background task optimization completed',
        data: {'ai_response': response},
      ));
      
    } catch (e) {
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.error,
        message: 'Failed to optimize tasks: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<void> _applyAIOptimizations(String aiResponse) async {
    // Parse AI response and apply optimizations
    final lines = aiResponse.split('\n');
    
    for (final line in lines) {
      if (line.toLowerCase().contains('increase concurrent tasks')) {
        _maxConcurrentTasks = min(_maxConcurrentTasks + 1, 10);
      } else if (line.toLowerCase().contains('adjust resource limit')) {
        _resourceLimit = (_resourceLimit + 0.1).clamp(0.5, 1.0);
      } else if (line.toLowerCase().contains('optimize task scheduling')) {
        _optimizeTaskScheduling();
      }
    }
    
    // Persist optimizations
    await _persistOptimizations();
  }
  
  void _optimizeTaskScheduling() {
    // Implement intelligent task scheduling
    // This would analyze task patterns and optimize execution order
  }
  
  /// Get task status
  Map<String, dynamic> getTaskStatus() {
    return {
      'is_initialized': _isInitialized,
      'is_processing': _isProcessing,
      'queue_size': _taskQueue.length,
      'running_tasks': _runningTasks.length,
      'max_concurrent_tasks': _maxConcurrentTasks,
      'resource_limit': _resourceLimit,
      'resource_usage': _resourceUsage,
      'task_performance': _taskPerformance.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
  
  /// Cancel task
  Future<bool> cancelTask(String taskId) async {
    // Remove from queue if not started
    final queueIndex = _taskQueue.indexWhere((task) => task.id == taskId);
    if (queueIndex != -1) {
      _taskQueue.removeAt(queueIndex);
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.task_cancelled,
        message: 'Task cancelled: $taskId',
        data: {'task_id': taskId},
      ));
      
      return true;
    }
    
    // Cancel running task
    final runningTask = _runningTasks[taskId];
    if (runningTask != null) {
      runningTask.status = TaskStatus.cancelled;
      runningTask.completedAt = DateTime.now();
      
      _runningTasks.remove(taskId);
      _updateResourceUsage(runningTask.resourceUsage, false);
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.task_cancelled,
        message: 'Running task cancelled: $taskId',
        data: {'task': runningTask.toJson()},
      ));
      
      return true;
    }
    
    return false;
  }
  
  /// Get task history
  List<BackgroundTask> getTaskHistory({TaskType? type, int limit = 50}) {
    // This would return task history from persistent storage
    // For now, return recent completed tasks
    return _taskQueue.where((task) => 
        task.status == TaskStatus.completed && 
        (type == null || task.type == type)
    ).take(limit).toList();
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load optimizations
      final maxConcurrent = _prefs.getInt('max_concurrent_tasks');
      if (maxConcurrent != null) {
        _maxConcurrentTasks = maxConcurrent;
      }
      
      final resourceLimit = _prefs.getDouble('resource_limit');
      if (resourceLimit != null) {
        _resourceLimit = resourceLimit;
      }
      
      _eventController.add(BackgroundEvent(
        type: BackgroundEventType.data_loaded,
        message: 'Background processor data loaded',
        data: {
          'max_concurrent_tasks': _maxConcurrentTasks,
          'resource_limit': _resourceLimit,
        },
      ));
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist task immediately for amnesia protection
  Future<void> _persistTaskImmediately(BackgroundTask task) async {
    try {
      final taskJson = jsonEncode(task.toJson());
      await _prefs.setString('task_${task.id}', taskJson);
    } catch (e) {
      debugPrint('❌ Failed to persist task immediately: $e');
    }
  }
  
  /// Persist task completion
  Future<void> _persistTaskCompletion(BackgroundTask task) async {
    try {
      final taskJson = jsonEncode(task.toJson());
      await _prefs.setString('task_${task.id}', taskJson);
      
      // Add to completion history
      final historyJson = _prefs.getString('task_completion_history') ?? '[]';
      final historyList = List<Map<String, dynamic>>.from(jsonDecode(historyJson));
      historyList.insert(0, task.toJson());
      
      // Keep only last 100 completions
      if (historyList.length > 100) {
        historyList.removeRange(100, historyList.length);
      }
      
      await _prefs.setString('task_completion_history', jsonEncode(historyList));
    } catch (e) {
      debugPrint('❌ Failed to persist task completion: $e');
    }
  }
  
  /// Persist optimizations
  Future<void> _persistOptimizations() async {
    try {
      await _prefs.setInt('max_concurrent_tasks', _maxConcurrentTasks);
      await _prefs.setDouble('resource_limit', _resourceLimit);
    } catch (e) {
      debugPrint('❌ Failed to persist optimizations: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _processingTimer?.cancel();
    _optimizationTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Background task
class BackgroundTask {
  final String id;
  final TaskType type;
  final String command;
  final List<String> arguments;
  final TaskPriority priority;
  TaskStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? estimatedDuration;
  final Duration? executionTime;
  final double resourceUsage;
  String? output;
  String? error;
  int retryCount;
  final int maxRetries;
  
  BackgroundTask({
    required this.id,
    required this.type,
    required this.command,
    required this.arguments,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.estimatedDuration,
    this.executionTime,
    required this.resourceUsage,
    this.output,
    this.error,
    this.retryCount = 0,
    this.maxRetries = 3,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'command': command,
    'arguments': arguments,
    'priority': priority.toString(),
    'status': status.toString(),
    'created_at': createdAt.toIso8601String(),
    'started_at': startedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'estimated_duration': estimatedDuration?.inMilliseconds,
    'execution_time': executionTime?.inMilliseconds,
    'resource_usage': resourceUsage,
    'output': output,
    'error': error,
    'retry_count': retryCount,
    'max_retries': maxRetries,
  };
}

/// Task types
enum TaskType {
  git_operation,
  docker_operation,
  file_operation,
  system_maintenance,
  ai_processing,
  backup_operation,
  cleanup_operation,
}

/// Task priority
enum TaskPriority {
  low,
  normal,
  high,
  critical,
}

/// Task status
enum TaskStatus {
  queued,
  running,
  completed,
  failed,
  cancelled,
  retrying,
}

/// Task result
class TaskResult {
  final bool success;
  final String output;
  final String error;
  final int exitCode;
  
  TaskResult({
    required this.success,
    required this.output,
    required this.error,
    required this.exitCode,
  });
}

/// Task performance metrics
class TaskPerformance {
  int executionCount = 0;
  int successCount = 0;
  int failureCount = 0;
  double successRate = 0.0;
  double totalExecutionTime = 0.0;
  double averageExecutionTime = 0.0;
  Duration? lastExecution;
  DateTime? lastExecutionTime;
  
  Map<String, dynamic> toJson() => {
    'execution_count': executionCount,
    'success_count': successCount,
    'failure_count': failureCount,
    'success_rate': successRate,
    'total_execution_time': totalExecutionTime,
    'average_execution_time': averageExecutionTime,
    'last_execution': lastExecution?.inMilliseconds,
    'last_execution_time': lastExecutionTime?.toIso8601String(),
  };
}

/// Background event types
enum BackgroundEventType {
  initialized,
  task_queued,
  task_started,
  task_completed,
  task_failed,
  task_cancelled,
  optimization_completed,
  data_loaded,
  error,
}

/// Background event
class BackgroundEvent {
  final BackgroundEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  BackgroundEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
