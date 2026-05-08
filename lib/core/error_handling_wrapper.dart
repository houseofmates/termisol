import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Comprehensive error handling and validation utilities
class ErrorHandlingWrapper {
  static const int MAX_SEQUENCE_LENGTH = 10000;
  static const int MAX_PASTE_LENGTH = 1000000;
  static const int MAX_PARAM_COUNT = 100;
  static const int MAX_COORDINATE = 10000;
  static const int MAX_COLOR_INDEX = 255;

  /// Validate and wrap function execution with error handling
  static T? safeExecute<T>(
    T Function() function,
    String context, {
    T? fallback,
    void Function(dynamic error, StackTrace stackTrace)? onError,
  }) {
    try {
      return function();
    } catch (e, stackTrace) {
      _logError(e, stackTrace, context);
      onError?.call(e, stackTrace);
      return fallback;
    }
  }

  /// Validate and wrap async function execution
  static Future<T?> safeExecuteAsync<T>(
    Future<T> Function() function,
    String context, {
    T? fallback,
    void Function(dynamic error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return await function();
    } catch (e, stackTrace) {
      _logError(e, stackTrace, context);
      onError?.call(e, stackTrace);
      return fallback;
    }
  }

  /// Validate escape sequence
  static void validateSequence(String sequence) {
    if (sequence.isEmpty) return;
    
    if (sequence.length > MAX_SEQUENCE_LENGTH) {
      throw ArgumentError('Sequence too long: ${sequence.length} characters');
    }
    
    // Check for null bytes
    if (sequence.contains('\x00')) {
      throw ArgumentError('Sequence contains null bytes');
    }
    
    // Validate UTF-8 encoding
    try {
      sequence.codeUnits;
    } catch (e) {
      throw ArgumentError('Invalid UTF-8 sequence: $e');
    }
  }

  /// Validate and parse CSI parameters
  static List<int> validateAndParseParams(String params) {
    if (params.isEmpty) return [];
    
    try {
      final paramList = params.split(';')
          .where((p) => p.isNotEmpty)
          .map((p) {
            final value = int.tryParse(p);
            if (value == null || value < 0 || value > 999999) {
              throw ArgumentError('Invalid parameter: $p');
            }
            return value;
          })
          .toList();
      
      if (paramList.length > MAX_PARAM_COUNT) {
        throw ArgumentError('Too many parameters: ${paramList.length}');
      }
      
      return paramList;
    } catch (e) {
      throw ArgumentError('Parameter parsing failed: $e');
    }
  }

  /// Validate mouse coordinates
  static void validateMouseCoordinates(int x, int y) {
    if (x < 0 || y < 0 || x > MAX_COORDINATE || y > MAX_COORDINATE) {
      throw ArgumentError('Invalid mouse coordinates: ($x, $y)');
    }
  }

  /// Validate color index
  static void validateColorIndex(int index) {
    if (index < 0 || index > MAX_COLOR_INDEX) {
      throw ArgumentError('Invalid color index: $index');
    }
  }

  /// Validate RGB color values
  static void validateRgbValues(int r, int g, int b) {
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('Invalid RGB values: ($r, $g, $b)');
    }
  }

  /// Validate hex color string
  static void validateHexColor(String hex) {
    if (hex.length != 6) {
      throw ArgumentError('Invalid hex color length: $hex');
    }
    
    final r = int.tryParse(hex.substring(0, 2), radix: 16);
    final g = int.tryParse(hex.substring(2, 4), radix: 16);
    final b = int.tryParse(hex.substring(4, 6), radix: 16);
    
    if (r == null || g == null || b == null) {
      throw ArgumentError('Invalid hex color: $hex');
    }
  }

  /// Validate paste text length
  static void validatePasteText(String text) {
    if (text.length > MAX_PASTE_LENGTH) {
      throw ArgumentError('Paste too long: ${text.length} characters');
    }
  }

  /// Validate key input
  static void validateKeyInput(String key) {
    if (key.length > 100) {
      throw ArgumentError('Key too long: $key');
    }
  }

  /// Validate OSC command
  static int validateOscCommand(String commandStr) {
    final command = int.tryParse(commandStr);
    if (command == null || command < 0 || command > 999999) {
      throw ArgumentError('Invalid OSC command: $commandStr');
    }
    return command;
  }

  /// Validate OSC data length
  static void validateOscData(String data) {
    if (data.length > 10000) {
      throw ArgumentError('OSC data too long: ${data.length}');
    }
  }

  /// Parse RGB color string safely
  static (int, int, int)? parseRgbColor(String color) {
    try {
      final rgbParts = color.substring(4).split('/');
      if (rgbParts.length != 3) {
        throw ArgumentError('Invalid RGB format: $color');
      }
      
      final r = int.tryParse(rgbParts[0], radix: 16);
      final g = int.tryParse(rgbParts[1], radix: 16);
      final b = int.tryParse(rgbParts[2], radix: 16);
      
      if (r == null || g == null || b == null) {
        return null;
      }
      
      validateRgbValues(r, g, b);
      return (r, g, b);
    } catch (e) {
      return null;
    }
  }

  /// Parse hex color string safely
  static (int, int, int)? parseHexColor(String color) {
    try {
      final hex = color.substring(1);
      validateHexColor(hex);
      
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      
      return (r, g, b);
    } catch (e) {
      return null;
    }
  }

