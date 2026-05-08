import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Automated maintenance scheduler with intelligent task management
/// 
/// Features:
/// - Smart maintenance scheduling
/// - Resource-aware task execution
/// - Performance impact minimization
/// - Maintenance history tracking
/// - Adaptive scheduling based on usage patterns
class AutomatedMaintenanceScheduler {
  final StreamController<MaintenanceEvent> _eventController = StreamController<MaintenanceEvent>.broadcast();
  
  final Map<String, MaintenanceTask> _tasks = {};
  final Map<String, MaintenanceSchedule> _schedules = {};
  final List<MaintenanceExecution> _executionHistory = [];
  final Map<String, UsagePattern> _usagePatterns = {};
  
  Timer? _schedulerTimer;
  Timer? _usageMonitorTimer;
  bool _isInitialized = false;
  bool _isMaintenanceActive = false;
  late SharedPreferences _prefs;
  
  Stream<MaintenanceEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isMaintenanceActive => _isMaintenanceActive;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load maintenance data
      await _loadMaintenanceData();
      
      // Initialize default tasks
      _initializeDefaultTasks();
      
      // Initialize default schedules
      _initializeDefaultSchedules();
      
      // Start usage monitoring
      _startUsageMonitoring();
      
      // Start scheduler
      _startScheduler();
      
