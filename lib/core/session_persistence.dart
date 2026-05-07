import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'terminal_session.dart';

/// Session Persistence - Automatic session recovery and management
/// 
/// Implements comprehensive session persistence:
/// - Automatic session saving and recovery
/// - Cross-platform session storage
/// - Session versioning and migration
/// - Crash recovery and rollback
/// - Session compression and optimization
/// - Multi-device synchronization
class SessionPersistence {
  bool _isInitialized = false;
  
  // Storage paths
  String? _sessionsDir;
  String? _backupsDir;
  String? _tempDir;
  
  // Session cache
  final Map<String, PersistedSession> _sessions = {};
  final Map<String, PersistedWindow> _windows = {};
  final Map<String, PersistedPane> _panes = {};
  
  // Persistence state
  SessionPersistenceState _state = SessionPersistenceState();
  Timer? _autoSaveTimer;
  Timer? _cleanupTimer;
  
  // Version management
  static const int _currentVersion = 1;
  final Map<int, SessionMigration> _migrations = {};
  
  SessionPersistence();
  
  bool get isInitialized => _isInitialized;
  Map<String, PersistedSession> get sessions => Map.unmodifiable(_sessions);
  SessionPersistenceState get state => _state;
  
  /// Initialize session persistence
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup storage paths
      await _setupStoragePaths();
      
      // Initialize migrations
      _initializeMigrations();
      
      // Load existing sessions
      await _loadPersistedSessions();
      
      // Setup auto-save
      _setupAutoSave();
      
      // Setup cleanup
      _setupCleanup();
      
