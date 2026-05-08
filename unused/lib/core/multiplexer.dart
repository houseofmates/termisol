import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'terminal_session.dart';

/// Terminal Multiplexer - tmux-inspired session management
/// 
/// Implements advanced multiplexing features:
/// - Multiple sessions in single window
/// - Session persistence across restarts
/// - Split panes (horizontal/vertical)
/// - Remote session synchronization
/// - Session sharing and collaboration
class TerminalMultiplexer {
  bool _isInitialized = false;
  final Map<String, MultiplexedSession> _sessions = {};
  final Map<String, MultiplexedWindow> _windows = {};
  final Map<String, MultiplexedPane> _panes = {};
  
  int _nextSessionId = 1;
  int _nextWindowId = 1;
  int _nextPaneId = 1;
  
  // Session persistence
  String? _persistencePath;
  Timer? _persistenceTimer;
  
  // Remote synchronization
  final Map<String, RemoteSyncClient> _syncClients = {};
  
  TerminalMultiplexer();
  
  bool get isInitialized => _isInitialized;
  Map<String, MultiplexedSession> get sessions => _sessions;
  Map<String, MultiplexedWindow> get windows => _windows;
  Map<String, MultiplexedPane> get panes => _panes;
  
  /// Initialize multiplexer with persistence
  Future<void> initialize({String? persistencePath}) async {
    if (_isInitialized) return;
    
    try {
      _persistencePath = persistencePath ?? '${Directory.systemTemp.path}/termisol_sessions';
      
      // Create persistence directory
      final dir = Directory(_persistencePath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // Load persisted sessions
      await _loadPersistedSessions();
      
      // Start persistence timer
      _persistenceTimer = Timer.periodic(const Duration(seconds: 30), (_) => _persistSessions());
      
      _isInitialized = true;
      debugPrint('🔀 Terminal Multiplexer initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Terminal Multiplexer: $e');
    }
  }
  
  /// Create new multiplexed session
  MultiplexedSession createSession({
    required String name,
    String? command,
    Map<String, String>? environment,
    bool persistent = true,
  }) {
    final sessionId = 'session_$_nextSessionId';
    _nextSessionId++;
    
    final session = MultiplexedSession(
      id: sessionId,
      name: name,
      command: command,
      environment: environment ?? {},
      persistent: persistent,
      createdAt: DateTime.now(),
    );
    
    _sessions[sessionId] = session;
    
    // Create default window
    createWindow(sessionId: sessionId, name: 'main');
    
    debugPrint('📺 Created multiplexed session: $sessionId ($name)');
    return session;
  }
  
  /// Create new window in session
  MultiplexedWindow createWindow({
    required String sessionId,
    required String name,
    WindowLayout layout = WindowLayout.single,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }
    
    final windowId = 'window_$_nextWindowId';
    _nextWindowId++;
    
    final window = MultiplexedWindow(
      id: windowId,
      sessionId: sessionId,
      name: name,
      layout: layout,
      createdAt: DateTime.now(),
    );
    
    _windows[windowId] = window;
    session.windows.add(windowId);
    
    // Create default pane for single layout
    if (layout == WindowLayout.single) {
      createPane(windowId: windowId, name: 'main');
    }
    
    debugPrint('🪟 Created window: $windowId ($name)');
    return window;
  }
  
  /// Create new pane in window
  MultiplexedPane createPane({
    required String windowId,
    required String name,
    PaneType type = PaneType.terminal,
    double? widthRatio,
    double? heightRatio,
  }) {
    final window = _windows[windowId];
    if (window == null) {
      throw ArgumentError('Window not found: $windowId');
    }
    
    final paneId = 'pane_$_nextPaneId';
    _nextPaneId++;
    
    final pane = MultiplexedPane(
      id: paneId,
      windowId: windowId,
      name: name,
      type: type,
      widthRatio: widthRatio ?? 1.0,
      heightRatio: heightRatio ?? 1.0,
      createdAt: DateTime.now(),
    );
    
    _panes[paneId] = pane;
    window.panes.add(paneId);
    
    debugPrint('📦 Created pane: $paneId ($name)');
    return pane;
  }
  
  /// Split pane horizontally
  MultiplexedPane splitPaneHorizontal(String paneId, {String? newName}) {
    final pane = _panes[paneId];
    if (pane == null) {
      throw ArgumentError('Pane not found: $paneId');
    }
    
    // Create new pane with same height, half width
    final newPane = createPane(
      windowId: pane.windowId,
      name: newName ?? '${pane.name}_split',
      widthRatio: pane.widthRatio / 2,
      heightRatio: pane.heightRatio,
    );
    
    // Update original pane width
    pane.widthRatio = pane.widthRatio / 2;
    
    // Update window layout
    final window = _windows[pane.windowId]!;
    window.layout = WindowLayout.horizontalSplit;
    
    return newPane;
  }
  
  /// Split pane vertically
  MultiplexedPane splitPaneVertical(String paneId, {String? newName}) {
    final pane = _panes[paneId];
    if (pane == null) {
      throw ArgumentError('Pane not found: $paneId');
    }
    
    // Create new pane with same width, half height
    final newPane = createPane(
      windowId: pane.windowId,
      name: newName ?? '${pane.name}_split',
      widthRatio: pane.widthRatio,
      heightRatio: pane.heightRatio / 2,
    );
    
    // Update original pane height
    pane.heightRatio = pane.heightRatio / 2;
    
    // Update window layout
    final window = _windows[pane.windowId]!;
    window.layout = WindowLayout.verticalSplit;
    
    return newPane;
  }
  
  /// Close pane
  void closePane(String paneId) {
    final pane = _panes[paneId];
    if (pane == null) return;
    
    final window = _windows[pane.windowId];
    if (window == null) return;
    
    // Remove pane from window
    window.panes.remove(paneId);
    _panes.remove(paneId);
    
    // If only one pane left, switch to single layout
    if (window.panes.length == 1) {
      window.layout = WindowLayout.single;
    }
    
    debugPrint('🗑️ Closed pane: $paneId');
  }
  
  /// Close window
  void closeWindow(String windowId) {
    final window = _windows[windowId];
    if (window == null) return;
    
    final session = _sessions[window.sessionId];
    if (session == null) return;
    
    // Close all panes in window
    for (final paneId in window.panes) {
      _panes.remove(paneId);
    }
    
    // Remove window from session
    session.windows.remove(windowId);
    _windows.remove(windowId);
    
    debugPrint('🗑️ Closed window: $windowId');
  }
  
  /// Close session
  void closeSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    
    // Close all windows in session
    for (final windowId in session.windows) {
      final window = _windows[windowId];
      if (window != null) {
        for (final paneId in window.panes) {
          _panes.remove(paneId);
        }
        _windows.remove(windowId);
      }
    }
    
    _sessions.remove(sessionId);
    debugPrint('🗑️ Closed session: $sessionId');
  }
  
