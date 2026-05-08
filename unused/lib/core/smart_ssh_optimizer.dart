import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Smart SSH optimization for .250/.233 machines
class SmartSSHOptimizer {
  final Map<String, SSHConnection> _connections = {};
  final List<ConnectionPool> _pools = [];
  final Map<String, int> _usageCounts = {};
  final Map<String, double> _latencyMetrics = {};
  
  Timer? _monitoringTimer;
  Timer? _optimizationTimer;
  StreamController<SSHEvent> _eventController = StreamController<SSHEvent>.broadcast();
  Stream<SSHEvent> get events => _eventController.stream;
  
  void initialize() {
    _setupMonitoring();
    _setupOptimization();
    _initializeConnectionPools();
    developer.log('Smart SSH Optimizer initialized');
  }
  
  void _setupMonitoring() {
    _monitoringTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _monitorConnections();
    });
  }
  
  void _setupOptimization() {
    _optimizationTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _optimizeConnections();
    });
  }
  
  void _initializeConnectionPools() {
    // Create connection pools for different hosts
    _pools.add(ConnectionPool(
      host: '192.168.4.250',
      maxConnections: 5,
      preferredUser: 'house',
      priority: PoolPriority.high,
    ));
    
    _pools.add(ConnectionPool(
      host: '192.168.4.233',
      maxConnections: 3,
      preferredUser: 'house',
      priority: PoolPriority.medium,
    ));
    
    _pools.add(ConnectionPool(
      host: 'localhost',
      maxConnections: 10,
      priority: PoolPriority.low,
    ));
  }
  
  void _monitorConnections() {
    for (final pool in _pools) {
      _monitorPool(pool);
    }
  }
  
  void _monitorPool(ConnectionPool pool) {
    final activeConnections = pool.connections.where((conn) => conn.isActive).length;
    final queuedConnections = pool.connections.where((conn) => conn.isQueued).length;
    
    // Update usage metrics
    _usageCounts[pool.host] = activeConnections + queuedConnections;
    
    // Check for optimization opportunities
    if (activeConnections == 0 && queuedConnections > 0) {
      _closeIdleConnections(pool);
    }
    
    // Monitor latency
    for (final connection in pool.connections) {
      if (connection.isActive) {
        _updateLatencyMetrics(connection);
      }
    }
    
    _eventController.add(SSHEvent(
      type: SSHEventType.poolStatus,
      data: {
        'host': pool.host,
        'activeConnections': activeConnections,
        'queuedConnections': queuedConnections,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }
  
  void _optimizeConnections() {
    for (final pool in _pools) {
      _optimizePool(pool);
    }
  }
  
  void _optimizePool(ConnectionPool pool) {
    // Close idle connections
    _closeIdleConnections(pool);
    
    // Rebalance connections based on usage patterns
    _rebalanceConnections(pool);
    
    // Pre-warm connections for likely usage
    _prewarmConnections(pool);
    
    _eventController.add(SSHEvent(
      type: SSHEventType.optimizationPerformed,
      data: {
        'host': pool.host,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }
  
  void _closeIdleConnections(SSHConnection connection) {
    final idleConnections = connection.connections.where((conn) => 
        conn.isActive && _isConnectionIdle(conn));
    
    for (final conn in idleConnections) {
      _closeConnection(conn);
    }
  }
  
  void _closeIdleConnections(ConnectionPool pool) {
    final idleConnections = pool.connections.where((conn) => 
        conn.isActive && _isConnectionIdle(conn));
    
    for (final conn in idleConnections) {
      _closeConnection(conn);
    }
  }
  
  bool _isConnectionIdle(SSHConnection connection) {
    final timeSinceLastUse = DateTime.now().difference(connection.lastUsed).inMinutes;
    return timeSinceLastUse > 10; // Idle for 10 minutes
  }
  
  void _rebalanceConnections(ConnectionPool pool) {
    // Move connections between pools based on load
    final overloadedPools = _pools.where((p) => _isPoolOverloaded(p));
    final underloadedPools = _pools.where((p) => !_isPoolOverloaded(p));
    
    if (overloadedPools.isNotEmpty && underloadedPools.isNotEmpty) {
      final sourcePool = underloadedPools.first;
      final targetPool = overloadedPools.first;
      
      _moveConnection(sourcePool, targetPool);
    }
  }
  
  bool _isPoolOverloaded(ConnectionPool pool) {
    final activeConnections = pool.connections.where((conn) => conn.isActive).length;
    return activeConnections > pool.maxConnections * 0.8;
  }
  
  void _prewarmConnections(ConnectionPool pool) {
    // Pre-warm connections based on usage patterns
    final usagePattern = _getUsagePattern(pool.host);
    
    switch (usagePattern) {
      case UsagePattern.morning:
        _prewarmForPattern(pool, 2);
        break;
      case UsagePattern.workday:
        _prewarmForPattern(pool, 3);
        break;
      case UsagePattern.evening:
        _prewarmForPattern(pool, 2);
        break;
      case UsagePattern.weekend:
        _prewarmForPattern(pool, 1);
        break;
    }
  }
  
  void _prewarmForPattern(ConnectionPool pool, int count) {
    final availableConnections = pool.connections.where((conn) => !conn.isActive).take(count);
    
    for (final conn in availableConnections) {
      conn.prewarm();
    }
    
    _eventController.add(SSHEvent(
      type: SSHEventType.connectionsPrewarmed,
      data: {
        'host': pool.host,
        'count': count,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }
  
  void _updateLatencyMetrics(SSHConnection connection) {
    final latency = _measureLatency(connection);
    _latencyMetrics[connection.id] = latency;
    
    if (latency > 1000) { // High latency threshold
      _eventController.add(SSHEvent(
        type: SSHEventType.highLatency,
        data: {
          'connectionId': connection.id,
          'latency': latency,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }
  }
  
  double _measureLatency(SSHConnection connection) {
    // Simulate latency measurement
    // In real implementation, this would use actual ping times
    return 50.0 + math.Random().nextDouble() * 100;
  }
  
  UsagePattern _getUsagePattern(String host) {
    final hour = DateTime.now().hour;
    
    if (hour >= 6 && hour < 12) {
      return UsagePattern.morning;
    } else if (hour >= 12 && hour < 18) {
      return UsagePattern.workday;
    } else if (hour >= 18 && hour < 22) {
      return UsagePattern.evening;
    } else {
      return UsagePattern.weekend;
    }
  }
  
  Future<SSHConnection> getConnection(String host, {
    String purpose = 'general',
    bool priority = false,
  }) async {
    final pool = _pools.firstWhere((p) => p.host == host);
    
    // Try to get existing connection
    final existingConnection = pool.connections.firstWhere(
      (conn) => conn.isActive && conn.purpose == purpose,
      orElse: () => SSHConnection.inactive(),
    );
    
    if (existingConnection.isActive) {
      return existingConnection;
    }
    
    // Create new connection if pool has capacity
    if (pool.connections.length < pool.maxConnections) {
      final newConnection = SSHConnection(
        id: '${host}_${DateTime.now().millisecondsSinceEpoch}',
        host: host,
        purpose: purpose,
        priority: priority,
      );
      
      pool.connections.add(newConnection);
      await newConnection.connect();
      
      _eventController.add(SSHEvent(
        type: SSHEventType.connectionCreated,
        data: {
          'connectionId': newConnection.id,
          'host': host,
          'purpose': purpose,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
      
      return newConnection;
    }
    
    // Queue connection if no capacity
    final queuedConnection = SSHConnection(
      id: '${host}_${DateTime.now().millisecondsSinceEpoch}_queued',
      host: host,
      purpose: purpose,
      priority: priority,
    );
    
    queuedConnection.isQueued = true;
    pool.connections.add(queuedConnection);
    
    _eventController.add(SSHEvent(
      type: SSHEventType.connectionQueued,
      data: {
        'connectionId': queuedConnection.id,
        'host': host,
        'purpose': purpose,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
    
    return queuedConnection;
  }
  
  void releaseConnection(SSHConnection connection) {
    connection.isActive = false;
    connection.lastUsed = DateTime.now();
    
    _eventController.add(SSHEvent(
      type: SSHEventType.connectionReleased,
      data: {
        'connectionId': connection.id,
        'host': connection.host,
        'duration': DateTime.now().difference(connection.createdAt).inMinutes,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }
  
  void _moveConnection(ConnectionPool sourcePool, ConnectionPool targetPool) {
    final availableConnections = sourcePool.connections.where((conn) => !conn.isActive).take(1);
    
    if (availableConnections.isNotEmpty) {
      final connection = availableConnections.first;
      sourcePool.connections.remove(connection);
      targetPool.connections.add(connection);
      
      _eventController.add(SSHEvent(
        type: SSHEventType.connectionMoved,
        data: {
          'connectionId': connection.id,
          'sourceHost': sourcePool.host,
          'targetHost': targetPool.host,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }
  }
  
  void _closeConnection(SSHConnection connection) {
    connection.isActive = false;
    connection.lastUsed = DateTime.now();
    
    _eventController.add(SSHEvent(
      type: SSHEventType.connectionClosed,
      data: {
        'connectionId': connection.id,
        'host': connection.host,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }
  
  Map<String, double> getLatencyMetrics() {
    return Map.from(_latencyMetrics);
  }
  
  Map<String, int> getConnectionCounts() {
    return Map.from(_usageCounts);
  }
  
  void dispose() {
    _monitoringTimer?.cancel();
    _optimizationTimer?.cancel();
    _eventController.close();
    
    // Close all connections
    for (final pool in _pools) {
      for (final connection in pool.connections) {
        if (connection.isActive) {
          connection.close();
        }
      }
    }
  }
}

class ConnectionPool {
  final String host;
  final int maxConnections;
  final String preferredUser;
  final PoolPriority priority;
  final List<SSHConnection> connections;
  
  ConnectionPool({
    required this.host,
    required this.maxConnections,
    required this.preferredUser,
    required this.priority,
  }) : connections = [];
}

class SSHConnection {
  final String id;
  final String host;
  final String purpose;
  final bool priority;
  final DateTime createdAt;
  DateTime lastUsed;
  bool isActive;
  bool isQueued;
  bool isPrewarmed;
  
  SSHConnection({
    required this.id,
    required this.host,
    required this.purpose,
    required this.priority,
    this.createdAt = DateTime.now(),
    this.lastUsed = DateTime.now(),
    this.isActive = false,
    this.isQueued = false,
    this.isPrewarmed = false,
  });
  
  Future<void> connect() async {
    isActive = true;
    isQueued = false;
    lastUsed = DateTime.now();
    
    // Simulate connection establishment
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  void prewarm() {
    isPrewarmed = true;
  }
  
  void close() {
    isActive = false;
    lastUsed = DateTime.now();
  }
}

enum UsagePattern {
  morning,
  workday,
  evening,
  weekend,
}

enum PoolPriority {
  high,
  medium,
  low,
}

enum SSHEventType {
  connectionCreated,
  connectionQueued,
  connectionReleased,
  connectionClosed,
  connectionMoved,
  poolStatus,
  optimizationPerformed,
  connectionsPrewarmed,
  highLatency,
}

class SSHEvent {
  final SSHEventType type;
  final Map<String, dynamic> data;
  
  SSHEvent({
    required this.type,
    required this.data,
  });
}
