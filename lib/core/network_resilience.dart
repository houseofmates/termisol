import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'production_config_system.dart';

/// Network resilience manager with automatic reconnection, retry logic, and failover.
class NetworkResilience {
  static const int maxRetryAttempts = 5;
  static const Duration baseRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(minutes: 2);
  static const Duration healthCheckInterval = Duration(seconds: 30);

  final StreamController<NetworkEvent> _eventController = StreamController.broadcast();
  final Map<String, ConnectionState> _connections = {};
  final Map<String, int> _failureCounts = {};

  Timer? _healthCheckTimer;
  bool _offlineMode = false;
  int _totalConnections = 0;
  int _failedConnections = 0;

  Stream<NetworkEvent> get events => _eventController.stream;
  bool get offlineMode => _offlineMode;
  double get connectionSuccessRate => _totalConnections > 0
      ? (_totalConnections - _failedConnections) / _totalConnections
      : 0.0;

  NetworkResilience() {
    _initialize();
  }

  void _initialize() {
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) => _performHealthChecks());
    debugPrint('NetworkResilience initialized');
  }

  /// Perform a resilient HTTP request with automatic retry and failover
  Future<http.Response> performRequest({
    required String connectionId,
    required Uri url,
    required String method,
    Map<String, String>? headers,
    dynamic body,
    Duration timeout = const Duration(seconds: 30),
    bool retryOnFailure = true,
  }) async {
    _totalConnections++;

    final startTime = DateTime.now();
    final connection = _getOrCreateConnection(connectionId);

    try {
      connection.status = ConnectionStatus.connecting;
      _eventController.add(NetworkEvent.connecting(connectionId, url.toString()));

      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(url, headers: headers).timeout(timeout);
          break;
        case 'POST':
          response = await http.post(url, headers: headers, body: body).timeout(timeout);
          break;
        case 'PUT':
          response = await http.put(url, headers: headers, body: body).timeout(timeout);
          break;
        case 'DELETE':
          response = await http.delete(url, headers: headers).timeout(timeout);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }

      final duration = DateTime.now().difference(startTime);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        connection.status = ConnectionStatus.connected;
        connection.lastSuccessTime = DateTime.now();
        _resetFailures(connectionId);

        _eventController.add(NetworkEvent.requestSucceeded(
          connectionId,
          url.toString(),
          response.statusCode,
          duration,
        ));

        return response;
      } else {
        _handleFailure(connectionId);
        throw NetworkException(
          'Request failed with status ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      _handleFailure(connectionId);

      if (retryOnFailure) {
        return _performRetry(connectionId, url, method, headers, body, timeout);
      }

      _eventController.add(NetworkEvent.requestFailed(connectionId, url.toString(), e.toString()));
      rethrow;
    }
  }

  Future<http.Response> _performRetry(
    String connectionId,
    Uri url,
    String method,
    Map<String, String>? headers,
    dynamic body,
    Duration timeout,
  ) async {
    final failureCount = _failureCounts[connectionId] ?? 0;

    if (failureCount >= maxRetryAttempts) {
      throw NetworkException('Max retry attempts ($maxRetryAttempts) reached for $connectionId');
    }

    final delay = _calculateRetryDelay(failureCount);
    debugPrint('Retrying $connectionId in ${delay.inSeconds}s (attempt ${failureCount + 1})');

    await Future.delayed(delay);

    return performRequest(
      connectionId: connectionId,
      url: url,
      method: method,
      headers: headers,
      body: body,
      timeout: timeout,
      retryOnFailure: true,
    );
  }

  Duration _calculateRetryDelay(int failureCount) {
    final baseDelay = baseRetryDelay.inMilliseconds;
    final exponentialDelay = baseDelay * pow(2, failureCount).toInt();
    final jitter = Random().nextInt(1000); // Add up to 1s jitter
    final delayMs = min(exponentialDelay + jitter, maxRetryDelay.inMilliseconds);

    return Duration(milliseconds: delayMs);
  }

  ConnectionState _getOrCreateConnection(String connectionId) {
    return _connections[connectionId] ??= ConnectionState(
      id: connectionId,
      status: ConnectionStatus.disconnected,
    );
  }

  void _handleFailure(String connectionId) {
    _failureCounts[connectionId] = (_failureCounts[connectionId] ?? 0) + 1;
    _failedConnections++;

    final connection = _connections[connectionId];
    if (connection != null) {
      connection.status = ConnectionStatus.failed;
      connection.lastFailureTime = DateTime.now();
    }

    _checkGlobalConnectionHealth();
  }

  void _resetFailures(String connectionId) {
    _failureCounts[connectionId] = 0;
  }

  void _checkGlobalConnectionHealth() {
    final totalFailures = _failureCounts.values.isEmpty ? 0 :
        _failureCounts.values.reduce((a, b) => a + b);

    if (totalFailures > 10) {
      _offlineMode = true;
      _eventController.add(NetworkEvent.offlineModeActivated(totalFailures));
      debugPrint('Offline mode activated due to excessive failures: $totalFailures');
    }
  }

  Future<void> _performHealthChecks() async {
    for (final connection in _connections.values) {
      if (connection.status == ConnectionStatus.connected) {
        try {
          final response = await http.get(
            Uri.parse(connection.lastUrl ?? 'http://localhost'),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            // Connection is healthy
          } else {
            connection.status = ConnectionStatus.degraded;
            _eventController.add(NetworkEvent.healthCheckWarning(connection.id, response.statusCode));
          }
        } catch (e) {
          connection.status = ConnectionStatus.degraded;
          _eventController.add(NetworkEvent.healthCheckFailed(connection.id, e.toString()));
        }
      }
    }
  }

  /// Enable or disable offline mode
  void setOfflineMode(bool enabled) {
    _offlineMode = enabled;
    debugPrint('Offline mode ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Register a known connection endpoint
  void registerConnection(String connectionId, String baseUrl) {
    final connection = _getOrCreateConnection(connectionId);
    connection.lastUrl = baseUrl;
    debugPrint('Connection registered: $connectionId -> $baseUrl');
  }

  /// Get connection statistics
  Map<String, dynamic> getConnectionStats() {
    final healthyConnections = _connections.values.where((c) =>
        c.status == ConnectionStatus.connected || c.status == ConnectionStatus.degraded).length;

    return {
      'totalConnections': _totalConnections,
      'failedConnections': _failedConnections,
      'successRate': connectionSuccessRate,
      'activeConnections': _connections.length,
      'healthyConnections': healthyConnections,
      'offlineMode': _offlineMode,
      'failureCounts': Map.from(_failureCounts),
    };
  }

  /// Reset all connection states
  void resetConnections() {
    _connections.clear();
    _failureCounts.clear();
    _totalConnections = 0;
    _failedConnections = 0;
    _offlineMode = false;
    _eventController.add(NetworkEvent.reset());
    debugPrint('Network resilience state reset');
  }

  void dispose() {
    _healthCheckTimer?.cancel();
    _eventController.close();
    debugPrint('NetworkResilience disposed');
  }
}

/// Connection state tracking
class ConnectionState {
  final String id;
  ConnectionStatus status;
  DateTime? lastSuccessTime;
  DateTime? lastFailureTime;
  String? lastUrl;
  int retryCount = 0;

  ConnectionState({
    required this.id,
    required this.status,
  });
}

/// Network event types
class NetworkEvent {
  final NetworkEventType type;
  final String? connectionId;
  final String? url;
  final int? statusCode;
  final Duration? duration;
  final String? error;
  final int? count;
  final DateTime timestamp;

  const NetworkEvent._(this.type, {
    this.connectionId,
    this.url,
    this.statusCode,
    this.duration,
    this.error,
    this.count,
    required this.timestamp,
  });

  factory NetworkEvent.connecting(String connectionId, String url) {
    return NetworkEvent._(NetworkEventType.connecting,
      connectionId: connectionId,
      url: url,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.requestSucceeded(
    String connectionId, String url, int statusCode, Duration duration,
  ) {
    return NetworkEvent._(NetworkEventType.requestSucceeded,
      connectionId: connectionId,
      url: url,
      statusCode: statusCode,
      duration: duration,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.requestFailed(String connectionId, String url, String error) {
    return NetworkEvent._(NetworkEventType.requestFailed,
      connectionId: connectionId,
      url: url,
      error: error,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.offlineModeActivated(int failureCount) {
    return NetworkEvent._(NetworkEventType.offlineModeActivated,
      count: failureCount,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.healthCheckWarning(String connectionId, int statusCode) {
    return NetworkEvent._(NetworkEventType.healthCheckWarning,
      connectionId: connectionId,
      statusCode: statusCode,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.healthCheckFailed(String connectionId, String error) {
    return NetworkEvent._(NetworkEventType.healthCheckFailed,
      connectionId: connectionId,
      error: error,
      timestamp: DateTime.now(),
    );
  }

  factory NetworkEvent.reset() {
    return NetworkEvent._(NetworkEventType.reset, timestamp: DateTime.now());
  }
}

enum NetworkEventType {
  connecting,
  requestSucceeded,
  requestFailed,
  offlineModeActivated,
  healthCheckWarning,
  healthCheckFailed,
  reset,
}

enum ConnectionStatus { disconnected, connecting, connected, degraded, failed }

class NetworkException implements Exception {
  final String message;
  final int? statusCode;

  const NetworkException(this.message, {this.statusCode});

  @override
  String toString() => 'NetworkException: $message';
}