      _isInitialized = true;
      
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.initialized,
        message: 'Automated maintenance scheduler initialized',
        data: {
          'tasks': _tasks.length,
          'schedules': _schedules.length,
        },
      ));
      
      debugPrint('🔧 Automated Maintenance Scheduler initialized');
    } catch (e) {
      debugPrint('Failed to initialize automated maintenance scheduler: $e');
    }
  }
  
  Future<void> _loadMaintenanceData() async {
    try {
      final tasksJson = _prefs.getString('maintenance_tasks');
      if (tasksJson != null) {
        final tasksMap = jsonDecode(tasksJson);
        _tasks = tasksMap.map((key, value) => 
          MapEntry(key, MaintenanceTask.fromJson(value)));
      }
      
      final schedulesJson = _prefs.getString('maintenance_schedules');
      if (schedulesJson != null) {
        final schedulesMap = jsonDecode(schedulesJson);
        _schedules = schedulesMap.map((key, value) => 
          MapEntry(key, MaintenanceSchedule.fromJson(value)));
      }
      
      final historyJson = _prefs.getString('maintenance_history');
      if (historyJson != null) {
        final historyList = jsonDecode(historyJson);
        _executionHistory = historyList.map((item) => 
          MaintenanceExecution.fromJson(item)).toList();
      }
      
      final patternsJson = _prefs.getString('usage_patterns');
      if (patternsJson != null) {
        final patternsMap = jsonDecode(patternsJson);
        _usagePatterns = patternsMap.map((key, value) => 
          MapEntry(key, UsagePattern.fromJson(value)));
      }
    } catch (e) {
      debugPrint('Failed to load maintenance data: $e');
    }
  }
  
  void _initializeDefaultTasks() {
    // System cleanup tasks
    _tasks['temp_cleanup'] = MaintenanceTask(
      id: 'temp_cleanup',
      name: 'Temporary Files Cleanup',
      description: 'Remove temporary files and directories',
      command: 'find /tmp -type f -atime +7 -delete',
      estimatedDuration: const Duration(minutes: 5),
      resourceImpact: ResourceImpact.low,
      category: TaskCategory.cleanup,
      priority: TaskPriority.normal,
    );
    
    _tasks['cache_cleanup'] = MaintenanceTask(
      id: 'cache_cleanup',
      name: 'Application Cache Cleanup',
      description: 'Clear application caches',
      command: 'find ~/.cache -type f -atime +30 -delete',
      estimatedDuration: const Duration(minutes: 10),
      resourceImpact: ResourceImpact.medium,
      category: TaskCategory.cleanup,
      priority: TaskPriority.normal,
    );
    
    _tasks['log_rotation'] = MaintenanceTask(
      id: 'log_rotation',
      name: 'Log File Rotation',
      description: 'Rotate and compress old log files',
      command: 'find ~/.local/share/logs -name "*.log" -mtime +30 -exec gzip {} \\;',
      estimatedDuration: const Duration(minutes: 15),
      resourceImpact: ResourceImpact.medium,
      category: TaskCategory.maintenance,
      priority: TaskPriority.normal,
    );
    
    _tasks['package_update'] = MaintenanceTask(
      id: 'package_update',
      name: 'System Package Updates',
      description: 'Update system packages',
      command: 'sudo apt update && sudo apt upgrade -y',
      estimatedDuration: const Duration(minutes: 30),
      resourceImpact: ResourceImpact.high,
      category: TaskCategory.update,
      priority: TaskPriority.high,
    );
    
    _tasks['disk_optimization'] = MaintenanceTask(
      id: 'disk_optimization',
      name: 'Disk Optimization',
      description: 'Optimize disk layout and defragment',
      command: 'sudo e4defrag /',
      estimatedDuration: const Duration(hours: 2),
      resourceImpact: ResourceImpact.high,
      category: TaskCategory.optimization,
      priority: TaskPriority.low,
    );
    
    _tasks['memory_optimization'] = MaintenanceTask(
      id: 'memory_optimization',
      name: 'Memory Optimization',
      description: 'Optimize memory usage and clear caches',
      command: 'sync && sudo sysctl vm.drop_caches=3',
      estimatedDuration: const Duration(minutes: 2),
      resourceImpact: ResourceImpact.low,
      category: TaskCategory.optimization,
      priority: TaskPriority.normal,
    );
  }
  
  void _initializeDefaultSchedules() {
    // Daily schedules (low impact tasks)
    _schedules['daily_cleanup'] = MaintenanceSchedule(
      id: 'daily_cleanup',
      name: 'Daily Cleanup',
      description: 'Daily cleanup tasks',
      frequency: ScheduleFrequency.daily,
      time: const TimeOfDay(hour: 2, minute: 0),
      enabled: true,
      taskIds: ['temp_cleanup', 'memory_optimization'],
      maxResourceImpact: ResourceImpact.low,
    );
    
    // Weekly schedules (medium impact tasks)
    _schedules['weekly_maintenance'] = MaintenanceSchedule(
      id: 'weekly_maintenance',
      name: 'Weekly Maintenance',
      description: 'Weekly maintenance tasks',
      frequency: ScheduleFrequency.weekly,
      dayOfWeek: 1, // Monday
      time: const TimeOfDay(hour: 3, minute: 0),
      enabled: true,
      taskIds: ['cache_cleanup', 'log_rotation'],
      maxResourceImpact: ResourceImpact.medium,
    );
    
    // Monthly schedules (high impact tasks)
    _schedules['monthly_maintenance'] = MaintenanceSchedule(
      id: 'monthly_maintenance',
      name: 'Monthly Maintenance',
      description: 'Monthly deep maintenance',
      frequency: ScheduleFrequency.monthly,
      dayOfMonth: 1,
      time: const TimeOfDay(hour: 4, minute: 0),
      enabled: true,
      taskIds: ['package_update'],
      maxResourceImpact: ResourceImpact.high,
    );
    
    // Quarterly schedules (optimization tasks)
    _schedules['quarterly_optimization'] = MaintenanceSchedule(
      id: 'quarterly_optimization',
      name: 'Quarterly Optimization',
      description: 'Quarterly system optimization',
      frequency: ScheduleFrequency.monthly,
      dayOfMonth: 1,
      months: [1, 4, 7, 10], // Quarterly
      time: const TimeOfDay(hour: 5, minute: 0),
      enabled: true,
      taskIds: ['disk_optimization'],
      maxResourceImpact: ResourceImpact.high,
    );
  }
  
  void _startUsageMonitoring() {
    _usageMonitorTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _updateUsagePatterns();
    });
  }
  
  void _startScheduler() {
    _schedulerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAndExecuteMaintenance();
    });
  }
  
  void _updateUsagePatterns() {
    try {
      final now = DateTime.now();
      final hour = now.hour;
      final dayOfWeek = now.weekday;
      
      // Update hourly usage pattern
      final hourlyPattern = _usagePatterns['hourly'] ?? UsagePattern(
        type: PatternType.hourly,
        data: {},
        lastUpdated: now,
      );
      
      hourlyPattern.data[hour.toString()] = (hourlyPattern.data[hour.toString()] ?? 0) + 1;
      hourlyPattern.lastUpdated = now;
      _usagePatterns['hourly'] = hourlyPattern;
      
      // Update daily usage pattern
      final dailyPattern = _usagePatterns['daily'] ?? UsagePattern(
        type: PatternType.daily,
        data: {},
        lastUpdated: now,
      );
      
      dailyPattern.data[dayOfWeek.toString()] = (dailyPattern.data[dayOfWeek.toString()] ?? 0) + 1;
      dailyPattern.lastUpdated = now;
      _usagePatterns['daily'] = dailyPattern;
      
    } catch (e) {
      debugPrint('Failed to update usage patterns: $e');
    }
  }
  
  Future<void> _checkAndExecuteMaintenance() async {
    if (_isMaintenanceActive) return;
    
    try {
      final now = DateTime.now();
      
      for (final schedule in _schedules.values) {
        if (!schedule.enabled) continue;
        
        if (_shouldExecuteSchedule(schedule, now)) {
          await _executeSchedule(schedule);
        }
      }
    } catch (e) {
      debugPrint('Failed to check maintenance schedules: $e');
    }
  }
  
  bool _shouldExecuteSchedule(MaintenanceSchedule schedule, DateTime now) {
    // Check if it's the right time
    final scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.time.hour,
      schedule.time.minute,
    );
    
    if (now.isBefore(scheduledTime)) return false;
    
    // Check frequency
    switch (schedule.frequency) {
      case ScheduleFrequency.daily:
        return _wasExecutedToday(schedule.id, now);
        
      case ScheduleFrequency.weekly:
        if (schedule.dayOfWeek != null && now.weekday != schedule.dayOfWeek) {
          return false;
        }
        return _wasExecutedThisWeek(schedule.id, now);
        
      case ScheduleFrequency.monthly:
        if (schedule.dayOfMonth != null && now.day != schedule.dayOfMonth) {
          return false;
        }
        if (schedule.months != null && !schedule.months!.contains(now.month)) {
          return false;
        }
        return _wasExecutedThisMonth(schedule.id, now);
    }
  }
  
  bool _wasExecutedToday(String scheduleId, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.executedAt.isAfter(today.subtract(const Duration(days: 1))));
    
    return recentExecutions.isNotEmpty;
  }
  
  bool _wasExecutedThisWeek(String scheduleId, DateTime now) {
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.executedAt.isAfter(weekStart));
    
    return recentExecutions.isNotEmpty;
  }
  
  bool _wasExecutedThisMonth(String scheduleId, DateTime now) {
    final monthStart = DateTime(now.year, now.month, 1);
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.executedAt.isAfter(monthStart));
    
    return recentExecutions.isNotEmpty;
  }
  
  Future<void> _executeSchedule(MaintenanceSchedule schedule) async {
    if (_isMaintenanceActive) return;
    
    try {
      _isMaintenanceActive = true;
      
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.schedule_started,
        message: 'Executing maintenance schedule: ${schedule.name}',
        data: {
          'scheduleId': schedule.id,
          'taskIds': schedule.taskIds,
        },
      ));
      
      // Check system load before execution
      final systemLoad = await _getSystemLoad();
      if (systemLoad > 0.8 && schedule.maxResourceImpact == ResourceImpact.high) {
        _eventController.add(MaintenanceEvent(
          type: MaintenanceEventType.schedule_postponed,
          message: 'Maintenance postponed due to high system load',
          data: {
            'scheduleId': schedule.id,
            'systemLoad': systemLoad,
          },
        ));
        return;
      }
      
      // Execute tasks
      final execution = MaintenanceExecution(
        id: _generateExecutionId(),
        scheduleId: schedule.id,
        taskIds: schedule.taskIds,
        startedAt: DateTime.now(),
        status: ExecutionStatus.running,
      );
      
      _executionHistory.add(execution);
      
      for (final taskId in schedule.taskIds) {
        final task = _tasks[taskId];
        if (task == null) continue;
        
        await _executeTask(task, execution);
      }
      
      // Update execution status
      execution.completedAt = DateTime.now();
      execution.status = ExecutionStatus.completed;
      execution.success = true;
      
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.schedule_completed,
        message: 'Maintenance schedule completed: ${schedule.name}',
        data: {
          'executionId': execution.id,
          'duration': execution.completedAt!.difference(execution.startedAt).inMinutes,
        },
      ));
      
      // Save execution history
      await _saveMaintenanceData();
      
    } catch (e) {
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.error,
        message: 'Maintenance execution failed: $e',
      ));
    } finally {
      _isMaintenanceActive = false;
    }
  }
  
  Future<void> _executeTask(MaintenanceTask task, MaintenanceExecution execution) async {
    try {
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.task_started,
        message: 'Executing maintenance task: ${task.name}',
        data: {
          'taskId': task.id,
          'executionId': execution.id,
        },
      ));
      
      final result = await run(task.command, runInShell: true);
      
      final taskExecution = TaskExecution(
        taskId: task.id,
        executionId: execution.id,
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
        exitCode: result.exitCode,
        output: result.stdout,
        error: result.stderr,
        success: result.exitCode == 0,
      );
      
      execution.taskExecutions.add(taskExecution);
      
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.task_completed,
        message: 'Maintenance task completed: ${task.name}',
        data: {
          'taskId': task.id,
          'success': taskExecution.success,
          'exitCode': taskExecution.exitCode,
        },
      ));
      
    } catch (e) {
      _eventController.add(MaintenanceEvent(
        type: MaintenanceEventType.error,
        message: 'Task execution failed: ${task.name} - $e',
        data: {'taskId': task.id, 'error': e.toString()},
      ));
    }
  }
  
  Future<double> _getSystemLoad() async {
    try {
      final result = await run('sh', ['-c', "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//g'"]);
      final loadStr = result.stdout.trim();
      return double.tryParse(loadStr) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  String _generateExecutionId() {
    return 'exec_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  Future<void> _saveMaintenanceData() async {
    try {
      final tasksMap = _tasks.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('maintenance_tasks', jsonEncode(tasksMap));
      
      final schedulesMap = _schedules.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('maintenance_schedules', jsonEncode(schedulesMap));
      
      final historyList = _executionHistory.take(100).map((item) => item.toJson()).toList();
      await _prefs.setString('maintenance_history', jsonEncode(historyList));
      
      final patternsMap = _usagePatterns.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('usage_patterns', jsonEncode(patternsMap));
      
    } catch (e) {
      debugPrint('Failed to save maintenance data: $e');
    }
  }
  
  Future<void> addCustomTask({
    required String name,
    required String description,
    required String command,
    required Duration estimatedDuration,
    required ResourceImpact resourceImpact,
    required TaskCategory category,
    TaskPriority priority = TaskPriority.normal,
  }) async {
    final taskId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = MaintenanceTask(
      id: taskId,
      name: name,
      description: description,
      command: command,
      estimatedDuration: estimatedDuration,
      resourceImpact: resourceImpact,
      category: category,
      priority: priority,
    );
    
    _tasks[taskId] = task;
    await _saveMaintenanceData();
    
    _eventController.add(MaintenanceEvent(
      type: MaintenanceEventType.task_added,
      message: 'Custom maintenance task added: $name',
      data: {'taskId': taskId},
    ));
  }
  
  Future<void> createCustomSchedule({
    required String name,
    required String description,
    required List<String> taskIds,
    required ScheduleFrequency frequency,
    TimeOfDay? time,
    int? dayOfWeek,
    int? dayOfMonth,
    List<int>? months,
    bool enabled = true,
    ResourceImpact maxResourceImpact = ResourceImpact.medium,
  }) async {
    final scheduleId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    
    final schedule = MaintenanceSchedule(
      id: scheduleId,
      name: name,
      description: description,
      frequency: frequency,
      time: time ?? const TimeOfDay(hour: 2, minute: 0),
      dayOfWeek: dayOfWeek,
      dayOfMonth: dayOfMonth,
      months: months,
      enabled: enabled,
      taskIds: taskIds,
      maxResourceImpact: maxResourceImpact,
    );
    
    _schedules[scheduleId] = schedule;
    await _saveMaintenanceData();
    
    _eventController.add(MaintenanceEvent(
      type: MaintenanceEventType.schedule_added,
      message: 'Custom maintenance schedule added: $name',
      data: {'scheduleId': scheduleId},
    ));
  }
  
  Future<void> executeTaskNow(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    
    final execution = MaintenanceExecution(
      id: _generateExecutionId(),
      taskIds: [taskId],
      startedAt: DateTime.now(),
      status: ExecutionStatus.running,
      manualExecution: true,
    );
    
    _executionHistory.add(execution);
    await _executeTask(task, execution);
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isMaintenanceActive': _isMaintenanceActive,
      'totalTasks': _tasks.length,
      'totalSchedules': _schedules.length,
      'executionHistory': _executionHistory.length,
      'usagePatterns': _usagePatterns.length,
      'enabledSchedules': _schedules.values.where((s) => s.enabled).length,
      'successRate': _calculateSuccessRate(),
    };
  }
  
  double _calculateSuccessRate() {
    if (_executionHistory.isEmpty) return 0.0;
    
    final successful = _executionHistory.where((e) => e.success == true).length;
    return (successful / _executionHistory.length) * 100.0;
  }
  
  Future<void> dispose() async {
    _schedulerTimer?.cancel();
    _usageMonitorTimer?.cancel();
    
    await _saveMaintenanceData();
    
    _eventController.close();
    debugPrint('🔧 Automated Maintenance Scheduler disposed');
  }
}

