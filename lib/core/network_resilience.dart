import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xterm/xterm.dart';

/// Network Resilience - Auto-reconnection and network health monitoring
/// 
/// Implements comprehensive network resilience:
/// - Automatic reconnection with exponential backoff
/// - Connection health monitoring
/// - Circuit breaker pattern
/// - Request retry with jitter
/// - Network quality assessment
/// - Fallback server support
/// - Connection pooling
/// - Network diagnostics
class NetworkResilience {
  bool _isInitialized = false;
  
  // Connection state
  bool _isConnected = false;
  bool _isReconnecting = false;
  DateTime? _lastConnectedTime;
  DateTime? _lastAttemptTime;
  int _connectionAttempts = 0;
  
  // Circuit breaker
  bool _circuitOpen = false;
  int _failureCount = 0;
  int _failureThreshold = 5;
  Duration _recoveryTimeout = const Duration(minutes: 1);
  
  // Backoff configuration
  Duration _baseDelay = const Duration(seconds: 1);
  Duration _maxDelay = const Duration(minutes: 5);
  double _backoffMultiplier = 2.0;
  double _jitterFactor = 0.1;
  
  // Connection pool
  final List<NetworkConnection> _connections = [];
  int _maxConnections = 10;
  int _activeConnections = 0;
  
  // Health monitoring
  Timer? _healthCheckTimer;
  Timer? _recoveryTimer;
  final List<NetworkHealth> _healthHistory = [];
  NetworkQuality _currentQuality = NetworkQuality.excellent;
  
  // Server endpoints
  List<String> _primaryServers = [];
  List<String> _fallbackServers = [];
  String? _currentServer;
  int _currentServerIndex = 0;
  
  // Event handlers
  final List<Function(NetworkStatus)> _onStatusChanged = [];
  final List<Function(NetworkHealth)> _onHealthUpdate = [];
  final List<Function(String, String)> _onServerSwitch = [];
  final List<Function(NetworkError)> _onError = [];
  
  NetworkResilience();
  
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  bool get isReconnecting => _isReconnecting;
  bool get circuitOpen => _circuitOpen;
  int get connectionAttempts => _connectionAttempts;
  NetworkQuality get currentQuality => _currentQuality;
  String? get currentServer => _currentServer;
  
  /// Initialize network resilience
  Future<void> initialize({
    List<String>? primaryServers,
    List<String>? fallbackServers,
    int? failureThreshold,
    Duration? baseDelay,
    Duration? maxDelay,
  }) async {
    if (_isInitialized) return;
    
    try {
      // Setup server endpoints
      _primaryServers = primaryServers ?? [
        'http://localhost:8786',
        'http://127.0.0.1:8786',
      ];
      
      _fallbackServers = fallbackServers ?? [
        'https://vc.houseofmates.space',
        'http://192.168.4.233:8786',
        'http://192.168.4.250:8786',
      ];
      
      // Configure parameters
      if (failureThreshold != null) _failureThreshold = failureThreshold!;
      if (baseDelay != null) _baseDelay = baseDelay!;
      if (maxDelay != null) _maxDelay = maxDelay!;
      
      // Start health monitoring
      _startHealthMonitoring();
      
      // Start recovery timer
      _startRecoveryTimer();
      
      _isInitialized = true;
      debugPrint('🌐 Network Resilience initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Network Resilience: $e');
      rethrow;
    }
  }
  
