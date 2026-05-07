import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Smart Command Chaining System
///
/// Automatically detects command sequences and creates executable workflows.
/// Supports chaining with &&, ||, and ; operators, plus intelligent pattern recognition.
class SmartCommandChaining {
  final StreamController<CommandChain> _chainController =
      StreamController<CommandChain>.broadcast();

  Stream<CommandChain> get chains => _chainController.stream;

  final List<CommandPattern> _patterns = [];
  final Map<String, CommandWorkflow> _workflows = {};
  final List<String> _commandHistory = [];
  final int _maxHistorySize = 1000;

  bool _isActive = false;
  bool get isActive => _isActive;

  SmartCommandChaining() {
    _initializePatterns();
  }

  /// Initialize the command chaining system
  Future<void> initialize() async {
    if (_isActive) return;

    _isActive = true;
    debugPrint('🔗 Smart Command Chaining initialized');
  }

  /// Initialize common command patterns
  void _initializePatterns() {
    _patterns.addAll([
      // Git workflow patterns
      CommandPattern(
        name: 'git-commit-push',
        trigger: ['git add', 'git commit', 'git push'],
        workflow: GitCommitPushWorkflow(),
      ),
      CommandPattern(
        name: 'git-pull-build',
        trigger: ['git pull', 'npm install', 'npm run build'],
        workflow: GitPullBuildWorkflow(),
      ),

      // Docker patterns
      CommandPattern(
        name: 'docker-build-run',
        trigger: ['docker build', 'docker run'],
        workflow: DockerBuildRunWorkflow(),
      ),

      // Testing patterns
      CommandPattern(
        name: 'test-lint-fix',
        trigger: ['npm test', 'npm run lint', 'npm run lint:fix'],
        workflow: TestLintFixWorkflow(),
      ),

      // Database patterns
      CommandPattern(
        name: 'db-migrate-seed',
        trigger: ['npm run db:migrate', 'npm run db:seed'],
        workflow: DbMigrateSeedWorkflow(),
      ),
    ]);
  }

  /// Analyze command input for chaining opportunities
  Future<CommandChain?> analyzeCommand(String input, List<String> history) async {
    if (!_isActive) return null;

    // Add to history
    _addToHistory(input);

    // Check for explicit chaining operators
    final explicitChain = _detectExplicitChain(input);
    if (explicitChain != null) {
      _chainController.add(explicitChain);
      return explicitChain;
    }

    // Check for pattern-based chaining
    final patternChain = _detectPatternChain(input, history);
    if (patternChain != null) {
      _chainController.add(patternChain);
      return patternChain;
    }

    return null;
  }

  /// Detect explicit command chains (using &&, ||, ;)
  CommandChain? _detectExplicitChain(String input) {
    final commands = <String>[];

    // Split by chaining operators while preserving them
    final parts = input.split(RegExp(r'(\s*(?:\|\||&&|;)\s*)'));

    String currentCommand = '';
    String? currentOperator;

    for (final part in parts) {
      if (part.trim().isEmpty) continue;

      if (part.contains('&&') || part.contains('||') || part.contains(';')) {
        if (currentCommand.isNotEmpty) {
          commands.add(currentCommand.trim());
        }
        currentOperator = part.trim();
      } else {
        currentCommand += part;
      }
    }

    if (currentCommand.isNotEmpty) {
      commands.add(currentCommand.trim());
    }

    if (commands.length > 1) {
      return CommandChain(
        commands: commands,
        operators: _extractOperators(input),
        type: ChainType.explicit,
        confidence: 1.0,
      );
    }

    return null;
  }

  /// Extract operators from chained command
  List<String> _extractOperators(String input) {
    final operators = <String>[];
    final matches = RegExp(r'\s*(\|\||&&|;)\s*').allMatches(input);

    for (final match in matches) {
      operators.add(match.group(1)!);
    }

    return operators;
  }

  /// Detect pattern-based command chains
  CommandChain? _detectPatternChain(String input, List<String> history) {
    // Look for patterns in recent history
    final recentHistory = history.take(10).toList().reversed.toList();

    for (final pattern in _patterns) {
      final match = _findPatternMatch(pattern, input, recentHistory);
      if (match != null) {
        return match;
      }
    }

    return null;
  }

