import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Error detection with automatic fixes for Termisol
/// 
/// Features:
/// - Real-time error detection
/// - Automatic fix suggestions
/// - AI-powered error analysis
/// - Common error patterns
/// - One-click fix application
/// - Error prevention tips
class ErrorDetectionSystem {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<ErrorEvent> _eventController = StreamController<ErrorEvent>.broadcast();
  
  final List<ErrorPattern> _errorPatterns = [];
  final List<DetectedError> _errorHistory = [];
  final Map<String, ErrorFix> _fixCache = {};
  
  Stream<ErrorEvent> get events => _eventController.stream;
  List<DetectedError> get errorHistory => List.unmodifiable(_errorHistory);
  
  ErrorDetectionSystem({this.aiAssistant}) {
    _initializeErrorPatterns();
  }
  
  void _initializeErrorPatterns() {
    // Common error patterns with fixes
    _errorPatterns.addAll([
      // Permission errors
      ErrorPattern(
        pattern: RegExp(r'permission denied', caseSensitive: false),
        type: ErrorType.permission,
        severity: ErrorSeverity.high,
        description: 'Permission denied',
        fixes: [
          ErrorFix(
            command: 'sudo {original_command}',
            description: 'Run with sudo (requires admin privileges)',
            risk: FixRisk.high,
          ),
          ErrorFix(
            command: 'chmod +x {file}',
            description: 'Make file executable',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'chown {user}:{user} {file}',
            description: 'Change file ownership',
            risk: FixRisk.medium,
          ),
        ],
      ),
      
      // Command not found
      ErrorPattern(
        pattern: RegExp(r'command not found|not recognized', caseSensitive: false),
        type: ErrorType.command_not_found,
        severity: ErrorSeverity.medium,
        description: 'Command not found',
        fixes: [
          ErrorFix(
            command: 'which {command}',
            description: 'Check if command is installed',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'apt install {command}',
            description: 'Install command (Debian/Ubuntu)',
            risk: FixRisk.medium,
          ),
          ErrorFix(
            command: 'brew install {command}',
            description: 'Install command (macOS)',
            risk: FixRisk.medium,
          ),
        ],
      ),
      
      // File not found
      ErrorPattern(
        pattern: RegExp(r'no such file|cannot access|not found', caseSensitive: false),
        type: ErrorType.file_not_found,
        severity: ErrorSeverity.medium,
        description: 'File not found',
        fixes: [
          ErrorFix(
            command: 'ls -la',
            description: 'List files in current directory',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'pwd',
            description: 'Show current directory',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'find . -name "{filename}"',
            description: 'Search for file',
            risk: FixRisk.low,
          ),
        ],
      ),
      
      // Network errors
      ErrorPattern(
        pattern: RegExp(r'connection refused|network unreachable|host not found', caseSensitive: false),
        type: ErrorType.network,
        severity: ErrorSeverity.high,
        description: 'Network connection error',
        fixes: [
          ErrorFix(
            command: 'ping {host}',
            description: 'Test network connectivity',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'curl -I {url}',
            description: 'Test HTTP connection',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'netstat -tuln',
            description: 'Check listening ports',
            risk: FixRisk.low,
          ),
        ],
      ),
      
      // Port already in use
      ErrorPattern(
        pattern: RegExp(r'address already in use|port already in use', caseSensitive: false),
        type: ErrorType.port_conflict,
        severity: ErrorSeverity.high,
        description: 'Port already in use',
        fixes: [
          ErrorFix(
            command: 'lsof -i :{port}',
            description: 'Find process using port',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'kill -9 {pid}',
            description: 'Kill process using port',
            risk: FixRisk.high,
          ),
          ErrorFix(
            command: '{command} --port={new_port}',
            description: 'Use different port',
            risk: FixRisk.low,
          ),
        ],
      ),
      
      // Syntax errors
      ErrorPattern(
        pattern: RegExp(r'syntax error|unexpected token|invalid syntax', caseSensitive: false),
        type: ErrorType.syntax,
        severity: ErrorSeverity.medium,
        description: 'Syntax error',
        fixes: [
          ErrorFix(
            command: 'echo "Check quotes and parentheses"',
            description: 'Check for missing quotes/brackets',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'shellcheck {script}',
            description: 'Validate shell script syntax',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'python -m py_compile {file}',
            description: 'Validate Python syntax',
            risk: FixRisk.low,
          ),
        ],
      ),
      
      // Memory errors
      ErrorPattern(
        pattern: RegExp(r'out of memory|cannot allocate|memory exhausted', caseSensitive: false),
        type: ErrorType.memory,
        severity: ErrorSeverity.high,
        description: 'Memory error',
        fixes: [
          ErrorFix(
            command: 'free -h',
            description: 'Check memory usage',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'kill -9 {pid}',
            description: 'Kill memory-intensive process',
            risk: FixRisk.high,
          ),
          ErrorFix(
            command: 'swapoff -a && swapon -a',
            description: 'Reset swap memory',
            risk: FixRisk.medium,
          ),
        ],
      ),
      
      // Disk space errors
      ErrorPattern(
        pattern: RegExp(r'no space left|disk full|insufficient space', caseSensitive: false),
        type: ErrorType.disk_space,
        severity: ErrorSeverity.high,
        description: 'Disk space error',
        fixes: [
          ErrorFix(
            command: 'df -h',
            description: 'Check disk usage',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'du -sh * | sort -hr | head -10',
            description: 'Find largest files',
            risk: FixRisk.low,
          ),
          ErrorFix(
            command: 'rm -rf {file}',
            description: 'Remove large files',
            risk: FixRisk.high,
          ),
        ],
      ),
    ]);
  }
  