// Data models
class MaintenanceTask {
  final String id;
  final String name;
  final String description;
  final String command;
  final Duration estimatedDuration;
  final ResourceImpact resourceImpact;
  final TaskCategory category;
  final TaskPriority priority;
  
  MaintenanceTask({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.estimatedDuration,
    required this.resourceImpact,
    required this.category,
    required this.priority,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'command': command,
    'estimatedDuration': estimatedDuration.inMinutes,
    'resourceImpact': resourceImpact.name,
    'category': category.name,
    'priority': priority.name,
  };
  
  factory MaintenanceTask.fromJson(Map<String, dynamic> json) => MaintenanceTask(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    command: json['command'],
    estimatedDuration: Duration(minutes: json['estimatedDuration'] ?? 0),
    resourceImpact: ResourceImpact.values.firstWhere((i) => i.name == json['resourceImpact'], orElse: () => ResourceImpact.low),
    category: TaskCategory.values.firstWhere((c) => c.name == json['category'], orElse: () => TaskCategory.cleanup),
    priority: TaskPriority.values.firstWhere((p) => p.name == json['priority'], orElse: () => TaskPriority.normal),
  );
}

class MaintenanceSchedule {
  final String id;
  final String name;
  final String description;
  final ScheduleFrequency frequency;
  final TimeOfDay time;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final List<int>? months;
  final bool enabled;
  final List<String> taskIds;
  final ResourceImpact maxResourceImpact;
  
