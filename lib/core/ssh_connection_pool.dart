import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

class SSHConnectionPool {
  static const int _maxConnectionsPerHost = 5;
  static const int _connectionTimeout = 30000; // 30 seconds
  static const int _idleTimeout = 300000; // 5 minutes
  static const int _healthCheckInterval = 60000; // 1 minute
  
  final Map<String, List<SSHConnection>> _connectionsByHost = {};
  final Map<String, HostConnectionStats> _hostStats = {};
  final Map<String, SSHConnection> _activeConnections = {};
  
  Timer? _healthCheckTimer;
  int _totalConnectionsCreated = 0;
  int _totalConnectionsUsed = 0;
  
  final StreamController<SSHEvent> _sshEventController = 
      StreamController<SSHEvent>.broadcast();

  void initialize() {
    _startHealthCheckTimer();
    developer.log('🔗 SSH Connection Pool initialized');
  }

  void _startHealthCheckTimer() {
    _healthCheckTimer = Timer.periodic(
      Duration(milliseconds: _healthCheckInterval),
      (_) => _performHealthCheck(),
    );
  }

  Future<String> getConnection({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPath,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final hostKey = '$host:$port:$username';
    
    // Check if we have an available connection
    final availableConnection = _getAvailableConnection(hostKey);
    if (availableConnection != null) {
      _totalConnectionsUsed++;
      availableConnection.lastUsed = DateTime.now();
      availableConnection.inUse = true;
      _activeConnections[availableConnection.id] = availableConnection;
      
      developer.log('🔗 Reusing SSH connection to $host:$port');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionReused,
        connectionId: availableConnection.id,
        host: host,
        port: port,
      ));
      
      return availableConnection.id;
    }
    