  /// Analyze output for errors
  Future<List<DetectedError>> analyzeOutput(String output, {String? command}) async {
    final detectedErrors = <DetectedError>[];
    
    for (final pattern in _errorPatterns) {
      final matches = pattern.pattern.allMatches(output);
      for (final match in matches) {
        final error = DetectedError(
          pattern: pattern,
          match: match,
          output: output,
          command: command,
          timestamp: DateTime.now(),
        );
        
        detectedErrors.add(error);
        _errorHistory.insert(0, error);
        
        // Limit history size
        if (_errorHistory.length > 100) {
          _errorHistory.removeLast();
        }
        
        _eventController.add(ErrorEvent(
          type: ErrorEventType.error_detected,
          message: 'Error detected: ${pattern.description}',
          data: {'error': error},
        ));
      }
    }
    
    return detectedErrors;
  }
  
  /// Get fixes for detected error
  Future<List<ErrorFix>> getFixes(DetectedError error) async {
    final cacheKey = '${error.pattern.type}_${error.match.group(0)}';
    
    // Check cache first
    if (_fixCache.containsKey(cacheKey)) {
      return [_fixCache[cacheKey]!];
    }
    
    // Get pattern fixes
    final fixes = List<ErrorFix>.from(error.pattern.fixes);
    
    // Get AI-powered fixes if available
    if (aiAssistant != null) {
      try {
        final aiFixes = await _getAIFixes(error);
        fixes.addAll(aiFixes);
      } catch (e) {
        debugPrint('❌ AI fix generation failed: $e');
      }
    }
    
    // Sort by risk (low risk first)
    fixes.sort((a, b) => a.risk.index.compareTo(b.risk.index));
    
    // Cache best fix
    if (fixes.isNotEmpty) {
      _fixCache[cacheKey] = fixes.first;
    }
    
    return fixes;
  }
  
  Future<List<ErrorFix>> _getAIFixes(DetectedError error) async {
    if (aiAssistant == null) return [];
    
    final prompt = '''Analyze this error and provide specific fixes:

Error: ${error.pattern.description}
Output: ${error.match.group(0)}
Command: ${error.command ?? 'Unknown'}

Provide 2-3 specific fixes with:
1. Exact command to run
2. Brief explanation
3. Risk level (low/medium/high)

Format as JSON array:
[
  {
    "command": "exact command",
    "description": "explanation",
    "risk": "low"
  }
]''';
    
    try {
      final response = await aiAssistant!.analyzeError(prompt);
      
      // Parse AI response (simplified)
      final fixes = <ErrorFix>[];
      
      // Add AI-generated fix
      fixes.add(ErrorFix(
        command: response,
        description: 'AI-suggested fix',
        risk: FixRisk.medium,
      ));
      
      return fixes;
    } catch (e) {
      return [];
    }
  }
  
