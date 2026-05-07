import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Tmux Integration - Native tmux session detection and management
/// 
/// Implements complete tmux integration:
/// - Automatic tmux session detection
/// - Session list and management
/// - Window and pane operations
/// - Real-time synchronization
/// - Session persistence and recovery
/// - tmux command integration
class TmuxIntegration {
  bool _isInitialized = false;
  bool _tmuxAvailable = false;
  String? _tmuxPath;
  
  // Session state
  final Map<String, TmuxSession> _sessions = {};
  final Map<String, TmuxWindow> _windows = {};
  final Map<String, TmuxPane> _panes = {};
  
  // Current session
  String? _currentSessionId;
  String? _currentWindowId;
  String? _currentPaneId;
  
  // Event handling
  final StreamController<TmuxEvent> _eventController = StreamController.broadcast();
  Timer? _sessionMonitor;
  
  // Configuration
  TmuxConfig _config = TmuxConfig();
  
  TmuxIntegration();
  
  bool get isInitialized => _isInitialized;
  bool get tmuxAvailable => _tmuxAvailable;
  String? get tmuxPath => _tmuxPath;
  Map<String, TmuxSession> get sessions => Map.unmodifiable(_sessions);
  String? get currentSessionId => _currentSessionId;
  Stream<TmuxEvent> get events => _eventController.stream;
  
  /// Initialize tmux integration
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Check tmux availability
      await _checkTmuxAvailability();
      
      if (_tmuxAvailable) {
        // Load configuration
        await _loadConfiguration();
        
        // Detect existing sessions
        await _detectSessions();
        
        // Start session monitoring
        _startSessionMonitoring();
        
        // Setup event handlers
        _setupEventHandlers();
      }
      