  /// Find pattern match in history
  CommandChain? _findPatternMatch(
    CommandPattern pattern,
    String currentInput,
    List<String> recentHistory,
  ) {
    final commands = <String>[];

    // Check if current input matches first trigger
    if (!pattern.trigger.first.split(' ').first.contains(currentInput.split(' ').first)) {
      return null;
    }

    commands.add(currentInput);

    // Look for subsequent commands in history
    for (int i = 0; i < pattern.trigger.length - 1 && i < recentHistory.length; i++) {
      final expectedBase = pattern.trigger[i + 1].split(' ').first;
      final historyBase = recentHistory[i].split(' ').first;

      if (expectedBase == historyBase) {
        commands.insert(0, recentHistory[i]);
      } else {
        return null; // Pattern broken
      }
    }

    if (commands.length == pattern.trigger.length) {
      return CommandChain(
        commands: commands,
        operators: List.filled(commands.length - 1, '&&'),
        type: ChainType.pattern,
        confidence: 0.8,
        pattern: pattern,
      );
    }

    return null;
  }

  /// Execute a command chain
  Future<ChainExecutionResult> executeChain(CommandChain chain) async {
    final results = <CommandResult>[];

    for (int i = 0; i < chain.commands.length; i++) {
      final command = chain.commands[i];
      final operator = i > 0 ? chain.operators[i - 1] : null;

      // Check if we should continue based on previous result and operator
      if (operator != null && results.isNotEmpty) {
        final previousResult = results.last;
        if (!_shouldContinue(operator, previousResult.success)) {
          break;
        }
      }

      debugPrint('🔗 Executing: $command');

      // Execute command (this would integrate with actual terminal execution)
      final result = await _executeCommand(command);

      results.add(result);

      // Update workflow if applicable
      if (chain.pattern?.workflow != null) {
        chain.pattern!.workflow.updateProgress(i, result);
      }
    }

    final overallSuccess = results.every((r) => r.success);

    return ChainExecutionResult(
      chain: chain,
      results: results,
      success: overallSuccess,
      totalDuration: results.fold(
        Duration.zero,
        (sum, r) => sum + r.duration,
      ),
    );
  }

  /// Determine if execution should continue based on operator and previous result
  bool _shouldContinue(String operator, bool previousSuccess) {
    switch (operator) {
      case '&&':
        return previousSuccess;
      case '||':
        return !previousSuccess;
      case ';':
        return true; // Always continue with semicolon
      default:
        return true;
    }
  }

  /// Execute individual command (placeholder - would integrate with PTY backend)
  Future<CommandResult> _executeCommand(String command) async {
    // Simulate command execution
    await Future.delayed(Duration(milliseconds: 100 + (command.length * 10)));

    // Mock success/failure based on command
    final success = !command.contains('fail') && !command.contains('error');

    return CommandResult(
      command: command,
      success: success,
      output: success ? 'Command executed successfully' : 'Command failed',
      duration: Duration(milliseconds: 100 + (command.length * 10)),
      exitCode: success ? 0 : 1,
    );
  }

  /// Save a command chain as a reusable workflow
  void saveWorkflow(String name, CommandChain chain) {
    _workflows[name] = CommandWorkflow(
      name: name,
      chain: chain,
      createdAt: DateTime.now(),
    );
    debugPrint('💾 Saved workflow: $name');
  }

  /// Get saved workflows
  List<CommandWorkflow> getWorkflows() {
    return _workflows.values.toList();
  }

  /// Execute saved workflow
  Future<ChainExecutionResult> executeWorkflow(String name) async {
    final workflow = _workflows[name];
    if (workflow == null) {
      throw Exception('Workflow not found: $name');
    }

    return executeChain(workflow.chain);
  }

  /// Add command to history
  void _addToHistory(String command) {
    _commandHistory.add(command);
    if (_commandHistory.length > _maxHistorySize) {
      _commandHistory.removeAt(0);
    }
  }

  /// Get command history
  List<String> getCommandHistory() {
    return List.unmodifiable(_commandHistory);
  }

  /// Get chaining suggestions for current input
  List<CommandChain> getSuggestions(String currentInput, List<String> history) {
    final suggestions = <CommandChain>[];

    // Suggest saved workflows
    for (final workflow in _workflows.values) {
      if (workflow.chain.commands.first.contains(currentInput.split(' ').first)) {
        suggestions.add(workflow.chain);
      }
    }

    // Suggest pattern-based chains
    for (final pattern in _patterns) {
      if (pattern.trigger.first.split(' ').first == currentInput.split(' ').first) {
        final mockChain = CommandChain(
          commands: pattern.trigger,
          operators: List.filled(pattern.trigger.length - 1, '&&'),
          type: ChainType.pattern,
          confidence: 0.7,
          pattern: pattern,
        );
        suggestions.add(mockChain);
      }
    }

    return suggestions;
  }

  /// Dispose resources
  void dispose() {
    _chainController.close();
    _isActive = false;
  }
}