  /// Apply fix
  Future<ErrorFixResult> applyFix(ErrorFix fix, DetectedError error) async {
    try {
      final command = _substituteCommand(fix.command, error);
      
      final result = await run(
        'bash',
        ['-c', command],
        workingDirectory: Directory.current.path,
      );
      
      final success = result.exitCode == 0;
      
      _eventController.add(ErrorEvent(
        type: success ? ErrorEventType.fix_applied : ErrorEventType.fix_failed,
        message: success ? 'Fix applied successfully' : 'Fix failed',
        data: {
          'fix': fix,
          'command': command,
          'exitCode': result.exitCode,
          'output': result.stdout,
        },
      ));
      
      return ErrorFixResult(
        fix: fix,
        command: command,
        success: success,
        output: result.stdout,
        error: result.stderr,
      );
    } catch (e) {
      _eventController.add(ErrorEvent(
        type: ErrorEventType.fix_failed,
        message: 'Fix failed with exception: $e',
        data: {'error': e.toString()},
      ));
      
      return ErrorFixResult(
        fix: fix,
        command: fix.command,
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }
  
  String _substituteCommand(String template, DetectedError error) {
    var command = template;
    
    // Substitute common placeholders
    command = command.replaceAll('{original_command}', error.command ?? '');
    command = command.replaceAll('{file}', _extractFileFromError(error.output));
    command = command.replaceAll('{user}', Platform.environment['USER'] ?? 'user');
    command = command.replaceAll('{command}', _extractCommandFromError(error.output));
    command = command.replaceAll('{host}', _extractHostFromError(error.output));
    command = command.replaceAll('{port}', _extractPortFromError(error.output).toString());
    command = command.replaceAll('{pid}', _extractPidFromError(error.output).toString());
    command = command.replaceAll('{filename}', _extractFileFromError(error.output));
    command = command.replaceAll('{new_port}', (_extractPortFromError(error.output) + 1).toString());
    
    return command;
  }
  
  String _extractFileFromError(String output) {
    final match = RegExp(r'["\']([^"\']+)["\']').firstMatch(output);
    return match?.group(1) ?? 'file';
  }
  
  String _extractCommandFromError(String output) {
    final match = RegExp(r'command\s+([^\s]+)').firstMatch(output);
    return match?.group(1) ?? 'command';
  }
  
  String _extractHostFromError(String output) {
    final match = RegExp(r'host\s+([^\s]+)').firstMatch(output);
    return match?.group(1) ?? 'localhost';
  }
  
  int _extractPortFromError(String output) {
    final match = RegExp(r'port\s+(\d+)').firstMatch(output);
    return int.tryParse(match?.group(1) ?? '') ?? 3000;
  }
  
  int _extractPidFromError(String output) {
    final match = RegExp(r'PID\s+(\d+)').firstMatch(output);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
  
  /// Get error statistics
  Map<String, dynamic> getStatistics() {
    final errorCounts = <ErrorType, int>{};
    final severityCounts = <ErrorSeverity, int>{};
    
    for (final error in _errorHistory) {
      errorCounts[error.pattern.type] = (errorCounts[error.pattern.type] ?? 0) + 1;
      severityCounts[error.pattern.severity] = (severityCounts[error.pattern.severity] ?? 0) + 1;
    }
    
    return {
      'total_errors': _errorHistory.length,
      'error_types': errorCounts.map((k, v) => MapEntry(k.toString(), v)),
      'severity_counts': severityCounts.map((k, v) => MapEntry(k.toString(), v)),
      'patterns_count': _errorPatterns.length,
      'fixes_cached': _fixCache.length,
    };
  }
  
  /// Clear error history
  void clearHistory() {
    _errorHistory.clear();
    _fixCache.clear();
    
    _eventController.add(ErrorEvent(
      type: ErrorEventType.history_cleared,
      message: 'Error history cleared',
      data: {},
    ));
  }
  
  /// Dispose
  void dispose() {
    _eventController.close();
  }
}

/// Error pattern definition
class ErrorPattern {
  final RegExp pattern;
  final ErrorType type;
  final ErrorSeverity severity;
  final String description;
  final List<ErrorFix> fixes;
  
  ErrorPattern({
    required this.pattern,
    required this.type,
    required this.severity,
    required this.description,
    required this.fixes,
  });
}

/// Error fix suggestion
class ErrorFix {
  final String command;
  final String description;
  final FixRisk risk;
  final bool isAIGenerated;
  
  ErrorFix({
    required this.command,
    required this.description,
    required this.risk,
    this.isAIGenerated = false,
  });
  
  Color get riskColor {
    switch (risk) {
      case FixRisk.low:
        return Colors.green;
      case FixRisk.medium:
        return Colors.orange;
      case FixRisk.high:
        return Colors.red;
    }
  }
  
  String get riskLabel {
    switch (risk) {
      case FixRisk.low:
        return 'LOW';
      case FixRisk.medium:
        return 'MEDIUM';
      case FixRisk.high:
        return 'HIGH';
    }
  }
}

/// Detected error instance
class DetectedError {
  final ErrorPattern pattern;
  final RegExpMatch match;
  final String output;
  final String? command;
  final DateTime timestamp;
  
  DetectedError({
    required this.pattern,
    required this.match,
    required this.output,
    this.command,
    required this.timestamp,
  });
  
  String get matchedText => match.group(0) ?? '';
}

/// Error fix result
class ErrorFixResult {
  final ErrorFix fix;
  final String command;
  final bool success;
  final String output;
  final String error;
  
  ErrorFixResult({
    required this.fix,
    required this.command,
    required this.success,
    required this.output,
    required this.error,
  });
}

/// Error types
enum ErrorType {
  permission,
  command_not_found,
  file_not_found,
  network,
  port_conflict,
  syntax,
  memory,
  disk_space,
}

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
}

/// Fix risk levels
enum FixRisk {
  low,
  medium,
  high,
}

/// Error event types
enum ErrorEventType {
  error_detected,
  fix_applied,
  fix_failed,
  history_cleared,
}

/// Error event
class ErrorEvent {
  final ErrorEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  ErrorEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