  /// Switch active pane
  void switchPane(String paneId) {
    final pane = _panes[paneId];
    if (pane == null) return;
    
    final window = _windows[pane.windowId];
    if (window == null) return;
    
    window.activePaneId = paneId;
    debugPrint('🔄 Switched to pane: $paneId');
  }
  
  /// Switch active window
  void switchWindow(String windowId) {
    final window = _windows[windowId];
    if (window == null) return;
    
    final session = _sessions[window.sessionId];
    if (session == null) return;
    
    session.activeWindowId = windowId;
    debugPrint('🔄 Switched to window: $windowId');
  }
  
  /// Switch active session
  void switchSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    
    // Set as active session
    for (final s in _sessions.values) {
      s.isActive = false;
    }
    session.isActive = true;
    
    debugPrint('🔄 Switched to session: $sessionId');
  }
  
  /// Attach terminal session to pane
  void attachTerminalSession(String paneId, TerminalSession terminalSession) {
    final pane = _panes[paneId];
    if (pane == null) return;
    
    pane.terminalSession = terminalSession;
    pane.type = PaneType.terminal;
    
    debugPrint('🔗 Attached terminal session to pane: $paneId');
  }
  
  /// Detach terminal session from pane
  void detachTerminalSession(String paneId) {
    final pane = _panes[paneId];
    if (pane == null) return;
    
    pane.terminalSession = null;
    pane.type = PaneType.empty;
    
    debugPrint('🔓 Detached terminal session from pane: $paneId');
  }
  
  /// Setup remote synchronization
  void setupRemoteSync(String sessionId, String serverUrl, String authToken) {
    final syncClient = RemoteSyncClient(
      sessionId: sessionId,
      serverUrl: serverUrl,
      authToken: authToken,
    );
    
    _syncClients[sessionId] = syncClient;
    syncClient.connect();
    
    debugPrint('🌐 Setup remote sync for session: $sessionId');
  }
  
  /// Persist sessions to disk
  Future<void> _persistSessions() async {
    if (_persistencePath == null) return;
    
    try {
      final sessionsData = <String, dynamic>{
        'sessions': _sessions.map((key, session) => MapEntry(key, session.toJson())),
        'windows': _windows.map((key, window) => MapEntry(key, window.toJson())),
        'panes': _panes.map((key, pane) => MapEntry(key, pane.toJson())),
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final file = File('$_persistencePath/sessions.json');
      await file.writeAsString(jsonEncode(sessionsData));
      
      debugPrint('💾 Persisted ${_sessions.length} sessions');
    } catch (e) {
      debugPrint('⚠️ Failed to persist sessions: $e');
    }
  }
  
  /// Load persisted sessions from disk
  Future<void> _loadPersistedSessions() async {
    if (_persistencePath == null) return;
    
    try {
      final file = File('$_persistencePath/sessions.json');
      if (!await file.exists()) return;
      
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      // Load sessions
      final sessionsData = data['sessions'] as Map<String, dynamic>?;
      if (sessionsData != null) {
        for (final entry in sessionsData.entries) {
          final session = MultiplexedSession.fromJson(entry.value as Map<String, dynamic>);
          _sessions[entry.key] = session;
        }
      }
      
      // Load windows
      final windowsData = data['windows'] as Map<String, dynamic>?;
      if (windowsData != null) {
        for (final entry in windowsData.entries) {
          final window = MultiplexedWindow.fromJson(entry.value as Map<String, dynamic>);
          _windows[entry.key] = window;
        }
      }
      
      // Load panes
      final panesData = data['panes'] as Map<String, dynamic>?;
      if (panesData != null) {
        for (final entry in panesData.entries) {
          final pane = MultiplexedPane.fromJson(entry.value as Map<String, dynamic>);
          _panes[entry.key] = pane;
        }
      }
      
      debugPrint('📂 Loaded ${_sessions.length} persisted sessions');
    } catch (e) {
      debugPrint('⚠️ Failed to load persisted sessions: $e');
    }
  }
  
  /// Get session by ID
  MultiplexedSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }
  
  /// Get window by ID
  MultiplexedWindow? getWindow(String windowId) {
    return _windows[windowId];
  }
  
  /// Get pane by ID
  MultiplexedPane? getPane(String paneId) {
    return _panes[paneId];
  }
  
  /// Get active session
  MultiplexedSession? getActiveSession() {
    return _sessions.values.firstWhere(
      (session) => session.isActive,
      orElse: () => _sessions.values.first,
    );
  }
  
  /// Get active window
  MultiplexedWindow? getActiveWindow() {
    final activeSession = getActiveSession();
    if (activeSession?.activeWindowId == null) return null;
    return _windows[activeSession!.activeWindowId!];
  }
  
  /// Get active pane
  MultiplexedPane? getActivePane() {
    final activeWindow = getActiveWindow();
    if (activeWindow?.activePaneId == null) return null;
    return _panes[activeWindow!.activePaneId!];
  }
  
  /// Dispose resources
  void dispose() {
    _persistenceTimer?.cancel();
    _persistSessions();
    
    for (final client in _syncClients.values) {
      client.disconnect();
    }
    
    _sessions.clear();
    _windows.clear();
    _panes.clear();
    _syncClients.clear();
    
    _isInitialized = false;
    debugPrint('🔀 Terminal Multiplexer disposed');
  }
}

