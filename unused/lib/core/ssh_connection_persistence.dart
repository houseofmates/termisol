import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class SSHConnectionPersistence {
  static const int _maxConnections = 50;
  static const int _connectionTimeout = 30000; // 30 seconds
  static const int _keepAliveInterval = 60000; // 1 minute
  static const String _connectionDataFile = '/home/house/.termisol_ssh_connections.json';
  
  final Map<String, PersistentSSHConnection> _connections = {};
  final Map<String, ConnectionHealth> _healthStatus = {};
  final List<ConnectionAttempt> _connectionAttempts = [];
  
  Timer? _keepAliveTimer;
  Timer? _healthCheckTimer;
  Timer? _cleanupTimer;
  
  int _totalConnections = 0;
  int _reconnectedConnections = 0;
  
  final StreamController<SSHEvent> _sshController = 
      StreamController<SSHEvent>.broadcast();

  void initialize() {
    _loadConnections();
    _startTimers();
    developer.log('🔌 SSH Connection Persistence initialized');
  }

  void _loadConnections() {
    try {
      final file = File(_connectionDataFile);
      if (!file.existsSync()) {
        developer.log('🔌 No existing connections file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['connections']) {
        final connection = PersistentSSHConnection.fromJson(entry);
        _connections[connection.id] = connection;
        _totalConnections++;
        
        // Start health monitoring
        _startHealthMonitoring(connection);
      }
      
      developer.log('🔌 Loaded ${_connections.length} persistent connections');
      
    } catch (e) {
      developer.log('🔌 Failed to load connections: $e');
    }
  }

  void _startTimers() {
    _keepAliveTimer = Timer.periodic(
      Duration(milliseconds: _keepAliveInterval),
      (_) => _sendKeepAlive(),
    );
    
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: 30),
      (_) => _checkConnectionHealth(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _cleanupDeadConnections(),
    );
  }

  Future<String> createPersistentConnection({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPath,
    Map<String, dynamic>? options,
  }) async {
    if (_connections.length >= _maxConnections) {
      throw Exception('Maximum persistent connections reached');
    }
    
    final connectionId = _generateConnectionId();
    
    final connection = PersistentSSHConnection(
      id: connectionId,
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: privateKeyPath ?? '/home/house/.ssh/hermes_key',
      options: options ?? {},
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
      status: ConnectionStatus.connecting,
      reconnectAttempts: 0,
      maxReconnectAttempts: 5,
      reconnectDelay: Duration(seconds: 5),
      keepAlive: true,
      autoReconnect: true,
    );
    
    _connections[connectionId] = connection;
    _totalConnections++;
    
    try {
      await _establishConnection(connection);
      
      developer.log('🔌 Created persistent connection: $connectionId to $username@$host:$port');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionCreated,
        connectionId: connectionId,
        host: host,
        port: port,
        username: username,
      ));
      
      // Save connections
      await _saveConnections();
      
      // Start health monitoring
      _startHealthMonitoring(connection);
      
      return connectionId;
      
    } catch (e) {
      connection.status = ConnectionStatus.failed;
      connection.lastError = e.toString();
      connection.lastErrorTime = DateTime.now();
      
      developer.log('🔌 Failed to create persistent connection: $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _establishConnection(PersistentSSHConnection connection) async {
    final attempt = ConnectionAttempt(
      id: _generateAttemptId(),
      connectionId: connection.id,
      timestamp: DateTime.now(),
      host: connection.host,
      port: connection.port,
      username: connection.username,
    );
    
    _connectionAttempts.add(attempt);
    
    try {
      // Simulate SSH connection establishment
      // In practice, this would use SSH client library
      
      developer.log('🔌 Establishing SSH connection to ${connection.username}@${connection.host}:${connection.port}');
      
      // Simulate connection process
      await Future.delayed(Duration(seconds: 2));
      
      // Check if key file exists
      final keyFile = File(connection.privateKeyPath);
      if (!keyFile.existsSync()) {
        throw Exception('SSH key not found: ${connection.privateKeyPath}');
      }
      
      // Simulate successful connection
      connection.status = ConnectionStatus.connected;
      connection.connectedAt = DateTime.now();
      connection.lastUsed = DateTime.now();
      connection.reconnectAttempts = 0;
      
      // Initialize health status
      _healthStatus[connection.id] = ConnectionHealth(
        connectionId: connection.id,
        isHealthy: true,
        lastCheck: DateTime.now(),
        responseTime: 100, // ms
        packetsLost: 0,
        uptime: Duration.zero,
      );
      
      developer.log('🔌 SSH connection established: ${connection.id}');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionEstablished,
        connectionId: connection.id,
      ));
      
    } catch (e) {
      connection.status = ConnectionStatus.failed;
      connection.lastError = e.toString();
      connection.lastErrorTime = DateTime.now();
      
      developer.log('🔌 SSH connection failed: ${connection.id} - $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionFailed,
        connectionId: connection.id,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> executeCommand({
    required String connectionId,
    required String command,
    Duration? timeout,
    Map<String, dynamic>? environment,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    if (connection.status != ConnectionStatus.connected) {
      throw Exception('Connection not active: $connectionId');
    }
    
    try {
      developer.log('🔌 Executing command on $connectionId: $command');
      
      // Simulate command execution
      final startTime = DateTime.now();
      
      // In practice, this would send command through SSH channel
      final result = await _executeSSHCommand(connection, command, timeout ?? Duration(seconds: 30));
      
      final endTime = DateTime.now();
      final executionTime = endTime.difference(startTime);
      
      connection.lastUsed = endTime;
      connection.commandCount = (connection.commandCount ?? 0) + 1;
      
      developer.log('🔌 Command executed successfully on $connectionId in ${executionTime.inMilliseconds}ms');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.commandExecuted,
        connectionId: connectionId,
        command: command,
        result: result,
        executionTime: executionTime,
      ));
      
    } catch (e) {
      developer.log('🔌 Command execution failed on $connectionId: $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.commandFailed,
        connectionId: connectionId,
        command: command,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<SSHCommandResult> _executeSSHCommand(
    PersistentSSHConnection connection,
    String command,
    Duration timeout,
  ) async {
    // Simulate SSH command execution
    // In practice, this would use SSH client to execute command
    
    await Future.delayed(Duration(milliseconds: 500));
    
    // Simulate command output
    final output = 'Command executed: $command\nExit status: 0';
    final exitCode = 0;
    
    return SSHCommandResult(
      command: command,
      output: output,
      error: '',
      exitCode: exitCode,
      executionTime: Duration(milliseconds: 500),
    );
  }

  Future<void> disconnect(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    try {
      // Close SSH connection
      connection.status = ConnectionStatus.disconnected;
      connection.disconnectedAt = DateTime.now();
      
      // Stop health monitoring
      _healthStatus.remove(connectionId);
      
      developer.log('🔌 Disconnected SSH connection: $connectionId');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionDisconnected,
        connectionId: connectionId,
      ));
      
      // Save connections
      await _saveConnections();
      
    } catch (e) {
      developer.log('🔌 Failed to disconnect SSH connection: $connectionId - $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.disconnectionFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> reconnect(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    if (!connection.autoReconnect) {
      throw Exception('Auto-reconnect disabled for connection: $connectionId');
    }
    
    try {
      connection.status = ConnectionStatus.reconnecting;
      connection.reconnectAttempts++;
      connection.lastReconnectAttempt = DateTime.now();
      
      developer.log('🔌 Reconnecting SSH connection: $connectionId (attempt ${connection.reconnectAttempts})');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.reconnecting,
        connectionId: connectionId,
        attempt: connection.reconnectAttempts,
      ));
      
      // Wait before reconnect attempt
      await Future.delayed(connection.reconnectDelay);
      
      // Attempt to re-establish connection
      await _establishConnection(connection);
      
      if (connection.status == ConnectionStatus.connected) {
        _reconnectedConnections++;
        
        developer.log('🔌 SSH connection reconnected successfully: $connectionId');
        
        _emitEvent(SSHEvent(
          type: SSHEventType.reconnected,
          connectionId: connectionId,
          attempts: connection.reconnectAttempts,
        ));
      } else {
        // Schedule next reconnect attempt if within limits
        if (connection.reconnectAttempts < connection.maxReconnectAttempts) {
          Timer(connection.reconnectDelay, () => reconnect(connectionId));
        } else {
          connection.status = ConnectionStatus.failed;
          connection.lastError = 'Max reconnect attempts reached';
          connection.lastErrorTime = DateTime.now();
          
          developer.log('🔌 Max reconnect attempts reached for $connectionId');
        }
      }
      
    } catch (e) {
      developer.log('🔌 Reconnection failed for $connectionId: $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.reconnectFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  void _startHealthMonitoring(PersistentSSHConnection connection) {
    _healthStatus[connection.id] = ConnectionHealth(
      connectionId: connection.id,
      isHealthy: true,
      lastCheck: DateTime.now(),
      responseTime: 100,
      packetsLost: 0,
      uptime: Duration.zero,
    );
  }

  void _sendKeepAlive() {
    for (final connection in _connections.values) {
      if (connection.status == ConnectionStatus.connected && connection.keepAlive) {
        _sendKeepAliveToConnection(connection);
      }
    }
  }

  Future<void> _sendKeepAliveToConnection(PersistentSSHConnection connection) async {
    try {
      // Send keep-alive packet
      // In practice, this would send SSH keep-alive or execute a simple command
      
      final health = _healthStatus[connection.id];
      if (health != null) {
        health.lastCheck = DateTime.now();
        health.isHealthy = true;
      }
      
      developer.log('🔌 Sent keep-alive to connection: ${connection.id}');
      
    } catch (e) {
      developer.log('🔌 Keep-alive failed for connection ${connection.id}: $e');
      
      final health = _healthStatus[connection.id];
      if (health != null) {
        health.isHealthy = false;
      }
      
      // Trigger reconnection if enabled
      if (connection.autoReconnect) {
        reconnect(connection.id);
      }
    }
  }

  void _checkConnectionHealth() {
    for (final connection in _connections.values) {
      if (connection.status == ConnectionStatus.connected) {
        _checkIndividualConnectionHealth(connection);
      }
    }
  }

  Future<void> _checkIndividualConnectionHealth(PersistentSSHConnection connection) async {
    try {
      final health = _healthStatus[connection.id];
      if (health == null) return;
      
      // Simulate health check
      final startTime = DateTime.now();
      
      // Execute a simple command to check responsiveness
      await _executeSSHCommand(connection, 'echo "health_check"', Duration(seconds: 5));
      
      final endTime = DateTime.now();
      final responseTime = endTime.difference(startTime).inMilliseconds;
      
      // Update health status
      health.lastCheck = DateTime.now();
      health.responseTime = responseTime;
      health.isHealthy = responseTime < 5000; // 5 second threshold
      health.uptime = health.uptime + Duration(seconds: 30);
      
      if (!health.isHealthy) {
        developer.log('🔌 Connection health check failed for ${connection.id}: ${responseTime}ms');
        
        // Trigger reconnection if enabled
        if (connection.autoReconnect) {
          reconnect(connection.id);
        }
      }
      
    } catch (e) {
      developer.log('🔌 Health check failed for connection ${connection.id}: $e');
      
      final health = _healthStatus[connection.id];
      if (health != null) {
        health.isHealthy = false;
      }
      
      // Trigger reconnection if enabled
      if (connection.autoReconnect) {
        reconnect(connection.id);
      }
    }
  }

  void _cleanupDeadConnections() {
    final now = DateTime.now();
    final connectionsToRemove = <String>[];
    
    for (final entry in _connections.entries) {
      final connection = entry.value;
      final health = _healthStatus[connection.id];
      
      bool shouldRemove = false;
      String reason = '';
      
      // Remove connections that have been disconnected too long
      if (connection.status == ConnectionStatus.disconnected && 
          connection.disconnectedAt != null &&
          now.difference(connection.disconnectedAt!).inHours > 24) {
        shouldRemove = true;
        reason = 'Disconnected for > 24 hours';
      }
      
      // Remove failed connections
      if (connection.status == ConnectionStatus.failed &&
          connection.lastErrorTime != null &&
          now.difference(connection.lastErrorTime!).inHours > 1) {
        shouldRemove = true;
        reason = 'Failed for > 1 hour';
      }
      
      // Remove connections with poor health
      if (health != null && !health.isHealthy &&
          now.difference(health.lastCheck).inMinutes > 5) {
        shouldRemove = true;
        reason = 'Poor health for > 5 minutes';
      }
      
      if (shouldRemove) {
        connectionsToRemove.add(entry.key);
        developer.log('🔌 Cleaning up connection ${connection.id}: $reason');
      }
    }
    
    // Remove dead connections
    for (final connectionId in connectionsToRemove) {
      _connections.remove(connectionId);
      _healthStatus.remove(connectionId);
    }
    
    if (connectionsToRemove.isNotEmpty) {
      _saveConnections();
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionsCleaned,
        connectionIds: connectionsToRemove,
      ));
    }
  }

  Future<void> _saveConnections() async {
    try {
      final file = File(_connectionDataFile);
      
      final connectionsData = _connections.values.map((conn) => conn.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'connections': connectionsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('🔌 Saved ${connectionsData.length} persistent connections');
      
    } catch (e) {
      developer.log('🔌 Failed to save connections: $e');
    }
  }

  PersistentSSHConnection? getConnection(String connectionId) {
    return _connections[connectionId];
  }

  List<PersistentSSHConnection> getConnections() {
    return _connections.values.toList();
  }

  List<PersistentSSHConnection> getActiveConnections() {
    return _connections.values
        .where((conn) => conn.status == ConnectionStatus.connected)
        .toList();
  }

  ConnectionHealth? getConnectionHealth(String connectionId) {
    return _healthStatus[connectionId];
  }

  List<ConnectionAttempt> getConnectionAttempts() {
    return _connectionAttempts.toList();
  }

  Future<void> updateConnectionOptions(String connectionId, Map<String, dynamic> options) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    connection.options.addAll(options);
    
    developer.log('🔌 Updated options for connection: $connectionId');
    
    _emitEvent(SSHEvent(
      type: SSHEventType.optionsUpdated,
      connectionId: connectionId,
      options: options,
    ));
    
    await _saveConnections();
  }

  Future<void> testConnection(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    try {
      developer.log('🔌 Testing connection: $connectionId');
      
      final startTime = DateTime.now();
      await _executeSSHCommand(connection, 'echo "test"', Duration(seconds: 10));
      final endTime = DateTime.now();
      final responseTime = endTime.difference(startTime).inMilliseconds;
      
      final health = _healthStatus[connectionId];
      if (health != null) {
        health.lastCheck = DateTime.now();
        health.responseTime = responseTime;
        health.isHealthy = responseTime < 5000;
      }
      
      developer.log('🔌 Connection test completed for $connectionId: ${responseTime}ms');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionTested,
        connectionId: connectionId,
        responseTime: responseTime,
        success: true,
      ));
      
    } catch (e) {
      developer.log('🔌 Connection test failed for $connectionId: $e');
      
      final health = _healthStatus[connectionId];
      if (health != null) {
        health.isHealthy = false;
      }
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionTested,
        connectionId: connectionId,
        success: false,
        error: e.toString(),
      ));
    }
  }

  String _generateConnectionId() {
    return 'ssh_conn_${DateTime.now().millisecondsSinceEpoch}_$_totalConnections';
  }

  String _generateAttemptId() {
    return 'attempt_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(SSHEvent event) {
    _sshController.add(event);
  }

  Stream<SSHEvent> get sshEventStream => _sshController.stream;

  SSHPersistenceStats getStats() {
    return SSHPersistenceStats(
      totalConnections: _totalConnections,
      activeConnections: _connections.values
          .where((conn) => conn.status == ConnectionStatus.connected)
          .length,
      reconnectedConnections: _reconnectedConnections,
      connectionAttempts: _connectionAttempts.length,
      healthyConnections: _healthStatus.values
          .where((health) => health.isHealthy)
          .length,
    );
  }

  void dispose() {
    _keepAliveTimer?.cancel();
    _healthCheckTimer?.cancel();
    _cleanupTimer?.cancel();
    
    // Disconnect all active connections
    for (final connectionId in _connections.keys.toList()) {
      if (_connections[connectionId]!.status == ConnectionStatus.connected) {
        disconnect(connectionId);
      }
    }
    
    _connections.clear();
    _healthStatus.clear();
    _connectionAttempts.clear();
    _sshController.close();
    
    developer.log('🔌 SSH Connection Persistence disposed');
  }
}

