import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/pty_backend.dart';

/// Robust local backend for terminal sessions using native PTY
class LocalBackend implements TermisolPtyBackend {
  final String name = 'Local Backend';
  final String workingDirectory;
  final Map<String, String> environment;
  
  Process? _process;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;
  late String _shellPath;
  
  LocalBackend({
    this.workingDirectory = Platform.environment['HOME'] ?? '/tmp',
    this.environment = const {},
  });

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  Future<void> start({int cols = 80, int rows = 24}) async {
    try {
      // Validate working directory
      final dir = Directory(workingDirectory);
      if (!await dir.exists()) {
        throw Exception('Working directory does not exist: $workingDirectory');
      }

      // Detect appropriate shell
      _shellPath = await _detectShell();
      
      // Set up environment
      final env = Map<String, String>.from(Platform.environment);
      env.addAll(environment);
      env['TERM'] = 'xterm-256color';
      env['COLUMNS'] = cols.toString();
      env['LINES'] = rows.toString();

      // Start shell process
      _process = await Process.start(
        _shellPath,
        ['-l'],
        workingDirectory: workingDirectory,
        environment: env,
      );

      _isRunning = true;

      // Handle stdout
      _process!.stdout.listen(
        (data) => _outputController.add(data),
        onDone: () => _isRunning = false,
        onError: (e) {
          debugPrint('[LOCAL] stdout error: $e');
          _isRunning = false;
        },
      );

      // Handle stderr
      _process!.stderr.listen(
        (data) => _outputController.add(data),
        onError: (e) => debugPrint('[LOCAL] stderr error: $e'),
      );

      // Handle process exit
      _process!.exitCode.then((code) {
        debugPrint('[LOCAL] Process exited with code: $code');
        _isRunning = false;
      });

      debugPrint('[LOCAL] Started shell: $_shellPath in $workingDirectory');
    } catch (e) {
      final errorMessage = e is ProcessException 
          ? 'Failed to start shell "${e.executable}": ${e.message}'
          : 'Failed to start local backend: $e';
      
      _outputController.add(utf8.encode('\r\n[local error: $errorMessage]\r\n'));
      _isRunning = false;
      
      // Attempt recovery with fallback shell
      if (_shellPath != fallbackShell) {
        debugPrint('[LOCAL] Attempting fallback to $fallbackShell');
        _shellPath = fallbackShell;
        await start(); // Retry with fallback
      } else {
        debugPrint('[LOCAL] All shell startup attempts failed');
        rethrow;
      }
    }
  }

  @override
  void write(List<int> data) {
    if (_process == null || !_isRunning) {
      debugPrint('[LOCAL] Cannot write: process not running');
      return;
    }
    
    try {
      _process!.stdin.add(data);
    } catch (e) {
      debugPrint('[LOCAL] Write error: $e');
      
      // Check if process died and attempt recovery
      if (_process != null && await _process!.exitCode != null) {
        debugPrint('[LOCAL] Process died, attempting restart...');
        _isRunning = false;
        await start();
        
        // Retry the write if restart succeeded
        if (_isRunning && _process != null) {
          try {
            _process!.stdin.add(data);
          } catch (retryError) {
            debugPrint('[LOCAL] Retry write failed: $retryError');
          }
        }
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    // Local terminal resize would need to signal the process
    // This is a simplified implementation
    debugPrint('[LOCAL] Resize requested: ${cols}x${rows}');
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      if (_process != null) {
        _process!.kill(ProcessSignal.sigterm);
        await _process!.exitCode.timeout(Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('[LOCAL] Stop error: $e');
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    try {
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
    } catch (e) {
      debugPrint('[LOCAL] Terminate error: $e');
    }
    await _outputController.close();
  }

  Future<String> _detectShell() async {
    // Check for common shells in order of preference
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
        // Continue to next shell
      }
    }
    
    // Fallback to default
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

  bool get isConnected => _isRunning && _process != null;
}
