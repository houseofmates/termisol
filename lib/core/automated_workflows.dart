import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'smart_command_chaining.dart';
import 'conversational_ai.dart';

/// Automated Workflow System
///
/// Manages complex, multi-step automated processes with conditional logic,
/// error handling, and progress tracking.
class AutomatedWorkflowSystem {
  final SmartCommandChaining _commandChaining;
  final ConversationalAI _conversationalAI;

  final StreamController<WorkflowExecution> _executionController =
      StreamController<WorkflowExecution>.broadcast();

  Stream<WorkflowExecution> get executions => _executionController.stream;

  final Map<String, AutomatedWorkflow> _workflows = {};
  final Map<String, WorkflowExecution> _activeExecutions = {};
  final List<WorkflowTemplate> _templates = [];

  bool _isActive = false;
  bool get isActive => _isActive;

  AutomatedWorkflowSystem(this._commandChaining, this._conversationalAI);

  /// Initialize the automated workflow system
  Future<void> initialize() async {
    if (_isActive) return;

    await _commandChaining.initialize();
    await _conversationalAI.initialize();

    _initializeTemplates();

    _isActive = true;
    debugPrint('⚙️ Automated Workflow System initialized');
  }

  /// Initialize built-in workflow templates
  void _initializeTemplates() {
    _templates.addAll([
      // Development workflows
      WorkflowTemplate(
        id: 'git-feature-branch',
        name: 'Git Feature Branch Workflow',
        description: 'Complete workflow for feature development with Git',
        category: 'development',
        variables: ['feature_name'],
        steps: [
          WorkflowStep(
            id: 'checkout-main',
            name: 'Checkout Main Branch',
            command: 'git checkout main',
            description: 'Switch to main branch',
            type: StepType.command,
          ),
          WorkflowStep(
            id: 'pull-latest',
            name: 'Pull Latest Changes',
            command: 'git pull origin main',
            description: 'Get latest changes from remote',
            type: StepType.command,
          ),
          WorkflowStep(
            id: 'create-feature-branch',
            name: 'Create Feature Branch',
            command: 'git checkout -b feature/{feature_name}',
            description: 'Create and switch to feature branch',
            type: StepType.command,
            requiresInput: true,
            inputPrompt: 'Enter feature name:',
          ),
        ],
      ),

      WorkflowTemplate(
        id: 'fullstack-deploy',
        name: 'Full Stack Deployment',
        description: 'Deploy full-stack application with tests and build',
        category: 'deployment',
        variables: [],
        steps: [
          WorkflowStep(
            id: 'run-tests',
            name: 'Run Test Suite',
            command: 'npm test',
            description: 'Execute all tests',
            type: StepType.command,
            continueOnFailure: false,
          ),
          WorkflowStep(
            id: 'build-frontend',
            name: 'Build Frontend',
            command: 'npm run build',
            description: 'Build production frontend',
            type: StepType.command,
            dependsOn: ['run-tests'],
          ),
          WorkflowStep(
            id: 'build-backend',
            name: 'Build Backend',
            command: 'npm run build:server',
            description: 'Build production backend',
            type: StepType.command,
            dependsOn: ['run-tests'],
          ),
          WorkflowStep(
            id: 'docker-build',
            name: 'Build Docker Images',
            command: 'docker-compose build',
            description: 'Build all Docker services',
            type: StepType.command,
            dependsOn: ['build-frontend', 'build-backend'],
          ),
          WorkflowStep(
            id: 'deploy',
            name: 'Deploy to Production',
            command: 'docker-compose up -d',
            description: 'Deploy services to production',
            type: StepType.command,
            dependsOn: ['docker-build'],
          ),
        ],
      ),

      WorkflowTemplate(
        id: 'code-review',
        name: 'Automated Code Review',
        description: 'Run comprehensive code quality checks',
        category: 'quality',
        variables: [],
        steps: [
          WorkflowStep(
            id: 'lint-code',
            name: 'Lint Code',
            command: 'npm run lint',
            description: 'Check code style and errors',
            type: StepType.command,
          ),
          WorkflowStep(
            id: 'run-tests',
            name: 'Run Tests',
            command: 'npm test',
            description: 'Execute test suite',
            type: StepType.command,
          ),
          WorkflowStep(
            id: 'check-coverage',
            name: 'Check Test Coverage',
            command: 'npm run coverage',
            description: 'Verify test coverage meets requirements',
            type: StepType.command,
            dependsOn: ['run-tests'],
          ),
          WorkflowStep(
            id: 'security-scan',
            name: 'Security Scan',
            command: 'npm audit',
            description: 'Check for security vulnerabilities',
            type: StepType.command,
          ),
        ],
      ),

      WorkflowTemplate(
        id: 'database-migration', // Automated database migration workflow
        name: 'Database Migration Workflow',
        description: 'Safe database migration with backup and rollback capabilities',
        category: 'database',
        variables: [],
        steps: [
          WorkflowStep(
            id: 'backup-db',
            name: 'Backup Database',
            command: 'pg_dump mydb > backup_\$(date +%Y%m%d_%H%M%S).sql',
            description: 'Create database backup before migration',
            type: StepType.command,
          ),
          WorkflowStep(
            id: 'run-migrations',
            name: 'Run Migrations',
            command: 'npm run db:migrate',
            description: 'Execute database migrations',
            type: StepType.command,
            dependsOn: ['backup-db'],
            continueOnFailure: false,
          ),
          WorkflowStep(
            id: 'verify-migration',
            name: 'Verify Migration',
            command: 'npm run db:verify',
            description: 'Verify migration completed successfully',
            type: StepType.command,
            dependsOn: ['run-migrations'],
          ),
          WorkflowStep(
            id: 'run-post-migration-tests',
            name: 'Run Post-Migration Tests',
            command: 'npm run test:integration',
            description: 'Run integration tests after migration',
            type: StepType.command,
            dependsOn: ['verify-migration'],
          ),
        ],
      ),
    ]);
  }