  /// Start health monitoring
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _performHealthCheck();
    });
  }
  
  /// Start recovery timer
  void _startRecoveryTimer() {
    _recoveryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _attemptRecovery();
    });
  }
  
  /// Perform health check
  Future<void> _performHealthCheck() async {
    if (_currentServer != null && _currentServer!.isNotEmpty) return;
    
    try {
      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse('$_currentServer/api/health'),
      ).timeout(const Duration(seconds: 10));
      
      final latency = DateTime.now().difference(startTime);
      final health = NetworkHealth(
        timestamp: DateTime.now(),
        latency: latency,
        success: response.statusCode == 200,
        server: _currentServer!,
      );
      
      _updateHealthStatus(health);
      _updateNetworkQuality(health);
      
      // Reset circuit breaker on successful health check
      if (health.success && _circuitOpen) {
        _resetCircuitBreaker();
      }
    } catch (e) {
      final health = NetworkHealth(
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
        server: _currentServer!,
      );
      
      _updateHealthStatus(health);
      _handleConnectionFailure();
    }
  }
  
  /// Update health status
  void _updateHealthStatus(NetworkHealth health) {
    _healthHistory.add(health);
    
    // Keep only last 100 health checks
    if (_healthHistory.length > 100) {
      _healthHistory.removeRange(0, _healthHistory.length - 100);
    }
    
    _onHealthUpdate.forEach((callback) => callback(health));
  }
  
  /// Update network quality assessment
  void _updateNetworkQuality(NetworkHealth health) {
    if (!health.success) {
      _currentQuality = NetworkQuality.poor;
      return;
    }
    
    final recentHealth = _healthHistory.where((h) =>
        h.timestamp.isAfter(DateTime.now().subtract(const Duration(minutes: 5)))
    ).toList();
    
    if (recentHealth.length < 3) return;
    
    final avgLatency = recentHealth
        .where((h) => h.success)
        .map((h) => h.latency?.inMilliseconds ?? 0)
        .fold(0, (a, b) => a + b) /
        recentHealth.where((h) => h.success).length;
    
    final successRate = recentHealth.where((h) => h.success).length / recentHealth.length;
    
    if (avgLatency < 100 && successRate > 0.9) {
      _currentQuality = NetworkQuality.excellent;
    } else if (avgLatency < 300 && successRate > 0.8) {
      _currentQuality = NetworkQuality.good;
    } else if (avgLatency < 1000 && successRate > 0.6) {
      _currentQuality = NetworkQuality.fair;
    } else {
      _currentQuality = NetworkQuality.poor;
    }
  }
  
  /// Handle connection failure
  void _handleConnectionFailure() {
    _failureCount++;
    _connectionAttempts++;
    _lastAttemptTime = DateTime.now();
    
    // Open circuit breaker if threshold exceeded
    if (_failureCount >= _failureThreshold) {
      _openCircuitBreaker();
    }
    
    // Attempt to reconnect with backoff
    if (!_isReconnecting) {
      _scheduleReconnection();
    }
    
    // Try next server if available
    if (_failureCount % 3 == 0) {
      _tryNextServer();
    }
  }
  
  /// Open circuit breaker
  void _openCircuitBreaker() {
    _circuitOpen = true;
    debugPrint('🔌 Circuit breaker opened');
    
    _notifyStatusChanged(NetworkStatus.circuitOpen);
  }
  
  /// Reset circuit breaker
  void _resetCircuitBreaker() {
    _circuitOpen = false;
    _failureCount = 0;
    debugPrint('🔓 Circuit breaker reset');
    
    _notifyStatusChanged(NetworkStatus.connected);
  }
  
  /// Schedule reconnection with exponential backoff
  void _scheduleReconnection() {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    _notifyStatusChanged(NetworkStatus.reconnecting);
    
    final delay = _calculateBackoffDelay();
    
    debugPrint('🔄 Scheduling reconnection in ${delay.inSeconds}s');
    
    Timer(delay, () async {
      await _attemptConnection();
    });
  }
  
  /// Calculate exponential backoff delay with jitter
  Duration _calculateBackoffDelay() {
    final exponentialDelay = _baseDelay * 
        math.pow(_backoffMultiplier, _connectionAttempts - 1);
    
    final cappedDelay = Duration(
      milliseconds: math.min(
        exponentialDelay.inMilliseconds,
        _maxDelay.inMilliseconds,
      ),
    );
    
    // Add jitter to prevent thundering herd
    final jitter = (cappedDelay.inMilliseconds * _jitterFactor * 
        (math.Random().nextDouble() * 2 - 1)).round();
    
    return Duration(
      milliseconds: (cappedDelay.inMilliseconds + jitter).round(),
    );
  }
  
  /// Attempt connection
  Future<bool> _attemptConnection() async {
    if (_circuitOpen) {
      debugPrint('🔌 Circuit breaker open, skipping connection attempt');
      return false;
    }
    
    try {
      debugPrint('🔌 Attempting connection to $_currentServer');
      
      final response = await http.get(
        Uri.parse('$_currentServer/api/health'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        _handleConnectionSuccess();
        return true;
      } else {
        _handleConnectionFailure();
        return false;
      }
    } catch (e) {
      _handleConnectionFailure();
      final error = NetworkError(
        type: NetworkErrorType.connectionFailed,
        message: e.toString(),
        server: _currentServer!,
        timestamp: DateTime.now(),
      );
      
      _onError.forEach((callback) => callback(error));
      return false;
    }
  }
  
  /// Handle successful connection
  void _handleConnectionSuccess() {
    _isConnected = true;
    _isReconnecting = false;
    _lastConnectedTime = DateTime.now();
    _connectionAttempts = 0;
    _failureCount = 0;
    
    if (_circuitOpen) {
      _resetCircuitBreaker();
    }
    
    debugPrint('✅ Successfully connected to $_currentServer');
    _notifyStatusChanged(NetworkStatus.connected);
  }
  
  /// Try next server in the list
  void _tryNextServer() {
    final allServers = [..._primaryServers, ..._fallbackServers];
    
    if (allServers.isEmpty) return;
    
    _currentServerIndex = (_currentServerIndex + 1) % allServers.length;
    _currentServer = allServers[_currentServerIndex];
    
    debugPrint('🔄 Switching to server: $_currentServer');
    
    final oldServer = _currentServer;
    _onServerSwitch.forEach((callback) => callback(oldServer!, _currentServer!));
  }
  
  /// Attempt recovery
  Future<void> _attemptRecovery() async {
    if (_isConnected || _isReconnecting) return;
    
    // Check if we should attempt recovery based on circuit state
    if (_circuitOpen) {
      final timeSinceOpen = DateTime.now().difference(_lastAttemptTime ?? DateTime.now());
      if (timeSinceOpen < _recoveryTimeout) return;
    }
    
    await _attemptConnection();
  }
  
  /// Make resilient HTTP request
  Future<http.Response> makeRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int? maxRetries,
  }) async {
    maxRetries ??= 3;
    timeout ??= const Duration(seconds: 30);
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      // Check circuit breaker
      if (_circuitOpen) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      
      try {
        final uri = Uri.parse('$_currentServer$endpoint');
        final response = await _executeHttpRequest(
          uri,
          method: method,
          headers: headers,
          body: body,
          timeout: timeout,
        );
        
        // Success - return response
        return response;
      } catch (e) {
        debugPrint('⚠️ Request attempt $attempt failed: $e');
        
        if (attempt == maxRetries) {
          // Final attempt failed - handle as connection failure
          _handleConnectionFailure();
          rethrow;
        } else {
          // Wait before retry
          final retryDelay = Duration(
            milliseconds: (1000 * math.pow(2, attempt)).round(),
          );
          await Future.delayed(retryDelay);
        }
      }
    }
    
    throw Exception('All retry attempts failed');
  }
  
  /// Execute HTTP request with connection pooling
  Future<http.Response> _executeHttpRequest(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    // Get connection from pool or create new one
    final connection = _getConnection();
    
    try {
      final streamedResponse = await connection.request(
        uri,
        method: method,
        headers: headers,
        body: body,
      ).timeout(timeout ?? const Duration(seconds: 30));
      
      // Return connection to pool
      _returnConnection(connection);
      
      return await http.Response.fromStream(streamedResponse);
    } catch (e) {
      // Don't return failed connections to pool
      _activeConnections--;
      rethrow;
    }
  }
  
  /// Get connection from pool
  NetworkConnection _getConnection() {
    if (_connections.isNotEmpty) {
      final connection = _connections.removeLast();
      _activeConnections++;
      return connection;
    }
    
    return NetworkConnection();
  }
  
  /// Return connection to pool
  void _returnConnection(NetworkConnection connection) {
    if (_activeConnections < _maxConnections) {
      connection.reset();
      _connections.add(connection);
    }
    _activeConnections--;
  }
  
  /// Notify status change
  void _notifyStatusChanged(NetworkStatus status) {
    _onStatusChanged.forEach((callback) => callback(status));
  }
  
  /// Add status change listener
  void addStatusChangeListener(Function(NetworkStatus) listener) {
    _onStatusChanged.add(listener);
  }
  
  /// Add health update listener
  void addHealthUpdateListener(Function(NetworkHealth) listener) {
    _onHealthUpdate.add(listener);
  }
  
  /// Add server switch listener
  void addServerSwitchListener(Function(String, String) listener) {
    _onServerSwitch.add(listener);
  }
  
  /// Add error listener
  void addErrorListener(Function(NetworkError) listener) {
    _onError.add(listener);
  }
  
  /// Remove status change listener
  void removeStatusChangeListener(Function(NetworkStatus) listener) {
    _onStatusChanged.remove(listener);
  }
  
  /// Remove health update listener
  void removeHealthUpdateListener(Function(NetworkHealth) listener) {
    _onHealthUpdate.remove(listener);
  }
  
  /// Remove server switch listener
  void removeServerSwitchListener(Function(String, String) listener) {
    _onServerSwitch.remove(listener);
  }
  
  /// Remove error listener
  void removeErrorListener(Function(NetworkError) listener) {
    _onError.remove(listener);
  }
  
  /// Get network statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'connected': _isConnected,
      'reconnecting': _isReconnecting,
      'circuitOpen': _circuitOpen,
      'connectionAttempts': _connectionAttempts,
      'failureCount': _failureCount,
      'currentServer': _currentServer,
      'currentServerIndex': _currentServerIndex,
      'networkQuality': _currentQuality.toString(),
      'activeConnections': _activeConnections,
      'pooledConnections': _connections.length,
      'healthCheckCount': _healthHistory.length,
      'lastConnectedTime': _lastConnectedTime?.toIso8601String(),
      'lastAttemptTime': _lastAttemptTime?.toIso8601String(),
    };
  }
  
  /// Set configuration
  void setConfiguration({
    int? failureThreshold,
    Duration? baseDelay,
    Duration? maxDelay,
    double? backoffMultiplier,
    double? jitterFactor,
    int? maxConnections,
  }) {
    if (failureThreshold != null) _failureThreshold = failureThreshold!;
    if (baseDelay != null) _baseDelay = baseDelay!;
    if (maxDelay != null) _maxDelay = maxDelay!;
    if (backoffMultiplier != null) _backoffMultiplier = backoffMultiplier!;
    if (jitterFactor != null) _jitterFactor = jitterFactor!;
    if (maxConnections != null) _maxConnections = maxConnections!;
    
    debugPrint('⚙️ Network resilience configuration updated');
  }
  
  /// Force reconnection
  Future<void> forceReconnection() async {
    _isConnected = false;
    _isReconnecting = false;
    _connectionAttempts = 0;
    _failureCount = 0;
    _circuitOpen = false;
    
    await _attemptConnection();
  }
  
  /// Test all servers
  Future<Map<String, bool>> testServers() async {
    final allServers = [..._primaryServers, ..._fallbackServers];
    final results = <String, bool>{};
    
    for (final server in allServers) {
      try {
        final response = await http.get(
          Uri.parse('$server/api/health'),
        ).timeout(const Duration(seconds: 5));
        
        results[server] = response.statusCode == 200;
      } catch (e) {
        results[server] = false;
      }
    }
    
    return results;
  }
  
  /// Dispose network resilience
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    _recoveryTimer?.cancel();
    
    // Close all connections
    for (final connection in _connections) {
      connection.close();
    }
    _connections.clear();
    
    // Clear listeners
    _onStatusChanged.clear();
    _onHealthUpdate.clear();
    _onServerSwitch.clear();
    _onError.clear();
    
    _isInitialized = false;
    debugPrint('🌐 Network Resilience disposed');
  }
}

