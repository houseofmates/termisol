import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Comprehensive Logging and Debugging System for Termisol
/// 
/// Features:
/// - Structured logging with multiple levels
/// - Performance monitoring and profiling
/// - Debug event tracking
/// - Log file rotation and compression
/// - Remote logging support
/// - Debug mode with enhanced details
class TermisolLogger {
  static const String _logDirectory = 'logs';
  static const int _maxLogFileSize = 10 * 1024 * 1024; // 10MB
  static const int _maxLogFiles = 5;
  static const Duration _flushInterval = Duration(seconds: 5);
  
  static final TermisolLogger _instance = TermisolLogger._internal();
  factory TermisolLogger() => _instance;
  TermisolLogger._internal();
  
  final List<LogSink> _sinks = [];
  final Map<String, PerformanceTracker> _performanceTrackers = {};
  final Map<String, DebugEvent> _debugEvents = {};
  final StreamController<LogEntry> _logStream = StreamController.broadcast();
  
  Timer? _flushTimer;
  bool _debugMode = false;
  String? _sessionId;
  
  /// Initialize the logging system
  Future<void> initialize({bool debugMode = false}) async {
    _debugMode = debugMode;
    _sessionId = _generateSessionId();
    
    // Create log directory
    await Directory(_logDirectory).create(recursive: true);
    
    // Add default sinks
    _sinks.add(ConsoleSink());
    _sinks.add(FileSink('$_logDirectory/termisol.log'));
    
    if (_debugMode) {
      _sinks.add(DebugSink());
    }
    
    // Start flush timer
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
    
    // Log initialization
    info('Logger initialized', {
      'debug_mode': _debugMode,
      'session_id': _sessionId,
      'sinks': _sinks.length,
    });
  }
  
  /// Dispose the logging system
  void dispose() {
    _flushTimer?.cancel();
    _flush();
    _logStream.close();
    
    for (final sink in _sinks) {
      sink.dispose();
    }
    _sinks.clear();
  }
  
  /// Log debug message
  void debug(String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.debug, message, context);
  }
  
  /// Log info message
  void info(String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.info, message, context);
  }
  
  /// Log warning message
  void warning(String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.warning, message, context);
  }
  
  /// Log error message
  void error(String message, [Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, context, error, stackTrace);
  }
  
  /// Log severe message (alias for error)
  void severe(String message, [Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, context, error, stackTrace);
  }

  /// Log fatal error
  void fatal(String message, [Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.fatal, message, context, error, stackTrace);
  }
  
  /// Start performance tracking
  void startPerformanceTracking(String operation) {
    _performanceTrackers[operation] = PerformanceTracker(operation);
  }
  
  /// End performance tracking and log result
  void endPerformanceTracking(String operation, [Map<String, dynamic>? context]) {
    final tracker = _performanceTrackers[operation];
    if (tracker != null) {
      final duration = tracker.end();
      
      info('Performance: $operation completed', {
        'duration_ms': duration.inMilliseconds,
        'duration_us': duration.inMicroseconds,
        'operation': operation,
        ...?context,
      });
      
      _performanceTrackers.remove(operation);
    }
  }
  
  /// Track a debug event
  void trackDebugEvent(String eventName, [Map<String, dynamic>? data]) {
    if (!_debugMode) return;
    
    final event = DebugEvent(eventName, data);
    _debugEvents[eventName] = event;
    
    debug('Debug Event: $eventName', data);
  }
  
  /// Log terminal protocol event
  void logProtocolEvent(String sequence, String type, [Map<String, dynamic>? context]) {
    debug('Protocol Event: $type', {
      'sequence': sequence.length > 100 ? '${sequence.substring(0, 100)}...' : sequence,
      'type': type,
      'length': sequence.length,
      ...?context,
    });
  }
  
  /// Log quantum engine event
  void logQuantumEvent(String operation, [Map<String, dynamic>? context]) {
    info('Quantum Event: $operation', {
      'operation': operation,
      'timestamp': DateTime.now().toIso8601String(),
      ...?context,
    });
  }
  
  /// Log performance metrics
  void logPerformanceMetrics(Map<String, dynamic> metrics) {
    info('Performance Metrics', metrics);
  }
  
  /// Log user interaction
  void logUserInteraction(String action, [Map<String, dynamic>? context]) {
    debug('User Interaction: $action', context);
  }
  
  /// Get log stream for real-time monitoring
  Stream<LogEntry> get logStream => _logStream.stream;
  
  /// Get debug events
  Map<String, DebugEvent> get debugEvents => Map.unmodifiable(_debugEvents);
  
  /// Get performance summary
  Map<String, dynamic> getPerformanceSummary() {
    return {
      'active_trackers': _performanceTrackers.length,
      'debug_events': _debugEvents.length,
      'debug_mode': _debugMode,
      'session_id': _sessionId,
    };
  }
  
  /// Internal logging method
  void _log(LogLevel level, String message, 
    [Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace]) {
    
    final entry = LogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      context: context ?? {},
      error: error,
      stackTrace: stackTrace,
      sessionId: _sessionId,
    );
    
    // Add to all sinks
    for (final sink in _sinks) {
      sink.write(entry);
    }
    
    // Add to stream
    _logStream.add(entry);
    
    // In debug mode, also send to Flutter developer log
    if (_debugMode) {
      developer.log(
        message,
        time: entry.timestamp,
        level: level.value,
        name: 'Termisol',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  
  /// Flush all sinks
  void _flush() {
    for (final sink in _sinks) {
      sink.flush();
    }
  }
  
  /// Generate session ID
  String _generateSessionId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_randomString(8)}';
  }
  
  /// Generate random string
  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    
    for (int i = 0; i < length; i++) {
      buffer.write(chars[(random + i) % chars.length]);
    }
    
    return buffer.toString();
  }
}

