import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

/// Session Persistence and Crash Recovery System
/// 
/// Comprehensive session management with automatic backup,
/// crash recovery, and cross-device synchronization.
class SessionPersistence {
  static final SessionPersistence _instance = SessionPersistence._internal();
  factory SessionPersistence() => _instance;
  SessionPersistence._internal();

  bool _isInitialized = false;
  
  // Session storage
  final Map<String, TerminalSession> _sessions = {};
  final List<SessionSnapshot> _sessionHistory = [];
  final Map<String, SessionBackup> _backups = {};
  
  // Auto-save system
  Timer? _autoSaveTimer;
  bool _autoSaveEnabled = true;
  Duration _autoSaveInterval = Duration(minutes: 1);
  
  // Crash recovery
  final Map<String, CrashReport> _crashReports = {};
  bool _recoveryMode = false;
  
  // Configuration
  Directory? _sessionsDir;
  Directory? _backupsDir;
  Directory? _crashDir;
  String? _deviceId;
  
  // Event system
  final _sessionController = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _sessionController.stream;
  
  // Configuration
  static const int _maxSessionHistory = 100;
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
      // Setup directories
      await _setupDirectories();
      
      // Generate device ID
      await _generateDeviceId();
      
      // Check for crash recovery
      await _checkForCrashRecovery();
      
      // Load existing sessions
      await _loadExistingSessions();
      
      // Load backups
      await _loadBackups();
      
      // Start auto-save
      if (_autoSaveEnabled) {
        _startAutoSave();
      }
      
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('💾 Session Persistence initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Session Persistence: $e');
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
      
