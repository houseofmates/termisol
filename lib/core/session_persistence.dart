import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'terminal_session.dart' as ui;

/// Session persistence and crash recovery system.
class SessionPersistence {
  static final SessionPersistence _instance = SessionPersistence._internal();
  factory SessionPersistence() => _instance;
  SessionPersistence._internal();

  bool _isInitialized = false;

  final Map<String, PersistedSessionRecord> _sessions = {};
  final List<SessionSnapshot> _sessionHistory = [];
  final Map<String, SessionBackup> _backups = {};

  Timer? _autoSaveTimer;
  Timer? _cleanupTimer;
  bool _autoSaveEnabled = true;
  Duration _autoSaveInterval = const Duration(minutes: 1);

  final Map<String, CrashReport> _crashReports = {};
  bool _recoveryMode = false;

  Directory? _sessionsDir;
  Directory? _backupsDir;
  Directory? _crashDir;
  String? _deviceId;

  final _sessionController = StreamController<SessionEvent>.broadcast(sync: false);
  Stream<SessionEvent> get events => _sessionController.stream;

  static const int _maxBackups = 50;
  static const int _maxCrashReports = 20;
  static const Duration _sessionTimeout = Duration(hours: 24);

  bool get isInitialized => _isInitialized;
  bool get autoSaveEnabled => _autoSaveEnabled;
  bool get recoveryMode => _recoveryMode;
  int get activeSessions => _sessions.length;
  int get availableBackups => _backups.length;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _setupDirectories();
      await _generateDeviceId();
      await _checkForCrashRecovery();
      await _loadExistingSessions();
      await _loadBackups();

      if (_autoSaveEnabled) {
        _startAutoSave();
      }
      _startCleanupTimer();

      _isInitialized = true;
      debugPrint('Session Persistence initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize Session Persistence: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _setupDirectories() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _sessionsDir = Directory('${appDir.path}/.termisol/sessions');
      _backupsDir = Directory('${appDir.path}/.termisol/backups');
      _crashDir = Directory('${appDir.path}/.termisol/crashes');

      await _sessionsDir!.create(recursive: true);
      await _backupsDir!.create(recursive: true);
      await _crashDir!.create(recursive: true);

      debugPrint('Session directories created');
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
        _deviceId = _generateDeviceIdString();
        await idFile.writeAsString(_deviceId!);
      }

