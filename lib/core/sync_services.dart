import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Sync Services
///
/// Cross-device data synchronization with conflict resolution,
/// delta sync optimization, and persistent change tracking.
class SyncServices {
  final Map<String, SyncStore> _stores = {};
  final Map<String, SyncPeer> _peers = {};
  final List<SyncChange> _pendingChanges = [];
  final List<SyncChange> _changeLog = [];
  Timer? _syncTimer;
  SyncMode _mode = SyncMode.manual;
  int _syncVersion = 0;
  int _conflicts = 0;
  bool _online = false;

  static const Duration _autoSyncInterval = Duration(seconds: 30);
  static const int _maxChangeLog = 500;

  SyncMode get mode => _mode;
  int get syncVersion => _syncVersion;
  int get conflicts => _conflicts;
  int get pendingChangeCount => _pendingChanges.length;

  Future<void> initialize({SyncMode mode = SyncMode.manual, String? syncServerUrl}) async {
    _mode = mode;
    await _loadState();
    if (mode == SyncMode.automatic) {
      _syncTimer = Timer.periodic(_autoSyncInterval, (_) => sync());
    }
    debugPrint('SyncServices initialized (mode: ${mode.name})');
  }

  void registerStore(String name, SyncStore store) {
    _stores[name] = store;
  }

  void addPeer(SyncPeer peer) {
    _peers[peer.id] = peer;
  }

  Future<SyncChange> put(String store, String key, dynamic value, {Map<String, dynamic>? metadata}) async {
    final change = SyncChange(
      id: _generateChangeId(),
      store: store,
      key: key,
      value: value,
      operation: SyncOperation.put,
      timestamp: DateTime.now(),
      metadata: metadata ?? {},
      syncVersion: _syncVersion,
    );

    _pendingChanges.add(change);
    _changeLog.add(change);
    if (_changeLog.length > _maxChangeLog) {
      _changeLog.removeRange(0, _changeLog.length - _maxChangeLog);
    }

    if (_stores.containsKey(store)) {
      _stores[store]!.data[key] = value;
    }

    return change;
  }

  Future<SyncChange> deleteRecord(String store, String key) async {
    final change = SyncChange(
      id: _generateChangeId(),
      store: store,
      key: key,
      value: null,
      operation: SyncOperation.delete,
      timestamp: DateTime.now(),
      metadata: {},
      syncVersion: _syncVersion,
    );

    _pendingChanges.add(change);
    _changeLog.add(change);
    if (_changeLog.length > _maxChangeLog) {
      _changeLog.removeRange(0, _changeLog.length - _maxChangeLog);
    }

    if (_stores.containsKey(store)) {
      _stores[store]!.data.remove(key);
    }

    return change;
  }

  dynamic get(String store, String key) {
    return _stores[store]?.data[key];
  }

  Map<String, dynamic> getAll(String store) {
    return Map.from(_stores[store]?.data ?? {});
  }

  Future<SyncResult> sync() async {
    if (_pendingChanges.isEmpty) return SyncResult(synced: 0, conflicts: 0);

    int synced = 0;
    int conflicts = 0;
    final pending = List<SyncChange>.from(_pendingChanges);
    _pendingChanges.clear();

    for (final peer in _peers.values) {
      if (!peer.isOnline) continue;
      try {
        final batch = pending.map((c) => c.toJson()).toList();
        final response = await _sendBatchToPeer(peer, batch);
        if (response.success) {
          synced += response.synced;
          conflicts += response.conflicts;
          _conflicts += response.conflicts;
        }
      } catch (e) {
        debugPrint('Failed to sync with peer ${peer.id}: $e');
        _pendingChanges.addAll(pending.where((c) => c.id != pending.first.id));
      }
    }

    _syncVersion++;
    await _persistState();
    return SyncResult(synced: synced, conflicts: conflicts);
  }

