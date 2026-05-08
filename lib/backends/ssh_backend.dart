import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../core/pty_backend.dart';

/// SSH backend for remote terminal sessions using dartssh2.
///
/// Supports password and private-key authentication. The connection is
/// established lazily on [start] and can be reconnected after [terminate].
class SshBackend implements TermisolPtyBackend {
  @override
  final String name = 'SSH Backend';
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;

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
    this.privateKeyPassphrase,
  });

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
    try {
      final socket = await SSHSocket.connect(host, port)
          .timeout(const Duration(seconds: 10));

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: password != null ? () => password! : null,
        identities: await _loadIdentities(),
      );

      _session = await _client!.execute(
        'exec bash -l',
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: cols,
          height: rows,
        ),
      );

      _isRunning = true;

      _session!.stdout.listen(
        (data) => _safeAdd(data),
        onDone: () => _isRunning = false,
        onError: (e) {
          if (kDebugMode) debugPrint('[SSH] stdout error: $e');
          _isRunning = false;
        },
      );

      _session!.stderr.listen(
        (data) => _safeAdd(data),
        onError: (e) {
          if (kDebugMode) debugPrint('[SSH] stderr error: $e');
        },
      );

      if (kDebugMode) debugPrint('[SSH] Connected to $host:$port as $username');
    } catch (e) {
      _safeAdd(utf8.encode('\r\n[ssh error: $e]\r\n'));
      _isRunning = false;
      rethrow;
    }
  }

  Future<List<SSHKeyPair>> _loadIdentities() async {
    if (privateKeyPath == null) return [];
    try {
      final keyData = await File(privateKeyPath!).readAsString();
      return SSHKeyPair.fromPem(keyData, privateKeyPassphrase ?? '');
    } catch (e) {
      if (kDebugMode) debugPrint('[SSH] Failed to load private key: $e');
      return [];
    }
  }

  @override
  void write(List<int> data) {
    if (_session == null || !_isRunning) return;
    try {
      _session!.write(Uint8List.fromList(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[SSH] Write error: $e');
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_session != null && _isRunning) {
      try {
        _session!.resizeTerminal(cols, rows);
      } catch (e) {
        if (kDebugMode) debugPrint('[SSH] Resize error: $e');
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      _session?.close();
      await _session?.done.timeout(const Duration(seconds: 5), onTimeout: () {});
      _session = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[SSH] Stop error: $e');
    } finally {
      await _closeController();
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    try {
      _session?.close();
      await _session?.done.timeout(const Duration(seconds: 3), onTimeout: () {});
      _session = null;
      _client?.close();
      _client = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[SSH] Terminate error: $e');
    } finally {
      await _closeController();
    }
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
  bool get isConnected => _isRunning && _client != null && _session != null;
}
