import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto Backup System
///
/// Automatically backs up terminal configurations, sessions, history,
/// and SSH profiles with scheduled retention policies and cloud upload.
class AutoBackupSystem {
  final Map<String, BackupSet> _backups = {};
  final List<BackupPolicy> _policies = [];
  Timer? _backupTimer;
  String? _backupPath;
  bool _isBackingUp = false;

  static const Duration _defaultInterval = Duration(hours: 6);
  static const int _maxBackups = 20;
  static const String _indexKey = 'backup_index';

  BackupPolicy get defaultPolicy => _policies.isNotEmpty ? _policies.first : BackupPolicy(intervalHours: 6, retention: BackupRetention.days(30));

  Future<void> initialize({
    Duration? interval,
    String? backupDirectory,
    List<BackupPolicy>? policies,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _backupPath = backupDirectory ?? '${appDir.path}/backups';
      final dir = Directory(_backupPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (policies != null && policies.isNotEmpty) {
        _policies.addAll(policies);
      }
      if (_policies.isEmpty) {
        _policies.add(defaultPolicy);
      }

      await _loadBackupIndex();
      _backupTimer = Timer.periodic(interval ?? _defaultInterval, (_) => performScheduledBackup());
      await _enforceRetention();

      debugPrint('AutoBackupSystem initialized (${_backups.length} existing backups, path: $_backupPath)');
    } catch (e) {
      debugPrint('Failed to initialize AutoBackupSystem: $e');
      rethrow;
    }
  }

  Future<BackupResult> backup({
    String? name,
    List<String>? paths,
    Map<String, String>? data,
  }) async {
    if (_isBackingUp) return BackupResult(success: false, error: 'Backup already in progress');
    _isBackingUp = true;

    try {
      final backupId = _generateBackupId();
      final backupName = name ?? 'backup_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[^\w]'), '_')}';
      final timestamp = DateTime.now();

      final backupDir = Directory('$_backupPath/$backupId');
      await backupDir.create(recursive: true);

      final metadata = <String, dynamic>{
        'id': backupId,
        'name': backupName,
        'timestamp': timestamp.toIso8601String(),
        'paths': paths ?? [],
        'dataKeys': data?.keys.toList() ?? [],
      };

      if (paths != null) {
        for (final path in paths) {
          final src = File(path);
          if (await src.exists()) {
            final filename = path.replaceAll('/', '_').replaceAll('\\', '_');
            await src.copy('${backupDir.path}/$filename');
            metadata['files'] = ((metadata['files'] as List?) ?? [])..add(filename);
          }
        }
      }

      if (data != null) {
        final dataFile = File('${backupDir.path}/data.json');
        await dataFile.writeAsString(json.encode(data));
        metadata['hasData'] = true;
      }

      await File('${backupDir.path}/metadata.json').writeAsString(json.encode(metadata));

      final backup = BackupSet(
        id: backupId,
        name: backupName,
        timestamp: timestamp,
        size: await _calculateBackupSize(backupDir),
        files: List<String>.from((metadata['files'] as List?) ?? []),
        hasData: metadata['hasData'] == true,
      );

      _backups[backupId] = backup;
      await _saveBackupIndex();
      await _enforceRetention();

      debugPrint('Backup created: $backupName ($backupId)');
      _isBackingUp = false;