  /// Create a new automated workflow
  Future<String> createWorkflow({
    required String name,
    required String description,
    required List<WorkflowStep> steps,
    String? category,
    List<String>? variables,
    Map<String, dynamic>? metadata,
  }) async {
    final workflowId = 'workflow_${DateTime.now().millisecondsSinceEpoch}';

    final workflow = AutomatedWorkflow(
      id: workflowId,
      name: name,
      description: description,
      steps: steps,
      category: category ?? 'custom',
      variables: variables ?? [],
      metadata: metadata ?? {},
      createdAt: DateTime.now(),
    );

    _workflows[workflowId] = workflow;

    debugPrint('📋 Created workflow: $name ($workflowId)');
    return workflowId;
  }

  /// Create workflow from template
  Future<String> createWorkflowFromTemplate(
    String templateId, {
    Map<String, String>? variableValues,
    String? customName,
  }) async {
    final template = _templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw Exception('Template not found: $templateId'),
    );

    // Create workflow steps with variable substitution
    final steps = template.steps.map((step) {
      var command = step.command;
      var description = step.description;

      if (variableValues != null) {
        for (final entry in variableValues.entries) {
          command = command.replaceAll('{${entry.key}}', entry.value);
          description = description.replaceAll('{${entry.key}}', entry.value);
        }
      }

      return WorkflowStep(
        id: step.id,
        name: step.name,
        command: command,
        description: description,
        type: step.type,
        dependsOn: step.dependsOn,
        continueOnFailure: step.continueOnFailure,
        requiresInput: step.requiresInput,
        inputPrompt: step.inputPrompt,
        timeout: step.timeout,
        retryCount: step.retryCount,
      );
    }).toList();

    final workflowName = customName ?? '${template.name} Instance';

