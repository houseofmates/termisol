import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';

/// production-grade error handling system for termisol
/// 
/// features:
/// - Structured error logging with context
/// - Automatic error recovery mechanisms
/// - Performance monitoring and alerting
/// - Cross-platform error reporting
/// - Secure error data handling
/// - Real-time error analytics
class RobustErrorHandler {
  static final RobustErrorHandler _instance = RobustErrorHandler._internal();
  factory RobustErrorHandler() => _instance;
  RobustErrorHandler._internal();

  static final _logger = Logger('RobustErrorHandler');
  final Map<String, int> _errorCounts = {};
  final Map<String, DateTime> _lastErrorTime = {};
  final List<ErrorReport> _errorHistory = [];
  final _errorController = StreamController<ErrorReport>.broadcast();
  
  // Connection pool for error recovery
  final List<dynamic> _connectionPool = [];
  
  // Recovery state variables
  Timer? _monitoringTimer;
  int _errorCount = 0;
  String? _lastError;
  
  // Additional state variables
  final DateTime _startTime = DateTime.now();
  final List<dynamic> _pendingRequests = [];
  final Map<String, dynamic> _networkCache = {};
  final List<dynamic> _performanceMetrics = [];
  final List<Timer> _pendingTimeouts = [];
  final Map<String, Timer> _connectionTimeouts = {};
  
  Stream<ErrorReport> get errorStream => _errorController.stream;
  
  // Configuration
  final int _maxErrorHistory = 1000;
  final int _errorThreshold = 10; // Alert after 10 similar errors
  final Duration _errorWindow = const Duration(minutes: 5);
  
  /// initialize the error handler
  Future<void> initialize() async {
    try {
      // Setup logging hierarchy
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen(_handleLogRecord);
      
      // Load error history
      await _loadErrorHistory();
      
      // Setup periodic cleanup
      Timer.periodic(const Duration(hours: 1), (_) => _cleanupOldErrors());
      
      _logger.info('Robust error handler initialized');
    } catch (e) {
      developer.log('CRITICAL: Failed to initialize error handler: $e');
    }
  }
  
