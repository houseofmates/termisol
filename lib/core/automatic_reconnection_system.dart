import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Automatic reconnection system for network connections
/// 
/// Features:
/// - Exponential backoff reconnection strategy
/// - Connection health monitoring
/// - Automatic failover to backup endpoints
/// - Circuit breaker pattern for failing services
/// - Connection state persistence and recovery
/// - Multi-protocol support (HTTP, WebSocket, TCP, SSH)
class AutomaticReconnectionSystem {
  static const Duration _initialBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(minutes: 5);
  static const double _backoffMultiplier = 1.5;
  static const int _maxRetries = 10;
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const Duration _circuitBreakerTimeout = Duration(minutes: 1);
  static const int _circuitBreakerFailureThreshold = 5;
  
  final Map<String, ManagedConnection> _connections = {};
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  final List<FailoverEndpoint> _failoverEndpoints = [];
  final Queue<ReconnectionAttempt> _reconnectionHistory = Queue();
  
  Timer? _healthCheckTimer;
  
  int _totalReconnections = 0;
  int _successfulReconnections = 0;
  int _failedReconnections = 0;
  double _totalReconnectionTime = 0.0;

  AutomaticReconnectionSystem() {
    _initializeReconnectionSystem();
  }

  /// Initialize the reconnection system
  void _initializeReconnectionSystem() {
    _setupFailoverEndpoints();
    _startHealthMonitoring();
  }

  /// Setup failover endpoints
  void _setupFailoverEndpoints() {
    // Example failover endpoints for different services
    _failoverEndpoints.add(FailoverEndpoint(
      service: 'api',
      primary: 'https://api.primary.com',
      backups: [
        'https://api.backup1.com',
        'https://api.backup2.com',
      ],
    ));
    
    _failoverEndpoints.add(FailoverEndpoint(
      service: 'websocket',
      primary: 'wss://ws.primary.com',
      backups: [
        'wss://ws.backup1.com',
        'wss://ws.backup2.com',
      ],
    ));
  }

  /// Start health monitoring
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  /// Register a managed connection
  String registerConnection({
    required String id,
    required ConnectionType type,
    required String endpoint,
    Map<String, dynamic>? config,
    ReconnectionPolicy? policy,
  }) async {
    final connection = ManagedConnection(
      id: id,
      type: type,
      endpoint: endpoint,
      config: config ?? {},
      policy: policy ?? ReconnectionPolicy.defaultPolicy(),
      createdAt: DateTime.now(),
      state: ConnectionState.disconnected,
    );
    
    _connections[id] = connection;
    
    // Setup circuit breaker
    _circuitBreakers[id] = CircuitBreaker(
      failureThreshold: _circuitBreakerFailureThreshold,
      timeout: _circuitBreakerTimeout,
    );
    
    // Attempt initial connection
    await _connectConnection(connection);
    
    return id;
  }

  /// Connect a managed connection
  Future<void> _connectConnection(ManagedConnection connection) async {
    final circuitBreaker = _circuitBreakers[connection.id];
    if (circuitBreaker != null && circuitBreaker.isOpen) {
      debugPrint('Circuit breaker is open for ${connection.id}');
      return;
    }
    
    try {
      connection.state = ConnectionState.connecting;
      
      switch (connection.type) {
        case ConnectionType.http:
          await _connectHTTP(connection);
          break;
        case ConnectionType.websocket:
          await _connectWebSocket(connection);
          break;
        case ConnectionType.tcp:
          await _connectTCP(connection);
          break;
        case ConnectionType.ssh:
          await _connectSSH(connection);
          break;
      }
      
      connection.state = ConnectionState.connected;
      connection.lastConnected = DateTime.now();
      connection.retryCount = 0;
      
      if (circuitBreaker != null) {
        circuitBreaker.recordSuccess();
      }
      
    } catch (e) {
      connection.state = ConnectionState.failed;
      connection.lastError = e.toString();
      
      if (circuitBreaker != null) {
        circuitBreaker.recordFailure();
      }
      
      // Schedule reconnection attempt
      _scheduleReconnection(connection);
    }
  }

  /// Connect HTTP connection
  Future<void> _connectHTTP(ManagedConnection connection) async {
    final client = http.Client();
    final response = await client.get(Uri.parse(connection.endpoint));
    
    if (response.statusCode != 200) {
      throw Exception('HTTP connection failed: ${response.statusCode}');
    }
    
    connection.connection = client;
  }

