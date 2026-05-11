import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'terminal_session.dart' as ui;

/// Crash-proof session persistence with atomic writes, checksums, and backup rotation.
class CrashProofPersistence {
  static final CrashProofPersistence _instance = CrashProofPersistence._internal();
  factory CrashProofPersistence() => _instance;
  CrashProofPersistence._internal();

  bool _isInitialized = false;
  final Map<String, PersistedSessionRecord> _sessions = {};
  final List<Map<String, dynamic>> _sessionHistory = [];
  final Map<String, SessionBackup> _backups = {};

  Timer? _autoSaveTimer;
  Timer? _debounceTimer;
  bool _autoSaveEnabled = true;
  Duration _autoSaveInterval = const Duration(seconds: 30);
  Duration _debounceDelay = const Duration(seconds: 5);

  final Map<String, CrashReport> _crashReports = {};
  bool _recoveryMode = false;

  Directory? _sessionsDir;
  Directory? _backupsDir;
  Directory? _crashDir;
  Directory? _tempDir;
  String? _deviceId;

  final _sessionController = StreamController<SessionEvent>.broadcast(sync: false);
  Stream<SessionEvent> get events => _sessionController.stream;

  static const int _maxBackups = 10;
  static const int _maxCrashReports = 20;
  static const Duration _sessionTimeout = Duration(hours: 24);
  static const String _version = '1.0.0';

  bool get isInitialized => _isInitialized;
  bool get autoSaveEnabled => _autoSaveEnabled;
  bool get recoveryMode => _recoveryMode;
  int get activeSessions => _sessions.length;
  int get availableBackups => _backups.length;
  String? get deviceId => _deviceId;

  Future<void> performCleanup() => _performCleanup();

  Future<void> createBackup() => _createBackup();

  Future<SessionBackup?> getLatestBackup() async {
    if (_backups.isEmpty) return null;
    final sortedBackups = _backups.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sortedBackups.first;
  }

  Future<List<CrashReport>> getCrashReports() async {
    return _crashReports.values.toList();
  }

  Future<PersistedSessionRecord?> getSession(String sessionId) async {
    return _sessions[sessionId];
  }

  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    await _sessionController.close();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _setupDirectories();
      await _generateDeviceId();
      await _checkForCrashRecovery();
      await _loadExistingSessions();
      await _loadBackups();
      await _verifyIntegrity();

      if (_autoSaveEnabled) {
        _startAutoSave();
      }
      _startCleanupTimer();

