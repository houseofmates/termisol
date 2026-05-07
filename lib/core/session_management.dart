import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class SessionManagement {
  static const int _maxSessions = 10;
  static const int _maxHistoryPerSession = 1000;
  static const String _socketDirectory = '/tmp/termisol_sessions';
  
  final Map<String, TerminalSession> _sessions = {};
  final Map<String, SessionSocket> _sockets = {};
  final Map<String, List<SessionCommand>> _commandHistory = {};
  final Map<String, SessionLayout> _layouts = {};
  
  String? _activeSessionId;
  SessionManager _manager = SessionManager();
  int _totalSessions = 0;
  
  final StreamController<SessionEvent> _sessionController = 
      StreamController<SessionEvent>.broadcast();

  void initialize() {
    _createSocketDirectory();
    _initializeManager();
    _loadExistingSessions();
    developer.log('🖥️ Session Management initialized');
  }

  void _createSocketDirectory() {
    final dir = Directory(_socketDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  void _initializeManager() {
    _manager = SessionManager(
      maxSessions: _maxSessions,
      socketDirectory: _socketDirectory,
    );
  }

  void _loadExistingSessions() {
    // Load existing session sockets
    final dir = Directory(_socketDirectory);
    if (!dir.existsSync()) return;
    
    final files = dir.listSync();
    for (final file in files) {
      if (file.path.endsWith('.sock')) {
        final sessionId = path.basenameWithoutExtension(file.path);
        _loadSession(sessionId, file.path);
      }
    }
  }

  void _loadSession(String sessionId, String socketPath) {
    try {
      final socket = SessionSocket(
        sessionId: sessionId,
        path: socketPath,
        createdAt: File(socketPath).statSync().modified,
      );
      
      _sockets[sessionId] = socket;
      
      final session = TerminalSession(
        id: sessionId,
        name: 'Session $sessionId',
        socket: socket,
        createdAt: socket.createdAt,
        commandHistory: [],
        layout: SessionLayout.defaultLayout(),
      );
      
      _sessions[sessionId] = session;
      _commandHistory[sessionId] = [];
      _layouts[sessionId] = session.layout;
      
      developer.log('🖥️ Loaded existing session: $sessionId');
      
    } catch (e) {
      developer.log('🖥️ Failed to load session $sessionId: $e');
    }
  }

  String createSession({
    String? name,
    String? workingDirectory,
    Map<String, String>? environment,
    SessionLayout? layout,
  }) {
    if (_sessions.length >= _maxSessions) {
      throw Exception('Maximum sessions reached');
    }
    
    final sessionId = _generateSessionId();
    final socketPath = '$_socketDirectory/${sessionId}.sock';
    
    // Create session socket
    final socket = SessionSocket(
      sessionId: sessionId,
      path: socketPath,
      createdAt: DateTime.now(),
    );
    
    // Create session
    final session = TerminalSession(
      id: sessionId,
      name: name ?? 'Session $sessionId',
      socket: socket,
      workingDirectory: workingDirectory ?? Directory.current.path,
      environment: environment ?? {},
      layout: layout ?? SessionLayout.defaultLayout(),
      createdAt: DateTime.now(),
      commandHistory: [],
    );
    
    _sessions[sessionId] = session;
    _sockets[sessionId] = socket;
    _commandHistory[sessionId] = [];
    _layouts[sessionId] = session.layout;
    _totalSessions++;
    
    // Create socket file
    _createSocketFile(socketPath);
    
    developer.log('🖥️ Created session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.created,
      sessionId: sessionId,
      sessionName: session.name,
    ));
    
    return sessionId;
  }

  void _createSocketFile(String socketPath) {
    final socketFile = File(socketPath);
    socketFile.createSync();
    
    // Write session metadata
    final metadata = {
      'created_at': DateTime.now().toIso8601String(),
      'termisol_version': '1.0.0',
    };
    
    socketFile.writeAsStringSync(jsonEncode(metadata));
  }

  void attachToSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    _activeSessionId = sessionId;
    session.lastAttached = DateTime.now();
    
    developer.log('🖥️ Attached to session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.attached,
      sessionId: sessionId,
      sessionName: session.name,
    ));
  }

  void detachFromSession() {
    if (_activeSessionId == null) return;
    
    final sessionId = _activeSessionId!;
    final session = _sessions[sessionId];
    
    if (session != null) {
      session.lastDetached = DateTime.now();
    }
    
    _activeSessionId = null;
    
    developer.log('🖥️ Detached from session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.detached,
      sessionId: sessionId,
      sessionName: session?.name,
    ));
  }

  void killSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    // Kill all processes in session
    _killSessionProcesses(session);
    
    // Remove socket file
    _removeSocketFile(session.socket.path);
    
    // Clean up
    _sessions.remove(sessionId);
    _sockets.remove(sessionId);
    _commandHistory.remove(sessionId);
    _layouts.remove(sessionId);
    
    // Update active session if needed
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
    
    developer.log('🖥️ Killed session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.killed,
      sessionId: sessionId,
      sessionName: session.name,
    ));
  }

  void _killSessionProcesses(TerminalSession session) {
    // Simulate killing processes
    // In practice, this would send signals to all processes in the session
    developer.log('🖥️ Killing processes in session: ${session.id}');
  }

  void _removeSocketFile(String socketPath) {
    try {
      final socketFile = File(socketPath);
      if (socketFile.existsSync()) {
        socketFile.deleteSync();
      }
    } catch (e) {
      developer.log('🖥️ Failed to remove socket file: $e');
    }
  }

  void renameSession(String sessionId, String newName) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final oldName = session.name;
    session.name = newName;
    
    developer.log('🖥️ Renamed session: $sessionId from $oldName to $newName');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.renamed,
      sessionId: sessionId,
      oldName: oldName,
      newName: newName,
    ));
  }

  void executeCommandInSession(String sessionId, String command) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    // Add to command history
    final historyEntry = SessionCommand(
      command: command,
      timestamp: DateTime.now(),
      workingDirectory: session.workingDirectory,
    );
    
    _commandHistory[sessionId]!.add(historyEntry);
    
    // Keep only recent history
    if (_commandHistory[sessionId]!.length > _maxHistoryPerSession) {
      _commandHistory[sessionId]!.removeAt(0);
    }
    
    // Execute command in session
    _executeCommand(session, command);
    
    developer.log('🖥️ Executed command in session $sessionId: $command');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.commandExecuted,
      sessionId: sessionId,
      command: command,
    ));
  }

  void _executeCommand(TerminalSession session, String command) {
    // Simulate command execution
    // In practice, this would send the command to the session's shell
    session.lastCommand = command;
    session.lastCommandTime = DateTime.now();
  }

  void setSessionLayout(String sessionId, SessionLayout layout) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final oldLayout = session.layout;
    session.layout = layout;
    _layouts[sessionId] = layout;
    
    developer.log('🖥️ Set layout for session $sessionId: ${layout.name}');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.layoutChanged,
      sessionId: sessionId,
      oldLayout: oldLayout,
      newLayout: layout,
    ));
  }

  void splitSession(String sessionId, {bool vertical = false}) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    // Create new session with same environment
    final newSessionId = createSession(
      name: '${session.name} (split)',
      workingDirectory: session.workingDirectory,
      environment: session.environment,
      layout: _createSplitLayout(session.layout, vertical),
    );
    
    // Execute split command in original session
    final splitCommand = vertical ? 'tmux split -v' : 'tmux split -h';
    executeCommandInSession(sessionId, splitCommand);
    
    developer.log('🖥️ Split session: $sessionId -> $newSessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.split,
      sessionId: sessionId,
      newSessionId: newSessionId,
      vertical: vertical,
    ));
  }

  SessionLayout _createSplitLayout(SessionLayout originalLayout, bool vertical) {
    return SessionLayout(
      name: '${originalLayout.name} (split)',
      panes: [
        LayoutPane(
          id: 'pane_0',
          x: 0,
          y: 0,
          width: vertical ? originalLayout.panes[0].width : originalLayout.panes[0].width / 2,
          height: vertical ? originalLayout.panes[0].height / 2 : originalLayout.panes[0].height,
          active: true,
        ),
        LayoutPane(
          id: 'pane_1',
          x: vertical ? 0 : originalLayout.panes[0].width / 2,
          y: vertical ? originalLayout.panes[0].height / 2 : 0,
          width: vertical ? originalLayout.panes[0].width : originalLayout.panes[0].width / 2,
          height: vertical ? originalLayout.panes[0].height / 2 : originalLayout.panes[0].height,
          active: false,
        ),
      ],
    );
  }

  List<String> listSessions() {
    return _sessions.keys.toList()..sort();
  }

  TerminalSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  TerminalSession? getActiveSession() {
    if (_activeSessionId == null) return null;
    return _sessions[_activeSessionId!];
  }

  List<SessionCommand> getSessionHistory(String sessionId) {
    return _commandHistory[sessionId] ?? [];
  }

  void clearSessionHistory(String sessionId) {
    _commandHistory[sessionId] = [];
    
    developer.log('🖥️ Cleared history for session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.historyCleared,
      sessionId: sessionId,
    ));
  }

  void searchSessions(String query) {
    final results = <SessionSearchResult>[];
    
    for (final session in _sessions.values) {
      // Search in session name
      if (session.name.toLowerCase().contains(query.toLowerCase())) {
        results.add(SessionSearchResult(
          sessionId: session.id,
          sessionName: session.name,
          matchType: MatchType.name,
          matchText: query,
        ));
      }
      
      // Search in command history
      final history = _commandHistory[session.id] ?? [];
      for (final command in history) {
        if (command.command.toLowerCase().contains(query.toLowerCase())) {
          results.add(SessionSearchResult(
            sessionId: session.id,
            sessionName: session.name,
            matchType: MatchType.command,
            matchText: command.command,
            timestamp: command.timestamp,
          ));
        }
      }
    }
    
    developer.log('🖥️ Searched sessions for: $query (${results.length} results)');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.searched,
      query: query,
      results: results,
    ));
  }

  void saveSessionState(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final stateFile = File('${_socketDirectory}/${sessionId}_state.json');
    
    final state = {
      'session': {
        'id': session.id,
        'name': session.name,
        'working_directory': session.workingDirectory,
        'environment': session.environment,
        'created_at': session.createdAt.toIso8601String(),
        'last_attached': session.lastAttached?.toIso8601String(),
        'last_detached': session.lastDetached?.toIso8601String(),
        'last_command': session.lastCommand,
        'last_command_time': session.lastCommandTime?.toIso8601String(),
      },
      'layout': {
        'name': session.layout.name,
        'panes': session.layout.panes.map((pane) => {
          'id': pane.id,
          'x': pane.x,
          'y': pane.y,
          'width': pane.width,
          'height': pane.height,
          'active': pane.active,
        }).toList(),
      },
      'command_history': _commandHistory[sessionId]?.map((cmd) => {
        'command': cmd.command,
        'timestamp': cmd.timestamp.toIso8601String(),
        'working_directory': cmd.workingDirectory,
      }).toList(),
    };
    
    stateFile.writeAsStringSync(jsonEncode(state));
    
    developer.log('🖥️ Saved state for session: $sessionId');
    
    _emitEvent(SessionEvent(
      type: SessionEventType.stateSaved,
      sessionId: sessionId,
    ));
  }

  void loadSessionState(String sessionId) {
    final stateFile = File('${_socketDirectory}/${sessionId}_state.json');
    if (!stateFile.existsSync()) {
      throw Exception('Session state file not found: $sessionId');
    }
    
    try {
      final stateData = jsonDecode(stateFile.readAsStringSync());
      
      // Restore session
      final sessionData = stateData['session'];
      final session = _sessions[sessionId];
      if (session != null) {
        session.name = sessionData['name'];
        session.workingDirectory = sessionData['working_directory'];
        session.environment = Map<String, String>.from(sessionData['environment']);
        session.lastAttached = DateTime.tryParse(sessionData['last_attached']);
        session.lastDetached = DateTime.tryParse(sessionData['last_detached']);
        session.lastCommand = sessionData['last_command'];
        session.lastCommandTime = DateTime.tryParse(sessionData['last_command_time']);
      }
      
      // Restore layout
      final layoutData = stateData['layout'];
      final layout = SessionLayout(
        name: layoutData['name'],
        panes: (layoutData['panes'] as List).map((pane) => LayoutPane(
          id: pane['id'],
          x: pane['x'],
          y: pane['y'],
          width: pane['width'],
          height: pane['height'],
          active: pane['active'],
        )).toList(),
      );
      
      if (session != null) {
        session.layout = layout;
        _layouts[sessionId] = layout;
      }
      
      // Restore command history
      final historyData = stateData['command_history'] as List?;
      if (historyData != null) {
        _commandHistory[sessionId] = historyData.map((cmd) => SessionCommand(
          command: cmd['command'],
          timestamp: DateTime.parse(cmd['timestamp']),
          workingDirectory: cmd['working_directory'],
        )).toList();
      }
      
      developer.log('🖥️ Loaded state for session: $sessionId');
      
      _emitEvent(SessionEvent(
        type: SessionEventType.stateLoaded,
        sessionId: sessionId,
      ));
      
    } catch (e) {
      developer.log('🖥️ Failed to load session state: $e');
    }
  }

  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_$_totalSessions';
  }

  void _emitEvent(SessionEvent event) {
    _sessionController.add(event);
  }

  Stream<SessionEvent> get sessionEventStream => _sessionController.stream;

  SessionManagementStats getStats() {
    return SessionManagementStats(
      totalSessions: _totalSessions,
      activeSessions: _sessions.length,
      activeSessionId: _activeSessionId,
      totalCommands: _commandHistory.values
          .fold(0, (sum, history) => sum + history.length),
      averageCommandsPerSession: _sessions.isNotEmpty
          ? _commandHistory.values.fold(0, (sum, history) => sum + history.length) / _sessions.length
          : 0.0,
    );
  }

  void dispose() {
    // Kill all sessions
    for (final sessionId in _sessions.keys.toList()) {
      killSession(sessionId);
    }
    
    _sessions.clear();
    _sockets.clear();
    _commandHistory.clear();
    _layouts.clear();
    _sessionController.close();
    
    developer.log('🖥️ Session Management disposed');
  }
}