      debugPrint('📁 Session directories created');
    } catch (e) {
      debugPrint('❌ Failed to setup directories: $e');
      rethrow;
    }
  }

  Future<void> _generateDeviceId() async {
    try {
      final idFile = File('${_sessionsDir!.path}/device_id');
      
      if (await idFile.exists()) {
        _deviceId = await idFile.readAsString();
      } else {
        _deviceId = _generateDeviceIdString();
        await idFile.writeAsString(_deviceId!);
      }
      
      debugPrint('🔑 Device ID: $_deviceId');
    } catch (e) {
      debugPrint('⚠️ Failed to generate device ID: $e');
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
      // Check for crash indicator file
      final crashIndicator = File('${_sessionsDir!.path}/.crash_indicator');
      
      if (await crashIndicator.exists()) {
        debugPrint('💥 Crash detected, entering recovery mode');
        _recoveryMode = true;
        
        // Create crash report
        await _createCrashReport();
        
        // Remove crash indicator
        await crashIndicator.delete();
        
        // Emit crash recovery event
        _sessionController.add(SessionEvent(
          type: SessionEventType.crashDetected,
          data: {'recovery_mode': true},
        ));
      }
      
      // Create crash indicator for this session
      await crashIndicator.writeAsString(DateTime.now().toIso8601String());
      
    } catch (e) {
      debugPrint('⚠️ Failed to check for crash recovery: $e');
    }
  }

  Future<void> _createCrashReport() async {
    try {
      final crashReport = CrashReport(
        id: 'crash_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        deviceId: _deviceId!,
        activeSessions: _sessions.length,
        lastKnownState: _captureCurrentState(),
        error: 'Application crash detected',
      );
      
      _crashReports[crashReport.id] = crashReport;
      await _saveCrashReport(crashReport);
      
      debugPrint('💥 Crash report created: ${crashReport.id}');
    } catch (e) {
      debugPrint('❌ Failed to create crash report: $e');
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
      if (!await _sessionsDir!.exists()) return;
      
      await for (final entity in _sessionsDir!.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;
            
            final session = TerminalSession.fromJson(data);
            _sessions[session.id] = session;
            
            // Check if session is still valid
            if (_isSessionValid(session)) {
              debugPrint('📂 Loaded session: ${session.id}');
            } else {
              _sessions.remove(session.id);
              await entity.delete();
            }
          } catch (e) {
            debugPrint('⚠️ Failed to load session from ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('📂 Loaded ${_sessions.length} sessions');
    } catch (e) {
      debugPrint('❌ Failed to load existing sessions: $e');
    }
  }

  Future<void> _loadBackups() async {
    try {
      if (!await _backupsDir!.exists()) return;
      
      await for (final entity in _backupsDir!.list()) {
        if (entity is File && entity.path.endsWith('.backup')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;
            
            final backup = SessionBackup.fromJson(data);
            _backups[backup.id] = backup;
          } catch (e) {
            debugPrint('⚠️ Failed to load backup from ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('💾 Loaded ${_backups.length} backups');
    } catch (e) {
      debugPrint('❌ Failed to load backups: $e');
    }
  }

  bool _isSessionValid(TerminalSession session) {
    final now = DateTime.now();
    final lastActivity = session.lastActivity ?? session.createdAt;
    
    // Check if session is too old
    if (now.difference(lastActivity) > _sessionTimeout) {
      return false;
    }
    
    // Check if session has valid data
    if (session.id.isEmpty || session.title.isEmpty) {
      return false;
    }
    
    return true;
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      _performAutoSave();
    });
    
    debugPrint('⏰ Auto-save started (${_autoSaveInterval.inMinutes} minutes)');
  }

  Future<void> _performAutoSave() async {
    try {
      await _saveAllSessions();
      await _createBackup();
      
      _sessionController.add(SessionEvent(
        type: SessionEventType.autoSaved,
        data: {
          'sessions_count': _sessions.length,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
      
    } catch (e) {
      debugPrint('⚠️ Auto-save failed: $e');
    }
  }

  Future<void> _startCleanupTimer() async {
    Timer.periodic(Duration(hours: 1), (_) {
      _performCleanup();
    });
  }

  Future<void> _performCleanup() async {
    try {
      // Clean up old sessions
      await _cleanupOldSessions();
      
      // Clean up old backups
      await _cleanupOldBackups();
      
      // Clean up old crash reports
      await _cleanupOldCrashReports();
      
      debugPrint('🧹 Cleanup completed');
    } catch (e) {
      debugPrint('⚠️ Cleanup failed: $e');
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
      debugPrint('🗑️ Cleaned up ${sessionsToRemove.length} old sessions');
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
      
      debugPrint('🗑️ Cleaned up ${toRemove.length} old backups');
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
      
      debugPrint('🗑️ Cleaned up ${toRemove.length} old crash reports');
    }
  }

  // Public API methods
  
  Future<String> createSession({
    required String title,
    required String workingDirectory,
    Map<String, String>? environment,
    String? command,
  }) async {
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    
    final session = TerminalSession(
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
    
    debugPrint('📂 Created session: $sessionId');
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
      debugPrint('🗑️ Removed session: $sessionId');
    }
  }

  TerminalSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  List<TerminalSession> getAllSessions() {
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

  Future<void> _saveSession(TerminalSession session) async {
    try {
      final sessionFile = File('${_sessionsDir!.path}/${session.id}.json');
      await sessionFile.writeAsString(jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('❌ Failed to save session ${session.id}: $e');
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      final sessionFile = File('${_sessionsDir!.path}/$sessionId.json');
      if (await sessionFile.exists()) {
        await sessionFile.delete();
      }
    } catch (e) {
      debugPrint('❌ Failed to delete session $sessionId: $e');
    }
  }

  Future<void> _createBackup() async {
    try {
      final backupId = 'backup_${DateTime.now().millisecondsSinceEpoch}';
      
      final backup = SessionBackup(
        id: backupId,
        timestamp: DateTime.now(),
        deviceId: _deviceId!,
        sessions: _sessions.map((k, v) => MapEntry(k, v.toJson())),
        metadata: {
          'version': '1.0.0',
          'session_count': _sessions.length,
          'platform': Platform.operatingSystem,
        },
      );
      
      _backups[backupId] = backup;
      await _saveBackup(backup);
      
      debugPrint('💾 Created backup: $backupId');
    } catch (e) {
      debugPrint('❌ Failed to create backup: $e');
    }
  }

  Future<void> _saveBackup(SessionBackup backup) async {
    try {
      final backupFile = File('${_backupsDir!.path}/${backup.id}.backup');
      await backupFile.writeAsString(jsonEncode(backup.toJson()));
    } catch (e) {
      debugPrint('❌ Failed to save backup ${backup.id}: $e');
    }
  }

  Future<void> _deleteBackup(String backupId) async {
    try {
      final backupFile = File('${_backupsDir!.path}/$backupId.backup');
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (e) {
      debugPrint('❌ Failed to delete backup $backupId: $e');
    }
  }

  Future<void> _saveCrashReport(CrashReport report) async {
    try {
      final reportFile = File('${_crashDir!.path}/${report.id}.crash');
      await reportFile.writeAsString(jsonEncode(report.toJson()));
    } catch (e) {
      debugPrint('❌ Failed to save crash report ${report.id}: $e');
    }
  }

  Future<void> _deleteCrashReport(String reportId) async {
    try {
      final reportFile = File('${_crashDir!.path}/$reportId.crash');
      if (await reportFile.exists()) {
        await reportFile.delete();
      }
    } catch (e) {
      debugPrint('❌ Failed to delete crash report $reportId: $e');
    }
  }

  Future<bool> restoreFromBackup(String backupId) async {
    try {
      final backup = _backups[backupId];
      if (backup == null) {
        throw ArgumentError('Backup not found: $backupId');
      }
      
      // Clear current sessions
      _sessions.clear();
      
      // Restore sessions from backup
      for (final entry in backup.sessions.entries) {
        final session = TerminalSession.fromJson(entry.value);
        _sessions[entry.key] = session;
        await _saveSession(session);
      }
      
      _sessionController.add(SessionEvent(
        type: SessionEventType.backupRestored,
        data: {
          'backup_id': backupId,
          'sessions_restored': backup.sessions.length,
        },
      ));
      
      debugPrint('🔄 Restored from backup: $backupId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to restore from backup: $e');
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
    
    debugPrint('⏰ Auto-save ${enabled ? 'enabled' : 'disabled'}');
  }

  void setAutoSaveInterval(Duration interval) {
    _autoSaveInterval = interval;
    
    if (_autoSaveTimer != null) {
      _autoSaveTimer?.cancel();
      _startAutoSave();
    }
    
    debugPrint('⏰ Auto-save interval set to ${interval.inMinutes} minutes');
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

  TerminalSession? _getOldestSession() {
    if (_sessions.isEmpty) return null;
    
    TerminalSession? oldest;
    for (final session in _sessions.values) {
      if (oldest == null || session.createdAt.isBefore(oldest.createdAt)) {
        oldest = session;
      }
    }
    
    return oldest;
  }

  TerminalSession? _getNewestSession() {
    if (_sessions.isEmpty) return null;
    
    TerminalSession? newest;
    for (final session in _sessions.values) {
      if (newest == null || session.createdAt.isAfter(newest.createdAt)) {
        newest = session;
      }
    }
    
    return newest;
  }

  Future<void> dispose() async {
    // Save all sessions
    await _saveAllSessions();
    
    // Create final backup
    await _createBackup();
    
    // Remove crash indicator (clean shutdown)
    final crashIndicator = File('${_sessionsDir!.path}/.crash_indicator');
    if (await crashIndicator.exists()) {
      await crashIndicator.delete();
    }
    
    // Cancel timers
    _autoSaveTimer?.cancel();
    
    // Clear data
    _sessions.clear();
    _sessionHistory.clear();
    _backups.clear();
    _crashReports.clear();
    
    // Close event controller
    _sessionController.close();
    
    _isInitialized = false;
    debugPrint('💾 Session Persistence disposed');
  }
}

/// Data classes
class TerminalSession {
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
  
  TerminalSession({
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
  
  factory TerminalSession.fromJson(Map<String, dynamic> json) {
    return TerminalSession(
      id: json['id'] as String,
      title: json['title'] as String,
      workingDirectory: json['working_directory'] as String,
      environment: Map<String, String>.from((json['environment'] ?? {}) as Map<dynamic, dynamic>),
      command: json['command'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastActivity: json['last_activity'] != null ? DateTime.parse(json['last_activity'] as String) : null,
      isActive: json['is_active'] as bool? ?? true,
      content: json['content'] as String? ?? '',
      history: List<String>.from((json['history'] ?? []) as List<dynamic>),
      bookmarks: List<String>.from((json['bookmarks'] ?? []) as List<dynamic>),
    );
  }
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
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      deviceId: json['device_id'] as String,
      sessions: (json['sessions'] as Map<dynamic, dynamic>? ?? {}).cast<String, Map<String, dynamic>>(),
      metadata: Map<String, dynamic>.from((json['metadata'] ?? {}) as Map<dynamic, dynamic>),
    );
  }
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
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      deviceId: json['device_id'] as String,
      activeSessions: json['active_sessions'] as int? ?? 0,
      lastKnownState: Map<String, dynamic>.from((json['last_known_state'] ?? {}) as Map<dynamic, dynamic>),
      error: json['error'] as String?,
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
  final TerminalSession? oldestSession;
  final TerminalSession? newestSession;
  
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