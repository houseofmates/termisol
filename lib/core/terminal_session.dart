import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'pty_backend.dart';
import 'bracketed_paste_manager.dart';
import 'focus_manager.dart';
import 'kitty_graphics_manager.dart';
import 'mouse_protocol_manager.dart';
import 'ligature_font_manager.dart';
import 'throttled_renderer.dart';
import 'smart_auto_complete.dart';
import 'smart_command_chaining.dart';
import 'semantic_search_engine.dart';
import 'session_persistence.dart';
import 'termisol_core_integration.dart';
import 'crash_recovery.dart';
import 'long_command_notifier.dart';
import 'termisol_plugin_system.dart';
import 'graphics_protocol_handler.dart';
import 'command_history.dart';
import 'hyperlink_handler.dart';
import 'command_alias_system.dart';
import 'directory_tracker.dart';
import '../ui/clipboard_manager.dart';

/// called when the user types `/ai <query>` and presses enter.
typedef AiQueryHandler = Future<String> Function(String query);

/// called when the user types `edit <filename>` and presses enter.
typedef EditCommandHandler = Future<void> Function(String filePath);

/// a url detected in terminal output.
class DetectedUrl {
  final String url;
  final DateTime detectedAt;

  DetectedUrl({required this.url, required this.detectedAt});
}

/// encapsulates a single terminal instance with its backend, controller,
/// and various optimization managers.
class TerminalSession extends ChangeNotifier {
  final String id;
  String name;
  late final Terminal terminal;
  late final TerminalController controller;
  TermisolPtyBackend? _backend;
  bool _connected = false;
  String? _error;
  final CommandHistory commandHistory = CommandHistory();
  StreamSubscription<dynamic>? _outputSub;
  late final CommandAliasSystem _aliasSystem;
  late final DirectoryTracker _directoryTracker;
  late final ValueNotifier<String?> _directoryNotifier;
  ValueNotifier<String?> get directory => _directoryNotifier;

  AiQueryHandler? onAiQuery;
  EditCommandHandler? onEditCommand;
  void Function(bool)? onFocusChanged;
  void Function(bool)? onFocusEvent;
  void Function(String)? onInputIntercepted;
  void Function(String)? onNotification;

  late final FocusManager focusManager;
  late final KittyGraphicsManager kittyGraphics;
  late final MouseProtocolManager mouseProtocol;
  late final LigatureFontManager ligatureFont;
  late final ThrottledRenderer throttledRenderer;
  late final TerminalClipboardManager clipboardManager;
  late final GraphicsProtocolHandler graphicsHandler;

  void Function(String output)? onOutputReceived;

  Future<List<String>> getCommandSuggestions(
    String currentInput, {
    int maxSuggestions = 5,
  }) async {
    final suggestions = await _autoComplete.getSuggestions(currentInput);
    return suggestions.map((s) => s.command).take(maxSuggestions).toList();
  }

  List<String> getChainedSuggestions(
    String currentCommand, {
    int maxSuggestions = 5,
  }) {
    final suggestions = _commandChaining.suggestNext(
      currentCommand,
      maxSuggestions: maxSuggestions,
    );
    return suggestions.map((s) => s.command).toList();
  }

  List<String> searchTerminalOutput(String query, {int maxResults = 10}) {
    try {
      final results = _semanticSearch.search(
        'terminal_output',
        query,
        maxResults: maxResults,
      );
      return results.map((result) => result.content).toList();
    } on Exception catch (e, stack) {
      debugPrint('Semantic search failed: $e\n$stack');
      return [];
    }
  }

  final List<DetectedUrl> detectedUrls = [];
  final _urlRegex = RegExp(
    r'''https?://[^\s<>"'\`\)\]\}]+''',
    caseSensitive: false,
  );

  final StringBuffer _inputBuffer = StringBuffer();

  late final SmartAutoComplete _autoComplete;
  late final SmartCommandChaining _commandChaining;
  late final SemanticSearchEngine _semanticSearch;
  late final SessionPersistence _sessionPersistence;
  late final CrashRecovery _crashRecovery;
  late final LongCommandNotifier _commandNotifier;
  late final TermisolPluginSystem _pluginSystem;
  late final BracketedPasteManager bracketedPaste;
  late final HyperlinkHandler _hyperlinkHandler;

  bool get connected => _connected;
  String? get error => _error;
  LongCommandNotifier get longCommandNotifier => _commandNotifier;

  bool _isDisposed = false;

