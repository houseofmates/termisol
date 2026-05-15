import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pty/pty.dart';
import '../backends/android_shell_backend.dart';
import 'prompt_config.dart';

/// cross-platform pty backend interface for termisol.
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
  factory TermisolPtyBackend.autoDetect({
    String? workingDirectory,
    Encoding encoding = utf8,
  }) {
    if (Platform.isAndroid) {
      return AndroidShellBackend(workingDirectory: workingDirectory);
    }
    return _PtyBackend(workingDirectory: workingDirectory, encoding: encoding);
  }
}

class _PtyBackend implements TermisolPtyBackend {
  @override
  final String name = 'PTY Backend';
  final String? workingDirectory;
  final Encoding encoding;
  PseudoTerminal? _pty;
  final _outputController = StreamController<List<int>>.broadcast(sync: false);
  bool _isRunning = false;
  bool _isDisposed = false;
  StreamSubscription<dynamic>? _outSub;
  Timer? _ps1Timer;

  @override
  Stream<List<int>> get output => _outputController.stream;

  _PtyBackend({this.workingDirectory, this.encoding = utf8});

  @override
  Future<void> start({
    int cols = 80,
    int rows = 24,
    String? workingDirectory,
  }) async {
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

    final wd = workingDirectory ?? this.workingDirectory ?? _resolveHome('~');

    _pty = PseudoTerminal.start(
      shell,
      [],
      workingDirectory: wd,
      environment: env,
    );

    _pty!.init();
    _isRunning = true;

    _outSub = _pty!.out.listen(
      (data) {
        _safeAdd(encoding.encode(data));
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[pty] out error: $e');
      },
      onDone: () {
        _isRunning = false;
      },
    );

    unawaited(
      _pty!.exitCode.then((code) {
        _isRunning = false;
        _safeAdd(encoding.encode('\r\n[process exited with code $code]\r\n'));
      }),
    );

    if (kDebugMode) debugPrint('[pty] started pty: $shell');

    // Inject termisol-colored PS1 after shell initializes.
    _ps1Timer = Timer(const Duration(milliseconds: 200), () {
      if (_isRunning && _pty != null && !_isDisposed) {
        try {
          write(encoding.encode("export PS1='${PromptConfig.bashPs1}'\n"));
        } catch (e) {
          if (kDebugMode) debugPrint('[pty] ps1 injection error: $e');
        }
      }
    });
  }

  @override
  void write(List<int> data) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.write(encoding.decode(data));
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[pty] write error: $e\n$stack');
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_pty != null && _isRunning) {
      try {
        _pty!.resize(cols, rows);
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[pty] resize error: $e\n$stack');
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _ps1Timer?.cancel();
    await _outSub?.cancel();
    _outSub = null;
    _pty?.kill();
    await _closeController();
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    _ps1Timer?.cancel();
    await _outSub?.cancel();
    _outSub = null;
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
      try {
        _outputController.add(data);
      } catch (e) {
        // ignore add-after-close races
      }
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
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return path.replaceFirst('~', home);
  }
  return path;
}
