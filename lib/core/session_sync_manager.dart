import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session Sync Manager
///
/// Synchronizes terminal sessions, configurations, and history across
/// devices using a conflict-resolved merge strategy with delta updates.
class SessionSyncManager {
  final Map<String, SyncedSession> _sessions = {};
  final Map<String, SyncConfig> _configs = {};
  final StreamController<SyncEvent> _eventController = StreamController<SyncEvent>.broadcast();
  SyncState _state = SyncState.idle;
  DateTime? _lastSyncTime;
  Timer? _syncTimer;
  int _syncVersion = 0;

  static const Duration _autoSyncInterval = Duration(minutes: 1);
  static const int _maxHistoryEntries = 500;
  static const String _prefsKeyPrefix = 'session_sync_';

  Stream<SyncEvent> get events => _eventController.stream;
  SyncState get state => _state;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get syncVersion => _syncVersion;

  Future<void> initialize({Duration? syncInterval}) async {
    try {
      await _loadPersistedState();
      _syncTimer = Timer.periodic(syncInterval ?? _autoSyncInterval, (_) => syncAll());
      _state = SyncState.idle;
      debugPrint('SessionSyncManager initialized (${_sessions.length} sessions)');
    } catch (e) {
      debugPrint('Failed to initialize SessionSyncManager: $e');
      rethrow;
    }
  }

  Future<bool> registerSession({
    required String sessionId,
    required String deviceId,
    String? title,
    Map<String, dynamic>? metadata,
  }) async {
    if (_sessions.containsKey(sessionId)) return false;
    _sessions[sessionId] = SyncedSession(
      id: sessionId,
      deviceId: deviceId,
      title: title ?? 'Session $sessionId',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      version: 0,
      metadata: metadata ?? {},
      history: [],
      tabs: [],
      activeTabIndex: 0,
    );
    _syncVersion++;
    await _persistState();
    _eventController.add(SyncEvent.snapshot(sessionId, _sessions[sessionId]!, _syncVersion));
    return true;
  }

  Future<bool> syncSession({
    required String sessionId,
    String? title,
    Map<String, dynamic>? metadata,
    List<String>? historyDelta,
    Map<String, dynamic>? configDelta,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) return false;

    if (title != null && title != session.title) {
      session.title = title;
      session.version++;
    }
    if (metadata != null) {
      session.metadata.addAll(metadata);
      session.version++;
    }
    if (historyDelta != null && historyDelta.isNotEmpty) {
      session.history.addAll(historyDelta);
      if (session.history.length > _maxHistoryEntries) {
        session.history.removeRange(0, session.history.length - _maxHistoryEntries);
      }
      session.version++;
    }
    if (configDelta != null) {
      session.config.addAll(configDelta);
      session.version++;
    }

    session.updatedAt = DateTime.now();
    _syncVersion++;
    _lastSyncTime = DateTime.now();
    await _persistState();
    _eventController.add(SyncEvent.snapshot(sessionId, session, _syncVersion));
    return true;
  }

  SyncedSession? getSession(String sessionId) => _sessions[sessionId];

  List<SyncedSession> getAllSessions() => _sessions.values.toList();

  List<SyncedSession> getSessionsForDevice(String deviceId) {
    return _sessions.values.where((s) => s.deviceId == deviceId).toList();
  }

  Future<bool> removeSession(String sessionId) async {
    final removed = _sessions.remove(sessionId);
    if (removed != null) {
      _syncVersion++;
      await _persistState();
      _eventController.add(SyncEvent.snapshot(sessionId, removed, _syncVersion));
    }
    return removed != null;
  }

  Future<SyncResult> mergeFromRemote(Map<String, dynamic> remoteState) async {
    try {
      _state = SyncState.syncing;
      int conflicts = 0;
      int merged = 0;

      final remoteSessions = (remoteState['sessions'] as Map<String, dynamic>?) ?? {};
      for (final entry in remoteSessions.entries) {
        final remote = SyncedSession.fromJson(Map<String, dynamic>.from(entry.value as Map));
        final local = _sessions[entry.key];

        if (local == null) {
          _sessions[entry.key] = remote;
          merged++;
        } else if (remote.updatedAt.isAfter(local.updatedAt)) {
          _mergeSession(local, remote);
          merged++;
        } else if (local.version != remote.version) {
          conflicts++;
        }
      }

      _syncVersion++;
      _lastSyncTime = DateTime.now();
      await _persistState();
      _state = SyncState.idle;
      _eventController.add(SyncEvent.withResult(SyncResult(merged: merged, conflicts: conflicts)));

      return SyncResult(merged: merged, conflicts: conflicts);
    } catch (e) {
      _state = SyncState.error;
      _eventController.add(SyncEvent.withError(e.toString()));
      return SyncResult(error: e.toString());
    }
  }

  Future<Map<String, dynamic>> exportState() async {
    return {
      'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
      'syncVersion': _syncVersion,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
    };
  }

