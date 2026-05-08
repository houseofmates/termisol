import 'dart:io';
import 'package:flutter/foundation.dart';

/// Real-time code validation and error detection for the editor
class EditorValidator {
  final List<ValidationRule> _rules = [];
  final StreamController<ValidationResult> _resultController = 
      StreamController<ValidationResult>.broadcast();
  
  Stream<ValidationResult> get results => _resultController.stream;
  
  EditorValidator() {
    _initializeDefaultRules();
  }
  
  void _initializeDefaultRules() {
    // Syntax validation rules
    _rules.addAll([
      ValidationRule(
        name: 'balanced_brackets',
        description: 'Check for balanced brackets, braces, and parentheses',
        validator: _validateBalancedBrackets,
        severity: ValidationSeverity.error,
      ),
      ValidationRule(
        name: 'string_termination',
        description: 'Check for properly terminated strings',
        validator: _validateStringTermination,
        severity: ValidationSeverity.error,
      ),
      ValidationRule(
        name: 'trailing_whitespace',
        description: 'Detect trailing whitespace',
        validator: _validateTrailingWhitespace,
        severity: ValidationSeverity.warning,
      ),
      ValidationRule(
        name: 'line_length',
        description: 'Check for excessively long lines',
        validator: _validateLineLength,
        severity: ValidationSeverity.info,
      ),
    ]);
  }
  
  /// Validate the entire document
  ValidationResult validateDocument(String content, String? language) {
    final lines = content.split('\n');
    final issues = <ValidationIssue>[];
    
    for (final rule in _rules) {
      try {
        final ruleIssues = rule.validator(content, lines, language);
        issues.addAll(ruleIssues);
      } catch (e) {
        debugPrint('Validation rule ${rule.name} failed: $e');
      }
    }
    
    return ValidationResult(
      issues: issues,
      timestamp: DateTime.now(),
      isValid: issues.where((i) => i.severity == ValidationSeverity.error).isEmpty,
    );
  }
  
  /// Validate a specific line
  ValidationResult validateLine(String line, int lineNumber, String? language) {
    final issues = <ValidationIssue>[];
    
    for (final rule in _rules) {
      try {
        final ruleIssues = rule.validator(line, [line], language);
        for (final issue in ruleIssues) {
          if (issue.line == null) {
            issues.add(issue.copyWith(line: lineNumber));
          } else {
            issues.add(issue);
          }
        }
      } catch (e) {
        debugPrint('Validation rule ${rule.name} failed: $e');
      }
    }
    
    return ValidationResult(
      issues: issues,
      timestamp: DateTime.now(),
      isValid: issues.where((i) => i.severity == ValidationSeverity.error).isEmpty,
    );
  }
  
  List<ValidationIssue> _validateBalancedBrackets(
    String content, List<String> lines, String? language) {
    final issues = <ValidationIssue>[];
    final stack = <String>[];
    final brackets = {'(': ')', '[': ']', '{': '}', '<': '>'};
    final closingBrackets = brackets.values.toSet();
    
    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      
      if (brackets.containsKey(char)) {
        stack.add(char);
      } else if (closingBrackets.contains(char)) {
        if (stack.isEmpty) {
          final lineNum = content.substring(0, i).split('\n').length;
          issues.add(ValidationIssue(
            rule: 'balanced_brackets',
            message: 'Unmatched closing bracket: $char',
            severity: ValidationSeverity.error,
            line: lineNum,
            column: i - content.lastIndexOf('\n', i),
          ));
        } else {
          final expected = brackets[stack.removeLast()];
          if (char != expected) {
            final lineNum = content.substring(0, i).split('\n').length;
            issues.add(ValidationIssue(
              rule: 'balanced_brackets',
              message: 'Expected closing bracket $expected but found $char',
              severity: ValidationSeverity.error,
              line: lineNum,
              column: i - content.lastIndexOf('\n', i),
            ));
          }
        }
      }
    }
    