  MaintenanceSchedule({
    required this.id,
    required this.name,
    required this.description,
    required this.frequency,
    required this.time,
    this.dayOfWeek,
    this.dayOfMonth,
    this.months,
    required this.enabled,
    required this.taskIds,
    required this.maxResourceImpact,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'frequency': frequency.name,
    'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    'dayOfWeek': dayOfWeek,
    'dayOfMonth': dayOfMonth,
    'months': months,
    'enabled': enabled,
    'taskIds': taskIds,
    'maxResourceImpact': maxResourceImpact.name,
  };
  
  factory MaintenanceSchedule.fromJson(Map<String, dynamic> json) => MaintenanceSchedule(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    frequency: ScheduleFrequency.values.firstWhere((f) => f.name == json['frequency'], orElse: () => ScheduleFrequency.daily),
    time: _parseTimeOfDay(json['time'] ?? '02:00'),
    dayOfWeek: json['dayOfWeek'],
    dayOfMonth: json['dayOfMonth'],
    months: (json['months'] as List<dynamic>?)?.cast<int>(),
    enabled: json['enabled'] ?? true,
    taskIds: (json['taskIds'] as List<dynamic>?)?.cast<String>() ?? [],
    maxResourceImpact: ResourceImpact.values.firstWhere((i) => i.name == json['maxResourceImpact'], orElse: () => ResourceImpact.low),
  );
  
  static TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }
}

class MaintenanceExecution {
  final String id;
  final String? scheduleId;
  final List<String> taskIds;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExecutionStatus status;
  final bool? success;
  final List<TaskExecution> taskExecutions;
  final bool manualExecution;
  
