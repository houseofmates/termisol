import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Session synchronization system across platforms
/// 
/// Features:
/// - Cross-platform session synchronization (Linux, Android, VR)
/// - Real-time session state sharing
/// - Conflict resolution and merging
/// - Offline support with sync on reconnect
/// - Global backend for centralized storage
class SessionSynchronizationSystem {
  static const String _baseUrl = 'https://termisol-sync.houseofmates.com';
  static const String _wsUrl = 'wss://termisol-sync.houseofmates.com/ws';
  static const Duration _syncInterval = Duration(seconds: 5);
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const int _maxRetries = 5;
  
  final Map<String, SessionData> _localSessions = {};
  final Map<String, SessionData> _remoteSessions = {};
  final Map<String, ConflictResolver> _conflictResolvers = {};
  final List<SyncEvent> _eventLog = [];
  
  WebSocketChannel? _wsChannel;
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  
  bool _isConnected = false;
  bool _isSyncing = false;
  int _retryCount = 0;
  String? _deviceId;
  PlatformType? _platformType;
  
  /// Sync callbacks
  final List<Function(SyncEvent)> _syncCallbacks = [];
  
  /// Performance metrics
  int _syncCount = 0;
  int _conflictCount = 0;
  int _mergeCount = 0;
  double _totalSyncTime = 0.0;
  int _totalBytesTransferred = 0;

  SessionSynchronizationSystem() {
    _initializeSynchronization();
  }

