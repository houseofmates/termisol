import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class TaskRunner {
  static const String _tasksFile = '/home/house/.termisol_tasks.json';
  static const int _maxConcurrentTasks = 10;
  static const int _maxTaskHistory = 1000;
  static const int _maxScheduledTasks = 100;
  
  final Map<String, Task> _tasks = {};
  final Map<String, TaskExecution> _executions = {};
  final Map<String, ScheduledTask> _scheduledTasks = {};
  final Queue<TaskExecution> _executionQueue = Queue();
  final Map<String, TaskTemplate> _templates = {};
  
  Timer? _schedulerTimer;
  Timer? _cleanupTimer;
  int _totalTasks = 0;
  int _totalExecutions = 0;
  int _successfulExecutions = 0;
  
  final StreamController<TaskEvent> _taskController = 
      StreamController<TaskEvent>.broadcast();

  void initialize() {
    _loadTasks();
    _loadScheduledTasks();
    _loadTemplates();
    _startTimers();
    developer.log('🏃 Task Runner initialized');
  }

  void _loadTasks() {
    try {
      final file = File(_tasksFile);
      if (!file.existsSync()) {
        developer.log('🏃 No existing tasks file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load tasks
      for (final entry in data['tasks']) {
        final task = Task.fromJson(entry);
        _tasks[task.id] = task;
        _totalTasks++;
      }
      
      // Load executions
      for (final entry in data['executions']) {
        final execution = TaskExecution.fromJson(entry);
        _executions[execution.id] = execution;
        _totalExecutions++;
        
        if (execution.status == ExecutionStatus.completed) {
          _successfulExecutions++;
        }
      }
      
      developer.log('🏃 Loaded ${_tasks.length} tasks, ${_executions.length} executions');
      
    } catch (e) {
      developer.log('🏃 Failed to load tasks: $e');
    }
  }

  void _loadScheduledTasks() {
    try {
      final scheduledFile = File('${_tasksFile}.scheduled');
      if (!scheduledFile.existsSync()) return;
      
      final content = scheduledFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['scheduled_tasks']) {
        final scheduledTask = ScheduledTask.fromJson(entry);
        _scheduledTasks[scheduledTask.id] = scheduledTask;
      }
      
      developer.log('🏃 Loaded ${_scheduledTasks.length} scheduled tasks');
      
    } catch (e) {
      developer.log('🏃 Failed to load scheduled tasks: $e');
    }
  }

  void _loadTemplates() {
    try {
      final templatesFile = File('${_tasksFile}.templates');
      if (!templatesFile.existsSync()) {
        _createDefaultTemplates();
        return;
      }
      
      final content = templatesFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['templates']) {
        final template = TaskTemplate.fromJson(entry);
        _templates[template.id] = template;
      }
      
      developer.log('🏃 Loaded ${_templates.length} task templates');
      
    } catch (e) {
      developer.log('🏃 Failed to load task templates: $e');
      _createDefaultTemplates();
    }
  }

  void _createDefaultTemplates() {
    // Development templates
    _templates['flutter_build'] = TaskTemplate(
      id: 'flutter_build',
      name: 'Flutter Build',
      description: 'Build Flutter application',
      command: 'flutter build',
      category: TaskCategory.development,
      parameters: [
        TaskParameter(
          name: 'target',
          type: ParameterType.select,
          defaultValue: 'apk',
          options: ['apk', 'ios', 'web', 'linux', 'windows', 'macos'],
          description: 'Build target platform',
        ),
        TaskParameter(
          name: 'release',
          type: ParameterType.boolean,
          defaultValue: false,
          description: 'Build in release mode',
        ),
      ],
      icon: '🦋',
      createdAt: DateTime.now(),
    );
    
    _templates['npm_install'] = TaskTemplate(
      id: 'npm_install',
      name: 'NPM Install',
      description: 'Install NPM dependencies',
      command: 'npm install',
      category: TaskCategory.development,
      parameters: [
        TaskParameter(
          name: 'package',
          type: ParameterType.string,
          description: 'Package to install (empty for all)',
        ),
        TaskParameter(
          name: 'dev',
          type: ParameterType.boolean,
          defaultValue: false,
          description: 'Install as dev dependency',
        ),
      ],
      icon: '📦',
      createdAt: DateTime.now(),
    );
    
    _templates['git_pull'] = TaskTemplate(
      id: 'git_pull',
      name: 'Git Pull',
      description: 'Pull latest changes from remote',
      command: 'git pull',
      category: TaskCategory.git,
      parameters: [
        TaskParameter(
          name: 'branch',
          type: ParameterType.string,
          defaultValue: 'main',
          description: 'Branch to pull from',
        ),
        TaskParameter(
          name: 'remote',
          type: ParameterType.string,
          defaultValue: 'origin',
          description: 'Remote repository',
        ),
      ],
      icon: '🔀',
      createdAt: DateTime.now(),
    );
    
    // System templates
    _templates['system_update'] = TaskTemplate(
      id: 'system_update',
      name: 'System Update',
      description: 'Update system packages',
      command: 'sudo apt update && sudo apt upgrade -y',
      category: TaskCategory.system,
      parameters: [
        TaskParameter(
          name: 'auto_confirm',
          type: ParameterType.boolean,
          defaultValue: true,
          description: 'Automatically confirm updates',
        ),
      ],
      icon: '🔄',
      createdAt: DateTime.now(),
    );
    
    _templates['backup_system'] = TaskTemplate(
      id: 'backup_system',
      name: 'System Backup',
      description: 'Create system backup',
      command: '/backup',
      category: TaskCategory.system,
      parameters: [
        TaskParameter(
          name: 'destination',
          type: ParameterType.string,
          description: 'Backup destination path',
        ),
        TaskParameter(
          name: 'compress',
          type: ParameterType.boolean,
          defaultValue: true,
          description: 'Compress backup',
        ),
      ],
      icon: '💾',
      createdAt: DateTime.now(),
    );
    
    // Utility templates
    _templates['find_large_files'] = TaskTemplate(
      id: 'find_large_files',
      name: 'Find Large Files',
      description: 'Find files larger than specified size',
      command: 'find . -type f -size +{size} -exec ls -lh {} \\;',
      category: TaskCategory.utility,
      parameters: [
        TaskParameter(
          name: 'size',
          type: ParameterType.string,
          defaultValue: '100M',
          description: 'Minimum file size (e.g., 100M, 1G)',
        ),
        TaskParameter(
          name: 'directory',
          type: ParameterType.string,
          defaultValue: '.',
          description: 'Directory to search',
        ),
      ],
      icon: '🔍',
      createdAt: DateTime.now(),
    );
    
    _saveTemplates();
    developer.log('🏃 Created default task templates');
  }

  void _startTimers() {
    _schedulerTimer = Timer.periodic(
      Duration(minutes: 1),
      (_) => _checkScheduledTasks(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(hours: 1),
      (_) => _cleanupOldExecutions(),
    );
  }

  void _checkScheduledTasks() {
    final now = DateTime.now();
    
    for (final scheduledTask in _scheduledTasks.values) {
      if (!scheduledTask.enabled) continue;
      
      if (now.isAfter(scheduledTask.nextRun)) {
        _executeScheduledTask(scheduledTask);
      }
    }
  }

  Future<void> _executeScheduledTask(ScheduledTask scheduledTask) async {
    try {
      developer.log('🏃 Executing scheduled task: ${scheduledTask.name}');
      
      // Create task execution
      final executionId = await executeTask(
        taskId: scheduledTask.taskId,
        parameters: scheduledTask.parameters,
        priority: scheduledTask.priority,
        scheduledTaskId: scheduledTask.id,
      );
      
      // Update schedule
      scheduledTask.lastRun = DateTime.now();
      scheduledTask.nextRun = _calculateNextRun(scheduledTask);
      scheduledTask.runCount++;
      
      _saveScheduledTasks();
      
      _emitEvent(TaskEvent(
        type: TaskEventType.scheduledTaskExecuted,
        taskId: scheduledTask.taskId,
        scheduledTaskId: scheduledTask.id,
        executionId: executionId,
      ));
      
    } catch (e) {
      developer.log('🏃 Failed to execute scheduled task: ${scheduledTask.name} - $e');
      
      _emitEvent(TaskEvent(
        type: TaskEventType.scheduledTaskFailed,
        taskId: scheduledTask.taskId,
        scheduledTaskId: scheduledTask.id,
        error: e.toString(),
      ));
    }
  }

  DateTime _calculateNextRun(ScheduledTask scheduledTask) {
    final now = DateTime.now();
    
    switch (scheduledTask.frequency) {
      case TaskFrequency.minutely:
        return now.add(Duration(minutes: scheduledTask.interval));
      case TaskFrequency.hourly:
        return now.add(Duration(hours: scheduledTask.interval));
      case TaskFrequency.daily:
        return now.add(Duration(days: scheduledTask.interval));
      case TaskFrequency.weekly:
        return now.add(Duration(days: 7 * scheduledTask.interval));
      case TaskFrequency.monthly:
        return now.add(Duration(days: 30 * scheduledTask.interval));
      case TaskFrequency.cron:
        // Simple cron implementation
        return _parseCronExpression(scheduledTask.cronExpression!, now);
    }
  }

  DateTime _parseCronExpression(String cronExpression, DateTime now) {
    // Very simple cron parser - in practice would use a proper cron library
    final parts = cronExpression.split(' ');
    if (parts.length != 5) {
      return now.add(Duration(hours: 1)); // Default to 1 hour
    }
    
    // Parse minute
    final minute = parts[0];
    if (minute == '*') {
      return now.add(Duration(minutes: 1));
    } else {
      final minuteValue = int.tryParse(minute);
      if (minuteValue != null) {
        final nextRun = DateTime(now.year, now.month, now.day, now.hour, minuteValue);
        if (nextRun.isBefore(now)) {
          return nextRun.add(Duration(hours: 1));
        }
        return nextRun;
      }
    }
    
    return now.add(Duration(hours: 1));
  }

  Future<String> createTask({
    required String name,
    required String command,
    TaskCategory? category,
    String? description,
    Map<String, dynamic>? parameters,
    String? workingDirectory,
    TaskPriority? priority,
    int? timeout,
    bool? retryOnFailure,
    int? maxRetries,
    List<String>? dependencies,
    String? icon,
  }) async {
    final taskId = _generateTaskId();
    
    final task = Task(
      id: taskId,
      name: name,
      command: command,
      category: category ?? TaskCategory.custom,
      description: description ?? '',
      parameters: parameters ?? {},
      workingDirectory: workingDirectory ?? Directory.current.path,
      priority: priority ?? TaskPriority.normal,
      timeout: timeout ?? 300, // 5 minutes
      retryOnFailure: retryOnFailure ?? false,
      maxRetries: maxRetries ?? 3,
      dependencies: dependencies ?? [],
      icon: icon ?? '📋',
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      enabled: true,
    );
    
    _tasks[taskId] = task;
    _totalTasks++;
    
    developer.log('🏃 Created task: $name');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskCreated,
      taskId: taskId,
      taskName: name,
    ));
    
    await _saveTasks();
    
    return taskId;
  }

  Future<String> executeTask({
    required String taskId,
    Map<String, dynamic>? parameters,
    TaskPriority? priority,
    String? scheduledTaskId,
  }) async {
    final task = _tasks[taskId];
    if (task == null) {
      throw Exception('Task not found: $taskId');
    }
    
    if (!task.enabled) {
      throw Exception('Task is disabled: $taskId');
    }
    
    // Check dependencies
    if (task.dependencies.isNotEmpty) {
      await _checkDependencies(task.dependencies);
    }
    
    final executionId = _generateExecutionId();
    
    final execution = TaskExecution(
      id: executionId,
      taskId: taskId,
      scheduledTaskId: scheduledTaskId,
      parameters: parameters ?? {},
      status: ExecutionStatus.queued,
      startTime: null,
      endTime: null,
      exitCode: null,
      output: '',
      error: '',
      priority: priority ?? task.priority,
      retryCount: 0,
      createdAt: DateTime.now(),
    );
    
    _executions[executionId] = execution;
    _totalExecutions++;
    
    // Add to queue
    _executionQueue.add(execution);
    
    developer.log('🏃 Queued task execution: $taskId');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskQueued,
      taskId: taskId,
      executionId: executionId,
    ));
    
    // Process queue
    _processExecutionQueue();
    
    await _saveTasks();
    
    return executionId;
  }

  Future<void> _checkDependencies(List<String> dependencies) async {
    for (final dependencyId in dependencies) {
      final dependency = _tasks[dependencyId];
      if (dependency == null) {
        throw Exception('Dependency task not found: $dependencyId');
      }
      
      // Check if dependency has successful execution
      final successfulExecutions = _executions.values
          .where((exec) => exec.taskId == dependencyId && exec.status == ExecutionStatus.completed)
          .toList();
      
      if (successfulExecutions.isEmpty) {
        throw Exception('Dependency task not completed: $dependencyId');
      }
    }
  }

  void _processExecutionQueue() {
    final runningExecutions = _executions.values
        .where((exec) => exec.status == ExecutionStatus.running)
        .length;
    
    while (_executionQueue.isNotEmpty && runningExecutions < _maxConcurrentTasks) {
      final execution = _executionQueue.removeFirst();
      _executeTaskInternal(execution);
    }
  }

  Future<void> _executeTaskInternal(TaskExecution execution) async {
    final task = _tasks[execution.taskId]!;
    
    try {
      execution.status = ExecutionStatus.running;
      execution.startTime = DateTime.now();
      
      developer.log('🏃 Starting task execution: ${task.name}');
      
      _emitEvent(TaskEvent(
        type: TaskEventType.taskStarted,
        taskId: execution.taskId,
        executionId: execution.id,
      ));
      
      // Prepare command with parameters
      final command = _prepareCommand(task.command, execution.parameters);
      
      // Execute command
      final process = await Process.start(
        'bash',
        ['-c', command],
        workingDirectory: task.workingDirectory,
      );
      
      // Capture output
      final outputBuffer = StringBuffer();
      final errorBuffer = StringBuffer();
      
      process.stdout.transform(utf8.decoder).listen((output) {
        outputBuffer.write(output);
        execution.output = outputBuffer.toString();
      });
      
      process.stderr.transform(utf8.decoder).listen((error) {
        errorBuffer.write(error);
        execution.error = errorBuffer.toString();
      });
      
      // Wait for completion with timeout
      final timeout = Duration(seconds: task.timeout);
      
      try {
        final exitCode = await process.exitCode.timeout(timeout);
        execution.exitCode = exitCode;
        
        if (exitCode == 0) {
          execution.status = ExecutionStatus.completed;
          _successfulExecutions++;
          
          developer.log('🏃 Task completed successfully: ${task.name}');
          
          _emitEvent(TaskEvent(
            type: TaskEventType.taskCompleted,
            taskId: execution.taskId,
            executionId: execution.id,
            exitCode: exitCode,
          ));
        } else {
          execution.status = ExecutionStatus.failed;
          
          developer.log('🏃 Task failed: ${task.name} (exit code: $exitCode)');
          
          _emitEvent(TaskEvent(
            type: TaskEventType.taskFailed,
            taskId: execution.taskId,
            executionId: execution.id,
            exitCode: exitCode,
            error: execution.error,
          ));
          
          // Retry logic
          if (task.retryOnFailure && execution.retryCount < task.maxRetries) {
            await _retryExecution(execution);
          }
        }
      } catch (e) {
        execution.status = ExecutionStatus.timeout;
        execution.error = 'Task timeout: $e';
        
        developer.log('🏃 Task timeout: ${task.name}');
        
        _emitEvent(TaskEvent(
          type: TaskEventType.taskTimeout,
          taskId: execution.taskId,
          executionId: execution.id,
        ));
        
        // Retry logic
        if (task.retryOnFailure && execution.retryCount < task.maxRetries) {
          await _retryExecution(execution);
        }
      }
      
      execution.endTime = DateTime.now();
      
    } catch (e) {
      execution.status = ExecutionStatus.error;
      execution.error = 'Execution error: $e';
      execution.endTime = DateTime.now();
      
      developer.log('🏃 Task execution error: ${task.name} - $e');
      
      _emitEvent(TaskEvent(
        type: TaskEventType.taskError,
        taskId: execution.taskId,
        executionId: execution.id,
        error: e.toString(),
      ));
    }
    
    await _saveTasks();
    
    // Process next in queue
    _processExecutionQueue();
  }

  String _prepareCommand(String command, Map<String, dynamic> parameters) {
    String preparedCommand = command;
    
    // Replace parameter placeholders
    for (final entry in parameters.entries) {
      final placeholder = '{${entry.key}}';
      preparedCommand = preparedCommand.replaceAll(placeholder, entry.value.toString());
    }
    
    return preparedCommand;
  }

  Future<void> _retryExecution(TaskExecution execution) async {
    final task = _tasks[execution.taskId]!;
    
    if (execution.retryCount >= task.maxRetries) {
      return;
    }
    
    execution.retryCount++;
    execution.status = ExecutionStatus.retrying;
    
    developer.log('🏃 Retrying task execution: ${task.name} (attempt ${execution.retryCount})');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskRetrying,
      taskId: execution.taskId,
      executionId: execution.id,
      retryCount: execution.retryCount,
    ));
    
    // Wait before retry
    await Future.delayed(Duration(seconds: 5 * execution.retryCount));
    
    // Reset execution state and re-queue
    execution.status = ExecutionStatus.queued;
    execution.startTime = null;
    execution.endTime = null;
    execution.exitCode = null;
    execution.output = '';
    execution.error = '';
    
    _executionQueue.add(execution);
    _processExecutionQueue();
  }

  Future<void> stopExecution(String executionId) async {
    final execution = _executions[executionId];
    if (execution == null) {
      throw Exception('Execution not found: $executionId');
    }
    
    if (execution.status != ExecutionStatus.running) {
      throw Exception('Execution is not running: $executionId');
    }
    
    execution.status = ExecutionStatus.cancelled;
    execution.endTime = DateTime.now();
    
    developer.log('🏃 Stopped task execution: $executionId');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskCancelled,
      taskId: execution.taskId,
      executionId: executionId,
    ));
    
    await _saveTasks();
    
    // Process next in queue
    _processExecutionQueue();
  }

  Future<String> scheduleTask({
    required String taskId,
    required TaskFrequency frequency,
    int? interval,
    String? cronExpression,
    DateTime? nextRun,
    Map<String, dynamic>? parameters,
    TaskPriority? priority,
    bool? enabled,
  }) async {
    final scheduledTaskId = _generateScheduledTaskId();
    
    final scheduledTask = ScheduledTask(
      id: scheduledTaskId,
      taskId: taskId,
      frequency: frequency,
      interval: interval ?? 1,
      cronExpression: cronExpression,
      nextRun: nextRun ?? _calculateNextRun(ScheduledTask(
        id: '',
        taskId: taskId,
        frequency: frequency,
        interval: interval ?? 1,
        cronExpression: cronExpression,
        nextRun: DateTime.now(),
        lastRun: null,
        runCount: 0,
        parameters: parameters ?? {},
        priority: priority ?? TaskPriority.normal,
        enabled: enabled ?? true,
        createdAt: DateTime.now(),
      )),
      lastRun: null,
      runCount: 0,
      parameters: parameters ?? {},
      priority: priority ?? TaskPriority.normal,
      enabled: enabled ?? true,
      createdAt: DateTime.now(),
    );
    
    _scheduledTasks[scheduledTaskId] = scheduledTask;
    
    developer.log('🏃 Scheduled task: $taskId (${frequency.name})');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskScheduled,
      taskId: taskId,
      scheduledTaskId: scheduledTaskId,
      frequency: frequency,
    ));
    
    await _saveScheduledTasks();
    
    return scheduledTaskId;
  }

  Future<String> createTaskFromTemplate({
    required String templateId,
    required String name,
    Map<String, dynamic>? parameters,
    String? description,
  }) async {
    final template = _templates[templateId];
    if (template == null) {
      throw Exception('Task template not found: $templateId');
    }
    
    final taskId = await createTask(
      name: name,
      command: template.command,
      category: template.category,
      description: description ?? template.description,
      parameters: parameters ?? {},
      icon: template.icon,
    );
    
    developer.log('🏃 Created task from template: $name');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskCreatedFromTemplate,
      taskId: taskId,
      templateId: templateId,
    ));
    
    return taskId;
  }

  Future<void> _cleanupOldExecutions() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    final executionsToRemove = <String>[];
    
    for (final entry in _executions.entries) {
      final execution = entry.value;
      
      if (execution.createdAt.isBefore(cutoffDate)) {
        executionsToRemove.add(entry.key);
      }
    }
    
    for (final executionId in executionsToRemove) {
      _executions.remove(executionId);
    }
    
    if (executionsToRemove.isNotEmpty) {
      developer.log('🏃 Cleaned up ${executionsToRemove.length} old executions');
      
      _emitEvent(TaskEvent(
        type: TaskEventType.executionsCleaned,
        executionIds: executionsToRemove,
      ));
      
      await _saveTasks();
    }
  }

  Future<void> _saveTasks() async {
    try {
      final file = File(_tasksFile);
      
      final tasksData = _tasks.values.map((task) => task.toJson()).toList();
      final executionsData = _executions.values.map((exec) => exec.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'tasks': tasksData,
        'executions': executionsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏃 Failed to save tasks: $e');
    }
  }

  Future<void> _saveScheduledTasks() async {
    try {
      final file = File('${_tasksFile}.scheduled');
      
      final scheduledData = _scheduledTasks.values.map((task) => task.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'scheduled_tasks': scheduledData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏃 Failed to save scheduled tasks: $e');
    }
  }

  Future<void> _saveTemplates() async {
    try {
      final file = File('${_tasksFile}.templates');
      
      final templatesData = _templates.values.map((template) => template.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'templates': templatesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏃 Failed to save task templates: $e');
    }
  }

  Task? getTask(String taskId) {
    return _tasks[taskId];
  }

  List<Task> getTasks({TaskCategory? category}) {
    final tasks = _tasks.values.toList();
    
    if (category != null) {
      return tasks.where((task) => task.category == category).toList();
    }
    
    return tasks;
  }

  TaskExecution? getExecution(String executionId) {
    return _executions[executionId];
  }

  List<TaskExecution> getExecutions({String? taskId, ExecutionStatus? status}) {
    final executions = _executions.values.toList();
    
    if (taskId != null) {
      return executions.where((exec) => exec.taskId == taskId).toList();
    }
    
    if (status != null) {
      return executions.where((exec) => exec.status == status).toList();
    }
    
    return executions;
  }

  ScheduledTask? getScheduledTask(String scheduledTaskId) {
    return _scheduledTasks[scheduledTaskId];
  }

  List<ScheduledTask> getScheduledTasks({bool? enabled}) {
    final tasks = _scheduledTasks.values.toList();
    
    if (enabled != null) {
      return tasks.where((task) => task.enabled == enabled).toList();
    }
    
    return tasks;
  }

  TaskTemplate? getTemplate(String templateId) {
    return _templates[templateId];
  }

  List<TaskTemplate> getTemplates({TaskCategory? category}) {
    final templates = _templates.values.toList();
    
    if (category != null) {
      return templates.where((template) => template.category == category).toList();
    }
    
    return templates;
  }

  Future<void> updateTask(String taskId, {
    String? name,
    String? command,
    TaskCategory? category,
    String? description,
    Map<String, dynamic>? parameters,
    String? workingDirectory,
    TaskPriority? priority,
    int? timeout,
    bool? retryOnFailure,
    int? maxRetries,
    List<String>? dependencies,
    String? icon,
    bool? enabled,
  }) async {
    final task = _tasks[taskId];
    if (task == null) {
      throw Exception('Task not found: $taskId');
    }
    
    if (name != null) task.name = name!;
    if (command != null) task.command = command!;
    if (category != null) task.category = category!;
    if (description != null) task.description = description!;
    if (parameters != null) task.parameters.addAll(parameters!);
    if (workingDirectory != null) task.workingDirectory = workingDirectory!;
    if (priority != null) task.priority = priority!;
    if (timeout != null) task.timeout = timeout!;
    if (retryOnFailure != null) task.retryOnFailure = retryOnFailure!;
    if (maxRetries != null) task.maxRetries = maxRetries!;
    if (dependencies != null) task.dependencies = dependencies!;
    if (icon != null) task.icon = icon!;
    if (enabled != null) task.enabled = enabled!;
    
    task.lastModified = DateTime.now();
    
    developer.log('🏃 Updated task: $taskId');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskUpdated,
      taskId: taskId,
    ));
    
    await _saveTasks();
  }

  Future<void> deleteTask(String taskId) async {
    final task = _tasks.remove(taskId);
    if (task == null) {
      throw Exception('Task not found: $taskId');
    }
    
    // Remove associated executions
    _executions.removeWhere((key, value) => value.taskId == taskId);
    
    // Remove scheduled tasks
    _scheduledTasks.removeWhere((key, value) => value.taskId == taskId);
    
    _totalTasks--;
    
    developer.log('🏃 Deleted task: $taskId');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.taskDeleted,
      taskId: taskId,
    ));
    
    await _saveTasks();
    await _saveScheduledTasks();
  }

  Future<void> deleteScheduledTask(String scheduledTaskId) async {
    final scheduledTask = _scheduledTasks.remove(scheduledTaskId);
    if (scheduledTask == null) {
      throw Exception('Scheduled task not found: $scheduledTaskId');
    }
    
    developer.log('🏃 Deleted scheduled task: $scheduledTaskId');
    
    _emitEvent(TaskEvent(
      type: TaskEventType.scheduledTaskDeleted,
      scheduledTaskId: scheduledTaskId,
    ));
    
    await _saveScheduledTasks();
  }

  String _generateTaskId() {
    return 'task_${DateTime.now().millisecondsSinceEpoch}_$_totalTasks';
  }

  String _generateExecutionId() {
    return 'exec_${DateTime.now().millisecondsSinceEpoch}_$_totalExecutions';
  }

  String _generateScheduledTaskId() {
    return 'sched_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(TaskEvent event) {
    _taskController.add(event);
  }

  Stream<TaskEvent> get taskEventStream => _taskController.stream;

  TaskRunnerStats getStats() {
    return TaskRunnerStats(
      totalTasks: _totalTasks,
      totalExecutions: _totalExecutions,
      successfulExecutions: _successfulExecutions,
      runningExecutions: _executions.values
          .where((exec) => exec.status == ExecutionStatus.running)
          .length,
      queuedExecutions: _executionQueue.length,
      scheduledTasks: _scheduledTasks.length,
      enabledScheduledTasks: _scheduledTasks.values
          .where((task) => task.enabled)
          .length,
      successRate: _totalExecutions > 0 
          ? _successfulExecutions / _totalExecutions 
          : 0.0,
    );
  }

  void dispose() {
    _schedulerTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _tasks.clear();
    _executions.clear();
    _scheduledTasks.clear();
    _executionQueue.clear();
    _templates.clear();
    _taskController.close();
    
    developer.log('🏃 Task Runner disposed');
  }
}

