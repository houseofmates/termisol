import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'core/terminal_session.dart';

/// Manages session restoration across app crashes and restarts.
/// Saves tab state, working directories, and command history.
class SessionRestoreManager {
  static const String _sessionsFile = 'termisol_sessions.json';
  static const int _maxSessions = 10;

  final Map<String, SessionState> _sessions = {};
  Timer? _autoSaveTimer;
  bool _loaded = false;
  final _loadCompleter = Completer<void>();

  SessionRestoreManager() {
    _loadSessions();
    _startAutoSave();
  }

  /// Ensure sessions are loaded before accessing them.
  Future<void> load() => _loadCompleter.future;

  /// Represents a saved terminal session state.
  class SessionState {
    final String id;
    final String name;
    final String workingDirectory;
    final String? shell;
    final List<String> commandHistory;
    final DateTime lastSaved;
    final Map<String, dynamic>? metadata;

    SessionState({
      required this.id,
      required this.name,
      required this.workingDirectory,
      this.shell,
      required this.commandHistory,
      required this.lastSaved,
      this.metadata,
    });

    Map<String, dynamic> toJson() {
      return {
        'id': id,
        'name': name,
        'workingDirectory': workingDirectory,
        'shell': shell,
        'commandHistory': commandHistory,
        'lastSaved': lastSaved.toIso8601String(),
        'metadata': metadata,
      };
    }

    factory SessionState.fromJson(Map<String, dynamic> json) {
      return SessionState(
        id: json['id'] as String,
        name: json['name'] as String,
        workingDirectory: json['workingDirectory'] as String,
        shell: json['shell'] as String?,
        commandHistory: List<String>.from(json['commandHistory'] as List? ?? []),
        lastSaved: DateTime.parse(json['lastSaved'] as String),
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
    }
  }

  /// Save current session state.
  Future<void> saveSession(TerminalSession session) async {
    try {
      final sessionState = SessionState(
        id: session.id,
        name: session.name,
        workingDirectory: Directory.current.path,
        shell: Platform.isLinux
            ? 'bash'
            : Platform.isMacOS
                ? 'zsh'
                : Platform.isWindows
                    ? 'cmd.exe'
                    : 'sh',
        commandHistory: const [],
        lastSaved: DateTime.now(),
        metadata: {
          'connected': session.connected,
          'hasError': session.error != null,
        },
      );

      _sessions[session.id] = sessionState;
      await _persistSessions();
      await _cleanupOldSessions();

      if (kDebugMode) debugPrint('Saved session: ${session.name} (${session.id})');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to save session: $e\n$stack');
    }
  }

  /// Restore a session by ID.
  Future<SessionState?> restoreSession(String sessionId) async {
    await _loadCompleter.future;
    try {
      final session = _sessions[sessionId];
      if (session != null) {
        if (kDebugMode) debugPrint('Restoring session: ${session.name} ($sessionId)');
        return session;
      }
      return null;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to restore session: $e\n$stack');
      return null;
    }
  }

  /// Get all saved sessions.
  List<SessionState> getSavedSessions() {
    final sessions = _sessions.values.toList();
    sessions.sort((a, b) => b.lastSaved.compareTo(a.lastSaved));
    return sessions;
  }

  /// Delete a saved session.
  Future<void> deleteSession(String sessionId) async {
    _sessions.remove(sessionId);
    await _persistSessions();
    if (kDebugMode) debugPrint('Deleted session: $sessionId');
  }

  /// Auto-save all active sessions periodically.
  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _persistSessions();
    });
  }

  /// Persist sessions to disk.
  Future<void> _persistSessions() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_sessionsFile');

      final json = {
        'sessions': _sessions.map((key, value) => MapEntry(key, value.toJson())),
        'version': '1.0',
        'lastSaved': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(jsonEncode(json));
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to persist sessions: $e\n$stack');
    }
  }

  /// Load sessions from disk.
  Future<void> _loadSessions() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_sessionsFile');

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        if (json['sessions'] is Map) {
          final sessionsMap = json['sessions'] as Map<String, dynamic>;
          for (final entry in sessionsMap.entries) {
            try {
              _sessions[entry.key] = SessionState.fromJson(entry.value);
            } catch (e) {
              if (kDebugMode) debugPrint('Skipping corrupt session ${entry.key}: $e');
            }
          }
          if (kDebugMode) debugPrint('Loaded ${_sessions.length} sessions');
        }
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to load sessions: $e\n$stack');
    } finally {
      if (!_loadCompleter.isCompleted) _loadCompleter.complete();
      _loaded = true;
    }
  }

  /// Clean up old sessions (keep only recent N).
  Future<void> _cleanupOldSessions() async {
    if (_sessions.length <= _maxSessions) return;

    final sessions = getSavedSessions();
    final toDelete = sessions.skip(_maxSessions);

    for (final session in toDelete) {
      await deleteSession(session.id);
    }
  }

  void dispose() {
    _autoSaveTimer?.cancel();
    _persistSessions();
  }
}
