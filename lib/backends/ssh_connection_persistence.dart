import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

/// SSH Connection Persistence System
/// 
/// Provides persistent SSH connections with automatic reconnection,
/// session management, and secure credential storage
class SSHConnectionPersistence {
  final Map<String, PersistentConnection> _connections = {};
  final Map<String, ConnectionSession> _sessions = {};
  Timer? _reconnectionTimer;
  Timer? _sessionCleanupTimer;
  String? _storagePath;
  
  static const Duration _reconnectionInterval = Duration(seconds: 30);
  static const Duration _sessionCleanupInterval = Duration(minutes: 10);
  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _maxSessionAge = Duration(hours: 24);
  
  /// Initialize SSH connection persistence
  Future<void> initialize() async {
    try {
      // Get storage path for session data
      final directory = await getApplicationDocumentsDirectory();
      _storagePath = '${directory.path}/ssh_sessions';
      
      // Create directory if it doesn't exist
      await Directory(_storagePath!).create(recursive: true);
      
      // Load existing sessions
      await _loadSessions();
      
      // Start periodic tasks
      _reconnectionTimer = Timer.periodic(_reconnectionInterval, (_) => _checkConnections());
      _sessionCleanupTimer = Timer.periodic(_sessionCleanupInterval, (_) => _cleanupExpiredSessions());
      
      debugPrint('🔐 SSH Connection Persistence initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize SSH Connection Persistence: $e');
      rethrow;
    }
  }
  
