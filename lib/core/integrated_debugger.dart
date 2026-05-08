import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Integrated Debugger
///
/// Debug terminal applications with GDB/LLDB integration, breakpoint
/// management, variable inspection, and stack trace analysis.
class IntegratedDebugger {
  final Map<String, DebugSession> _sessions = {};
  final Map<String, Breakpoint> _breakpoints = {};
  final List<DebugEvent> _eventLog = [];
  final StreamController<DebugEvent> _eventController = StreamController<DebugEvent>.broadcast();
  DebuggerBackend _backend = DebuggerBackend.gdb;

  Stream<DebugEvent> get events => _eventController.stream;
  List<DebugSession> get activeSessions => _sessions.values.where((s) => s.isRunning).toList();
  List<Breakpoint> get allBreakpoints => _breakpoints.values.toList();

  Future<void> initialize({DebuggerBackend backend = DebuggerBackend.gdb}) async {
    _backend = backend;
    debugPrint('IntegratedDebugger initialized (backend: ${backend.name})');
  }

  Future<DebugSession> createSession({
    required String program,
    List<String>? args,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final sessionId = 'debug_${DateTime.now().millisecondsSinceEpoch}';
    final process = await Process.start(
      _getDebuggerCommand(),
      _buildDebuggerArgs(program, args ?? []),
      workingDirectory: workingDirectory,
      environment: environment,
    );

    final session = DebugSession(
      id: sessionId,
      program: program,
      args: args ?? [],
      process: process,
      status: DebugStatus.started,
    );

    _sessions[sessionId] = session;

    process.stdout.transform(utf8.decoder).listen((data) {
      _parseGdbOutput(session, data);
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      debugPrint('GDB stderr: $data');
    });

    process.exitCode.then((exitCode) {
      session.status = DebugStatus.exited;
      session.exitCode = exitCode;
      _eventLog.add(DebugEvent(sessionId: sessionId, type: DebugEventType.sessionEnded, message: 'Process exited with code $exitCode'));
      _eventController.add(_eventLog.last);
    });

    _eventLog.add(DebugEvent(sessionId: sessionId, type: DebugEventType.sessionStarted, message: 'Debug session started for $program'));
    _eventController.add(_eventLog.last);

    return session;
  }

  Future<bool> setBreakpoint(String sessionId, {String? file, int? line, String? function}) async {
    final session = _sessions[sessionId];
    if (session == null) return false;

    final bpId = 'bp_${_breakpoints.length}_${DateTime.now().millisecondsSinceEpoch}';
    String command;

    if (file != null && line != null) {
      command = '$file:$line';
    } else if (function != null) {
      command = function;
    } else {
      return false;
    }

    final bp = Breakpoint(id: bpId, file: file, line: line, function: function, sessionId: sessionId);
    _breakpoints[bpId] = bp;
    await _sendCommand(session, 'break $command');

    _eventLog.add(DebugEvent(sessionId: sessionId, type: DebugEventType.breakpointSet, message: 'Breakpoint set: $command'));
    _eventController.add(_eventLog.last);

    return true;
  }

  Future<bool> removeBreakpoint(String bpId) async {
    final bp = _breakpoints.remove(bpId);
    if (bp == null) return false;
    final session = _sessions[bp.sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'delete breakpoints $bpId');
    return true;
  }

  Future<bool> run(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'run');
    session.status = DebugStatus.running;
    return true;
  }