class TerminalSession {
  final String id;
  String name;
  final SessionSocket socket;
  final String workingDirectory;
  final Map<String, String> environment;
  final SessionLayout layout;
  final DateTime createdAt;
  final List<SessionCommand> commandHistory;
  
  DateTime? lastAttached;
  DateTime? lastDetached;
  String? lastCommand;
  DateTime? lastCommandTime;

  TerminalSession({
    required this.id,
    required this.name,
    required this.socket,
    required this.workingDirectory,
    required this.environment,
    required this.layout,
    required this.createdAt,
    required this.commandHistory,
  });
}

class SessionSocket {
  final String sessionId;
  final String path;
  final DateTime createdAt;

  SessionSocket({
    required this.sessionId,
    required this.path,
    required this.createdAt,
  });
}

class SessionLayout {
  final String name;
  final List<LayoutPane> panes;

  SessionLayout({
    required this.name,
    required this.panes,
  });

  factory SessionLayout.defaultLayout() {
    return SessionLayout(
      name: 'default',
      panes: [
        LayoutPane(
          id: 'pane_0',
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          active: true,
        ),
      ],
    );
  }
}

class LayoutPane {
  final String id;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool active;

  LayoutPane({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.active,
  });
}

class SessionCommand {
  final String command;
  final DateTime timestamp;
  final String workingDirectory;