      _isInitialized = true;
      debugPrint('Crash-Proof Persistence initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize Crash-Proof Persistence: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _setupDirectories() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _sessionsDir = Directory('${appDir.path}/.termisol/sessions');
      _backupsDir = Directory('${appDir.path}/.termisol/backups');
      _crashDir = Directory('${appDir.path}/.termisol/crashes');
      _tempDir = Directory('${appDir.path}/.termisol/temp');

      for (final dir in [_sessionsDir, _backupsDir, _crashDir, _tempDir]) {
        await dir!.create(recursive: true);
      }

      debugPrint('Crash-proof directories created');
    } catch (e, stack) {
      debugPrint('Failed to setup directories: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _generateDeviceId() async {
    try {
      final dir = _sessionsDir;
      if (dir == null) return;
      final idFile = File('${dir.path}/device_id');

      if (await idFile.exists()) {
        _deviceId = await idFile.readAsString();
      } else {
        _deviceId = _generateSecureDeviceId();
        await _atomicWrite(idFile, _deviceId!);
      }

      debugPrint('Device ID: $_deviceId');
    } catch (e, stack) {
      debugPrint('Failed to generate device ID: $e\n$stack');
      _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  String _generateSecureDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  Future<void> _checkForCrashRecovery() async {
    try {
      final dir = _sessionsDir;
      if (dir == null) return;
      final crashIndicator = File('${dir.path}/.crash_indicator');

      if (await crashIndicator.exists()) {
        debugPrint('Crash detected, entering recovery mode');
        _recoveryMode = true;
        await _createCrashReport();
        await crashIndicator.delete();
        _sessionController.add(SessionEvent.crashDetected({'recovery_mode': true}));
      }

      await _atomicWrite(crashIndicator, DateTime.now().toIso8601String());
    } catch (e, stack) {
      debugPrint('Failed to check for crash recovery: $e\n$stack');
    }
  }

  Future<void> _createCrashReport() async {
    try {
      final crashReport = CrashReport(
        id: 'crash_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        deviceId: _deviceId ?? 'unknown',
        activeSessions: _sessions.length,
        lastKnownState: await _captureCurrentState(),
        error: 'Application crash detected',
      );

      _crashReports[crashReport.id] = crashReport;
      await _saveCrashReport(crashReport);

      debugPrint('Crash report created: ${crashReport.id}');
    } catch (e, stack) {
      debugPrint('Failed to create crash report: $e\n$stack');
    }
  }

  Future<Map<String, dynamic>> _captureCurrentState() async {
    return {
      'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': _deviceId,
      'version': _version,
      'checksum': await _calculateChecksum(),
    };
  }

  Future<String> _calculateChecksum() async {
    final data = jsonEncode({
      'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
      'timestamp': DateTime.now().toIso8601String(),
    });
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _verifyIntegrity() async {
    try {
      for (final session in _sessions.values) {
        if (session.checksum != null) {
          final currentChecksum = _calculateSessionChecksum(session);
          if (currentChecksum != session.checksum) {
            debugPrint('Checksum mismatch for session ${session.id}, attempting recovery');
            await _recoverSession(session.id);
          }
        }
      }
    } catch (e, stack) {
      debugPrint('Failed to verify integrity: $e\n$stack');
    }
  }

  String _calculateSessionChecksum(PersistedSessionRecord session) {
    final data = jsonEncode(session.toJson());
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _loadExistingSessions() async {
    try {
      final dir = _sessionsDir;
      if (dir == null || !await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content);
            if (data is! Map<String, dynamic>) continue;
            
            // Verify checksum if present
            if (data['checksum'] != null) {
              final calculatedChecksum = _calculateDataChecksum(data);
              if (calculatedChecksum != data['checksum']) {
                debugPrint('Corrupted session file: ${entity.path}');
                await entity.delete();
                continue;
              }
            }
            
            final session = PersistedSessionRecord.fromJson(data);
            _sessions[session.id] = session;

            if (_isSessionValid(session)) {
              debugPrint('Loaded session: ${session.id}');
            } else {
              _sessions.remove(session.id);
              await entity.delete();
            }
          } catch (e, stack) {
            debugPrint('Failed to load session from ${entity.path}: $e\n$stack');
          }
        }
      }

      debugPrint('Loaded ${_sessions.length} sessions');
    } catch (e, stack) {
      debugPrint('Failed to load existing sessions: $e\n$stack');
    }
  }

  String _calculateDataChecksum(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    copy.remove('checksum');
    final json = jsonEncode(copy);
    final bytes = utf8.encode(json);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _loadBackups() async {
    try {
      final dir = _backupsDir;
      if (dir == null || !await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.backup')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content);
            if (data is! Map<String, dynamic>) continue;
            
            // Verify backup integrity
            if (data['checksum'] != null) {
              final calculatedChecksum = _calculateDataChecksum(data);
              if (calculatedChecksum != data['checksum']) {
                debugPrint('Corrupted backup file: ${entity.path}');
                await entity.delete();
                continue;
              }
            }
            
            final backup = SessionBackup.fromJson(data);
            _backups[backup.id] = backup;
          } catch (e, stack) {
            debugPrint('Failed to load backup from ${entity.path}: $e\n$stack');
          }
        }
      }

      debugPrint('Loaded ${_backups.length} backups');
    } catch (e, stack) {
      debugPrint('Failed to load backups: $e\n$stack');
    }
  }

  bool _isSessionValid(PersistedSessionRecord session) {
    final now = DateTime.now();
    final lastActivity = session.lastActivity ?? session.createdAt;

    if (now.difference(lastActivity) > _sessionTimeout) {
      return false;
    }

    if (session.id.isEmpty || session.title.isEmpty) {
      return false;
    }

    return true;
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      unawaited(_performAutoSave().catchError((e) {
        debugPrint('Auto-save failed: $e');
      }));
    });