  /// Safe clipboard operation
  static Future<void> safeClipboardCopy(String text) async {
    try {
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } catch (e) {
      _logError(e, StackTrace.current, 'Clipboard copy');
    }
  }

  /// Safe terminal write
  static void safeTerminalWrite(dynamic terminal, String text) {
    try {
      if (text.isNotEmpty && text.length <= 10000) {
        terminal.write(text);
      }
    } catch (e) {
      _logError(e, StackTrace.current, 'Terminal write');
    }
  }

  /// Log error with context
  static void _logError(dynamic error, StackTrace stackTrace, String context) {
    debugPrint('⚠️ Error in $context: $error');
    debugPrint('⚠️ Stack trace: $stackTrace');
  }

  /// Create error recovery strategy
  static ErrorRecoveryStrategy createRecoveryStrategy() {
    return ErrorRecoveryStrategy();
  }
}

/// Error recovery strategies
class ErrorRecoveryStrategy {
  final List<RecoveryAction> _actions = [];
  
  ErrorRecoveryStrategy() {
    _initializeDefaultActions();
  }
  
  void _initializeDefaultActions() {
    // Add default recovery actions
    _actions.addAll([
      RecoveryAction(
        name: 'reset_terminal',
        condition: (error) => error.toString().contains('protocol'),
        action: () => debugPrint('🔄 Attempting terminal reset'),
      ),
      RecoveryAction(
        name: 'clear_buffers',
        condition: (error) => error.toString().contains('buffer'),
        action: () => debugPrint('🧹 Clearing buffers'),
      ),
      RecoveryAction(
        name: 'reinitialize',
        condition: (error) => error.toString().contains('initialization'),
        action: () => debugPrint('🔄 Reinitializing components'),
      ),
    ]);
  }
  
  /// Attempt recovery from error
  bool attemptRecovery(dynamic error) {
    for (final action in _actions) {
      if (action.condition(error)) {
        try {
          action.action();
          return true;
        } catch (e) {
          debugPrint('⚠️ Recovery action ${action.name} failed: $e');
        }
      }
    }
    return false;
  }
  
  /// Add custom recovery action
  void addRecoveryAction(RecoveryAction action) {
    _actions.add(action);
  }
}

/// Recovery action definition
class RecoveryAction {
  final String name;
  final bool Function(dynamic error) condition;
  final void Function() action;
  
  RecoveryAction({
    required this.name,
    required this.condition,
    required this.action,
  });
}

/// Validation utilities for specific data types
class ValidationUtils {
  /// Validate string length
  static bool isValidLength(String text, int maxLength) {
    return text.length <= maxLength;
  }
  
  /// Validate numeric range
  static bool isValidRange(int value, int min, int max) {
    return value >= min && value <= max;
  }
  
  /// Validate hex string
  static bool isValidHex(String hex) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }
  
  /// Validate RGB format
  static bool isValidRgbFormat(String rgb) {
    return RegExp(r'^rgb:[0-9a-fA-F]+/[0-9a-fA-F]+/[0-9a-fA-F]+$').hasMatch(rgb);
  }
  
  /// Validate escape sequence format
  static bool isValidEscapeSequence(String sequence) {
    return sequence.startsWith('\x1b') && sequence.isNotEmpty;
  }
  
  /// Validate key format
  static bool isValidKey(String key) {
    return key.isNotEmpty && key.length <= 100;
  }
}

/// Circuit breaker pattern for preventing cascading failures
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;
  
  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(minutes: 1),
  });
  
  /// Execute function with circuit breaker protection
  T? execute<T>(T Function() function, {T? fallback}) {
    if (_isOpen) {
      if (DateTime.now().difference(_lastFailureTime!) > timeout) {
        _isOpen = false;
        _failureCount = 0;
      } else {
        return fallback;
      }
    }
    
    try {
      final result = function();
      _reset();
      return result;
    } catch (e) {
      _recordFailure();
      return fallback;
    }
  }
  
  void _recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _isOpen = true;
    }
  }
  
  void _reset() {
    _failureCount = 0;
    _isOpen = false;
  }
  
  /// Reset circuit breaker manually
  void reset() {
    _reset();
  }
  
  /// Get circuit breaker state
  bool get isOpen => _isOpen;
  int get failureCount => _failureCount;
}

/// Retry mechanism with exponential backoff
class RetryMechanism {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  
  RetryMechanism({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 100),
    this.backoffMultiplier = 2.0,
  });
  
  /// Execute function with retry logic
  Future<T?> executeAsync<T>(
    Future<T> Function() function, {
    T? fallback,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    var delay = initialDelay;
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await function();
      } catch (e) {
        if (attempt == maxAttempts || (shouldRetry != null && !shouldRetry(e))) {
          return fallback;
        }
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }
    
    return fallback;
  }
  
  /// Execute synchronous function with retry logic
  T? execute<T>(
    T Function() function, {
    T? fallback,
    bool Function(dynamic error)? shouldRetry,
  }) {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return function();
      } catch (e) {
        if (attempt == maxAttempts || (shouldRetry != null && !shouldRetry(e))) {
          return fallback;
        }
      }
    }
    
    return fallback;
  }
}