class PersistentSSHConnection {
  final String id;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String privateKeyPath;
  final Map<String, dynamic> options;
  final DateTime createdAt;
  DateTime lastUsed;
  ConnectionStatus status;
  DateTime? connectedAt;
  DateTime? disconnectedAt;
  DateTime? lastErrorTime;
  String? lastError;
  int reconnectAttempts;
  int maxReconnectAttempts;
  Duration reconnectDelay;
  bool keepAlive;
  bool autoReconnect;
  int? commandCount;

  PersistentSSHConnection({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    required this.privateKeyPath,
    required this.options,
    required this.createdAt,
    required this.lastUsed,
    required this.status,
    this.connectedAt,
    this.disconnectedAt,
    this.lastErrorTime,
    this.lastError,
    required this.reconnectAttempts,
    required this.maxReconnectAttempts,
    required this.reconnectDelay,
    required this.keepAlive,
    required this.autoReconnect,
    this.commandCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'host': host,
      'port': port,
      'username': username,
      'private_key_path': privateKeyPath,
      'options': options,
      'created_at': createdAt.toIso8601String(),
      'last_used': lastUsed.toIso8601String(),
      'status': status.name,
      'connected_at': connectedAt?.toIso8601String(),
      'disconnected_at': disconnectedAt?.toIso8601String(),
      'last_error_time': lastErrorTime?.toIso8601String(),
      'last_error': lastError,
      'reconnect_attempts': reconnectAttempts,
      'max_reconnect_attempts': maxReconnectAttempts,
      'reconnect_delay': reconnectDelay.inMilliseconds,
      'keep_alive': keepAlive,
      'auto_reconnect': autoReconnect,
      'command_count': commandCount,
    };
  }

