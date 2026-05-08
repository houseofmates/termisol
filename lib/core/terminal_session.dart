import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'pty_backend.dart';
import '../backends/local_backend.dart';
import '../backends/ssh_backend.dart';
import '../backends/android_shell_backend.dart';
import 'crash_recovery.dart';
import 'long_command_notifier.dart';
import 'termisol_plugin_system.dart';
import 'smart_auto_complete.dart';
import 'session_persistence.dart';

// Session data for saving/loading
class TerminalSessionData {
  final String id;
  final String name;
  final String type;
  final Map<String, dynamic> state;
  final DateTime timestamp;

  TerminalSessionData({
    required this.id,
    required this.name,
    required this.type,
    required this.state,
    required this.timestamp,
  });
}

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

  // Optimization managers
  late final OptimizedTextBuffer _textBuffer;
  late final LazyTerminalOutput _lazyOutput;
  late final SmartAutoComplete _autoComplete;
  late final SessionPersistence _sessionPersistence;
  late final CrashRecovery _crashRecovery;
  late final LongCommandNotifier _commandNotifier;
  late final TermisolPluginSystem _pluginSystem;

  bool get connected => _connected;
  String? get error => _error;

  TerminalSession({
    required this.id,
    required this.name,
    int maxLines = 50000,
  }) {
    terminal = Terminal(maxLines: maxLines);
    controller = TerminalController();
    
    // Initialize optimization managers
    _textBuffer = OptimizedTextBuffer(maxLines: maxLines);
    _lazyOutput = LazyTerminalOutput(sessionId: id, visibleLines: 1000);
    _autoComplete = SmartAutoComplete();
    _sessionPersistence = SessionPersistence();
    _crashRecovery = CrashRecovery();
    _commandNotifier = LongCommandNotifier();
    _pluginSystem = TermisolPluginSystem();
    
    // Start health monitoring and auto-save
    _crashRecovery._startHealthMonitoring();
    _sessionPersistence.startAutoSave(() => _saveSessionState());
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

      // Add to auto-complete history
      _autoComplete.addToHistory(line);

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

      // Check for long-running commands
      _checkForLongCommand(line);
    } else {
      _inputBuffer.write(data);
    }

    // Add to optimized text buffer
    _textBuffer.append(data);
    _lazyOutput.addContent([data]);

    _backend?.write(bytes);
  }

  /// Check if command should trigger long-running notification
  void _checkForLongCommand(String command) {
    final longCommands = [
      'apt-get install', 'apt install', 'dnf install', 'yum install',
      'make', 'cmake', 'cargo build', 'npm install', 'yarn install',
      'pip install', 'pip3 install', 'docker build', 'docker-compose up',
      'git clone', 'wget', 'curl', 'rsync', 'scp', 'ffmpeg',
    ];

    for (final longCmd in longCommands) {
      if (command.startsWith(longCmd)) {
        _commandNotifier.notifyLongCommand(command);
        break;
      }
    }
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

  /// Save current session state
  Future<void> _saveSessionState() async {
    try {
      final sessionData = TerminalSessionData(
        id: id,
        name: name,
        type: _backend?.runtimeType.toString() ?? 'local',
        state: {
          'terminal_content': _textBuffer.getVisibleText(1000),
          'cursor_position': _textBuffer._cursorPosition,
          'history': _autoComplete._recentCommands,
          'timestamp': DateTime.now().toIso8601String(),
        },
        timestamp: DateTime.now(),
      );
      
      await _sessionPersistence.saveSessions([sessionData]);
    } catch (e) {
      print('Failed to save session state: $e');
    }
  }

  /// Get auto-complete suggestions for current input
  Future<List<CommandSuggestion>> getAutoCompleteSuggestions(String partialCommand) async {
    return await _autoComplete.getSuggestions(partialCommand);
  }

  /// Get session statistics
  Map<String, dynamic> getSessionStats() {
    return {
      'buffer_stats': _textBuffer.stats,
      'lazy_output_stats': {
        'total_lines': _lazyOutput.totalLineCount,
        'visible_lines': _lazyOutput.visibleLineCount,
        'is_loading': _lazyOutput.isLoading,
      },
      'auto_complete_stats': {
          'history_size': _autoComplete.recentCommands.length,
          'command_frequency': _autoComplete.commandFrequency,
      },
      'active_plugins': _pluginSystem.loadedPlugins.map((p) => p.name).toList(),
      'active_long_commands': _commandNotifier.activeCommands,
    };
  }

  Future<void> disposeSession() async {
    // Save session state before disposal
    await _saveSessionState();
    
    // Cancel long command notifications
    for (final command in _commandNotifier.activeCommands.keys) {
      _commandNotifier.cancelNotification(command);
    }
    
    // Dispose optimization managers
    _textBuffer.clear();
    _lazyOutput.dispose();
    _autoComplete.clearHistory();
    _sessionPersistence.stopAutoSave();
    _crashRecovery.dispose();
    _commandNotifier.dispose();
    await _pluginSystem.disposeAll();
    
    _outputSub?.cancel();
    await _backend?.stop();
    _backend = null;
  }

  @override
  void dispose() {
    disposeSession();
    super.dispose();
  }
}