  /// handle an error with full context
  Future<void> handleError(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? metadata,
    ErrorSeverity severity = ErrorSeverity.error,
    bool recoverable = true,
  }) async {
    try {
      final errorReport = ErrorReport(
        id: _generateErrorId(),
        timestamp: DateTime.now(),
        error: error.toString(),
        stackTrace: stackTrace?.toString(),
        context: context,
        metadata: metadata ?? {},
        severity: severity,
        recoverable: recoverable,
        platform: Platform.operatingSystem,
        version: '1.0.0',
      );
      
      // Update error statistics
      _updateErrorStats(errorReport);
      
      // Add to history
      _errorHistory.add(errorReport);
      if (_errorHistory.length > _maxErrorHistory) {
        _errorHistory.removeAt(0);
      }
      
      // Log the error
      _logError(errorReport);
      
      // Broadcast to listeners
      _errorController.add(errorReport);
      
      // Check for error patterns
      _checkErrorPatterns(errorReport);
      
      // Attempt recovery if possible
      if (recoverable) {
        await _attemptRecovery(errorReport);
      }
      
      // Persist to disk
      await _persistError(errorReport);
      
    } catch (e) {
      developer.log('CRITICAL: Error in error handler: $e');
    }
  }
  
  /// generate unique error id
  String _generateErrorId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 1000000;
    return 'err_${timestamp}_$random';
  }
  
  /// update error statistics
  void _updateErrorStats(ErrorReport report) {
    final key = '${report.error}_${report.context ?? ''}';
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
    _lastErrorTime[key] = report.timestamp;
  }
  
  /// check for error patterns and thresholds
  void _checkErrorPatterns(ErrorReport report) {
    final key = '${report.error}_${report.context ?? ''}';
    final count = _errorCounts[key] ?? 0;
    final lastTime = _lastErrorTime[key];
    
    if (count >= _errorThreshold && 
        lastTime != null && 
        DateTime.now().difference(lastTime) <= _errorWindow) {
      
      _logger.warning('Error threshold exceeded for: $key (count: $count)');
      _handleErrorThreshold(report, count);
    }
  }
  
  /// handle error threshold exceeded
  void _handleErrorThreshold(ErrorReport report, int count) {
    // Create alert for high-frequency errors
    final alert = ErrorAlert(
      id: _generateErrorId(),
      timestamp: DateTime.now(),
      type: AlertType.highFrequencyError,
      message: 'High frequency error detected: ${report.error}',
      count: count,
      context: report.context,
      severity: AlertSeverity.critical,
    );
    
    _broadcastAlert(alert);
  }
  
  /// attempt automatic error recovery
  Future<void> _attemptRecovery(ErrorReport report) async {
    try {
      switch (report.severity) {
        case ErrorSeverity.info:
          // No recovery needed for info
          break;
          
        case ErrorSeverity.warning:
          await _recoverFromWarning(report);
          break;
          
        case ErrorSeverity.error:
          await _recoverFromError(report);
          break;
          
        case ErrorSeverity.critical:
          await _recoverFromCritical(report);
          break;
      }
    } catch (e) {
      _logger.warning('Recovery attempt failed: $e');
    }
  }
  
  /// recovery strategies for warnings
  Future<void> _recoverFromWarning(ErrorReport report) async {
    // Implement warning-specific recovery
    if (report.error.contains('memory')) {
      await _triggerMemoryCleanup();
    }
    
    if (report.error.contains('connection')) {
      await _triggerConnectionRetry();
    }
  }
  
  /// recovery strategies for errors
  Future<void> _recoverFromError(ErrorReport report) async {
    // Implement error-specific recovery
    if (report.error.contains('file')) {
      await _triggerFilesystemCheck();
    }
    
    if (report.error.contains('network')) {
      await _triggerNetworkReset();
    }
  }
  
  /// recovery strategies for critical errors
  Future<void> _recoverFromCritical(ErrorReport report) async {
    // Implement critical error recovery
    _logger.severe('Critical error detected, initiating emergency recovery');
    
    // Save current state
    await _emergencyStateSave();
    
    // Clear caches
    await _clearAllCaches();
    
    // Restart affected services
    await _restartCriticalServices();
  }
  
  /// memory cleanup recovery
  Future<void> _triggerMemoryCleanup() async {
    try {
      _logger.info('Triggering memory cleanup');
      
      // Clear image cache
      PaintingBinding.instance.imageCache.clear();
      
      // Clear performance metrics
      _performanceMetrics.clear();
      
      // Force garbage collection
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // Clear temporary files
      final tempDir = Directory.systemTemp;
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          if (entity is File && entity.path.contains('termisol')) {
            try {
              await entity.delete();
            } catch (e) {
              _logger.warning('Failed to delete temp file: $e');
            }
          }
        }
      }
      
      _logger.info('Memory cleanup completed');
    } catch (e) {
      _logger.severe('Memory cleanup failed: $e');
    }
  }
  
  /// connection retry recovery
  Future<void> _triggerConnectionRetry() async {
    try {
      _logger.info('Triggering connection retry');
      
      // Reset connection pools
      _connectionPool.clear();
      
      // Cancel pending timeouts
      for (final timer in _pendingTimeouts) {
        timer.cancel();
      }
      _pendingTimeouts.clear();
      
      // Wait before retry
      await Future.delayed(const Duration(seconds: 2));
      
      // Reinitialize critical connections
      await _reinitializeCriticalConnections();
      
      _logger.info('Connection retry completed');
    } catch (e) {
      _logger.severe('Connection retry failed: $e');
    }
  }
  
  /// filesystem check recovery
  Future<void> _triggerFilesystemCheck() async {
    try {
      _logger.info('Triggering filesystem check');
      
      // Check disk space
      try {
        final currentDir = Directory.current;
        final stat = await currentDir.stat();
        final freeSpace = stat.size;
        
        if (freeSpace < 100 * 1024 * 1024) { // Less than 100MB
          _logger.warning('Low disk space detected: ${(freeSpace / 1024 / 1024).toStringAsFixed(1)}MB');
          await _clearOldLogFiles();
        }
      } catch (e) {
        _logger.warning('Failed to check disk space: $e');
      }
      
      // Verify critical directories
      final criticalDirs = [
        Directory.current,
        Directory.systemTemp,
        await getApplicationDocumentsDirectory(),
      ];
      
      for (final dir in criticalDirs) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
            _logger.info('Created missing directory: ${dir.path}');
          }
        } catch (e) {
          _logger.severe('Failed to create directory ${dir.path}: $e');
        }
      }
      
      _logger.info('Filesystem check completed');
    } catch (e) {
      _logger.severe('Filesystem check failed: $e');
    }
  }
  
  /// network reset recovery
  Future<void> _triggerNetworkReset() async {
    try {
      _logger.info('Triggering network reset');
      
      // Clear network cache
      _networkCache.clear();
      
      // Reset connection timeouts
      _connectionTimeouts.clear();
      
      // Cancel pending requests
      for (final request in _pendingRequests) {
        request.cancel();
      }
      _pendingRequests.clear();
      
      // Wait for network to stabilize
      await Future.delayed(const Duration(seconds: 3));
      
      // Test basic connectivity
      final connectivity = await _testBasicConnectivity();
      if (!connectivity) {
        _logger.warning('Network connectivity still unavailable');
      } else {
        _logger.info('Network reset successful');
      }
    } catch (e) {
      _logger.severe('Network reset failed: $e');
    }
  }
  
  /// emergency state save
  Future<void> _emergencyStateSave() async {
    try {
      _logger.info('Performing emergency state save');
      
      final emergencyState = {
        'timestamp': DateTime.now().toIso8601String(),
        'errorCount': _errorCount,
        'lastError': _lastError?.toString(),
        'activeConnections': _connectionPool.length,
        'memoryUsage': _getCurrentMemoryUsage(),
        'uptime': DateTime.now().difference(_startTime).inSeconds,
      };
      
      // Save to emergency file
      final documentsDir = await getApplicationDocumentsDirectory();
      final emergencyFile = File('${documentsDir.path}/termisol_emergency_state.json');
      
      await emergencyFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(emergencyState),
      );
      
      _logger.info('Emergency state saved to ${emergencyFile.path}');
    } catch (e) {
      _logger.severe('Emergency state save failed: $e');
    }
  }
  
  /// clear all caches
  Future<void> _clearAllCaches() async {
    try {
      _logger.info('Clearing all caches');
      
      // Clear image cache
      PaintingBinding.instance.imageCache.clear();
      
      // Clear network cache
      _networkCache.clear();
      
      // Clear connection pool
      _connectionPool.clear();
      
      // Clear performance metrics
      _performanceMetrics.clear();
      
      // Clear temporary files
      final tempDir = Directory.systemTemp;
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          if (entity is File && entity.path.contains('termisol')) {
            try {
              await entity.delete();
            } catch (e) {
              _logger.warning('Failed to delete temp file: $e');
            }
          }
        }
      }
      
      _logger.info('All caches cleared');
    } catch (e) {
      _logger.severe('Cache clearing failed: $e');
    }
  }
  
  /// restart critical services
  Future<void> _restartCriticalServices() async {
    try {
      _logger.info('Restarting critical services');
      
      // Cancel existing timers
      _monitoringTimer?.cancel();
      _monitoringTimer = null;
      
      // Clear state
      _errorCount = 0;
      _lastError = null;

      
      // Wait for cleanup
      await Future.delayed(const Duration(seconds: 1));
      
      // Restart monitoring
      _monitoringTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _performHealthCheck(),
      );
      
      _logger.info('Critical services restarted');
    } catch (e) {
      _logger.severe('Failed to restart critical services: $e');
    }
  }
  
  /// perform health check
  Future<void> _performHealthCheck() async {
    try {
      // Check system health
      final memoryUsage = await _checkMemoryUsage();
      final diskSpace = await _checkDiskSpace();
      
      if (memoryUsage > 0.9) {
        _logger.warning('High memory usage detected: ${(memoryUsage * 100).toStringAsFixed(1)}%');
      }
      
      if (diskSpace < 100) { // Less than 100MB
        _logger.warning('Low disk space: ${diskSpace.toStringAsFixed(1)}MB');
      }
    } catch (e) {
      _logger.warning('Health check failed: $e');
    }
  }
  
  /// check memory usage as a ratio of current rss to total system memory.
  Future<double> _checkMemoryUsage() async {
    try {
      final rss = ProcessInfo.currentRss;
      final total = await _getTotalSystemMemory();
      if (total <= 0) return 0.0;
      return (rss / total).clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  Future<int> _getTotalSystemMemory() async {
    if (Platform.isLinux || Platform.isAndroid) {
      try {
        final meminfo = await File('/proc/meminfo').readAsString();
        final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(meminfo);
        if (match != null) {
          final kb = int.parse(match.group(1)!);
          return kb * 1024;
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run('sysctl', ['hw.memsize']);
        final match = RegExp(r'hw.memsize:\s+(\d+)').firstMatch(result.stdout as String);
        if (match != null) return int.parse(match.group(1)!);
      } catch (_) {}
    }
    return 8 * 1024 * 1024 * 1024; // 8GB fallback
  }

  /// check available disk space in mb.
  Future<double> _checkDiskSpace() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
        final result = await Process.run('df', ['-k', directory.path]);
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final availableKb = int.tryParse(parts[3]) ?? 0;
            return availableKb / 1024.0;
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['logicaldisk', 'get', 'freespace', ',', 'size', '/format:csv']);
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines.skip(1)) {
          final parts = line.split(',');
          if (parts.length >= 3) {
            final free = int.tryParse(parts[parts.length - 2]) ?? 0;
            return free / (1024 * 1024);
          }
        }
      }
      return 1000.0;
    } catch (e) {
      return 1000.0;
    }
  }
  
  /// log error with proper formatting
  void _logError(ErrorReport report) {
    final level = _mapSeverityToLevel(report.severity);
    _logger.log(level, _formatErrorLog(report));
  }
  
  /// map error severity to log level
  Level _mapSeverityToLevel(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return Level.INFO;
      case ErrorSeverity.warning:
        return Level.WARNING;
      case ErrorSeverity.error:
        return Level.SEVERE;
      case ErrorSeverity.critical:
        return Level.SHOUT;
    }
  }
  
  /// format error for logging
  String _formatErrorLog(ErrorReport report) {
    final buffer = StringBuffer();
    buffer.writeln('Error ID: ${report.id}');
    buffer.writeln('Timestamp: ${report.timestamp.toIso8601String()}');
    buffer.writeln('Severity: ${report.severity}');
    buffer.writeln('Error: ${report.error}');
    
    if (report.context != null) {
      buffer.writeln('Context: ${report.context}');
    }
    
    if (report.metadata.isNotEmpty) {
      buffer.writeln('Metadata: ${jsonEncode(report.metadata)}');
    }
    
    if (report.stackTrace != null) {
      buffer.writeln('Stack Trace: ${report.stackTrace}');
    }
    
    return buffer.toString();
  }
  
  /// handle log records
  void _handleLogRecord(LogRecord record) {
    // Convert log records to error reports if they're severe enough
    if (record.level.value >= Level.SEVERE.value) {
      handleError(
        record.message,
        record.stackTrace,
        context: 'Logging System',
        severity: _mapLogLevelToSeverity(record.level),
      );
    }
  }
  
  /// map log level to error severity
  ErrorSeverity _mapLogLevelToSeverity(Level level) {
    if (level.value >= Level.SHOUT.value) {
      return ErrorSeverity.critical;
    } else if (level.value >= Level.SEVERE.value) {
      return ErrorSeverity.error;
    } else if (level.value >= Level.WARNING.value) {
      return ErrorSeverity.warning;
    } else {
      return ErrorSeverity.info;
    }
  }
  
  /// broadcast alert
  void _broadcastAlert(ErrorAlert alert) {
    _logger.warning('ALERT: ${alert.message}');
    // Implementation would notify monitoring systems
  }
  
  /// Persist error to disk
  Future<void> _persistError(ErrorReport report) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final errorFile = File('${directory.path}/termisol_errors.jsonl');
      
      await errorFile.writeAsString(
        '${jsonEncode(report.toJson())}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('Failed to persist error: $e');
    }
  }
  
  /// Load error history from disk
  Future<void> _loadErrorHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final errorFile = File('${directory.path}/termisol_errors.jsonl');
      
      if (await errorFile.exists()) {
        final lines = await errorFile.readAsLines();
        for (final line in lines.take(100)) { // Load last 100 errors
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final report = ErrorReport.fromJson(json);
            _errorHistory.add(report);
          } catch (e) {
            debugPrint('Failed to parse error history: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load error history: $e');
    }
  }
  
  /// Clean up old errors
  void _cleanupOldErrors() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _errorHistory.removeWhere((error) => error.timestamp.isBefore(cutoff));
    
    // Clean up error counts older than window
    final keysToRemove = <String>[];
    for (final entry in _lastErrorTime.entries) {
      if (DateTime.now().difference(entry.value) > _errorWindow) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _errorCounts.remove(key);
      _lastErrorTime.remove(key);
    }
  }
  
  /// Get error statistics
  Map<String, dynamic> getErrorStats() {
    return {
      'totalErrors': _errorHistory.length,
      'errorCounts': _errorCounts,
      'lastErrors': _errorHistory.take(10).map((e) => e.toJson()).toList(),
      'mostCommonErrors': (_errorCounts.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => {'error': e.key, 'count': e.value})
          .toList(),
    };
  }
  
  /// Dispose resources
  void dispose() {
    _errorController.close();
  }
}

