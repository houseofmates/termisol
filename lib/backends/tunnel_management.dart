import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production-grade tunnel management for Termisol
/// 
/// Features:
/// - SSH tunnel management
/// - Port forwarding
/// - Dynamic tunnel creation
/// - Tunnel monitoring
/// - Auto-reconnection
class TunnelManagement {
  static final TunnelManagement _instance = TunnelManagement._internal();
  factory TunnelManagement() => _instance;
  TunnelManagement._internal();

  bool _initialized = false;
  final Map<String, Tunnel> _tunnels = {};
  final StreamController<TunnelEvent> _eventController = StreamController.broadcast();
  final Map<String, Process> _tunnelProcesses = {};
  Timer? _monitoringTimer;
  
  Stream<TunnelEvent> get events => _eventController.stream;
  bool get isInitialized => _initialized;
  Map<String, Tunnel> get tunnels => Map.unmodifiable(_tunnels);
  List<Tunnel> get activeTunnels => _tunnels.values
      .where((tunnel) => tunnel.status == TunnelStatus.active)
      .toList();

  /// Initialize tunnel management
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadPersistedTunnels();
      _startTunnelMonitoring();
      _initialized = true;
      debugPrint('✅ TunnelManagement initialized');
      _eventController.add(TunnelEvent('initialized', 'Tunnel management ready'));
    } catch (e) {
      debugPrint('❌ TunnelManagement initialization failed: $e');
      _eventController.add(TunnelEvent('error', 'Initialization failed: $e'));
    }
  }

  /// Load persisted tunnels
  Future<void> _loadPersistedTunnels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tunnelsJson = prefs.getString('persisted_tunnels');
      
      if (tunnelsJson != null) {
        final List<dynamic> tunnelsList = jsonDecode(tunnelsJson);
        for (final tunnelJson in tunnelsList) {
          final tunnel = Tunnel.fromJson(tunnelJson);
          _tunnels[tunnel.id] = tunnel;
          
          // Auto-start persistent tunnels
          if (tunnel.persistent && tunnel.autoStart) {
            await startTunnel(tunnel.id);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load persisted tunnels: $e');
    }
  }

  /// Start tunnel monitoring
  void _startTunnelMonitoring() {
    _monitoringTimer = Timer.periodic(Duration(seconds: 10), (_) async {
      await _monitorTunnels();
    });
  }

  /// Monitor tunnels
  Future<void> _monitorTunnels() async {
    try {
      for (final tunnel in _tunnels.values) {
        if (tunnel.status == TunnelStatus.active) {
          final isHealthy = await _checkTunnelHealth(tunnel);
          
          if (!isHealthy) {
            debugPrint('Tunnel ${tunnel.id} is unhealthy, attempting restart');
            await _restartTunnel(tunnel);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to monitor tunnels: $e');
    }
  }

  /// Check tunnel health
  Future<bool> _checkTunnelHealth(Tunnel tunnel) async {
    try {
      switch (tunnel.type) {
        case TunnelType.ssh:
          return await _checkSshTunnelHealth(tunnel);
        case TunnelType.http:
          return await _checkHttpTunnelHealth(tunnel);
        case TunnelType.socks:
          return await _checkSocksTunnelHealth(tunnel);
        default:
          return true;
      }
    } catch (e) {
      debugPrint('Failed to check tunnel health: $e');
      return false;
    }
  }

  /// Check SSH tunnel health
  Future<bool> _checkSshTunnelHealth(Tunnel tunnel) async {
    try {
      final process = _tunnelProcesses[tunnel.id];
      if (process == null) return false;
      
      // Check if process is still running
      return await process.exitCode.then((_) => false).catchError((_) => true);
    } catch (e) {
      return false;
    }
  }

  /// Check HTTP tunnel health
  Future<bool> _checkHttpTunnelHealth(Tunnel tunnel) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://localhost:${tunnel.localPort}'));
      final response = await request.close();
      client.close();
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Check SOCKS tunnel health
  Future<bool> _checkSocksTunnelHealth(Tunnel tunnel) async {
    try {
      final socket = await Socket.connect('localhost', tunnel.localPort);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create a new tunnel
  Future<String> createTunnel({
    required TunnelType type,
    required String host,
    required int remotePort,
    int? localPort,
    String? username,
    String? password,
    String? keyPath,
    Map<String, dynamic>? options,
    bool persistent = false,
    bool autoStart = false,
    String? description,
  }) async {
    final tunnelId = 'tunnel_${DateTime.now().millisecondsSinceEpoch}';
    
    final tunnel = Tunnel(
      id: tunnelId,
      type: type,
      host: host,
      remotePort: remotePort,
      localPort: localPort ?? await _findAvailablePort(),
      username: username,
      password: password,
      keyPath: keyPath,
      options: options ?? {},
      persistent: persistent,
      autoStart: autoStart,
      description: description ?? '',
      status: TunnelStatus.created,
      createdAt: DateTime.now(),
    );
    
    _tunnels[tunnelId] = tunnel;
    
    debugPrint('✅ Tunnel created: $tunnelId');
    _eventController.add(TunnelEvent('tunnel_created', 'Tunnel created: $tunnelId'));
    
    _persistTunnels();
    
    if (autoStart) {
      startTunnel(tunnelId);
    }
    
    return tunnelId;
  }

  /// Find available port
  Future<int> _findAvailablePort() async {
    try {
      final socket = await ServerSocket.bind('localhost', 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (e) {
      // Fallback to random port in range 20000-30000
      return 20000 + (DateTime.now().millisecondsSinceEpoch % 10000);
    }
  }

  /// Start a tunnel
  Future<bool> startTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      debugPrint('Tunnel not found: $tunnelId');
      return false;
    }
    
    try {
      if (tunnel.status == TunnelStatus.active) {
        debugPrint('Tunnel already active: $tunnelId');
        return true;
      }
      
      Process? process;
      
      switch (tunnel.type) {
        case TunnelType.ssh:
          process = await _startSshTunnel(tunnel);
          break;
        case TunnelType.http:
          process = await _startHttpTunnel(tunnel);
          break;
        case TunnelType.socks:
          process = await _startSocksTunnel(tunnel);
          break;
      }
      
      if (process != null) {
        _tunnelProcesses[tunnelId] = process;
        tunnel.status = TunnelStatus.active;
        tunnel.startTime = DateTime.now();
        
        debugPrint('✅ Tunnel started: $tunnelId');
        _eventController.add(TunnelEvent('tunnel_started', 'Tunnel started: $tunnelId'));
        
        _persistTunnels();
        return true;
      }
    } catch (e) {
      debugPrint('Failed to start tunnel $tunnelId: $e');
      _eventController.add(TunnelEvent('error', 'Failed to start tunnel: $tunnelId - $e'));
    }
    
    return false;
  }

  /// Start SSH tunnel
  Future<Process?> _startSshTunnel(Tunnel tunnel) async {
    try {
      final args = <String>[
        '-L', '${tunnel.localPort}:${tunnel.host}:${tunnel.remotePort}',
        '-N', // Don't execute remote command
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=60',
        '-o', 'ServerAliveCountMax=3',
      ];
      
      if (tunnel.keyPath != null) {
        args.addAll(['-i', tunnel.keyPath!]);
      }
      
      String host = tunnel.host;
      if (tunnel.username != null) {
        host = '${tunnel.username}@${tunnel.host}';
      }
      
      args.add(host);
      
      final process = await Process.start('ssh', args);
      
      // Handle process output
      process.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('SSH tunnel ${tunnel.id}: $data');
      });
      
      process.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('SSH tunnel ${tunnel.id} error: $data');
      });
      
      // Handle process exit
      process.exitCode.then((exitCode) {
        if (exitCode != 0) {
          debugPrint('SSH tunnel ${tunnel.id} exited with code: $exitCode');
          _handleTunnelExit(tunnel.id);
        }
      });
      
      return process;
    } catch (e) {
      debugPrint('Failed to start SSH tunnel: $e');
      return null;
    }
  }

  /// Start HTTP tunnel
  Future<Process?> _startHttpTunnel(Tunnel tunnel) async {
    try {
      // Simulate HTTP tunnel process
      final args = <String>[
        '--local-port', tunnel.localPort.toString(),
        '--remote-host', tunnel.host,
        '--remote-port', tunnel.remotePort.toString(),
      ];
      
      final process = await Process.start('http-tunnel', args);
      
      return process;
    } catch (e) {
      debugPrint('Failed to start HTTP tunnel: $e');
      return null;
    }
  }

  /// Start SOCKS tunnel
  Future<Process?> _startSocksTunnel(Tunnel tunnel) async {
    try {
      final args = <String>[
        '-D', tunnel.localPort.toString(),
        '-N',
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=60',
        '-o', 'ServerAliveCountMax=3',
      ];
      
      if (tunnel.keyPath != null) {
        args.addAll(['-i', tunnel.keyPath!]);
      }
      
      String host = tunnel.host;
      if (tunnel.username != null) {
        host = '${tunnel.username}@${tunnel.host}';
      }
      
      args.add(host);
      
      final process = await Process.start('ssh', args);
      
      return process;
    } catch (e) {
      debugPrint('Failed to start SOCKS tunnel: $e');
      return null;
    }
  }

  /// Stop a tunnel
  Future<bool> stopTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      debugPrint('Tunnel not found: $tunnelId');
      return false;
    }
    
    try {
      final process = _tunnelProcesses.remove(tunnelId);
      if (process != null) {
        process.kill();
        await process.exitCode;
      }
      
      tunnel.status = TunnelStatus.stopped;
      tunnel.endTime = DateTime.now();
      
      debugPrint('✅ Tunnel stopped: $tunnelId');
      _eventController.add(TunnelEvent('tunnel_stopped', 'Tunnel stopped: $tunnelId'));
      
      _persistTunnels();
      return true;
    } catch (e) {
      debugPrint('Failed to stop tunnel $tunnelId: $e');
      return false;
    }
  }

  /// Delete a tunnel
  Future<bool> deleteTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) {
      debugPrint('Tunnel not found: $tunnelId');
      return false;
    }
    
    try {
      // Stop tunnel if active
      if (tunnel.status == TunnelStatus.active) {
        await stopTunnel(tunnelId);
      }
      
      _tunnels.remove(tunnelId);
      
      debugPrint('✅ Tunnel deleted: $tunnelId');
      _eventController.add(TunnelEvent('tunnel_deleted', 'Tunnel deleted: $tunnelId'));
      
      _persistTunnels();
      return true;
    } catch (e) {
      debugPrint('Failed to delete tunnel $tunnelId: $e');
      return false;
    }
  }

  /// Restart tunnel
  Future<bool> _restartTunnel(Tunnel tunnel) async {
    await stopTunnel(tunnel.id);
    await Future.delayed(Duration(seconds: 2));
    return await startTunnel(tunnel.id);
  }

  /// Handle tunnel exit
  void _handleTunnelExit(String tunnelId) {
    final tunnel = _tunnels[tunnelId];
    if (tunnel != null) {
      tunnel.status = TunnelStatus.failed;
      tunnel.endTime = DateTime.now();
      
      _tunnelProcesses.remove(tunnelId);
      
      debugPrint('❌ Tunnel exited: $tunnelId');
      _eventController.add(TunnelEvent('tunnel_exited', 'Tunnel exited: $tunnelId'));
      
      _persistTunnels();
    }
  }

  /// Get tunnel by ID
  Tunnel? getTunnel(String tunnelId) {
    return _tunnels[tunnelId];
  }

  /// Get tunnels by type
  List<Tunnel> getTunnelsByType(TunnelType type) {
    return _tunnels.values
        .where((tunnel) => tunnel.type == type)
        .toList();
  }

  /// Get tunnels by status
  List<Tunnel> getTunnelsByStatus(TunnelStatus status) {
    return _tunnels.values
        .where((tunnel) => tunnel.status == status)
        .toList();
  }

  /// Persist tunnels
  Future<void> _persistTunnels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final persistentTunnels = _tunnels.values
          .where((tunnel) => tunnel.persistent)
          .toList();
      
      final tunnelsJson = jsonEncode(
        persistentTunnels.map((tunnel) => tunnel.toJson()).toList()
      );
      
      await prefs.setString('persisted_tunnels', tunnelsJson);
    } catch (e) {
      debugPrint('Failed to persist tunnels: $e');
    }
  }

  /// Get tunnel statistics
  Map<String, dynamic> getStatistics() {
    final tunnelsByStatus = <TunnelStatus, int>{};
    for (final tunnel in _tunnels.values) {
      tunnelsByStatus[tunnel.status] = (tunnelsByStatus[tunnel.status] ?? 0) + 1;
    }
    
    final tunnelsByType = <TunnelType, int>{};
    for (final tunnel in _tunnels.values) {
      tunnelsByType[tunnel.type] = (tunnelsByType[tunnel.type] ?? 0) + 1;
    }
    
    return {
      'initialized': _initialized,
      'totalTunnels': _tunnels.length,
      'activeTunnels': activeTunnels.length,
      'tunnelsByStatus': tunnelsByStatus.map((k, v) => MapEntry(k.name, v)),
      'tunnelsByType': tunnelsByType.map((k, v) => MapEntry(k.name, v)),
    };
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      _monitoringTimer?.cancel();
      
      // Stop all active tunnels
      for (final tunnelId in _tunnelProcesses.keys.toList()) {
        await stopTunnel(tunnelId);
      }
      
      _tunnels.clear();
      _tunnelProcesses.clear();
      await _eventController.close();
      _initialized = false;
      
      debugPrint('TunnelManagement disposed');
    } catch (e) {
      debugPrint('Error disposing TunnelManagement: $e');
    }
  }
}

