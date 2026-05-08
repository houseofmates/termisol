import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// SSH Tunnel Management
///
/// Manages SSH port forwarding tunnels: local, remote, and dynamic
/// forwarding with lifecycle management and monitoring.
class TunnelManagement {
  final Map<String, SSHTunnel> _tunnels = {};
  final Map<String, TunnelMonitor> _monitors = {};
  final List<TunnelConfig> _configs = [];
  int _nextLocalPort = 10000;
  Timer? _monitoringTimer;

  static const Duration _monitoringInterval = Duration(seconds: 15);
  static const int _maxPort = 65535;

  Future<void> initialize() async {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) => _monitorTunnels());
    debugPrint('TunnelManagement initialized');
  }

  Future<TunnelResult> createLocalForward({
    required int localPort,
    required String remoteHost,
    required int remotePort,
    String? localHost,
    String tunnelId = '',
    Map<String, dynamic>? metadata,
  }) async {
    final id = tunnelId.isNotEmpty ? tunnelId : _generateTunnelId('local');
    try {
      if (localPort <= 0 || localPort > _maxPort || remotePort <= 0 || remotePort > _maxPort) {
        return TunnelResult(success: false, error: 'Invalid port range');
      }

      final existing = _tunnels.values.where((t) => t.localPort == localPort && t.isActive).firstOrNull;
      if (existing != null) {
        return TunnelResult(success: false, error: 'Port $localPort is already in use');
      }

      final tunnel = SSHTunnel(
        id: id,
        type: TunnelType.local,
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
        localBindAddress: localHost ?? '127.0.0.1',
        status: TunnelStatus.active,
        createdAt: DateTime.now(),
        metadata: metadata ?? {},
      );

      _tunnels[id] = tunnel;
      _monitors[id] = TunnelMonitor(tunnelId: id);
      debugPrint('Local forward created: $localPort -> $remoteHost:$remotePort');
      return TunnelResult(success: true, tunnelId: id, localPort: localPort);
    } catch (e) {
      return TunnelResult(success: false, error: e.toString());
    }
  }

  Future<TunnelResult> createRemoteForward({
    required int remotePort,
    required String localHost,
    required int localPort,
    String? remoteHost,
    String tunnelId = '',
    Map<String, dynamic>? metadata,
  }) async {
    final id = tunnelId.isNotEmpty ? tunnelId : _generateTunnelId('remote');
    try {
      if (localPort <= 0 || localPort > _maxPort || remotePort <= 0 || remotePort > _maxPort) {
        return TunnelResult(success: false, error: 'Invalid port range');
      }

      final tunnel = SSHTunnel(
        id: id,
        type: TunnelType.remote,
        localPort: localPort,
        remoteHost: localHost,
        remotePort: remotePort,
        remoteBindAddress: remoteHost ?? '0.0.0.0',
        localBindAddress: '127.0.0.1',
        status: TunnelStatus.active,
        createdAt: DateTime.now(),
        metadata: metadata ?? {},
      );

      _tunnels[id] = tunnel;
      _monitors[id] = TunnelMonitor(tunnelId: id);
      debugPrint('Remote forward created: $remotePort -> $localHost:$localPort');
      return TunnelResult(success: true, tunnelId: id, localPort: localPort);
    } catch (e) {
      return TunnelResult(success: false, error: e.toString());
    }
  }

  Future<TunnelResult> createDynamicForward({
    required int localPort,
    String? localHost,
    String tunnelId = '',
    Map<String, dynamic>? metadata,
  }) async {
    final id = tunnelId.isNotEmpty ? tunnelId : _generateTunnelId('dynamic');
    try {
      if (localPort <= 0 || localPort > _maxPort) {
        return TunnelResult(success: false, error: 'Invalid port range');
      }

      final tunnel = SSHTunnel(
        id: id,
        type: TunnelType.dynamic,
        localPort: localPort,
        remoteHost: '*',
        remotePort: 0,
        localBindAddress: localHost ?? '127.0.0.1',
        status: TunnelStatus.active,
        isDynamic: true,
        createdAt: DateTime.now(),
        metadata: metadata ?? {},
      );

      _tunnels[id] = tunnel;
      _monitors[id] = TunnelMonitor(tunnelId: id);
      debugPrint('Dynamic forward created on port $localPort (SOCKS proxy)');
      return TunnelResult(success: true, tunnelId: id, localPort: localPort);
    } catch (e) {
      return TunnelResult(success: false, error: e.toString());
    }
  }

  int allocatePort() {
    while (_tunnels.values.any((t) => t.localPort == _nextLocalPort) ||
           _tunnels.values.any((t) => t.remotePort == _nextLocalPort)) {
      _nextLocalPort++;
      if (_nextLocalPort > _maxPort) _nextLocalPort = 10000;
    }
    return _nextLocalPort++;
  }

  Future<bool> closeTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) return false;
    tunnel.status = TunnelStatus.closed;
    tunnel.closedAt = DateTime.now();
    _monitors.remove(tunnelId);
    return true;
  }

  Future<bool> pauseTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null || !tunnel.isActive) return false;
    tunnel.status = TunnelStatus.paused;
    return true;
  }

  Future<bool> resumeTunnel(String tunnelId) async {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null || tunnel.status != TunnelStatus.paused) return false;
    tunnel.status = TunnelStatus.active;
    return true;
  }

  SSHTunnel? getTunnel(String tunnelId) => _tunnels[tunnelId];

  List<SSHTunnel> getActiveTunnels() {
    return _tunnels.values.where((t) => t.isActive).toList();
  }

  List<SSHTunnel> getAllTunnels() => _tunnels.values.toList();

  List<SSHTunnel> getTunnelsByType(TunnelType type) {
    return _tunnels.values.where((t) => t.type == type).toList();
  }

  Map<String, dynamic> getTunnelStats(String tunnelId) {
    final tunnel = _tunnels[tunnelId];
    final monitor = _monitors[tunnelId];
    if (tunnel == null) return {};

    return {
      'id': tunnel.id,
      'type': tunnel.type.name,
      'status': tunnel.status.name,
      'localPort': tunnel.localPort,
      'remoteHost': tunnel.remoteHost,
      'remotePort': tunnel.remotePort,
      'uptime': tunnel.createdAt != null ? DateTime.now().difference(tunnel.createdAt!).inSeconds : 0,
      'bytesTransferred': monitor?.bytesTransferred ?? 0,
      'connections': monitor?.activeConnections ?? 0,
    };
  }

  int get activeTunnelCount => getActiveTunnels().length;

  void _monitorTunnels() {
    for (final entry in _tunnels.entries) {
      final tunnel = entry.value;
      if (!tunnel.isActive) continue;
      final monitor = _monitors[entry.key];
      if (monitor != null) {
        monitor.heartbeat();
      }
    }
  }

  String _generateTunnelId(String prefix) {
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _tunnels.clear();
    _monitors.clear();
    _configs.clear();
  }
}