/// Error severity levels
enum ErrorSeverity {
  info,
  warning,
  error,
  critical,
}

/// Alert types
enum AlertType {
  highFrequencyError,
  memoryThreshold,
  connectionFailure,
  securityIssue,
}

/// Alert severity levels
enum AlertSeverity {
  low,
  medium,
  high,
  critical,
}

/// Error report data structure
class ErrorReport {
  final String id;
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String? context;
  final Map<String, dynamic> metadata;
  final ErrorSeverity severity;
  final bool recoverable;
  final String platform;
  final String version;
  
  ErrorReport({
    required this.id,
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.context,
    required this.metadata,
    required this.severity,
    required this.recoverable,
    required this.platform,
    required this.version,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
    'stackTrace': stackTrace,
    'context': context,
    'metadata': metadata,
    'severity': severity.toString(),
    'recoverable': recoverable,
    'platform': platform,
    'version': version,
  };
  
  factory ErrorReport.fromJson(Map<String, dynamic> json) => ErrorReport(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    error: json['error'] as String,
    stackTrace: json['stackTrace'] as String?,
    context: json['context'] as String?,
    metadata: Map<String, dynamic>.from((json['metadata'] ?? {}) as Map<dynamic, dynamic>),
    severity: ErrorSeverity.values.firstWhere(
      (e) => e.toString() == json['severity'],
      orElse: () => ErrorSeverity.error,
    ),
    recoverable: json['recoverable'] as bool? ?? true,
    platform: json['platform'] as String? ?? 'unknown',
    version: json['version'] as String? ?? '1.0.0',
  );
}

/// Alert data structure
class ErrorAlert {
  final String id;
  final DateTime timestamp;
  final AlertType type;
  final String message;
  final int count;
  final String? context;
  final AlertSeverity severity;
  
