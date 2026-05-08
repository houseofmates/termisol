import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'pty_backend.dart';
import 'bracketed_paste_manager.dart';
import 'focus_manager.dart';
import 'truecolor_manager.dart';
import 'kitty_graphics_manager.dart';
import 'mouse_protocol_manager.dart';
import 'ligature_font_manager.dart';
import 'throttled_renderer.dart';
import 'optimized_text_buffer.dart';
import 'lazy_terminal_output.dart';
import 'smart_auto_complete.dart';
import 'session_persistence.dart';
import 'crash_recovery.dart';
import 'long_command_notifier.dart';
import 'termisol_plugin_system.dart';
import 'ring_buffer_scrollback.dart';
import 'command_history.dart';
import '../ui/clipboard_manager.dart';

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
  late final RingBufferScrollback scrollback;
  TermisolPtyBackend? _backend;
  bool _connected = false;
  String? _error;
  final CommandHistory commandHistory = CommandHistory();
  StreamSubscription<List<int>>? _outputSub;

  /// Called when the user types `/ai <query>` and presses Enter.
  AiQueryHandler? onAiQuery;

  /// Called when the user types `edit <filename>` and presses Enter.
  EditCommandHandler? onEditCommand;

  /// Called when the terminal widget gains or loses focus.
  void Function(bool)? onFocusChanged;

  /// Called when the terminal receives focus events (bracketed paste mode).
  void Function(bool)? onFocusEvent;

  late final FocusManager focusManager;
  late final TrueColorManager trueColor;
  late final KittyGraphicsManager kittyGraphics;
  late final MouseProtocolManager mouseProtocol;
  late final LigatureFontManager ligatureFont;
  late final ThrottledRenderer throttledRenderer;
  late final TerminalClipboardManager clipboardManager;

  /// Called whenever data is received from the backend.
  void Function(String output)? onOutputReceived;

  final List<DetectedUrl> detectedUrls = [];
  final _urlRegex = RegExp(
    r'''https?://[^\s<>"'`\)\]\}]+''',
    caseSensitive: false,
  );

  final StringBuffer _inputBuffer = StringBuffer();

  // Optimization managers
  late final OptimizedTextBuffer _textBuffer;
  late final LazyTerminalOutput _lazyOutput;
  late final SmartAutoComplete _autoComplete;
  late final SessionPersistence _sessionPersistence;
  late final CrashRecovery _crashRecovery;
  late final LongCommandNotifier _commandNotifier;
  late final TermisolPluginSystem _pluginSystem;
  late final BracketedPasteManager bracketedPaste;

  bool get connected => _connected;
  String? get error => _error;

  TerminalSession({
    required this.id,
    required this.name,
    int maxLines = 50000,
  }) {
    // Initialize ring buffer scrollback with memory optimization
    scrollback = RingBufferScrollback(
      maxLines: maxLines,
      compressionThreshold: maxLines ~/ 5, // Compress after 20% capacity
      gcThreshold: maxLines ~/ 2, // GC at 50% capacity
    );
    
    terminal = Terminal(maxLines: 1000); // Keep terminal buffer small for performance
    controller = TerminalController();

    // Initialize optimization managers
    _textBuffer = OptimizedTextBuffer(maxLines: maxLines);
    _lazyOutput = LazyTerminalOutput(sessionId: id, visibleLines: 1000);
    _autoComplete = SmartAutoComplete();
    _sessionPersistence = SessionPersistence();
    _crashRecovery = CrashRecovery();
    _commandNotifier = LongCommandNotifier();
    _pluginSystem = TermisolPluginSystem();
    await _pluginSystem.initialize();

    bracketedPaste = BracketedPasteManager(terminal, controller);
    focusManager = FocusManager(terminal, controller, onFocusChanged, onFocusEvent);
    trueColor = TrueColorManager(terminal, controller);
    kittyGraphics = KittyGraphicsManager(terminal, controller);
    mouseProtocol = MouseProtocolManager(terminal, controller);
    ligatureFont = LigatureFontManager(terminal, controller);
    throttledRenderer = ThrottledRenderer(terminal);
    clipboardManager = TerminalClipboardManager(terminal, controller);

    // Setup advanced features
    focusManager.enableFocusEvents();
    trueColor.enable();
    kittyGraphics.enable();
    mouseProtocol.enable(TermisolMouseMode.any);
    ligatureFont.setFont('Fira Code', enableLigatures: true);

    // Start health monitoring and auto-save
    _crashRecovery.startHealthMonitoring(id);
    // Auto-save disabled: SessionPersistence does not expose startAutoSave
  }

  /// Rename this session and notify listeners.
  void rename(String newName) {
    name = newName;
    notifyListeners();
  }

  /// Start the session with an auto-detected shell.
  Future<void> start({String? workingDirectory}) async {
    if (_connected) return;

    try {
      // Use the cross-platform auto-detect factory
      _backend = TermisolPtyBackend.autoDetect(workingDirectory: workingDirectory);

      // Start the backend
      await _backend!.start();
      _connected = true;
      _error = null;

      // Enable terminal features
      terminal.write('\x1b[?2004h'); // bracketed paste
      terminal.write('\x1b[?1004h'); // focus tracking
      terminal.write('\x1b[?1;2c'); // TrueColor (DA1 response)
      terminal.write('\x1b[?1000h'); // mouse protocol
      terminal.write('\x1b[?1002h'); // button-event tracking
      terminal.write('\x1b[?1005h'); // UTF-8 mouse encoding

      bracketedPaste.enable();

      // Start listening for output with throttled rendering
      _outputSub = _backend!.output.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          // Normalize line endings for display consistency
          final normalized = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

          throttledRenderer.write(normalized);
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
    } catch (e, stack) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('TerminalSession start error: $e\n$stack');
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Write input to the backend. Intercepts `/ai` and `edit` commands.
  void writeInput(String input) {
    if (_backend == null || !_connected) return;

    _inputBuffer.write(input);

    if (input.contains('\n') || input.contains('\r')) {
      final bufferText = _inputBuffer.toString().trim();
      _inputBuffer.clear();

      if (bufferText.startsWith('/ai ')) {
        final query = bufferText.substring(4).trim();
        onAiQuery?.call(query).then((response) {
          terminal.write('\r\n[AI Response]\r\n$response\r\n');
        }).catchError((e) {
          terminal.write('\r\n[AI Error: $e]\r\n');
        });
        return;
      }

      if (bufferText.startsWith('edit ')) {
        final filePath = bufferText.substring(5).trim();
        onEditCommand?.call(filePath);
        return;
      }

      // Record non-empty commands to history
      if (bufferText.isNotEmpty) {
        commandHistory.add(bufferText);
      }
    }

    // Actually send input to the backend
    try {
      _backend!.write(utf8.encode(input));
    } catch (e, stack) {
      if (kDebugMode) debugPrint('writeInput error: $e\n$stack');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Resize the terminal.
  void resize(int cols, int rows) {
    terminal.resize(cols, rows);
    try {
      _backend?.resize(cols, rows);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('resize error: $e\n$stack');
    }
  }

  void _extractUrls(String text) {
    final matches = _urlRegex.allMatches(text);
    for (final match in matches) {
      final url = match.group(0)!;
      if (!detectedUrls.any((d) => d.url == url)) {
        detectedUrls.add(DetectedUrl(
          url: url,
          detectedAt: DateTime.now(),
        ));
        if (detectedUrls.length > 100) {
          detectedUrls.removeAt(0);
        }
      }
    }
  }

  /// Persist current session state.
  Map<String, dynamic> saveSessionState() {
    return {
      'id': id,
      'name': name,
      'connected': _connected,
      'error': _error,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Copy session data from another session.
  void copyFrom(TerminalSession other) {
    // Buffer copying not supported by xterm package
    terminal.resize(other.terminal.viewWidth, other.terminal.viewHeight);

    if (other._backend != null) {
      _backend = other._backend;
      _connected = other._connected;
      _error = other._error;
    }

    detectedUrls.clear();
    detectedUrls.addAll(other.detectedUrls);

    onAiQuery = other.onAiQuery;
    onEditCommand = other.onEditCommand;
  }

  /// Gracefully dispose the session and all resources.
  Future<void> disposeSession() async {
    await _outputSub?.cancel();
    _outputSub = null;
    _connected = false;

    try {
      await _backend?.stop();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('disposeSession stop error: $e\n$stack');
    }

    try {
      await _backend?.terminate();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('disposeSession terminate error: $e\n$stack');
    }

    _backend = null;
    _sessionPersistence.dispose();
    _crashRecovery.dispose();
    _commandNotifier.dispose();
    _autoComplete.dispose();
    _lazyOutput.dispose();
    _textBuffer.dispose();
    clipboardManager.dispose();
    await _pluginSystem.disposeAll();
  }

  @override
  void dispose() {
    disposeSession();
    super.dispose();
  }
}
