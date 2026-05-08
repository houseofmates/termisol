import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Asciicast Recorder
///
/// Records terminal sessions in asciicast v2 format for playback
/// and sharing. Compatible with asciinema players.
class AsciicastRecorder {
  final Map<String, AsciicastSession> _sessions = {};
  final Map<String, List<AsciicastFrame>> _frames = {};
  String? _recordingPath;

  static const int _maxFrameBuffer = 100000;

  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _recordingPath = '${appDir.path}/asciicasts';
      final dir = Directory(_recordingPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      debugPrint('AsciicastRecorder initialized');
    } catch (e) {
      debugPrint('Failed to initialize AsciicastRecorder: $e');
      rethrow;
    }
  }

  Future<String?> startRecording({
    String? name,
    AsciicastTerminalSize? terminalSize,
    Map<String, dynamic>? env,
    String? command,
    String? title,
  }) async {
    try {
      final sessionId = 'cast_${DateTime.now().millisecondsSinceEpoch}';
      final session = AsciicastSession(
        id: sessionId,
        name: name ?? 'Session ${_sessions.length + 1}',
        title: title ?? 'Termisol Recording',
        terminalSize: terminalSize ?? AsciicastTerminalSize(cols: 80, rows: 24),
        env: env ?? _defaultEnv(),
        command: command,
        startTime: DateTime.now(),
        duration: Duration.zero,
      );

      _sessions[sessionId] = session;
      _frames[sessionId] = [];

      debugPrint('Recording started: $sessionId');
      return sessionId;
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      return null;
    }
  }

  void recordOutput(String sessionId, String data) {
    final frames = _frames[sessionId];
    if (frames == null) return;

    final session = _sessions[sessionId];
    if (session == null) return;

    final elapsed = DateTime.now().difference(session.startTime!);
    final seconds = elapsed.inSeconds + elapsed.inMilliseconds / 1000.0 % 1;

    frames.add(AsciicastFrame(
      time: seconds,
      eventType: 'o',
      data: data,
    ));

    if (frames.length > _maxFrameBuffer) {
      frames.removeRange(0, 1000);
    }

    session.duration = elapsed;
    session.frameCount = frames.length;
  }

  void recordInput(String sessionId, String data) {
    final frames = _frames[sessionId];
    if (frames == null) return;

    final session = _sessions[sessionId];
    if (session == null) return;

    final elapsed = DateTime.now().difference(session.startTime!);
    final seconds = elapsed.inSeconds + elapsed.inMilliseconds / 1000.0 % 1;

    frames.add(AsciicastFrame(
      time: seconds,
      eventType: 'i',
      data: data,
    ));

    session.frameCount = frames.length;
  }

  void recordMarker(String sessionId, String marker) {
    final frames = _frames[sessionId];
    if (frames == null) return;

    final session = _sessions[sessionId];
    if (session == null) return;

    final elapsed = DateTime.now().difference(session.startTime!);
    frames.add(AsciicastFrame(
      time: elapsed.inMicroseconds / 1000000.0,
      eventType: 'm',
      data: marker,
    ));
  }

  void recordResize(String sessionId, int cols, int rows) {
    final frames = _frames[sessionId];
    if (frames == null) return;

    final session = _sessions[sessionId];
    if (session == null) return;

    final elapsed = DateTime.now().difference(session.startTime!);
    frames.add(AsciicastFrame(
      time: elapsed.inMicroseconds / 1000000.0,
      eventType: 'r',
      data: '${cols}x$rows',
    ));

    session.terminalSize = AsciicastTerminalSize(cols: cols, rows: rows);
  }

  Future<AsciicastResult> stopRecording(String sessionId) async {
    final session = _sessions[sessionId];
    final frames = _frames[sessionId];

    if (session == null || frames == null) {
      return AsciicastResult(success: false, error: 'No active recording');
    }

    try {
      session.duration = DateTime.now().difference(session.startTime!);
      session.frameCount = frames.length;

      final filePath = await _writeAsciicastFile(session, frames);
      _frames.remove(sessionId);

      debugPrint('Recording saved: $filePath (${frames.length} frames)');

      return AsciicastResult(
        success: true,
        sessionId: sessionId,
        filePath: filePath,
        duration: session.duration,
        frameCount: session.frameCount,
      );
    } catch (e) {
      return AsciicastResult(success: false, error: e.toString());
    }
  }

  Future<void> cancelRecording(String sessionId) async {
    _sessions.remove(sessionId);
    _frames.remove(sessionId);
  }

  Future<String?> saveRecording(String sessionId) async {
    final session = _sessions[sessionId];
    final frames = _frames[sessionId];
    if (session == null || frames == null) return null;
    return _writeAsciicastFile(session, frames);
  }

  Future<String?> exportAsciicastJson(String sessionId) async {
    final session = _sessions[sessionId];
    final frames = _frames[sessionId];
    if (session == null || frames == null) return null;
    return _buildAsciicastV2Json(session, frames);
  }

  bool isRecording(String sessionId) => _sessions.containsKey(sessionId);

  AsciicastSession? getSession(String sessionId) => _sessions[sessionId];

  List<AsciicastSession> getActiveSessions() => _sessions.values.toList();

  int getFrameCount(String sessionId) => _frames[sessionId]?.length ?? 0;

  List<AsciicastFrame> getFrames(String sessionId, {int? start, int? end}) {
    final frames = _frames[sessionId];
    if (frames == null) return [];
    return frames.sublist(start ?? 0, min(end ?? frames.length, frames.length));
  }

  Future<String> _writeAsciicastFile(AsciicastSession session, List<AsciicastFrame> frames) async {
    final json = _buildAsciicastV2Json(session, frames);
    final filename = '${session.name.replaceAll(RegExp(r'[^\w\-]'), '_')}_${session.startTime?.millisecondsSinceEpoch ?? 0}.cast';
    final file = File('$_recordingPath/$filename');
    await file.writeAsString(json);
    return file.path;
  }

  String _buildAsciicastV2Json(AsciicastSession session, List<AsciicastFrame> frames) {
    final header = {
      'version': 2,
      'width': session.terminalSize.cols,
      'height': session.terminalSize.rows,
      'timestamp': session.startTime?.millisecondsSinceEpoch ?? 0,
      'title': session.title ?? 'Termisol Recording',
      'env': session.env,
      if (session.command != null) 'command': session.command,
      'duration': session.duration.inSeconds,
    };

    final events = frames.map((f) {
      return [f.time, f.eventType, f.data];
    }).toList();

    return json.encode({
      ...header,
      'stdout': events,
    });
  }

  Map<String, dynamic> _defaultEnv() => {
    'SHELL': Platform.environment['SHELL'] ?? '/bin/bash',
    'TERM': 'xterm-256color',
    'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
  };

  void dispose() {
    _sessions.clear();
    _frames.clear();
  }
}

class AsciicastSession {
  final String id;
  final String name;
  String? title;
  AsciicastTerminalSize terminalSize;
  final Map<String, dynamic> env;
  final String? command;
  final DateTime? startTime;
  Duration duration;
  int frameCount;

  AsciicastSession({
    required this.id,
    required this.name,
    this.title,
    required this.terminalSize,
    required this.env,
    this.command,
    this.startTime,
    this.duration = Duration.zero,
    this.frameCount = 0,
  });
}

class AsciicastTerminalSize {
  final int cols;
  final int rows;

  AsciicastTerminalSize({required this.cols, required this.rows});
}

class AsciicastFrame {
  final double time;
  final String eventType;
  final String data;

  AsciicastFrame({required this.time, required this.eventType, required this.data});

  List<dynamic> toList() => [time, eventType, data];
}

class AsciicastResult {
  final bool success;
  final String? sessionId;
  final String? filePath;
  final Duration? duration;
  final int? frameCount;
  final String? error;

  AsciicastResult({
    required this.success,
    this.sessionId,
    this.filePath,
    this.duration,
    this.frameCount,
    this.error,
  });
}