    return createWorkflow(
      name: workflowName,
      description: template.description,
      steps: steps,
      category: template.category,
      variables: template.variables,
    );
  }

  /// Execute a workflow
  Future<WorkflowExecutionResult> executeWorkflow(
    String workflowId, {
    Map<String, dynamic>? inputs,
    bool dryRun = false,
  }) async {
    final workflow = _workflows[workflowId];
    if (workflow == null) {
      throw Exception('Workflow not found: $workflowId');
    }

    final executionId = 'exec_${DateTime.now().millisecondsSinceEpoch}';
    final execution = WorkflowExecution(
      id: executionId,
      workflow: workflow,
      startTime: DateTime.now(),
      status: ExecutionStatus.running,
      inputs: inputs ?? {},
      dryRun: dryRun,
    );

    _activeExecutions[executionId] = execution;
    _executionController.add(execution);

    try {
      // Validate workflow dependencies
      await _validateWorkflowDependencies(workflow);

      // Execute steps in order
      final results = <StepExecutionResult>[];
      final stepOrder = _calculateExecutionOrder(workflow.steps);

      for (final stepId in stepOrder) {
        final step = workflow.steps.firstWhere((s) => s.id == stepId);

        // Check dependencies
        if (step.dependsOn != null && step.dependsOn!.isNotEmpty) {
          final dependencyFailed = step.dependsOn!.any((depId) {
            final depResult = results.firstWhere(
              (r) => r.stepId == depId,
              orElse: () => StepExecutionResult(
                stepId: depId,
                success: false,
                output: 'Dependency not found',
                duration: Duration.zero,
              ),
            );
            return !depResult.success;
          });

          if (dependencyFailed) {
            final result = StepExecutionResult(
              stepId: step.id,
              success: false,
              output: 'Skipped due to failed dependency',
              duration: Duration.zero,
              skipped: true,
            );
            results.add(result);
            continue;
          }
        }

        // Handle input requirements
        if (step.requiresInput && inputs != null && inputs.containsKey(step.id)) {
          // Input provided, continue
        } else if (step.requiresInput) {
          final result = StepExecutionResult(
            stepId: step.id,
            success: false,
            output: 'Waiting for user input: ${step.inputPrompt}',
            duration: Duration.zero,
            waitingForInput: true,
          );
          results.add(result);
          execution.status = ExecutionStatus.waiting;
          _executionController.add(execution);
          continue;
        }

        // Execute step
        final stepResult = await _executeWorkflowStep(
          step,
          inputs: inputs,
          dryRun: dryRun,
        );
        results.add(stepResult);

        // Update execution status
        execution.currentStep = step.id;
        execution.progress = results.length / workflow.steps.length;
        _executionController.add(execution);

        // Handle failure
        if (!stepResult.success && !step.continueOnFailure) {
          execution.status = ExecutionStatus.failed;
          _executionController.add(execution);
          break;
        }
      }

      // Determine final status
      final allSuccessful = results.every((r) => r.success || r.skipped);
      execution.status = allSuccessful ? ExecutionStatus.completed : ExecutionStatus.failed;
      execution.endTime = DateTime.now();

      final result = WorkflowExecutionResult(
        executionId: executionId,
        workflowId: workflowId,
        success: allSuccessful,
        results: results,
        totalDuration: execution.duration,
        dryRun: dryRun,
      );

      _executionController.add(execution);
      return result;

    } catch (e) {
      execution.status = ExecutionStatus.failed;
      execution.endTime = DateTime.now();
      execution.error = e.toString();
      _executionController.add(execution);

      rethrow;
    } finally {
      _activeExecutions.remove(executionId);
    }
  }

  /// Execute a single workflow step
  Future<StepExecutionResult> _executeWorkflowStep(
    WorkflowStep step, {
    Map<String, dynamic>? inputs,
    bool dryRun = false,
  }) async {
    final startTime = DateTime.now();

    try {
      if (dryRun) {
        // Simulate execution
        await Future.delayed(Duration(milliseconds: 100));
        return StepExecutionResult(
          stepId: step.id,
          success: true,
          output: '[DRY RUN] Would execute: ${step.command}',
          duration: DateTime.now().difference(startTime),
          dryRun: true,
        );
      }

      // Execute based on step type
      switch (step.type) {
        case StepType.command:
          return await _executeCommandStep(step, startTime, inputs);

        case StepType.script:
          return await _executeScriptStep(step, startTime, inputs);

        case StepType.api_call:
          return await _executeApiStep(step, startTime, inputs);

        case StepType.manual:
          return StepExecutionResult(
            stepId: step.id,
            success: true,
            output: 'Manual step completed',
            duration: DateTime.now().difference(startTime),
            manual: true,
          );

        default:
          throw Exception('Unsupported step type: ${step.type}');
      }
    } catch (e) {
      return StepExecutionResult(
        stepId: step.id,
        success: false,
        output: 'Step failed: $e',
        duration: DateTime.now().difference(startTime),
        error: e.toString(),
      );
    }
  }

  /// Execute command step
  Future<StepExecutionResult> _executeCommandStep(
    WorkflowStep step,
    DateTime startTime,
    Map<String, dynamic>? inputs,
  ) async {
    // This would integrate with the actual terminal execution
    // For now, simulate execution
    await Future.delayed(Duration(milliseconds: (step.command.length * 10).clamp(500, 5000)));

    // Mock success/failure
    final success = !step.command.contains('fail') && !step.command.contains('error');

    return StepExecutionResult(
      stepId: step.id,
      success: success,
      output: success
          ? 'Command executed successfully: ${step.command}'
          : 'Command failed: ${step.command}',
      duration: DateTime.now().difference(startTime),
      exitCode: success ? 0 : 1,
    );
  }

  /// Execute script step
  Future<StepExecutionResult> _executeScriptStep(
    WorkflowStep step,
    DateTime startTime,
    Map<String, dynamic>? inputs,
  ) async {
    // Execute script file
    final scriptCommand = step.command;

    // Simulate script execution
    await Future.delayed(Duration(seconds: 2));

    return StepExecutionResult(
      stepId: step.id,
      success: true,
      output: 'Script executed: $scriptCommand',
      duration: DateTime.now().difference(startTime),
    );
  }

  /// Execute API step
  Future<StepExecutionResult> _executeApiStep(
    WorkflowStep step,
    DateTime startTime,
    Map<String, dynamic>? inputs,
  ) async {
    // Make API call
    final apiCommand = step.command;

    // Simulate API call
    await Future.delayed(Duration(milliseconds: 500));

    return StepExecutionResult(
      stepId: step.id,
      success: true,
      output: 'API call completed: $apiCommand',
      duration: DateTime.now().difference(startTime),
    );
  }

  /// Validate workflow dependencies
  Future<void> _validateWorkflowDependencies(AutomatedWorkflow workflow) async {
    final stepIds = workflow.steps.map((s) => s.id).toSet();

    for (final step in workflow.steps) {
      if (step.dependsOn != null) {
        for (final depId in step.dependsOn!) {
          if (!stepIds.contains(depId)) {
            throw Exception('Step ${step.id} depends on unknown step: $depId');
          }
        }
      }
    }

    // Check for circular dependencies
    final visited = <String>{};
    final recursionStack = <String>{};

    for (final step in workflow.steps) {
      if (_hasCircularDependency(step, workflow.steps, visited, recursionStack)) {
        throw Exception('Circular dependency detected involving step: ${step.id}');
      }
    }
  }

  /// Check for circular dependencies using DFS
  bool _hasCircularDependency(
    WorkflowStep step,
    List<WorkflowStep> allSteps,
    Set<String> visited,
    Set<String> recursionStack,
  ) {
    if (recursionStack.contains(step.id)) {
      return true;
    }
    if (visited.contains(step.id)) {
      return false;
    }

    visited.add(step.id);
    recursionStack.add(step.id);

    if (step.dependsOn != null) {
      for (final depId in step.dependsOn!) {
        final depStep = allSteps.firstWhere((s) => s.id == depId);
        if (_hasCircularDependency(depStep, allSteps, visited, recursionStack)) {
          return true;
        }
      }
    }

    recursionStack.remove(step.id);
    return false;
  }

  /// Calculate execution order using topological sort
  List<String> _calculateExecutionOrder(List<WorkflowStep> steps) {
    final result = <String>[];
    final visited = <String>{};
    final tempVisited = <String>{};

    void visit(WorkflowStep step) {
      if (tempVisited.contains(step.id)) {
        throw Exception('Circular dependency detected');
      }
      if (visited.contains(step.id)) {
        return;
      }

      tempVisited.add(step.id);

      // Visit dependencies first
      if (step.dependsOn != null) {
        for (final depId in step.dependsOn!) {
          final depStep = steps.firstWhere((s) => s.id == depId);
          visit(depStep);
        }
      }

      tempVisited.remove(step.id);
      visited.add(step.id);
      result.add(step.id);
    }

    // Visit all steps
    for (final step in steps) {
      if (!visited.contains(step.id)) {
        visit(step);
      }
    }

    return result;
  }

  /// Get workflow templates
  List<WorkflowTemplate> getTemplates({String? category}) {
    if (category == null) return List.unmodifiable(_templates);

    return _templates.where((t) => t.category == category).toList();
  }

  /// Get saved workflows
  List<AutomatedWorkflow> getWorkflows({String? category}) {
    final workflows = _workflows.values.toList();

    if (category == null) return workflows;

    return workflows.where((w) => w.category == category).toList();
  }

  /// Get workflow by ID
  AutomatedWorkflow? getWorkflow(String workflowId) {
    return _workflows[workflowId];
  }

  /// Delete workflow
  void deleteWorkflow(String workflowId) {
    _workflows.remove(workflowId);
    debugPrint('🗑️ Deleted workflow: $workflowId');
  }

  /// Get active executions
  List<WorkflowExecution> getActiveExecutions() {
    return _activeExecutions.values.toList();
  }

  /// Cancel execution
  Future<void> cancelExecution(String executionId) async {
    final execution = _activeExecutions[executionId];
    if (execution != null) {
      execution.status = ExecutionStatus.cancelled;
      execution.endTime = DateTime.now();
      _executionController.add(execution);
      _activeExecutions.remove(executionId);
    }
  }

  /// Export workflow to JSON
  String exportWorkflow(String workflowId) {
    final workflow = _workflows[workflowId];
    if (workflow == null) {
      throw Exception('Workflow not found: $workflowId');
    }

    return jsonEncode(workflow.toJson());
  }

  /// Import workflow from JSON
  Future<String> importWorkflow(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final workflow = AutomatedWorkflow.fromJson(data);

      // Generate new ID to avoid conflicts
      final newId = 'workflow_${DateTime.now().millisecondsSinceEpoch}';
      workflow.id = newId;

      _workflows[newId] = workflow;
      return newId;
    } catch (e) {
      throw Exception('Failed to import workflow: $e');
    }
  }

  /// Get workflow statistics
  Map<String, dynamic> getWorkflowStats() {
    return {
      'total_workflows': _workflows.length,
      'total_templates': _templates.length,
      'active_executions': _activeExecutions.length,
      'categories': _workflows.values.map((w) => w.category).toSet().toList(),
    };
  }

  /// Dispose resources
  void dispose() {
    _executionController.close();
    _isActive = false;
  }
}

