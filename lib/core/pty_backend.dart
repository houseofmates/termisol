import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pty/pty.dart';
import '../backends/android_shell_backend.dart';
import 'ffi_pty_backend.dart';
import 'prompt_config.dart';

/// Cross-platform PTY backend interface for termisol.
abstract class TermisolPtyBackend {
  String get name;
  Stream<List<int>> get output;
  bool get isConnected;
  Future<void> start({int cols, int rows, String? workingDirectory});
  void write(List<int> data);
  void resize(int cols, int rows);
  Future<void> stop();
  Future<void> terminate();

  /// Auto-detect the best backend for the current platform.
  factory TermisolPtyBackend.autoDetect({String? workingDirectory}) {
    if (Platform.isAndroid) {
      return AndroidShellBackend(workingDirectory: workingDirectory);
    }
    
    // Prefer FFI backend for desktop platforms for maximum performance
    try {
      return FfiPtyBackend(workingDirectory: workingDirectory);
    } catch (e, stack) {
      debugPrint('[pty] FFI backend failed, falling back to PTY package: $e\n$stack');
      return _PtyBackend(workingDirectory: workingDirectory);
    }
  }
}

class _PtyBackend implements TermisolPtyBackend {
  @override
  final String name = 'PTY Backend';
  final String? workingDirectory;
  PseudoTerminal? _pty;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;
  bool _isDisposed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  _PtyBackend({this.workingDirectory});

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
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
      workingDirectory: workingDirectory ?? this.workingDirectory ?? _resolveHome('~'),
      environment: env,
    );

    _pty!.init();
    _isRunning = true;

    _pty!.out.listen(
      (data) {
        _safeAdd(utf8.encode(data));
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[pty] out error: $e');
      },
      onDone: () {
        _isRunning = false;
      },
    );

    _pty!.exitCode.then((code) {
      _isRunning = false;
      _safeAdd(utf8.encode('\r\n[process exited with code $code]\r\n'));
    });

    if (kDebugMode) debugPrint('[pty] started pty: $shell');

    // Inject termisol-colored PS1 after shell initializes
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_isRunning && _pty != null) {
        write(utf8.encode("export PS1='${PromptConfig.bashPs1}'\n"));
      }
    });
  }

  @override
  void write(List<int> data) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.write(utf8.decode(data));
      } catch (e) {
        if (kDebugMode) debugPrint('[pty] write error: $e');
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.resize(cols, rows);
      } catch (e) {
        if (kDebugMode) debugPrint('[pty] resize error: $e');
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _pty?.kill();
    await _closeController();
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    _pty?.kill();
    await _closeController();
  }

  Future<void> _closeController() async {
    if (!_outputController.isClosed && !_isDisposed) {
      await _outputController.close();
    }
    _isDisposed = true;
  }

  void _safeAdd(List<int> data) {
    if (!_outputController.isClosed && !_isDisposed) {
      _outputController.add(data);
    }
  }

  @override
  bool get isConnected => _isRunning && _pty != null;
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