/// Multiplexed session data structure
class MultiplexedSession {
  final String id;
  final String name;
  final String? command;
  final Map<String, String> environment;
  final bool persistent;
  final DateTime createdAt;
  
  List<String> windows = [];
  String? activeWindowId;
  bool isActive = false;
  
  MultiplexedSession({
    required this.id,
    required this.name,
    this.command,
    required this.environment,
    required this.persistent,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'environment': environment,
    'persistent': persistent,
    'createdAt': createdAt.toIso8601String(),
    'windows': windows,
    'activeWindowId': activeWindowId,
    'isActive': isActive,
  };
  
  factory MultiplexedSession.fromJson(Map<String, dynamic> json) => MultiplexedSession(
    id: json['id'] as String,
    name: json['name'] as String,
    command: json['command'] as String?,
    environment: Map<String, String>.from(json['environment'] as Map),
    persistent: json['persistent'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Multiplexed window data structure
class MultiplexedWindow {
  final String id;
  final String sessionId;
  final String name;
  final DateTime createdAt;
  
  WindowLayout layout = WindowLayout.single;
  List<String> panes = [];
  String? activePaneId;
  
  MultiplexedWindow({
    required this.id,
    required this.sessionId,
    required this.name,
    this.layout = WindowLayout.single,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'name': name,
    'layout': layout.index,
    'panes': panes,
    'activePaneId': activePaneId,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory MultiplexedWindow.fromJson(Map<String, dynamic> json) => MultiplexedWindow(
    id: json['id'] as String,
    sessionId: json['sessionId'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  )..layout = WindowLayout.values[json['layout'] as int? ?? 0]
   ..panes = List<String>.from(json['panes'] as List)
   ..activePaneId = json['activePaneId'] as String?;
}

/// Multiplexed pane data structure
class MultiplexedPane {
  final String id;
  final String windowId;
  final String name;
  final DateTime createdAt;
  
  PaneType type = PaneType.empty;
  double widthRatio = 1.0;
  double heightRatio = 1.0;
  TerminalSession? terminalSession;
  
  MultiplexedPane({
    required this.id,
    required this.windowId,
    required this.name,
    this.type = PaneType.empty,
    this.widthRatio = 1.0,
    this.heightRatio = 1.0,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'windowId': windowId,
    'name': name,
    'type': type.index,
    'widthRatio': widthRatio,
    'heightRatio': heightRatio,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory MultiplexedPane.fromJson(Map<String, dynamic> json) => MultiplexedPane(
    id: json['id'] as String,
    windowId: json['windowId'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  )..type = PaneType.values[json['type'] as int? ?? 0]
   ..widthRatio = json['widthRatio'] as double? ?? 1.0
   ..heightRatio = json['heightRatio'] as double? ?? 1.0;
}

/// Window layout enumeration
enum WindowLayout {
  single,
  horizontalSplit,
  verticalSplit,
  grid,
}

/// Pane type enumeration
enum PaneType {
  empty,
  terminal,
  editor,
  fileManager,
  browser,
}

/// Remote synchronization client
class RemoteSyncClient {
  final String sessionId;
  final String serverUrl;
  final String authToken;
  
  WebSocket? _channel;
  
  RemoteSyncClient({
    required this.sessionId,
    required this.serverUrl,
    required this.authToken,
  });
  
  Future<void> connect() async {
    try {
      _channel = await WebSocket.connect(
        '$serverUrl/sync/$sessionId',
        protocols: ['termisol-sync'],
      );
      
      _channel!.add(jsonEncode({
        'type': 'auth',
        'token': authToken,
      }));
      
      _channel!.listen(_handleMessage);
      
      debugPrint('🌐 Connected to sync server for session: $sessionId');
    } catch (e) {
      debugPrint('❌ Failed to connect to sync server: $e');
    }
  }
  
  void disconnect() {
    _channel?.close();
    _channel = null;
    debugPrint('🌐 Disconnected from sync server for session: $sessionId');
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String;
      
      switch (type) {
        case 'sync':
          _handleSyncMessage(data);
          break;
        case 'command':
          _handleCommandMessage(data);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle sync message: $e');
    }
  }
  
  void _handleSyncMessage(Map<String, dynamic> data) {
    // Handle session synchronization
    debugPrint('🔄 Received sync message for session: $sessionId');
  }
  
  void _handleCommandMessage(Map<String, dynamic> data) {
    // Handle remote commands
    debugPrint('📥 Received remote command for session: $sessionId');
  }
  
  void sendSyncMessage(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.add(jsonEncode({
        'type': 'sync',
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      }));
    }
  }
}