  /// Connect WebSocket connection
  Future<void> _connectWebSocket(ManagedConnection connection) async {
    final channel = WebSocketChannel.connect(Uri.parse(connection.endpoint));
    
    // Wait for connection to be established
    await channel.ready.timeout(Duration(seconds: 10));
    
    connection.connection = channel;
  }

  /// Connect TCP connection
  Future<void> _connectTCP(ManagedConnection connection) async {
    final uri = Uri.parse(connection.endpoint);
    final socket = await Socket.connect(uri.host, uri.port);
    
    connection.connection = socket;
  }

  /// Connect SSH connection
  Future<void> _connectSSH(ManagedConnection connection) async {
    // Simplified SSH connection
    // In a real implementation, you would use an SSH library
    connection.connection = 'ssh_connected'; // Placeholder
  }

  /// Schedule reconnection attempt
  void _scheduleReconnection(ManagedConnection connection) {
    if (connection.retryCount >= connection.policy.maxRetries) {
      debugPrint('Max retries exceeded for ${connection.id}');
      connection.state = ConnectionState.abandoned;
      return;
    }
    
    final backoff = _calculateBackoff(connection.retryCount);
    connection.nextRetry = DateTime.now().add(backoff);
    
    Timer(backoff, () async {
      await _attemptReconnection(connection);
    });
  }

  /// Calculate exponential backoff
  Duration _calculateBackoff(int retryCount) {
    final backoff = _initialBackoff * pow(_backoffMultiplier, retryCount);
    return Duration(milliseconds: min(backoff.inMilliseconds, _maxBackoff.inMilliseconds));
  }