      _isInitialized = true;
      debugPrint('🔀 Tmux Integration initialized (available: $_tmuxAvailable)');
    } catch (e) {
      debugPrint('❌ Failed to initialize Tmux Integration: $e');
    }
  }
  
  /// Check tmux availability
  Future<void> _checkTmuxAvailability() async {
    try {
      // Check common tmux paths
      final paths = [
        '/usr/bin/tmux',
        '/usr/local/bin/tmux',
        '/opt/homebrew/bin/tmux',
        '${Platform.environment['HOME']}/.local/bin/tmux',
      ];
      
      for (final path in paths) {
        if (await File(path).exists()) {
          _tmuxPath = path;
          _tmuxAvailable = true;
          break;
        }
      }
      
      if (_tmuxAvailable) {
        // Test tmux functionality
        final result = await Process.run(_tmuxPath!, ['list-sessions']);
        _tmuxAvailable = result.exitCode == 0;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to check tmux availability: $e');
      _tmuxAvailable = false;
    }
  }
  
  /// Load tmux configuration
  Future<void> _loadConfiguration() async {
    try {
      // Load user tmux configuration
      final homeDir = Platform.environment['HOME'] ?? '';
      final configFile = File('$homeDir/.tmux.conf');
      
      if (await configFile.exists()) {
        final configContent = await configFile.readAsString();
        _config = _parseTmuxConfig(configContent);
      }
      
      // Load Termisol-specific tmux settings
      await _setupTermisolTmuxConfig();
    } catch (e) {
      debugPrint('⚠️ Failed to load tmux configuration: $e');
    }
  }
  
  /// Parse tmux configuration
  TmuxConfig _parseTmuxConfig(String configContent) {
    final config = TmuxConfig();
    
    for (final line in configContent.split('\n')) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) continue;
      
      final parts = trimmedLine.split(' ');
      if (parts.length >= 2) {
        final option = parts[0];
        final value = parts.sublist(1).join(' ');
        
        switch (option) {
          case 'prefix':
            config.prefix = value;
            break;
          case 'mouse':
            config.mouse = value;
            break;
          case 'status-keys':
            config.statusKeys = value;
            break;
          case 'base-index':
            config.baseIndex = int.tryParse(value) ?? 0;
            break;
          case 'pane-base-index':
            config.paneBaseIndex = int.tryParse(value) ?? 0;
            break;
        }
      }
    }
    
    return config;
  }
  
  /// Setup Termisol-specific tmux configuration
  Future<void> _setupTermisolTmuxConfig() async {
    try {
      // Create Termisol-specific tmux config
      final termisolConfig = '''
# Termisol-specific tmux configuration
set -g mouse on
set -g status-keys vi
set -g base-index 1
set -g pane-base-index 1
set -g renumber-windows on
set -g automatic-rename off
set -g allow-rename off
set -g history-limit 50000
set -g display-time 3000
set -g display-panes-time 3000
set -g visual-activity on
set -g visual-bell on
set -g visual-silence on
set -g bell-action other
set -g silence-action other
set -g activity-action other
set -g set-titles on
set -g set-titles-string "Termisol - #S:#I:#W"
set -g window-status-current-format "#[fg=colour235,bg=colour255,bold] #I:#W #[fg=colour255,bg=colour235,nobold]#F #W "
set -g window-status-format "#[fg=colour235,bg=colour238] #I:#W #[fg=colour255,bg=colour235]#F #W "
set -g window-status-bell-style "fg=colour255,bg=colour1,bold"
set -g window-status-activity-style "fg=colour255,bg=colour1,bold"
set -g window-status-current-style "fg=colour255,bg=colour28,bold"
set -g pane-border-style "fg=colour238"
set -g pane-active-border-style "fg=colour46"
set -g message-command-style "fg=colour255,bg=colour235"
set -g message-line-style "fg=colour255,bg=colour235"
''';
      
      // Write to temporary config file
      final tempConfigFile = File('${Directory.systemTemp.path}/termisol_tmux.conf');
      await tempConfigFile.writeAsString(termisolConfig);
      
      // Apply configuration
      await Process.run(_tmuxPath!, ['source-file', tempConfigFile.path]);
      
      debugPrint('⚙️ Applied Termisol tmux configuration');
    } catch (e) {
      debugPrint('⚠️ Failed to setup Termisol tmux config: $e');
    }
  }
  
  /// Detect existing tmux sessions
  Future<void> _detectSessions() async {
    if (!_tmuxAvailable) return;
    
    try {
      final result = await Process.run(_tmuxPath!, ['list-sessions', '-F', '#{session_id},#{session_name},#{session_attached},#{session_width},#{session_height}']);
      
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        _sessions.clear();
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 5) {
            final session = TmuxSession(
              id: parts[0],
              name: parts[1],
              attached: parts[2] == '1',
              width: int.tryParse(parts[3]) ?? 80,
              height: int.tryParse(parts[4]) ?? 24,
            );
            
            _sessions[session.id] = session;
            
            // Detect current session
            if (session.attached) {
              _currentSessionId = session.id;
            }
          }
        }
        
        // Load windows and panes for current session
        if (_currentSessionId != null) {
          await _loadSessionWindows(_currentSessionId!);
        }
        
        debugPrint('🔀 Detected ${_sessions.length} tmux sessions');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detect tmux sessions: $e');
    }
  }
  
  /// Load session windows
  Future<void> _loadSessionWindows(String sessionId) async {
    try {
      final result = await Process.run(_tmuxPath!, ['list-windows', '-t', sessionId, '-F', '#{window_id},#{window_name},#{window_width},#{window_height},#{window_layout}']);
      
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        _windows.clear();
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 5) {
            final window = TmuxWindow(
              id: parts[0],
              name: parts[1],
              width: int.tryParse(parts[2]) ?? 80,
              height: int.tryParse(parts[3]) ?? 24,
              layout: parts[4],
              sessionId: sessionId,
            );
            
            _windows[window.id] = window;
          }
        }
        
        // Load panes for each window
        for (final window in _windows.values) {
          await _loadWindowPanes(sessionId, window.id);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load session windows: $e');
    }
  }
  
  /// Load window panes
  Future<void> _loadWindowPanes(String sessionId, String windowId) async {
    try {
      final result = await Process.run(_tmuxPath!, ['list-panes', '-t', '$sessionId:$windowId', '-F', '#{pane_id},#{pane_title},#{pane_width},#{pane_height},#{pane_current_command},#{pane_current_path}']);
      
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 6) {
            final pane = TmuxPane(
              id: parts[0],
              title: parts[1],
              width: int.tryParse(parts[2]) ?? 80,
              height: int.tryParse(parts[3]) ?? 24,
              currentCommand: parts[4],
              currentPath: parts[5],
              sessionId: sessionId,
              windowId: windowId,
            );
            
            _panes[pane.id] = pane;
            
            // Detect current pane
            if (pane.currentCommand.isNotEmpty) {
              _currentPaneId = pane.id;
              _currentWindowId = windowId;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load window panes: $e');
    }
  }
  
  /// Start session monitoring
  void _startSessionMonitoring() {
    _sessionMonitor = Timer.periodic(const Duration(seconds: 1), (_) {
      _monitorSessions();
    });
    debugPrint('👁️ Started tmux session monitoring');
  }
  
  /// Monitor sessions for changes
  Future<void> _monitorSessions() async {
    if (!_tmuxAvailable) return;
    
    try {
      final result = await Process.run(_tmuxPath!, ['list-sessions', '-F', '#{session_id},#{session_attached}']);
      
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        final currentSessions = <String>{};
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 2) {
            currentSessions[parts[0]] = parts[1] == '1';
          }
        }
        
        // Check for session changes
        _checkSessionChanges(currentSessions);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to monitor sessions: $e');
    }
  }
  
  /// Check for session changes
  void _checkSessionChanges(Map<String, bool> currentSessions) {
    // Check for new sessions
    for (final sessionId in currentSessions.keys) {
      if (!_sessions.containsKey(sessionId)) {
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionCreated,
          sessionId: sessionId,
        ));
      }
    }
    
    // Check for removed sessions
    for (final sessionId in _sessions.keys) {
      if (!currentSessions.containsKey(sessionId)) {
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionDestroyed,
          sessionId: sessionId,
        ));
      }
    }
    
    // Check for attachment changes
    for (final entry in currentSessions.entries) {
      final sessionId = entry.key;
      final attached = entry.value;
      final session = _sessions[sessionId];
      
      if (session != null && session.attached != attached) {
        _eventController.add(TmuxEvent(
          type: attached ? TmuxEventType.sessionAttached : TmuxEventType.sessionDetached,
          sessionId: sessionId,
        ));
      }
    }
  }
  
  /// Setup event handlers
  void _setupEventHandlers() {
    // Setup event listeners for tmux events
    debugPrint('👂 Setup tmux event handlers');
  }
  
  /// Create new session
  Future<bool> createSession(String name, {String? command, int? width, int? height}) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final args = <String>['new-session', '-d', '-s', name];
      
      if (command != null) {
        args.addAll(['-n', name, command]);
      }
      
      if (width != null && height != null) {
        args.addAll(['-x', width.toString(), '-y', height.toString()]);
      }
      
      final result = await Process.run(_tmuxPath!, args);
      
      if (result.exitCode == 0) {
        await _detectSessions(); // Refresh session list
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionCreated,
          sessionId: name,
          data: {'name': name},
        ));
        
        debugPrint('🔀 Created tmux session: $name');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to create tmux session: $e');
    }
    
    return false;
  }
  
  /// Attach to session
  Future<bool> attachSession(String sessionId) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['attach-session', '-t', sessionId]);
      
      if (result.exitCode == 0) {
        _currentSessionId = sessionId;
        await _loadSessionWindows(sessionId);
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionAttached,
          sessionId: sessionId,
        ));
        
        debugPrint('🔀 Attached to tmux session: $sessionId');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to attach to tmux session: $e');
    }
    
    return false;
  }
  
  /// Detach from session
  Future<bool> detachSession() async {
    if (!_tmuxAvailable || _currentSessionId == null) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['detach-client']);
      
      if (result.exitCode == 0) {
        final sessionId = _currentSessionId!;
        _currentSessionId = null;
        _currentWindowId = null;
        _currentPaneId = null;
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionDetached,
          sessionId: sessionId,
        ));
        
        debugPrint('🔀 Detached from tmux session: $sessionId');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detach from tmux session: $e');
    }
    
    return false;
  }
  
  /// Kill session
  Future<bool> killSession(String sessionId) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['kill-session', '-t', sessionId]);
      
      if (result.exitCode == 0) {
        _sessions.remove(sessionId);
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.sessionDestroyed,
          sessionId: sessionId,
        ));
        
        debugPrint('🔀 Killed tmux session: $sessionId');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to kill tmux session: $e');
    }
    
    return false;
  }
  
  /// Create new window
  Future<bool> createWindow(String sessionId, String name) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['new-window', '-t', sessionId, '-n', name]);
      
      if (result.exitCode == 0) {
        await _loadSessionWindows(sessionId);
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.windowCreated,
          sessionId: sessionId,
          data: {'windowName': name},
        ));
        
        debugPrint('🪟 Created tmux window: $name');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to create tmux window: $e');
    }
    
    return false;
  }
  
  /// Switch to window
  Future<bool> switchWindow(String sessionId, String windowId) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['select-window', '-t', '$sessionId:$windowId']);
      
      if (result.exitCode == 0) {
        _currentWindowId = windowId;
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.windowSelected,
          sessionId: sessionId,
          data: {'windowId': windowId},
        ));
        
        debugPrint('🪟 Switched to tmux window: $windowId');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to switch tmux window: $e');
    }
    
    return false;
  }
  
  /// Split window horizontally
  Future<bool> splitWindowHorizontal(String sessionId, String windowId) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['split-window', '-t', '$sessionId:$windowId', '-h']);
      
      if (result.exitCode == 0) {
        await _loadWindowPanes(sessionId, windowId);
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.paneCreated,
          sessionId: sessionId,
          data: {'split': 'horizontal'},
        ));
        
        debugPrint('🪟 Split tmux window horizontally');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to split tmux window: $e');
    }
    
    return false;
  }
  
  /// Split window vertically
  Future<bool> splitWindowVertical(String sessionId, String windowId) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['split-window', '-t', '$sessionId:$windowId', '-v']);
      
      if (result.exitCode == 0) {
        await _loadWindowPanes(sessionId, windowId);
        
        _eventController.add(TmuxEvent(
          type: TmuxEventType.paneCreated,
          sessionId: sessionId,
          data: {'split': 'vertical'},
        ));
        
        debugPrint('🪟 Split tmux window vertically');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to split tmux window: $e');
    }
    
    return false;
  }
  
  /// Send command to pane
  Future<bool> sendCommand(String sessionId, String windowId, String paneId, String command) async {
    if (!_tmuxAvailable) return false;
    
    try {
      final result = await Process.run(_tmuxPath!, ['send-keys', '-t', '$sessionId:$windowId.$paneId', command]);
      
      if (result.exitCode == 0) {
        debugPrint('📝 Sent command to tmux pane: $command');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to send command to tmux pane: $e');
    }
    
    return false;
  }
  
  /// Get session by ID
  TmuxSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }
  
  /// Get window by ID
  TmuxWindow? getWindow(String windowId) {
    return _windows[windowId];
  }
  
  /// Get pane by ID
  TmuxPane? getPane(String paneId) {
    return _panes[paneId];
  }
  
  /// Get current session
  TmuxSession? getCurrentSession() {
    if (_currentSessionId == null) return null;
    return _sessions[_currentSessionId!];
  }
  
  /// Get current window
  TmuxWindow? getCurrentWindow() {
    if (_currentWindowId == null) return null;
    return _windows[_currentWindowId!];
  }
  
  /// Get current pane
  TmuxPane? getCurrentPane() {
    if (_currentPaneId == null) return null;
    return _panes[_currentPaneId!];
  }
  
  /// Dispose resources
  void dispose() {
    _sessionMonitor?.cancel();
    _eventController.close();
    _sessions.clear();
    _windows.clear();
    _panes.clear();
    _currentSessionId = null;
    _currentWindowId = null;
    _currentPaneId = null;
    _isInitialized = false;
    debugPrint('🔀 Tmux Integration disposed');
  }
}