  Future<void> syncAll() async {
    if (_state == SyncState.syncing) return;
    _state = SyncState.syncing;
    try {
      await _persistState();
      _eventController.add(SyncEvent.heartbeat(_syncVersion));
    } finally {
      _state = SyncState.idle;
    }
  }

  void _mergeSession(SyncedSession local, SyncedSession remote) {
    local.title = remote.title;
    local.metadata.addAll(remote.metadata);
    local.history = _mergeLists(local.history, remote.history);
    local.config.addAll(remote.config);
    local.tabs = remote.tabs;
    local.activeTabIndex = remote.activeTabIndex;
    local.version = max(local.version, remote.version) + 1;
    local.updatedAt = DateTime.now();
  }

  List<String> _mergeLists(List<String> a, List<String> b) {
    final merged = <String>{...a, ...b}.toList();
    if (merged.length > _maxHistoryEntries) {
      return merged.sublist(merged.length - _maxHistoryEntries);
    }
    return merged;
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = json.encode({
        'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
        'syncVersion': _syncVersion,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
      });
      await prefs.setString('${_prefsKeyPrefix}state', data);
    } catch (e) {
      debugPrint('Failed to persist sync state: $e');
    }
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('${_prefsKeyPrefix}state');
      if (data == null) return;
      final decoded = json.decode(data) as Map<String, dynamic>;
      _syncVersion = (decoded['syncVersion'] as int?) ?? 0;
      if (decoded['lastSyncTime'] != null) {
        _lastSyncTime = DateTime.tryParse(decoded['lastSyncTime'] as String);
      }
      final sessions = (decoded['sessions'] as Map<String, dynamic>?) ?? {};
      for (final entry in sessions.entries) {
        _sessions[entry.key] = SyncedSession.fromJson(Map<String, dynamic>.from(entry.value as Map));
      }
    } catch (e) {
      debugPrint('Failed to load persisted sync state: $e');
    }
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    _sessions.clear();
    _configs.clear();
    await _eventController.close();
  }
}

enum SyncState { idle, syncing, error }

class SyncedSession {
  final String id;
  final String deviceId;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  int version;
  Map<String, dynamic> metadata;
  List<String> history;
  List<SessionTab> tabs;
  int activeTabIndex;
  Map<String, dynamic> config;

  SyncedSession({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    required this.metadata,
    required this.history,
    required this.tabs,
    required this.activeTabIndex,
    this.config = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'version': version,
    'metadata': metadata,
    'history': history,
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'activeTabIndex': activeTabIndex,
    'config': config,
  };

  factory SyncedSession.fromJson(Map<String, dynamic> json) {
    return SyncedSession(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      version: json['version'] as int,
      metadata: Map<String, dynamic>.from((json['metadata'] as Map?) ?? {}),
      history: List<String>.from((json['history'] as List?) ?? []),
      tabs: ((json['tabs'] as List?)?.map((t) => SessionTab.fromJson(Map<String, dynamic>.from(t as Map))).toList() ?? []),
      activeTabIndex: (json['activeTabIndex'] as int?) ?? 0,
      config: Map<String, dynamic>.from((json['config'] as Map?) ?? {}),
    );
  }
}

class SessionTab {
  final String id;
  String title;
  String workingDirectory;
  bool isActive;

  SessionTab({
    required this.id,
    required this.title,
    this.workingDirectory = '/',
    this.isActive = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'workingDirectory': workingDirectory,
    'isActive': isActive,
  };

  factory SessionTab.fromJson(Map<String, dynamic> json) {
    return SessionTab(
      id: json['id'] as String,
      title: json['title'] as String,
      workingDirectory: json['workingDirectory'] as String? ?? '/',
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

class SyncConfig {
  final String key;
  final dynamic value;
  final DateTime updatedAt;

  SyncConfig({required this.key, required this.value, required this.updatedAt});
}

class SyncResult {
  final int merged;
  final int conflicts;
  final String? error;

  SyncResult({this.merged = 0, this.conflicts = 0, this.error});
}

class SyncEvent {
  final String? sessionId;
  final SyncedSession? snapshot;
  final SyncResult? result;
  final int syncVersion;
  final String? error;
  final bool isHeartbeat;

  SyncEvent._({
    this.sessionId,
    this.snapshot,
    this.result,
    required this.syncVersion,
    this.error,
    this.isHeartbeat = false,
  });

  factory SyncEvent.snapshot(String sessionId, SyncedSession snapshot, int syncVersion) {
    return SyncEvent._(sessionId: sessionId, snapshot: snapshot, syncVersion: syncVersion);
  }

  factory SyncEvent.withResult(SyncResult result) {
    return SyncEvent._(result: result, syncVersion: 0);
  }

  factory SyncEvent.heartbeat(int syncVersion) {
    return SyncEvent._(syncVersion: syncVersion, isHeartbeat: true);
  }

  factory SyncEvent.withError(String error) {
    return SyncEvent._(syncVersion: 0, error: error);
  }
}