class Task {
  final String id;
  String name;
  final String command;
  final TaskCategory category;
  final String description;
  final Map<String, dynamic> parameters;
  final String workingDirectory;
  final TaskPriority priority;
  final int timeout;
  final bool retryOnFailure;
  final int maxRetries;
  final List<String> dependencies;
  final String icon;
  final DateTime createdAt;
  DateTime lastModified;
  bool enabled;

  Task({
    required this.id,
    required this.name,
    required this.command,
    required this.category,
    required this.description,
    required this.parameters,
    required this.workingDirectory,
    required this.priority,
    required this.timeout,
    required this.retryOnFailure,
    required this.maxRetries,
    required this.dependencies,
    required this.icon,
    required this.createdAt,
    required this.lastModified,
    required this.enabled,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'category': category.name,
      'description': description,
      'parameters': parameters,
      'working_directory': workingDirectory,
      'priority': priority.name,
      'timeout': timeout,
      'retry_on_failure': retryOnFailure,
      'max_retries': maxRetries,
      'dependencies': dependencies,
      'icon': icon,
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
      'enabled': enabled,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      name: json['name'],
      command: json['command'],
      category: TaskCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => TaskCategory.custom,
      ),
      description: json['description'],
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      workingDirectory: json['working_directory'],
      priority: TaskPriority.values.firstWhere(
        (priority) => priority.name == json['priority'],
        orElse: () => TaskPriority.normal,
      ),
      timeout: json['timeout'] ?? 300,
      retryOnFailure: json['retry_on_failure'] ?? false,
      maxRetries: json['max_retries'] ?? 3,
      dependencies: List<String>.from(json['dependencies'] ?? []),
      icon: json['icon'] ?? '📋',
      createdAt: DateTime.parse(json['created_at']),
      lastModified: DateTime.parse(json['last_modified']),
      enabled: json['enabled'] ?? true,
    );
  }
}