  SessionCommand({
    required this.command,
    required this.timestamp,
    required this.workingDirectory,
  });
}

class SessionManager {
  final int maxSessions;
  final String socketDirectory;

  SessionManager({
    required this.maxSessions,
    required this.socketDirectory,
  });
}

class SessionSearchResult {
  final String sessionId;
  final String sessionName;
  final MatchType matchType;
  final String matchText;
  final DateTime? timestamp;

  SessionSearchResult({
    required this.sessionId,
    required this.sessionName,
    required this.matchType,
    required this.matchText,
    this.timestamp,
  });
}

enum SessionEventType {
  created,
  attached,
  detached,
  killed,
  renamed,
  commandExecuted,
  layoutChanged,
  split,
  historyCleared,
  searched,
  stateSaved,
  stateLoaded,
}

enum MatchType {
  name,
  command,
  workingDirectory,
}

class SessionEvent {
  final SessionEventType type;
  final String? sessionId;
  final String? sessionName;
  final String? oldName;
  final String? newName;
  final String? command;
  final String? query;
  final SessionLayout? oldLayout;
  final SessionLayout? newLayout;
  final String? newSessionId;
  final bool? vertical;
  final List<SessionSearchResult>? results;

  SessionEvent({
    required this.type,
    this.sessionId,
    this.sessionName,
    this.oldName,
    this.newName,
    this.command,
    this.query,
    this.oldLayout,
    this.newLayout,
    this.newSessionId,
    this.vertical,
    this.results,
  });
}

class SessionManagementStats {
  final int totalSessions;
  final int activeSessions;
  final String? activeSessionId;
  final int totalCommands;
  final double averageCommandsPerSession;

  SessionManagementStats({
    required this.totalSessions,
    required this.activeSessions,
    this.activeSessionId,
    required this.totalCommands,
    required this.averageCommandsPerSession,
  });
}
