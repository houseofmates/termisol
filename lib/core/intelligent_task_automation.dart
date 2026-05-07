import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Intelligent task automation with workflow management
/// 
/// Features:
/// - Workflow creation and management
/// - Trigger-based automation
/// - Task scheduling and execution
/// - Conditional task execution
/// - Automation analytics and optimization
class IntelligentTaskAutomation {
  final StreamController<AutomationEvent> _eventController = StreamController<AutomationEvent>.broadcast();
  
  final Map<String, Workflow> _workflows = {};
  final Map<String, Trigger> _triggers = {};
  final Map<String, Task> _tasks = {};
  final List<WorkflowExecution> _executionHistory = [];
  final Map<String, AutomationMetric> _metrics = {};
  
  Timer? _triggerCheckTimer;
  Timer? _scheduleTimer;
  Timer? _cleanupTimer;
  bool _isInitialized = false;
  bool _isExecuting = false;
  late SharedPreferences _prefs;
  
  Stream<AutomationEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isExecuting => _isExecuting;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load automation data
      await _loadAutomationData();
      
      // Initialize default workflows
      _initializeDefaultWorkflows();
      
      // Initialize default triggers
      _initializeDefaultTriggers();
      
      // Start trigger checking
      _startTriggerChecking();
      
      // Start schedule checking
      _startScheduleChecking();
      
      // Start cleanup
      _startCleanup();
      
