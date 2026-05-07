import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class MultihopSSH {
  static const int _maxHops = 10;
  static const int _connectionTimeout = 30000; // 30 seconds
  static const int _commandTimeout = 60000; // 60 seconds
  static const String _connectionDataFile = '/home/house/.termisol_multihop_connections.json';
  
  final Map<String, MultihopConnection> _connections = {};
  final Map<String, List<SSHCommand>> _commandQueues = {};
  final Map<String, ConnectionHop> _hops = {};
  
  int _totalConnections = 0;
  int _totalCommands = 0;
  
  final StreamController<MultihopEvent> _multihopController = 
      StreamController<MultihopEvent>.broadcast();

  void initialize() {
    _loadConnections();
    developer.log('🔗 Multihop SSH initialized');
  }

  void _loadConnections() {
    try {
      final file = File(_connectionDataFile);
      if (!file.existsSync()) {
        developer.log('🔗 No existing multihop connections file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['connections']) {
        final connection = MultihopConnection.fromJson(entry);
        _connections[connection.id] = connection;
        _totalConnections++;
        
        // Initialize hops
        _initializeHops(connection);
      }
      
      developer.log('🔗 Loaded ${_connections.length} multihop connections');
      
    } catch (e) {
      developer.log('🔗 Failed to load connections: $e');
    }
  }

  void _initializeHops(MultihopConnection connection) {
    for (int i = 0; i < connection.hops.length; i++) {
      final hop = connection.hops[i];
      
      final connectionHop = ConnectionHop(
        connectionId: connection.id,
        hopIndex: i,
        host: hop.host,
        port: hop.port,
        username: hop.username,
        privateKeyPath: hop.privateKeyPath ?? '/home/house/.ssh/hermes_key',
        status: HopStatus.disconnected,
        process: null,
        connectedAt: null,
        lastActivity: null,
      );
      
      _hops['${connection.id}_$i'] = connectionHop;
    }
  }

  Future<String> createMultihopConnection({
    required String name,
    required List<SSHHop> hops,
    Map<String, dynamic>? options,
  }) async {
    if (hops.length > _maxHops) {
      throw Exception('Maximum hops exceeded: $_maxHops');
    }
    
    if (hops.isEmpty) {
      throw Exception('At least one hop is required');
    }
    
    final connectionId = _generateConnectionId();
    
    final connection = MultihopConnection(
      id: connectionId,
      name: name,
      hops: hops,
      options: options ?? {},
      createdAt: DateTime.now(),
      status: ConnectionStatus.creating,
      currentHop: -1,
      commandQueue: [],
      totalCommands: 0,
    );
    
    _connections[connectionId] = connection;
    _totalConnections++;
    
    // Initialize hops
    _initializeHops(connection);
    
    try {
      await _establishMultihopConnection(connection);
      
      developer.log('🔗 Created multihop connection: $name (${hops.length} hops)');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.created,
        connectionId: connectionId,
        name: name,
        hopCount: hops.length,
      ));
      
      // Save connections
      await _saveConnections();
      
      return connectionId;
      
    } catch (e) {
      connection.status = ConnectionStatus.failed;
      connection.lastError = e.toString();
      connection.lastErrorTime = DateTime.now();
      
      developer.log('🔗 Failed to create multihop connection: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.failed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _establishMultihopConnection(MultihopConnection connection) async {
    connection.status = ConnectionStatus.connecting;
    
    try {
      // Establish connection through hops sequentially
      for (int i = 0; i < connection.hops.length; i++) {
        final hop = connection.hops[i];
        final connectionHop = _hops['${connection.id}_$i']!;
        
        developer.log('🔗 Establishing hop $i: ${hop.username}@${hop.host}:${hop.port}');
        
        connectionHop.status = HopStatus.connecting;
        connection.currentHop = i;
        
        _emitEvent(MultihopEvent(
          type: MultihopEventType.hopConnecting,
          connectionId: connection.id,
          hopIndex: i,
          host: hop.host,
          port: hop.port,
        ));
        
        // Create SSH command to establish hop
        final sshCommand = _buildHopCommand(connection, i);
        
        // Execute SSH command
        final process = await Process.start('bash', ['-c', sshCommand]);
        
        connectionHop.process = process;
        connectionHop.connectedAt = DateTime.now();
        connectionHop.lastActivity = DateTime.now();
        
        // Wait for connection to establish
        await Future.delayed(Duration(seconds: 3));
        
        // Check if connection is still running
        final exitCode = await process.exitCode;
        if (exitCode != null) {
          throw Exception('Hop $i connection failed with exit code $exitCode');
        }
        
        connectionHop.status = HopStatus.connected;
        
        developer.log('🔗 Hop $i connected successfully');
        
        _emitEvent(MultihopEvent(
          type: MultihopEventType.hopConnected,
          connectionId: connection.id,
          hopIndex: i,
        ));
      }
      
      connection.status = ConnectionStatus.connected;
      connection.connectedAt = DateTime.now();
      
      developer.log('🔗 Multihop connection established: ${connection.name}');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.connected,
        connectionId: connection.id,
      ));
      
    } catch (e) {
      connection.status = ConnectionStatus.failed;
      connection.lastError = e.toString();
      connection.lastErrorTime = DateTime.now();
      
      // Clean up any established connections
      await _cleanupConnection(connection);
      
      developer.log('🔗 Failed to establish multihop connection: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.failed,
        connectionId: connection.id,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  String _buildHopCommand(MultihopConnection connection, int hopIndex) {
    final hop = connection.hops[hopIndex];
    final hopKey = '${connection.id}_$hopIndex';
    
    String command = 'ssh ';
    
    // Add SSH options
    command += '-o StrictHostKeyChecking=no ';
    command += '-o UserKnownHostsFile=/dev/null ';
    command += '-o ExitOnForwardFailure=yes ';
    command += '-o ServerAliveInterval=30 ';
    command += '-o ServerAliveCountMax=3 ';
    
    // Add private key
    command += '-i ${hop.privateKeyPath ?? '/home/house/.ssh/hermes_key'} ';
    
    // Add authentication
    command += '${hop.username}@${hop.host} -p ${hop.port} ';
    
    // If not the last hop, add command to establish next hop
    if (hopIndex < connection.hops.length - 1) {
      final nextHop = connection.hops[hopIndex + 1];
      command += '"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${nextHop.privateKeyPath ?? '/home/house/.ssh/hermes_key'} ${nextHop.username}@${nextHop.host} -p ${nextHop.port}"';
    } else {
      // Last hop - just establish shell
      command += '"echo \'Multihop connection established\'"';
    }
    
    return command;
  }

  Future<MultihopCommandResult> executeCommand({
    required String connectionId,
    required String command,
    Duration? timeout,
    Map<String, dynamic>? environment,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    if (connection.status != ConnectionStatus.connected) {
      throw Exception('Multihop connection not active: $connectionId');
    }
    
    final commandId = _generateCommandId();
    final commandEntry = SSHCommand(
      id: commandId,
      command: command,
      environment: environment ?? {},
      createdAt: DateTime.now(),
      status: CommandStatus.queued,
      result: null,
    );
    
    connection.commandQueue.add(commandEntry);
    connection.totalCommands++;
    _totalCommands++;
    
    try {
      developer.log('🔗 Executing command on multihop connection $connectionId: $command');
      
      // Get the last hop process
      final lastHopIndex = connection.hops.length - 1;
      final lastHop = _hops['${connectionId}_$lastHopIndex'];
      
      if (lastHop?.process == null) {
        throw Exception('Last hop process not available');
      }
      
      commandEntry.status = CommandStatus.running;
      commandEntry.startedAt = DateTime.now();
      
      // Execute command through the last hop
      final process = lastHop!.process!;
      final stdin = process.stdin;
      
      // Write command to stdin
      stdin.write(command + '\n');
      
      // Wait for command completion
      final timeoutDuration = timeout ?? Duration(seconds: 30);
      final startTime = DateTime.now();
      
      String output = '';
      bool commandCompleted = false;
      
      // Read output
      final stdoutStream = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      
      await for (final line in stdoutStream) {
        output += line + '\n';
        
        // Check for command completion (simple heuristic)
        if (line.contains('Multihop connection established') || 
            line.trim().endsWith('$ ') ||
            line.contains(command.split(' ').first)) {
          commandCompleted = true;
        }
        
        // Check timeout
        if (DateTime.now().difference(startTime) > timeoutDuration) {
          break;
        }
      }
      
      final endTime = DateTime.now();
      final executionTime = endTime.difference(startTime);
      
      if (commandCompleted) {
        commandEntry.status = CommandStatus.completed;
        commandEntry.result = MultihopCommandResult(
          commandId: commandId,
          command: command,
          output: output,
          error: '',
          exitCode: 0,
          executionTime: executionTime,
          hopIndex: lastHopIndex,
        );
      } else {
        commandEntry.status = CommandStatus.timeout;
        commandEntry.result = MultihopCommandResult(
          commandId: commandId,
          command: command,
          output: output,
          error: 'Command timeout',
          exitCode: -1,
          executionTime: executionTime,
          hopIndex: lastHopIndex,
        );
      }
      
      commandEntry.completedAt = endTime;
      
      developer.log('🔗 Command executed on multihop connection $connectionId in ${executionTime.inMilliseconds}ms');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.commandExecuted,
        connectionId: connectionId,
        commandId: commandId,
        command: command,
        result: commandEntry.result,
      ));
      
      return commandEntry.result!;
      
    } catch (e) {
      commandEntry.status = CommandStatus.failed;
      commandEntry.result = MultihopCommandResult(
        commandId: commandId,
        command: command,
        output: '',
        error: e.toString(),
        exitCode: -1,
        executionTime: Duration.zero,
        hopIndex: connection.hops.length - 1,
      );
      
      commandEntry.completedAt = DateTime.now();
      
      developer.log('🔗 Command failed on multihop connection $connectionId: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.commandFailed,
        connectionId: connectionId,
        commandId: commandId,
        command: command,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> addHop({
    required String connectionId,
    required SSHHop hop,
    int? insertIndex,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    if (connection.hops.length >= _maxHops) {
      throw Exception('Maximum hops exceeded: $_maxHops');
    }
    
    try {
      // Disconnect current connection if active
      if (connection.status == ConnectionStatus.connected) {
        await disconnect(connectionId);
      }
      
      // Insert hop at specified position
      final insertAt = insertIndex ?? connection.hops.length;
      connection.hops.insert(insertAt, hop);
      
      // Reinitialize hops
      _initializeHops(connection);
      
      developer.log('🔗 Added hop to multihop connection $connectionId at position $insertAt');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.hopAdded,
        connectionId: connectionId,
        hopIndex: insertAt,
        host: hop.host,
        port: hop.port,
      ));
      
      // Re-establish connection
      if (connection.status != ConnectionStatus.disconnected) {
        await _establishMultihopConnection(connection);
      }
      
      // Save connections
      await _saveConnections();
      
    } catch (e) {
      developer.log('🔗 Failed to add hop: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.hopAddFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> removeHop({
    required String connectionId,
    required int hopIndex,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    if (hopIndex < 0 || hopIndex >= connection.hops.length) {
      throw Exception('Invalid hop index: $hopIndex');
    }
    
    try {
      // Disconnect current connection if active
      if (connection.status == ConnectionStatus.connected) {
        await disconnect(connectionId);
      }
      
      // Remove hop
      final removedHop = connection.hops.removeAt(hopIndex);
      
      // Clean up hop data
      _hops.remove('${connectionId}_$hopIndex');
      
      // Reindex remaining hops
      for (int i = hopIndex; i < connection.hops.length; i++) {
        final oldKey = '${connectionId}_${i + 1}';
        final newKey = '${connectionId}_$i';
        final hopData = _hops[oldKey];
        
        if (hopData != null) {
          _hops[newKey] = hopData!;
          _hops.remove(oldKey);
        }
      }
      
      developer.log('🔗 Removed hop from multihop connection $connectionId at index $hopIndex');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.hopRemoved,
        connectionId: connectionId,
        hopIndex: hopIndex,
        host: removedHop.host,
        port: removedHop.port,
      ));
      
      // Re-establish connection if hops remain
      if (connection.hops.isNotEmpty) {
        await _establishMultihopConnection(connection);
      }
      
      // Save connections
      await _saveConnections();
      
    } catch (e) {
      developer.log('🔗 Failed to remove hop: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.hopRemoveFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> disconnect(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    try {
      // Clean up all hop processes
      for (int i = 0; i < connection.hops.length; i++) {
        final hopKey = '${connectionId}_$i';
        final hop = _hops[hopKey];
        
        if (hop?.process != null) {
          await _killHopProcess(hop!);
        }
      }
      
      connection.status = ConnectionStatus.disconnected;
      connection.disconnectedAt = DateTime.now();
      
      developer.log('🔗 Disconnected multihop connection: $connectionId');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.disconnected,
        connectionId: connectionId,
      ));
      
      // Save connections
      await _saveConnections();
      
    } catch (e) {
      developer.log('🔗 Failed to disconnect: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.disconnectFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _killHopProcess(ConnectionHop hop) async {
    try {
      if (hop.process != null) {
        // Try graceful shutdown first
        hop.process!.kill(ProcessSignal.sigterm);
        
        // Wait for graceful shutdown
        await Future.delayed(Duration(seconds: 3));
        
        // Check if process is still running
        final exitCode = await hop.process!.exitCode;
        if (exitCode == null) {
          // Force kill if still running
          hop.process!.kill(ProcessSignal.sigkill);
        }
        
        hop.status = HopStatus.disconnected;
        hop.process = null;
        
        developer.log('🔗 Killed hop process');
      }
    } catch (e) {
      developer.log('🔗 Failed to kill hop process: $e');
    }
  }

  Future<void> _cleanupConnection(MultihopConnection connection) async {
    for (int i = 0; i < connection.hops.length; i++) {
      final hopKey = '${connection.id}_$i';
      final hop = _hops[hopKey];
      
      if (hop?.process != null) {
        await _killHopProcess(hop!);
      }
    }
  }

  Future<void> testConnection({
    required String connectionId,
    Duration? timeout,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    try {
      developer.log('🔗 Testing multihop connection: $connectionId');
      
      final startTime = DateTime.now();
      final testTimeout = timeout ?? Duration(seconds: 10);
      
      // Execute a simple test command through the last hop
      final result = await executeCommand(
        connectionId: connectionId,
        command: 'echo "multihop_test_${DateTime.now().millisecondsSinceEpoch}"',
        timeout: testTimeout,
      );
      
      final endTime = DateTime.now();
      final testDuration = endTime.difference(startTime);
      
      final success = result.exitCode == 0;
      
      developer.log('🔗 Multihop connection test completed: $connectionId (${success ? 'success' : 'failed'})');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.connectionTested,
        connectionId: connectionId,
        success: success,
        testDuration: testDuration,
        result: result,
      ));
      
      return;
      
    } catch (e) {
      developer.log('🔗 Multihop connection test failed: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.connectionTestFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
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
      
      developer.log('🔗 Saved ${connectionsData.length} multihop connections');
      
    } catch (e) {
      developer.log('🔗 Failed to save connections: $e');
    }
  }

  MultihopConnection? getConnection(String connectionId) {
    return _connections[connectionId];
  }

  List<MultihopConnection> getConnections() {
    return _connections.values.toList();
  }

  List<MultihopConnection> getActiveConnections() {
    return _connections.values
        .where((conn) => conn.status == ConnectionStatus.connected)
        .toList();
  }

  List<SSHCommand> getCommandHistory({
    String? connectionId,
    int? limit,
  }) {
    List<SSHCommand> commands = [];
    
    if (connectionId != null) {
      final connection = _connections[connectionId];
      if (connection != null) {
        commands = connection.commandQueue;
      }
    } else {
      // Get all commands from all connections
      for (final connection in _connections.values) {
        commands.addAll(connection.commandQueue);
      }
    }
    
    // Sort by creation time (newest first)
    commands.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Apply limit
    if (limit != null && limit! > 0) {
      commands = commands.take(limit!).toList();
    }
    
    return commands;
  }

  ConnectionHop? getHopStatus(String connectionId, int hopIndex) {
    return _hops['${connectionId}_$hopIndex'];
  }

  Future<String> optimizeRoute({
    required String connectionId,
    List<String>? targetHosts,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Multihop connection not found: $connectionId');
    }
    
    try {
      developer.log('🔗 Optimizing route for multihop connection: $connectionId');
      
      // Test connection latency through each hop
      final hopLatencies = <int, double>{};
      
      for (int i = 0; i < connection.hops.length; i++) {
        final startTime = DateTime.now();
        
        // Test ping to hop
        final hop = connection.hops[i];
        final process = await Process.start('ping', ['-c', '1', hop.host]);
        
        final exitCode = await process.exitCode;
        final endTime = DateTime.now();
        
        if (exitCode == 0) {
          hopLatencies[i] = endTime.difference(startTime).inMilliseconds.toDouble();
        } else {
          hopLatencies[i] = double.infinity;
        }
      }
      
      // Find optimal path based on latencies
      int optimalHop = 0;
      double minLatency = hopLatencies[0] ?? double.infinity;
      
      for (int i = 1; i < connection.hops.length; i++) {
        if (hopLatencies[i]! < minLatency) {
          minLatency = hopLatencies[i]!;
          optimalHop = i;
        }
      }
      
      // Reorder hops to put optimal hop first
      final optimalHopData = connection.hops[optimalHop];
      connection.hops.removeAt(optimalHop);
      connection.hops.insert(0, optimalHopData);
      
      // Reinitialize hops
      _initializeHops(connection);
      
      developer.log('🔗 Route optimized: optimal hop is $optimalHop (${minLatency.toStringAsFixed(2)}ms)');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.routeOptimized,
        connectionId: connectionId,
        optimalHop: optimalHop,
        latency: minLatency,
      ));
      
      // Re-establish connection with optimized route
      await _establishMultihopConnection(connection);
      
      return 'Route optimized: optimal hop is $optimalHop';
      
    } catch (e) {
      developer.log('🔗 Failed to optimize route: $e');
      
      _emitEvent(MultihopEvent(
        type: MultihopEventType.routeOptimizationFailed,
        connectionId: connectionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  String _generateConnectionId() {
    return 'multihop_${DateTime.now().millisecondsSinceEpoch}_$_totalConnections';
  }

  String _generateCommandId() {
    return 'cmd_${DateTime.now().millisecondsSinceEpoch}_$_totalCommands';
  }

  void _emitEvent(MultihopEvent event) {
    _multihopController.add(event);
  }

  Stream<MultihopEvent> get multihopEventStream => _multihopController.stream;

  MultihopStats getStats() {
    return MultihopStats(
      totalConnections: _totalConnections,
      activeConnections: _connections.values
          .where((conn) => conn.status == ConnectionStatus.connected)
          .length,
      totalHops: _connections.values
          .fold(0, (sum, conn) => sum + conn.hops.length),
      totalCommands: _totalCommands,
      averageHopsPerConnection: _connections.isNotEmpty
          ? _connections.values.fold(0, (sum, conn) => sum + conn.hops.length) / _connections.length
          : 0.0,
    );
  }

  void dispose() {
    // Disconnect all active connections
    for (final connectionId in _connections.keys.toList()) {
      final connection = _connections[connectionId];
      if (connection != null && connection!.status == ConnectionStatus.connected) {
        disconnect(connectionId);
      }
    }
    
    _connections.clear();
    _commandQueues.clear();
    _hops.clear();
    _multihopController.close();
    
    developer.log('🔗 Multihop SSH disposed');
  }
}

class MultihopConnection {
  final String id;
  final String name;
  final List<SSHHop> hops;
  final Map<String, dynamic> options;
  final DateTime createdAt;
  ConnectionStatus status;
  int currentHop;
  final List<SSHCommand> commandQueue;
  final int totalCommands;
  DateTime? connectedAt;
  DateTime? disconnectedAt;
  String? lastError;
  DateTime? lastErrorTime;

  MultihopConnection({
    required this.id,
    required this.name,
    required this.hops,
    required this.options,
    required this.createdAt,
    required this.status,
    required this.currentHop,
    required this.commandQueue,
    required this.totalCommands,
    this.connectedAt,
    this.disconnectedAt,
    this.lastError,
    this.lastErrorTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hops': hops.map((hop) => hop.toJson()).toList(),
      'options': options,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'current_hop': currentHop,
      'total_commands': totalCommands,
      'connected_at': connectedAt?.toIso8601String(),
      'disconnected_at': disconnectedAt?.toIso8601String(),
      'last_error': lastError,
      'last_error_time': lastErrorTime?.toIso8601String(),
    };
  }

  factory MultihopConnection.fromJson(Map<String, dynamic> json) {
    return MultihopConnection(
      id: json['id'],
      name: json['name'],
      hops: (json['hops'] as List).map((hop) => SSHHop.fromJson(hop)).toList(),
      options: Map<String, dynamic>.from(json['options'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      status: ConnectionStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => ConnectionStatus.disconnected,
      ),
      currentHop: json['current_hop'] ?? -1,
      commandQueue: [],
      totalCommands: json['total_commands'] ?? 0,
      connectedAt: json['connected_at'] != null ? DateTime.parse(json['connected_at']) : null,
      disconnectedAt: json['disconnected_at'] != null ? DateTime.parse(json['disconnected_at']) : null,
      lastError: json['last_error'],
      lastErrorTime: json['last_error_time'] != null ? DateTime.parse(json['last_error_time']) : null,
    );
  }
}

class SSHHop {
  final String host;
  final int port;
  final String username;
  final String? privateKeyPath;

  SSHHop({
    required this.host,
    required this.port,
    required this.username,
    this.privateKeyPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'private_key_path': privateKeyPath,
    };
  }

  factory SSHHop.fromJson(Map<String, dynamic> json) {
    return SSHHop(
      host: json['host'],
      port: json['port'],
      username: json['username'],
      privateKeyPath: json['private_key_path'],
    );
  }
}

class ConnectionHop {
  final String connectionId;
  final int hopIndex;
  final String host;
  final int port;
  final String username;
  final String privateKeyPath;
  final HopStatus status;
  final Process? process;
  final DateTime? connectedAt;
  final DateTime? lastActivity;

  ConnectionHop({
    required this.connectionId,
    required this.hopIndex,
    required this.host,
    required this.port,
    required this.username,
    required this.privateKeyPath,
    required this.status,
    this.process,
    this.connectedAt,
    this.lastActivity,
  });
}

class SSHCommand {
  final String id;
  final String command;
  final Map<String, dynamic> environment;
  final DateTime createdAt;
  CommandStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final MultihopCommandResult? result;

  SSHCommand({
    required this.id,
    required this.command,
    required this.environment,
    required this.createdAt,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.result,
  });
}

class MultihopCommandResult {
  final String commandId;
  final String command;
  final String output;
  final String error;
  final int exitCode;
  final Duration executionTime;
  final int hopIndex;

  MultihopCommandResult({
    required this.commandId,
    required this.command,
    required this.output,
    required this.error,
    required this.exitCode,
    required this.executionTime,
    required this.hopIndex,
  });
}

enum ConnectionStatus {
  creating,
  connecting,
  connected,
  disconnecting,
  disconnected,
  failed,
}

enum HopStatus {
  connecting,
  connected,
  disconnecting,
  disconnected,
  failed,
}

enum CommandStatus {
  queued,
  running,
  completed,
  failed,
  timeout,
}

enum MultihopEventType {
  created,
  connected,
  disconnected,
  failed,
  hopConnecting,
  hopConnected,
  hopAdded,
  hopRemoved,
  hopAddFailed,
  hopRemoveFailed,
  commandExecuted,
  commandFailed,
  connectionTested,
  connectionTestFailed,
  routeOptimized,
  routeOptimizationFailed,
  disconnectFailed,
}

class MultihopEvent {
  final MultihopEventType type;
  final String? connectionId;
  final String? name;
  final int? hopIndex;
  final String? host;
  final int? port;
  final String? commandId;
  final String? command;
  final MultihopCommandResult? result;
  final String? error;
  final bool? success;
  final Duration? testDuration;
  final int? optimalHop;
  final double? latency;
  final List<String>? connectionIds;

  MultihopEvent({
    required this.type,
    this.connectionId,
    this.name,
    this.hopIndex,
    this.host,
    this.port,
    this.commandId,
    this.command,
    this.result,
    this.error,
    this.success,
    this.testDuration,
    this.optimalHop,
    this.latency,
    this.connectionIds,
  });
}

class MultihopStats {
  final int totalConnections;
  final int activeConnections;
  final int totalHops;
  final int totalCommands;
  final double averageHopsPerConnection;

  MultihopStats({
    required this.totalConnections,
    required this.activeConnections,
    required this.totalHops,
    required this.totalCommands,
    required this.averageHopsPerConnection,
  });
}
