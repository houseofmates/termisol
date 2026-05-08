import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Error Telemetry and Crash Reporting System
///
/// Collects error data for debugging and improvement without compromising user privacy.
class ErrorTelemetrySystem {
  static final ErrorTelemetrySystem _instance = ErrorTelemetrySystem._internal();
  factory ErrorTelemetrySystem() => _instance;
  ErrorTelemetrySystem._internal();

  final StreamController<ErrorEvent> _errorStream = StreamController.broadcast();
  final List<ErrorEvent> _errorHistory = [];
  bool _enabled = true;

  /// Enable/disable telemetry
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Report an error
  void reportError(dynamic error, StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? metadata,
    ErrorSeverity severity = ErrorSeverity.medium,
  }) {
    if (!_enabled) return;

    final event = ErrorEvent(
      timestamp: DateTime.now(),
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context,
      metadata: metadata,
      severity: severity,
    );

    _errorHistory.add(event);
    _errorStream.add(event);

    // Keep only last 500 errors
    if (_errorHistory.length > 500) {
      _errorHistory.removeAt(0);
    }

    // In debug mode, print to console
    if (kDebugMode) {
      debugPrint('Error reported: ${event.error}');
      if (event.stackTrace != null) {
        debugPrint('Stack trace: ${event.stackTrace}');
      }
    }

    // Send to error reporting service
    _sendToErrorReportingService(event);
  }

  /// Report a non-fatal issue
  void reportIssue(String message, {
    String? context,
    Map<String, dynamic>? metadata,
    ErrorSeverity severity = ErrorSeverity.low,
  }) {
    reportError(message, null,
      context: context,
      metadata: metadata,
      severity: severity,
    );
  }

  /// Listen to error events
  Stream<ErrorEvent> get errorStream => _errorStream.stream;

  /// Get error history
  List<ErrorEvent> getErrorHistory({
    ErrorSeverity? minSeverity,
    DateTime? since,
  }) {
    var history = _errorHistory;

    if (minSeverity != null) {
      history = history.where((e) => e.severity.index >= minSeverity.index).toList();
    }

    if (since != null) {
      history = history.where((e) => e.timestamp.isAfter(since)).toList();
    }

    return List.unmodifiable(history);
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final stats = <String, dynamic>{
      'total_errors': _errorHistory.length,
      'severity_breakdown': <String, int>{},
      'recent_errors': _errorHistory.where((e) =>
        e.timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 1)))
      ).length,
    };

    for (final severity in ErrorSeverity.values) {
      stats['severity_breakdown'][severity.name] = _errorHistory
          .where((e) => e.severity == severity)
          .length;
    }

    return stats;
  }

  void _sendToErrorReportingService(ErrorEvent event) {
    if (kReleaseMode && event.severity.index >= ErrorSeverity.medium.index) {
      try {
        // Implement actual error reporting service integration
        _reportToExternalService(event);
      } catch (e) {
        debugPrint('Failed to send error to external service: $e');
        // Fallback to local logging
        _logErrorLocally(event);
      }
    } else {
      // In debug mode or for low severity, just log locally
      _logErrorLocally(event);
    }
  }
  
  void _reportToExternalService(ErrorEvent event) {
    // Integration with error reporting services like Sentry, Bugsnag, etc.
    // For now, implement basic local error logging
    final errorLog = {
      'timestamp': event.timestamp.toIso8601String(),
      'error': event.error,
      'stackTrace': event.stackTrace,
      'context': event.context,
      'metadata': event.metadata,
      'severity': event.severity.name,
    };
    
    debugPrint('Error reported: ${errorLog.toString()}');
  }
  
  void _logErrorLocally(ErrorEvent event) {
    final errorLog = '[${event.timestamp.toIso8601String()}] ${event.severity.name.toUpperCase()}: ${event.error}';
    if (event.context != null) {
      debugPrint('$errorLog (Context: ${event.context})');
    } else {
      debugPrint(errorLog);
    }
  }

  /// Clean up resources
  void dispose() {
    _errorStream.close();
  }
}

class ErrorEvent {
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String? context;
  final Map<String, dynamic>? metadata;
  final ErrorSeverity severity;

  ErrorEvent({
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.context,
    this.metadata,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'error': error,
    'stackTrace': stackTrace,
    'context': context,
    'metadata': metadata,
    'severity': severity.name,
  };
}

enum ErrorSeverity {
  low,      // Minor issues, can be ignored
  medium,   // Functional issues that should be fixed
  high,     // Serious issues affecting usability
  critical, // Crashes or data loss
}