      _isInitialized = true;
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.initialized,
        message: 'Intelligent task automation initialized',
        data: {
          'workflows': _workflows.length,
          'triggers': _triggers.length,
          'tasks': _tasks.length,
        },
      ));
      
      debugPrint('⚙️ Intelligent Task Automation initialized');
    } catch (e) {
      debugPrint('Failed to initialize intelligent task automation: $e');
    }
  }
  
  Future<void> _loadAutomationData() async {
    try {
      final workflowsJson = _prefs.getString('automation_workflows');
      if (workflowsJson != null) {
        final workflowsMap = jsonDecode(workflowsJson);
        _workflows = workflowsMap.map((key, value) => 
          MapEntry(key, Workflow.fromJson(value)));
      }
      
      final triggersJson = _prefs.getString('automation_triggers');
      if (triggersJson != null) {
        final triggersMap = jsonDecode(triggersJson);
        _triggers = triggersMap.map((key, value) => 
          MapEntry(key, Trigger.fromJson(value)));
      }
      
      final tasksJson = _prefs.getString('automation_tasks');
      if (tasksJson != null) {
        final tasksMap = jsonDecode(tasksJson);
        _tasks = tasksMap.map((key, value) => 
          MapEntry(key, Task.fromJson(value)));
      }
      
      final historyJson = _prefs.getString('automation_history');
      if (historyJson != null) {
        final historyList = jsonDecode(historyJson);
        _executionHistory = historyList.map((item) => 
          WorkflowExecution.fromJson(item)).toList();
      }
      
      final metricsJson = _prefs.getString('automation_metrics');
      if (metricsJson != null) {
        final metricsMap = jsonDecode(metricsJson);
        _metrics = metricsMap.map((key, value) => 
          MapEntry(key, AutomationMetric.fromJson(value)));
      }
    } catch (e) {
      debugPrint('Failed to load automation data: $e');
    }
  }
  
  void _initializeDefaultWorkflows() {
    // File cleanup workflow
    _workflows['file_cleanup'] = Workflow(
      id: 'file_cleanup',
      name: 'File Cleanup',
      description: 'Automated file cleanup and organization',
      enabled: true,
      triggers: ['daily_cleanup_trigger'],
      tasks: [
        'clean_temp_files',
        'organize_downloads',
        'compress_old_files',
      ],
      conditions: [],
      createdAt: DateTime.now(),
      lastExecuted: null,
      executionCount: 0,
    );
    
    // System maintenance workflow
    _workflows['system_maintenance'] = Workflow(
      id: 'system_maintenance',
      name: 'System Maintenance',
      description: 'Automated system maintenance tasks',
      enabled: true,
      triggers: ['weekly_maintenance_trigger'],
      tasks: [
        'update_system',
        'clean_logs',
        'check_disk_space',
        'optimize_performance',
      ],
      conditions: [],
      createdAt: DateTime.now(),
      lastExecuted: null,
      executionCount: 0,
    );
    
    // Development workflow
    _workflows['development_setup'] = Workflow(
      id: 'development_setup',
      name: 'Development Setup',
      description: 'Automated development environment setup',
      enabled: true,
      triggers: ['project_open_trigger'],
      tasks: [
        'start_services',
        'open_ide',
        'setup_environment',
        'check_dependencies',
      ],
      conditions: [],
      createdAt: DateTime.now(),
      lastExecuted: null,
      executionCount: 0,
    );
    
    // Backup workflow
    _workflows['automated_backup'] = Workflow(
      id: 'automated_backup',
      name: 'Automated Backup',
      description: 'Automated backup of important files',
      enabled: true,
      triggers: ['backup_schedule_trigger'],
      tasks: [
        'backup_documents',
        'backup_code',
        'backup_config',
      ],
      conditions: [],
      createdAt: DateTime.now(),
      lastExecuted: null,
      executionCount: 0,
    );
  }
  
  void _initializeDefaultTriggers() {
    // Time-based triggers
    _triggers['daily_cleanup_trigger'] = Trigger(
      id: 'daily_cleanup_trigger',
      name: 'Daily Cleanup Trigger',
      type: TriggerType.time_based,
      enabled: true,
      config: {
        'time': '02:00',
        'days': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    _triggers['weekly_maintenance_trigger'] = Trigger(
      id: 'weekly_maintenance_trigger',
      name: 'Weekly Maintenance Trigger',
      type: TriggerType.time_based,
      enabled: true,
      config: {
        'time': '03:00',
        'days': ['sunday'],
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    _triggers['backup_schedule_trigger'] = Trigger(
      id: 'backup_schedule_trigger',
      name: 'Backup Schedule Trigger',
      type: TriggerType.time_based,
      enabled: true,
      config: {
        'time': '01:00',
        'days': ['monday', 'wednesday', 'friday'],
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    // Event-based triggers
    _triggers['project_open_trigger'] = Trigger(
      id: 'project_open_trigger',
      name: 'Project Open Trigger',
      type: TriggerType.event_based,
      enabled: true,
      config: {
        'event': 'project_opened',
        'conditions': {
          'project_type': ['development', 'design'],
        },
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    // System-based triggers
    _triggers['low_disk_space_trigger'] = Trigger(
      id: 'low_disk_space_trigger',
      name: 'Low Disk Space Trigger',
      type: TriggerType.system_based,
      enabled: true,
      config: {
        'condition': 'disk_usage > 90',
        'check_interval': 300, // 5 minutes
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    _triggers['high_cpu_trigger'] = Trigger(
      id: 'high_cpu_trigger',
      name: 'High CPU Usage Trigger',
      type: TriggerType.system_based,
      enabled: true,
      config: {
        'condition': 'cpu_usage > 85',
        'duration': 300, // 5 minutes
      },
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
  }
  
  void _startTriggerChecking() {
    _triggerCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkTriggers();
    });
  }
  
  void _startScheduleChecking() {
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkScheduledTasks();
    });
  }
  
  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _performAutomationCleanup();
    });
  }
  
  Future<void> _checkTriggers() async {
    try {
      for (final trigger in _triggers.values) {
        if (!trigger.enabled) continue;
        
        if (await _evaluateTrigger(trigger)) {
          await _executeTrigger(trigger);
        }
      }
    } catch (e) {
      debugPrint('Failed to check triggers: $e');
    }
  }
  
  Future<void> _checkScheduledTasks() async {
    try {
      final now = DateTime.now();
      
      for (final workflow in _workflows.values) {
        if (!workflow.enabled) continue;
        
        // Check if workflow should be scheduled
        if (await _shouldScheduleWorkflow(workflow, now)) {
          await _executeWorkflow(workflow);
        }
      }
    } catch (e) {
      debugPrint('Failed to check scheduled tasks: $e');
    }
  }
  
  Future<bool> _evaluateTrigger(Trigger trigger) async {
    try {
      switch (trigger.type) {
        case TriggerType.time_based:
          return _evaluateTimeTrigger(trigger);
        case TriggerType.event_based:
          return _evaluateEventTrigger(trigger);
        case TriggerType.system_based:
          return _evaluateSystemTrigger(trigger);
        case TriggerType.file_based:
          return _evaluateFileTrigger(trigger);
        default:
          return false;
      }
    } catch (e) {
      debugPrint('Failed to evaluate trigger: $e');
      return false;
    }
  }
  
  Future<bool> _evaluateTimeTrigger(Trigger trigger) async {
    try {
      final config = trigger.config;
      final timeStr = config['time'] as String;
      final days = (config['days'] as List<dynamic>?)?.cast<String>() ?? [];
      
      final timeParts = timeStr.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      
      final now = DateTime.now();
      final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);
      
      // Check if current time is past scheduled time
      if (now.isAfter(scheduledTime)) {
        // Check if today is in the allowed days
        final dayName = now.weekday.toString().toLowerCase();
        final dayMap = {
          '1': 'monday',
          '2': 'tuesday',
          '3': 'wednesday',
          '4': 'thursday',
          '5': 'friday',
          '6': 'saturday',
          '7': 'sunday',
        };
        
        return days.contains(dayMap[now.weekday.toString()]);
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate time trigger: $e');
      return false;
    }
  }
  
  Future<bool> _evaluateEventTrigger(Trigger trigger) async {
    try {
      final config = trigger.config;
      final eventType = config['event'] as String;
      
      // This would integrate with system event monitoring
      // For now, return false as we don't have event monitoring
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate event trigger: $e');
      return false;
    }
  }
  
  Future<bool> _evaluateSystemTrigger(Trigger trigger) async {
    try {
      final config = trigger.config;
      final condition = config['condition'] as String;
      
      if (condition.contains('disk_usage')) {
        final threshold = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final diskUsage = await _getDiskUsage();
        return diskUsage > threshold;
      }
      
      if (condition.contains('cpu_usage')) {
        final threshold = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final cpuUsage = await _getCpuUsage();
        return cpuUsage > threshold;
      }
      
      if (condition.contains('memory_usage')) {
        final threshold = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final memoryUsage = await _getMemoryUsage();
        return memoryUsage > threshold;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate system trigger: $e');
      return false;
    }
  }
  
  Future<bool> _evaluateFileTrigger(Trigger trigger) async {
    try {
      final config = trigger.config;
      final filePath = config['file_path'] as String;
      final condition = config['condition'] as String;
      
      final file = File(filePath);
      if (!await file.exists()) return false;
      
      if (condition.contains('file_exists')) {
        return true;
      }
      
      if (condition.contains('file_modified')) {
        final stat = await file.stat();
        final lastModified = stat.modified;
        final checkInterval = Duration(minutes: (config['check_interval'] as int?) ?? 60);
        
        return DateTime.now().difference(lastModified) < checkInterval;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate file trigger: $e');
      return false;
    }
  }
  
  Future<bool> _shouldScheduleWorkflow(Workflow workflow, DateTime now) async {
    try {
      // Check if workflow has time-based triggers
      for (final triggerId in workflow.triggers) {
        final trigger = _triggers[triggerId];
        if (trigger != null && trigger.type == TriggerType.time_based) {
          return await _evaluateTimeTrigger(trigger);
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to check workflow scheduling: $e');
      return false;
    }
  }
  
  Future<void> _executeTrigger(Trigger trigger) async {
    try {
      trigger.lastTriggered = DateTime.now();
      trigger.triggerCount++;
      
      // Find workflows that use this trigger
      final affectedWorkflows = _workflows.values.where((w) => 
          w.enabled && w.triggers.contains(trigger.id));
      
      for (final workflow in affectedWorkflows) {
        await _executeWorkflow(workflow);
      }
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.trigger_fired,
        message: 'Trigger fired: ${trigger.name}',
        data: {
          'triggerId': trigger.id,
          'affectedWorkflows': affectedWorkflows.length,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to execute trigger: $e');
    }
  }
  
  Future<void> _executeWorkflow(Workflow workflow) async {
    if (_isExecuting) return;
    
    try {
      _isExecuting = true;
      
      final execution = WorkflowExecution(
        id: 'exec_${DateTime.now().millisecondsSinceEpoch}',
        workflowId: workflow.id,
        startedAt: DateTime.now(),
        status: ExecutionStatus.running,
        tasks: [],
      );
      
      _executionHistory.add(execution);
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.workflow_started,
        message: 'Workflow started: ${workflow.name}',
        data: {
          'workflowId': workflow.id,
          'executionId': execution.id,
        },
      ));
      
      // Execute tasks
      for (final taskId in workflow.tasks) {
        final task = _tasks[taskId];
        if (task == null) continue;
        
        await _executeTask(task, execution);
      }
      
      // Update workflow
      workflow.lastExecuted = DateTime.now();
      workflow.executionCount++;
      
      // Update execution
      execution.completedAt = DateTime.now();
      execution.status = ExecutionStatus.completed;
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.workflow_completed,
        message: 'Workflow completed: ${workflow.name}',
        data: {
          'workflowId': workflow.id,
          'executionId': execution.id,
          'duration': execution.completedAt!.difference(execution.startedAt).inSeconds,
        },
      ));
      
      await _saveAutomationData();
    } catch (e) {
      debugPrint('Failed to execute workflow: $e');
    } finally {
      _isExecuting = false;
    }
  }
  
  Future<void> _executeTask(Task task, WorkflowExecution execution) async {
    try {
      final taskExecution = TaskExecution(
        taskId: task.id,
        startedAt: DateTime.now(),
        status: ExecutionStatus.running,
      );
      
      execution.tasks.add(taskExecution);
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.task_started,
        message: 'Task started: ${task.name}',
        data: {
          'taskId': task.id,
          'executionId': execution.id,
        },
      ));
      
      // Execute task based on type
      bool success = false;
      String? error;
      
      switch (task.type) {
        case TaskType.command:
          success = await _executeCommandTask(task);
          break;
        case TaskType.script:
          success = await _executeScriptTask(task);
          break;
        case TaskType.file_operation:
          success = await _executeFileOperationTask(task);
          break;
        case TaskType.system_operation:
          success = await _executeSystemOperationTask(task);
          break;
        case TaskType.notification:
          success = await _executeNotificationTask(task);
          break;
        default:
          error = 'Unknown task type: ${task.type}';
      }
      
      // Update task execution
      taskExecution.completedAt = DateTime.now();
      taskExecution.status = success ? ExecutionStatus.completed : ExecutionStatus.failed;
      taskExecution.error = error;
      
      _eventController.add(AutomationEvent(
        type: AutomationEventType.task_completed,
        message: 'Task ${success ? 'completed' : 'failed'}: ${task.name}',
        data: {
          'taskId': task.id,
          'executionId': execution.id,
          'success': success,
          'error': error,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to execute task: $e');
    }
  }
  
  Future<bool> _executeCommandTask(Task task) async {
    try {
      final command = task.config['command'] as String;
      final args = (task.config['args'] as List<dynamic>?)?.cast<String>() ?? [];
      
      final result = await run(command, args);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to execute command task: $e');
      return false;
    }
  }
  
  Future<bool> _executeScriptTask(Task task) async {
    try {
      final scriptPath = task.config['script_path'] as String;
      final script = File(scriptPath);
      
      if (!await script.exists()) {
        debugPrint('Script not found: $scriptPath');
        return false;
      }
      
      final result = await run('bash', [scriptPath]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to execute script task: $e');
      return false;
    }
  }
  
  Future<bool> _executeFileOperationTask(Task task) async {
    try {
      final operation = task.config['operation'] as String;
      final path = task.config['path'] as String;
      
      switch (operation) {
        case 'delete':
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            return true;
          }
          break;
        case 'move':
          final source = File(task.config['source'] as String);
          final destination = task.config['destination'] as String;
          if (await source.exists()) {
            await source.rename(destination);
            return true;
          }
          break;
        case 'copy':
          final source = File(task.config['source'] as String);
          final destination = task.config['destination'] as String;
          if (await source.exists()) {
            await source.copy(destination);
            return true;
          }
          break;
        case 'create_directory':
          final dir = Directory(path);
          await dir.create(recursive: true);
          return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to execute file operation task: $e');
      return false;
    }
  }
  
  Future<bool> _executeSystemOperationTask(Task task) async {
    try {
      final operation = task.config['operation'] as String;
      
      switch (operation) {
        case 'shutdown':
          await run('systemctl', ['poweroff']);
          return true;
        case 'reboot':
          await run('systemctl', ['reboot']);
          return true;
        case 'suspend':
          await run('systemctl', ['suspend']);
          return true;
        case 'hibernate':
          await run('systemctl', ['hibernate']);
          return true;
        case 'lock_screen':
          await run('loginctl', ['lock-session']);
          return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to execute system operation task: $e');
      return false;
    }
  }
  
  Future<bool> _executeNotificationTask(Task task) async {
    try {
      final message = task.config['message'] as String;
      final title = task.config['title'] as String;
      final urgency = task.config['urgency'] as String? ?? 'normal';
      
      // Use notify-send for Linux notifications
      final result = await run('notify-send', [
        '--urgency=$urgency',
        '--app-name=Termisol Automation',
        title,
        message,
      ]);
      
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to execute notification task: $e');
      return false;
    }
  }
  
  Future<void> _performAutomationCleanup() async {
    try {
      // Clean old execution history (keep last 100)
      if (_executionHistory.length > 100) {
        _executionHistory.removeRange(0, _executionHistory.length - 100);
      }
      
      // Clean old metrics (keep last 500)
      if (_metrics.length > 500) {
        final keys = _metrics.keys.toList()..sort();
        final toRemove = keys.take(_metrics.length - 500);
        for (final key in toRemove) {
          _metrics.remove(key);
        }
      }
      
      await _saveAutomationData();
    } catch (e) {
      debugPrint('Failed to perform automation cleanup: $e');
    }
  }
  
  // Helper methods for system monitoring
  Future<double> _getDiskUsage() async {
    try {
      final result = await run('df', ['-h', '/']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('/dev/')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final usageStr = parts[4].replaceAll('%', '');
            return double.tryParse(usageStr) ?? 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getCpuUsage() async {
    try {
      final result = await run('top', ['-bn', '1']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.contains('%Cpu(s):')) {
          final match = RegExp(r'\s+([0-9.]+)%\s+us').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getMemoryUsage() async {
    try {
      final result = await run('free', ['-m']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('Mem:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final total = double.tryParse(parts[1]) ?? 0.0;
            final used = double.tryParse(parts[2]) ?? 0.0;
            return total > 0 ? (used / total) * 100.0 : 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<void> _saveAutomationData() async {
    try {
      final workflowsMap = _workflows.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('automation_workflows', jsonEncode(workflowsMap));
      
      final triggersMap = _triggers.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('automation_triggers', jsonEncode(triggersMap));
      
      final tasksMap = _tasks.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('automation_tasks', jsonEncode(tasksMap));
      
      final historyList = _executionHistory.take(100).map((item) => item.toJson()).toList();
      await _prefs.setString('automation_history', jsonEncode(historyList));
      
      final metricsMap = _metrics.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('automation_metrics', jsonEncode(metricsMap));
    } catch (e) {
      debugPrint('Failed to save automation data: $e');
    }
  }
  
  Future<void> createWorkflow({
    required String name,
    required String description,
    required List<String> triggers,
    required List<String> tasks,
    List<String> conditions = const [],
    bool enabled = true,
  }) async {
    final workflowId = 'workflow_${DateTime.now().millisecondsSinceEpoch}';
    
    final workflow = Workflow(
      id: workflowId,
      name: name,
      description: description,
      enabled: enabled,
      triggers: triggers,
      tasks: tasks,
      conditions: conditions,
      createdAt: DateTime.now(),
      lastExecuted: null,
      executionCount: 0,
    );
    
    _workflows[workflowId] = workflow;
    await _saveAutomationData();
    
    _eventController.add(AutomationEvent(
      type: AutomationEventType.workflow_created,
      message: 'Workflow created: $name',
      data: {'workflowId': workflowId},
    ));
  }
  
  Future<void> createTrigger({
    required String name,
    required TriggerType type,
    required Map<String, dynamic> config,
    bool enabled = true,
  }) async {
    final triggerId = 'trigger_${DateTime.now().millisecondsSinceEpoch}';
    
    final trigger = Trigger(
      id: triggerId,
      name: name,
      type: type,
      enabled: enabled,
      config: config,
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    _triggers[triggerId] = trigger;
    await _saveAutomationData();
    
    _eventController.add(AutomationEvent(
      type: AutomationEventType.trigger_created,
      message: 'Trigger created: $name',
      data: {'triggerId': triggerId},
    ));
  }
  
  Future<void> createTask({
    required String name,
    required TaskType type,
    required Map<String, dynamic> config,
    String description = '',
  }) async {
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
    
    final task = Task(
      id: taskId,
      name: name,
      description: description,
      type: type,
      config: config,
      createdAt: DateTime.now(),
    );
    
    _tasks[taskId] = task;
    await _saveAutomationData();
    
    _eventController.add(AutomationEvent(
      type: AutomationEventType.task_created,
      message: 'Task created: $name',
      data: {'taskId': taskId},
    ));
  }
  
  Future<void> executeWorkflowNow(String workflowId) async {
    final workflow = _workflows[workflowId];
    if (workflow == null) return;
    
    await _executeWorkflow(workflow);
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isExecuting': _isExecuting,
      'totalWorkflows': _workflows.length,
      'enabledWorkflows': _workflows.values.where((w) => w.enabled).length,
      'totalTriggers': _triggers.length,
      'enabledTriggers': _triggers.values.where((t) => t.enabled).length,
      'totalTasks': _tasks.length,
      'executionHistory': _executionHistory.length,
      'successRate': _calculateSuccessRate(),
      'averageExecutionTime': _calculateAverageExecutionTime(),
    };
  }
  
  double _calculateSuccessRate() {
    if (_executionHistory.isEmpty) return 0.0;
    
    final successful = _executionHistory.where((e) => 
        e.status == ExecutionStatus.completed).length;
    return (successful / _executionHistory.length) * 100.0;
  }
  
  double _calculateAverageExecutionTime() {
    if (_executionHistory.isEmpty) return 0.0;
    
    final completed = _executionHistory.where((e) => 
        e.status == ExecutionStatus.completed && e.completedAt != null);
    
    if (completed.isEmpty) return 0.0;
    
    final totalTime = completed.fold(0.0, (sum, e) => 
        sum + e.completedAt!.difference(e.startedAt).inSeconds.toDouble());
    
    return totalTime / completed.length;
  }
  
  Future<void> dispose() async {
    _triggerCheckTimer?.cancel();
    _scheduleTimer?.cancel();
    _cleanupTimer?.cancel();
    
    await _saveAutomationData();
    
    _eventController.close();
    debugPrint('⚙️ Intelligent Task Automation disposed');
  }
}

// Data models
class Workflow {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final List<String> triggers;
  final List<String> tasks;
  final List<String> conditions;
  final DateTime createdAt;
  final DateTime? lastExecuted;
  final int executionCount;
  
  Workflow({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.triggers,
    required this.tasks,
    required this.conditions,
    required this.createdAt,
    this.lastExecuted,
    this.executionCount = 0,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'triggers': triggers,
    'tasks': tasks,
    'conditions': conditions,
    'createdAt': createdAt.toIso8601String(),
    'lastExecuted': lastExecuted?.toIso8601String(),
    'executionCount': executionCount,
  };
  
  factory Workflow.fromJson(Map<String, dynamic> json) => Workflow(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    enabled: json['enabled'] ?? true,
    triggers: (json['triggers'] as List<dynamic>?)?.cast<String>() ?? [],
    tasks: (json['tasks'] as List<dynamic>?)?.cast<String>() ?? [],
    conditions: (json['conditions'] as List<dynamic>?)?.cast<String>() ?? [],
    createdAt: DateTime.parse(json['createdAt']),
    lastExecuted: json['lastExecuted'] != null ? DateTime.parse(json['lastExecuted']) : null,
    executionCount: json['executionCount'] ?? 0,
  );
}

class Trigger {
  final String id;
  final String name;
  final TriggerType type;
  final bool enabled;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  final DateTime? lastTriggered;
  final int triggerCount;
  
  Trigger({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.config,
    required this.createdAt,
    this.lastTriggered,
    this.triggerCount = 0,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'enabled': enabled,
    'config': config,
    'createdAt': createdAt.toIso8601String(),
    'lastTriggered': lastTriggered?.toIso8601String(),
    'triggerCount': triggerCount,
  };
  
  factory Trigger.fromJson(Map<String, dynamic> json) => Trigger(
    id: json['id'],
    name: json['name'],
    type: TriggerType.values.firstWhere((t) => t.name == json['type'], orElse: () => TriggerType.time_based),
    enabled: json['enabled'] ?? true,
    config: json['config'] ?? {},
    createdAt: DateTime.parse(json['createdAt']),
    lastTriggered: json['lastTriggered'] != null ? DateTime.parse(json['lastTriggered']) : null,
    triggerCount: json['triggerCount'] ?? 0,
  );
}

class Task {
  final String id;
  final String name;
  final String description;
  final TaskType type;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  
  Task({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.config,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'config': config,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    type: TaskType.values.firstWhere((t) => t.name == json['type'], orElse: () => TaskType.command),
    config: json['config'] ?? {},
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class WorkflowExecution {
  final String id;
  final String workflowId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExecutionStatus status;
  final List<TaskExecution> tasks;
  
  WorkflowExecution({
    required this.id,
    required this.workflowId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.tasks,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'workflowId': workflowId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'status': status.name,
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };
  
  factory WorkflowExecution.fromJson(Map<String, dynamic> json) => WorkflowExecution(
    id: json['id'],
    workflowId: json['workflowId'],
    startedAt: DateTime.parse(json['startedAt']),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    status: ExecutionStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => ExecutionStatus.pending),
    tasks: (json['tasks'] as List<dynamic>?)?.map((t) => TaskExecution.fromJson(t)).toList() ?? [],
  );
}

class TaskExecution {
  final String taskId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExecutionStatus status;
  final String? error;
  
  TaskExecution({
    required this.taskId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.error,
  });
  
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'status': status.name,
    'error': error,
  };
}

class AutomationMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final AutomationCategory category;
  
  AutomationMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
    required this.category,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'unit': unit,
    'category': category.name,
  };
  
  factory AutomationMetric.fromJson(Map<String, dynamic> json) => AutomationMetric(
    name: json['name'],
    value: json['value']?.toDouble() ?? 0.0,
    timestamp: DateTime.parse(json['timestamp']),
    unit: json['unit'] ?? '',
    category: AutomationCategory.values.firstWhere((c) => c.name == json['category'], orElse: () => AutomationCategory.performance),
  );
}

enum TriggerType {
  time_based,
  event_based,
  system_based,
  file_based,
  manual,
}

enum TaskType {
  command,
  script,
  file_operation,
  system_operation,
  notification,
  api_call,
}

enum ExecutionStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

enum AutomationCategory {
  performance,
  usage,
  errors,
  success,
}

enum AutomationEventType {
  initialized,
  workflow_created,
  workflow_started,
  workflow_completed,
  trigger_created,
  trigger_fired,
  task_created,
  task_started,
  task_completed,
  error,
}

class AutomationEvent {
  final AutomationEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  AutomationEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