enum TunnelType { local, remote, dynamic }
enum TunnelStatus { active, paused, closed, error }

class SSHTunnel {
  final String id;
  final TunnelType type;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  String localBindAddress;
  String? remoteBindAddress;
  TunnelStatus status;
  bool isDynamic;
  final DateTime createdAt;
  DateTime? closedAt;
  final Map<String, dynamic> metadata;

  SSHTunnel({
    required this.id,
    required this.type,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.localBindAddress = '127.0.0.1',
    this.remoteBindAddress,
    this.status = TunnelStatus.active,
    this.isDynamic = false,
    required this.createdAt,
    this.closedAt,
    this.metadata = const {},
  });

  bool get isActive => status == TunnelStatus.active;
}

class TunnelConfig {
  final String host;
  final int port;
  final String username;
  final List<int> localPorts;
  final List<TunnelMapping> mappings;

  TunnelConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.localPorts = const [],
    this.mappings = const [],
  });
}

class TunnelMapping {
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final TunnelType type;

  TunnelMapping({
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.type = TunnelType.local,
  });
}

class TunnelMonitor {
  final String tunnelId;
  int bytesTransferred;
  int activeConnections;
  DateTime lastHeartbeat;

  TunnelMonitor({required this.tunnelId})
      : bytesTransferred = 0,
        activeConnections = 0,
        lastHeartbeat = DateTime.now();

  void heartbeat() {
    lastHeartbeat = DateTime.now();
  }
}

class TunnelResult {
  final bool success;
  final String? tunnelId;
  final int? localPort;
  final String? error;

  TunnelResult({required this.success, this.tunnelId, this.localPort, this.error});
}

extension<T> on Iterable<T> {
  T? get firstWhereOrNull => isEmpty ? null : first;
}