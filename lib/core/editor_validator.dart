import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Editor Input Validator and Sanitizer
/// 
/// Comprehensive validation and sanitization for text editor input
/// to ensure security, performance, and stability for production use.
class EditorValidator {
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  static const int maxLineLength = 10000;
  static const int maxLineCount = 100000;
  static const int maxInputLength = 1000;
  static const int maxCursorCount = 100;
  
  // Security validation patterns
  static final RegExp _dangerousPatterns = RegExp(r'''
    (?:<script[^>]*>.*?</script>)|           # Script tags
    (?:javascript:)|                         # JavaScript URLs
    (?:on\w+\s*=)                            # Event handlers
  ''', caseSensitive: false, multiLine: true, dotAll: true);
  
  static final RegExp _controlCharacters = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
  static final RegExp _validUnicode = RegExp(r'^[\p{L}\p{N}\p{P}\p{S}\p{Z}\p{M}\p{C}]*$', unicode: true);
  
  /// Validate file content before loading
  static ValidationResult validateFileContent(String filePath, String content) {
    try {
      // Check file size
      if (content.length > maxFileSize) {
        return ValidationResult(
          isValid: false,
          error: 'File too large: ${content.length} bytes (max: $maxFileSize)',
          type: ValidationType.fileSize,
        );
      }
      
      // Check line count
      final lineCount = content.split('\n').length;
      if (lineCount > maxLineCount) {
        return ValidationResult(
          isValid: false,
          error: 'Too many lines: $lineCount (max: $maxLineCount)',
          type: ValidationType.lineCount,
        );
      }
      
      // Check for excessively long lines
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].length > maxLineLength) {
          return ValidationResult(
            isValid: false,
            error: 'Line ${i + 1} too long: ${lines[i].length} characters (max: $maxLineLength)',
            type: ValidationType.lineLength,
          );
        }
      }
      
      // Check for dangerous content
      if (_containsDangerousContent(content)) {
        return ValidationResult(
          isValid: false,
          error: 'File contains potentially dangerous content',
          type: ValidationType.security,
        );
      }
      
      // Validate encoding
      if (!_isValidEncoding(content)) {
        return ValidationResult(
          isValid: false,
          error: 'File contains invalid character encoding',
          type: ValidationType.encoding,
        );
      }
      
      return ValidationResult(isValid: true);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: 'Error validating file: $e',
        type: ValidationType.system,
      );
    }
  }
  
  /// Validate and sanitize user input
  static ValidationResult validateInput(String input, {bool allowMultiLine = true}) {
    try {
      if (input.isEmpty) {
        return ValidationResult(isValid: true);
      }
      
      // Check input length
      if (input.length > maxInputLength) {
        return ValidationResult(
          isValid: false,
          error: 'Input too long: ${input.length} characters (max: $maxInputLength)',
          type: ValidationType.inputLength,
        );
      }
      
      // Check for control characters (except newlines if allowed)
      final controlChars = allowMultiLine 
        ? _controlCharacters
        : RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\n\r]');
      
      if (controlChars.hasMatch(input)) {
        return ValidationResult(
          isValid: false,
          error: 'Input contains invalid control characters',
          type: ValidationType.controlChars,
        );
      }
      
      // Sanitize dangerous patterns
      final sanitized = _sanitizeInput(input);
      if (sanitized != input) {
        return ValidationResult(
          isValid: false,
          error: 'Input contains potentially dangerous content',
          type: ValidationType.security,
          sanitizedContent: sanitized,
        );
      }
      
      return ValidationResult(isValid: true, sanitizedContent: input);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: 'Error validating input: $e',
        type: ValidationType.system,
      );
    }
  }
  
  /// Validate cursor position
  static ValidationResult validateCursorPosition(int offset, int textLength) {
    if (offset < 0) {
      return ValidationResult(
        isValid: false,
        error: 'Cursor position cannot be negative: $offset',
        type: ValidationType.cursorPosition,
      );
    }
    
    if (offset > textLength) {
      return ValidationResult(
        isValid: false,
        error: 'Cursor position beyond text: $offset > $textLength',
        type: ValidationType.cursorPosition,
      );
    }
    
    return ValidationResult(isValid: true);
  }
  
  /// Validate multi-cursor setup
  static ValidationResult validateMultiCursorSetup(List<int> cursorOffsets, int textLength) {
    if (cursorOffsets.isEmpty) {
      return ValidationResult(isValid: true);
    }
    
    // Check cursor count limit
    if (cursorOffsets.length > maxCursorCount) {
      return ValidationResult(
        isValid: false,
        error: 'Too many cursors: ${cursorOffsets.length} (max: $maxCursorCount)',
        type: ValidationType.cursorCount,
      );
    }
    
    // Validate each cursor position
    for (int i = 0; i < cursorOffsets.length; i++) {
      final offset = cursorOffsets[i];
      final result = validateCursorPosition(offset, textLength);
      if (!result.isValid) {
        return ValidationResult(
          isValid: false,
          error: 'Cursor ${i + 1}: ${result.error}',
          type: ValidationType.cursorPosition,
        );
      }
    }
    
    // Check for duplicate positions
    final uniqueOffsets = cursorOffsets.toSet();
    if (uniqueOffsets.length != cursorOffsets.length) {
      return ValidationResult(
        isValid: false,
        error: 'Duplicate cursor positions detected',
        type: ValidationType.cursorPosition,
      );
    }
    
    return ValidationResult(isValid: true);
  }
  
  /// Validate text operation (insert/delete)
  static ValidationResult validateTextOperation(String operation, String text, int offset, {String? content}) {
    try {
      // Validate operation type
      if (!['insert', 'delete', 'replace'].contains(operation)) {
        return ValidationResult(
          isValid: false,
          error: 'Invalid operation type: $operation',
          type: ValidationType.operation,
        );
      }
      
      // Validate offset
      final offsetResult = validateCursorPosition(offset, text.length);
      if (!offsetResult.isValid) {
        return offsetResult;
      }
      
      // Validate content for insert/replace operations
      if (operation == 'insert' || operation == 'replace') {
        if (content == null) {
          return ValidationResult(
            isValid: false,
            error: 'Content required for $operation operation',
            type: ValidationType.operation,
          );
        }
        
        final contentResult = validateInput(content, allowMultiLine: true);
        if (!contentResult.isValid) {
          return ValidationResult(
            isValid: false,
            error: 'Invalid content for $operation: ${contentResult.error}',
            type: ValidationType.operation,
          );
        }
      }
      
      // Check if operation would result in oversized file
      int newSize = text.length;
      switch (operation) {
        case 'insert':
          newSize += content?.length ?? 0;
          break;
        case 'delete':
          // Assume single character deletion for simplicity
          newSize -= 1;
          break;
        case 'replace':
          newSize = newSize - 1 + (content?.length ?? 0);
          break;
      }
      
      if (newSize > maxFileSize) {
        return ValidationResult(
          isValid: false,
          error: 'Operation would exceed maximum file size: $newSize > $maxFileSize',
          type: ValidationType.fileSize,
        );
      }
      
      return ValidationResult(isValid: true);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: 'Error validating operation: $e',
        type: ValidationType.system,
      );
    }
  }
  
  /// Check if content contains dangerous patterns
  static bool _containsDangerousContent(String content) {
    return _dangerousPatterns.hasMatch(content);
  }
  
  /// Validate character encoding
  static bool _isValidEncoding(String content) {
    try {
      // Try to encode as UTF-8 and decode back
      final encoded = utf8.encode(content);
      final decoded = utf8.decode(encoded);
      return decoded == content;
    } catch (e) {
      return false;
    }
  }
  
  /// Sanitize input by removing dangerous patterns
  static String _sanitizeInput(String input) {
    String sanitized = input;
    
    // Remove script tags
    sanitized = sanitized.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    
    // Remove JavaScript URLs
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    
    // Remove event handlers
    sanitized = sanitized.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return sanitized;
  }
  
  /// Validate file path
  static ValidationResult validateFilePath(String filePath) {
    try {
      final file = File(filePath);
      
      // Check if file exists
      if (!file.existsSync()) {
        return ValidationResult(
          isValid: false,
          error: 'File does not exist: $filePath',
          type: ValidationType.filePath,
        );
      }
      
      // Check file size
      final fileSize = file.lengthSync();
      if (fileSize > maxFileSize) {
        return ValidationResult(
          isValid: false,
          error: 'File too large: ${fileSize} bytes (max: $maxFileSize)',
          type: ValidationType.fileSize,
        );
      }
      
      // Check file extension for known dangerous types
      final dangerousExtensions = ['.exe', '.bat', '.cmd', '.scr', '.pif', '.com'];
      final extension = filePath.toLowerCase().split('.').last;
      if (dangerousExtensions.contains('.$extension')) {
        return ValidationResult(
          isValid: false,
          error: 'Dangerous file type: .$extension',
          type: ValidationType.security,
        );
      }
      
      return ValidationResult(isValid: true);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        error: 'Error validating file path: $e',
        type: ValidationType.system,
      );
    }
  }
  
  /// Performance validation for large operations
  static ValidationResult validatePerformance(int operationCount, int textLength) {
    // Check if operation would be too expensive
    if (operationCount > 1000) {
      return ValidationResult(
        isValid: false,
        error: 'Too many operations: $operationCount (max: 1000)',
        type: ValidationType.performance,
      );
    }
    
    // Check if text is too large for complex operations
    if (textLength > 1000000 && operationCount > 100) {
      return ValidationResult(
        isValid: false,
        error: 'Complex operations on large text not recommended',
        type: ValidationType.performance,
      );
    }
    
    return ValidationResult(isValid: true);
  }
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;
  final ValidationType type;
  final String? sanitizedContent;
  
  const ValidationResult({
    required this.isValid,
    this.error,
    this.type = ValidationType.general,
    this.sanitizedContent,
  });
  
  @override
  String toString() {
    if (isValid) {
      return 'Valid';
    } else {
      return 'Invalid: $error (${type.name})';
    }
  }
}