/// Workflow execution statuses
enum ExecutionStatus {
  pending,
  running,
  waiting,
  completed,
  failed,
  cancelled,
}

/// Step types
enum StepType {
  command,
  script,
  api_call,
  manual,
}

/// Automated workflow
class AutomatedWorkflow {
  String id;
  String name;
  String description;
  List<WorkflowStep> steps;
  String category;
  List<String> variables;
  Map<String, dynamic> metadata;
  DateTime createdAt;
  DateTime? lastExecuted;
  int executionCount = 0;

  AutomatedWorkflow({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
    required this.category,
    required this.variables,
    required this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'steps': steps.map((s) => s.toJson()).toList(),
      'category': category,
      'variables': variables,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'lastExecuted': lastExecuted?.toIso8601String(),
      'executionCount': executionCount,
    };
  }

  factory AutomatedWorkflow.fromJson(Map<String, dynamic> json) {
    return AutomatedWorkflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      steps: (json['steps'] as List).map((s) => WorkflowStep.fromJson(s)).toList(),
      category: json['category'],
      variables: List<String>.from(json['variables']),
      metadata: Map<String, dynamic>.from(json['metadata']),
      createdAt: DateTime.parse(json['createdAt']),
    )..lastExecuted = json['lastExecuted'] != null ? DateTime.parse(json['lastExecuted']) : null
      ..executionCount = json['executionCount'] ?? 0;
  }
}