    // Check for unclosed brackets
    for (final bracket in stack.reversed) {
      final lastPos = content.lastIndexOf(bracket);
      final lineNum = content.substring(0, lastPos).split('\n').length;
      issues.add(ValidationIssue(
        rule: 'balanced_brackets',
        message: 'Unclosed bracket: $bracket',
        severity: ValidationSeverity.error,
        line: lineNum,
        column: lastPos - content.lastIndexOf('\n', lastPos),
      ));
    }
    
    return issues;
  }
  
  List<ValidationIssue> _validateStringTermination(
    String content, List<String> lines, String? language) {
    final issues = <ValidationIssue>[];
    bool inString = false;
    String? stringDelimiter;
    bool escaped = false;
    
    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      
      if (escaped) {
        escaped = false;
        continue;
      }
      
      if (char == '\\') {
        escaped = true;
        continue;
      }
      
      if (!inString && (char == '"' || char == "'")) {
        inString = true;
        stringDelimiter = char;
      } else if (inString && char == stringDelimiter) {
        inString = false;
        stringDelimiter = null;
      }
    }
    
    if (inString) {
      final lastPos = content.lastIndexOf(stringDelimiter!);
      final lineNum = content.substring(0, lastPos).split('\n').length;
      issues.add(ValidationIssue(
        rule: 'string_termination',
        message: 'Unterminated string literal',
        severity: ValidationSeverity.error,
        line: lineNum,
        column: lastPos - content.lastIndexOf('\n', lastPos),
      ));
    }
    
    return issues;
  }
  
  List<ValidationIssue> _validateTrailingWhitespace(
    String content, List<String> lines, String? language) {
    final issues = <ValidationIssue>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && line.endsWith(' ')) {
        issues.add(ValidationIssue(
          rule: 'trailing_whitespace',
          message: 'Trailing whitespace',
          severity: ValidationSeverity.warning,
          line: i + 1,
          column: line.length,
        ));
      }
    }
    
    return issues;
  }
  
  List<ValidationIssue> _validateLineLength(
    String content, List<String> lines, String? language) {
    final issues = <ValidationIssue>[];
    const maxLength = 120;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.length > maxLength) {
        issues.add(ValidationIssue(
          rule: 'line_length',
          message: 'Line exceeds ${maxLength} characters (${line.length})',
          severity: ValidationSeverity.info,
          line: i + 1,
          column: maxLength + 1,
        ));
      }
    }
    
    return issues;
  }
  
  void dispose() {
    _resultController.close();
  }
}

/// Validation rule definition
class ValidationRule {
  final String name;
  final String description;
  final List<ValidationIssue> Function(String content, List<String> lines, String? language) validator;
  final ValidationSeverity severity;
  
  ValidationRule({
    required this.name,
    required this.description,
    required this.validator,
    required this.severity,
  });
}

/// Validation result
class ValidationResult {
  final List<ValidationIssue> issues;
  final DateTime timestamp;
  final bool isValid;
  
  ValidationResult({
    required this.issues,
    required this.timestamp,
    required this.isValid,
  });
  
  int get errorCount => issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount => issues.where((i) => i.severity == ValidationSeverity.warning).length;
  int get infoCount => issues.where((i) => i.severity == ValidationSeverity.info).length;
}

/// Validation issue
class ValidationIssue {
  final String rule;
  final String message;
  final ValidationSeverity severity;
  final int? line;
  final int? column;
  
  ValidationIssue({
    required this.rule,
    required this.message,
    required this.severity,
    this.line,
    this.column,
  });
  
  ValidationIssue copyWith({
    String? rule,
    String? message,
    ValidationSeverity? severity,
    int? line,
    int? column,
  }) {
    return ValidationIssue(
      rule: rule ?? this.rule,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      line: line ?? this.line,
      column: column ?? this.column,
    );
  }
}

/// Validation severity levels
enum ValidationSeverity {
  error,
  warning,
  info,
}
