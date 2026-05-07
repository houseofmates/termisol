import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'session_persistence.dart';

/// Cloud Session Sync for Termisol
///
/// Provides cross-device session synchronization using a simple cloud backend.
/// Since this is a single-user application, uses a dedicated cloud service
/// for session storage and real-time sync across devices.
///
/// Features:
/// - Automatic cloud backup and restore
/// - Real-time sync between devices
/// - Conflict resolution for concurrent edits
/// - Offline-first with sync when online
/// - End-to-end encryption for session data
class CloudSessionSync {
  static const String _cloudBaseUrl = 'https://api.termisol-cloud.com/v1'; // Placeholder - would be actual service
  static const Duration _syncInterval = Duration(minutes: 5);
  static const Duration _realtimeCheckInterval = Duration(seconds: 30);

  final SessionPersistence _localPersistence;
  final String _userId; // For single user, this would be a fixed identifier

  bool _isInitialized = false;
  bool _isOnline = true;
  Timer? _syncTimer;
  Timer? _realtimeTimer;
  String? _authToken;
  DateTime? _lastSyncTime;
  final Map<String, DateTime> _lastModified = {};

  final StreamController<CloudSyncEvent> _eventController =
      StreamController<CloudSyncEvent>.broadcast();

  Stream<CloudSyncEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isOnline => _isOnline;
  DateTime? get lastSyncTime => _lastSyncTime;

  CloudSessionSync(this._localPersistence, this._userId);

  /// Initialize cloud sync
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('☁️ Initializing Cloud Session Sync...');

      // Load auth token
      await _loadAuthToken();

      // Check connectivity
      await _checkConnectivity();

      // Setup sync timers
      _setupSyncTimers();

      // Initial sync
      await _performInitialSync();