/// Log levels
enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  fatal(4);
  
  const LogLevel(this.value);
  final int value;
  
  String get name => toString().split('.').last.toUpperCase();
}

/// Log entry
class LogEntry {
  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> context;
  final dynamic error;
  final StackTrace? stackTrace;
  final String? sessionId;
  
  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    required this.context,
    this.error,
    this.stackTrace,
    this.sessionId,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
      'error': error?.toString(),
      'stack_trace': stackTrace?.toString(),
      'session_id': sessionId,
    };
  }
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} [${level.name}] $message');
    
    if (context.isNotEmpty) {
      buffer.write(' | Context: ${jsonEncode(context)}');
    }
    
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    
    if (stackTrace != null) {
      buffer.write('\nStack Trace:\n$stackTrace');
    }
    
    return buffer.toString();
  }
}

/// Log sink interface
abstract class LogSink {
  void write(LogEntry entry);
  void flush();
  void dispose();
}

/// Console log sink
class ConsoleSink implements LogSink {
  @override
  void write(LogEntry entry) {
    final color = _getColorForLevel(entry.level);
    print('$color${entry.toString()}$ansiReset');
  }
  
  @override
  void flush() {
    // Nothing to flush for console
  }
  
  @override
  void dispose() {
    // Nothing to dispose for console
  }
  
  String _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return ansiGray;
      case LogLevel.info:
        return ansiBlue;
      case LogLevel.warning:
        return ansiYellow;
      case LogLevel.error:
        return ansiRed;
      case LogLevel.fatal:
        return ansiMagenta;
    }
  }
  
  static const String ansiReset = '\x1b[0m';
  static const String ansiGray = '\x1b[90m';
  static const String ansiBlue = '\x1b[94m';
  static const String ansiYellow = '\x1b[93m';
  static const String ansiRed = '\x1b[91m';
  static const String ansiMagenta = '\x1b[95m';
}

/// File log sink with rotation
class FileSink implements LogSink {
  late File _file;
  late IOSink _sink;
  int _currentSize = 0;
  
  FileSink(String filePath) {
    _file = File(filePath);
    _initializeFile();
  }
  
  void _initializeFile() {
    if (_file.existsSync()) {
      _currentSize = _file.lengthSync();
      
      // Rotate if file is too large
      if (_currentSize > TermisolLogger._maxLogFileSize) {
        _rotateLog();
      }
    }
    
    _sink = _file.openWrite(mode: FileMode.append);
  }
  
  @override
  void write(LogEntry entry) {
    final line = '${entry.toJson()}\n';
    _sink.write(line);
    _currentSize += line.length;
    
    // Rotate if needed
    if (_currentSize > TermisolLogger._maxLogFileSize) {
      _rotateLog();
    }
  }
  