/// Network connection wrapper
class NetworkConnection {
  bool _isActive = false;
  DateTime? _lastUsed;
  
  bool get isActive => _isActive;
  DateTime? get lastUsed => _lastUsed;
  
  Future<http.StreamedResponse> request(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    Object? body,
  }) async {
    _isActive = true;
    _lastUsed = DateTime.now();
    
    try {
      final request = http.Request(method, uri);
      if (headers != null) request.headers.addAll(headers);
      if (body != null) {
        if (body is String) {
          request.body = body;
        } else if (body is List<int>) {
          request.bodyBytes = body;
        } else {
          request.body = body.toString();
        }
      }
      final response = await request.send();
      
      return response;
    } finally {
      _isActive = false;
    }
  }
  
  void reset() {
    _isActive = false;
    _lastUsed = null;
  }
  
  void close() {
    reset();
  }
}

/// Network health status
class NetworkHealth {
  final DateTime timestamp;
  final Duration? latency;
  final bool success;
  final String? error;
  final String server;
  
  NetworkHealth({
    required this.timestamp,
    this.latency,
    required this.success,
    this.error,
    required this.server,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'latency': latency?.inMilliseconds,
      'success': success,
      'error': error,
      'server': server,
    };
  }
}

/// Network quality levels
enum NetworkQuality {
  excellent,
  good,
  fair,
  poor,
}

/// Network status
enum NetworkStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  circuitOpen,
}

/// Network error
class NetworkError {
  final NetworkErrorType type;
  final String message;
  final String server;
  final DateTime timestamp;
  
  NetworkError({
    required this.type,
    required this.message,
    required this.server,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'message': message,
      'server': server,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Network error types
enum NetworkErrorType {
  connectionFailed,
  timeout,
  dnsError,
  sslError,
  serverError,
  circuitOpen,
}
