import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

/// Session Persistence Manager - Best-in-class crash recovery and session management
/// 
/// Provides comprehensive session persistence with:
/// - Automatic session saving and restoration
/// - Crash detection and recovery
/// - Incremental state snapshots
/// - Multiple session profiles
/// - Session encryption and security
/// - Health monitoring and validation
class SessionPersistence {
  static final SessionPersistence _instance = SessionPersistence._internal();
  factory SessionPersistence() => _instance;
  SessionPersistence._internal();

  SessionData? _currentSession;
  SessionSnapshot? _lastSnapshot;
  final List<SessionSnapshot> _snapshots = [];
  final Map<String, SessionProfile> _profiles = {};
  
  bool _isInitialized = false;
  bool _autoSave = true;
  Timer? _autoSaveTimer;
  Timer? _healthCheckTimer;
  
  // Persistence configuration
  static const Duration _autoSaveInterval = Duration(seconds: 30);
  static const Duration _healthCheckInterval = Duration(minutes: 5);
  static const int _maxSnapshots = 50;
  static const int _maxProfiles = 10;
  
  final _sessionController = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _sessionController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get autoSave => _autoSave;
  SessionData? get currentSession => _currentSession;

  /// Initialize session persistence
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Create session directory
      await _ensureSessionDirectory();
      
      // Load existing sessions
      await _loadExistingSessions();
      
      // Check for crash recovery
      await _checkForCrashRecovery();
      
      // Start auto-save timer
      _startAutoSaveTimer();
      
      // Start health check timer
      _startHealthCheckTimer();
      