  factory PersistentSSHConnection.fromJson(Map<String, dynamic> json) {
    return PersistentSSHConnection(
      id: json['id'],
      host: json['host'],
      port: json['port'],
      username: json['username'],
      password: json['password'],
      privateKeyPath: json['private_key_path'],
      options: Map<String, dynamic>.from(json['options'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      lastUsed: DateTime.parse(json['last_used']),
      status: ConnectionStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => ConnectionStatus.disconnected,
      ),
      connectedAt: json['connected_at'] != null ? DateTime.parse(json['connected_at']) : null,
      disconnectedAt: json['disconnected_at'] != null ? DateTime.parse(json['disconnected_at']) : null,
      lastErrorTime: json['last_error_time'] != null ? DateTime.parse(json['last_error_time']) : null,
      lastError: json['last_error'],
      reconnectAttempts: json['reconnect_attempts'] ?? 0,
      maxReconnectAttempts: json['max_reconnect_attempts'] ?? 5,
      reconnectDelay: Duration(milliseconds: json['reconnect_delay'] ?? 5000),
      keepAlive: json['keep_alive'] ?? true,
      autoReconnect: json['auto_reconnect'] ?? true,
      commandCount: json['command_count'],
    );
  }
}

class ConnectionHealth {
  final String connectionId;
  bool isHealthy;
  DateTime lastCheck;
  int responseTime;
  int packetsLost;
  Duration uptime;