    debugPrint('Auto-save started (${_autoSaveInterval.inSeconds} seconds)');
  }

  Future<void> _performAutoSave() async {
    await _saveAllSessions();
    await _createBackup();

    _sessionController.add(SessionEvent.autoSaved({
        'sessions_count': _sessions.length,
        'timestamp': DateTime.now().toIso8601String(),
      }));
  }

  void _startCleanupTimer() {
    Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_performCleanup().catchError((e) {
        debugPrint('Cleanup failed: $e');
      }));
    });
  }

  Future<void> _performCleanup() async {
    await _cleanupOldSessions();
    await _cleanupOldBackups();
    await _cleanupOldCrashReports();
    await _cleanupTempFiles();
    debugPrint('Cleanup completed');
  }

  Future<void> _cleanupTempFiles() async {
    try {
      final dir = _tempDir;
      if (dir == null || !await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) > const Duration(hours: 1)) {
            await entity.delete();
          }
        }
      }
    } catch (e, stack) {
      debugPrint('Failed to cleanup temp files: $e\n$stack');
    }
  }

  Future<void> _cleanupOldSessions() async {
    final now = DateTime.now();
    final sessionsToRemove = <String>[];

    for (final entry in _sessions.entries) {
      final session = entry.value;
      final lastActivity = session.lastActivity ?? session.createdAt;

      if (now.difference(lastActivity) > _sessionTimeout) {
        sessionsToRemove.add(entry.key);
      }
    }

    for (final sessionId in sessionsToRemove) {
      await _removeSession(sessionId);
    }

    if (sessionsToRemove.isNotEmpty) {
      debugPrint('Cleaned up ${sessionsToRemove.length} old sessions');
    }
  }

  Future<void> _cleanupOldBackups() async {
    final backups = _backups.values.toList();
    backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (backups.length > _maxBackups) {
      final toRemove = backups.skip(_maxBackups);

      for (final backup in toRemove) {
        _backups.remove(backup.id);
        await _deleteBackup(backup.id);
      }

      debugPrint('Cleaned up ${toRemove.length} old backups');
    }
  }

  Future<void> _cleanupOldCrashReports() async {
    final reports = _crashReports.values.toList();
    reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (reports.length > _maxCrashReports) {
      final toRemove = reports.skip(_maxCrashReports);

      for (final report in toRemove) {
        _crashReports.remove(report.id);
        await _deleteCrashReport(report.id);
      }

      debugPrint('Cleaned up ${toRemove.length} old crash reports');
    }
  }

  Future<String> createSession({
    required String title,
    required String workingDirectory,
    Map<String, String>? environment,
    String? command,
  }) async {
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';

    final session = PersistedSessionRecord(
      id: sessionId,
      title: title,
      workingDirectory: workingDirectory,
      environment: environment ?? {},
      command: command,
      createdAt: DateTime.now(),
      lastActivity: DateTime.now(),
      isActive: true,
      content: '',
      history: [],
      bookmarks: [],
    );

    session.checksum = _calculateSessionChecksum(session);
    _sessions[sessionId] = session;
    await _saveSession(session);

    _sessionController.add(SessionEvent.sessionCreated(sessionId, session.toJson()));

    debugPrint('Created session: $sessionId');
    return sessionId;
  }

  Future<void> updateSession(String sessionId, {
    String? title,
    String? content,
    String? workingDirectory,
    Map<String, String>? environment,
    List<String>? history,
    List<String>? bookmarks,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }

    if (title != null) session.title = title;
    if (content != null) session.content = content;
    if (workingDirectory != null) session.workingDirectory = workingDirectory;
    if (environment != null) session.environment = environment;
    if (history != null) session.history = history;
    if (bookmarks != null) session.bookmarks = bookmarks;

    session.lastActivity = DateTime.now();
    session.checksum = _calculateSessionChecksum(session);

    await _saveSession(session);

    _sessionController.add(SessionEvent.sessionUpdated(sessionId, session.toJson()));
  }

  Future<void> removeSession(String sessionId) async {
    await _removeSession(sessionId);

    _sessionController.add(SessionEvent.sessionRemoved(sessionId));
  }

  Future<void> _removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await _deleteSession(sessionId);
      debugPrint('Removed session: $sessionId');
    }
  }

  

  List<PersistedSessionRecord> getAllSessions() {
    return _sessions.values.toList();
  }

  Future<void> saveAllSessions() async {
    await _saveAllSessions();
  }

  Future<void> _saveAllSessions() async {
    for (final session in _sessions.values) {
      await _saveSession(session);
    }
  }

  Future<void> _saveSession(PersistedSessionRecord session) async {
    try {
      final dir = _sessionsDir;
      if (dir == null) return;
      
      final sessionData = session.toJson();
      sessionData['checksum'] = _calculateSessionChecksum(session);
      
      final sessionFile = File('${dir.path}/${session.id}.json');
      await _atomicWrite(sessionFile, jsonEncode(sessionData));
    } catch (e, stack) {
      debugPrint('Failed to save session ${session.id}: $e\n$stack');
    }
  }

  Future<void> _atomicWrite(File file, String content) async {
    final tempFile = File('${file.path}.tmp.${DateTime.now().millisecondsSinceEpoch}');
    try {
      await tempFile.writeAsString(content);
      await tempFile.rename(file.path);
    } catch (e) {
      await tempFile.delete();
      rethrow;
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      final dir = _sessionsDir;
      if (dir == null) return;
      final sessionFile = File('${dir.path}/$sessionId.json');
      if (await sessionFile.exists()) {
        await sessionFile.delete();
      }
    } catch (e, stack) {
      debugPrint('Failed to delete session $sessionId: $e\n$stack');
    }
  }

  Future<void> _createBackup() async {
    try {
      final backupId = 'backup_${DateTime.now().millisecondsSinceEpoch}';

      final backupData = {
        'id': backupId,
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': _deviceId ?? 'unknown',
        'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
        'metadata': {
          'version': _version,
          'session_count': _sessions.length,
          'platform': Platform.operatingSystem,
        },
      };

      backupData['checksum'] = _calculateDataChecksum(backupData);

      final backup = SessionBackup.fromJson(backupData);
      _backups[backupId] = backup;
      await _saveBackup(backup);

      debugPrint('Created backup: $backupId');
    } catch (e, stack) {
      debugPrint('Failed to create backup: $e\n$stack');
    }
  }

  Future<void> _saveBackup(SessionBackup backup) async {
    try {
      final dir = _backupsDir;
      if (dir == null) return;
      
      final backupData = backup.toJson();
      backupData['checksum'] = _calculateDataChecksum(backupData);
      
      final backupFile = File('${dir.path}/${backup.id}.backup');
      await _atomicWrite(backupFile, jsonEncode(backupData));
    } catch (e, stack) {
      debugPrint('Failed to save backup ${backup.id}: $e\n$stack');
    }
  }

  Future<void> _deleteBackup(String backupId) async {
    try {
      final dir = _backupsDir;
      if (dir == null) return;
      final backupFile = File('${dir.path}/$backupId.backup');
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (e, stack) {
      debugPrint('Failed to delete backup $backupId: $e\n$stack');
    }
  }

  Future<void> _saveCrashReport(CrashReport report) async {
    try {
      final dir = _crashDir;
      if (dir == null) return;
      final reportFile = File('${dir.path}/${report.id}.json');
      await _atomicWrite(reportFile, jsonEncode(report.toJson()));
    } catch (e, stack) {
      debugPrint('Failed to save crash report ${report.id}: $e\n$stack');
    }
  }

  Future<void> _deleteCrashReport(String reportId) async {
    try {
      final dir = _crashDir;
      if (dir == null) return;
      final reportFile = File('${dir.path}/$reportId.json');
      if (await reportFile.exists()) {
        await reportFile.delete();
      }
    } catch (e, stack) {
      debugPrint('Failed to delete crash report $reportId: $e\n$stack');
    }
  }

  Future<void> _recoverSession(String sessionId) async {
    try {
      final backup = _findLatestBackupWithSession(sessionId);
      if (backup != null) {
        final sessionData = backup.sessions[sessionId];
        if (sessionData != null) {
          final session = PersistedSessionRecord.fromJson(sessionData);
          session.checksum = _calculateSessionChecksum(session);
          _sessions[sessionId] = session;
          await _saveSession(session);
          debugPrint('Recovered session $sessionId from backup');
        }
      }
    } catch (e, stack) {
      debugPrint('Failed to recover session $sessionId: $e\n$stack');
    }
  }

  SessionBackup? _findLatestBackupWithSession(String sessionId) {
    final backups = _backups.values.toList();
    backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (final backup in backups) {
      if (backup.sessions.containsKey(sessionId)) {
        return backup;
      }
    }
    return null;
  }

  Future<void> restoreFromBackup(String backupId) async {
    try {
      final backup = _backups[backupId];
      if (backup == null) {
        throw ArgumentError('Backup not found: $backupId');
      }

      _sessions.clear();
      for (final entry in backup.sessions.entries) {
        final session = PersistedSessionRecord.fromJson(entry.value);
        session.checksum = _calculateSessionChecksum(session);
        _sessions[entry.key] = session;
      }

      await _saveAllSessions();

      _sessionController.add(SessionEvent(
        type: SessionEventType.sessionRestored,
        data: {'backup_id': backupId, 'sessions_count': _sessions.length},
      ));

      debugPrint('Restored ${_sessions.length} sessions from backup $backupId');
    } catch (e, stack) {
      debugPrint('Failed to restore from backup $backupId: $e\n$stack');
      rethrow;
    }
  }

  List<SessionBackup> getAvailableBackups() {
    final backups = _backups.values.toList();
    backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return backups;
  }

  
}