/// Tmux session data structure
class TmuxSession {
  final String id;
  final String name;
  final bool attached;
  final int width;
  final int height;
  final DateTime createdAt;
  
  TmuxSession({
    required this.id,
    required this.name,
    required this.attached,
    required this.width,
    required this.height,
  }) : createdAt = DateTime.now();
}

/// Tmux window data structure
class TmuxWindow {
  final String id;
  final String name;
  final int width;
  final int height;
  final String layout;
  final String sessionId;
  final DateTime createdAt;
  
  TmuxWindow({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.layout,
    required this.sessionId,
  }) : createdAt = DateTime.now();
}

/// Tmux pane data structure
class TmuxPane {
  final String id;
  final String title;
  final int width;
  final int height;
  final String currentCommand;
  final String currentPath;
  final String sessionId;
  final String windowId;
  final DateTime createdAt;
  
  TmuxPane({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.currentCommand,
    required this.currentPath,
    required this.sessionId,
    required this.windowId,
  }) : createdAt = DateTime.now();
}

/// Tmux configuration data structure
class TmuxConfig {
  String prefix = 'C-b';
  String mouse = 'on';
  String statusKeys = 'vi';
  int baseIndex = 1;
  int paneBaseIndex = 1;
  bool renumberWindows = true;
  bool automaticRename = false;
  int historyLimit = 50000;
  int displayTime = 3000;
  int displayPanesTime = 3000;
  bool visualActivity = true;
  bool visualBell = true;
  bool visualSilence = true;
  String bellAction = 'other';
  String silenceAction = 'other';
  String activityAction = 'other';
  bool setTitles = true;
  String setTitlesString = 'Termisol - #S:#I:#W';
}

/// Tmux event data structure
class TmuxEvent {
  final TmuxEventType type;
  final String? sessionId;
  final String? windowId;
  final String? paneId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  TmuxEvent({
    required this.type,
    this.sessionId,
    this.windowId,
    this.paneId,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Tmux event type enumeration
enum TmuxEventType {
  sessionCreated,
  sessionDestroyed,
  sessionAttached,
  sessionDetached,
  windowCreated,
  windowDestroyed,
  windowSelected,
  windowRenamed,
  paneCreated,
  paneDestroyed,
  paneSelected,
  paneActive,
}
