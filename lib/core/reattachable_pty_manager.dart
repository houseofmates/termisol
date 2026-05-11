import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pty/pty.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'pty_backend.dart';

/// Re-attachable PTY manager with socket-based session persistence.
class ReattachablePtyManager {
  static final ReattachablePtyManager _instance = ReattachablePtyManager._internal();
  factory ReattachablePtyManager() => _instance;
  ReattachablePtyManager._internal();

  bool _isInitialized = false;
  final Map<String, PtySession> _sessions = {};
  final Map<String, ServerSocket> _servers = {};
  final Map<String, Socket> _clients = {};
  
  Timer? _cleanupTimer;
  Timer? _heartbeatTimer;
  
  Directory? _socketDir;
  String? _instanceId;
  
  static const int _maxSessions = 100;
  static const Duration _sessionTimeout = Duration(hours: 24);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _cleanupInterval = Duration(minutes: 5);

  bool get isInitialized => _isInitialized;
  int get activeSessions => _sessions.length;
  List<String> get sessionIds => _sessions.keys.toList();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _setupSocketDirectory();
      await _generateInstanceId();
      await _startHeartbeat();
      await _startCleanup();
      await _recoverExistingSessions();

      _isInitialized = true;
      debugPrint('Reattachable PTY Manager initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize Reattachable PTY Manager: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _setupSocketDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _socketDir = Directory('${appDir.path}/.termisol/sockets');
      await _socketDir!.create(recursive: true);
      
      // Set proper permissions for socket directory
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('chmod', ['700', _socketDir!.path]);
        if (result.exitCode != 0) {
          debugPrint('Failed to set socket directory permissions: ${result.stderr}');
        }
      }
      
