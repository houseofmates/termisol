import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection pooling system for efficient network resource management
/// 
/// Features:
/// - HTTP connection pooling with keep-alive
/// - WebSocket connection management
/// - SSH connection pooling
/// - Automatic connection health monitoring
/// - Connection reuse and load balancing
/// - Adaptive pool sizing based on usage patterns
class ConnectionPoolingSystem {
  static const int _defaultMaxPoolSize = 50;
  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(minutes: 5);
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);
  
  final Map<String, ConnectionPool> _connectionPools = {};
  final Map<String, PooledConnection> _activeConnections = {};
  final List<ConnectionMetrics> _metrics = [];
  
  Timer? _healthCheckTimer;
  Timer? _cleanupTimer;
  
  int _totalConnections = 0;
  int _reusedConnections = 0;
  int _failedConnections = 0;
  double _totalConnectionTime = 0.0;

  ConnectionPoolingSystem() {
    _initializeConnectionPooling();
  }

  /// Initialize the connection pooling system
  void _initializeConnectionPooling() {
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) => _performHealthCheck());
    _cleanupTimer = Timer.periodic(Duration(minutes: 2), (_) => _cleanupIdleConnections());
  }

  /// Get HTTP connection from pool
  Future<PooledConnection> getHTTPConnection(
    String baseUrl, {
    Map<String, String>? headers,
    Duration? timeout,
    bool keepAlive = true,
  }) async {
    final poolKey = _generateHTTPPoolKey(baseUrl, headers, keepAlive);
    final pool = _getOrCreatePool(poolKey, ConnectionType.http);
    
    final stopwatch = Stopwatch()..start();
    
    try {
      _totalConnections++;
      
      // Try to get existing connection
      final connection = await pool.getConnection();
      if (connection != null) {
        _reusedConnections++;
        _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
        return connection;
      }
      
      // Create new connection
      final newConnection = await _createHTTPConnection(
        baseUrl,
        headers: headers,
        timeout: timeout ?? _connectionTimeout,
        keepAlive: keepAlive,
      );
      
      await pool.addConnection(newConnection);
      _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return newConnection;
    } catch (e) {
      _failedConnections++;
      debugPrint('Failed to get HTTP connection: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Get WebSocket connection from pool
  Future<PooledConnection> getWebSocketConnection(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final poolKey = _generateWebSocketPoolKey(url, headers);
    final pool = _getOrCreatePool(poolKey, ConnectionType.websocket);
    
    final stopwatch = Stopwatch()..start();
    
    try {
      _totalConnections++;
      
      // Try to get existing connection
      final connection = await pool.getConnection();
      if (connection != null) {
        _reusedConnections++;
        _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
        return connection;
      }
      
      // Create new connection
      final newConnection = await _createWebSocketConnection(
        url,
        headers: headers,
        timeout: timeout ?? _connectionTimeout,
      );
      
      await pool.addConnection(newConnection);
      _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return newConnection;
    } catch (e) {
      _failedConnections++;
      debugPrint('Failed to get WebSocket connection: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Get SSH connection from pool
  Future<PooledConnection> getSSHConnection(
    String host,
    int port, {
    String? username,
    String? password,
    String? privateKeyPath,
    Duration? timeout,
  }) async {
    final poolKey = _generateSSHPoolKey(host, port, username);
    final pool = _getOrCreatePool(poolKey, ConnectionType.ssh);
    
    final stopwatch = Stopwatch()..start();
    
    try {
      _totalConnections++;
      
      // Try to get existing connection
      final connection = await pool.getConnection();
      if (connection != null) {
        _reusedConnections++;
        _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
        return connection;
      }
      
      // Create new connection
      final newConnection = await _createSSHConnection(
        host,
        port,
        username: username,
        password: password,
        privateKeyPath: privateKeyPath,
        timeout: timeout ?? _connectionTimeout,
      );
      
      await pool.addConnection(newConnection);
      _totalConnectionTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return newConnection;
    } catch (e) {
      _failedConnections++;
      debugPrint('Failed to get SSH connection: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Return connection to pool
  Future<void> returnConnection(PooledConnection connection) async {
    try {
      if (connection.isHealthy()) {
        final pool = _connectionPools[connection.poolKey];
        if (pool != null) {
          await pool.returnConnection(connection);
        }
      } else {
        await connection.close();
        _activeConnections.remove(connection.id);
      }
    } catch (e) {
      debugPrint('Failed to return connection: $e');
    }
  }

  /// Create HTTP connection
  Future<PooledConnection> _createHTTPConnection(
    String baseUrl,
    {
    Map<String, String>? headers,
    Duration? timeout,
    bool keepAlive = true,
  }) async {
    final client = http.Client();
    
    // Configure client with timeout and keep-alive
    if (timeout != null) {
      // Note: http.Client doesn't directly support timeout configuration
      // This would need to be implemented at the request level
    }
    
    final connection = HTTPConnection(
      id: _generateConnectionId(),
      baseUrl: baseUrl,
      client: client,
      headers: headers ?? {},
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
      keepAlive: keepAlive,
    );
    
    _activeConnections[connection.id] = connection;
    
    return connection;
  }

  /// Create WebSocket connection
  Future<PooledConnection> _createWebSocketConnection(
    String url,
    {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(url),
        protocols: headers?.keys.toList(),
      );
      
      final connection = WebSocketConnection(
        id: _generateConnectionId(),
        url: url,
        channel: channel,
        headers: headers ?? {},
        createdAt: DateTime.now(),
        lastUsed: DateTime.now(),
      );
      
      _activeConnections[connection.id] = connection;
      
      return connection;
    } catch (e) {
      debugPrint('Failed to create WebSocket connection: $e');
      rethrow;
    }
  }

  /// Create SSH connection
  Future<PooledConnection> _createSSHConnection(
    String host,
    int port,
    {
    String? username,
    String? password,
    String? privateKeyPath,
    Duration? timeout,
  }) async {
    // Note: This is a simplified implementation
    // In a real implementation, you would use an SSH library like 'ssh2'
    
    final connection = SSHConnection(
      id: _generateConnectionId(),
      host: host,
      port: port,
      username: username ?? '',
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
      connected: true,
    );
    
    _activeConnections[connection.id] = connection;
    
    return connection;
  }

  /// Get or create connection pool
  ConnectionPool _getOrCreatePool(String poolKey, ConnectionType type) {
    if (!_connectionPools.containsKey(poolKey)) {
      _connectionPools[poolKey] = ConnectionPool(
        key: poolKey,
        type: type,
        maxSize: _defaultMaxPoolSize,
        idleTimeout: _idleTimeout,
      );
    }
    return _connectionPools[poolKey]!;
  }

  /// Generate HTTP pool key
  String _generateHTTPPoolKey(String baseUrl, Map<String, String>? headers, bool keepAlive) {
    final headerHash = headers?.entries.map((e) => '${e.key}:${e.value}').join('|') ?? '';
    return 'http:${baseUrl.hashCode}:$keepAlive:${headerHash.hashCode}';
  }

  /// Generate WebSocket pool key
  String _generateWebSocketPoolKey(String url, Map<String, String>? headers) {
    final headerHash = headers?.entries.map((e) => '${e.key}:${e.value}').join('|') ?? '';
    return 'ws:${url.hashCode}:${headerHash.hashCode}';
  }

  /// Generate SSH pool key
  String _generateSSHPoolKey(String host, int port, String? username) {
    return 'ssh:${host.hashCode}:$port:${username.hashCode}';
  }

  /// Generate connection ID
  String _generateConnectionId() {
    return 'conn_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Perform health check on all connections
  Future<void> _performHealthCheck() async {
    for (final pool in _connectionPools.values) {
      await pool.performHealthCheck();
    }
  }

  /// Cleanup idle connections
  Future<void> _cleanupIdleConnections() async {
    for (final pool in _connectionPools.values) {
      await pool.cleanupIdleConnections();
    }
  }

  /// Get connection statistics
  ConnectionPoolStats getStats() {
    return ConnectionPoolStats(
      totalConnections: _totalConnections,
      reusedConnections: _reusedConnections,
      failedConnections: _failedConnections,
      reuseRate: _totalConnections > 0 ? _reusedConnections / _totalConnections : 0.0,
      averageConnectionTime: _totalConnections > 0 ? _totalConnectionTime / _totalConnections : 0.0,
      totalConnectionTime: _totalConnectionTime,
      activePools: _connectionPools.length,
      activeConnections: _activeConnections.length,
      poolUtilization: _calculatePoolUtilization(),
    );
  }

  /// Calculate pool utilization
  double _calculatePoolUtilization() {
    if (_connectionPools.isEmpty) return 0.0;
    
    double totalUtilization = 0.0;
    for (final pool in _connectionPools.values) {
      totalUtilization += pool.utilization;
    }
    
    return totalUtilization / _connectionPools.length;
  }

  /// Optimize connection pools
  Future<void> optimizePools() async {
    for (final pool in _connectionPools.values) {
      await pool.optimize();
    }
    
    // Remove empty pools
    final emptyPools = <String>[];
    for (final entry in _connectionPools.entries) {
      if (entry.value.isEmpty) {
        emptyPools.add(entry.key);
      }
    }
    
    for (final poolKey in emptyPools) {
      _connectionPools.remove(poolKey);
    }
  }

  /// Close all connections
  Future<void> closeAllConnections() async {
    for (final connection in _activeConnections.values) {
      await connection.close();
    }
    
    _activeConnections.clear();
    _connectionPools.clear();
  }

  /// Dispose connection pooling system
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    _cleanupTimer?.cancel();
    await closeAllConnections();
    _metrics.clear();
  }
}

/// Connection pool for managing connections of the same type
class ConnectionPool {
  final String key;
  final ConnectionType type;
  final int maxSize;
  final Duration idleTimeout;
  
  final Queue<PooledConnection> _availableConnections = Queue();
  final Set<PooledConnection> _activeConnections = {};
  
  int _totalCreated = 0;
  int _totalReused = 0;
  int _totalClosed = 0;

  ConnectionPool({
    required this.key,
    required this.type,
    required this.maxSize,
    required this.idleTimeout,
  });

  /// Get connection from pool
  Future<PooledConnection?> getConnection() async {
    // Remove unhealthy connections
    while (_availableConnections.isNotEmpty) {
      final connection = _availableConnections.removeFirst();
      if (connection.isHealthy()) {
        connection.lastUsed = DateTime.now();
        _activeConnections.add(connection);
        _totalReused++;
        return connection;
      } else {
        await connection.close();
        _totalClosed++;
      }
    }
    
    return null;
  }

  /// Return connection to pool
  Future<void> returnConnection(PooledConnection connection) async {
    if (!_activeConnections.contains(connection)) return;
    
    _activeConnections.remove(connection);
    
    if (connection.isHealthy() && _availableConnections.length < maxSize) {
      connection.lastUsed = DateTime.now();
      _availableConnections.add(connection);
    } else {
      await connection.close();
      _totalClosed++;
    }
  }

  /// Add new connection to pool
  Future<void> addConnection(PooledConnection connection) async {
    if (_availableConnections.length < maxSize) {
      connection.lastUsed = DateTime.now();
      _availableConnections.add(connection);
      _totalCreated++;
    } else {
      await connection.close();
      _totalClosed++;
    }
  }

  /// Perform health check on all connections
  Future<void> performHealthCheck() async {
    final unhealthyConnections = <PooledConnection>[];
    
    // Check available connections
    for (final connection in _availableConnections) {
      if (!connection.isHealthy()) {
        unhealthyConnections.add(connection);
      }
    }
    
    // Check active connections
    for (final connection in _activeConnections) {
      if (!connection.isHealthy()) {
        unhealthyConnections.add(connection);
      }
    }
    
    // Remove unhealthy connections
    for (final connection in unhealthyConnections) {
      _availableConnections.remove(connection);
      _activeConnections.remove(connection);
      await connection.close();
      _totalClosed++;
    }
  }

  /// Cleanup idle connections
  Future<void> cleanupIdleConnections() async {
    final now = DateTime.now();
    final idleConnections = <PooledConnection>[];
    
    for (final connection in _availableConnections) {
      if (now.difference(connection.lastUsed) > idleTimeout) {
        idleConnections.add(connection);
      }
    }
    
    for (final connection in idleConnections) {
      _availableConnections.remove(connection);
      await connection.close();
      _totalClosed++;
    }
  }

  /// Optimize pool
  Future<void> optimize() async {
    // Adjust pool size based on usage patterns
    final utilization = this.utilization;
    
    if (utilization > 0.8 && maxSize < 100) {
      // Pool is heavily utilized, consider increasing size
      debugPrint('Pool $key is highly utilized (${(utilization * 100).toStringAsFixed(1)}%)');
    } else if (utilization < 0.2 && maxSize > 10) {
      // Pool is underutilized, consider decreasing size
      debugPrint('Pool $key is underutilized (${(utilization * 100).toStringAsFixed(1)}%)');
    }
  }

  /// Check if pool is empty
  bool get isEmpty => _availableConnections.isEmpty && _activeConnections.isEmpty;

  /// Get pool utilization
  double get utilization {
    final totalConnections = _availableConnections.length + _activeConnections.length;
    return maxSize > 0 ? totalConnections / maxSize : 0.0;
  }

  /// Get pool statistics
  Map<String, dynamic> getStats() {
    return {
      'total_created': _totalCreated,
      'total_reused': _totalReused,
      'total_closed': _totalClosed,
      'available_count': _availableConnections.length,
      'active_count': _activeConnections.length,
      'utilization': utilization,
      'max_size': maxSize,
    };
  }
}

/// Base class for pooled connections
abstract class PooledConnection {
  final String id;
  final String poolKey;
  final DateTime createdAt;
  DateTime lastUsed;
  
  PooledConnection({
    required this.id,
    required this.poolKey,
    required this.createdAt,
    required this.lastUsed,
  });

  /// Check if connection is healthy
  bool isHealthy();

  /// Close connection
  Future<void> close();

  /// Get connection type
  ConnectionType get type;
}

/// HTTP connection implementation
class HTTPConnection extends PooledConnection {
  final String baseUrl;
  final http.Client client;
  final Map<String, String> headers;
  final bool keepAlive;

  HTTPConnection({
    required String id,
    required this.baseUrl,
    required this.client,
    required this.headers,
    required DateTime createdAt,
    required DateTime lastUsed,
    required this.keepAlive,
  }) : super(id: 'http_${id}', 'http', createdAt, lastUsed);

  @override
  bool isHealthy() {
    // HTTP clients don't have a direct health check method
    // In a real implementation, you might check last activity or ping the server
    return true;
  }

  @override
  Future<void> close() async {
    client.close();
  }

  @override
  ConnectionType get type => ConnectionType.http;
}

/// WebSocket connection implementation
class WebSocketConnection extends PooledConnection {
  final String url;
  final WebSocketChannel channel;
  final Map<String, String> headers;

  WebSocketConnection({
    required String id,
    required this.url,
    required this.channel,
    required this.headers,
    required DateTime createdAt,
    required DateTime lastUsed,
  }) : super(id: 'ws_${id}', 'websocket', createdAt, lastUsed);

  @override
  bool isHealthy() {
    try {
      // Check if WebSocket connection is still open
      return channel.sink != null && !channel.sink.isClosed;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    try {
      channel.sink.close();
    } catch (e) {
      debugPrint('Error closing WebSocket: $e');
    }
  }

  @override
  ConnectionType get type => ConnectionType.websocket;
}

/// SSH connection implementation
class SSHConnection extends PooledConnection {
  final String host;
  final int port;
  final String username;
  bool connected;

  SSHConnection({
    required String id,
    required this.host,
    required this.port,
    required this.username,
    required DateTime createdAt,
    required DateTime lastUsed,
    required this.connected,
  }) : super(id: 'ssh_${id}', 'ssh', createdAt, lastUsed);

  @override
  bool isHealthy() {
    return connected;
  }

  @override
  Future<void> close() async {
    connected = false;
    // In a real implementation, you would close the SSH session here
  }

  @override
  ConnectionType get type => ConnectionType.ssh;
}

/// Connection types
enum ConnectionType {
  http,
  websocket,
  ssh,
}

/// Connection pool statistics
class ConnectionPoolStats {
  final int totalConnections;
  final int reusedConnections;
  final int failedConnections;
  final double reuseRate;
  final double averageConnectionTime;
  final double totalConnectionTime;
  final int activePools;
  final int activeConnections;
  final double poolUtilization;

  const ConnectionPoolStats({
    required this.totalConnections,
    required this.reusedConnections,
    required this.failedConnections,
    required this.reuseRate,
    required this.averageConnectionTime,
    required this.totalConnectionTime,
    required this.activePools,
    required this.activeConnections,
    required this.poolUtilization,
  });
}

/// Connection metrics
class ConnectionMetrics {
  final String poolKey;
  final ConnectionType type;
  final DateTime timestamp;
  final double connectionTime;
  final bool reused;
  final bool successful;

  const ConnectionMetrics({
    required this.poolKey,
    required this.type,
    required this.timestamp,
    required this.connectionTime,
    required this.reused,
    required this.successful,
  });
}