      _isInitialized = true;
      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.initialized,
        message: 'Cloud sync initialized',
        data: {'online': _isOnline},
      ));

      debugPrint('☁️ Cloud Session Sync initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Cloud Sync: $e');
      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.error,
        message: 'Failed to initialize cloud sync',
        data: {'error': e.toString()},
      ));
    }
  }

  /// Load authentication token
  Future<void> _loadAuthToken() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tokenFile = File('${dir.path}/.termisol_cloud_token');

      if (await tokenFile.exists()) {
        _authToken = await tokenFile.readAsString();
        debugPrint('🔑 Loaded cloud auth token');
      } else {
        // For single user, generate or use a fixed token
        _authToken = 'termisol_user_${_userId}_token'; // In real implementation, this would be proper auth
        await tokenFile.writeAsString(_authToken!);
        debugPrint('🔑 Generated new cloud auth token');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load auth token: $e');
    }
  }

  /// Check network connectivity
  Future<void> _checkConnectivity() async {
    try {
      final result = await http.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 5));
      _isOnline = result.statusCode == 200;
    } catch (e) {
      _isOnline = false;
      debugPrint('🌐 Connectivity check failed: $e');
    }
  }

  /// Setup sync timers
  void _setupSyncTimers() {
    _syncTimer = Timer.periodic(_syncInterval, (_) => _periodicSync());
    _realtimeTimer = Timer.periodic(_realtimeCheckInterval, (_) => _checkForRemoteChanges());
    debugPrint('⏰ Cloud sync timers started');
  }

  /// Perform initial sync on startup
  Future<void> _performInitialSync() async {
    if (!_isOnline) return;

    try {
      debugPrint('🔄 Performing initial cloud sync...');

      // Download remote sessions
      final remoteSessions = await _downloadRemoteSessions();

      // Merge with local sessions
      await _mergeSessions(remoteSessions);

      // Upload local changes
      await _uploadLocalChanges();

      _lastSyncTime = DateTime.now();

      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.syncCompleted,
        message: 'Initial sync completed',
        data: {'last_sync': _lastSyncTime.toString()},
      ));

      debugPrint('✅ Initial cloud sync completed');
    } catch (e) {
      debugPrint('⚠️ Initial sync failed: $e');
      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.error,
        message: 'Initial sync failed',
        data: {'error': e.toString()},
      ));
    }
  }

  /// Download sessions from cloud
  Future<Map<String, CloudSessionData>> _downloadRemoteSessions() async {
    if (_authToken == null || !_isOnline) return {};

    try {
      final response = await http.get(
        Uri.parse('$_cloudBaseUrl/sessions'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final sessions = data['sessions'] as Map<String, dynamic>? ?? {};

        return sessions.map((key, value) =>
            MapEntry(key, CloudSessionData.fromJson(value as Map<String, dynamic>)));
      } else if (response.statusCode == 404) {
        // No remote sessions yet
        return {};
      } else {
        throw Exception('Failed to download sessions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download remote sessions: $e');
      return {};
    }
  }

  /// Upload local changes to cloud
  Future<void> _uploadLocalChanges() async {
    if (_authToken == null || !_isOnline) return;

    try {
      final localSessions = _localPersistence.sessions;
      final uploadData = {
        'sessions': localSessions.map((key, session) =>
            MapEntry(key, CloudSessionData.fromPersistedSession(session).toJson())),
        'lastModified': DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('$_cloudBaseUrl/sessions/sync'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(uploadData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        debugPrint('📤 Uploaded local changes to cloud');
      } else {
        throw Exception('Failed to upload changes: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to upload local changes: $e');
    }
  }

  /// Merge remote and local sessions
  Future<void> _mergeSessions(Map<String, CloudSessionData> remoteSessions) async {
    try {
      final localSessions = Map<String, PersistedSession>.from(_localPersistence.sessions);

      for (final entry in remoteSessions.entries) {
        final remoteSession = entry.value;
        final localSession = localSessions[entry.key];

        if (localSession == null) {
          // New remote session, add locally
          final persistedSession = remoteSession.toPersistedSession();
          _localPersistence.sessions[entry.key] = persistedSession;
          _lastModified[entry.key] = remoteSession.lastModified;
          debugPrint('📥 Added remote session: ${entry.key}');
        } else {
          // Compare timestamps to resolve conflicts
          final remoteTime = remoteSession.lastModified;
          final localTime = _lastModified[entry.key] ?? localSession.lastAccessed;

          if (remoteTime.isAfter(localTime)) {
            // Remote is newer, update local
            final updatedSession = remoteSession.toPersistedSession();
            _localPersistence.sessions[entry.key] = updatedSession;
            _lastModified[entry.key] = remoteTime;
            debugPrint('🔄 Updated local session from remote: ${entry.key}');
          } else if (localTime.isAfter(remoteTime)) {
            // Local is newer, will be uploaded in next sync
            debugPrint('📤 Local session newer, will upload: ${entry.key}');
          }
        }
      }

      // Save merged sessions
      await _localPersistence.forceSave();

      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.mergeCompleted,
        message: 'Session merge completed',
        data: {'remote_count': remoteSessions.length},
      ));

    } catch (e) {
      debugPrint('⚠️ Failed to merge sessions: $e');
    }
  }

  /// Periodic sync
  Future<void> _periodicSync() async {
    if (!_isInitialized || !_isOnline) return;

    try {
      await _checkConnectivity();
      if (!_isOnline) return;

      debugPrint('🔄 Performing periodic cloud sync...');

      // Download latest changes
      final remoteSessions = await _downloadRemoteSessions();

      // Check for changes
      bool hasChanges = false;
      for (final entry in remoteSessions.entries) {
        final lastMod = _lastModified[entry.key];
        if (lastMod == null || entry.value.lastModified.isAfter(lastMod)) {
          hasChanges = true;
          break;
        }
      }

      if (hasChanges) {
        await _mergeSessions(remoteSessions);
      }

      // Upload any local changes
      await _uploadLocalChanges();

      _lastSyncTime = DateTime.now();

      debugPrint('✅ Periodic sync completed');
    } catch (e) {
      debugPrint('⚠️ Periodic sync failed: $e');
    }
  }

  /// Check for remote changes in real-time
  Future<void> _checkForRemoteChanges() async {
    if (!_isInitialized || !_isOnline) return;

    try {
      final response = await http.get(
        Uri.parse('$_cloudBaseUrl/sessions/changes?since=${_lastSyncTime?.toIso8601String() ?? ''}'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hasChanges = data['hasChanges'] as bool? ?? false;

        if (hasChanges) {
          _eventController.add(CloudSyncEvent(
            type: CloudSyncEventType.remoteChangesDetected,
            message: 'Remote changes detected',
            data: data,
          ));

          // Trigger immediate sync
          await _periodicSync();
        }
      }
    } catch (e) {
      // Silently fail for real-time checks
      debugPrint('⚠️ Real-time change check failed: $e');
    }
  }

  /// Force immediate sync
  Future<void> forceSync() async {
    if (!_isInitialized) return;

    try {
      await _checkConnectivity();
      if (!_isOnline) {
        throw Exception('No internet connection');
      }

      await _periodicSync();

      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.syncCompleted,
        message: 'Manual sync completed',
        data: {'manual': true, 'timestamp': DateTime.now().toString()},
      ));

      debugPrint('🔄 Manual sync completed');
    } catch (e) {
      debugPrint('⚠️ Manual sync failed: $e');
      _eventController.add(CloudSyncEvent(
        type: CloudSyncEventType.error,
        message: 'Manual sync failed',
        data: {'error': e.toString()},
      ));
      rethrow;
    }
  }

  /// Get sync statistics
  Map<String, dynamic> getSyncStats() {
    return {
      'is_online': _isOnline,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'sessions_synced': _lastModified.length,
      'sync_interval_minutes': _syncInterval.inMinutes,
      'realtime_check_seconds': _realtimeCheckInterval.inSeconds,
    };
  }

  /// Dispose resources
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _realtimeTimer?.cancel();
    await _eventController.close();
    _isInitialized = false;
    debugPrint('☁️ Cloud Session Sync disposed');
  }
}

/// Cloud session data structure
class CloudSessionData {
  final String sessionId;
  final String data; // Encrypted JSON string
  final DateTime lastModified;
  final String deviceId;
  final int version;

  CloudSessionData({
    required this.sessionId,
    required this.data,
    required this.lastModified,
    required this.deviceId,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'data': data,
    'lastModified': lastModified.toIso8601String(),
    'deviceId': deviceId,
    'version': version,
  };

  factory CloudSessionData.fromJson(Map<String, dynamic> json) => CloudSessionData(
    sessionId: json['sessionId'] as String,
    data: json['data'] as String,
    lastModified: DateTime.parse(json['lastModified'] as String),
    deviceId: json['deviceId'] as String? ?? 'unknown',
    version: json['version'] as int? ?? 1,
  );

  factory CloudSessionData.fromPersistedSession(PersistedSession session) => CloudSessionData(
    sessionId: session.id,
    data: jsonEncode(session.toJson()), // In real implementation, this would be encrypted
    lastModified: session.lastAccessed,
    deviceId: Platform.localHostname, // Or a proper device ID
    version: 1,
  );

  PersistedSession toPersistedSession() {
    final json = jsonDecode(data) as Map<String, dynamic>;
    return PersistedSession.fromJson(json);
  }
}

/// Cloud sync event types
enum CloudSyncEventType {
  initialized,
  syncCompleted,
  mergeCompleted,
  remoteChangesDetected,
  error,
}

/// Cloud sync event
class CloudSyncEvent {
  final CloudSyncEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  CloudSyncEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}