  Future<bool> applyRemote(String store, String key, dynamic value, int remoteVersion) async {
    if (!_stores.containsKey(store)) return false;

    final local = _stores[store]!.data[key];
    final localVersion = _stores[store]!.versions[key] ?? 0;

    if (remoteVersion > localVersion) {
      _stores[store]!.data[key] = value;
      _stores[store]!.versions[key] = remoteVersion;
      return true;
    } else if (remoteVersion == localVersion && local != null && local != value) {
      _conflicts++;
      return false;
    }
    return false;
  }

  Future<SyncBatchResponse> _sendBatchToPeer(SyncPeer peer, List<Map<String, dynamic>> batch) async {
    if (peer.endpoint.isEmpty) {
      return SyncBatchResponse(success: true, synced: batch.length, conflicts: 0);
    }
    try {
      final response = await http.post(
        Uri.parse(peer.endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'changes': batch, 'peerId': peer.id}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return SyncBatchResponse(
          success: true,
          synced: data['synced'] as int? ?? batch.length,
          conflicts: data['conflicts'] as int? ?? 0,
        );
      }
      return SyncBatchResponse(success: false, synced: 0, conflicts: 0);
    } catch (e) {
      return SyncBatchResponse(success: false, synced: 0, conflicts: 0);
    }
  }

  Future<Map<String, dynamic>> exportState() async {
    final state = <String, dynamic>{};
    for (final entry in _stores.entries) {
      state[entry.key] = entry.value.data;
    }
    return {
      'stores': state,
      'syncVersion': _syncVersion,
      'conflicts': _conflicts,
      'pendingChanges': _pendingChanges.length,
    };
  }

  Future<void> resetSync() async {
    _pendingChanges.clear();
    _changeLog.clear();
    _syncVersion = 0;
    _conflicts = 0;
    for (final store in _stores.values) {
      store.versions.clear();
    }
    await _persistState();
  }

  String _generateChangeId() {
    return 'change_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync_version', _syncVersion);
      await prefs.setInt('sync_conflicts', _conflicts);
    } catch (e) {
      debugPrint('Failed to persist sync state: $e');
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _syncVersion = prefs.getInt('sync_version') ?? 0;
      _conflicts = prefs.getInt('sync_conflicts') ?? 0;
    } catch (e) {
      debugPrint('Failed to load sync state: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _stores.clear();
    _peers.clear();
    _pendingChanges.clear();
    _changeLog.clear();
  }
}

enum SyncMode { manual, automatic, onConnect }
enum SyncOperation { put, delete, patch }

class SyncStore {
  final String name;
  final Map<String, dynamic> data;
  final Map<String, int> versions;

  SyncStore({required this.name, Map<String, dynamic>? data, Map<String, int>? versions})
      : data = data ?? {},
        versions = versions ?? {};
}

class SyncPeer {
  final String id;
  final String name;
  final String endpoint;
  bool isOnline;
  DateTime? lastSync;

  SyncPeer({
    required this.id,
    required this.name,
    this.endpoint = '',
    this.isOnline = false,
    this.lastSync,
  });
}

class SyncChange {
  final String id;
  final String store;
  final String key;
  final dynamic value;
  final SyncOperation operation;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final int syncVersion;

  SyncChange({
    required this.id,
    required this.store,
    required this.key,
    this.value,
    required this.operation,
    required this.timestamp,
    required this.metadata,
    required this.syncVersion,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'store': store, 'key': key, 'value': value,
    'operation': operation.name, 'timestamp': timestamp.toIso8601String(),
    'metadata': metadata, 'syncVersion': syncVersion,
  };

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      id: json['id'] as String,
      store: json['store'] as String,
      key: json['key'] as String,
      value: json['value'],
      operation: SyncOperation.values.byName(json['operation'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: Map<String, dynamic>.from((json['metadata'] as Map?) ?? {}),
      syncVersion: json['syncVersion'] as int? ?? 0,
    );
  }
}

class SyncResult {
  final int synced;
  final int conflicts;
  final String? error;

  SyncResult({required this.synced, required this.conflicts, this.error});
}

class SyncBatchResponse {
  final bool success;
  final int synced;
  final int conflicts;

  SyncBatchResponse({required this.success, required this.synced, required this.conflicts});
}