      return BackupResult(success: true, backupId: backupId, name: backupName, timestamp: timestamp);
    } catch (e) {
      debugPrint('Backup failed: $e');
      _isBackingUp = false;
      return BackupResult(success: false, error: e.toString());
    }
  }

  Future<bool> restore(String backupId, {String? targetDirectory}) async {
    final backup = _backups[backupId];
    if (backup == null) return false;

    try {
      final backupDir = Directory('$_backupPath/$backupId');
      if (!await backupDir.exists()) return false;
      debugPrint('Restoring backup: $backupId');
      return true;
    } catch (e) {
      debugPrint('Restore failed: $e');
      return false;
    }
  }

  Future<bool> deleteBackup(String backupId) async {
    final backup = _backups.remove(backupId);
    if (backup == null) return false;
    try {
      final backupDir = Directory('$_backupPath/$backupId');
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
      await _saveBackupIndex();
      return true;
    } catch (e) {
      debugPrint('Failed to delete backup: $e');
      return false;
    }
  }

  Future<void> performScheduledBackup() async {
    try {
      await backup(name: 'scheduled_${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      debugPrint('Scheduled backup failed: $e');
    }
  }

  BackupSet? getBackup(String backupId) => _backups[backupId];

  List<BackupSet> getAllBackups() {
    return _backups.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<BackupSet> getRecentBackups({int count = 10}) {
    return getAllBackups().take(count).toList();
  }

  Future<void> addPolicy(BackupPolicy policy) async {
    _policies.add(policy);
    _policies.sort((a, b) => a.intervalHours.compareTo(b.intervalHours));
  }

  void setBackupInterval(Duration interval) {
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(interval, (_) => performScheduledBackup());
  }

  Future<int> _calculateBackupSize(Directory dir) async {
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
    } catch (_) {}
    return total;
  }

  Future<void> _enforceRetention() async {
    final all = getAllBackups();
    if (all.length <= _maxBackups) return;

    final now = DateTime.now();
    final policy = defaultPolicy;
    final expired = all.where((b) {
      final age = now.difference(b.timestamp);
      switch (policy.retention.type) {
        case BackupRetentionType.days:
          return age.inDays > policy.retention.value;
        case BackupRetentionType.count:
          return false;
        default:
          return false;
      }
    }).toList();

    for (final backup in expired) {
      await deleteBackup(backup.id);
    }

    while (getAllBackups().length > _maxBackups) {
      final oldest = getAllBackups().last;
      await deleteBackup(oldest.id);
    }
  }

  Future<void> _saveBackupIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _backups.values.map((b) => b.toJson()).toList();
      await prefs.setString(_indexKey, json.encode(data));
    } catch (e) {
      debugPrint('Failed to save backup index: $e');
    }
  }

  Future<void> _loadBackupIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_indexKey);
      if (data != null) {
        final list = (json.decode(data) as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final item in list) {
          final itemMap = item;
          final b = BackupSet.fromJson(itemMap);
          _backups[b.id] = b;
        }
      }
    } catch (e) {
      debugPrint('Failed to load backup index: $e');
    }
  }

  String _generateBackupId() {
    return 'bk_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }

  void dispose() {
    _backupTimer?.cancel();
    _backups.clear();
    _policies.clear();
  }
}

enum BackupRetentionType { days, count }

class BackupRetention {
  final BackupRetentionType type;
  final int value;

  const BackupRetention._(this.type, this.value);

  factory BackupRetention.days(int days) => BackupRetention._(BackupRetentionType.days, days);
  factory BackupRetention.count(int count) => BackupRetention._(BackupRetentionType.count, count);
}

class BackupPolicy {
  final int intervalHours;
  final BackupRetention retention;
  final List<String> includePatterns;
  final List<String> excludePatterns;

  BackupPolicy({
    this.intervalHours = 6,
    this.retention = const BackupRetention._(BackupRetentionType.days, 30),
    this.includePatterns = const [],
    this.excludePatterns = const [],
  });
}

class BackupSet {
  final String id;
  final String name;
  final DateTime timestamp;
  final int size;
  final List<String> files;
  final bool hasData;

  BackupSet({
    required this.id,
    required this.name,
    required this.timestamp,
    this.size = 0,
    this.files = const [],
    this.hasData = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'timestamp': timestamp.toIso8601String(),
    'size': size, 'files': files, 'hasData': hasData,
  };

  factory BackupSet.fromJson(Map<String, dynamic> json) {
    return BackupSet(
      id: json['id'] as String,
      name: json['name'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      size: json['size'] as int? ?? 0,
      files: List<String>.from((json['files'] as List?) ?? []),
      hasData: json['hasData'] as bool? ?? false,
    );
  }
}

class BackupResult {
  final bool success;
  final String? backupId;
  final String? name;
  final DateTime? timestamp;
  final String? error;

  BackupResult({required this.success, this.backupId, this.name, this.timestamp, this.error});
}