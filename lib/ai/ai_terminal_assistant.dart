import 'dart:async';
import 'package:flutter/material.dart';

/// AI Terminal Assistant for Termisol
/// 
/// Provides intelligent terminal assistance including:
/// - Command prediction and completion
/// - Command explanation and analysis
/// - Error analysis and suggestions
/// - Natural language translation
enum AIEventType {
  commandPredicted,
  commandExplained,
  errorAnalyzed,
  translationCompleted,
}

class AIEvent {
  final AIEventType type;
  final String data;
  final DateTime timestamp;
  
  AIEvent({
    required this.type,
    required this.data,
  }) : timestamp = DateTime.now();
}

class AITerminalAssistant {
  final StreamController<AIEvent> _eventController = 
      StreamController<AIEvent>.broadcast();
  
  Stream<AIEvent> get events => _eventController.stream;
  
  bool _isActive = false;
  
  bool get isActive => _isActive;
  
  /// Initialize the AI assistant
  Future<void> initialize() async {
    _isActive = true;
    debugPrint('🤖 AI Terminal Assistant initialized');
  }
  
  /// Predict next command based on context
  Future<String> predictCommand(String currentInput, List<String> history) async {
    // Simple prediction logic - in production would use ML model
    await Future.delayed(Duration(milliseconds: 100));
    
    final prediction = _generatePrediction(currentInput, history);
    _eventController.add(AIEvent(
      type: AIEventType.commandPredicted,
      data: prediction,
    ));
    
    return prediction;
  }
  
  /// Explain a command
  Future<String> explainCommand(String command) async {
    await Future.delayed(Duration(milliseconds: 200));
    
    final explanation = _generateExplanation(command);
    _eventController.add(AIEvent(
      type: AIEventType.commandExplained,
      data: explanation,
    ));
    
    return explanation;
  }
  
  /// Analyze error and provide suggestions
  Future<String> analyzeError(String errorOutput) async {
    await Future.delayed(Duration(milliseconds: 150));
    
    final analysis = _generateErrorAnalysis(errorOutput);
    _eventController.add(AIEvent(
      type: AIEventType.errorAnalyzed,
      data: analysis,
    ));
    
    return analysis;
  }
  
  /// Translate natural language to command
  Future<String> translateToCommand(String naturalLanguage) async {
    await Future.delayed(Duration(milliseconds: 300));
    
    final command = _generateTranslation(naturalLanguage);
    _eventController.add(AIEvent(
      type: AIEventType.translationCompleted,
      data: command,
    ));
    
    return command;
  }
  
  String _generatePrediction(String currentInput, List<String> history) {
    // Simple prediction based on history and current input
    if (currentInput.isEmpty && history.isNotEmpty) {
      return history.last;
    }
    
    // Common command patterns
    if (currentInput.startsWith('cd ')) {
      return 'cd ..';
    }
    if (currentInput.startsWith('ls ')) {
      return 'ls -la';
    }
    if (currentInput.startsWith('git ')) {
      return 'git status';
    }
    
    return '';
  }
  
  String _generateExplanation(String command) {
    final explanations = {
      'ls': 'List directory contents',
      'cd': 'Change directory',
      'pwd': 'Print working directory',
      'mkdir': 'Create directory',
      'rm': 'Remove file or directory',
      'cp': 'Copy file or directory',
      'mv': 'Move or rename file',
      'cat': 'Display file contents',
      'grep': 'Search text patterns',
      'find': 'Find files',
      'chmod': 'Change file permissions',
      'chown': 'Change file owner',
      'ps': 'Process status',
      'kill': 'Terminate process',
      'top': 'Process monitor',
      'df': 'Disk free space',
      'du': 'Disk usage',
      'tar': 'Archive utility',
      'ssh': 'Secure shell connection',
      'scp': 'Secure copy',
      'git': 'Version control system',
    };
    
    final baseCommand = command.split(' ').first;
    return explanations[baseCommand] ?? 'Command: $baseCommand';
  }
  
  String _generateErrorAnalysis(String errorOutput) {
    if (errorOutput.contains('command not found')) {
      return 'Command not found. Check spelling or install the command.';
    }
    if (errorOutput.contains('inaccessible or not found')) {
      return 'doesn\'t exist';
    }
    if (errorOutput.contains('permission denied')) {
      return 'Permission denied. Try using sudo or check file permissions.';
    }
    if (errorOutput.contains('no such file')) {
      return 'File or directory not found. Check the path.';
    }
    if (errorOutput.contains('connection refused')) {
      return 'Connection refused. Check if the service is running.';
    }
    
    return 'Error detected. Check command syntax and permissions.';
  }
  
  String _generateTranslation(String naturalLanguage) {
    final lower = naturalLanguage.toLowerCase();
    
    if (lower.contains('list') && lower.contains('file')) {
      return 'ls -la';
    }
    if (lower.contains('change') && lower.contains('directory')) {
      return 'cd';
    }
    if (lower.contains('create') && lower.contains('directory')) {
      return 'mkdir';
    }
    if (lower.contains('remove') || lower.contains('delete')) {
      return 'rm';
    }
    if (lower.contains('copy')) {
      return 'cp';
    }
    if (lower.contains('move') || lower.contains('rename')) {
      return 'mv';
    }
    if (lower.contains('git') && lower.contains('status')) {
      return 'git status';
    }
    if (lower.contains('git') && lower.contains('commit')) {
      return 'git commit';
    }
    if (lower.contains('git') && lower.contains('push')) {
      return 'git push';
    }
    
    return '# ' + naturalLanguage;
  }
  
  /// Process AI query (for compatibility)
  Future<String> processAiQuery(String query) async {
    return await explainCommand(query);
  }
  
  /// Update context (for compatibility)
  void updateContext({String? lastOutput}) {
    // Context update logic would go here
  }
  
  /// Check if text looks like an error
  bool looksLikeError(String text) {
    final errorPatterns = [
      'error',
      'failed',
      'cannot',
      'permission denied',
      'not found',
      'command not found',
      'inaccessible or not found',
      'no such file',
    ];
    
    final lowerText = text.toLowerCase();
    return errorPatterns.any((pattern) => lowerText.contains(pattern));
  }
  
  /// Dispose resources
  void dispose() {
    _isActive = false;
    _eventController.close();
  }
}