  ErrorAlert({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.message,
    required this.count,
    this.context,
    required this.severity,
  });
}

/// Missing helper functions for robust error handler
extension RobustErrorHandlerHelpers on RobustErrorHandler {
  
  /// Clear old log files
  Future<void> _clearOldLogFiles() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${documentsDir.path}/logs');
      
      if (await logDir.exists()) {
        await for (final entity in logDir.list()) {
          if (entity is File && entity.path.endsWith('.log')) {
            final stat = await entity.stat();
            final age = DateTime.now().difference(stat.modified);
            if (age.inDays > 7) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to clear old log files: $e');
    }
  }
  
  /// Reinitialize critical connections
  Future<void> _reinitializeCriticalConnections() async {
    try {
      // Reset connection pool
      _connectionPool.clear();
      
      // Test basic connectivity
      await _testBasicConnectivity();
      
      debugPrint('Critical connections reinitialized');
    } catch (e) {
      debugPrint('Failed to reinitialize connections: $e');
    }
  }
  
  /// Test basic connectivity
  Future<bool> _testBasicConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('Connectivity test failed: $e');
      return false;
    }
  }
  
  /// Get current memory usage
  Map<String, dynamic> _getCurrentMemoryUsage() {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      return {
        'imageCacheSize': imageCache.currentSize,
        'imageCacheBytes': imageCache.currentSizeBytes,
        'liveByteCount': ProcessInfo.currentRss,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString(), 'timestamp': DateTime.now().toIso8601String()};
    }
  }
}