/// Command chain data structure
enum ChainType { explicit, pattern, workflow }

class CommandChain {
  final List<String> commands;
  final List<String> operators;
  final ChainType type;
  final double confidence;
  final CommandPattern? pattern;

  CommandChain({
    required this.commands,
    required this.operators,
    required this.type,
    required this.confidence,
    this.pattern,
  });

  String get displayName {
    switch (type) {
      case ChainType.explicit:
        return commands.join(' && ');
      case ChainType.pattern:
        return pattern?.name ?? 'Pattern Chain';
      case ChainType.workflow:
        return 'Workflow';
    }
  }

  @override
  String toString() => displayName;
}

/// Command execution result
class CommandResult {
  final String command;
  final bool success;
  final String output;
  final Duration duration;
  final int exitCode;

  CommandResult({
    required this.command,
    required this.success,
    required this.output,
    required this.duration,
    required this.exitCode,
  });
}

/// Chain execution result
class ChainExecutionResult {
  final CommandChain chain;
  final List<CommandResult> results;
  final bool success;
  final Duration totalDuration;

  ChainExecutionResult({
    required this.chain,
    required this.results,
    required this.success,
    required this.totalDuration,
  });
}

/// Command pattern for auto-detection
class CommandPattern {
  final String name;
  final List<String> trigger;
  final CommandWorkflow workflow;

  CommandPattern({
    required this.name,
    required this.trigger,
    required this.workflow,
  });
}

/// Saved command workflow
class CommandWorkflow {
  final String name;
  final CommandChain chain;
  final DateTime createdAt;
  int executionCount = 0;
  Duration totalExecutionTime = Duration.zero;

  CommandWorkflow({
    required this.name,
    required this.chain,
    required this.createdAt,
  });

  void updateProgress(int step, CommandResult result) {
    // Update workflow statistics
    executionCount++;
    totalExecutionTime += result.duration;
  }

  Duration get averageExecutionTime =>
      executionCount > 0 ? totalExecutionTime ~/ executionCount : Duration.zero;
}

/// Predefined workflow implementations

class GitCommitPushWorkflow extends CommandWorkflow {
  GitCommitPushWorkflow()
      : super(
          name: 'git-commit-push',
          chain: CommandChain(
            commands: ['git add .', 'git commit -m "Auto commit"', 'git push'],
            operators: ['&&', '&&'],
            type: ChainType.workflow,
            confidence: 1.0,
          ),
          createdAt: DateTime.now(),
        );

  @override
  void updateProgress(int step, CommandResult result) {
    super.updateProgress(step, result);

    // Custom logic for git workflow
    if (step == 0 && !result.success) {
      debugPrint('⚠️ Git add failed - check for untracked files');
    } else if (step == 1 && !result.success) {
      debugPrint('⚠️ Git commit failed - check commit message or staged files');
    } else if (step == 2 && !result.success) {
      debugPrint('⚠️ Git push failed - check remote configuration');
    }
  }
}

class GitPullBuildWorkflow extends CommandWorkflow {
  GitPullBuildWorkflow()
      : super(
          name: 'git-pull-build',
          chain: CommandChain(
            commands: ['git pull', 'npm install', 'npm run build'],
            operators: ['&&', '&&'],
            type: ChainType.workflow,
            confidence: 1.0,
          ),
          createdAt: DateTime.now(),
        );
}

class DockerBuildRunWorkflow extends CommandWorkflow {
  DockerBuildRunWorkflow()
      : super(
          name: 'docker-build-run',
          chain: CommandChain(
            commands: ['docker build -t myapp .', 'docker run -p 3000:3000 myapp'],
            operators: ['&&'],
            type: ChainType.workflow,
            confidence: 1.0,
          ),
          createdAt: DateTime.now(),
        );
}

class TestLintFixWorkflow extends CommandWorkflow {
  TestLintFixWorkflow()
      : super(
          name: 'test-lint-fix',
          chain: CommandChain(
            commands: ['npm test', 'npm run lint', 'npm run lint:fix'],
            operators: ['&&', '&&'],
            type: ChainType.workflow,
            confidence: 1.0,
          ),
          createdAt: DateTime.now(),
        );
}

class DbMigrateSeedWorkflow extends CommandWorkflow {
  DbMigrateSeedWorkflow()
      : super(
          name: 'db-migrate-seed',
          chain: CommandChain(
            commands: ['npm run db:migrate', 'npm run db:seed'],
            operators: ['&&'],
            type: ChainType.workflow,
            confidence: 1.0,
          ),
          createdAt: DateTime.now(),
        );
}