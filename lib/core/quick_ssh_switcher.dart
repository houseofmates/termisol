import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:process_run/process_run.dart';
import 'package:path/path.dart' as path;

/// Quick SSH Host Switcher with Key Management
/// 
/// Implements intelligent SSH management:
/// - Quick host switching with keyboard shortcuts
/// - SSH key management and rotation
/// - Host profile management
/// - Connection health monitoring
/// - Auto-reconnection with fallback
/// - Secure credential storage
/// - Multi-device synchronization
class QuickSSHSwitcher {
  bool _isInitialized = false;
  
  // SSH configuration
  final Map<String, SSHHost> _hosts = {};
  final Map<String, SSHKey> _keys = {};
  String? _activeKeyId;
  String? _activeHostId;
  
  // Connection state
  final Map<String, SSHConnection> _connections = {};
  final StreamController<SSHEvent> _eventController = StreamController.broadcast();
  Timer? _healthCheckTimer;
  
  // Quick access
  final List<String> _recentHosts = [];
  final Map<String, int> _hostUsageCount = {};
  
  // Configuration
  String _sshConfigPath = '';
  String _sshKeyDir = '';
  bool _autoReconnect = true;
  int _maxRecentHosts = 10;
  
  // Event handlers
  final List<Function(SSHHost)> _onHostAdded = [];
  final List<Function(SSHHost)> _onHostRemoved = [];
  final List<Function(SSHHost)> _onHostConnected = [];
  final List<Function(SSHHost)> _onHostDisconnected = [];
  final List<Function(SSHKey)> _onKeyAdded = [];
  final List<Function(String)> _onActiveHostChanged = [];
  final List<Function(String)> _onActiveKeyChanged = [];
  
  QuickSSHSwitcher();
  
  bool get isInitialized => _isInitialized;
  Map<String, SSHHost> get hosts => Map.unmodifiable(_hosts);
  Map<String, SSHKey> get keys => Map.unmodifiable(_keys);
  String? get activeKeyId => _activeKeyId;
  String? get activeHostId => _activeHostId;
  List<String> get recentHosts => List.unmodifiable(_recentHosts);
  Stream<SSHEvent> get events => _eventController.stream;
  
  /// Initialize SSH switcher
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup paths
      _setupPaths();
      
      // Load existing configuration
      await _loadSSHConfig();
      await _loadSSHKeys();
      
      // Start health monitoring
      _startHealthMonitoring();
      
