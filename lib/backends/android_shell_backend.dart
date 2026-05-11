import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/pty_backend.dart';
import '../core/prompt_config.dart';

/// android-specific shell backend with robust shell probing and environment
/// bootstrap.
class AndroidShellBackend implements TermisolPtyBackend {
  @override
  final String name = 'Android Shell Backend';
  final String? workingDirectory;
  Process? _process;

  @visibleForTesting
  void setProcessForTesting(Process process) {
    _process = process;
  }
  final _outputController = StreamController<List<int>>.broadcast(sync: false);
  bool _isRunning = false;
  bool _isDisposed = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // Line-discipline buffer for interactive use without a PTY.
  final StringBuffer _lineBuffer = StringBuffer();

  StreamSubscription<dynamic>? _stdoutSub;
  StreamSubscription<dynamic>? _stderrSub;
  Timer? _ps1Timer;

  @override
  Stream<List<int>> get output => _outputController.stream;

  AndroidShellBackend({this.workingDirectory});

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
    final env = await _buildEnvironment(cols, rows);
    await _startProcess(env);
  }

  Future<Map<String, String>> _buildEnvironment(int cols, int rows) async {
    final appDir = await getApplicationDocumentsDirectory();
    final tmpDir = Directory('${appDir.path}/tmp');
    if (!await tmpDir.exists()) {
      await tmpDir.create(recursive: true);
    }

    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = 'xterm-256color';
    env['TERM_PROGRAM'] = 'termisol';
    env['COLORTERM'] = 'truecolor';
    env['COLUMNS'] = '$cols';
    env['LINES'] = '$rows';
    env['HOME'] = appDir.path;
    env['TMPDIR'] = tmpDir.path;
    env['SHELL'] = '/system/bin/sh';

    final existingPath = env['PATH'] ?? '';
    final paths = <String>[
      '/apex/com.android.runtime/bin',
      '/apex/com.android.art/bin',
      '/product/bin',
      '/system_ext/bin',
      '/system/bin',
      '/vendor/bin',
      '/system/xbin',
      '/odm/bin',
      '/vendor/xbin',
    ];
    try {
      if (await File('/data/data/com.termux/files/usr/bin/bash').exists()) {
        paths.insert(0, '/data/data/com.termux/files/usr/bin');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[androidshell] termux probe error: $e');
    }
    if (existingPath.isNotEmpty) {
      paths.add(existingPath);
    }
    env['PATH'] = paths.join(':');
    return env;
  }

  Future<void> _startProcess(Map<String, String> env) async {
    try {
      String? shell;
      List<String> args = [];
      final String? workDir = workingDirectory ?? env['HOME'];

      final probes = [
        ('/system/bin/sh', <String>[]),
        ('/vendor/bin/sh', <String>[]),
        ('/system/xbin/sh', <String>[]),
        ('/data/data/com.termux/files/usr/bin/bash', <String>['-l']),
        ('/data/data/com.termux/files/usr/bin/sh', <String>[]),
      ];

      for (final probe in probes) {
        try {
          if (await File(probe.$1).exists()) {
            shell = probe.$1;
            args = probe.$2;
            break;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[androidshell] probe error for ${probe.$1}: $e');
          continue;
        }
      }

      if (shell == null) {
        _emitError('no accessible shell found on this device.');
        _emitError('install termux for a full local shell environment.');
        return;
      }

      _process = await Process.start(
        shell,
        args,
        environment: env,
        workingDirectory: workDir,
      );

      _isRunning = true;
      _retryCount = 0;

      _stdoutSub = _process!.stdout.listen(
        _onProcessOutput,
        onDone: () {
          if (kDebugMode) debugPrint('[androidshell] stdout stream ended');
          _isRunning = false;
        },
        onError: (e) {
          if (kDebugMode) debugPrint('[androidshell] stdout error: $e');
          _isRunning = false;
        },
      );

      _stderrSub = _process!.stderr.listen(
        _onProcessOutput,
        onError: (e) => debugPrint('[androidshell] stderr error: $e'),
      );

      unawaited(_process!.exitCode.then((code) {
        if (kDebugMode) debugPrint('[androidshell] shell exited with code $code');
        _isRunning = false;
        _safeAdd(utf8.encode('\r\n[process exited: $code]\r\n'));
      }));

      if (kDebugMode) debugPrint('[androidshell] started shell: $shell');

      // Set a colored PS1 and emit the first prompt.
      _ps1Timer = Timer(const Duration(milliseconds: 300), () {
        if (!_isRunning || _isDisposed) return;
        final user = Platform.environment['USER'] ?? 'user';
        final host = Platform.environment['HOSTNAME'] ?? 'android';
        final ps1 = PromptConfig.portablePs1(user: user, host: host, pwd: r'\$PWD');
        _safeWriteStdin("export PS1='$ps1'\n");
        _safeAdd(utf8.encode('\r\n'));
      });
    } on ProcessException catch (e) {
      if (kDebugMode) debugPrint('[androidshell] process error: ${e.message}');
      if (_retryCount < _maxRetries) {
        _retryCount++;
        if (kDebugMode) debugPrint('[androidshell] retrying ($_retryCount/$_maxRetries)...');
        await _startProcess(env);
      } else {
        _emitError('failed to start shell after $_maxRetries attempts: ${e.message}');
      }
    } on FileSystemException catch (e) {
      if (kDebugMode) debugPrint('[androidshell] filesystem error: ${e.message}');
      _emitError('permission denied: ${e.message}');
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[androidshell] unexpected error: $e');
      _emitError('shell error: $e');
    }
  }

  void _onProcessOutput(List<int> data) {
    _safeAdd(data);
  }

  void _emitError(String message) {
    _safeAdd(utf8.encode('\r\n\x1b[31m[error] $message\x1b[0m\r\n'));
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

  void _safeWriteStdin(String data) {
    try {
      _process?.stdin.add(utf8.encode(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[androidshell] stdin write error: $e');
    }
  }

  /// Simple line discipline for Android shells running without a PTY.
  @override
  void write(List<int> data) {
    if (_process == null || !_isRunning) return;
    _doWrite(data);
  }

  void _doWrite(List<int> data) {
    try {
      final text = utf8.decode(data, allowMalformed: true);

      // Escape sequences (arrow keys, etc.) go straight to the shell.
      if (text.contains('\x1b')) {
        _safeWriteStdin(text);
        return;
      }

      for (final rune in text.runes) {
        final ch = String.fromCharCode(rune);

        if (ch == '\r' || ch == '\n') {
          final line = _lineBuffer.toString();
          _lineBuffer.clear();
          _safeAdd(utf8.encode('\r\n'));
          if (line.isNotEmpty) {
            _safeWriteStdin('$line\n');
          } else {
            _safeWriteStdin('\n');
          }
        } else if (ch == '\b' || ch == '\x7f') {
          if (_lineBuffer.isNotEmpty) {
            final str = _lineBuffer.toString();
            final runes = str.runes.toList();
            if (runes.isNotEmpty) {
              _lineBuffer.clear();
              _lineBuffer.write(String.fromCharCodes(runes.sublist(0, runes.length - 1)));
            }
            _safeAdd(utf8.encode('\b \b'));
          }
        } else if (rune == 0x03) {
          _lineBuffer.clear();
          _safeAdd(utf8.encode('^C\r\n'));
          _safeWriteStdin('\x03');
        } else if (rune == 0x04) {
          if (_lineBuffer.isEmpty) {
            try {
              _process?.stdin.close();
            } catch (e) {
              if (kDebugMode) debugPrint('[androidshell] stdin close error: $e');
            }
          }
        } else if (rune < 0x20) {
          _safeWriteStdin(String.fromCharCode(rune));
        } else {
          _lineBuffer.write(ch);
          _safeAdd(utf8.encode(ch));
        }
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[androidshell] write error: $e\n$stack');
      _safeAdd(utf8.encode('\r\n\x1b[31m[i/o error: $e]\x1b[0m\r\n'));
    }
  }

  @override
  void resize(int cols, int rows) {
    // No-op: without a PTY resize escape sequences are meaningless to the shell.
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _ps1Timer?.cancel();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    if (_process != null) {
      try {
        _process!.kill();
        await Future.delayed(const Duration(milliseconds: 100));
        _process?.kill(ProcessSignal.sigkill);
      } catch (e) {
        if (kDebugMode) debugPrint('[androidshell] force kill error: $e');
      }
    }
    await _closeController();
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    _ps1Timer?.cancel();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    if (_process != null) {
      try {
        _process!.kill();
        await _process!.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _process?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } on Exception catch (e) {
        if (kDebugMode) debugPrint('[androidshell] terminate error: $e');
        try {
          _process?.kill(ProcessSignal.sigkill);
        } on Exception catch (e) {
          if (kDebugMode) debugPrint('[androidshell] termination cleanup error: $e');
        }
      }
      _process = null;
    }

    await _closeController();
    if (kDebugMode) debugPrint('[androidshell] terminated');
  }

  Future<void> _closeController() async {
    if (!_outputController.isClosed && !_isDisposed) {
      await _outputController.close();
    }
    _isDisposed = true;
  }

  @override
  bool get isConnected => _isRunning && _process != null;
}
