import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pty/pty.dart';
import '../backends/android_shell_backend.dart';

/// cross-platform pty backend for termisol.
abstract class TermisolPtyBackend {
  Stream<List<int>> get output;
  Future<void> start({int cols, int rows});
  void write(List<int> data);
  void resize(int cols, int rows);
  Future<void> terminate();

  /// auto-detect the best backend for the current platform.
  factory TermisolPtyBackend.autoDetect({String? workingDirectory}) {
    if (Platform.isAndroid) {
      return AndroidShellBackend(workingDirectory: workingDirectory);
    }
    return _PtyBackend(workingDirectory: workingDirectory);
  }
}

class _PtyBackend implements TermisolPtyBackend {
  final String? workingDirectory;
  PseudoTerminal? _pty;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  _PtyBackend({this.workingDirectory});

  @override
  Future<void> start({int cols = 80, int rows = 24}) async {
    String shell;

    if (Platform.isLinux) {
      shell = Platform.environment['SHELL'] ?? '/bin/bash';
    } else if (Platform.isMacOS) {
      shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    } else if (Platform.isWindows) {
      shell = Platform.environment['COMSPEC'] ?? 'cmd.exe';
    } else {
      shell = Platform.environment['SHELL'] ?? 'sh';
    }

    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = 'xterm-256color';
    env['TERM_PROGRAM'] = 'termisol';
    env['COLORTERM'] = 'truecolor';
    env['COLUMNS'] = cols.toString();
    env['LINES'] = rows.toString();

    _pty = PseudoTerminal.start(
      shell,
      [],
      workingDirectory: workingDirectory ?? _resolveHome('~'),
      environment: env,
    );

    _pty!.init();
    _isRunning = true;

    _pty!.out.listen(
      (data) {
        if (!_outputController.isClosed) {
          _outputController.add(utf8.encode(data));
        }
      },
      onError: (Object e) {
        debugPrint('[pty] out error: $e');
      },
      onDone: () {
        _isRunning = false;
      },
    );

    unawaited(_pty!.exitCode.then((code) {
      _isRunning = false;
      if (!_outputController.isClosed) {
        _outputController.add(
          utf8.encode('\r\n[process exited with code $code]\r\n'),
        );
      }
    }));

    debugPrint('[pty] started pty: $shell');
  }

  @override
  void write(List<int> data) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.write(utf8.decode(data));
      } catch (e) {
        debugPrint('[pty] write error: $e');
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.resize(cols, rows);
      } catch (e) {
        debugPrint('[pty] resize error: $e');
      }
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    _pty?.kill();
    await _outputController.close();
  }
}

String _resolveHome(String path) {
  if (path == '~') {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
  }
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return path.replaceFirst('~', home);
  }
  return path;
}