  Future<bool> stepOver(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'next');
    return true;
  }

  Future<bool> stepInto(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'step');
    return true;
  }

  Future<bool> stepOut(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'finish');
    return true;
  }

  Future<bool> continue_(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'continue');
    return true;
  }

  Future<String?> printVariable(String sessionId, String variable) async {
    final session = _sessions[sessionId];
    if (session == null) return null;
    await _sendCommand(session, 'print $variable');
    return 'Sent print command for $variable';
  }

  Future<String?> backtrace(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return null;
    await _sendCommand(session, 'backtrace');
    return 'Requested backtrace';
  }

  Future<String?> frameInfo(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return null;
    await _sendCommand(session, 'info frame');
    return 'Requested frame info';
  }

  Future<List<String>> listLocals(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return [];
    await _sendCommand(session, 'info locals');
    return [];
  }

  Future<bool> stopSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    await _sendCommand(session, 'quit');
    session.process.kill();
    session.status = DebugStatus.stopped;
    return true;
  }

  Future<bool> pauseSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return false;
    session.process.kill(ProcessSignal.sigint);
    session.status = DebugStatus.paused;
    return true;
  }

  DebugSession? getSession(String sessionId) => _sessions[sessionId];

  List<DebugEvent> getEventLog({int? limit}) {
    if (limit == null) return List.from(_eventLog);
    return _eventLog.sublist(max(0, _eventLog.length - limit));
  }

  Future<void> _sendCommand(DebugSession session, String command) async {
    if (session.status == DebugStatus.exited) return;
    try {
      session.process.stdin.writeln(command);
      await session.process.stdin.flush();
      session.lastCommand = command;
    } catch (e) {
      debugPrint('Failed to send debugger command: $e');
    }
  }

  void _parseGdbOutput(DebugSession session, String data) {
    if (data.contains('stopped') || data.contains('Breakpoint')) {
      session.status = DebugStatus.paused;
      _eventLog.add(DebugEvent(sessionId: session.id, type: DebugEventType.breakpointHit, message: data.trim()));
      _eventController.add(_eventLog.last);
    }
    if (data.contains('error') || data.contains('Error')) {
      _eventLog.add(DebugEvent(sessionId: session.id, type: DebugEventType.error, message: data.trim()));
      _eventController.add(_eventLog.last);
    }
  }

  String _getDebuggerCommand() {
    switch (_backend) {
      case DebuggerBackend.gdb: return 'gdb';
      case DebuggerBackend.lldb: return 'lldb';
      case DebuggerBackend.pdb: return 'pdb';
      case DebuggerBackend.gdbgui: return 'gdbgui';
    }
  }

  List<String> _buildDebuggerArgs(String program, List<String> args) {
    switch (_backend) {
      case DebuggerBackend.gdb:
        return ['--quiet', '--args', program, ...args];
      case DebuggerBackend.lldb:
        return ['-o', 'run', '--', program, ...args];
      default:
        return [program, ...args];
    }
  }

  Future<void> dispose() async {
    for (final session in _sessions.values) {
      await stopSession(session.id);
    }
    _eventController.close();
    _sessions.clear();
    _breakpoints.clear();
    _eventLog.clear();
  }
}

enum DebuggerBackend { gdb, lldb, pdb, gdbgui }
enum DebugStatus { started, running, paused, stopped, exited }
enum DebugEventType { sessionStarted, sessionEnded, breakpointSet, breakpointHit, error, variableChanged }

class DebugSession {
  final String id;
  final String program;
  final List<String> args;
  final Process process;
  DebugStatus status;
  int? exitCode;
  String? lastCommand;
  final DateTime createdAt;
  final List<String> output;
  final Map<String, dynamic> registers;
  final Map<String, dynamic> variables;

  DebugSession({
    required this.id,
    required this.program,
    required this.args,
    required this.process,
    required this.status,
    DateTime? createdAt,
    List<String>? output,
    Map<String, dynamic>? registers,
    Map<String, dynamic>? variables,
  })  : createdAt = createdAt ?? DateTime.now(),
        output = output ?? [],
        registers = registers ?? {},
        variables = variables ?? {};

  bool get isRunning => status == DebugStatus.running || status == DebugStatus.started;
}

class Breakpoint {
  final String id;
  final String? file;
  final int? line;
  final String? function;
  final String sessionId;
  bool enabled;
  int hitCount;

  Breakpoint({
    required this.id,
    this.file,
    this.line,
    this.function,
    required this.sessionId,
    this.enabled = true,
    this.hitCount = 0,
  });
}

class DebugEvent {
  final String sessionId;
  final DebugEventType type;
  final String message;
  final DateTime timestamp;

  DebugEvent({
    required this.sessionId,
    required this.type,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
```