      debugPrint('Device ID: $_deviceId');
    } catch (e, stack) {
      debugPrint('Failed to generate device ID: $e\n$stack');
      _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  String _generateDeviceIdString() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode(random + Platform.localHostname);
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
        _sessionController.add(SessionEvent(
          type: SessionEventType.crashDetected,
          data: {'recovery_mode': true},
        ));
      }

      await crashIndicator.writeAsString(DateTime.now().toIso8601String());
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
        lastKnownState: _captureCurrentState(),
        error: 'Application crash detected',
      );

      _crashReports[crashReport.id] = crashReport;
      await _saveCrashReport(crashReport);

      debugPrint('Crash report created: ${crashReport.id}');
    } catch (e, stack) {
      debugPrint('Failed to create crash report: $e\n$stack');
    }
  }

  Map<String, dynamic> _captureCurrentState() {
    return {
      'sessions': _sessions.map((k, v) => MapEntry(k, v.toJson())),
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': _deviceId,
      'version': '1.0.0',
    };
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

    debugPrint('Auto-save started (${_autoSaveInterval.inMinutes} minutes)');
  }

  Future<void> _performAutoSave() async {
    await _saveAllSessions();
    await _createBackup();

    _sessionController.add(SessionEvent(
      type: SessionEventType.autoSaved,
      data: {
        'sessions_count': _sessions.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ));
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_performCleanup().catchError((e) {
        debugPrint('Cleanup failed: $e');
      }));
    });
  }

  Future<void> _performCleanup() async {
    await _cleanupOldSessions();
    await _cleanupOldBackups();
    await _cleanupOldCrashReports();
    debugPrint('Cleanup completed');
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

    _sessions[sessionId] = session;
    await _saveSession(session);

    _sessionController.add(SessionEvent(
      type: SessionEventType.sessionCreated,
      sessionId: sessionId,
      data: session.toJson(),
    ));

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

    await _saveSession(session);

    _sessionController.add(SessionEvent(
      type: SessionEventType.sessionUpdated,
      sessionId: sessionId,
      data: session.toJson(),
    ));
  }

  Future<void> removeSession(String sessionId) async {
    await _removeSession(sessionId);

    _sessionController.add(SessionEvent(
      type: SessionEventType.sessionRemoved,
      sessionId: sessionId,
    ));
  }

  Future<void> _removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await _deleteSession(sessionId);
      debugPrint('Removed session: $sessionId');
    }
  }

  PersistedSessionRecord? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  List<PersistedSessionRecord> getAllSessions() {
    return _sessions.values.toList();
  }

  Future<void> saveAllSessions() async {
    await _saveAllSessions();
  }

  static const String _prefsKey = 'termisol_sessions';

  Future<void> saveSessions(List<ui.TerminalSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final data = sessions.map((s) => {
      'id': s.id,
      'name': s.name,
      'workingDirectory': s.directory.value ?? '',
      'commandHistory': s.commandHistory.commands,
      'terminalDimensions': {
        'cols': s.terminal.viewWidth,
        'rows': s.terminal.viewHeight,
      },
      'scrollback': s.terminal.buffer.getText(),
    }).toList();
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    final list = jsonDecode(jsonStr);
    if (list is! List<dynamic>) return [];
    return list.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
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
      final sessionFile = File('${dir.path}/${session.id}.json');
      await sessionFile.writeAsString(jsonEncode(session.toJson()));
    } catch (e, stack) {
      debugPrint('Failed to save session ${session.id}: $e\n$stack');
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

      final backup = SessionBackup(
        id: backupId,
        timestamp: DateTime.now(),
        deviceId: _deviceId ?? 'unknown',
        sessions: _sessions.map((k, v) => MapEntry(k, v.toJson())),
        metadata: {
          'version': '1.0.0',
          'session_count': _sessions.length,
          'platform': Platform.operatingSystem,
        },
      );

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
      final backupFile = File('${dir.path}/${backup.id}.backup');
      await backupFile.writeAsString(jsonEncode(backup.toJson()));
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
      final reportFile = File('${dir.path}/${report.id}.crash');
      await reportFile.writeAsString(jsonEncode(report.toJson()));
    } catch (e, stack) {
      debugPrint('Failed to save crash report ${report.id}: $e\n$stack');
    }
  }

  Future<void> _deleteCrashReport(String reportId) async {
    try {
      final dir = _crashDir;
      if (dir == null) return;
      final reportFile = File('${dir.path}/$reportId.crash');
      if (await reportFile.exists()) {
        await reportFile.delete();
      }
    } catch (e, stack) {
      debugPrint('Failed to delete crash report $reportId: $e\n$stack');
    }
  }

  Future<bool> restoreFromBackup(String backupId) async {
    try {
      final backup = _backups[backupId];
      if (backup == null) {
        throw ArgumentError('Backup not found: $backupId');
      }

      // Validate backup data before clearing current sessions.
      final restoredSessions = <String, PersistedSessionRecord>{};
      for (final entry in backup.sessions.entries) {
        final session = PersistedSessionRecord.fromJson(entry.value);
        restoredSessions[entry.key] = session;
      }

      _sessions.clear();
      _sessions.addAll(restoredSessions);

      for (final session in restoredSessions.values) {
        await _saveSession(session);
      }

      _sessionController.add(SessionEvent(
        type: SessionEventType.backupRestored,
        data: {
          'backup_id': backupId,
          'sessions_restored': backup.sessions.length,
        },
      ));

      debugPrint('Restored from backup: $backupId');
      return true;
    } catch (e, stack) {
      debugPrint('Failed to restore from backup: $e\n$stack');
      return false;
    }
  }

  List<SessionBackup> getAvailableBackups() {
    return _backups.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<CrashReport> getCrashReports() {
    return _crashReports.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void setAutoSaveEnabled(bool enabled) {
    _autoSaveEnabled = enabled;

    if (enabled && _autoSaveTimer == null) {
      _startAutoSave();
    } else if (!enabled && _autoSaveTimer != null) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
    }

    debugPrint('Auto-save ${enabled ? 'enabled' : 'disabled'}');
  }

  void setAutoSaveInterval(Duration interval) {
    _autoSaveInterval = interval;

    if (_autoSaveTimer != null) {
      _autoSaveTimer?.cancel();
      _startAutoSave();
    }

    debugPrint('Auto-save interval set to ${interval.inMinutes} minutes');
  }

  SessionStatistics getStatistics() {
    return SessionStatistics(
      activeSessions: _sessions.length,
      availableBackups: _backups.length,
      crashReports: _crashReports.length,
      autoSaveEnabled: _autoSaveEnabled,
      autoSaveInterval: _autoSaveInterval,
      recoveryMode: _recoveryMode,
      deviceId: _deviceId,
      oldestSession: _getOldestSession(),
      newestSession: _getNewestSession(),
    );
  }

  PersistedSessionRecord? _getOldestSession() {
    if (_sessions.isEmpty) return null;

    PersistedSessionRecord? oldest;
    for (final session in _sessions.values) {
      if (oldest == null || session.createdAt.isBefore(oldest.createdAt)) {
        oldest = session;
      }
    }

    return oldest;
  }

  PersistedSessionRecord? _getNewestSession() {
    if (_sessions.isEmpty) return null;

    PersistedSessionRecord? newest;
    for (final session in _sessions.values) {
      if (newest == null || session.createdAt.isAfter(newest.createdAt)) {
        newest = session;
      }
    }

    return newest;
  }

  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    _cleanupTimer?.cancel();

    await _saveAllSessions();
    await _createBackup();

    final dir = _sessionsDir;
    if (dir != null) {
      try {
        final crashIndicator = File('${dir.path}/.crash_indicator');
        if (await crashIndicator.exists()) {
          await crashIndicator.delete();
        }
      } catch (e, stack) {
        debugPrint('Failed to delete crash indicator: $e\n$stack');
      }
    }

    _sessions.clear();
    _sessionHistory.clear();
    _backups.clear();
    _crashReports.clear();

    await _sessionController.close();

    _isInitialized = false;
    debugPrint('Session Persistence disposed');
  }
}