/// Workflow template
class WorkflowTemplate {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<WorkflowStep> steps;
  final List<String> variables;

  WorkflowTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.steps,
    required this.variables,
  });
}

/// Workflow step
class WorkflowStep {
  final String id;
  final String name;
  final String command;
  final String description;
  final StepType type;
  final List<String>? dependsOn;
  final bool continueOnFailure;
  final bool requiresInput;
  final String? inputPrompt;
  final Duration? timeout;
  final int retryCount;

  WorkflowStep({
    required this.id,
    required this.name,
    required this.command,
    required this.description,
    required this.type,
    this.dependsOn,
    this.continueOnFailure = true,
    this.requiresInput = false,
    this.inputPrompt,
    this.timeout,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'description': description,
      'type': type.name,
      'dependsOn': dependsOn,
      'continueOnFailure': continueOnFailure,
      'requiresInput': requiresInput,
      'inputPrompt': inputPrompt,
      'timeout': timeout?.inSeconds,
      'retryCount': retryCount,
    };
  }

  factory WorkflowStep.fromJson(Map<String, dynamic> json) {
    return WorkflowStep(
      id: json['id'],
      name: json['name'],
      command: json['command'],
      description: json['description'],
      type: StepType.values.firstWhere((e) => e.name == json['type']),
      dependsOn: json['dependsOn'] != null ? List<String>.from(json['dependsOn']) : null,
      continueOnFailure: json['continueOnFailure'] ?? true,
      requiresInput: json['requiresInput'] ?? false,
      inputPrompt: json['inputPrompt'],
      timeout: json['timeout'] != null ? Duration(seconds: json['timeout']) : null,
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

/// Workflow execution
class WorkflowExecution {
  final String id;
  final AutomatedWorkflow workflow;
  final DateTime startTime;
  DateTime? endTime;
  ExecutionStatus status;
  final Map<String, dynamic> inputs;
  final bool dryRun;
  String? currentStep;
  double progress = 0.0;
  String? error;

  WorkflowExecution({
    required this.id,
    required this.workflow,
    required this.startTime,
    required this.status,
    required this.inputs,
    required this.dryRun,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}

/// Workflow execution result
class WorkflowExecutionResult {
  final String executionId;
  final String workflowId;
  final bool success;
  final List<StepExecutionResult> results;
  final Duration totalDuration;
  final bool dryRun;

  WorkflowExecutionResult({
    required this.executionId,
    required this.workflowId,
    required this.success,
    required this.results,
    required this.totalDuration,
    required this.dryRun,
  });

  int get totalSteps => results.length;
  int get successfulSteps => results.where((r) => r.success).length;
  int get failedSteps => results.where((r) => !r.success && !r.skipped).length;
  int get skippedSteps => results.where((r) => r.skipped).length;
}

/// Step execution result
class StepExecutionResult {
  final String stepId;
  final bool success;
  final String output;
  final Duration duration;
  final int? exitCode;
  final bool skipped;
  final bool waitingForInput;
  final bool manual;
  final bool dryRun;
  final String? error;

  StepExecutionResult({
    required this.stepId,
    required this.success,
    required this.output,
    required this.duration,
    this.exitCode,
    this.skipped = false,
    this.waitingForInput = false,
    this.manual = false,
    this.dryRun = false,
    this.error,
  });
}