  MaintenanceExecution({
    required this.id,
    this.scheduleId,
    required this.taskIds,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.success,
    this.taskExecutions = const [],
    this.manualExecution = false,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleId': scheduleId,
    'taskIds': taskIds,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'status': status.name,
    'success': success,
    'taskExecutions': taskExecutions.map((e) => e.toJson()).toList(),
    'manualExecution': manualExecution,
  };
  
  factory MaintenanceExecution.fromJson(Map<String, dynamic> json) => MaintenanceExecution(
    id: json['id'],
    scheduleId: json['scheduleId'],
    taskIds: (json['taskIds'] as List<dynamic>?)?.cast<String>() ?? [],
    startedAt: DateTime.parse(json['startedAt']),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    status: ExecutionStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => ExecutionStatus.pending),
    success: json['success'],
    taskExecutions: (json['taskExecutions'] as List<dynamic>?)?.map((e) => TaskExecution.fromJson(e)).toList() ?? [],
    manualExecution: json['manualExecution'] ?? false,
  );
}

class TaskExecution {
  final String taskId;
  final String executionId;
  final DateTime startedAt;
  final DateTime completedAt;
  final int exitCode;
  final String output;
  final String error;
  final bool success;
  
  TaskExecution({
    required this.taskId,
    required this.executionId,
    required this.startedAt,
    required this.completedAt,
    required this.exitCode,
    required this.output,
    required this.error,
    required this.success,
  });
  
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'executionId': executionId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'exitCode': exitCode,
    'output': output,
    'error': error,
    'success': success,
  };
  
