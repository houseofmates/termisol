import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/pty_backend.dart';

/// Robust local backend for terminal sessions using native process
class LocalBackend implements TermisolPtyBackend {
  @override
  final String name = 'Local Backend';
  final String workingDirectory;
  final Map<String, String> environment;

  Process? _process;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;
  bool _isDisposed = false;
  String _shellPath = '';

  LocalBackend({
    this.workingDirectory = '/tmp',
    this.environment = const {},
  });

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
    final wd = workingDirectory ?? this.workingDirectory;
    try {
      final dir = Directory(wd);
      if (!await dir.exists()) {
        throw Exception('Working directory does not exist: $wd');
      }

      _shellPath = await _detectShell();

      final env = Map<String, String>.from(Platform.environment);
      env.addAll(environment);
      env['TERM'] = 'xterm-256color';
      env['COLUMNS'] = cols.toString();
      env['LINES'] = rows.toString();

      _process = await Process.start(
        _shellPath,
        ['-l'],
        workingDirectory: wd,
        environment: env,
      );

      _isRunning = true;

      _process!.stdout.listen(
        (data) => _safeAdd(data),
        onDone: () => _isRunning = false,
        onError: (e) {
          if (kDebugMode) debugPrint('[LOCAL] stdout error: $e');
          _isRunning = false;
        },
      );

      _process!.stderr.listen(
        (data) => _safeAdd(data),
        onError: (e) {
          if (kDebugMode) debugPrint('[LOCAL] stderr error: $e');
        },
      );

      _process!.exitCode.then((code) {
        if (kDebugMode) debugPrint('[LOCAL] Process exited with code: $code');
        _isRunning = false;
        _safeAdd(utf8.encode('\r\n[process exited: $code]\r\n'));
      });

      if (kDebugMode) debugPrint('[LOCAL] Started shell: $_shellPath in $wd');
    } catch (e) {
      final errorMessage = e is ProcessException
          ? 'Failed to start shell "${e.executable}": ${e.message}'
          : 'Failed to start local backend: $e';

      _safeAdd(utf8.encode('\r\n[local error: $errorMessage]\r\n'));
      _isRunning = false;

      // Attempt recovery with fallback shell
      if (_shellPath.isNotEmpty && _shellPath != fallbackShell) {
        if (kDebugMode) debugPrint('[LOCAL] Attempting fallback to $fallbackShell');
        _shellPath = fallbackShell;
        await start(cols: cols, rows: rows, workingDirectory: wd);
      } else {
        if (kDebugMode) debugPrint('[LOCAL] All shell startup attempts failed');
        rethrow;
      }
    }
  }

  @override
  Future<void> write(List<int> data) async {
    if (_process == null || !_isRunning) {
      if (kDebugMode) debugPrint('[LOCAL] Cannot write: process not running');
      return;
    }

    try {
      _process!.stdin.add(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[LOCAL] Write error: $e');

      // Check if process died and attempt recovery
      if (_process != null) {
        try {
          // Use a short timeout to avoid blocking indefinitely
          final exited = await _process!.exitCode.timeout(const Duration(milliseconds: 100), onTimeout: () => -1);
          if (exited != -1) {
            if (kDebugMode) debugPrint('[LOCAL] Process died, attempting restart...');
            _isRunning = false;
            await start();
            if (_isRunning && _process != null) {
              try {
                _process!.stdin.add(data);
              } catch (retryError) {
                if (kDebugMode) debugPrint('[LOCAL] Retry write failed: $retryError');
              }
            }
          }
        } catch (_) {
          // Process is still running but stdin failed for another reason
        }
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (kDebugMode) debugPrint('[LOCAL] Resize requested: ${cols}x${rows}');
    // On POSIX systems we'd send SIGWINCH, but dart:io doesn't expose this directly.
    // The shell should pick up COLUMNS/LINES from environment on next prompt.
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      if (_process != null) {
        _process!.kill(ProcessSignal.sigterm);
        await _process!.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
          _process?.kill(ProcessSignal.sigkill);
          return -1;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LOCAL] Stop error: $e');
    } finally {
      await _closeController();
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    try {
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[LOCAL] Terminate error: $e');
    } finally {
      await _closeController();
    }
  }

  Future<void> _closeController() async {
    if (!_outputController.isClosed) {
      await _outputController.close();
    }
    _isDisposed = true;
  }

  void _safeAdd(List<int> data) {
    if (!_outputController.isClosed && !_isDisposed) {
      _outputController.add(data);
    }
  }

  Future<String> _detectShell() async {
    final shells = [
      Platform.isWindows ? 'powershell.exe' : '/bin/bash',
      Platform.isWindows ? 'cmd.exe' : '/bin/zsh',
      '/bin/sh',
    ];

    for (final shell in shells) {
      try {
        final result = await Process.run('which', [shell]);
        if (result.exitCode == 0) {
          return shell;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[LOCAL] Shell detection error for $shell: $e');
      }
    }

    return Platform.isWindows ? 'cmd.exe' : '/bin/sh';
  }

  Future<String> getWorkingDirectory() async {
    try {
      final result = await Process.run('pwd', []);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
      return workingDirectory;
    } catch (e) {
      return workingDirectory;
    }
  }

  @override
  bool get isConnected => _isRunning && _process != null;
}

String get fallbackShell => Platform.isWindows ? 'cmd.exe' : '/bin/sh';