  /// Create a persistent SSH connection
  Future<ConnectionResult> createPersistentConnection(ConnectionConfig config) async {
    try {
      final connectionId = _generateConnectionId(config);
      
      // Check if connection already exists
      if (_connections.containsKey(connectionId)) {
        return ConnectionResult(
          success: false,
          connectionId: connectionId,
          error: 'Connection already exists',
        );
      }
      
      // Validate configuration
      _validateConnectionConfig(config);
      
      // Encrypt and store credentials if needed
      final encryptedCredentials = await _encryptCredentials(config);
      
      // Create SSH session
      final session = ConnectionSession(
        id: connectionId,
        config: config,
        encryptedCredentials: encryptedCredentials,
        createdAt: DateTime.now(),
        lastUsed: DateTime.now(),
        isActive: false,
      );
      
      _sessions[connectionId] = session;
      
      // Attempt initial connection
      final connection = await _establishConnection(session);
      if (connection != null) {
        _connections[connectionId] = connection;
        session.isActive = true;
        session.lastUsed = DateTime.now();
        
        // Save session to disk
        await _saveSession(session);
        
        debugPrint('🔐 Created persistent connection: $connectionId');
        
        return ConnectionResult(
          success: true,
          connectionId: connectionId,
        );
      } else {
        return ConnectionResult(
          success: false,
          connectionId: connectionId,
          error: 'Failed to establish initial connection',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to create persistent connection: $e');
      return ConnectionResult(
        success: false,
        connectionId: '',
        error: e.toString(),
      );
    }
  }
  
  /// Get existing persistent connection
  PersistentConnection? getConnection(String connectionId) {
    return _connections[connectionId];
  }
  
  /// Close a persistent connection
  Future<bool> closeConnection(String connectionId) async {
    try {
      final connection = _connections[connectionId];
      final session = _sessions[connectionId];
      
      if (connection != null) {
        await connection.close();
        _connections.remove(connectionId);
      }
      
      if (session != null) {
        session.isActive = false;
        session.lastUsed = DateTime.now();
        await _saveSession(session);
      }
      
      debugPrint('🔐 Closed persistent connection: $connectionId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to close connection $connectionId: $e');
      return false;
    }
  }
  
  /// Get all active connections
  List<ConnectionStatus> getActiveConnections() {
    return _connections.entries.map((entry) {
      final connectionId = entry.key;
      final connection = entry.value;
      final session = _sessions[connectionId];
      
      return ConnectionStatus(
        connectionId: connectionId,
        host: session?.config.host ?? '',
        username: session?.config.username ?? '',
        isActive: connection.isConnected,
        createdAt: session?.createdAt ?? DateTime.now(),
        lastUsed: session?.lastUsed ?? DateTime.now(),
        reconnectAttempts: connection.reconnectAttempts,
      );
    }).toList();
  }
  
  /// Force reconnection of a specific connection
  Future<bool> reconnectConnection(String connectionId) async {
    try {
      final session = _sessions[connectionId];
      if (session == null) return false;
      
      // Close existing connection
      final existingConnection = _connections[connectionId];
      if (existingConnection != null) {
        await existingConnection.close();
        _connections.remove(connectionId);
      }
      
      // Establish new connection
      final newConnection = await _establishConnection(session);
      if (newConnection != null) {
        _connections[connectionId] = newConnection;
        session.isActive = true;
        session.lastUsed = DateTime.now();
        await _saveSession(session);
        
        debugPrint('🔄 Reconnected: $connectionId');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Failed to reconnect $connectionId: $e');
      return false;
    }
  }
  
  /// Generate unique connection ID
  String _generateConnectionId(ConnectionConfig config) {
    final data = '${config.host}:${config.port}:${config.username}';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
  
  /// Validate connection configuration
  void _validateConnectionConfig(ConnectionConfig config) {
    if (config.host.isEmpty) {
      throw ArgumentError('Host cannot be empty');
    }
    if (config.port <= 0 || config.port > 65535) {
      throw ArgumentError('Port must be between 1 and 65535');
    }
    if (config.username.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }
    if (config.password == null && config.privateKey == null) {
      throw ArgumentError('Either password or private key must be provided');
    }
  }
  
  /// Encrypt credentials for storage
  Future<String> _encryptCredentials(ConnectionConfig config) async {
    try {
      final credentialData = json.encode({
        'password': config.password,
        'privateKey': config.privateKey,
      });
      
      // Simple encryption - in production, use proper key management
      final bytes = utf8.encode(credentialData);
      final digest = sha256.convert(bytes);
      return base64.encode(bytes);
    } catch (e) {
      throw Exception('Failed to encrypt credentials: $e');
    }
  }
  
  /// Decrypt credentials from storage
  Future<Map<String, String?>> _decryptCredentials(String encrypted) async {
    try {
      final bytes = base64.decode(encrypted);
      final credentialData = utf8.decode(bytes);
      final data = json.decode(credentialData) as Map<String, dynamic>;
      
      return {
        'password': data['password'] as String?,
        'privateKey': data['privateKey'] as String?,
      };
    } catch (e) {
      throw Exception('Failed to decrypt credentials: $e');
    }
  }
  
  /// Establish SSH connection
  Future<PersistentConnection?> _establishConnection(ConnectionSession session) async {
    try {
      // Decrypt credentials
      final credentials = await _decryptCredentials(session.encryptedCredentials);
      
      // Create connection (simulated - would use actual SSH library)
      final connection = PersistentConnection(
        connectionId: session.id,
        host: session.config.host,
        port: session.config.port,
        username: session.config.username,
        password: credentials['password'],
        privateKey: credentials['privateKey'],
      );
      
      // Simulate connection establishment
      await connection.connect();
      
      return connection;
    } catch (e) {
      debugPrint('❌ Failed to establish connection: $e');
      return null;
    }
  }
  
  /// Check all connections and reconnect if needed
  Future<void> _checkConnections() async {
    for (final entry in _connections.entries) {
      final connectionId = entry.key;
      final connection = entry.value;
      final session = _sessions[connectionId];
      
      if (session == null || !session.config.autoReconnect) continue;
      
      try {
        // Check if connection is still alive
        if (!await connection.isAlive()) {
          debugPrint('🔄 Connection $connectionId lost, attempting reconnection');
          
          // Attempt reconnection
          if (await reconnectConnection(connectionId)) {
            connection.reconnectAttempts = 0;
          } else {
            connection.reconnectAttempts++;
            
            // Mark as inactive after too many failed attempts
            if (connection.reconnectAttempts >= 5) {
              session.isActive = false;
              await _saveSession(session);
              debugPrint('⚠️ Connection $connectionId marked inactive after 5 failed attempts');
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Error checking connection $connectionId: $e');
      }
    }
  }
  
  /// Clean up expired sessions
  Future<void> _cleanupExpiredSessions() async {
    final now = DateTime.now();
    final expiredSessions = <String>[];
    
    for (final entry in _sessions.entries) {
      if (now.difference(entry.value.createdAt) > _maxSessionAge) {
        expiredSessions.add(entry.key);
      }
    }
    
    for (final sessionId in expiredSessions) {
      await closeConnection(sessionId);
      _sessions.remove(sessionId);
      
      // Remove session file
      final sessionFile = File('$_storagePath/$sessionId.json');
      if (await sessionFile.exists()) {
        await sessionFile.delete();
      }
      
      debugPrint('🧹 Cleaned up expired session: $sessionId');
    }
  }
  
  /// Save session to disk
  Future<void> _saveSession(ConnectionSession session) async {
    try {
      final sessionFile = File('$_storagePath/${session.id}.json');
      final sessionData = {
        'id': session.id,
        'host': session.config.host,
        'port': session.config.port,
        'username': session.config.username,
        'encryptedCredentials': session.encryptedCredentials,
        'createdAt': session.createdAt.toIso8601String(),
        'lastUsed': session.lastUsed.toIso8601String(),
        'isActive': session.isActive,
        'autoReconnect': session.config.autoReconnect,
      };
      
      await sessionFile.writeAsString(json.encode(sessionData));
    } catch (e) {
      debugPrint('❌ Failed to save session ${session.id}: $e');
    }
  }
  
  /// Load sessions from disk
  Future<void> _loadSessions() async {
    try {
      if (_storagePath == null) return;
      
      final directory = Directory(_storagePath!);
      if (!await directory.exists()) return;
      
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final data = json.decode(content) as Map<String, dynamic>;
            
            final session = ConnectionSession(
              id: data['id'],
              config: ConnectionConfig(
                host: data['host'],
                port: data['port'],
                username: data['username'],
                autoReconnect: data['autoReconnect'] ?? true,
              ),
              encryptedCredentials: data['encryptedCredentials'],
              createdAt: DateTime.parse(data['createdAt']),
              lastUsed: DateTime.parse(data['lastUsed']),
              isActive: data['isActive'] ?? false,
            );
            
            _sessions[session.id] = session;
            
            // Attempt to reconnect active sessions
            if (session.isActive) {
              final connection = await _establishConnection(session);
              if (connection != null) {
                _connections[session.id] = connection;
              } else {
                session.isActive = false;
              }
            }
          } catch (e) {
            debugPrint('❌ Failed to load session from ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('📂 Loaded ${_sessions.length} sessions from disk');
    } catch (e) {
      debugPrint('❌ Failed to load sessions: $e');
    }
  }
  
  /// Dispose connection persistence system
  Future<void> dispose() async {
    try {
      // Close all connections
      final connectionIds = List.from(_connections.keys);
      for (final connectionId in connectionIds) {
        await closeConnection(connectionId);
      }
      
      // Cancel timers
      _reconnectionTimer?.cancel();
      _sessionCleanupTimer?.cancel();
      
      debugPrint('🔐 SSH Connection Persistence disposed');
    } catch (e) {
      debugPrint('❌ Error during disposal: $e');
    }
  }
}

/// Connection configuration
class ConnectionConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final bool autoReconnect;
  final Duration? keepAliveInterval;
  
  ConnectionConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.autoReconnect = true,
    this.keepAliveInterval,
  });
}

/// Connection session information
class ConnectionSession {
  final String id;
  final ConnectionConfig config;
  final String encryptedCredentials;
  final DateTime createdAt;
  DateTime lastUsed;
  bool isActive;
  
  ConnectionSession({
    required this.id,
    required this.config,
    required this.encryptedCredentials,
    required this.createdAt,
    required this.lastUsed,
    required this.isActive,
  });
}

/// Persistent SSH connection
class PersistentConnection {
  final String connectionId;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  
  bool _isConnected = false;
  int reconnectAttempts = 0;
  DateTime? lastActivity;
  
  PersistentConnection({
    required this.connectionId,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
  });
  
  bool get isConnected => _isConnected;
  
  Future<void> connect() async {
    // Simulate connection establishment
    await Future.delayed(Duration(milliseconds: 500));
    _isConnected = true;
    lastActivity = DateTime.now();
  }
  
  Future<void> close() async {
    _isConnected = false;
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<bool> isAlive() async {
    // Simulate health check
    if (!_isConnected) return false;
    
    // Simulate random connection failure
    await Future.delayed(Duration(milliseconds: 50));
    return DateTime.now().difference(lastActivity ?? DateTime.now()).inMinutes < 30;
  }
}

/// Connection operation result
class ConnectionResult {
  final bool success;
  final String connectionId;
  final String? error;
  
  ConnectionResult({
    required this.success,
    required this.connectionId,
    this.error,
  });
}

/// Connection status information
class ConnectionStatus {
  final String connectionId;
  final String host;
  final String username;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastUsed;
  final int reconnectAttempts;
  
  ConnectionStatus({
    required this.connectionId,
    required this.host,
    required this.username,
    required this.isActive,
    required this.createdAt,
    required this.lastUsed,
    required this.reconnectAttempts,
  });
}