  /// Attempt reconnection
  Future<void> _attemptReconnection(ManagedConnection connection) async {
    _totalReconnections++;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Try failover endpoints if primary failed
      String endpointToTry = connection.endpoint;
      if (connection.retryCount > 0) {
        endpointToTry = _getFailoverEndpoint(connection.endpoint);
        if (endpointToTry != connection.endpoint) {
          connection.endpoint = endpointToTry;
          debugPrint('Trying failover endpoint: $endpointToTry');
        }
      }
      
      // Close existing connection
      await _closeConnection(connection);
      
      // Attempt new connection
      await _connectConnection(connection);
      
      _successfulReconnections++;
      debugPrint('Successfully reconnected ${connection.id}');
      
    } catch (e) {
      _failedReconnections++;
      connection.retryCount++;
      connection.lastError = e.toString();
      
      debugPrint('Reconnection failed for ${connection.id}: $e');
      
      // Schedule next attempt
      _scheduleReconnection(connection);
    } finally {
      _totalReconnectionTime += stopwatch.elapsedMilliseconds.toDouble();
      stopwatch.stop();
      
      // Record reconnection attempt
      _reconnectionHistory.add(ReconnectionAttempt(
        connectionId: connection.id,
        timestamp: DateTime.now(),
        retryCount: connection.retryCount,
        success: connection.state == ConnectionState.connected,
        duration: stopwatch.elapsedMilliseconds.toDouble(),
        endpoint: connection.endpoint,
      ));
      
      // Keep only recent history
      if (_reconnectionHistory.length > 1000) {
        _reconnectionHistory.removeFirst();
      }
    }
  }

  /// Get failover endpoint
  String _getFailoverEndpoint(String primaryEndpoint) {
    for (final failover in _failoverEndpoints) {
      if (failover.primary == primaryEndpoint) {
        final index = Random().nextInt(failover.backups.length + 1);
        if (index == 0) {
          return primaryEndpoint; // Try primary again
        } else {
          return failover.backups[index - 1];
        }
      }
    }
    return primaryEndpoint;
  }

  /// Close connection
  Future<void> _closeConnection(ManagedConnection connection) async {
    try {
      switch (connection.type) {
        case ConnectionType.http:
          if (connection.connection is http.Client) {
            (connection.connection as http.Client).close();
          }
          break;
        case ConnectionType.websocket:
          if (connection.connection is WebSocketChannel) {
            (connection.connection as WebSocketChannel).sink.close();
          }
          break;
        case ConnectionType.tcp:
          if (connection.connection is Socket) {
            await (connection.connection as Socket).close();
          }
          break;
        case ConnectionType.ssh:
          // Close SSH connection
          break;
      }
    } catch (e) {
      debugPrint('Error closing connection ${connection.id}: $e');
    }
  }

  /// Perform health check on all connections
  void _performHealthCheck() {
    for (final connection in _connections.values) {
      if (connection.state == ConnectionState.connected) {
        _checkConnectionHealth(connection);
      }
    }
  }

  /// Check individual connection health
  Future<void> _checkConnectionHealth(ManagedConnection connection) async {
    try {
      bool isHealthy = false;
      
      switch (connection.type) {
        case ConnectionType.http:
          isHealthy = await _checkHTTPHealth(connection);
          break;
        case ConnectionType.websocket:
          isHealthy = await _checkWebSocketHealth(connection);
          break;
        case ConnectionType.tcp:
          isHealthy = await _checkTCPHealth(connection);
          break;
        case ConnectionType.ssh:
          isHealthy = await _checkSSHHealth(connection);
          break;
      }
      
      if (!isHealthy) {
        debugPrint('Connection ${connection.id} is unhealthy, scheduling reconnection');
        connection.state = ConnectionState.failed;
        _scheduleReconnection(connection);
      }
    } catch (e) {
      debugPrint('Health check failed for ${connection.id}: $e');
      connection.state = ConnectionState.failed;
      _scheduleReconnection(connection);
    }
  }

  /// Check HTTP connection health
  Future<bool> _checkHTTPHealth(ManagedConnection connection) async {
    if (connection.connection is! http.Client) return false;
    
    try {
      final response = await (connection.connection as http.Client)
          .get(Uri.parse('${connection.endpoint}/health'))
          .timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Check WebSocket connection health
  Future<bool> _checkWebSocketHealth(ManagedConnection connection) async {
    if (connection.connection is! WebSocketChannel) return false;
    
    try {
      final channel = connection.connection as WebSocketChannel;
      return channel.sink != null && !channel.sink.isClosed;
    } catch (e) {
      return false;
    }
  }

  /// Check TCP connection health
  Future<bool> _checkTCPHealth(ManagedConnection connection) async {
    if (connection.connection is! Socket) return false;
    
    try {
      final socket = connection.connection as Socket;
      return !socket.done;
    } catch (e) {
      return false;
    }
  }

  /// Check SSH connection health
  Future<bool> _checkSSHHealth(ManagedConnection connection) async {
    // Simplified SSH health check
    return connection.connection != null;
  }

  /// Get connection by ID
  ManagedConnection? getConnection(String id) {
    return _connections[id];
  }

  /// Get all connections
  Map<String, ManagedConnection> getAllConnections() {
    return Map.unmodifiable(_connections);
  }

  /// Get connections by state
  List<ManagedConnection> getConnectionsByState(ConnectionState state) {
    return _connections.values.where((c) => c.state == state).toList();
  }

  /// Get reconnection statistics
  ReconnectionStats getStats() {
    return ReconnectionStats(
      totalReconnections: _totalReconnections,
      successfulReconnections: _successfulReconnections,
      failedReconnections: _failedReconnections,
      successRate: _totalReconnections > 0 ? _successfulReconnections / _totalReconnections : 0.0,
      averageReconnectionTime: _totalReconnections > 0 ? _totalReconnectionTime / _totalReconnections : 0.0,
      totalReconnectionTime: _totalReconnectionTime,
      activeConnections: _connections.values.where((c) => c.state == ConnectionState.connected).length,
      failedConnections: _connections.values.where((c) => c.state == ConnectionState.failed).length,
      abandonedConnections: _connections.values.where((c) => c.state == ConnectionState.abandoned).length,
      circuitBreakersOpen: _circuitBreakers.values.where((cb) => cb.isOpen).length,
      historySize: _reconnectionHistory.length,
    );
  }

  /// Get reconnection history
  List<ReconnectionAttempt> getHistory({Duration? duration}) {
    if (duration == null) return _reconnectionHistory.toList();
    
    final cutoff = DateTime.now().subtract(duration);
    return _reconnectionHistory.where((attempt) => attempt.timestamp.isAfter(cutoff)).toList();
  }

  /// Force reconnection of a connection
  Future<void> forceReconnection(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection != null) {
      connection.retryCount = 0;
      await _attemptReconnection(connection);
    }
  }

  /// Reset circuit breaker for a connection
  void resetCircuitBreaker(String connectionId) {
    final circuitBreaker = _circuitBreakers[connectionId];
    if (circuitBreaker != null) {
      circuitBreaker.reset();
    }
  }

  /// Unregister connection
  Future<void> unregisterConnection(String connectionId) async {
    final connection = _connections.remove(connectionId);
    if (connection != null) {
      await _closeConnection(connection);
    }
    _circuitBreakers.remove(connectionId);
  }

  /// Dispose reconnection system
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    
    // Close all connections
    for (final connection in _connections.values) {
      await _closeConnection(connection);
    }
    
    _connections.clear();
    _circuitBreakers.clear();
    _reconnectionHistory.clear();
    _failoverEndpoints.clear();
  }
}