// Data classes
class PersistedSessionRecord {
  String id;
  String title;
  String workingDirectory;
  Map<String, String> environment;
  String? command;
  DateTime createdAt;
  DateTime? lastActivity;
  bool isActive;
  String content;
  List<String> history;
  List<String> bookmarks;
  String? checksum;

  PersistedSessionRecord({
    required this.id,
    required this.title,
    required this.workingDirectory,
    required this.environment,
    this.command,
    required this.createdAt,
    this.lastActivity,
    required this.isActive,
    required this.content,
    required this.history,
    required this.bookmarks,
    this.checksum,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'workingDirectory': workingDirectory,
        'environment': environment,
        'command': command,
        'createdAt': createdAt.toIso8601String(),
        'lastActivity': lastActivity?.toIso8601String(),
        'isActive': isActive,
        'content': content,
        'history': history,
        'bookmarks': bookmarks,
        'checksum': checksum,
      };

  factory PersistedSessionRecord.fromJson(Map<String, dynamic> json) => PersistedSessionRecord(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        workingDirectory: json['workingDirectory'] as String? ?? '',
        environment: Map<String, String>.from(json['environment'] ?? {}),
        command: json['command'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastActivity: json['lastActivity'] != null ? DateTime.parse(json['lastActivity'] as String) : null,
        isActive: json['isActive'] as bool? ?? false,
        content: json['content'] as String? ?? '',
        history: List<String>.from(json['history'] ?? []),
        bookmarks: List<String>.from(json['bookmarks'] ?? []),
        checksum: json['checksum'] as String?,
      );
}

class SessionBackup {
  String id;
  DateTime timestamp;
  String deviceId;
  Map<String, Map<String, dynamic>> sessions;
  Map<String, dynamic> metadata;

  SessionBackup({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.sessions,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'device_id': deviceId,
        'sessions': sessions,
        'metadata': metadata,
      };

  factory SessionBackup.fromJson(Map<String, dynamic> json) => SessionBackup(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        deviceId: json['device_id'] as String? ?? '',
        sessions: Map<String, Map<String, dynamic>>.from(json['sessions'] ?? {}),
        metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      );
}

class CrashReport {
  String id;
  DateTime timestamp;
  String deviceId;
  int activeSessions;
  Map<String, dynamic> lastKnownState;
  String error;

  CrashReport({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.activeSessions,
    required this.lastKnownState,
    required this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'device_id': deviceId,
        'active_sessions': activeSessions,
        'last_known_state': lastKnownState,
        'error': error,
      };
}

class SessionEvent {
  final SessionEventType type;
  final String? sessionId;
  final Map<String, dynamic> data;

  SessionEvent({
    required this.type,
    this.sessionId,
    required this.data,
  });

  factory SessionEvent.sessionCreated(String sessionId, Map<String, dynamic> data) =>
      SessionEvent(type: SessionEventType.sessionCreated, sessionId: sessionId, data: data);

  factory SessionEvent.sessionUpdated(String sessionId, Map<String, dynamic> data) =>
      SessionEvent(type: SessionEventType.sessionUpdated, sessionId: sessionId, data: data);

  factory SessionEvent.sessionRemoved(String sessionId) =>
      SessionEvent(type: SessionEventType.sessionRemoved, sessionId: sessionId, data: {});

  factory SessionEvent.sessionRestored(Map<String, dynamic> data) =>
      SessionEvent(type: SessionEventType.sessionRestored, data: data);

  factory SessionEvent.autoSaved(Map<String, dynamic> data) =>
      SessionEvent(type: SessionEventType.autoSaved, data: data);

  factory SessionEvent.crashDetected(Map<String, dynamic> data) =>
      SessionEvent(type: SessionEventType.crashDetected, data: data);
}

enum SessionEventType {
  sessionCreated,
  sessionUpdated,
  sessionRemoved,
  sessionRestored,
  autoSaved,
  crashDetected,
}

// Utility function for unawaited futures
void unawaited(Future<void> future) {
  // Intentionally not awaiting - fire and forget
}