    // Create new connection
    return await _createNewConnection(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: privateKeyPath,
      environment: environment,
      timeout: timeout,
    );
  }

  SSHConnection? _getAvailableConnection(String hostKey) {
    final connections = _connectionsByHost[hostKey];
    if (connections == null || connections.isEmpty) {
      return null;
    }
    
    // Find a healthy, unused connection
    for (final connection in connections) {
      if (!connection.inUse && 
          connection.status == SSHConnectionStatus.connected &&
          !_isConnectionIdle(connection)) {
        return connection;
      }
    }
    
    return null;
  }

  bool _isConnectionIdle(SSHConnection connection) {
    final idleTime = DateTime.now().difference(connection.lastUsed);
    return idleTime.inMilliseconds > _idleTimeout;
  }

  Future<String> _createNewConnection({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPath,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final connectionId = _generateConnectionId();
    final hostKey = '$host:$port:$username';
    
    // Check connection limit
    final connections = _connectionsByHost[hostKey] ?? [];
    if (connections.length >= _maxConnectionsPerHost) {
      throw Exception('Maximum connections reached for $hostKey');
    }
    
    final connection = SSHConnection(
      id: connectionId,
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: privateKeyPath,
      environment: environment ?? {},
      timeout: timeout ?? Duration(milliseconds: _connectionTimeout),
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );

    try {
      // Simulate SSH connection establishment
      await _establishSSHConnection(connection);
      
      connection.status = SSHConnectionStatus.connected;
      connection.connectedAt = DateTime.now();
      
      // Add to pool
      if (!_connectionsByHost.containsKey(hostKey)) {
        _connectionsByHost[hostKey] = [];
      }
      _connectionsByHost[hostKey]!.add(connection);
      
      _activeConnections[connectionId] = connection;
      _totalConnectionsCreated++;
      _totalConnectionsUsed++;
      
      // Update host stats
      _updateHostStats(hostKey, connection);
      
      developer.log('🔗 Created new SSH connection to $host:$port (ID: $connectionId)');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionCreated,
        connectionId: connectionId,
        host: host,
        port: port,
      ));
      
      return connectionId;
      
    } catch (e) {
      connection.status = SSHConnectionStatus.failed;
      connection.error = e.toString();
      
      developer.log('🔗 Failed to create SSH connection to $host:$port: $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.connectionFailed,
        connectionId: connectionId,
        host: host,
        port: port,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _establishSSHConnection(SSHConnection connection) async {
    // Simulate SSH connection establishment
    // In practice, this would use an SSH library
    
    await Future.delayed(Duration(milliseconds: 100)); // Simulate connection time
    
    // Validate connection parameters
    if (connection.host.isEmpty || connection.username.isEmpty) {
      throw Exception('Invalid connection parameters');
    }
    
    // Simulate authentication
    if (connection.password != null || connection.privateKeyPath != null) {
      await Future.delayed(Duration(milliseconds: 50)); // Simulate auth time
    } else {
      throw Exception('No authentication method provided');
    }
  }

  void releaseConnection(String connectionId) {
    final connection = _activeConnections[connectionId];
    if (connection == null) return;
    
    connection.inUse = false;
    connection.lastUsed = DateTime.now();
    _activeConnections.remove(connectionId);
    
    developer.log('🔗 Released SSH connection (ID: $connectionId)');
    
    _emitEvent(SSHEvent(
      type: SSHEventType.connectionReleased,
      connectionId: connectionId,
      host: connection.host,
      port: connection.port,
    ));
  }

  Future<void> closeConnection(String connectionId) async {
    final connection = _activeConnections.remove(connectionId);
    if (connection == null) {
      // Check if it's in the pool
      for (final hostConnections in _connectionsByHost.values) {
        final index = hostConnections.indexWhere((conn) => conn.id == connectionId);
        if (index != -1) {
          final poolConnection = hostConnections.removeAt(index);
          await _closeSSHConnection(poolConnection);
          break;
        }
      }
      return;
    }
    
    // Remove from pool
    final hostKey = '${connection.host}:${connection.port}:${connection.username}';
    final hostConnections = _connectionsByHost[hostKey];
    if (hostConnections != null) {
      hostConnections.removeWhere((conn) => conn.id == connectionId);
      if (hostConnections.isEmpty) {
        _connectionsByHost.remove(hostKey);
      }
    }
    
    await _closeSSHConnection(connection);
    
    developer.log('🔗 Closed SSH connection (ID: $connectionId)');
    
    _emitEvent(SSHEvent(
      type: SSHEventType.connectionClosed,
      connectionId: connectionId,
      host: connection.host,
      port: connection.port,
    ));
  }

  Future<void> _closeSSHConnection(SSHConnection connection) async {
    connection.status = SSHConnectionStatus.closed;
    connection.closedAt = DateTime.now();
    
    // Simulate connection cleanup
    await Future.delayed(Duration(milliseconds: 10));
  }

  Future<SSHCommandResult> executeCommand(String connectionId, String command, {
    Duration? timeout,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final connection = _activeConnections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }
    
    if (connection.status != SSHConnectionStatus.connected) {
      throw Exception('Connection not active: $connectionId');
    }
    
    try {
      // Simulate command execution
      final result = await _executeSSHCommand(connection, command, 
          timeout: timeout, 
          workingDirectory: workingDirectory,
          environment: environment);
      
      connection.commandsExecuted++;
      connection.lastCommandAt = DateTime.now();
      
      developer.log('🔗 Executed command on $connectionId: $command');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.commandExecuted,
        connectionId: connectionId,
        host: connection.host,
        port: connection.port,
        command: command,
        exitCode: result.exitCode,
      ));
      
      return result;
      
    } catch (e) {
      connection.commandsFailed++;
      
      developer.log('🔗 Command execution failed on $connectionId: $e');
      
      _emitEvent(SSHEvent(
        type: SSHEventType.commandFailed,
        connectionId: connectionId,
        host: connection.host,
        port: connection.port,
        command: command,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<SSHCommandResult> _executeSSHCommand(
    SSHConnection connection,
    String command, {
    Duration? timeout,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    // Simulate command execution
    final executionTime = _estimateCommandExecutionTime(command);
    await Future.delayed(Duration(milliseconds: executionTime));
    
    // Simulate different outcomes based on command
    if (command.contains('exit') || command.contains('logout')) {
      return SSHCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
        executionTime: executionTime,
      );
    } else if (command.contains('ls') || command.contains('pwd')) {
      return SSHCommandResult(
        exitCode: 0,
        stdout: 'file1.txt\nfile2.txt\ndirectory1/',
        stderr: '',
        executionTime: executionTime,
      );
    } else if (command.contains('cat')) {
      return SSHCommandResult(
        exitCode: 0,
        stdout: 'File content here',
        stderr: '',
        executionTime: executionTime,
      );
    } else {
      return SSHCommandResult(
        exitCode: 0,
        stdout: 'Command executed successfully',
        stderr: '',
        executionTime: executionTime,
      );
    }
  }

  int _estimateCommandExecutionTime(String command) {
    // Estimate execution time based on command type
    if (command.contains('ls') || command.contains('pwd')) return 50;
    if (command.contains('cat')) return 100;
    if (command.contains('find') || command.contains('grep')) return 500;
    if (command.contains('git')) return 2000;
    if (command.contains('npm') || command.contains('yarn')) return 5000;
    return 200; // Default
  }

  void _performHealthCheck() {
    final now = DateTime.now();
    final connectionsToClose = <String>[];
    
    for (final hostConnections in _connectionsByHost.values) {
      for (final connection in hostConnections) {
        // Check for idle connections
        if (!connection.inUse && _isConnectionIdle(connection)) {
          connectionsToClose.add(connection.id);
          continue;
        }
        
        // Check for failed connections
        if (connection.status == SSHConnectionStatus.failed) {
          connectionsToClose.add(connection.id);
          continue;
        }
        
        // Check for old connections
        if (connection.connectedAt != null && 
            now.difference(connection.connectedAt!).inMinutes > 30) {
          connectionsToClose.add(connection.id);
        }
      }
    }
    
    // Close unhealthy connections
    for (final connectionId in connectionsToClose) {
      closeConnection(connectionId);
    }
  }

  void _updateHostStats(String hostKey, SSHConnection connection) {
    final stats = _hostStats.putIfAbsent(
      hostKey,
      () => HostConnectionStats(hostKey: hostKey),
    );
    
    stats.recordConnection(connection);
  }

  Future<List<String>> getActiveConnections() async {
    final activeConnections = <String>[];
    
    for (final connection in _activeConnections.values) {
      if (connection.status == SSHConnectionStatus.connected) {
        activeConnections.add('${connection.host}:${connection.port} (${connection.username})');
      }
    }
    
    return activeConnections;
  }

  Map<String, dynamic> getConnectionStats() {
    final stats = <String, dynamic>{};
    
    for (final entry in _hostStats.entries) {
      final hostKey = entry.key;
      final hostStats = entry.value;
      
      stats[hostKey] = {
        'totalConnections': hostStats.totalConnections,
        'activeConnections': hostStats.activeConnections,
        'failedConnections': hostStats.failedConnections,
        'averageConnectionTime': hostStats.averageConnectionTime,
        'totalCommandsExecuted': hostStats.totalCommandsExecuted,
      };
    }
    
    return stats;
  }

  String _generateConnectionId() {
    return 'ssh_${DateTime.now().millisecondsSinceEpoch}_$_totalConnectionsCreated';
  }

  void _emitEvent(SSHEvent event) {
    _sshEventController.add(event);
  }

  Stream<SSHEvent> get sshEventStream => _sshEventController.stream;

  SSHConnectionPoolStats getStats() {
    return SSHConnectionPoolStats(
      totalConnectionsCreated: _totalConnectionsCreated,
      totalConnectionsUsed: _totalConnectionsUsed,
      activeConnections: _activeConnections.length,
      pooledConnections: _connectionsByHost.values
          .map((connections) => connections.length)
          .reduce((a, b) => a + b),
      hostStats: _hostStats.values.toList(),
    );
  }

  void dispose() {
    _healthCheckTimer?.cancel();
    
    // Close all connections
    for (final connectionId in _activeConnections.keys.toList()) {
      closeConnection(connectionId);
    }
    
    // Close pooled connections
    for (final hostConnections in _connectionsByHost.values) {
      for (final connection in hostConnections) {
        _closeSSHConnection(connection);
      }
    }
    
    _activeConnections.clear();
    _connectionsByHost.clear();
    _hostStats.clear();
    _sshEventController.close();
    
    developer.log('🔗 SSH Connection Pool disposed');
  }
}

class SSHConnection {
  final String id;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final Map<String, String> environment;
  final Duration timeout;
  final DateTime createdAt;
  
  SSHConnectionStatus status = SSHConnectionStatus.created;
  DateTime? connectedAt;
  DateTime? closedAt;
  DateTime lastUsed;
  bool inUse = false;
  int commandsExecuted = 0;
  int commandsFailed = 0;
  DateTime? lastCommandAt;
  String? error;

  SSHConnection({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
    required this.environment,
    required this.timeout,
    required this.createdAt,
  }) : lastUsed = DateTime.now();

  int? get connectionTime {
    if (connectedAt == null) return null;
    return connectedAt!.difference(createdAt).inMilliseconds;
  }

  int? get uptime {
    if (connectedAt == null) return null;
    final endTime = closedAt ?? DateTime.now();
    return endTime.difference(connectedAt!).inMilliseconds;
  }
}

enum SSHConnectionStatus {
  created,
  connecting,
  connected,
  failed,
  closed,
}

class SSHCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int executionTime;

  SSHCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.executionTime,
  });
}