      debugPrint('Socket directory created: ${_socketDir!.path}');
    } catch (e, stack) {
      debugPrint('Failed to setup socket directory: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _generateInstanceId() async {
    try {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      final digest = sha256.convert(bytes);
      _instanceId = digest.toString().substring(0, 8);
      
      final instanceFile = File('${_socketDir!.path}/instance_id');
      await instanceFile.writeAsString(_instanceId!);
      
      debugPrint('Instance ID: $_instanceId');
    } catch (e, stack) {
      debugPrint('Failed to generate instance ID: $e\n$stack');
      _instanceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _startHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    try {
      final heartbeatFile = File('${_socketDir!.path}/heartbeat');
      final heartbeatData = {
        'instance_id': _instanceId,
        'timestamp': DateTime.now().toIso8601String(),
        'sessions': _sessions.length,
        'pid': pid,
      };
      heartbeatFile.writeAsStringSync(jsonEncode(heartbeatData));
    } catch (e) {
      debugPrint('Failed to send heartbeat: $e');
    }
  }

  Future<void> _startCleanup() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  Future<void> _performCleanup() async {
    try {
      await _cleanupDeadSessions();
      await _cleanupOldSockets();
      await _cleanupStaleHeartbeats();
    } catch (e) {
      debugPrint('Cleanup failed: $e');
    }
  }

  Future<void> _cleanupDeadSessions() async {
    final deadSessions = <String>[];
    
    for (final entry in _sessions.entries) {
      final session = entry.value;
      if (!session.isAlive || DateTime.now().difference(session.lastActivity) > _sessionTimeout) {
        deadSessions.add(entry.key);
      }
    }
    
    for (final sessionId in deadSessions) {
      await detachSession(sessionId);
    }
    
    if (deadSessions.isNotEmpty) {
      debugPrint('Cleaned up ${deadSessions.length} dead sessions');
    }
  }

  Future<void> _cleanupOldSockets() async {
    try {
      if (_socketDir == null) return;
      
      await for (final entity in _socketDir!.list()) {
        if (entity is File && entity.path.endsWith('.sock')) {
          try {
            final stat = await entity.stat();
            if (DateTime.now().difference(stat.modified) > _sessionTimeout) {
              await entity.delete();
            }
          } catch (e) {
            // Socket might be in use, ignore
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup old sockets: $e');
    }
  }

  Future<void> _cleanupStaleHeartbeats() async {
    try {
      if (_socketDir == null) return;
      
      final heartbeatFile = File('${_socketDir!.path}/heartbeat');
      if (await heartbeatFile.exists()) {
        final content = await heartbeatFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final timestamp = DateTime.parse(data['timestamp'] as String);
        
        if (DateTime.now().difference(timestamp) > const Duration(minutes: 2)) {
          debugPrint('Stale heartbeat detected, possible crash recovery needed');
          await _handleStaleHeartbeat(data);
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup stale heartbeats: $e');
    }
  }

  Future<void> _handleStaleHeartbeat(Map<String, dynamic> data) async {
    try {
      final instanceId = data['instance_id'] as String?;
      if (instanceId != _instanceId) {
        debugPrint('Different instance detected, recovering sessions');
        await _recoverExistingSessions();
      }
    } catch (e) {
      debugPrint('Failed to handle stale heartbeat: $e');
    }
  }

  Future<void> _recoverExistingSessions() async {
    try {
      if (_socketDir == null) return;
      
      await for (final entity in _socketDir!.list()) {
        if (entity is File && entity.path.endsWith('.session')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;
            final session = PtySession.fromJson(data);
            
            if (session.isValid) {
              _sessions[session.id] = session;
              debugPrint('Recovered session: ${session.id}');
            } else {
              await entity.delete();
            }
          } catch (e) {
            debugPrint('Failed to recover session from ${entity.path}: $e');
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to recover existing sessions: $e');
    }
  }

  Future<String> createSession({
    required String workingDirectory,
    required String shell,
    Map<String, String>? environment,
    int cols = 80,
    int rows = 24,
  }) async {
    if (_sessions.length >= _maxSessions) {
      throw StateError('Maximum number of sessions reached');
    }

    final sessionId = _generateSessionId();
    
    try {
      // Create PTY session
      final pty = PseudoTerminal.start(
        shell,
        [],
        workingDirectory: workingDirectory,
        environment: environment ?? {},
      );
      
      final session = PtySession(
        id: sessionId,
        pty: pty,
        workingDirectory: workingDirectory,
        shell: shell,
        environment: environment ?? {},
        createdAt: DateTime.now(),
        lastActivity: DateTime.now(),
      );
      
      _sessions[sessionId] = session;
      await _saveSession(session);
      await _startSessionServer(session);
      
      debugPrint('Created session: $sessionId');
      return sessionId;
    } catch (e, stack) {
      debugPrint('Failed to create session: $e\n$stack');
      rethrow;
    }
  }

  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(9999);
    return 'pty_${timestamp}_$random';
  }

  Future<void> _saveSession(PtySession session) async {
    try {
      if (_socketDir == null) return;
      
      final sessionFile = File('${_socketDir!.path}/${session.id}.session');
      await sessionFile.writeAsString(jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('Failed to save session ${session.id}: $e');
    }
  }

  Future<void> _startSessionServer(PtySession session) async {
    try {
      if (_socketDir == null) return;
      
      final socketPath = '${_socketDir!.path}/${session.id}.sock';
      
      // Clean up existing socket if present
      if (await File(socketPath).exists()) {
        await File(socketPath).delete();
      }
      
      final server = await ServerSocket.bind(socketPath, 0);
      
      _servers[session.id] = server;
      
      server.listen((client) {
        _clients[session.id] = client;
        _handleClient(session, client);
      });
      
      debugPrint('Session server started for ${session.id} at $socketPath');
    } catch (e, stack) {
      debugPrint('Failed to start session server for ${session.id}: $e\n$stack');
      rethrow;
    }
  }

  void _handleClient(PtySession session, Socket client) {
    debugPrint('Client connected to session ${session.id}');
    
    // Send session metadata
    client.writeln(jsonEncode({
      'type': 'session_info',
      'session_id': session.id,
      'working_directory': session.workingDirectory,
      'shell': session.shell,
      'created_at': session.createdAt.toIso8601String(),
    }));
    
    // Forward PTY output to client
    session.output.listen((data) {
      try {
        client.add(data);
      } catch (e) {
        // Socket closed, ignore
      }
    });
    
    // Handle client input
    client.listen(
      (data) {
        session.write(data);
        session.lastActivity = DateTime.now();
      },
      onDone: () {
        debugPrint('Client disconnected from session ${session.id}');
        _clients.remove(session.id);
      },
      onError: (e) {
        debugPrint('Client error for session ${session.id}: $e');
        _clients.remove(session.id);
      },
    );
  }

  Future<Stream<List<int>>> attachToSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }
    
    try {
      if (_socketDir == null) throw StateError('Socket directory not initialized');
      
      final socketPath = '${_socketDir!.path}/$sessionId.sock';
      final socket = await Socket.connect(socketPath, 0);
      
      final controller = StreamController<List<int>>();
      
      socket.listen(
        (data) {
          if (!controller.isClosed) {
            controller.add(data);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
        onError: (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        },
      );
      
      debugPrint('Attached to session: $sessionId');
      return controller.stream;
    } catch (e, stack) {
      debugPrint('Failed to attach to session $sessionId: $e\n$stack');
      rethrow;
    }
  }

  Future<void> writeSession(String sessionId, List<int> data) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }
    
    session.write(data);
    session.lastActivity = DateTime.now();
    await _saveSession(session);
  }

  Future<void> resizeSession(String sessionId, int cols, int rows) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }
    
    session.resize(cols, rows);
    session.lastActivity = DateTime.now();
    await _saveSession(session);
  }

  Future<void> detachSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    
    try {
      await session.terminate();
      
      // Close server
      final server = _servers.remove(sessionId);
      if (server != null) {
        await server.close();
      }
      
      // Close client
      final client = _clients.remove(sessionId);
      if (client != null) {
        await client.close();
      }
      
      // Remove session file
      if (_socketDir != null) {
        final sessionFile = File('${_socketDir!.path}/$sessionId.session');
        if (await sessionFile.exists()) {
          await sessionFile.delete();
        }
        
        final socketFile = File('${_socketDir!.path}/$sessionId.sock');
        if (await socketFile.exists()) {
          await socketFile.delete();
        }
      }
      
      debugPrint('Detached session: $sessionId');
    } catch (e, stack) {
      debugPrint('Failed to detach session $sessionId: $e\n$stack');
    }
  }

  Future<Map<String, dynamic>> getSessionInfo(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw ArgumentError('Session not found: $sessionId');
    }
    
    return session.toJson();
  }

  Future<List<Map<String, dynamic>>> getAllSessionsInfo() async {
    return _sessions.values.map((session) => session.toJson()).toList();
  }

  Future<bool> isSessionAlive(String sessionId) async {
    final session = _sessions[sessionId];
    return session?.isAlive ?? false;
  }

  Future<PtySession?> getSession(String sessionId) async {
    return _sessions[sessionId];
  }

  Future<void> updateSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session != null) {
      session.lastActivity = DateTime.now();
    }
  }

  Future<void> performCleanup() async {
    await _performCleanup();
  }

  String get instanceId => _instanceId ?? 'unknown';

  Future<void> terminateAllSessions() async {
    final sessionIds = _sessions.keys.toList();
    for (final sessionId in sessionIds) {
      await detachSession(sessionId);
    }

    debugPrint('All sessions terminated');
  }

  Future<void> dispose() async {
    try {
      _heartbeatTimer?.cancel();
      _cleanupTimer?.cancel();
      
      await terminateAllSessions();
      
      // Close all servers
      for (final server in _servers.values) {
        await server.close();
      }
      _servers.clear();
      
      // Close all clients
      for (final client in _clients.values) {
        await client.close();
      }
      _clients.clear();
      
      debugPrint('Reattachable PTY Manager disposed');
    } catch (e, stack) {
      debugPrint('Error disposing Reattachable PTY Manager: $e\n$stack');
    }
  }
}