  /// Initialize synchronization system
  Future<void> _initializeSynchronization() async {
    // Get device ID and platform type
    _deviceId = await _getDeviceId();
    _platformType = await _getPlatformType();
    
    // Setup conflict resolvers
    _setupConflictResolvers();
    
    // Connect to sync server
    await _connectToServer();
    
    // Start sync timer
    _syncTimer = Timer.periodic(_syncInterval, (_) => _performSync());
    
    // Start heartbeat
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (_) => _sendHeartbeat());
  }

  /// Get unique device ID
  Future<String> _getDeviceId() async {
    // Generate unique device ID based on platform info
    final platform = Platform.operatingSystem;
    final hostname = Platform.localHostname;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    return '$platform-$hostname-$timestamp';
  }

  /// Get platform type
  Future<PlatformType> _getPlatformType() async {
    if (Platform.isAndroid) return PlatformType.android;
    if (Platform.isLinux) return PlatformType.linux;
    if (Platform.isWindows) return PlatformType.windows;
    if (Platform.isMacOS) return PlatformType.macos;
    if (Platform.isIOS) return PlatformType.ios;
    
    // Check for VR environment
    if (await _isVREnvironment()) {
      return PlatformType.vr;
    }
    
    return PlatformType.unknown;
  }

  /// Check if running in VR environment
  Future<bool> _isVREnvironment() async {
    try {
      // Check for VR-specific environment variables or files
      final vrIndicators = [
        'OCULUS_RUNTIME',
        'OPENVR_RUNTIME',
        '/usr/lib/oculus',
        '/var/lib/oculus',
      ];
      
      for (final indicator in vrIndicators) {
        if (Platform.environment.containsKey(indicator) || 
            await File(indicator).exists()) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Setup conflict resolvers
  void _setupConflictResolvers() {
    _conflictResolvers['terminal_content'] = TerminalContentResolver();
    _conflictResolvers['session_state'] = SessionStateResolver();
    _conflictResolvers['user_preferences'] = UserPreferencesResolver();
  }

  /// Connect to sync server
  Future<void> _connectToServer() async {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse('$_wsUrl?deviceId=$_deviceId&platform=$_platformType'));
      
      _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketDone,
      );
      
      _isConnected = true;
      _retryCount = 0;
      
      _logEvent(SyncEvent.connected(_deviceId!, _platformType!));
    } catch (e) {
      debugPrint('Failed to connect to sync server: $e');
      _handleWebSocketError(e);
    }
  }

  /// Handle WebSocket message
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);
      final type = data['type'] as String;
      
      switch (type) {
        case 'sync_response':
          _handleSyncResponse(data);
          break;
        case 'session_update':
          _handleSessionUpdate(data);
          break;
        case 'conflict_detected':
          _handleConflictDetected(data);
          break;
        case 'heartbeat':
          // Handle heartbeat response
          break;
      }
    } catch (e) {
      debugPrint('Failed to handle WebSocket message: $e');
    }
  }

  /// Handle WebSocket error
  void _handleWebSocketError(dynamic error) {
    _isConnected = false;
    _logEvent(SyncEvent.error(error.toString()));
    
    // Attempt reconnection
    if (_retryCount < _maxRetries) {
      _retryCount++;
      Future.delayed(_reconnectDelay * _retryCount, () {
        _connectToServer();
      });
    }
  }

  /// Handle WebSocket connection done
  void _handleWebSocketDone() {
    _isConnected = false;
    _logEvent(SyncEvent.disconnected());
    
    // Attempt reconnection
    _handleWebSocketError('Connection closed');
  }

  /// Handle sync response
  void _handleSyncResponse(Map<String, dynamic> data) {
    final sessions = data['sessions'] as List?;
    if (sessions != null) {
      for (final sessionData in sessions) {
        final session = SessionData.fromJson(sessionData);
        _remoteSessions[session.id] = session;
      }
    }
  }

  /// Handle session update
  void _handleSessionUpdate(Map<String, dynamic> data) {
    final session = SessionData.fromJson(data['session']);
    _remoteSessions[session.id] = session;
    
    _notifySyncCallbacks(SyncEvent.sessionUpdated(session.id));
  }

  /// Handle conflict detected
  void _handleConflictDetected(Map<String, dynamic> data) {
    final conflict = ConflictData.fromJson(data);
    _conflictCount++;
    
    // Resolve conflict
    _resolveConflict(conflict);
  }

  /// Resolve conflict
  Future<void> _resolveConflict(ConflictData conflict) async {
    final resolver = _conflictResolvers[conflict.type];
    if (resolver != null) {
      try {
        final mergedData = await resolver.resolve(conflict.localData, conflict.remoteData);
        _mergeCount++;
        
        // Send merged data back to server
        await _sendMergedData(conflict.sessionId, mergedData);
        
        _logEvent(SyncEvent.conflictResolved(conflict.sessionId));
      } catch (e) {
        debugPrint('Failed to resolve conflict: $e');
      }
    }
  }

  /// Send merged data to server
  Future<void> _sendMergedData(String sessionId, Map<String, dynamic> mergedData) async {
    if (!_isConnected) return;
    
    try {
      final message = {
        'type': 'merge_data',
        'sessionId': sessionId,
        'deviceId': _deviceId,
        'data': mergedData,
      };
      
      _wsChannel!.sink.add(json.encode(message));
    } catch (e) {
      debugPrint('Failed to send merged data: $e');
    }
  }

  /// Perform synchronization
  Future<void> _performSync() async {
    if (_isSyncing || !_isConnected) return;
    
    _isSyncing = true;
    final stopwatch = Stopwatch()..start();
    
    try {
      _syncCount++;
      
      // Prepare local sessions for sync
      final localSessionsData = _localSessions.values.map((s) => s.toJson()).toList();
      
      // Send sync request
      final message = {
        'type': 'sync_request',
        'deviceId': _deviceId,
        'platform': _platformType.toString(),
        'sessions': localSessionsData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final messageBytes = utf8.encode(json.encode(message));
      _totalBytesTransferred += messageBytes.length;
      
      _wsChannel!.sink.add(json.encode(message));
      
      _totalSyncTime += stopwatch.elapsedMilliseconds.toDouble();
      
      _logEvent(SyncEvent.syncCompleted(localSessionsData.length));
    } catch (e) {
      debugPrint('Sync failed: $e');
      _logEvent(SyncEvent.error(e.toString()));
    } finally {
      _isSyncing = false;
      stopwatch.stop();
    }
  }

  /// Send heartbeat
  void _sendHeartbeat() {
    if (!_isConnected) return;
    
    try {
      final message = {
        'type': 'heartbeat',
        'deviceId': _deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _wsChannel!.sink.add(json.encode(message));
    } catch (e) {
      debugPrint('Failed to send heartbeat: $e');
    }
  }

  /// Add local session
  void addLocalSession(SessionData session) {
    _localSessions[session.id] = session;
    _logEvent(SyncEvent.sessionAdded(session.id));
  }

  /// Update local session
  void updateLocalSession(SessionData session) {
    _localSessions[session.id] = session;
    _logEvent(SyncEvent.sessionUpdated(session.id));
  }

  /// Remove local session
  void removeLocalSession(String sessionId) {
    _localSessions.remove(sessionId);
    _logEvent(SyncEvent.sessionRemoved(sessionId));
  }

  /// Get merged sessions (local + remote)
  Map<String, SessionData> getAllSessions() {
    final allSessions = <String, SessionData>{};
    allSessions.addAll(_localSessions);
    allSessions.addAll(_remoteSessions);
    return allSessions;
  }

  /// Get session by ID
  SessionData? getSession(String sessionId) {
    return getAllSessions()[sessionId];
  }

  /// Get sessions by platform
  List<SessionData> getSessionsByPlatform(PlatformType platform) {
    return getAllSessions().values
        .where((session) => session.platform == platform)
        .toList();
  }

  /// Notify sync callbacks
  void _notifySyncCallbacks(SyncEvent event) {
    for (final callback in _syncCallbacks) {
      try {
        callback(event);
      } catch (e) {
        debugPrint('Error in sync callback: $e');
      }
    }
  }

  /// Add sync callback
  void addSyncCallback(Function(SyncEvent) callback) {
    _syncCallbacks.add(callback);
  }

  /// Remove sync callback
  void removeSyncCallback(Function(SyncEvent) callback) {
    _syncCallbacks.remove(callback);
  }

  /// Log sync event
  void _logEvent(SyncEvent event) {
    _eventLog.add(event);
    
    // Keep only recent events
    if (_eventLog.length > 1000) {
      _eventLog.removeRange(0, _eventLog.length - 1000);
    }
  }

  /// Get synchronization statistics
  SyncStats getStats() {
    return SyncStats(
      isConnected: _isConnected,
      deviceId: _deviceId ?? '',
      platformType: _platformType ?? PlatformType.unknown,
      localSessions: _localSessions.length,
      remoteSessions: _remoteSessions.length,
      totalSessions: _localSessions.length + _remoteSessions.length,
      syncCount: _syncCount,
      conflictCount: _conflictCount,
      mergeCount: _mergeCount,
      averageSyncTime: _syncCount > 0 ? _totalSyncTime / _syncCount : 0.0,
      totalBytesTransferred: _totalBytesTransferred,
      retryCount: _retryCount,
      eventLogSize: _eventLog.length,
    );
  }

  /// Force synchronization
  Future<void> forceSync() async {
    await _performSync();
  }

  /// Clear all sessions
  void clearSessions() {
    _localSessions.clear();
    _remoteSessions.clear();
    _logEvent(SyncEvent.cleared());
  }

  /// Dispose synchronization system
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _heartbeatTimer?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    
    clearSessions();
    _syncCallbacks.clear();
    _conflictResolvers.clear();
  }
}

