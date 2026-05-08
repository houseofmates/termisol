import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:xterm/xterm.dart';
import '../backends/pty_backend.dart';
import '../ai/ai_terminal_assistant.dart';
import '../core/advanced_terminal_protocol.dart';
import '../config/pkm_theme.dart';
import 'bracketed_paste_manager.dart';
import 'focus_manager.dart';
import 'truecolor_manager.dart';
import 'kitty_graphics_manager.dart';
import 'mouse_protocol_manager.dart';
import 'ligature_font_manager.dart';
import 'throttled_renderer.dart';

/// Called when the user types `/ai <query>` and presses Enter.
/// If null, `/ai` commands are passed through to shell normally.
typedef AiQueryHandler = Future<String> Function(String query);

/// Called when the user types `edit <filename>` and presses Enter.
/// If null, edit commands are passed through to the shell normally.
typedef EditCommandHandler = Future<void> Function(String filePath);

/// A URL detected in terminal output.
class DetectedUrl {
  final String url;
  final DateTime detectedAt;

  DetectedUrl({required this.url, required this.detectedAt});
}

/// Encapsulates a single terminal instance with its backend, controller,
/// and various optimization managers. Handles input/output, AI queries, edit commands,
/// and session persistence.
class TerminalSession extends ChangeNotifier {
  final String id;
  String name;
  late final Terminal terminal;
  late final TerminalController controller;
  TermisolPtyBackend? _backend;
  bool _connected = false;
  String? _error;
  StreamSubscription? _outputSub;

  /// Called when the user types `/ai <query>` and presses Enter.
  /// If null, `/ai` commands are passed through to shell normally.
  AiQueryHandler? onAiQuery;

  /// Called when the user types `edit <filename>` and presses Enter.
  /// If null, edit commands are passed through to the shell normally.
  EditCommandHandler? onEditCommand;

  /// Called when the terminal widget gains or loses focus.
  void Function(bool)? onFocusChanged;

  /// Called when the terminal receives focus events (bracketed paste mode).
  void Function(bool)? onFocusEvent;

  /// Focus manager for bracketed paste integration.
  late final FocusManager focusManager;

  /// TrueColor manager for 24-bit color support.
  late final TrueColorManager trueColor;

  /// Called whenever data is received from the backend.
  /// Useful for monitoring output to detect errors or context changes.
  void Function(String output)? onOutputReceived;

  /// Detected URLs from terminal output, updated on each output batch.
  final List<DetectedUrl> detectedUrls = [];
  final _urlRegex = RegExp(
    r"https?://[^\s<>\"'`\)\]\}]+",
    caseSensitive: false,
  );

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
    bracketedPaste = BracketedPasteManager(terminal, controller);
    
    // Start health monitoring and auto-save
      _crashRecovery.startHealthMonitoring();
    _sessionPersistence.startAutoSave(() => _saveSessionState());
      
      // Setup focus management
      focusManager = FocusManager(terminal, controller, onFocusChanged, onFocusEvent);
      focusManager.enableFocusEvents();
      
      // Setup TrueColor support
      trueColor = TrueColorManager(terminal, controller);
      trueColor.enable();
  }

  /// rename this session and notify listeners.
  void rename(String newName) {
    name = newName;
    notifyListeners();
  }

  /// Start the session with an auto-detected shell.
  Future<void> start({String? workingDirectory}) async {
    if (_connected) return;

    try {
      // Detect platform and create appropriate backend
      if (Platform.isAndroid) {
        _backend = AndroidShellBackend();
      } else if (Platform.isLinux || Platform.isMacOS) {
        _backend = LocalPtyBackend();
      } else if (Platform.isWindows) {
        _backend = WindowsPtyBackend();
      } else {
        throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
      }

      // Start the backend
      await _backend!.start(workingDirectory: workingDirectory);
      _connected = true;
      _error = null;

      // Enable bracketed paste mode
      terminal.write('\x1b[?2004h');

      // Enable focus tracking
      terminal.write('\x1b[?1004h');

      // Enable TrueColor (24-bit)
      terminal.write('\x1b[?1;2c');

      // Enable mouse protocol
      terminal.write('\x1b[?1000h');

      // Enable extended keyboard
      terminal.write('\x1b[?1002h');

      // Enable Unicode
      terminal.write('\x1b[?1005h');

      // Enable bracketed paste
      bracketedPaste.enable();

      // Start listening for output
      _outputSub = _backend!.output.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          // Android shells run without a PTY, so their output uses raw \n
          // line endings. A real TTY translates \n -> \r\n (ONLCR). We
          // emulate that here so the terminal displays lines correctly.
          final normalized =
              text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
          terminal.write(normalized);
          _extractUrls(text);
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

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Write input to the backend. Intercepts `/ai` and `edit` commands.
  void writeInput(String input) {
    if (_backend == null || !_connected) return;

    // Accumulate input for AI command detection
    _inputBuffer.write(input);

    // Check for AI query command
    if (input.contains('\n') || input.contains('\r')) {
      final bufferText = _inputBuffer.toString().trim();
      _inputBuffer.clear();

      if (bufferText.startsWith('/ai ')) {
        final query = bufferText.substring(4).trim();
        onAiQuery?.call(query).then((response) {
          terminal.write('\r\n[AI Response]\r\n$response\r\n');
        });
        return; // Don't send to shell
      }

      if (bufferText.startsWith('edit ')) {
        final filePath = bufferText.substring(5).trim();
        onEditCommand?.call(filePath);
        return; // Don't send to shell
      }
    }

    _backend!.writeInput(utf8.encode(input));
  }

  /// Resize the terminal.
  void resize(int width, int height) {
    _backend?.resize(width, height);
    terminal.resize(width, height);
  }

  /// Stop the session and clean up resources.
  Future<void> disposeSession() async {
    _sessionPersistence.stopAutoSave();
    _crashRecovery.dispose();
    _commandNotifier.dispose();
    await _pluginSystem.disposeAll();
    
    _outputSub?.cancel();
    await _backend?.stop();
    _backend = null;
  }

  /// Scan text for URLs and add them to detectedUrls with deduplication.
  void _extractUrls(String text) {
    final matches = _urlRegex.allMatches(text);
    for (final match in matches) {
      final url = match.group(0)!;
      if (!detectedUrls.any((d) => d.url == url)) {
        detectedUrls.add(DetectedUrl(
          url: url,
          detectedAt: DateTime.now(),
        ));
        // Keep list bounded
        if (detectedUrls.length > 100) {
          detectedUrls.removeAt(0);
        }
      }
    }
  }

  @override
  void dispose() {
    disposeSession();
    super.dispose();
  }
}