  TerminalSession({
    required this.id,
    required this.name,
    this.onNotification,
    int maxLines = 50000,
  }) {
    terminal = Terminal();
    controller = TerminalController();
    terminal.onOutput = (data) => writeInput(data);

    _autoComplete = SmartAutoComplete();
    _commandChaining = SmartCommandChaining();
    _semanticSearch = SemanticSearchEngine();
    _sessionPersistence = SessionPersistence();
    _crashRecovery = CrashRecovery();
    _commandNotifier = LongCommandNotifier();
    _pluginSystem = TermisolPluginSystem();

    bracketedPaste = BracketedPasteManager(terminal, controller);
    focusManager = FocusManager(
      terminal,
      controller,
      onFocusChanged,
      onFocusEvent,
    );
    kittyGraphics = KittyGraphicsManager(terminal, controller);
    mouseProtocol = MouseProtocolManager(terminal, controller);
    ligatureFont = LigatureFontManager(terminal, controller);
    throttledRenderer = ThrottledRenderer(terminal);
    clipboardManager = TerminalClipboardManager(terminal, controller);
    graphicsHandler = GraphicsProtocolHandler(terminal, controller);
    _hyperlinkHandler = HyperlinkHandler();
    _hyperlinkHandler.attach(terminal);

    _aliasSystem = CommandAliasSystem.instance;
    unawaited(
      _aliasSystem.load().catchError((e, stack) {
        debugPrint('Alias system load failed: $e\n$stack');
      }),
    );

    _directoryTracker = DirectoryTracker();
    _directoryNotifier = ValueNotifier<String?>(null);
    _directoryTracker.directory.addListener(() {
      _directoryNotifier.value = _directoryTracker.currentDirectory;
    });

    focusManager.enableFocusEvents();
    kittyGraphics.enable();
    mouseProtocol.enable(TermisolMouseMode.any);
    unawaited(
      _initLigatureFont().catchError((e, stack) {
        debugPrint('Ligature font init failed: $e\n$stack');
      }),
    );

    _crashRecovery.startHealthMonitoring(id);
    _sessionPersistence.setAutoSaveEnabled(true);

    TermisolCoreIntegration.instance.activeConfig.addListener(
      _onCoreConfigChanged,
    );
  }

  void _onCoreConfigChanged() {
    applyCoreConfig(TermisolCoreIntegration.instance.activeConfig.value);
  }

  Future<void> _initLigatureFont() async {
    final ok = await ligatureFont.setFont('Fira Code');
    if (!ok) {
      await ligatureFont.setFont('monospace');
      onNotification?.call('fira code unavailable, using monospace fallback');
    }
  }

  void rename(String newName) {
    name = newName;
    notifyListeners();
  }

  Future<void> start({String? workingDirectory}) async {
    if (_connected) return;

    try {
      _backend = TermisolPtyBackend.autoDetect(
        workingDirectory: workingDirectory,
      );

      await _backend!.start();
      _connected = true;
      _error = null;

      await _pluginSystem.initialize();
      await graphicsHandler.initialize();
      await _commandChaining.initialize();
      await _semanticSearch.initialize();

      terminal.write('\x1b[?2004h');
      terminal.write('\x1b[?1004h');
      terminal.write('\x1b[?1;2c');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');
      terminal.write('\x1b[?1005h');

      bracketedPaste.enable();

      final rawStream = _backend!.output.asyncMap((data) async {
        final text = utf8.decode(data, allowMalformed: true);
        final normalized = text.contains('\x1b')
            ? text
            : text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');

        final processedText = await graphicsHandler.processOutput(
          normalized,
          terminal.viewWidth,
          terminal.viewHeight,
        );
        throttledRenderer.write(processedText);
        _directoryTracker.processOutput(text);
        _extractUrls(text);
        _hyperlinkHandler.processOutput(text);
        _semanticSearch.indexDocument('terminal_output', id, text, metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'session_id': id,
        });
        onOutputReceived?.call(text);
      });
      _outputSub = rawStream.listen(
        null,
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

  void writeInput(String input) {
    if (_isDisposed) return;
    onInputIntercepted?.call(input);

    if (_backend == null || !_connected) return;

    _inputBuffer.write(input);

    if (input.contains('\n') || input.contains('\r')) {
      final bufferText = _inputBuffer.toString().trim();
      _inputBuffer.clear();

      final expanded = _aliasSystem.expand(bufferText);
      if (expanded != bufferText) {
        terminal.write('\r\n[alias: $bufferText → $expanded]\r\n');
        final backspaces = '\x7f' * bufferText.length;
        _backend!.write(utf8.encode(backspaces));
        _backend!.write(utf8.encode('$expanded\r'));
        return;
      }

      if (bufferText.startsWith('/ai ')) {
        final query = bufferText.substring(4).trim();
        unawaited(
          onAiQuery
                  ?.call(query)
                  .then((response) {
                    if (_isDisposed) return;
                    terminal.write('\r\n[AI Response]\r\n$response\r\n');
                  })
                  .catchError((e) {
                    if (_isDisposed) return;
                    terminal.write('\r\n[AI Error: $e]\r\n');
                  }) ??
              Future<void>.value(),
        );
        return;
      }

      if (bufferText.startsWith('edit ')) {
        final filePath = bufferText.substring(5).trim();
        unawaited(
          onEditCommand?.call(filePath).catchError((e) {
                if (_isDisposed) return;
                terminal.write('\r\n[Edit Error: $e]\r\n');
              }) ??
              Future<void>.value(),
        );
        return;
      }

      if (bufferText.isNotEmpty) {
        unawaited(
          commandHistory.add(bufferText).catchError((e) {
            debugPrint('commandHistory.add error: $e');
          }),
        );
        _autoComplete.addToHistory(bufferText);
        _commandNotifier.notifyLongCommand(
          bufferText,
          timeout: const Duration(seconds: 10),
        );
        _commandChaining.recordCommand(id, bufferText, cwd: directory.value);
      }
    }

    try {
      _backend!.write(utf8.encode(input));
    } catch (e, stack) {
      if (kDebugMode) debugPrint('writeInput error: $e\n$stack');
      _error = e.toString();
      notifyListeners();
    }
  }

  void sendRawInput(String input) {
    if (_backend == null || !_connected) return;
    try {
      _backend!.write(utf8.encode(input));
    } catch (e, stack) {
      if (kDebugMode) debugPrint('sendRawInput error: $e\n$stack');
      _error = e.toString();
      notifyListeners();
    }
  }

  void resize(int cols, int rows) {
    if (cols <= 0 || rows <= 0) return;
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
        detectedUrls.add(DetectedUrl(url: url, detectedAt: DateTime.now()));
        if (detectedUrls.length > 100) {
          detectedUrls.removeAt(0);
        }
      }
    }
  }