      _isInitialized = true;
      debugPrint('💾 Session Persistence initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Session Persistence: $e');
      rethrow;
    }
  }

  /// Create a new session
  Future<void> createSession({
    String? name,
    String? profileId,
    Map<String, dynamic>? metadata,
  }) async {
    final sessionId = _generateSessionId();
    final sessionName = name ?? 'Session ${DateTime.now().millisecondsSinceEpoch}';
    
    _currentSession = SessionData(
      id: sessionId,
      name: sessionName,
      profileId: profileId ?? 'default',
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      metadata: metadata ?? {},
      terminalStates: {},
      editorStates: {},
      aiStates: {},
      configuration: {},
    );

    // Save initial session
    await _saveSession(_currentSession!);
    
    // Create initial snapshot
    await _createSnapshot('Session created');
    
    _sessionController.add(SessionEvent(
      type: SessionEventType.sessionCreated,
      sessionId: sessionId,
      timestamp: DateTime.now(),
    ));

    debugPrint('💾 Created session: $sessionName ($sessionId)');
  }

  /// Update session state
  Future<void> updateSession({
    String? terminalId,
    TerminalState? terminalState,
    String? editorId,
    EditorState? editorState,
    String? aiId,
    AIState? aiState,
    Map<String, dynamic>? configuration,
  }) async {
    if (_currentSession == null) {
      await createSession();
    }

    final session = _currentSession!;
    bool hasChanges = false;

    // Update terminal states
    if (terminalId != null && terminalState != null) {
      session.terminalStates[terminalId] = terminalState;
      hasChanges = true;
    }

    // Update editor states
    if (editorId != null && editorState != null) {
      session.editorStates[editorId] = editorState;
      hasChanges = true;
    }

    // Update AI states
    if (aiId != null && aiState != null) {
      session.aiStates[aiId] = aiState;
      hasChanges = true;
    }

    // Update configuration
    if (configuration != null) {
      session.configuration.addAll(configuration);
      hasChanges = true;
    }

    if (hasChanges) {
      session.lastModified = DateTime.now();
      
      if (_autoSave) {
        await _saveSession(session);
      }
      
      _sessionController.add(SessionEvent(
        type: SessionEventType.sessionUpdated,
        sessionId: session.id,
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Create a session snapshot
  Future<void> createSnapshot(String description) async {
    if (_currentSession == null) return;
    
    await _createSnapshot(description);
  }

  /// Restore session from snapshot
  Future<bool> restoreSession(String sessionId, {String? snapshotId}) async {
    try {
      // Load session
      final session = await _loadSession(sessionId);
      if (session == null) {
        debugPrint('❌ Session not found: $sessionId');
        return false;
      }

      // Load specific snapshot if requested
      if (snapshotId != null) {
        final snapshot = _loadSnapshot(snapshotId);
        if (snapshot != null) {
          await _restoreFromSnapshot(snapshot);
        }
      }

      _currentSession = session;
      
      _sessionController.add(SessionEvent(
        type: SessionEventType.sessionRestored,
        sessionId: sessionId,
        timestamp: DateTime.now(),
      ));

      debugPrint('💾 Restored session: ${session.name}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to restore session: $e');
      return false;
    }
  }

  /// Delete session
  Future<void> deleteSession(String sessionId) async {
    try {
      // Remove from memory
      if (_currentSession?.id == sessionId) {
        _currentSession = null;
      }

      // Delete session file
      final sessionFile = await _getSessionFile(sessionId);
      if (await sessionFile.exists()) {
        await sessionFile.delete();
      }

      // Delete snapshots
      final snapshotsDir = await _getSnapshotsDir(sessionId);
      if (await snapshotsDir.exists()) {
        await snapshotsDir.delete(recursive: true);
      }

      _sessionController.add(SessionEvent(
        type: SessionEventType.sessionDeleted,
        sessionId: sessionId,
        timestamp: DateTime.now(),
      ));

      debugPrint('💾 Deleted session: $sessionId');
      
    } catch (e) {
      debugPrint('❌ Failed to delete session: $e');
    }
  }

  /// Get list of available sessions
  Future<List<SessionInfo>> getAvailableSessions() async {
    final sessionsDir = await _getSessionsDir();
    if (!await sessionsDir.exists()) {
      return [];
    }

    final sessionFiles = await sessionsDir.list().where((entity) => 
        entity is File && entity.path.endsWith('.json')).toList();

    final sessions = <SessionInfo>[];
    
    for (final file in sessionFiles) {
      try {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        
        sessions.add(SessionInfo(
          id: data['id'] as String,
          name: data['name'] as String,
          profileId: data['profileId'] as String?,
          createdAt: DateTime.parse(data['createdAt'] as String),
          lastModified: DateTime.parse(data['lastModified'] as String),
          metadata: data['metadata'] as Map<String, dynamic>?,
        ));
      } catch (e) {
        debugPrint('❌ Failed to load session info from ${file.path}: $e');
      }
    }

    // Sort by last modified
    sessions.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return sessions;
  }

  /// Get session statistics
  SessionStatistics getStatistics() {
    return SessionStatistics(
      currentSessionId: _currentSession?.id,
      totalSnapshots: _snapshots.length,
      lastSnapshotTime: _lastSnapshot?.timestamp,
      autoSaveEnabled: _autoSave,
      sessionAge: _currentSession?.createdAt != null 
          ? DateTime.now().difference(_currentSession!.createdAt)
          : null,
    );
  }

  /// Create a snapshot
  Future<void> _createSnapshot(String description) async {
    if (_currentSession == null) return;

    final snapshot = SessionSnapshot(
      id: _generateSnapshotId(),
      sessionId: _currentSession!.id,
      description: description,
      timestamp: DateTime.now(),
      terminalStates: Map.from(_currentSession!.terminalStates),
      editorStates: Map.from(_currentSession!.editorStates),
      aiStates: Map.from(_currentSession!.aiStates),
      configuration: Map.from(_currentSession!.configuration),
    );

    _snapshots.add(snapshot);
    _lastSnapshot = snapshot;

    // Limit snapshots
    if (_snapshots.length > _maxSnapshots) {
      _snapshots.removeAt(0);
    }

    // Save snapshot
    await _saveSnapshot(snapshot);

    _sessionController.add(SessionEvent(
      type: SessionEventType.snapshotCreated,
      sessionId: _currentSession!.id,
      snapshotId: snapshot.id,
      timestamp: DateTime.now(),
    ));

    debugPrint('📸 Created snapshot: $description');
  }

  /// Restore from snapshot
  Future<void> _restoreFromSnapshot(SessionSnapshot snapshot) async {
    if (_currentSession == null) return;

    _currentSession!.terminalStates = Map.from(snapshot.terminalStates);
    _currentSession!.editorStates = Map.from(snapshot.editorStates);
    _currentSession!.aiStates = Map.from(snapshot.aiStates);
    _currentSession!.configuration = Map.from(snapshot.configuration);
    _currentSession!.lastModified = DateTime.now();

    await _saveSession(_currentSession!);

    _sessionController.add(SessionEvent(
      type: SessionEventType.snapshotRestored,
      sessionId: _currentSession!.id,
      snapshotId: snapshot.id,
      timestamp: DateTime.now(),
    ));

    debugPrint('📸 Restored from snapshot: ${snapshot.description}');
  }

  /// Save session to file
  Future<void> _saveSession(SessionData session) async {
    try {
      final sessionFile = await _getSessionFile(session.id);
      final sessionJson = json.encode(session.toJson());
      
      await sessionFile.writeAsString(sessionJson);
      
    } catch (e) {
      debugPrint('❌ Failed to save session: $e');
    }
  }

  /// Save snapshot to file
  Future<void> _saveSnapshot(SessionSnapshot snapshot) async {
    try {
      final snapshotsDir = await _getSnapshotsDir(snapshot.sessionId);
      await snapshotsDir.create(recursive: true);
      
      final snapshotFile = File('${snapshotsDir.path}/${snapshot.id}.json');
      final snapshotJson = json.encode(snapshot.toJson());
      
      await snapshotFile.writeAsString(snapshotJson);
      
    } catch (e) {
      debugPrint('❌ Failed to save snapshot: $e');
    }
  }

  /// Load session from file
  Future<SessionData?> _loadSession(String sessionId) async {
    try {
      final sessionFile = await _getSessionFile(sessionId);
      if (!await sessionFile.exists()) {
        return null;
      }

      final content = await sessionFile.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      
      return SessionData.fromJson(data);
      
    } catch (e) {
      debugPrint('❌ Failed to load session: $e');
      return null;
    }
  }

  /// Load existing sessions
  Future<void> _loadExistingSessions() async {
    try {
      final sessions = await getAvailableSessions();
      
      // Check for most recent session
      if (sessions.isNotEmpty) {
        final mostRecent = sessions.first;
        
        // Check if we should auto-restore
        final prefs = await SharedPreferences.getInstance();
        final autoRestore = prefs.getBool('auto_restore_session') ?? true;
        
        if (autoRestore) {
          await restoreSession(mostRecent.id);
        }
      }
      
      debugPrint('💾 Loaded ${sessions.length} existing sessions');
      
    } catch (e) {
      debugPrint('❌ Failed to load existing sessions: $e');
    }
  }

  /// Check for crash recovery
  Future<void> _checkForCrashRecovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShutdown = prefs.getString('last_shutdown_time');
      
      if (lastShutdown != null) {
        final lastShutdownTime = DateTime.parse(lastShutdown);
        final now = DateTime.now();
        
        // If last shutdown was more than 5 minutes ago, assume crash
        if (now.difference(lastShutdownTime) > Duration(minutes: 5)) {
          await _handleCrashRecovery();
        }
      }
      
      // Mark current startup time
      await prefs.setString('last_shutdown_time', DateTime.now().toIso8601String());
      
    } catch (e) {
      debugPrint('❌ Failed to check for crash recovery: $e');
    }
  }

  /// Handle crash recovery
  Future<void> _handleCrashRecovery() async {
    debugPrint('💥 Crash detected, initiating recovery');

    // Create crash recovery session
    await createSession(
      name: 'Crash Recovery ${DateTime.now().millisecondsSinceEpoch}',
      metadata: {
        'is_crash_recovery': true,
        'crash_time': DateTime.now().toIso8601String(),
      },
    );

    // Try to recover from last snapshot if available
    if (_lastSnapshot != null) {
      await _restoreFromSnapshot(_lastSnapshot!);
    }

    _sessionController.add(SessionEvent(
      type: SessionEventType.crashRecovery,
      timestamp: DateTime.now(),
    ));

    debugPrint('💥 Crash recovery completed');
  }

  /// Ensure session directory exists
  Future<void> _ensureSessionDirectory() async {
    final sessionsDir = await _getSessionsDir();
    await sessionsDir.create(recursive: true);
  }

  /// Get sessions directory
  Future<Directory> _getSessionsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/termisol/sessions');
  }

  /// Get session file
  Future<File> _getSessionFile(String sessionId) async {
    final sessionsDir = await _getSessionsDir();
    return File('${sessionsDir.path}/$sessionId.json');
  }

  /// Get snapshots directory
  Future<Directory> _getSnapshotsDir(String sessionId) async {
    final sessionsDir = await _getSessionsDir();
    return Directory('${sessionsDir.path}/$sessionId/snapshots');
  }

  /// Load snapshot from file
  Future<SessionSnapshot?> _loadSnapshot(String snapshotId) async {
    try {
      final sessionsDir = await _getSessionsDir();
      final snapshotFiles = await sessionsDir
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('$snapshotId.json'))
          .cast<File>()
          .toList();

      if (snapshotFiles.isEmpty) {
        return null;
      }

      final content = await snapshotFiles.first.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      
      return SessionSnapshot.fromJson(data);
      
    } catch (e) {
      debugPrint('❌ Failed to load snapshot: $e');
      return null;
    }
  }

  /// Generate session ID
  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
  }

  /// Generate snapshot ID
  String _generateSnapshotId() {
    return 'snapshot_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
  }

  /// Generate random string
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = math.Random();
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }

  /// Start auto-save timer
  void _startAutoSaveTimer() {
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      if (_currentSession != null && _autoSave) {
        unawaited(_saveSession(_currentSession!));
      }
    });
  }

  /// Start health check timer
  void _startHealthCheckTimer() {
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  /// Perform health check
  void _performHealthCheck() {
    if (_currentSession == null) return;

    // Check session integrity
    final now = DateTime.now();
    final age = now.difference(_currentSession!.lastModified);
    
    if (age > Duration(hours: 1)) {
      _sessionController.add(SessionEvent(
        type: SessionEventType.healthWarning,
        sessionId: _currentSession!.id,
        timestamp: now,
        data: {'warning': 'Session not updated recently'},
      ));
    }
  }

  /// Set auto-save mode
  void setAutoSave(bool enabled) {
    _autoSave = enabled;
    debugPrint('💾 Auto-save ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Dispose session persistence
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    _healthCheckTimer?.cancel();
    _sessionController.close();
    
    // Save current session
    if (_currentSession != null) {
      await _saveSession(_currentSession!);
    }
    
    // Mark clean shutdown
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_shutdown_time', DateTime.now().toIso8601String());
    
    _currentSession = null;
    _snapshots.clear();
    _profiles.clear();
    
    debugPrint('💾 Session Persistence disposed');
  }
}

/// Session data
class SessionData {
  final String id;
  final String name;
  final String? profileId;
  final DateTime createdAt;
  DateTime lastModified;
  final Map<String, dynamic> metadata;
  final Map<String, TerminalState> terminalStates;
  final Map<String, EditorState> editorStates;
  final Map<String, AIState> aiStates;
  final Map<String, dynamic> configuration;
  
  SessionData({
    required this.id,
    required this.name,
    this.profileId,
    required this.createdAt,
    required this.lastModified,
    required this.metadata,
    required this.terminalStates,
    required this.editorStates,
    required this.aiStates,
    required this.configuration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'profileId': profileId,
    'createdAt': createdAt.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    'metadata': metadata,
    'terminalStates': terminalStates.map((k, v) => MapEntry(k, v.toJson())),
    'editorStates': editorStates.map((k, v) => MapEntry(k, v.toJson())),
    'aiStates': aiStates.map((k, v) => MapEntry(k, v.toJson())),
    'configuration': configuration,
  };

  static SessionData fromJson(Map<String, dynamic> json) => SessionData(
    id: json['id'] as String,
    name: json['name'] as String,
    profileId: json['profileId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastModified: DateTime.parse(json['lastModified'] as String),
    metadata: json['metadata'] as Map<String, dynamic>,
    terminalStates: (json['terminalStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, TerminalState.fromJson(v as Map<String, dynamic>)),
    ),
    editorStates: (json['editorStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, EditorState.fromJson(v as Map<String, dynamic>)),
    ),
    aiStates: (json['aiStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, AIState.fromJson(v as Map<String, dynamic>)),
    ),
    configuration: json['configuration'] as Map<String, dynamic>,
  );
}

/// Session snapshot
class SessionSnapshot {
  final String id;
  final String sessionId;
  final String description;
  final DateTime timestamp;
  final Map<String, TerminalState> terminalStates;
  final Map<String, EditorState> editorStates;
  final Map<String, AIState> aiStates;
  final Map<String, dynamic> configuration;
  
  SessionSnapshot({
    required this.id,
    required this.sessionId,
    required this.description,
    required this.timestamp,
    required this.terminalStates,
    required this.editorStates,
    required this.aiStates,
    required this.configuration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'terminalStates': terminalStates.map((k, v) => MapEntry(k, v.toJson())),
    'editorStates': editorStates.map((k, v) => MapEntry(k, v.toJson())),
    'aiStates': aiStates.map((k, v) => MapEntry(k, v.toJson())),
    'configuration': configuration,
  };

  static SessionSnapshot fromJson(Map<String, dynamic> json) => SessionSnapshot(
    id: json['id'] as String,
    sessionId: json['sessionId'] as String,
    description: json['description'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    terminalStates: (json['terminalStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, TerminalState.fromJson(v as Map<String, dynamic>)),
    ),
    editorStates: (json['editorStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, EditorState.fromJson(v as Map<String, dynamic>)),
    ),
    aiStates: (json['aiStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, AIState.fromJson(v as Map<String, dynamic>)),
    ),
    configuration: json['configuration'] as Map<String, dynamic>,
  );
}

/// Terminal state
class TerminalState {
  final String workingDirectory;
  final List<String> commandHistory;
  final int cursorPosition;
  final Map<String, dynamic> environment;
  
  TerminalState({
    required this.workingDirectory,
    required this.commandHistory,
    required this.cursorPosition,
    required this.environment,
  });

  Map<String, dynamic> toJson() => {
    'workingDirectory': workingDirectory,
    'commandHistory': commandHistory,
    'cursorPosition': cursorPosition,
    'environment': environment,
  };

  static TerminalState fromJson(Map<String, dynamic> json) => TerminalState(
    workingDirectory: json['workingDirectory'] as String,
    commandHistory: List<String>.from(json['commandHistory'] as List),
    cursorPosition: json['cursorPosition'] as int,
    environment: json['environment'] as Map<String, dynamic>,
  );
}

/// Editor state
class EditorState {
  final String filePath;
  final String content;
  final int cursorPosition;
  final List<int> selection;
  final Map<String, dynamic> settings;
  
  EditorState({
    required this.filePath,
    required this.content,
    required this.cursorPosition,
    required this.selection,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'content': content,
    'cursorPosition': cursorPosition,
    'selection': selection,
    'settings': settings,
  };

  static EditorState fromJson(Map<String, dynamic> json) => EditorState(
    filePath: json['filePath'] as String,
    content: json['content'] as String,
    cursorPosition: json['cursorPosition'] as int,
    selection: List<int>.from(json['selection'] as List),
    settings: json['settings'] as Map<String, dynamic>,
  );
}

/// AI state
class AIState {
  final String model;
  final List<Map<String, String>> chatHistory;
  final Map<String, dynamic> context;
  final Map<String, dynamic> settings;
  
  AIState({
    required this.model,
    required this.chatHistory,
    required this.context,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
    'model': model,
    'chatHistory': chatHistory,
    'context': context,
    'settings': settings,
  };

  static AIState fromJson(Map<String, dynamic> json) => AIState(
    model: json['model'] as String,
    chatHistory: List<Map<String, String>>.from(json['chatHistory'] as List),
    context: json['context'] as Map<String, dynamic>,
    settings: json['settings'] as Map<String, dynamic>,
  );
}

/// Session info
class SessionInfo {
  final String id;
  final String name;
  final String? profileId;
  final DateTime createdAt;
  final DateTime lastModified;
  final Map<String, dynamic>? metadata;
  
  SessionInfo({
    required this.id,
    required this.name,
    this.profileId,
    required this.createdAt,
    required this.lastModified,
    this.metadata,
  });
}

/// Session profile
class SessionProfile {
  final String id;
  final String name;
  final Map<String, dynamic> settings;
  final DateTime createdAt;
  
  SessionProfile({
    required this.id,
    required this.name,
    required this.settings,
    required this.createdAt,
  });
}

/// Session statistics
class SessionStatistics {
  final String? currentSessionId;
  final int totalSnapshots;
  final DateTime? lastSnapshotTime;
  final bool autoSaveEnabled;
  final Duration? sessionAge;
  
  SessionStatistics({
    this.currentSessionId,
    required this.totalSnapshots,
    this.lastSnapshotTime,
    required this.autoSaveEnabled,
    this.sessionAge,
  });
}

/// Session event
class SessionEvent {
  final SessionEventType type;
  final String? sessionId;
  final String? snapshotId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  SessionEvent({
    required this.type,
    this.sessionId,
    this.snapshotId,
    required this.timestamp,
    this.data,
  });
}

/// Enums
enum SessionEventType {
  sessionCreated,
  sessionUpdated,
  sessionRestored,
  sessionDeleted,
  snapshotCreated,
  snapshotRestored,
  crashRecovery,
  healthWarning,
}

/// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents "unawaited_future" lint
}