/// Session data model
class SessionData {
  final String id;
  final String name;
  final PlatformType platform;
  final String deviceId;
  final Map<String, dynamic> state;
  final DateTime timestamp;
  final DateTime lastModified;

  const SessionData({
    required this.id,
    required this.name,
    required this.platform,
    required this.deviceId,
    required this.state,
    required this.timestamp,
    required this.lastModified,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: PlatformType.values.firstWhere(
        (p) => p.toString() == json['platform'],
        orElse: () => PlatformType.unknown,
      ),
      deviceId: json['deviceId'] as String,
      state: json['state'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      lastModified: DateTime.parse(json['lastModified'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platform': platform.toString(),
      'deviceId': deviceId,
      'state': state,
      'timestamp': timestamp.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
    };
  }
}

/// Conflict data model
class ConflictData {
  final String sessionId;
  final String type;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime timestamp;

  const ConflictData({
    required this.sessionId,
    required this.type,
    required this.localData,
    required this.remoteData,
    required this.timestamp,
  });

  factory ConflictData.fromJson(Map<String, dynamic> json) {
    return ConflictData(
      sessionId: json['sessionId'] as String,
      type: json['type'] as String,
      localData: json['localData'] as Map<String, dynamic>,
      remoteData: json['remoteData'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Conflict resolver interface
abstract class ConflictResolver {
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> localData, Map<String, dynamic> remoteData);
}

/// Terminal content conflict resolver
class TerminalContentResolver implements ConflictResolver {
  @override
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> localData, Map<String, dynamic> remoteData) async {
    // Merge terminal content by appending remote content to local content
    final localContent = localData['content'] as String? ?? '';
    final remoteContent = remoteData['content'] as String? ?? '';
    
    // Simple merge strategy: append remote content if it's different
    String mergedContent = localContent;
    if (remoteContent.isNotEmpty && !localContent.contains(remoteContent)) {
      mergedContent = '$localContent\n$remoteContent';
    }
    
    return {
      'content': mergedContent,
      'merged_at': DateTime.now().toIso8601String(),
      'merge_strategy': 'append',
    };
  }
}

/// Session state conflict resolver
class SessionStateResolver implements ConflictResolver {
  @override
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> localData, Map<String, dynamic> remoteData) async {
    // Merge session state by taking the most recent values
    final mergedState = <String, dynamic>{};
    
    // Add all local state
    mergedState.addAll(localData);
    
    // Override with remote state if it's newer
    final localTimestamp = DateTime.tryParse(localData['lastModified'] as String? ?? '');
    final remoteTimestamp = DateTime.tryParse(remoteData['lastModified'] as String? ?? '');
    
    if (remoteTimestamp != null && (localTimestamp == null || remoteTimestamp.isAfter(localTimestamp))) {
      mergedState.addAll(remoteData);
    }
    
    return mergedState;
  }
}

/// User preferences conflict resolver
class UserPreferencesResolver implements ConflictResolver {
  @override
  Future<Map<String, dynamic>> resolve(Map<String, dynamic> localData, Map<String, dynamic> remoteData) async {
    // Merge user preferences by combining both sets
    final mergedPreferences = <String, dynamic>{};
    
    // Add all local preferences
    mergedPreferences.addAll(localData);
    
    // Add remote preferences that don't exist locally
    for (final entry in remoteData.entries) {
      if (!localData.containsKey(entry.key)) {
        mergedPreferences[entry.key] = entry.value;
      }
    }
    
    return mergedPreferences;
  }
}

/// Platform types
enum PlatformType {
  linux,
  android,
  windows,
  macos,
  ios,
  vr,
  unknown,
}

/// Sync events
class SyncEvent {
  final SyncEventType type;
  final String? data;
  final DateTime timestamp;

  const SyncEvent(this.type, this.data) : timestamp = DateTime.now();

  factory SyncEvent.connected(String deviceId) => SyncEvent(SyncEventType.connected, deviceId);
  factory SyncEvent.disconnected() => const SyncEvent(SyncEventType.disconnected, null);
  factory SyncEvent.error(String error) => SyncEvent(SyncEventType.error, error);
  factory SyncEvent.syncCompleted(int sessionCount) => SyncEvent(SyncEventType.syncCompleted, sessionCount.toString());
  factory SyncEvent.sessionAdded(String sessionId) => SyncEvent(SyncEventType.sessionAdded, sessionId);
  factory SyncEvent.sessionUpdated(String sessionId) => SyncEvent(SyncEventType.sessionUpdated, sessionId);
  factory SyncEvent.sessionRemoved(String sessionId) => SyncEvent(SyncEventType.sessionRemoved, sessionId);
  factory SyncEvent.conflictResolved(String sessionId) => SyncEvent(SyncEventType.conflictResolved, sessionId);
  factory SyncEvent.cleared() => const SyncEvent(SyncEventType.cleared, null);
}

enum SyncEventType {
  connected,
  disconnected,
  error,
  syncCompleted,
  sessionAdded,
  sessionUpdated,
  sessionRemoved,
  conflictResolved,
  cleared,
}

/// Synchronization statistics
class SyncStats {
  final bool isConnected;
  final String deviceId;
  final PlatformType platformType;
  final int localSessions;
  final int remoteSessions;
  final int totalSessions;
  final int syncCount;
  final int conflictCount;
  final int mergeCount;
  final double averageSyncTime;
  final int totalBytesTransferred;
  final int retryCount;
  final int eventLogSize;

  const SyncStats({
    required this.isConnected,
    required this.deviceId,
    required this.platformType,
    required this.localSessions,
    required this.remoteSessions,
    required this.totalSessions,
    required this.syncCount,
    required this.conflictCount,
    required this.mergeCount,
    required this.averageSyncTime,
    required this.totalBytesTransferred,
    required this.retryCount,
    required this.eventLogSize,
  });
}