class PtySession {
  final String id;
  final PseudoTerminal pty;
  final String workingDirectory;
  final String shell;
  final Map<String, String> environment;
  DateTime createdAt;
  DateTime lastActivity;
  bool _isAlive = true;

  PtySession({
    required this.id,
    required this.pty,
    required this.workingDirectory,
    required this.shell,
    required this.environment,
    required this.createdAt,
    required this.lastActivity,
  });

  Stream<List<int>> get output {
    return pty.out.map((data) {
      lastActivity = DateTime.now();
      return utf8.encode(data) as List<int>;
    });
  }

  bool get isAlive => _isAlive && pty.exitCode == null;

  bool get isValid {
    return id.isNotEmpty && 
           workingDirectory.isNotEmpty && 
           shell.isNotEmpty &&
           DateTime.now().difference(lastActivity) < const Duration(hours: 24);
  }

  void write(List<int> data) {
    if (_isAlive && pty.exitCode == null) {
      try {
        pty.write(utf8.decode(data));
      } catch (e) {
        debugPrint('Failed to write to PTY ${id}: $e');
      }
    }
  }

  void resize(int cols, int rows) {
    if (_isAlive && pty.exitCode == null) {
      try {
        pty.resize(cols, rows);
      } catch (e) {
        debugPrint('Failed to resize PTY ${id}: $e');
      }
    }
  }

  Future<void> terminate() async {
    try {
      _isAlive = false;
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Failed to terminate PTY ${id}: $e');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'working_directory': workingDirectory,
        'shell': shell,
        'environment': environment,
        'created_at': createdAt.toIso8601String(),
        'last_activity': lastActivity.toIso8601String(),
        'is_alive': isAlive,
        'exit_code': pty.exitCode,
      };

  factory PtySession.fromJson(Map<String, dynamic> json) => PtySession(
        id: json['id'],
        pty: null, // PTY will be recreated on recovery
        workingDirectory: json['working_directory'],
        shell: json['shell'],
        environment: Map<String, String>.from(json['environment'] ?? {}),
        createdAt: DateTime.parse(json['created_at']),
        lastActivity: DateTime.parse(json['last_activity']),
      );
}