  ConnectionHealth({
    required this.connectionId,
    required this.isHealthy,
    required this.lastCheck,
    required this.responseTime,
    required this.packetsLost,
    required this.uptime,
  });
}

class ConnectionAttempt {
  final String id;
  final String connectionId;
  final DateTime timestamp;
  final String host;
  final int port;
  final String username;

  ConnectionAttempt({
    required this.id,
    required this.connectionId,
    required this.timestamp,
    required this.host,
    required this.port,
    required this.username,
  });
}

class SSHCommandResult {
  final String command;
  final String output;
  final String error;
  final int exitCode;
  final Duration executionTime;

  SSHCommandResult({
    required this.command,
    required this.output,
    required this.error,
    required this.exitCode,
    required this.executionTime,
  });
}

enum ConnectionStatus {
  connecting,
  connected,
  disconnecting,
  disconnected,
  reconnecting,
  failed,
}

enum SSHEventType {
  connectionCreated,
  connectionEstablished,
  connectionFailed,
  connectionDisconnected,
  disconnectionFailed,
  reconnecting,
  reconnected,
  reconnectFailed,
  commandExecuted,
  commandFailed,
  connectionsCleaned,
  optionsUpdated,
  connectionTested,
}

class SSHEvent {
  final SSHEventType type;
  final String? connectionId;
  final String? host;
  final int? port;
  final String? username;
  final String? error;
  final String? command;
  final SSHCommandResult? result;
  final Duration? executionTime;
  final int? attempt;
  final int? attempts;
  final Map<String, dynamic>? options;
  final List<String>? connectionIds;
  final int? responseTime;
  final bool? success;

  SSHEvent({
    required this.type,
    this.connectionId,
    this.host,
    this.port,
    this.username,
    this.error,
    this.command,
    this.result,
    this.executionTime,
    this.attempt,
    this.attempts,
    this.options,
    this.connectionIds,
    this.responseTime,
    this.success,
  });
}

class SSHPersistenceStats {
  final int totalConnections;
  final int activeConnections;
  final int reconnectedConnections;
  final int connectionAttempts;
  final int healthyConnections;

  SSHPersistenceStats({
    required this.totalConnections,
    required this.activeConnections,
    required this.reconnectedConnections,
    required this.connectionAttempts,
    required this.healthyConnections,
  });
}