class PersistedSessionRecord {
  final String id;
  String title;
  String workingDirectory;
  Map<String, String> environment;
  String? command;
  final DateTime createdAt;
  DateTime? lastActivity;
  bool isActive;
  String content;
  List<String> history;
  List<String> bookmarks;

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
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'working_directory': workingDirectory,
      'environment': environment,
      'command': command,
      'created_at': createdAt.toIso8601String(),
      'last_activity': lastActivity?.toIso8601String(),
      'is_active': isActive,
      'content': content,
      'history': history,
      'bookmarks': bookmarks,
    };
  }

  factory PersistedSessionRecord.fromJson(Map<String, dynamic> json) {
    return PersistedSessionRecord(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      workingDirectory: json['working_directory'] as String? ?? '',
      environment: _mapStringString(json['environment']),
      command: json['command'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      lastActivity: _parseDateTimeOptional(json['last_activity']),
      isActive: json['is_active'] as bool? ?? true,
      content: json['content'] as String? ?? '',
      history: _listString(json['history']),
      bookmarks: _listString(json['bookmarks']),
    );
  }
}

Map<String, String> _mapStringString(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((k, v) => MapEntry(k, v.toString()));
  }
  if (value is Map<dynamic, dynamic>) {
    return value.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  return {};
}

List<String> _listString(dynamic value) {
  if (value is List<dynamic>) {
    return value.map((e) => e.toString()).toList();
  }
  return [];
}

DateTime _parseDateTime(dynamic value) {
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }
  return DateTime.now();
}

DateTime? _parseDateTimeOptional(dynamic value) {
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
  return null;
}

class SessionSnapshot {
  final String sessionId;
  final DateTime timestamp;
  final Map<String, dynamic> state;

  SessionSnapshot({
    required this.sessionId,
    required this.timestamp,
    required this.state,
  });
}

class SessionBackup {
  final String id;
  final DateTime timestamp;
  final String deviceId;
  final Map<String, Map<String, dynamic>> sessions;
  final Map<String, dynamic> metadata;

  SessionBackup({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.sessions,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
      'sessions': sessions,
      'metadata': metadata,
    };
  }

  factory SessionBackup.fromJson(Map<String, dynamic> json) {
    return SessionBackup(
      id: json['id'] as String? ?? '',
      timestamp: _parseDateTime(json['timestamp']),
      deviceId: json['device_id'] as String? ?? '',
      sessions: _mapStringMap(json['sessions']),
      metadata: _mapDynamic(json['metadata']),
    );
  }
}

Map<String, Map<String, dynamic>> _mapStringMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((k, v) => MapEntry(k, v is Map<String, dynamic> ? v : <String, dynamic>{}));
  }
  if (value is Map<dynamic, dynamic>) {
    return value.map((k, v) => MapEntry(k.toString(), v is Map<String, dynamic> ? v : <String, dynamic>{}));
  }
  return {};
}

Map<String, dynamic> _mapDynamic(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<dynamic, dynamic>) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

class CrashReport {
  final String id;
  final DateTime timestamp;
  final String deviceId;
  final int activeSessions;
  final Map<String, dynamic> lastKnownState;
  final String error;

  CrashReport({
    required this.id,
    required this.timestamp,
    required this.deviceId,
    required this.activeSessions,
    required this.lastKnownState,
    required this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
      'active_sessions': activeSessions,
      'last_known_state': lastKnownState,
      'error': error,
    };
  }

  factory CrashReport.fromJson(Map<String, dynamic> json) {
    return CrashReport(
      id: json['id'] as String? ?? '',
      timestamp: _parseDateTime(json['timestamp']),
      deviceId: json['device_id'] as String? ?? '',
      activeSessions: json['active_sessions'] as int? ?? 0,
      lastKnownState: _mapDynamic(json['last_known_state']),
      error: json['error'] as String? ?? '',
    );
  }
}

class SessionEvent {
  final SessionEventType type;
  final String? sessionId;
  final Map<String, dynamic>? data;

  SessionEvent({
    required this.type,
    this.sessionId,
    this.data,
  });
}

class SessionStatistics {
  final int activeSessions;
  final int availableBackups;
  final int crashReports;
  final bool autoSaveEnabled;
  final Duration autoSaveInterval;
  final bool recoveryMode;
  final String? deviceId;
  final PersistedSessionRecord? oldestSession;
  final PersistedSessionRecord? newestSession;

  SessionStatistics({
    required this.activeSessions,
    required this.availableBackups,
    required this.crashReports,
    required this.autoSaveEnabled,
    required this.autoSaveInterval,
    required this.recoveryMode,
    this.deviceId,
    this.oldestSession,
    this.newestSession,
  });
}

enum SessionEventType {
  sessionCreated,
  sessionUpdated,
  sessionRemoved,
  autoSaved,
  backupCreated,
  backupRestored,
  crashDetected,
  recoveryCompleted,
}