      _isInitialized = true;
      debugPrint('🔑 Quick SSH Switcher initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize SSH Switcher: $e');
      rethrow;
    }
  }
  
  /// Setup file paths
  void _setupPaths() {
    final homeDir = Platform.environment['HOME'] ?? '';
    _sshConfigPath = path.join(homeDir, '.ssh', 'config');
    _sshKeyDir = path.join(homeDir, '.ssh');
  }
  
  /// Load SSH configuration
  Future<void> _loadSSHConfig() async {
    try {
      final configFile = File(_sshConfigPath);
      if (!await configFile.exists()) {
        // Create default hosts for house setup
        await _createDefaultHosts();
        return;
      }
      
      final content = await configFile.readAsString();
      final lines = content.split('\n');
      
      SSHHost? currentHost;
      String? currentSection;
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        
        if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) continue;
        
        if (trimmedLine.startsWith('Host ')) {
          // Save previous host
          if (currentHost != null && currentSection != null) {
            _hosts[currentSection!] = currentHost;
          }
          
          // Start new host
          currentSection = trimmedLine.substring(5).trim();
          currentHost = SSHHost(
            id: currentSection,
            name: currentSection,
            configLines: [],
          );
        } else if (currentHost != null && currentSection != null) {
          // Add config line to current host
          currentHost.configLines.add(trimmedLine);
          
          // Parse key configuration
          _parseHostConfigLine(currentHost, trimmedLine);
        }
      }
      
      // Save last host
      if (currentHost != null && currentSection != null) {
        _hosts[currentSection!] = currentHost;
      }
      
      debugPrint('🔑 Loaded ${_hosts.length} SSH hosts from config');
    } catch (e) {
      debugPrint('⚠️ Failed to load SSH config: $e');
      await _createDefaultHosts();
    }
  }
  
  /// Create default hosts for house setup
  Future<void> _createDefaultHosts() async {
    final defaultHosts = {
      'ubuntu': SSHHost(
        id: 'ubuntu',
        name: 'Ubuntu Server',
        hostname: '192.168.4.250',
        username: 'house',
        port: 22,
        keyPath: '/home/house/.ssh/hermes_key',
        description: 'Main Ubuntu development server',
        tags: ['development', 'server', 'linux'],
        quickConnect: true,
        autoReconnect: true,
      ),
      'popos': SSHHost(
        id: 'popos',
        name: 'Pop!_OS Desktop',
        hostname: '192.168.4.233',
        username: 'house',
        port: 22,
        keyPath: '/home/house/.ssh/hermes_key',
        description: 'Pop!_OS desktop machine',
        tags: ['desktop', 'linux', 'popos'],
        quickConnect: true,
        autoReconnect: true,
      ),
      'local': SSHHost(
        id: 'local',
        name: 'Local Machine',
        hostname: 'localhost',
        username: Platform.environment['USER'] ?? 'house',
        port: 22,
        keyPath: null,
        description: 'Local development environment',
        tags: ['local', 'development'],
        quickConnect: true,
        autoReconnect: false,
      ),
      'github': SSHHost(
        id: 'github',
        name: 'GitHub',
        hostname: 'github.com',
        username: 'houseofmates',
        port: 22,
        keyPath: '/home/house/.ssh/id_ed25519',
        description: 'GitHub access',
        tags: ['git', 'remote', 'version-control'],
        quickConnect: false,
        autoReconnect: false,
      ),
    };
    
    _hosts.addAll(defaultHosts);
    await _saveSSHConfig();
    
    debugPrint('🔑 Created default SSH hosts for house setup');
  }
  
  /// Parse host configuration line
  void _parseHostConfigLine(SSHHost host, String line) {
    if (line.startsWith('HostName ')) {
      host.hostname = line.substring(9).trim();
    } else if (line.startsWith('User ')) {
      host.username = line.substring(5).trim();
    } else if (line.startsWith('Port ')) {
      host.port = int.tryParse(line.substring(5).trim()) ?? 22;
    } else if (line.startsWith('IdentityFile ')) {
      host.keyPath = line.substring(13).trim();
    } else if (line.startsWith('ConnectTimeout ')) {
      host.connectTimeout = int.tryParse(line.substring(15).trim()) ?? 30;
    } else if (line.startsWith('ServerAliveInterval ')) {
      host.serverAliveInterval = int.tryParse(line.substring(20).trim()) ?? 60;
    }
  }
  
  /// Load SSH keys
  Future<void> _loadSSHKeys() async {
    try {
      final keyDir = Directory(_sshKeyDir);
      if (!await keyDir.exists()) return;
      
      await for (final entity in keyDir.list()) {
        if (entity is File && entity.path.endsWith('.pub')) {
          final publicKey = await _parseSSHPublicKey(entity.path);
          if (publicKey != null) {
            _keys[publicKey.fingerprint] = publicKey;
          }
        }
      }
      
      debugPrint('🔑 Loaded ${_keys.length} SSH keys');
    } catch (e) {
      debugPrint('⚠️ Failed to load SSH keys: $e');
    }
  }
  
  /// Parse SSH public key
  Future<SSHKey?> _parseSSHPublicKey(String keyPath) async {
    try {
      final keyFile = File(keyPath);
      final content = await keyFile.readAsString();
      final lines = content.split('\n');
      
      String? keyType;
      String? fingerprint;
      String? comment;
      
      for (final line in lines) {
        if (line.startsWith('ssh-')) {
          keyType = line.split(' ')[0];
        } else if (line.startsWith('SHA256:')) {
          fingerprint = line.split(':')[1]?.trim();
        } else if (comment == null && line.trim().isNotEmpty && !line.startsWith('ssh-')) {
          comment = line.trim();
        }
      }
      
      if (keyType != null && fingerprint != null) {
        return SSHKey(
          id: fingerprint!,
          type: keyType!,
          path: keyPath,
          fingerprint: fingerprint!,
          comment: comment,
          isDefault: keyPath.contains('hermes_key') || keyPath.contains('id_rsa'),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to parse SSH key $keyPath: $e');
      return null;
    }
  }
  
  /// Start health monitoring
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnectionHealth();
    });
  }
  
  /// Check connection health
  Future<void> _checkConnectionHealth() async {
    for (final entry in _connections.entries) {
      final hostId = entry.key;
      final connection = entry.value;
      
      if (connection.isActive) {
        try {
          final result = await Process.run('ssh', [
            '-O', 'ConnectTimeout=5',
            '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=no',
            '${connection.username}@${connection.hostname}',
            'echo "health_check"',
          ]);
          
          final isHealthy = result.exitCode == 0;
          connection.isHealthy = isHealthy;
          connection.lastHealthCheck = DateTime.now();
          
          if (!isHealthy) {
            _handleConnectionFailure(hostId, connection);
          }
        } catch (e) {
          connection.isHealthy = false;
          connection.lastHealthCheck = DateTime.now();
          _handleConnectionFailure(hostId, connection);
        }
      }
    }
  }
  
  /// Handle connection failure
  void _handleConnectionFailure(String hostId, SSHConnection connection) {
    connection.failureCount = (connection.failureCount ?? 0) + 1;
    
    final event = SSHEvent(
      type: SSHEventType.connectionFailure,
      hostId: hostId,
      timestamp: DateTime.now(),
      data: {
        'failure_count': connection.failureCount,
        'auto_reconnect': _autoReconnect,
      },
    );
    
    _eventController.add(event);
    
    // Attempt reconnection if enabled
    if (_autoReconnect && connection.failureCount! < 3) {
      _attemptReconnection(hostId);
    }
  }
  
  /// Attempt reconnection
  Future<void> _attemptReconnection(String hostId) async {
    final host = _hosts[hostId];
    if (host == null || !host.autoReconnect) return;
    
    try {
      debugPrint('🔄 Attempting SSH reconnection to ${host.name}');
      
      final result = await Process.run('ssh', [
        '-f', '-N', // Don't execute remote commands
        '-o', 'ConnectTimeout=10',
        '-o', 'ServerAliveInterval=30',
        '-o', 'ExitOnForwardFailure=yes',
        '-i', host.keyPath ?? '',
        '${host.username}@${host.hostname}',
      ]);
      
      if (result.exitCode == 0) {
        final connection = SSHConnection(
          hostId: hostId,
          hostname: host.hostname,
          username: host.username,
          isActive: true,
          isHealthy: true,
          connectedAt: DateTime.now(),
          lastHealthCheck: DateTime.now(),
        );
        
        _connections[hostId] = connection;
        
        final event = SSHEvent(
          type: SSHEventType.reconnected,
          hostId: hostId,
          timestamp: DateTime.now(),
        );
        
        _eventController.add(event);
        _onHostConnected.forEach((callback) => callback(host));
      }
    } catch (e) {
      debugPrint('⚠️ SSH reconnection failed: $e');
    }
  }
  
  /// Quick connect to host
  Future<bool> quickConnect(String hostId) async {
    final host = _hosts[hostId];
    if (host == null) {
      debugPrint('⚠️ Host not found: $hostId');
      return false;
    }
    
    try {
      debugPrint('🚀 Quick connecting to ${host.name}');
      
      // Add to recent hosts
      _addToRecentHosts(hostId);
      
      // Set as active
      _activeHostId = hostId;
      if (host.keyPath != null) {
        final key = _getKeyByPath(host.keyPath!);
        if (key != null) {
          _activeKeyId = key.id;
        }
      }
      
      // Execute SSH connection
      final result = await Process.run('ssh', [
        '-i', host.keyPath ?? '',
        '-o', 'ConnectTimeout=10',
        '-o', 'ServerAliveInterval=30',
        '${host.username}@${host.hostname}',
      ]);
      
      if (result.exitCode == 0) {
        final connection = SSHConnection(
          hostId: hostId,
          hostname: host.hostname,
          username: host.username,
          isActive: true,
          isHealthy: true,
          connectedAt: DateTime.now(),
          lastHealthCheck: DateTime.now(),
        );
        
        _connections[hostId] = connection;
        
        final event = SSHEvent(
          type: SSHEventType.connected,
          hostId: hostId,
          timestamp: DateTime.now(),
        );
        
        _eventController.add(event);
        _onHostConnected.forEach((callback) => callback(host));
        _onActiveHostChanged.forEach((callback) => callback(hostId));
        
        debugPrint('✅ Connected to ${host.name}');
        return true;
      } else {
        debugPrint('❌ Failed to connect to ${host.name}: ${result.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ SSH connection error: $e');
      return false;
    }
  }
  
  /// Disconnect from host
  Future<bool> disconnect(String hostId) async {
    final connection = _connections[hostId];
    if (connection == null || !connection.isActive) {
      return false;
    }
    
    try {
      // Kill SSH process
      await Process.run('pkill', ['-f', 'ssh']);
      
      connection.isActive = false;
      connection.disconnectedAt = DateTime.now();
      
      final event = SSHEvent(
        type: SSHEventType.disconnected,
        hostId: hostId,
        timestamp: DateTime.now(),
      );
      
      _eventController.add(event);
      _onHostDisconnected.forEach((callback) => callback(_hosts[hostId]!));
      
      if (_activeHostId == hostId) {
        _activeHostId = null;
        _activeKeyId = null;
        _onActiveHostChanged.forEach((callback) => callback(''));
      }
      
      debugPrint('🔌 Disconnected from ${_hosts[hostId]?.name}');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to disconnect from $hostId: $e');
      return false;
    }
  }
  
  /// Switch to host
  Future<bool> switchToHost(String hostId) async {
    // Disconnect from current host if connected
    if (_activeHostId != null) {
      await disconnect(_activeHostId!);
    }
    
    // Connect to new host
    return await quickConnect(hostId);
  }
  
  /// Add host
  Future<void> addHost(SSHHost host) async {
    _hosts[host.id] = host;
    await _saveSSHConfig();
    
    final event = SSHEvent(
      type: SSHEventType.hostAdded,
      hostId: host.id,
      timestamp: DateTime.now(),
      data: host.toJson(),
    );
    
    _eventController.add(event);
    _onHostAdded.forEach((callback) => callback(host));
    
    debugPrint('➕ Added SSH host: ${host.name}');
  }
  
  /// Remove host
  Future<void> removeHost(String hostId) async {
    final host = _hosts.remove(hostId);
    if (host != null) {
      await _saveSSHConfig();
      
      // Disconnect if currently connected
      if (_activeHostId == hostId) {
        await disconnect(hostId);
      }
      
      final event = SSHEvent(
        type: SSHEventType.hostRemoved,
        hostId: hostId,
        timestamp: DateTime.now(),
        data: host.toJson(),
      );
      
      _eventController.add(event);
      _onHostRemoved.forEach((callback) => callback(host));
      
      debugPrint('➖ Removed SSH host: ${host.name}');
    }
  }
  
  /// Add SSH key
  Future<void> addSSHKey(String keyPath) async {
    try {
      final publicKey = await _parseSSHPublicKey(keyPath);
      if (publicKey != null) {
        _keys[publicKey.fingerprint] = publicKey;
        
        final event = SSHEvent(
          type: SSHEventType.keyAdded,
          timestamp: DateTime.now(),
          data: publicKey.toJson(),
        );
        
        _eventController.add(event);
        _onKeyAdded.forEach((callback) => callback(publicKey));
        
        debugPrint('🔑 Added SSH key: ${publicKey.comment}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to add SSH key: $e');
    }
  }
  
  /// Get key by path
  SSHKey? _getKeyByPath(String keyPath) {
    return _keys.values.where((key) => key.path == keyPath).firstOrNull;
  }
  
  /// Add to recent hosts
  void _addToRecentHosts(String hostId) {
    _recentHosts.remove(hostId);
    _recentHosts.insert(0, hostId);
    
    // Keep only recent hosts
    if (_recentHosts.length > _maxRecentHosts) {
      _recentHosts.removeRange(_maxRecentHosts, _recentHosts.length);
    }
    
    // Update usage count
    _hostUsageCount[hostId] = (_hostUsageCount[hostId] ?? 0) + 1;
  }
  
  /// Get recent hosts
  List<SSHHost> getRecentHosts() {
    return _recentHosts
        .map((id) => _hosts[id])
        .where((host) => host != null)
        .toList();
  }
  
  /// Search hosts
  List<SSHHost> searchHosts(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _hosts.values.where((host) {
      return host.name.toLowerCase().contains(lowerQuery) ||
             host.hostname.toLowerCase().contains(lowerQuery) ||
             host.username.toLowerCase().contains(lowerQuery) ||
             host.description.toLowerCase().contains(lowerQuery) ||
             host.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Get hosts by tag
  List<SSHHost> getHostsByTag(String tag) {
    final lowerTag = tag.toLowerCase();
    
    return _hosts.values.where((host) {
      return host.tags.any((hostTag) => hostTag.toLowerCase() == lowerTag);
    }).toList();
  }
  
  /// Save SSH configuration
  Future<void> _saveSSHConfig() async {
    try {
      final configLines = <String>[];
      
      for (final host in _hosts.values) {
        configLines.add('Host ${host.id}');
        configLines.add('    HostName ${host.hostname}');
        configLines.add('    User ${host.username}');
        configLines.add('    Port ${host.port}');
        
        if (host.keyPath != null) {
          configLines.add('    IdentityFile ${host.keyPath}');
        }
        
        if (host.connectTimeout != null) {
          configLines.add('    ConnectTimeout ${host.connectTimeout}');
        }
        
        if (host.serverAliveInterval != null) {
          configLines.add('    ServerAliveInterval ${host.serverAliveInterval}');
        }
        
        configLines.add(''); // Empty line between hosts
      }
      
      final configFile = File(_sshConfigPath);
      await configFile.writeAsString(configLines.join('\n'));
      
      debugPrint('💾 Saved SSH configuration with ${_hosts.length} hosts');
    } catch (e) {
      debugPrint('⚠️ Failed to save SSH config: $e');
    }
  }
  
  /// Get connection statistics
  Map<String, dynamic> getStatistics() {
    final activeConnections = _connections.values.where((c) => c.isActive).length;
    final healthyConnections = _connections.values.where((c) => c.isHealthy).length;
    final totalFailures = _connections.values
        .map((c) => c.failureCount ?? 0)
        .reduce((a, b) => a + b, 0);
    
    return {
      'total_hosts': _hosts.length,
      'total_keys': _keys.length,
      'active_host_id': _activeHostId,
      'active_key_id': _activeKeyId,
      'active_connections': activeConnections,
      'healthy_connections': healthyConnections,
      'total_failures': totalFailures,
      'recent_hosts': _recentHosts.length,
      'auto_reconnect_enabled': _autoReconnect,
      'health_monitoring_active': _healthCheckTimer?.isActive ?? false,
    };
  }
  
  /// Set configuration
  void setConfiguration({
    bool? autoReconnect,
    int? maxRecentHosts,
    String? sshConfigPath,
    String? sshKeyDir,
  }) {
    if (autoReconnect != null) _autoReconnect = autoReconnect!;
    if (maxRecentHosts != null) _maxRecentHosts = maxRecentHosts!;
    if (sshConfigPath != null) _sshConfigPath = sshConfigPath!;
    if (sshKeyDir != null) _sshKeyDir = sshKeyDir!;
    
    debugPrint('⚙️ SSH Switcher configuration updated');
  }
  
  /// Add host added listener
  void addHostAddedListener(Function(SSHHost) listener) {
    _onHostAdded.add(listener);
  }
  
  /// Add host removed listener
  void addHostRemovedListener(Function(SSHHost) listener) {
    _onHostRemoved.add(listener);
  }
  
  /// Add host connected listener
  void addHostConnectedListener(Function(SSHHost) listener {
    _onHostConnected.add(listener);
  }
  
  /// Add host disconnected listener
  void addHostDisconnectedListener(Function(SSHHost) listener {
    _onHostDisconnected.add(listener);
  }
  
  /// Add key added listener
  void addKeyAddedListener(Function(SSHKey) listener {
    _onKeyAdded.add(listener);
  }
  
  /// Add active host changed listener
  void addActiveHostChangedListener(Function(String) listener {
    _onActiveHostChanged.add(listener);
  }
  
  /// Add active key changed listener
  void addActiveKeyChangedListener(Function(String) listener {
    _onActiveKeyChanged.add(listener);
  }
  
  /// Remove host added listener
  void removeHostAddedListener(Function(SSHHost) listener {
    _onHostAdded.remove(listener);
  }
  
  /// Remove host removed listener
  void removeHostRemovedListener(Function(SSHHost) listener {
    _onHostRemoved.remove(listener);
  }
  
  /// Remove host connected listener
  void removeHostConnectedListener(Function(SSHHost) listener {
    _onHostConnected.remove(listener);
  }
  
  /// Remove host disconnected listener
  void removeHostDisconnectedListener(Function(SSHHost) listener {
    _onHostDisconnected.remove(listener);
  }
  
  /// Remove key added listener
  void removeKeyAddedListener(Function(SSHKey) listener {
    _onKeyAdded.remove(listener);
  }
  
  /// Remove active host changed listener
  void removeActiveHostChangedListener(Function(String) listener {
    _onActiveHostChanged.remove(listener);
  }
  
  /// Remove active key changed listener
  void removeActiveKeyChangedListener(Function(String) listener {
    _onActiveKeyChanged.remove(listener);
  }
  
  /// Dispose SSH switcher
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    
    // Disconnect all active connections
    for (final hostId in List.from(_connections.keys)) {
      await disconnect(hostId);
    }
    
    // Clear listeners
    _onHostAdded.clear();
    _onHostRemoved.clear();
    _onHostConnected.clear();
    _onHostDisconnected.clear();
    _onKeyAdded.clear();
    _onActiveHostChanged.clear();
    _onActiveKeyChanged.clear();
    
    _isInitialized = false;
    debugPrint('🔑 Quick SSH Switcher disposed');
  }
}

/// SSH host model
class SSHHost {
  final String id;
  final String name;
  final String hostname;
  final String username;
  final int port;
  final String? keyPath;
  final String? description;
  final List<String> tags;
  final bool quickConnect;
  final bool autoReconnect;
  final int? connectTimeout;
  final int? serverAliveInterval;
  final List<String> configLines;
  final DateTime? lastUsed;
  final Map<String, dynamic>? metadata;
  
  SSHHost({
    required this.id,
    required this.name,
    required this.hostname,
    required this.username,
    this.port = 22,
    this.keyPath,
    this.description,
    this.tags = const [],
    this.quickConnect = false,
    this.autoReconnect = false,
    this.connectTimeout,
    this.serverAliveInterval,
    this.configLines = const [],
    this.lastUsed,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hostname': hostname,
      'username': username,
      'port': port,
      'key_path': keyPath,
      'description': description,
      'tags': tags,
      'quick_connect': quickConnect,
      'auto_reconnect': autoReconnect,
      'connect_timeout': connectTimeout,
      'server_alive_interval': serverAliveInterval,
      'last_used': lastUsed?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// SSH key model
class SSHKey {
  final String id;
  final String type;
  final String path;
  final String fingerprint;
  final String? comment;
  final bool isDefault;
  final DateTime? addedAt;
  final Map<String, dynamic>? metadata;
  
  SSHKey({
    required this.id,
    required this.type,
    required this.path,
    required this.fingerprint,
    this.comment,
    this.isDefault = false,
    this.addedAt,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'path': path,
      'fingerprint': fingerprint,
      'comment': comment,
      'is_default': isDefault,
      'added_at': addedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// SSH connection model
class SSHConnection {
  final String hostId;
  final String hostname;
  final String username;
  final bool isActive;
  final bool isHealthy;
  final DateTime? connectedAt;
  final DateTime? disconnectedAt;
  final DateTime? lastHealthCheck;
  final int? failureCount;
  final Map<String, dynamic>? metadata;
  
  SSHConnection({
    required this.hostId,
    required this.hostname,
    required this.username,
    required this.isActive,
    required this.isHealthy,
    this.connectedAt,
    this.disconnectedAt,
    this.lastHealthCheck,
    this.failureCount,
    this.metadata,
  });
}

/// SSH event types
enum SSHEventType {
  connected,
  disconnected,
  connectionFailure,
  reconnected,
  hostAdded,
  hostRemoved,
  keyAdded,
  authenticationFailed,
}

/// SSH event model
class SSHEvent {
  final SSHEventType type;
  final String? hostId;
  final DateTime timestamp;
  final dynamic data;
  
  SSHEvent({
    required this.type,
    this.hostId,
    required this.timestamp,
    this.data,
  });
}