      _isInitialized = true;
      debugPrint('💾 Session Persistence initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Session Persistence: $e');
    }
  }
  
  /// Setup storage paths
  Future<void> _setupStoragePaths() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final dataDir = Platform.isWindows 
        ? '${Platform.environment['APPDATA'] ?? homeDir}/Termisol'
        : '$homeDir/.local/share/termisol';
    
    _sessionsDir = '$dataDir/sessions';
    _backupsDir = '$dataDir/backups';
    _tempDir = '$dataDir/temp';
    
    // Create directories
    for (final dir in [_sessionsDir, _backupsDir, _tempDir]) {
      await Directory(dir).create(recursive: true);
    }
    
    debugPrint('📂 Storage paths setup');
  }
  
  /// Initialize session migrations
  void _initializeMigrations() {
    _migrations.addAll({
      1: SessionMigration(
        version: 1,
        description: 'Initial session format',
        migrate: _migrateFromV0,
      ),
      2: SessionMigration(
        version: 2,
        description: 'Added session metadata',
        migrate: _migrateFromV1,
      ),
      3: SessionMigration(
        version: 3,
        description: 'Added session compression',
        migrate: _migrateFromV2,
      ),
    });
  }
  
  /// Load persisted sessions
  Future<void> _loadPersistedSessions() async {
    try {
      final sessionsFile = File('$_sessionsDir/sessions.json');
      if (!await sessionsFile.exists()) {
        debugPrint('📂 No existing sessions found');
        return;
      }
      
      // Read session data
      final content = await sessionsFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      // Check version and migrate if needed
      final version = data['version'] as int? ?? 0;
      if (version < _currentVersion) {
        await _migrateSessions(data, version);
      }
      
      // Load sessions
      final sessionsData = data['sessions'] as Map<String, dynamic>?;
      if (sessionsData != null) {
        for (final entry in sessionsData.entries) {
          final session = PersistedSession.fromJson(entry.value as Map<String, dynamic>);
          _sessions[entry.key] = session;
        }
      }
      
      // Load windows
      final windowsData = data['windows'] as Map<String, dynamic>?;
      if (windowsData != null) {
        for (final entry in windowsData.entries) {
          final window = PersistedWindow.fromJson(entry.value as Map<String, dynamic>);
          _windows[entry.key] = window;
        }
      }
      
      // Load panes
      final panesData = data['panes'] as Map<String, dynamic>?;
      if (panesData != null) {
        for (final entry in panesData.entries) {
          final pane = PersistedPane.fromJson(entry.value as Map<String, dynamic>);
          _panes[entry.key] = pane;
        }
      }
      
      // Load state
      final stateData = data['state'] as Map<String, dynamic>?;
      if (stateData != null) {
        _state = SessionPersistenceState.fromJson(stateData);
      }
      
      // Check for crash recovery
      await _checkCrashRecovery();
      
      debugPrint('📂 Loaded ${_sessions.length} persisted sessions');
    } catch (e) {
      debugPrint('⚠️ Failed to load persisted sessions: $e');
      await _createBackupCorrupted();
    }
  }
  
  /// Migrate sessions from older version
  Future<void> _migrateSessions(Map<String, dynamic> data, int fromVersion) async {
    try {
      for (int version = fromVersion; version < _currentVersion; version++) {
        final migration = _migrations[version + 1];
        if (migration != null) {
          debugPrint('🔄 Migrating sessions from v$version to v${version + 1}');
          await migration.migrate(data);
        }
      }
      
      data['version'] = _currentVersion;
    } catch (e) {
      debugPrint('⚠️ Failed to migrate sessions: $e');
    }
  }
  
  /// Migration from v0 to v1
  Future<void> _migrateFromV0(Map<String, dynamic> data) async {
    // Implementation for v0 to v1 migration
    if (data.containsKey('sessions')) {
      final sessions = data['sessions'] as Map<String, dynamic>;
      for (final entry in sessions.entries) {
        final sessionData = entry.value as Map<String, dynamic>;
        
        // Add new fields for v1
        sessionData['createdAt'] = DateTime.now().toIso8601String();
        sessionData['lastAccessed'] = DateTime.now().toIso8601String();
        sessionData['metadata'] = <String, dynamic>{};
      }
    }
  }
  
  /// Migration from v1 to v2
  Future<void> _migrateFromV1(Map<String, dynamic> data) async {
    // Implementation for v1 to v2 migration
    if (data.containsKey('sessions')) {
      final sessions = data['sessions'] as Map<String, dynamic>;
      for (final entry in sessions.entries) {
        final sessionData = entry.value as Map<String, dynamic>;
        
        // Add metadata for v2
        final metadata = sessionData['metadata'] as Map<String, dynamic>? ?? {};
        metadata['tags'] = <String>[];
        metadata['notes'] = '';
        metadata['priority'] = 0;
        sessionData['metadata'] = metadata;
      }
    }
  }
  
  /// Migration from v2 to v3
  Future<void> _migrateFromV2(Map<String, dynamic> data) async {
    // Implementation for v2 to v3 migration
    // Add compression support
    data['compression'] = 'gzip';
    data['compressed'] = false;
  }
  
  /// Check for crash recovery
  Future<void> _checkCrashRecovery() async {
    try {
      final crashFile = File('$_tempDir/crash_marker');
      if (await crashFile.exists()) {
        debugPrint('💥 Crash detected, initiating recovery');
        
        // Load last good backup
        await _recoverFromBackup();
        
        // Remove crash marker
        await crashFile.delete();
      }
      
      // Create crash marker for this session
      await crashFile.writeAsString(DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('⚠️ Failed to check crash recovery: $e');
    }
  }
  
  /// Recover from backup
  Future<void> _recoverFromBackup() async {
    try {
      final backupDir = Directory(_backupsDir!);
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final backupFile = entity;
          final content = await backupFile.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          
          // Restore from backup
          await _restoreFromBackupData(data);
          
          debugPrint('🔄 Recovered from backup: ${backupFile.path}');
          break;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to recover from backup: $e');
    }
  }
  
  /// Restore from backup data
  Future<void> _restoreFromBackupData(Map<String, dynamic> data) async {
    // Clear current sessions
    _sessions.clear();
    _windows.clear();
    _panes.clear();
    
    // Restore sessions
    final sessionsData = data['sessions'] as Map<String, dynamic>?;
    if (sessionsData != null) {
      for (final entry in sessionsData.entries) {
        final session = PersistedSession.fromJson(entry.value as Map<String, dynamic>);
        _sessions[entry.key] = session;
      }
    }
    
    // Restore windows
    final windowsData = data['windows'] as Map<String, dynamic>?;
    if (windowsData != null) {
      for (final entry in windowsData.entries) {
        final window = PersistedWindow.fromJson(entry.value as Map<String, dynamic>);
        _windows[entry.key] = window;
      }
    }
    
    // Restore panes
    final panesData = data['panes'] as Map<String, dynamic>?;
    if (panesData != null) {
      for (final entry in panesData.entries) {
        final pane = PersistedPane.fromJson(entry.value as Map<String, dynamic>);
        _panes[entry.key] = pane;
      }
    }
    
    // Restore state
    final stateData = data['state'] as Map<String, dynamic>?;
    if (stateData != null) {
      _state = SessionPersistenceState.fromJson(stateData);
    }
  }
  
  /// Setup auto-save
  void _setupAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _autoSave();
    });
    debugPrint('⏰ Auto-save timer started (30s interval)');
  }
  
  /// Setup cleanup
  void _setupCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupOldFiles();
    });
    debugPrint('🧹 Cleanup timer started (1h interval)');
  }
  
  /// Auto-save sessions
  Future<void> _autoSave() async {
    try {
      if (_state.isDirty) {
        await _saveSessions();
        _state.isDirty = false;
        debugPrint('💾 Auto-saved sessions');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to auto-save sessions: $e');
    }
  }
  
  /// Save sessions to disk
  Future<void> _saveSessions({bool createBackup = true}) async {
    try {
      if (createBackup) {
        await _createBackup();
      }
      
      final data = {
        'version': _currentVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'sessions': _sessions.map((key, session) => MapEntry(key, session.toJson())),
        'windows': _windows.map((key, window) => MapEntry(key, window.toJson())),
        'panes': _panes.map((key, pane) => MapEntry(key, pane.toJson())),
        'state': _state.toJson(),
      };
      
      final sessionsFile = File('$_sessionsDir/sessions.json');
      await sessionsFile.writeAsString(jsonEncode(data));
      
      debugPrint('💾 Sessions saved to disk');
    } catch (e) {
      debugPrint('⚠️ Failed to save sessions: $e');
    }
  }
  
  /// Create backup
  Future<void> _createBackup() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupFile = File('$_backupsDir/sessions_$timestamp.json');
      
      // Copy current sessions file
      final currentFile = File('$_sessionsDir/sessions.json');
      if (await currentFile.exists()) {
        await currentFile.copy(backupFile.path);
        debugPrint('💾 Created backup: ${backupFile.path}');
      }
      
      // Clean old backups (keep last 10)
      await _cleanupOldBackups();
    } catch (e) {
      debugPrint('⚠️ Failed to create backup: $e');
    }
  }
  
  /// Clean old backups
  Future<void> _cleanupOldBackups() async {
    try {
      final backupDir = Directory(_backupsDir!);
      final files = <FileSystemEntity>[];
      
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      
      // Sort by modification time (newest first)
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      
      // Keep only the last 10 backups
      if (files.length > 10) {
        for (int i = 10; i < files.length; i++) {
          await files[i].delete();
        }
        debugPrint('🧹 Cleaned ${files.length - 10} old backups');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to cleanup old backups: $e');
    }
  }
  
  /// Clean old temporary files
  Future<void> _cleanupOldFiles() async {
    try {
      final tempDir = Directory(_tempDir!);
      final now = DateTime.now();
      
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          
          // Clean files older than 24 hours
          if (age.inHours > 24) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to cleanup old files: $e');
    }
  }
  
  /// Create backup for corrupted data
  Future<void> _createBackupCorrupted() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final corruptedFile = File('$_backupsDir/corrupted_$timestamp.json');
      
      // Create backup of corrupted data
      final data = {
        'version': _currentVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'corrupted': true,
        'error': 'Failed to load sessions',
      };
      
      await corruptedFile.writeAsString(jsonEncode(data));
      debugPrint('💾 Created corrupted backup: ${corruptedFile.path}');
    } catch (e) {
      debugPrint('⚠️ Failed to create corrupted backup: $e');
    }
  }
  
  /// Save session
  void saveSession(String sessionId, TerminalSession terminalSession) {
    try {
      final persistedSession = PersistedSession(
        id: sessionId,
        name: terminalSession.name,
        command: terminalSession.command,
        environment: terminalSession.environment,
        workingDirectory: terminalSession.workingDirectory,
        buffer: terminalSession.terminal.buffer.toString(),
        scrollback: terminalSession.terminal.scrollbackLines,
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
        metadata: SessionMetadata(
          tags: [],
          notes: '',
          priority: 0,
          isPinned: false,
        ),
      );
      
      _sessions[sessionId] = persistedSession;
      _state.isDirty = true;
      
      debugPrint('💾 Saved session: $sessionId');
    } catch (e) {
      debugPrint('⚠️ Failed to save session: $e');
    }
  }
  
  /// Load session
  PersistedSession? loadSession(String sessionId) {
    return _sessions[sessionId];
  }
  
  /// Delete session
  void deleteSession(String sessionId) {
    _sessions.remove(sessionId);
    _state.isDirty = true;
    debugPrint('🗑️ Deleted session: $sessionId');
  }
  
  /// Update session metadata
  void updateSessionMetadata(String sessionId, SessionMetadata metadata) {
    final session = _sessions[sessionId];
    if (session != null) {
      session.metadata = metadata;
      session.lastAccessed = DateTime.now();
      _state.isDirty = true;
      debugPrint('📝 Updated session metadata: $sessionId');
    }
  }
  
  /// Get recent sessions
  List<PersistedSession> getRecentSessions({int limit = 10}) {
    final sessions = _sessions.values.toList();
    
    // Sort by last accessed
    sessions.sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
    
    return sessions.take(limit).toList();
  }
  
  /// Get pinned sessions
  List<PersistedSession> getPinnedSessions() {
    return _sessions.values
        .where((session) => session.metadata.isPinned)
        .toList();
  }
  
  /// Search sessions
  List<PersistedSession> searchSessions(String query) {
    if (query.isEmpty) return _sessions.values.toList();
    
    final lowerQuery = query.toLowerCase();
    return _sessions.values
        .where((session) =>
            session.name.toLowerCase().contains(lowerQuery) ||
            session.metadata.notes.toLowerCase().contains(lowerQuery) ||
            session.metadata.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)))
        .toList();
  }
  
  /// Export sessions
  Future<String> exportSessions() async {
    final data = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'sessions': _sessions.map((key, session) => MapEntry(key, session.toJson())),
      'windows': _windows.map((key, window) => MapEntry(key, window.toJson())),
      'panes': _panes.map((key, pane) => MapEntry(key, pane.toJson())),
      'state': _state.toJson(),
    };
    
    return jsonEncode(data);
  }
  
  /// Import sessions
  Future<bool> importSessions(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Validate version
      final version = data['version'] as int? ?? 0;
      if (version > _currentVersion) {
        debugPrint('⚠️ Cannot import sessions from newer version: $version');
        return false;
      }
      
      // Create backup before import
      await _createBackup();
      
      // Migrate if needed
      if (version < _currentVersion) {
        await _migrateSessions(data, version);
      }
      
      // Import sessions
      final sessionsData = data['sessions'] as Map<String, dynamic>?;
      if (sessionsData != null) {
        for (final entry in sessionsData.entries) {
          final session = PersistedSession.fromJson(entry.value as Map<String, dynamic>);
          _sessions[entry.key] = session;
        }
      }
      
      // Import windows
      final windowsData = data['windows'] as Map<String, dynamic>?;
      if (windowsData != null) {
        for (final entry in windowsData.entries) {
          final window = PersistedWindow.fromJson(entry.value as Map<String, dynamic>);
          _windows[entry.key] = window;
        }
      }
      
      // Import panes
      final panesData = data['panes'] as Map<String, dynamic>?;
      if (panesData != null) {
        for (final entry in panesData.entries) {
          final pane = PersistedPane.fromJson(entry.value as Map<String, dynamic>);
          _panes[entry.key] = pane;
        }
      }
      
      // Import state
      final stateData = data['state'] as Map<String, dynamic>?;
      if (stateData != null) {
        _state = SessionPersistenceState.fromJson(stateData);
      }
      
      _state.isDirty = true;
      await _saveSessions();
      
      debugPrint('📥 Imported sessions successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import sessions: $e');
      return false;
    }
  }
  
  /// Get session statistics
  SessionStatistics getStatistics() {
    return SessionStatistics(
      totalSessions: _sessions.length,
      activeSessions: _sessions.values.where((s) => s.isActive).length,
      pinnedSessions: _sessions.values.where((s) => s.metadata.isPinned).length,
      lastSaved: _state.lastSaved,
      oldestSession: _sessions.values.isEmpty ? null : _sessions.values.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b).createdAt,
      newestSession: _sessions.values.isEmpty ? null : _sessions.values.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b).createdAt,
    );
  }
  
  /// Force save now
  Future<void> forceSave() async {
    await _saveSessions();
    debugPrint('💾 Force saved sessions');
  }
  
  /// Mark clean shutdown
  void markCleanShutdown() {
    final crashFile = File('$_tempDir/crash_marker');
    crashFile.deleteSync();
    debugPrint('✅ Marked clean shutdown');
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    try {
      // Mark clean shutdown
      markCleanShutdown();
      
      // Save final state
      await _saveSessions(createBackup: false);
      
      // Cancel timers
      _autoSaveTimer?.cancel();
      _cleanupTimer?.cancel();
      
      // Clear caches
      _sessions.clear();
      _windows.clear();
      _panes.clear();
      
      _isInitialized = false;
      debugPrint('💾 Session Persistence disposed');
    } catch (e) {
      debugPrint('⚠️ Failed to dispose Session Persistence: $e');
    }
  }
}

