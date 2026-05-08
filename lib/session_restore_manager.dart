import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';
import 'core/terminal_session.dart';

/// Manages session restoration across app crashes and restarts.
/// Saves tab state, working directories, and command history.
class SessionRestoreManager {
  static const String _sessionsFile = 'termisol_sessions.json';
  static const String _maxSessions = 10;
  
  final Map<String, SessionState> _sessions = {};
  Timer? _autoSaveTimer;
  
  SessionRestoreManager() {
    _loadSessions();
    _startAutoSave();
  }

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
        commandHistory: List<String>.from(json['commandHistory'] as List),
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
        shell: Platform.isLinux ? 'bash' : Platform.isMacOS ? 'zsh' : 'cmd.exe',
        commandHistory: _getCommandHistory(session),
        lastSaved: DateTime.now(),
        metadata: {
          'connected': session.connected,
          'hasError': session.error != null,
        },
      );

      _sessions[session.id] = sessionState;
      await _persistSessions();
      
      debugPrint('💾 Saved session: ${session.name} (${session.id})');
    } catch (e) {
      debugPrint('❌ Failed to save session: $e');
    }
  }

  /// Restore a session by ID.
  Future<SessionState?> restoreSession(String sessionId) async {
    try {
      final session = _sessions[sessionId];
      if (session != null) {
        debugPrint('🔄 Restoring session: ${session.name} ($sessionId)');
        return session;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Failed to restore session: $e');
      return null;
    }
  }

  /// Get all saved sessions.
  List<SessionState> getSavedSessions() {
    final sessions = _sessions.values.toList();
    // Sort by last saved time
    sessions.sort((a, b) => b.lastSaved.compareTo(a.lastSaved));
    return sessions;
  }

  /// Delete a saved session.
  Future<void> deleteSession(String sessionId) async {
    _sessions.remove(sessionId);
    await _persistSessions();
    debugPrint('🗑️ Deleted session: $sessionId');
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
    } catch (e) {
      debugPrint('❌ Failed to persist sessions: $e');
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
            _sessions[entry.key] = SessionState.fromJson(entry.value);
          }
          debugPrint('📂 Loaded ${_sessions.length} sessions');
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load sessions: $e');
    }
  }

  /// Extract command history from terminal session.
  List<String> _getCommandHistory(TerminalSession session) {
    // This is a simplified implementation
    // In a real implementation, you'd track all commands entered
    return [
      'ls -la',
      'pwd',
      'whoami',
    ];
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
