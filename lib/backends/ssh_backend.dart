import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../core/pty_backend.dart';
import '../core/prompt_config.dart';

/// SSH backend for remote terminal connections
class SshBackend implements TermisolPtyBackend {
  @override
  final String name = 'SSH Backend';

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? workingDirectory;

  SSHClient? _client;
  SSHSession? _session;
  final _outputController = StreamController<List<int>>.broadcast();
  bool _isRunning = false;
  bool _isDisposed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  SshBackend({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.workingDirectory,
  });

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
    try {
      // Connect to SSH server
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        onPasswordRequest: password != null ? () => password! : null,
        identities: privateKeyPath != null
            ? await SSHKeyPair.fromPem(await File(privateKeyPath!).readAsString())
            : null,
      );

      // Start shell session
      _session = _client!.execute('bash');

      _isRunning = true;

      // Listen to output
      _session!.stdout.listen(
        (data) => _safeAdd(data),
        onError: (Object e) {
          debugPrint('[ssh] stdout error: $e');
        },
        onDone: () {
          _isRunning = false;
        },
      );

      _session!.stderr.listen(
        (data) => _safeAdd(data),
        onError: (Object e) {
          debugPrint('[ssh] stderr error: $e');
        },
      );

      // Set terminal size
      resize(cols, rows);

      // Set working directory if specified
      if (workingDirectory != null || this.workingDirectory != null) {
        final wd = workingDirectory ?? this.workingDirectory!;
        write(utf8.encode('cd "$wd"\n'));
      }

      // Inject colored PS1
      write(utf8.encode("export PS1='${PromptConfig.sshPs1}'\n"));

      debugPrint('[ssh] connected to $username@$host:$port');
    } catch (e, stack) {
      debugPrint('[ssh] connection failed: $e\n$stack');
      _isRunning = false;
      rethrow;
    }
  }

  @override
  void write(List<int> data) {
    if (_session != null && _isRunning) {
      try {
        _session!.stdin.add(Uint8List.fromList(data));
      } catch (e) {
        debugPrint('[ssh] write error: $e');
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_session != null && _isRunning) {
      try {
        _session!.resizeTerminal(cols, rows);
      } catch (e) {
        debugPrint('[ssh] resize error: $e');
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      _session?.close();
      _client?.close();
    } catch (e) {
      debugPrint('[ssh] stop error: $e');
    }
    await _closeController();
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    try {
      _session?.close();
      _client?.close();
    } catch (e) {
      debugPrint('[ssh] terminate error: $e');
    }
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
  bool get isConnected => _isRunning && _client != null;
}