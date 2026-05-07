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
  Future<void> start({int cols = 80, int rows = 24}) async {
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
        (data) => _outputController.add(data),
        onDone: () => _isRunning = false,
        onError: (e) {
          debugPrint('[SSH] stdout error: $e');
          _isRunning = false;
        },
      );

      _session!.stderr.listen(
        (data) => _outputController.add(data),
        onError: (e) => debugPrint('[SSH] stderr error: $e'),
      );

      debugPrint('[SSH] Connected to $host:$port as $username');
    } catch (e) {
      _outputController.add(utf8.encode('\r\n[ssh error: $e]\r\n'));
      _isRunning = false;
    }
  }

  Future<List<SSHKeyPair>> _loadIdentities() async {
    if (privateKeyPath == null) return [];
    try {
      final keyData = await File(privateKeyPath!).readAsString();
      return SSHKeyPair.fromPem(keyData, privateKeyPassphrase ?? '');
    } catch (e) {
      debugPrint('[SSH] Failed to load private key: $e');
      return [];
    }
  }

  @override
  void write(List<int> data) {
    if (_session == null) return;
    try {
      _session!.write(Uint8List.fromList(data));
    } catch (e) {
      debugPrint('[SSH] Write error: $e');
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_session == null) return;
    try {
      _session!.resizeTerminal(cols, rows);
    } catch (e) {
      debugPrint('[SSH] Resize error: $e');
    }
  }

  @override
  Future<void> terminate() async {
    _isRunning = false;
    try {
      await _session?.done;
      _session = null;
      _client?.close();
      _client = null;
    } catch (e) {
      debugPrint('[SSH] Terminate error: $e');
    }
    await _outputController.close();
  }
}