/// Validation types
enum ValidationType {
  general,
  fileSize,
  lineCount,
  lineLength,
  inputLength,
  controlChars,
  security,
  encoding,
  cursorPosition,
  cursorCount,
  operation,
  filePath,
  performance,
  system,
}

/// Input sanitizer for various contexts
class InputSanitizer {
  /// Sanitize for display (remove control chars)
  static String forDisplay(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  }
  
  /// Sanitize for storage (preserve newlines, remove other controls)
  static String forStorage(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  }
  
  /// Sanitize for search (normalize whitespace)
  static String forSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  /// Sanitize file name
  static String fileName(String input) {
    // Remove invalid filename characters
    return input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  }
  
  /// Sanitize for JSON output
  static String forJson(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}

/// Performance monitor for editor operations
class EditorPerformanceMonitor {
  static const Duration warningThreshold = Duration(milliseconds: 100);
  static const Duration errorThreshold = Duration(milliseconds: 500);
  
  static T measureOperation<T>(String operationName, T Function() operation) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = operation();
      stopwatch.stop();
      
      final duration = stopwatch.elapsed;
      if (duration > errorThreshold) {
        debugPrint('🚨 Slow operation: $operationName took ${duration.inMilliseconds}ms');
      } else if (duration > warningThreshold) {
        debugPrint('⚠️ Slow operation: $operationName took ${duration.inMilliseconds}ms');
      }
      
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Failed operation: $operationName after ${stopwatch.elapsed.inMilliseconds}ms');
      rethrow;
    }
  }
  
  static Future<T> measureAsyncOperation<T>(String operationName, Future<T> Function() operation) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await operation();
      stopwatch.stop();
      
      final duration = stopwatch.elapsed;
      if (duration > errorThreshold) {
        debugPrint('🚨 Slow async operation: $operationName took ${duration.inMilliseconds}ms');
      } else if (duration > warningThreshold) {
        debugPrint('⚠️ Slow async operation: $operationName took ${duration.inMilliseconds}ms');
      }
      
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Failed async operation: $operationName after ${stopwatch.elapsed.inMilliseconds}ms');
      rethrow;
    }
  }
}
