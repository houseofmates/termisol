import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'pty_backend.dart';

/// Callback signature for AI queries intercepted from the terminal.
///
/// The [query] contains everything after `/ai ` and may include any
/// characters or symbols. The callback should return the AI response
/// which will be printed into the terminal.
typedef AiQueryHandler = Future<String> Function(String query);

/// Callback signature for edit commands intercepted from the terminal.
///
/// The [filename] contains the filename specified in the edit command.
typedef EditCommandHandler = Future<void> Function(String filename);

/// A single terminal session that couples a [Terminal] with a [TermisolPtyBackend].
///
/// This is the rxvt-inspired daemon-client unit: lightweight, isolated,
/// and disposable without affecting other sessions.
class TerminalSession extends ChangeNotifier {
  final String id;
  String name;
  late final Terminal terminal;
  late final TerminalController controller;
  TermisolPtyBackend? _backend;
  StreamSubscription? _outputSub;

  bool _connected = false;
  String? _error;

  /// Called when the user types `/ai <query>` and presses Enter.
  /// If null, `/ai` commands are passed through to the shell normally.
  AiQueryHandler? onAiQuery;

  /// Called when the user types `edit <filename>` and presses Enter.
  /// If null, edit commands are passed through to the shell normally.
  EditCommandHandler? onEditCommand;

  /// Called whenever data is received from the backend.
  /// Useful for monitoring output to detect errors or context changes.
  void Function(String output)? onOutputReceived;

  /// Buffer for intercepting /ai commands. xterm sends data character
  /// by character, so we accumulate input until we see a newline.
  final StringBuffer _inputBuffer = StringBuffer();

  bool get connected => _connected;
  String? get error => _error;

  TerminalSession({
    required this.id,
    required this.name,
    int maxLines = 50000,
  }) {
    terminal = Terminal(maxLines: maxLines);
    controller = TerminalController();
  }

  /// rename this session and notify listeners.
  void rename(String newName) {
    name = newName;
    notifyListeners();
  }

  /// Start the session with an auto-detected shell.
  Future<void> start({String? workingDirectory}) async {
    _backend = TermisolPtyBackend.autoDetect(workingDirectory: workingDirectory);
    await _wireBackend();
  }

  /// Start with a custom backend (e.g. SSH).
  Future<void> startWithBackend(TermisolPtyBackend backend) async {
    _backend = backend;
    await _wireBackend();
  }

  Future<void> _wireBackend() async {
    terminal.onOutput = _handleTerminalOutput;
    terminal.onResize = (w, h, pw, ph) => _backend?.resize(w, h);

    try {
      await _backend!.start(
        cols: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
      _connected = true;

      _outputSub = _backend!.output.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          // Android shells run without a PTY, so their output uses raw \n
          // line endings. A real TTY translates \n -> \r\n (ONLCR). We
          // emulate that here so the terminal displays lines correctly.
          final normalized =
              text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
          terminal.write(normalized);
          onOutputReceived?.call(text);
        },
        onError: (Object e) {
          _error = e.toString();
          terminal.write('\r\n[backend error: $e]\r\n');
          notifyListeners();
        },
        onDone: () {
          _connected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = e.toString();
      terminal.write('\r\n[connection failed: $e]\r\n');
      notifyListeners();
    }
  }

  /// Intercept terminal output to detect `/ai` commands.
  void _handleTerminalOutput(String data) {
    final bytes = utf8.encode(data);

    // Check if this looks like a newline (Enter pressed).
    final isNewline = bytes.isNotEmpty &&
        (bytes.last == 0x0D || // \r
            bytes.last == 0x0A); // \n

    if (isNewline) {
      _inputBuffer.write(data);
      final line = _inputBuffer.toString().trim();
      _inputBuffer.clear();

      if (onAiQuery != null && line.startsWith('/ai ')) {
        final query = line.substring(4);
        _processAiQuery(query);
        return; // Do not send to shell.
      }
      
      if (onEditCommand != null && line.startsWith('edit ')) {
        final filename = line.substring(5).trim();
        _processEditCommand(filename);
        return; // Do not send to shell.
      }
    } else {
      _inputBuffer.write(data);
    }

    _backend?.write(bytes);
  }

  /// Send the AI query and display the response in the terminal.
  Future<void> _processAiQuery(String query) async {
    terminal.write('\r\n');
    terminal.write('\x1b[36m[AI] Processing: $query...\x1b[0m\r\n');

    try {
      final response = await onAiQuery!(query);
      terminal.write('\x1b[36m[AI] $response\x1b[0m\r\n');
    } catch (e) {
      terminal.write('\x1b[31m[AI] Error: $e\x1b[0m\r\n');
    }
  }

  /// Launch the edit command with the specified filename.
  Future<void> _processEditCommand(String filename) async {
    terminal.write('\r\n');
    terminal.write('\x1b[33m[EDIT] Opening editor: $filename\x1b[0m\r\n');

    try {
      await onEditCommand!(filename);
      terminal.write('\x1b[33m[EDIT] Editor closed\x1b[0m\r\n');
    } catch (e) {
      terminal.write('\x1b[31m[EDIT] Error: $e\x1b[0m\r\n');
    }
  }

  /// Write text directly into the terminal buffer (e.g. for AI responses).
  void writeInput(String text) {
    terminal.write(text);
  }

  /// Send raw data to the backend without interception.
  void sendToBackend(List<int> data) {
    _backend?.write(data);
  }

  Future<void> disposeSession() async {
    await _outputSub?.cancel();
    _outputSub = null;
    if (_backend != null) {
      await _backend!.terminate();
      _backend = null;
    }
    controller.dispose();
    _connected = false;
  }

  @override
  void dispose() {
    disposeSession();
    super.dispose();
  }
}