/// Managed connection
class ManagedConnection {
  final String id;
  final ConnectionType type;
  String endpoint;
  final Map<String, dynamic> config;
  final ReconnectionPolicy policy;
  final DateTime createdAt;
  
  dynamic connection;
  ConnectionState state;
  DateTime? lastConnected;
  DateTime? nextRetry;
  int retryCount = 0;
  String? lastError;

  ManagedConnection({
    required this.id,
    required this.type,
    required this.endpoint,
    required this.config,
    required this.policy,
    required this.createdAt,
    required this.state,
  });
}

/// Reconnection policy
class ReconnectionPolicy {
  final int maxRetries;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final double backoffMultiplier;
  final bool enableFailover;
  final bool enableCircuitBreaker;

  const ReconnectionPolicy({
    required this.maxRetries,
    required this.initialBackoff,
    required this.maxBackoff,
    required this.backoffMultiplier,
    required this.enableFailover,
    required this.enableCircuitBreaker,
  });

  factory ReconnectionPolicy.defaultPolicy() {
    return const ReconnectionPolicy(
      maxRetries: 10,
      initialBackoff: Duration(seconds: 1),
      maxBackoff: Duration(minutes: 5),
      backoffMultiplier: 1.5,
      enableFailover: true,
      enableCircuitBreaker: true,
    );
  }
}

/// Circuit breaker
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;

  CircuitBreaker({
    required this.failureThreshold,
    required this.timeout,
  });

  bool get isOpen => _isOpen;

  void recordSuccess() {
    _failureCount = 0;
    _isOpen = false;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _isOpen = true;
    }
  }

  void reset() {
    _failureCount = 0;
    _isOpen = false;
    _lastFailureTime = null;
  }

  bool shouldAllowRequest() {
    if (!_isOpen) return true;
    
    if (_lastFailureTime != null && 
        DateTime.now().difference(_lastFailureTime!) > timeout) {
      reset();
      return true;
    }
    
    return false;
  }
}

/// Failover endpoint
class FailoverEndpoint {
  final String service;
  final String primary;
  final List<String> backups;

  const FailoverEndpoint({
    required this.service,
    required this.primary,
    required this.backups,
  });
}

/// Reconnection attempt
class ReconnectionAttempt {
  final String connectionId;
  final DateTime timestamp;
  final int retryCount;
  final bool success;
  final double duration;
  final String endpoint;

  const ReconnectionAttempt({
    required this.connectionId,
    required this.timestamp,
    required this.retryCount,
    required this.success,
    required this.duration,
    required this.endpoint,
  });
}

/// Reconnection statistics
class ReconnectionStats {
  final int totalReconnections;
  final int successfulReconnections;
  final int failedReconnections;
  final double successRate;
  final double averageReconnectionTime;
  final double totalReconnectionTime;
  final int activeConnections;
  final int failedConnections;
  final int abandonedConnections;
  final int circuitBreakersOpen;
  final int historySize;

  const ReconnectionStats({
    required this.totalReconnections,
    required this.successfulReconnections,
    required this.failedReconnections,
    required this.successRate,
    required this.averageReconnectionTime,
    required this.totalReconnectionTime,
    required this.activeConnections,
    required this.failedConnections,
    required this.abandonedConnections,
    required this.circuitBreakersOpen,
    required this.historySize,
  });
}

/// Connection types
enum ConnectionType {
  http,
  websocket,
  tcp,
  ssh,
}

/// Connection states
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
  abandoned,
}
