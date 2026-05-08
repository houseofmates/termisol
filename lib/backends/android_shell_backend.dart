import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/pty_backend.dart';

/// Android-specific shell backend with robust shell probing and environment
/// bootstrap.
///
/// Modern Android restricts direct execution of /system/bin/sh for untrusted
/// apps. This backend probes multiple shell paths, sets up a proper local
/// environment in the app's private directory, and never uses runInShell
/// (which would look for /bin/sh and fail on Android).
///
/// Because there is no real PTY on Android, this backend implements a simple
/// line discipline: local echo, backspace handling, and \r -> \n translation.
class AndroidShellBackend implements TermisolPtyBackend {
  final String? workingDirectory;
  Process? _process;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // Line-discipline buffer for interactive use without a PTY.
  final StringBuffer _lineBuffer = StringBuffer();

  @override
  Stream<List<int>> get output => _outputController.stream;

  AndroidShellBackend({this.workingDirectory});

  @override
  Future<void> start({int cols = 80, int rows = 24}) async {
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

    // Build a comprehensive PATH. On Android 10+ core utilities live in
    // APEX modules, so we must include those directories. We prepend our
    // known directories to any existing PATH the runtime already set up.
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
    if (await File('/data/data/com.termux/files/usr/bin/bash').exists()) {
      paths.insert(0, '/data/data/com.termux/files/usr/bin');
    }
    if (existingPath.isNotEmpty) {
      // Append original PATH so we don't lose anything the runtime provided.
      paths.add(existingPath);
    }
    env['PATH'] = paths.join(':');
    return env;
  }

  Future<void> _startProcess(Map<String, String> env) async {
    try {
      String? shell;
      List<String> args = [];
      String? workDir = workingDirectory ?? env['HOME'];

      final probes = [
        ('/system/bin/sh', <String>[]),
        ('/vendor/bin/sh', <String>[]),
        ('/system/xbin/sh', <String>[]),
        ('/data/data/com.termux/files/usr/bin/bash', <String>['-l']),
        ('/data/data/com.termux/files/usr/bin/sh', <String>[]),
      ];

      for (final probe in probes) {
        if (await File(probe.$1).exists()) {
          shell = probe.$1;
          args = probe.$2;
          break;
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
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      _isRunning = true;
      _retryCount = 0;

      _process!.stdout.listen(
        _onProcessOutput,
        onDone: () {
          debugPrint('[androidshell] stdout stream ended');
          _isRunning = false;
        },
        onError: (e) {
          debugPrint('[androidshell] stdout error: $e');
          _isRunning = false;
        },
      );

      _process!.stderr.listen(
        _onProcessOutput,
        onError: (e) => debugPrint('[androidshell] stderr error: $e'),
      );

      _process!.exitCode.then((code) {
        debugPrint('[androidshell] shell exited with code $code');
        _isRunning = false;
        if (!_outputController.isClosed) {
          _outputController
              .add(utf8.encode('\r\n[process exited: $code]\r\n'));
        }
      });

      debugPrint('[androidshell] started shell: $shell');

      // Set a colored PS1 and emit the first prompt.
      // We delay slightly so TerminalSession has time to attach its listener.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_isRunning || _outputController.isClosed) return;
        // Send PS1 export: yellow username, cyan directory.
        _process!.stdin.add(utf8.encode(
          "export PS1='\[\e[38;2;246;176;18m\]termisol\[\e[0m\]:\[\e[38;2;53;199;255m\]\$PWD\[\e[0m\]\$ '\n",
        ));
        _outputController.add(utf8.encode('\r\n'));
      });
    } on ProcessException catch (e) {
      debugPrint('[androidshell] process error: ${e.message}');
      if (_retryCount < _maxRetries) {
        _retryCount++;
        debugPrint('[androidshell] retrying ($_retryCount/$_maxRetries)...');
        await _startProcess(env);
      } else {
        _emitError(
            'failed to start shell after $_maxRetries attempts: ${e.message}');
      }
    } on FileSystemException catch (e) {
      debugPrint('[androidshell] filesystem error: ${e.message}');
      _emitError('permission denied: ${e.message}');
    } catch (e) {
      debugPrint('[androidshell] unexpected error: $e');
      _emitError('shell error: $e');
    }
  }

  void _onProcessOutput(List<int> data) {
    try {
      if (!_outputController.isClosed) {
        _outputController.add(data);
      }
    } catch (e) {
      debugPrint('[androidshell] output error: $e');
    }
  }

  void _emitError(String message) {
    if (!_outputController.isClosed) {
      _outputController.add(
          utf8.encode('\r\n\x1b[31m[error] $message\x1b[0m\r\n'));
    }
  }

  /// Simple line discipline for Android shells running without a PTY.
  ///
  /// - Echoes printable characters so the user can see what they type.
  /// - Buffers a line until \r or \n, then sends it with a \n terminator.
  /// - Handles backspace (\b / 0x7F) locally.
  /// - Passes escape sequences straight through.
  @override
  void write(List<int> data) {
    if (_process == null || !_isRunning) return;
    try {
      final text = utf8.decode(data, allowMalformed: true);

      // Escape sequences (arrow keys, etc.) go straight to the shell.
      if (text.contains('\x1b')) {
        _process!.stdin.add(data);
        return;
      }

      for (final rune in text.runes) {
        final ch = String.fromCharCode(rune);

        if (ch == '\r' || ch == '\n') {
          // Enter pressed.
          final line = _lineBuffer.toString();
          _lineBuffer.clear();
          _outputController.add(utf8.encode('\r\n'));
          if (line.isNotEmpty) {
            _process!.stdin.add(utf8.encode('$line\n'));
          } else {
            _process!.stdin.add([0x0A]);
          }
        } else if (ch == '\b' || ch == '\x7f') {
          // Backspace / delete.
          if (_lineBuffer.isNotEmpty) {
            final str = _lineBuffer.toString();
            _lineBuffer.clear();
            _lineBuffer.write(str.substring(0, str.length - 1));
            // Erase character on screen: back, space, back.
            _outputController.add(utf8.encode('\b \b'));
          }
        } else if (rune == 0x03) {
          // Ctrl+C.
          _lineBuffer.clear();
          _outputController.add(utf8.encode('^C\r\n'));
          _process!.stdin.add([0x03]);
        } else if (rune == 0x04) {
          // Ctrl+D.
          if (_lineBuffer.isEmpty) {
            unawaited(_process!.stdin.close());
          }
        } else if (rune < 0x20) {
          // Other control chars pass through raw.
          _process!.stdin.add([rune]);
        } else {
          // Printable char: buffer and echo.
          _lineBuffer.write(ch);
          _outputController.add(utf8.encode(ch));
        }
      }
    } catch (e) {
      debugPrint('[androidshell] write error: $e');
      if (!_outputController.isClosed) {
        _outputController.add(
            utf8.encode('\r\n\x1b[31m[i/o error: $e]\x1b[0m\r\n'));
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    // No-op: without a PTY resize escape sequences are meaningless to the
    // shell.
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
        await Future.delayed(const Duration(milliseconds: 100));
        if (_process != null) {
          _process!.kill(ProcessSignal.sigkill);
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;

    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
        await _process!.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _process?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        debugPrint('[androidshell] terminate error: $e');
        try {
          _process?.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
      _process = null;
    }

    await _outputController.close();
    debugPrint('[androidshell] terminated');
  }
}
