import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../core/pty_backend.dart';
import '../core/prompt_config.dart';

/// SSH backend for remote terminal connections.
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
  final _outputController = StreamController<List<int>>.broadcast(sync: false);
  bool _isRunning = false;
  bool _isDisposed = false;
  StreamSubscription<dynamic>? _stdoutSub;
  StreamSubscription<dynamic>? _stderrSub;

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
      final socket = await SSHSocket.connect(host, port).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('SSH connection timed out to $host:$port'),
      );

      List<SSHKeyPair>? identities;
      if (privateKeyPath != null) {
        final pem = await File(privateKeyPath!).readAsString();
        identities = SSHKeyPair.fromPem(pem);
      }

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: password != null ? () => password! : null,
        identities: identities,
      );

      _session = await _client!.execute('bash');

      _isRunning = true;

      _stdoutSub = _session!.stdout.listen(
        (data) => _safeAdd(data),
        onError: (Object e) {
          if (kDebugMode) debugPrint('[ssh] stdout error: $e');
        },
        onDone: () {
          _isRunning = false;
        },
      );

      _stderrSub = _session!.stderr.listen(
        (data) => _safeAdd(data),
        onError: (Object e) {
          if (kDebugMode) debugPrint('[ssh] stderr error: $e');
        },
      );

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_isRunning && _session != null) {
          resize(cols, rows);
        }
      });

      final wd = workingDirectory ?? this.workingDirectory;
      if (wd != null) {
        final escaped = wd.replaceAll("'", "'\"'\"'");
        write(utf8.encode("cd '$escaped'\n"));
      }

      write(utf8.encode("export PS1='${PromptConfig.sshPs1}'\n"));

      if (kDebugMode) debugPrint('[ssh] connected to $username@$host:$port');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[ssh] connection failed: $e\n$stack');
      _isRunning = false;
      rethrow;
    }
  }

  @override
  void write(List<int> data) {
    if (_session != null && _isRunning) {
      try {
        _session!.stdin.add(Uint8List.fromList(data));
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[ssh] write error: $e\n$stack');
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_session != null && _isRunning) {
      try {
        _session!.resizeTerminal(cols, rows);
      } catch (e, stack) {
        if (kDebugMode) debugPrint('[ssh] resize error: $e\n$stack');
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    await _closeStreams();
    await _closeController();
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    await _closeStreams();
    await _closeController();
  }

  Future<void> _closeStreams() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _session?.close();
    } catch (e) {
      if (kDebugMode) debugPrint('[ssh] session close error: $e');
    }
    try {
      _client?.close();
    } catch (e) {
      if (kDebugMode) debugPrint('[ssh] client close error: $e');
    }
    _session = null;
    _client = null;
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
  bool get isConnected => _isRunning && _client != null;
}