  String? getHyperlinkAt(int line, int column) {
    return _hyperlinkHandler.getUrlAt(line, column);
  }

  Map<String, dynamic> saveSessionState() {
    return {
      'id': id,
      'name': name,
      'connected': _connected,
      'error': _error,
      'workingDirectory': directory.value,
      'terminalWidth': terminal.viewWidth,
      'terminalHeight': terminal.viewHeight,
      'commandHistory': commandHistory.commands.toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void copyFrom(TerminalSession other) {
    terminal.resize(other.terminal.viewWidth, other.terminal.viewHeight);

    if (other._backend != null) {
      _backend = other._backend;
      other._backend = null;
      _connected = other._connected;
      _error = other._error;
    }

    detectedUrls.clear();
    detectedUrls.addAll(other.detectedUrls);

    for (final cmd in other.commandHistory.commands) {
      unawaited(
        commandHistory.add(cmd).catchError((e) {
          debugPrint('copyFrom commandHistory.add error: $e');
        }),
      );
    }

    _directoryTracker.directory.value = other.directory.value ?? '';

    onAiQuery = other.onAiQuery;
    onEditCommand = other.onEditCommand;
    onNotification = other.onNotification;
  }

  void applyCoreConfig(TermisolCoreConfig config) {
    try {
      terminal.buffer.lines.maxLength = config.maxScrollbackLines;
      ligatureFont.setFont(
        ligatureFont.currentFont,
        enableLigatures: config.enableGpuAcceleration,
      );
      throttledRenderer.setTargetFps(config.targetFps);
    } on Exception catch (e, stack) {
      debugPrint('failed to apply core config: $e\n$stack');
    }
  }

  Future<void> disposeSession() async {
    _isDisposed = true;
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
    _directoryTracker.dispose();
    _directoryNotifier.dispose();
    await _sessionPersistence.dispose();
    _crashRecovery.dispose();
    _commandNotifier.dispose();
    _autoComplete.dispose();
    clipboardManager.dispose();
    focusManager.dispose();
    kittyGraphics.dispose();
    mouseProtocol.dispose();
    ligatureFont.dispose();
    throttledRenderer.dispose();
    unawaited(graphicsHandler.dispose());
    bracketedPaste.disable();
    await _pluginSystem.dispose();
    _hyperlinkHandler.dispose();
    TermisolCoreIntegration.instance.activeConfig.removeListener(
      _onCoreConfigChanged,
    );
  }

  @override
  void dispose() {
    unawaited(
      disposeSession().catchError((e, stack) {
        debugPrint('disposeSession error: $e\n$stack');
      }),
    );
    super.dispose();
  }
}