class HostConnectionStats {
  final String hostKey;
  int totalConnections = 0;
  int activeConnections = 0;
  int failedConnections = 0;
  int totalConnectionTime = 0;
  int totalCommandsExecuted = 0;
  DateTime lastConnection = DateTime.now();

  HostConnectionStats({required this.hostKey});

  void recordConnection(SSHConnection connection) {
    totalConnections++;
    lastConnection = DateTime.now();
    
    if (connection.status == SSHConnectionStatus.connected) {
      activeConnections++;
    } else if (connection.status == SSHConnectionStatus.failed) {
      failedConnections++;
    }
    
    if (connection.connectionTime != null) {
      totalConnectionTime += connection.connectionTime!;
    }
    
    totalCommandsExecuted += connection.commandsExecuted;
  }

  double get averageConnectionTime {
    return totalConnections > 0 ? totalConnectionTime / totalConnections : 0.0;
  }

  double get successRate {
    return totalConnections > 0 ? (totalConnections - failedConnections) / totalConnections : 0.0;
  }
}

enum SSHEventType {
  connectionCreated,
  connectionReused,
  connectionReleased,
  connectionClosed,
  connectionFailed,
  commandExecuted,
  commandFailed,
}

class SSHEvent {
  final SSHEventType type;
  final String? connectionId;
  final String host;
  final int port;
  final String? command;
  final int? exitCode;
  final String? error;

  SSHEvent({
    required this.type,
    this.connectionId,
    required this.host,
    required this.port,
    this.command,
    this.exitCode,
    this.error,
  });
}

class SSHConnectionPoolStats {
  final int totalConnectionsCreated;
  final int totalConnectionsUsed;
  final int activeConnections;
  final int pooledConnections;
  final List<HostConnectionStats> hostStats;

  SSHConnectionPoolStats({
    required this.totalConnectionsCreated,
    required this.totalConnectionsUsed,
    required this.activeConnections,
    required this.pooledConnections,
    required this.hostStats,
  });
}