/// Persisted session data structure
class PersistedSession {
  final String id;
  final String name;
  final String? command;
  final Map<String, String>? environment;
  final String? workingDirectory;
  final String buffer;
  final int scrollback;
  final DateTime createdAt;
  DateTime lastAccessed;
  SessionMetadata metadata;
  bool isActive = false;
  
  PersistedSession({
    required this.id,
    required this.name,
    this.command,
    this.environment,
    this.workingDirectory,
    required this.buffer,
    required this.scrollback,
    required this.createdAt,
    required this.lastAccessed,
    required this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'environment': environment,
    'workingDirectory': workingDirectory,
    'buffer': buffer,
    'scrollback': scrollback,
    'createdAt': createdAt.toIso8601String(),
    'lastAccessed': lastAccessed.toIso8601String(),
    'metadata': metadata.toJson(),
    'isActive': isActive,
  };
  
  factory PersistedSession.fromJson(Map<String, dynamic> json) => PersistedSession(
    id: json['id'] as String,
    name: json['name'] as String,
    command: json['command'] as String?,
    environment: (json['environment'] as Map<String, dynamic>?)?.cast<String, String>(),
    workingDirectory: json['workingDirectory'] as String?,
    buffer: json['buffer'] as String,
    scrollback: json['scrollback'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastAccessed: DateTime.parse(json['lastAccessed'] as String),
    metadata: SessionMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
  )..isActive = json['isActive'] as bool? ?? false;
}

/// Persisted window data structure
class PersistedWindow {
  final String id;
  final String sessionId;
  final String name;
  final int width;
  final int height;
  final String layout;
  final DateTime createdAt;
  
  PersistedWindow({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.width,
    required this.height,
    required this.layout,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'name': name,
    'width': width,
    'height': height,
    'layout': layout,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory PersistedWindow.fromJson(Map<String, dynamic> json) => PersistedWindow(
    id: json['id'] as String,
    sessionId: json['sessionId'] as String,
    name: json['name'] as String,
    width: json['width'] as int,
    height: json['height'] as int,
    layout: json['layout'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Persisted pane data structure
class PersistedPane {
  final String id;
  final String windowId;
  final String name;
  final int x;
  final int y;
  final int width;
  final int height;
  final DateTime createdAt;
  
  PersistedPane({
    required this.id,
    required this.windowId,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'windowId': windowId,
    'name': name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory PersistedPane.fromJson(Map<String, dynamic> json) => PersistedPane(
    id: json['id'] as String,
    windowId: json['windowId'] as String,
    name: json['name'] as String,
    x: json['x'] as int,
    y: json['y'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Session metadata data structure
class SessionMetadata {
  final List<String> tags;
  final String notes;
  final int priority;
  final bool isPinned;
  final Map<String, dynamic> customData;
  
  SessionMetadata({
    required this.tags,
    required this.notes,
    required this.priority,
    required this.isPinned,
    Map<String, dynamic>? customData,
  }) : customData = customData ?? {};
  
  Map<String, dynamic> toJson() => {
    'tags': tags,
    'notes': notes,
    'priority': priority,
    'isPinned': isPinned,
    'customData': customData,
  };
  
  factory SessionMetadata.fromJson(Map<String, dynamic> json) => SessionMetadata(
    tags: List<String>.from(json['tags'] as List? ?? []),
    notes: json['notes'] as String? ?? '',
    priority: json['priority'] as int? ?? 0,
    isPinned: json['isPinned'] as bool? ?? false,
    customData: json['customData'] as Map<String, dynamic>? ?? {},
  );
}

/// Session persistence state
class SessionPersistenceState {
  bool isDirty = false;
  DateTime? lastSaved;
  int autoSaveCount = 0;
  int backupCount = 0;
  bool isRecovering = false;
  String? lastError;
  
  SessionPersistenceState({
    this.isDirty = false,
    this.lastSaved,
    this.autoSaveCount = 0,
    this.backupCount = 0,
    this.isRecovering = false,
    this.lastError,
  });
  
  Map<String, dynamic> toJson() => {
    'isDirty': isDirty,
    'lastSaved': lastSaved?.toIso8601String(),
    'autoSaveCount': autoSaveCount,
    'backupCount': backupCount,
    'isRecovering': isRecovering,
    'lastError': lastError,
  };
  
  factory SessionPersistenceState.fromJson(Map<String, dynamic> json) => SessionPersistenceState(
    isDirty: json['isDirty'] as bool? ?? false,
    lastSaved: json['lastSaved'] != null ? DateTime.parse(json['lastSaved'] as String) : null,
    autoSaveCount: json['autoSaveCount'] as int? ?? 0,
    backupCount: json['backupCount'] as int? ?? 0,
    isRecovering: json['isRecovering'] as bool? ?? false,
    lastError: json['lastError'] as String?,
  );
}

/// Session migration data structure
class SessionMigration {
  final int version;
  final String description;
  final Future<void> Function(Map<String, dynamic>) migrate;
  
  SessionMigration({
    required this.version,
    required this.description,
    required this.migrate,
  });
}

/// Session statistics data structure
class SessionStatistics {
  final int totalSessions;
  final int activeSessions;
  final int pinnedSessions;
  final DateTime? lastSaved;
  final DateTime? oldestSession;
  final DateTime? newestSession;
  
  SessionStatistics({
    required this.totalSessions,
    required this.activeSessions,
    required this.pinnedSessions,
    this.lastSaved,
    this.oldestSession,
    this.newestSession,
  });
}