  @override
  void flush() {
    _sink.flush();
  }
  
  @override
  void dispose() {
    _sink.close();
  }
  
  void _rotateLog() {
    _sink.close();
    
    // Move current file to backup
    final backupFile = File('${_file.path}.1');
    if (backupFile.existsSync()) {
      backupFile.deleteSync();
    }
    _file.renameSync(backupFile.path);
    
    // Create new file
    _file = File(_file.path);
    _currentSize = 0;
    _sink = _file.openWrite(mode: FileMode.append);
  }
}

/// Debug sink for enhanced debugging
class DebugSink implements LogSink {
  final List<LogEntry> _entries = [];
  static const int _maxEntries = 1000;
  
  @override
  void write(LogEntry entry) {
    _entries.add(entry);
    
    // Keep only recent entries
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }
  
  @override
  void flush() {
    // Nothing to flush for debug sink
  }
  
  @override
  void dispose() {
    _entries.clear();
  }
  
  List<LogEntry> get entries => List.unmodifiable(_entries);
  
  /// Get entries by level
  List<LogEntry> getEntriesByLevel(LogLevel level) {
    return _entries.where((e) => e.level == level).toList();
  }
  
  /// Get entries by time range
  List<LogEntry> getEntriesByTimeRange(DateTime start, DateTime end) {
    return _entries.where((e) => 
      e.timestamp.isAfter(start) && e.timestamp.isBefore(end)
    ).toList();
  }
}

/// Performance tracker
class PerformanceTracker {
  final String operation;
  final Stopwatch _stopwatch;
  
  PerformanceTracker(this.operation) : _stopwatch = Stopwatch()..start();
  
  Duration end() {
    _stopwatch.stop();
    return _stopwatch.elapsed;
  }
}

/// Debug event
class DebugEvent {
  final String name;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  DebugEvent(this.name, this.data) : timestamp = DateTime.now();
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Debug utilities
class DebugUtils {
  static void logMemoryUsage(String context) {
    if (!kDebugMode) return;
    
    // Note: In a real implementation, you would use platform-specific APIs
    // to get actual memory usage. This is a placeholder.
    TermisolLogger().debug('Memory usage: $context', {
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  static void logFunctionCall(String functionName, [Map<String, dynamic>? args]) {
    if (!kDebugMode) return;
    
    TermisolLogger().trackDebugEvent('function_call', {
      'function': functionName,
      'args': args,
    });
  }
  
  static void logStateChange(String component, String fromState, String toState) {
    if (!kDebugMode) return;
    
    TermisolLogger().trackDebugEvent('state_change', {
      'component': component,
      'from_state': fromState,
      'to_state': toState,
    });
  }
  
  static void logUserAction(String action, [Map<String, dynamic>? details]) {
    TermisolLogger().logUserInteraction(action, details);
  }
  
  static void logErrorWithContext(String error, String context, [Map<String, dynamic>? additional]) {
    TermisolLogger().severe(error, {
      'context': context,
      ...?additional,
    });
  }
  
  static void logPerformanceWithThreshold(String operation, Duration threshold, Function() operationToMeasure) {
    final logger = TermisolLogger();
    logger.startPerformanceTracking(operation);
    
    try {
      operationToMeasure();
    } finally {
      logger.endPerformanceTracking(operation, {
        'threshold_ms': threshold.inMilliseconds,
      });
    }
  }
}

/// Global logger instance
final logger = TermisolLogger();

/// Extension methods for easy logging
extension LoggerExtensions on Object {
  void logDebug(String message, [Map<String, dynamic>? context]) {
    logger.debug('$runtimeType: $message', context);
  }
  
  void logInfo(String message, [Map<String, dynamic>? context]) {
    logger.info('$runtimeType: $message', context);
  }
  
  void logWarning(String message, [Map<String, dynamic>? context]) {
    logger.warning('$runtimeType: $message', context);
  }
  
  void logError(String message, [Map<String, dynamic>? context, dynamic error, StackTrace? stackTrace]) {
    logger.severe('$runtimeType: $message', context, error, stackTrace);
  }
}