/// Tunnel definition
class Tunnel {
  final String id;
  final TunnelType type;
  final String host;
  final int remotePort;
  final int localPort;
  final String? username;
  final String? password;
  final String? keyPath;
  final Map<String, dynamic> options;
  final bool persistent;
  final bool autoStart;
  final String description;
  TunnelStatus status;
  final DateTime createdAt;
  DateTime? startTime;
  DateTime? endTime;

  Tunnel({
    required this.id,
    required this.type,
    required this.host,
    required this.remotePort,
    required this.localPort,
    this.username,
    this.password,
    this.keyPath,
    required this.options,
    required this.persistent,
    required this.autoStart,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory Tunnel.fromJson(Map<String, dynamic> json) {
    return Tunnel(
      id: json['id'] as String,
      type: TunnelType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => TunnelType.ssh,
      ),
      host: json['host'] as String,
      remotePort: json['remotePort'] as int,
      localPort: json['localPort'] as int,
      username: json['username'] as String?,
      password: json['password'] as String?,
      keyPath: json['keyPath'] as String?,
      options: json['options'] as Map<String, dynamic>? ?? {},
      persistent: json['persistent'] as bool? ?? false,
      autoStart: json['autoStart'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      status: TunnelStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => TunnelStatus.created,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    )..startTime = json['startTime'] != null 
        ? DateTime.parse(json['startTime'] as String) 
        : null
      ..endTime = json['endTime'] != null 
        ? DateTime.parse(json['endTime'] as String) 
        : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'host': host,
      'remotePort': remotePort,
      'localPort': localPort,
      'username': username,
      'password': password,
      'keyPath': keyPath,
      'options': options,
      'persistent': persistent,
      'autoStart': autoStart,
      'description': description,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  /// Get tunnel duration
  Duration? get duration {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!);
    } else if (startTime != null) {
      return DateTime.now().difference(startTime!);
    }
    return null;
  }

  /// Get connection string
  String get connectionString {
    switch (type) {
      case TunnelType.ssh:
        return 'ssh -L $localPort:$host:$remotePort $host';
      case TunnelType.http:
        return 'http://localhost:$localPort -> $host:$remotePort';
      case TunnelType.socks:
        return 'socks://localhost:$localPort -> $host';
    }
  }
}

/// Tunnel type
enum TunnelType {
  ssh,
  http,
  socks,
}

/// Tunnel status
enum TunnelStatus {
  created,
  active,
  stopped,
  failed,
}

/// Tunnel event
class TunnelEvent {
  final String type;
  final String message;
  final DateTime timestamp;

  TunnelEvent(this.type, this.message) : timestamp = DateTime.now();
}