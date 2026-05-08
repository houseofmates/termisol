import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Health Check System for Production Stability
///
/// Provides endpoints to monitor system health and detect issues early.
class HealthCheckSystem {
  static final HealthCheckSystem _instance = HealthCheckSystem._internal();
  factory HealthCheckSystem() => _instance;
  HealthCheckSystem._internal();

  final Map<String, HealthCheck> _checks = {};
  final List<HealthStatus> _statusHistory = [];

  void registerCheck(String name, HealthCheck check) {
    _checks[name] = check;
  }

  /// Run all health checks
  Future<Map<String, dynamic>> runHealthCheck() async {
    final results = <String, dynamic>{};
    final startTime = DateTime.now();

    for (final entry in _checks.entries) {
      try {
        final result = await entry.value.check();
        results[entry.key] = {
          'status': result.status.name,
          'message': result.message,
          'timestamp': DateTime.now().toIso8601String(),
          'details': result.details,
        };
      } catch (e) {
        results[entry.key] = {
          'status': 'error',
          'message': 'Check failed: $e',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
    }

    final overallStatus = _determineOverallStatus(results);
    final duration = DateTime.now().difference(startTime);

    final healthStatus = HealthStatus(
      timestamp: startTime,
      overallStatus: overallStatus,
      checks: results,
      duration: duration,
    );

    _statusHistory.add(healthStatus);

    // Keep only last 100 status entries
    if (_statusHistory.length > 100) {
      _statusHistory.removeAt(0);
    }

    return {
      'status': overallStatus.name,
      'timestamp': startTime.toIso8601String(),
      'duration_ms': duration.inMilliseconds,
      'checks': results,
    };
  }

  HealthStatusEnum _determineOverallStatus(Map<String, dynamic> results) {
    bool hasError = false;
    bool hasWarning = false;

    for (final result in results.values) {
      final status = result['status'];
      if (status == 'error') hasError = true;
      if (status == 'warning') hasWarning = true;
    }

    if (hasError) return HealthStatusEnum.unhealthy;
    if (hasWarning) return HealthStatusEnum.degraded;
    return HealthStatusEnum.healthy;
  }

  /// Get health status history
  List<HealthStatus> getStatusHistory() => List.unmodifiable(_statusHistory);

  /// Get current health summary
  Map<String, dynamic> getHealthSummary() {
    if (_statusHistory.isEmpty) return {'status': 'unknown'};

    final latest = _statusHistory.last;
    return {
      'status': latest.overallStatus.name,
      'timestamp': latest.timestamp.toIso8601String(),
      'checks_count': latest.checks.length,
      'duration_ms': latest.duration.inMilliseconds,
    };
  }
}

class HealthCheck {
  final Future<HealthResult> Function() check;

  HealthCheck(this.check);
}

class HealthResult {
  final HealthStatusEnum status;
  final String message;
  final Map<String, dynamic>? details;

  HealthResult(this.status, this.message, [this.details]);
}

enum HealthStatusEnum {
  healthy,
  degraded,
  unhealthy,
}

class HealthStatus {
  final DateTime timestamp;
  final HealthStatusEnum overallStatus;
  final Map<String, dynamic> checks;
  final Duration duration;

  HealthStatus({
    required this.timestamp,
    required this.overallStatus,
    required this.checks,
    required this.duration,
  });
}