class TaskExecution {
  final String id;
  final String taskId;
  final String? scheduledTaskId;
  final Map<String, dynamic> parameters;
  ExecutionStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? exitCode;
  String output;
  String error;
  final TaskPriority priority;
  int retryCount;
  final DateTime createdAt;

  TaskExecution({
    required this.id,
    required this.taskId,
    this.scheduledTaskId,
    required this.parameters,
    required this.status,
    this.startTime,
    this.endTime,
    this.exitCode,
    required this.output,
    required this.error,
    required this.priority,
    required this.retryCount,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'scheduled_task_id': scheduledTaskId,
      'parameters': parameters,
      'status': status.name,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'exit_code': exitCode,
      'output': output,
      'error': error,
      'priority': priority.name,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory TaskExecution.fromJson(Map<String, dynamic> json) {
    return TaskExecution(
      id: json['id'],
      taskId: json['task_id'],
      scheduledTaskId: json['scheduled_task_id'],
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      status: ExecutionStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => ExecutionStatus.queued,
      ),
      startTime: json['start_time'] != null ? DateTime.parse(json['start_time']) : null,
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      exitCode: json['exit_code'],
      output: json['output'] ?? '',
      error: json['error'] ?? '',
      priority: TaskPriority.values.firstWhere(
        (priority) => priority.name == json['priority'],
        orElse: () => TaskPriority.normal,
      ),
      retryCount: json['retry_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class ScheduledTask {
  final String id;
  final String taskId;
  final TaskFrequency frequency;
  final int interval;
  final String? cronExpression;
  DateTime nextRun;
  DateTime? lastRun;
  int runCount;
  final Map<String, dynamic> parameters;
  final TaskPriority priority;
  bool enabled;
  final DateTime createdAt;

  ScheduledTask({
    required this.id,
    required this.taskId,
    required this.frequency,
    required this.interval,
    this.cronExpression,
    required this.nextRun,
    this.lastRun,
    required this.runCount,
    required this.parameters,
    required this.priority,
    required this.enabled,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'frequency': frequency.name,
      'interval': interval,
      'cron_expression': cronExpression,
      'next_run': nextRun.toIso8601String(),
      'last_run': lastRun?.toIso8601String(),
      'run_count': runCount,
      'parameters': parameters,
      'priority': priority.name,
      'enabled': enabled,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    return ScheduledTask(
      id: json['id'],
      taskId: json['task_id'],
      frequency: TaskFrequency.values.firstWhere(
        (frequency) => frequency.name == json['frequency'],
        orElse: () => TaskFrequency.daily,
      ),
      interval: json['interval'] ?? 1,
      cronExpression: json['cron_expression'],
      nextRun: DateTime.parse(json['next_run']),
      lastRun: json['last_run'] != null ? DateTime.parse(json['last_run']) : null,
      runCount: json['run_count'] ?? 0,
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      priority: TaskPriority.values.firstWhere(
        (priority) => priority.name == json['priority'],
        orElse: () => TaskPriority.normal,
      ),
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class TaskTemplate {
  final String id;
  final String name;
  final String description;
  final String command;
  final TaskCategory category;
  final List<TaskParameter> parameters;
  final String icon;
  final DateTime createdAt;

  TaskTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    required this.category,
    required this.parameters,
    required this.icon,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'command': command,
      'category': category.name,
      'parameters': parameters.map((param) => param.toJson()).toList(),
      'icon': icon,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory TaskTemplate.fromJson(Map<String, dynamic> json) {
    return TaskTemplate(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      command: json['command'],
      category: TaskCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => TaskCategory.custom,
      ),
      parameters: (json['parameters'] as List)
          .map((param) => TaskParameter.fromJson(param))
          .toList(),
      icon: json['icon'] ?? '📋',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class TaskParameter {
  final String name;
  final String description;
  final ParameterType type;
  final dynamic defaultValue;
  final List<String>? options;

  TaskParameter({
    required this.name,
    required this.description,
    required this.type,
    this.defaultValue,
    this.options,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'type': type.name,
      'default_value': defaultValue,
      'options': options,
    };
  }

  factory TaskParameter.fromJson(Map<String, dynamic> json) {
    return TaskParameter(
      name: json['name'],
      description: json['description'],
      type: ParameterType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ParameterType.string,
      ),
      defaultValue: json['default_value'],
      options: json['options'] != null ? List<String>.from(json['options']) : null,
    );
  }
}

enum TaskCategory {
  development,
  system,
  git,
  utility,
  custom,
}

enum TaskPriority {
  low,
  normal,
  high,
  urgent,
}

enum ExecutionStatus {
  queued,
  running,
  completed,
  failed,
  cancelled,
  timeout,
  retrying,
  error,
}

enum TaskFrequency {
  minutely,
  hourly,
  daily,
  weekly,
  monthly,
  cron,
}

enum ParameterType {
  string,
  number,
  boolean,
  select,
  multiselect,
}

enum TaskEventType {
  taskCreated,
  taskUpdated,
  taskDeleted,
  taskQueued,
  taskStarted,
  taskCompleted,
  taskFailed,
  taskCancelled,
  taskTimeout,
  taskError,
  taskRetrying,
  taskScheduled,
  scheduledTaskExecuted,
  scheduledTaskFailed,
  scheduledTaskDeleted,
  taskCreatedFromTemplate,
  executionsCleaned,
}

class TaskEvent {
  final TaskEventType type;
  final String? taskId;
  final String? executionId;
  final String? scheduledTaskId;
  final String? taskName;
  final String? templateId;
  final int? exitCode;
  final String? error;
  final TaskFrequency? frequency;
  final int? retryCount;
  final List<String>? executionIds;

  TaskEvent({
    required this.type,
    this.taskId,
    this.executionId,
    this.scheduledTaskId,
    this.taskName,
    this.templateId,
    this.exitCode,
    this.error,
    this.frequency,
    this.retryCount,
    this.executionIds,
  });
}

class TaskRunnerStats {
  final int totalTasks;
  final int totalExecutions;
  final int successfulExecutions;
  final int runningExecutions;
  final int queuedExecutions;
  final int scheduledTasks;
  final int enabledScheduledTasks;
  final double successRate;

  TaskRunnerStats({
    required this.totalTasks,
    required this.totalExecutions,
    required this.successfulExecutions,
    required this.runningExecutions,
    required this.queuedExecutions,
    required this.scheduledTasks,
    required this.enabledScheduledTasks,
    required this.successRate,
  });
}