  factory TaskExecution.fromJson(Map<String, dynamic> json) => TaskExecution(
    taskId: json['taskId'],
    executionId: json['executionId'],
    startedAt: DateTime.parse(json['startedAt']),
    completedAt: DateTime.parse(json['completedAt']),
    exitCode: json['exitCode'],
    output: json['output'] ?? '',
    error: json['error'] ?? '',
    success: json['success'] ?? false,
  );
}

class UsagePattern {
  final PatternType type;
  final Map<String, dynamic> data;
  final DateTime lastUpdated;
  
  UsagePattern({
    required this.type,
    required this.data,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'data': data,
    'lastUpdated': lastUpdated.toIso8601String(),
  };
  
  factory UsagePattern.fromJson(Map<String, dynamic> json) => UsagePattern(
    type: PatternType.values.firstWhere((t) => t.name == json['type'], orElse: () => PatternType.hourly),
    data: json['data'] ?? {},
    lastUpdated: DateTime.parse(json['lastUpdated']),
  );
}

enum TaskCategory {
  cleanup,
  maintenance,
  update,
  optimization,
  security,
  backup,
}

enum TaskPriority {
  low,
  normal,
  high,
  critical,
}

enum ResourceImpact {
  low,
  medium,
  high,
}

enum ScheduleFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
  yearly,
}

enum ExecutionStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

enum PatternType {
  hourly,
  daily,
  weekly,
  monthly,
}

enum MaintenanceEventType {
  initialized,
  task_added,
  schedule_added,
  schedule_started,
  schedule_completed,
  schedule_postponed,
  task_started,
  task_completed,
  error,
}

class MaintenanceEvent {
  final MaintenanceEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  MaintenanceEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
