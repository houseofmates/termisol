import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class TunnelManagement {
  static const int _maxTunnels = 50;
  static const int _tunnelTimeout = 30000; // 30 seconds
  static const String _tunnelDataFile = '/home/house/.termisol_tunnels.json';
  
  final Map<String, SSHTunnel> _tunnels = {};
  final Map<String, TunnelProcess> _tunnelProcesses = {};
  final Map<String, TunnelStatus> _tunnelStatus = {};
  final List<TunnelPort> _usedPorts = [];
  
  Timer? _statusCheckTimer;
  Timer? _cleanupTimer;
  int _totalTunnels = 0;
  int _activeTunnels = 0;
  
  final StreamController<TunnelEvent> _tunnelController = 
      StreamController<TunnelEvent>.broadcast();

  void initialize() {
    _loadTunnels();
    _startTimers();
    developer.log('🌐 Tunnel Management initialized');
  }

  void _loadTunnels() {
    try {
      final file = File(_tunnelDataFile);
      if (!file.existsSync()) {
        developer.log('🌐 No existing tunnels file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['tunnels']) {
        final tunnel = SSHTunnel.fromJson(entry);
        _tunnels[tunnel.id] = tunnel;
        _totalTunnels++;
        
        // Check if tunnel process is still running
        _checkTunnelProcess(tunnel);
      }
      
      developer.log('🌐 Loaded ${_tunnels.length} tunnels');
      
    } catch (e) {
      developer.log('🌐 Failed to load tunnels: $e');
    }
  }

  void _startTimers() {
    _statusCheckTimer = Timer.periodic(
      Duration(seconds: 10),
      (_) => _checkTunnelStatuses(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _cleanupDeadTunnels(),
    );
  }

  Future<String> createTunnel({
    required String name,
    required String host,
    required int remotePort,
    required int localPort,
    String? username,
    String? privateKeyPath,
    String? remoteHost,
    TunnelType type = TunnelType.local,
    Map<String, dynamic>? options,
  }) async {
    if (_tunnels.length >= _maxTunnels) {
      throw Exception('Maximum tunnels reached');
    }
    
    // Check if local port is already in use
    if (_isPortInUse(localPort)) {
      throw Exception('Local port $localPort is already in use');
    }
    
    final tunnelId = _generateTunnelId();
    
    final tunnel = SSHTunnel(
      id: tunnelId,
      name: name,
      host: host,
      remotePort: remotePort,
      localPort: localPort,
      username: username ?? 'house',
      privateKeyPath: privateKeyPath ?? '/home/house/.ssh/hermes_key',
      remoteHost: remoteHost ?? 'localhost',
      type: type,
      options: options ?? {},
      createdAt: DateTime.now(),
      status: TunnelStatus.creating,
      autoReconnect: true,
      reconnectAttempts: 0,
      maxReconnectAttempts: 5,
      reconnectDelay: Duration(seconds: 5),
    );
    
    _tunnels[tunnelId] = tunnel;
    _totalTunnels++;
    
    try {
      await _startTunnel(tunnel);
      
      developer.log('🌐 Created tunnel: $name ($localPort -> $host:$remotePort)');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.created,
        tunnelId: tunnelId,
        name: name,
        localPort: localPort,
        remotePort: remotePort,
        host: host,
      ));
      
      // Save tunnels
      await _saveTunnels();
      
      return tunnelId;
      
    } catch (e) {
      tunnel.status = TunnelStatus.failed;
      tunnel.lastError = e.toString();
      tunnel.lastErrorTime = DateTime.now();
      
      developer.log('🌐 Failed to create tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.failed,
        tunnelId: tunnelId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _startTunnel(SSHTunnel tunnel) async {
    tunnel.status = TunnelStatus.starting;
    tunnel.startTime = DateTime.now();
    
    // Build SSH command for tunnel
    final command = _buildTunnelCommand(tunnel);
    
    try {
      // Start tunnel process
      final process = await Process.start(
        'ssh',
        command.split(' '),
        mode: ProcessStartMode.detached,
      );
      
      final tunnelProcess = TunnelProcess(
        tunnelId: tunnel.id,
        process: process,
        startTime: DateTime.now(),
        command: command,
      );
      
      _tunnelProcesses[tunnel.id] = tunnelProcess;
      
      // Wait a moment to check if process started successfully
      await Future.delayed(Duration(seconds: 2));
      
      final exitCode = await process.exitCode;
      if (exitCode != null) {
        throw Exception('SSH tunnel process exited immediately with code $exitCode');
      }
      
      tunnel.status = TunnelStatus.active;
      tunnel.lastUsed = DateTime.now();
      _activeTunnels++;
      
      // Add to used ports
      _usedPorts.add(TunnelPort(
        port: tunnel.localPort,
        tunnelId: tunnel.id,
        inUseSince: DateTime.now(),
      ));
      
      developer.log('🌐 Tunnel started: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.started,
        tunnelId: tunnel.id,
      ));
      
    } catch (e) {
      tunnel.status = TunnelStatus.failed;
      tunnel.lastError = e.toString();
      tunnel.lastErrorTime = DateTime.now();
      
      developer.log('🌐 Failed to start tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.failed,
        tunnelId: tunnel.id,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  String _buildTunnelCommand(SSHTunnel tunnel) {
    final command = StringBuffer();
    
    // SSH options
    command.write('-o StrictHostKeyChecking=no ');
    command.write('-o UserKnownHostsFile=/dev/null ');
    command.write('-o ExitOnForwardFailure=yes ');
    command.write('-o ServerAliveInterval=30 ');
    command.write('-o ServerAliveCountMax=3 ');
    
    // Authentication
    command.write('-i ${tunnel.privateKeyPath} ');
    
    // Tunnel type specific options
    switch (tunnel.type) {
      case TunnelType.local:
        command.write('-L ${tunnel.localPort}:${tunnel.remoteHost}:${tunnel.remotePort} ');
        break;
      case TunnelType.remote:
        command.write('-R ${tunnel.localPort}:${tunnel.remoteHost}:${tunnel.remotePort} ');
        break;
      case TunnelType.dynamic:
        command.write('-R ${tunnel.localPort} ');
        command.write('-D ${tunnel.remoteHost}:${tunnel.remotePort} ');
        break;
    }
    
    // Connection
    command.write('${tunnel.username}@${tunnel.host}');
    
    // Additional options
    for (final entry in tunnel.options.entries) {
      command.write(' ${entry.key} ${entry.value}');
    }
    
    return command.toString().trim();
  }

  bool _isPortInUse(int port) {
    return _usedPorts.any((tp) => tp.port == port && tp.inUse);
  }

  Future<void> stopTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      throw Exception('Tunnel not found: $tunnelId');
    }
    
    try {
      final process = _tunnelProcesses[tunnelId];
      if (process != null) {
        // Kill the SSH process
        await _killTunnelProcess(process);
        
        _tunnelProcesses.remove(tunnelId);
      }
      
      tunnel.status = TunnelStatus.stopped;
      tunnel.stoppedAt = DateTime.now();
      _activeTunnels--;
      
      // Remove from used ports
      _usedPorts.removeWhere((tp) => tp.tunnelId == tunnelId);
      
      developer.log('🌐 Stopped tunnel: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.stopped,
        tunnelId: tunnelId,
      ));
      
      // Save tunnels
      await _saveTunnels();
      
    } catch (e) {
      developer.log('🌐 Failed to stop tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.stopFailed,
        tunnelId: tunnelId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _killTunnelProcess(TunnelProcess process) async {
    try {
      // Try graceful shutdown first
      process.process.kill(ProcessSignal.sigterm);
      
      // Wait a moment for graceful shutdown
      await Future.delayed(Duration(seconds: 3));
      
      // Check if process is still running
      final exitCode = await process.process.exitCode;
      if (exitCode == null) {
        // Force kill if still running
        process.process.kill(ProcessSignal.sigkill);
      }
      
      developer.log('🌐 Killed tunnel process');
      
    } catch (e) {
      developer.log('🌐 Failed to kill tunnel process: $e');
    }
  }

  Future<void> restartTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      throw Exception('Tunnel not found: $tunnelId');
    }
    
    try {
      // Stop existing tunnel
      if (tunnel.status == TunnelStatus.active) {
        await stopTunnel(tunnelId);
      }
      
      // Wait a moment before restarting
      await Future.delayed(Duration(seconds: 2));
      
      // Start tunnel again
      await _startTunnel(tunnel);
      
      developer.log('🌐 Restarted tunnel: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.restarted,
        tunnelId: tunnelId,
      ));
      
    } catch (e) {
      developer.log('🌐 Failed to restart tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.restartFailed,
        tunnelId: tunnelId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> updateTunnel(String tunnelId, {
    String? name,
    String? host,
    int? remotePort,
    int? localPort,
    String? username,
    String? privateKeyPath,
    String? remoteHost,
    TunnelType? type,
    Map<String, dynamic>? options,
    bool? autoReconnect,
  }) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      throw Exception('Tunnel not found: $tunnelId');
    }
    
    // Check if local port change would conflict
    if (localPort != null && localPort != tunnel.localPort) {
      if (_isPortInUse(localPort!)) {
        throw Exception('Local port $localPort is already in use');
      }
    }
    
    try {
      // Update tunnel properties
      if (name != null) tunnel.name = name!;
      if (host != null) tunnel.host = host!;
      if (remotePort != null) tunnel.remotePort = remotePort!;
      if (localPort != null) tunnel.localPort = localPort!;
      if (username != null) tunnel.username = username!;
      if (privateKeyPath != null) tunnel.privateKeyPath = privateKeyPath!;
      if (remoteHost != null) tunnel.remoteHost = remoteHost!;
      if (type != null) tunnel.type = type!;
      if (options != null) tunnel.options.addAll(options!);
      if (autoReconnect != null) tunnel.autoReconnect = autoReconnect!;
      
      tunnel.lastModified = DateTime.now();
      
      // If tunnel is active, restart with new settings
      if (tunnel.status == TunnelStatus.active) {
        await restartTunnel(tunnelId);
      }
      
      developer.log('🌐 Updated tunnel: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.updated,
        tunnelId: tunnelId,
      ));
      
      // Save tunnels
      await _saveTunnels();
      
    } catch (e) {
      developer.log('🌐 Failed to update tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.updateFailed,
        tunnelId: tunnelId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> deleteTunnel(String tunnelId) async {
    final tunnel = _tunnels.remove(tunnelId);
    if (tunnel == null) {
      throw Exception('Tunnel not found: $tunnelId');
    }
    
    try {
      // Stop tunnel if active
      if (tunnel.status == TunnelStatus.active) {
        await stopTunnel(tunnelId);
      }
      
      // Remove from used ports
      _usedPorts.removeWhere((tp) => tp.tunnelId == tunnelId);
      
      _totalTunnels--;
      
      developer.log('🌐 Deleted tunnel: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.deleted,
        tunnelId: tunnelId,
      ));
      
      // Save tunnels
      await _saveTunnels();
      
    } catch (e) {
      developer.log('🌐 Failed to delete tunnel: $e');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.deleteFailed,
        tunnelId: tunnelId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  void _checkTunnelProcess(SSHTunnel tunnel) {
    final process = _tunnelProcesses[tunnel.id];
    if (process != null) {
      // Check if process is still running
      process.process.exitCode.then((exitCode) {
        if (exitCode != null) {
          // Process has exited
          tunnel.status = TunnelStatus.failed;
          tunnel.lastError = 'Process exited with code $exitCode';
          tunnel.lastErrorTime = DateTime.now();
          
          _tunnelProcesses.remove(tunnel.id);
          _activeTunnels = max(0, _activeTunnels - 1);
          
          // Remove from used ports
          _usedPorts.removeWhere((tp) => tp.tunnelId == tunnel.id);
          
          // Attempt reconnection if enabled
          if (tunnel.autoReconnect) {
            _attemptReconnection(tunnel);
          }
        }
      });
    }
  }

  Future<void> _attemptReconnection(SSHTunnel tunnel) async {
    if (tunnel.reconnectAttempts >= tunnel.maxReconnectAttempts) {
      tunnel.status = TunnelStatus.failed;
      tunnel.lastError = 'Max reconnection attempts reached';
      tunnel.lastErrorTime = DateTime.now();
      
      developer.log('🌐 Max reconnection attempts reached for tunnel: ${tunnel.name}');
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.reconnectFailed,
        tunnelId: tunnel.id,
        error: 'Max reconnection attempts reached',
      ));
      
      return;
    }
    
    tunnel.reconnectAttempts++;
    tunnel.lastReconnectAttempt = DateTime.now();
    
    try {
      developer.log('🌐 Attempting reconnection for tunnel: ${tunnel.name} (attempt ${tunnel.reconnectAttempts})');
      
      // Wait before reconnect attempt
      await Future.delayed(tunnel.reconnectDelay);
      
      // Restart tunnel
      await _startTunnel(tunnel);
      
      _emitEvent(TunnelEvent(
        type: TunnelEventType.reconnected,
        tunnelId: tunnel.id,
        attempts: tunnel.reconnectAttempts,
      ));
      
    } catch (e) {
      developer.log('🌐 Reconnection attempt failed for tunnel: ${tunnel.name} - $e');
      
      // Schedule next attempt
      Timer(tunnel.reconnectDelay, () => _attemptReconnection(tunnel));
    }
  }

  void _checkTunnelStatuses() {
    for (final tunnel in _tunnels.values) {
      if (tunnel.status == TunnelStatus.active) {
        _checkIndividualTunnelStatus(tunnel);
      }
    }
  }

  Future<void> _checkIndividualTunnelStatus(SSHTunnel tunnel) async {
    try {
      // Check if local port is still accessible
      final socket = await Socket.connect('localhost', tunnel.localPort)
          .timeout(Duration(seconds: 5));
      
      socket.destroy();
      
      // Update tunnel status
      tunnel.lastChecked = DateTime.now();
      
    } catch (e) {
      // Port is not accessible
      tunnel.status = TunnelStatus.failed;
      tunnel.lastError = 'Port check failed: $e';
      tunnel.lastErrorTime = DateTime.now();
      
      // Attempt reconnection if enabled
      if (tunnel.autoReconnect) {
        _attemptReconnection(tunnel);
      }
    }
  }

  void _cleanupDeadTunnels() {
    final now = DateTime.now();
    final tunnelsToRemove = <String>[];
    
    for (final entry in _tunnels.entries) {
      final tunnel = entry.value;
      
      bool shouldRemove = false;
      String reason = '';
      
      // Remove tunnels that have been failed for more than 1 hour
      if (tunnel.status == TunnelStatus.failed &&
          tunnel.lastErrorTime != null &&
          now.difference(tunnel.lastErrorTime!).inHours > 1) {
        shouldRemove = true;
        reason = 'Failed for > 1 hour';
      }
      
      // Remove tunnels that have been stopped for more than 24 hours
      if (tunnel.status == TunnelStatus.stopped &&
          tunnel.stoppedAt != null &&
          now.difference(tunnel.stoppedAt!).inHours > 24) {
        shouldRemove = true;
        reason = 'Stopped for > 24 hours';
      }
      
      if (shouldRemove) {
        tunnelsToRemove.add(entry.key);
        developer.log('🌐 Cleaning up tunnel ${tunnel.name}: $reason');
      }
    }
    
    // Remove dead tunnels
    for (final tunnelId in tunnelsToRemove) {
      await deleteTunnel(tunnelId);
    }
    
    if (tunnelsToRemove.isNotEmpty) {
      _emitEvent(TunnelEvent(
        type: TunnelEventType.cleaned,
        tunnelIds: tunnelsToRemove,
      ));
    }
  }

  Future<void> _saveTunnels() async {
    try {
      final file = File(_tunnelDataFile);
      
      final tunnelsData = _tunnels.values.map((tunnel) => tunnel.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'tunnels': tunnelsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('🌐 Saved ${_tunnels.length} tunnels');
      
    } catch (e) {
      developer.log('🌐 Failed to save tunnels: $e');
    }
  }

  SSHTunnel? getTunnel(String tunnelId) {
    return _tunnels[tunnelId];
  }

  List<SSHTunnel> getTunnels() {
    return _tunnels.values.toList();
  }

  List<SSHTunnel> getActiveTunnels() {
    return _tunnels.values
        .where((tunnel) => tunnel.status == TunnelStatus.active)
        .toList();
  }

  List<SSHTunnel> getTunnelsByHost(String host) {
    return _tunnels.values
        .where((tunnel) => tunnel.host == host)
        .toList();
  }

  List<int> getUsedPorts() {
    return _usedPorts.map((tp) => tp.port).toList();
  }

  bool isPortAvailable(int port) {
    return !_isPortInUse(port);
  }

  Future<int> findAvailablePort(int startPort, int endPort) async {
    for (int port = startPort; port <= endPort; port++) {
      if (!await _isPortActuallyAvailable(port)) {
        return port;
      }
    }
    throw Exception('No available ports found in range $startPort-$endPort');
  }

  Future<bool> _isPortActuallyAvailable(int port) async {
    try {
      final socket = await Socket.connect('localhost', port)
          .timeout(Duration(seconds: 1));
      socket.destroy();
      return false; // Port is in use
    } catch (e) {
      return true; // Port is available
    }
  }

  String _generateTunnelId() {
    return 'tunnel_${DateTime.now().millisecondsSinceEpoch}_$_totalTunnels';
  }

  void _emitEvent(TunnelEvent event) {
    _tunnelController.add(event);
  }

  Stream<TunnelEvent> get tunnelEventStream => _tunnelController.stream;

  TunnelManagementStats getStats() {
    return TunnelManagementStats(
      totalTunnels: _totalTunnels,
      activeTunnels: _activeTunnels,
      usedPorts: _usedPorts.length,
      failedTunnels: _tunnels.values
          .where((tunnel) => tunnel.status == TunnelStatus.failed)
          .length,
      averageUptime: _calculateAverageUptime(),
    );
  }

  double _calculateAverageUptime() {
    final activeTunnels = _tunnels.values
        .where((tunnel) => tunnel.status == TunnelStatus.active);
    
    if (activeTunnels.isEmpty) return 0.0;
    
    final totalUptime = activeTunnels
        .map((tunnel) => tunnel.startTime != null 
            ? DateTime.now().difference(tunnel.startTime!).inMilliseconds.toDouble()
            : 0.0)
        .fold(0.0, (sum, uptime) => sum + uptime);
    
    return totalUptime / activeTunnels.length;
  }

  void dispose() {
    _statusCheckTimer?.cancel();
    _cleanupTimer?.cancel();
    
    // Stop all active tunnels
    for (final tunnelId in _tunnels.keys.toList()) {
      final tunnel = _tunnels[tunnelId];
      if (tunnel != null && tunnel!.status == TunnelStatus.active) {
        stopTunnel(tunnelId);
      }
    }
    
    _tunnels.clear();
    _tunnelProcesses.clear();
    _tunnelStatus.clear();
    _usedPorts.clear();
    _tunnelController.close();
    
    developer.log('🌐 Tunnel Management disposed');
  }
}

class SSHTunnel {
  final String id;
  String name;
  final String host;
  final int remotePort;
  final int localPort;
  final String username;
  final String privateKeyPath;
  final String remoteHost;
  final TunnelType type;
  final Map<String, dynamic> options;
  final DateTime createdAt;
  DateTime? lastModified;
  TunnelStatus status;
  DateTime? startTime;
  DateTime? stoppedAt;
  DateTime? lastUsed;
  DateTime? lastChecked;
  String? lastError;
  DateTime? lastErrorTime;
  DateTime? lastReconnectAttempt;
  bool autoReconnect;
  int reconnectAttempts;
  int maxReconnectAttempts;
  Duration reconnectDelay;

  SSHTunnel({
    required this.id,
    required this.name,
    required this.host,
    required this.remotePort,
    required this.localPort,
    required this.username,
    required this.privateKeyPath,
    required this.remoteHost,
    required this.type,
    required this.options,
    required this.createdAt,
    this.lastModified,
    required this.status,
    this.startTime,
    this.stoppedAt,
    this.lastUsed,
    this.lastChecked,
    this.lastError,
    this.lastErrorTime,
    this.lastReconnectAttempt,
    required this.autoReconnect,
    required this.reconnectAttempts,
    required this.maxReconnectAttempts,
    required this.reconnectDelay,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'remote_port': remotePort,
      'local_port': localPort,
      'username': username,
      'private_key_path': privateKeyPath,
      'remote_host': remoteHost,
      'type': type.name,
      'options': options,
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified?.toIso8601String(),
      'status': status.name,
      'start_time': startTime?.toIso8601String(),
      'stopped_at': stoppedAt?.toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
      'last_checked': lastChecked?.toIso8601String(),
      'last_error': lastError,
      'last_error_time': lastErrorTime?.toIso8601String(),
      'last_reconnect_attempt': lastReconnectAttempt?.toIso8601String(),
      'auto_reconnect': autoReconnect,
      'reconnect_attempts': reconnectAttempts,
      'max_reconnect_attempts': maxReconnectAttempts,
      'reconnect_delay': reconnectDelay.inMilliseconds,
    };
  }

  factory SSHTunnel.fromJson(Map<String, dynamic> json) {
    return SSHTunnel(
      id: json['id'],
      name: json['name'],
      host: json['host'],
      remotePort: json['remote_port'],
      localPort: json['local_port'],
      username: json['username'],
      privateKeyPath: json['private_key_path'],
      remoteHost: json['remote_host'],
      type: TunnelType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => TunnelType.local,
      ),
      options: Map<String, dynamic>.from(json['options'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      lastModified: json['last_modified'] != null ? DateTime.parse(json['last_modified']) : null,
      status: TunnelStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => TunnelStatus.stopped,
      ),
      startTime: json['start_time'] != null ? DateTime.parse(json['start_time']) : null,
      stoppedAt: json['stopped_at'] != null ? DateTime.parse(json['stopped_at']) : null,
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
      lastChecked: json['last_checked'] != null ? DateTime.parse(json['last_checked']) : null,
      lastError: json['last_error'],
      lastErrorTime: json['last_error_time'] != null ? DateTime.parse(json['last_error_time']) : null,
      lastReconnectAttempt: json['last_reconnect_attempt'] != null ? DateTime.parse(json['last_reconnect_attempt']) : null,
      autoReconnect: json['auto_reconnect'] ?? true,
      reconnectAttempts: json['reconnect_attempts'] ?? 0,
      maxReconnectAttempts: json['max_reconnect_attempts'] ?? 5,
      reconnectDelay: Duration(milliseconds: json['reconnect_delay'] ?? 5000),
    );
  }
}

class TunnelProcess {
  final String tunnelId;
  final Process process;
  final DateTime startTime;
  final String command;

  TunnelProcess({
    required this.tunnelId,
    required this.process,
    required this.startTime,
    required this.command,
  });
}

class TunnelPort {
  final int port;
  final String tunnelId;
  final DateTime inUseSince;

  TunnelPort({
    required this.port,
    required this.tunnelId,
    required this.inUseSince,
  });
}

enum TunnelType {
  local,
  remote,
  dynamic,
}

enum TunnelStatus {
  creating,
  starting,
  active,
  stopping,
  stopped,
  failed,
  reconnecting,
}

enum TunnelEventType {
  created,
  started,
  stopped,
  failed,
  restarted,
  updated,
  deleted,
  reconnected,
  reconnectFailed,
  stopFailed,
  updateFailed,
  deleteFailed,
  cleaned,
}

class TunnelEvent {
  final TunnelEventType type;
  final String? tunnelId;
  final String? name;
  final int? localPort;
  final int? remotePort;
  final String? host;
  final String? error;
  final int? attempts;
  final List<String>? tunnelIds;

  TunnelEvent({
    required this.type,
    this.tunnelId,
    this.name,
    this.localPort,
    this.remotePort,
    this.host,
    this.error,
    this.attempts,
    this.tunnelIds,
  });
}

class TunnelManagementStats {
  final int totalTunnels;
  final int activeTunnels;
  final int usedPorts;
  final int failedTunnels;
  final double averageUptime;

  TunnelManagementStats({
    required this.totalTunnels,
    required this.activeTunnels,
    required this.usedPorts,
    required this.failedTunnels,
    required this.averageUptime,
  });
}
