import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart' show Terminal, TerminalTheme, TerminalView, TerminalViewState, BufferPosition;
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../core/deep_l_service.dart';
import '../core/graphics_protocol_handler.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';
import 'copy_mode_overlay.dart';
import 'custom_hotkey_manager.dart';

/// active terminal theme based on the current [pkmtheme.thememode].
TerminalTheme get termisolTerminalTheme => PkmTheme.activeTerminalTheme;

const _defaultTerminalFontSize = 14.0;
const _minFontSize = 8.0;
const _maxFontSize = 32.0;

/// gpu-optimized terminal widget for termisol
class TermisolTerminalView extends StatefulWidget {
  final TerminalSession session;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onNewTab;
  final VoidCallback? onNewWindow;
  final VoidCallback? onCloseTab;
  final Future<String> Function(String text)? onSummarize;
  final ScrollController? scrollController;

  const TermisolTerminalView({
    super.key,
    required this.session,
    this.autofocus = true,
    this.focusNode,
    this.onNewTab,
    this.onNewWindow,
    this.onCloseTab,
    this.onSummarize,
    this.scrollController,
  });

  @override
  State<TermisolTerminalView> createState() => _TermisolTerminalViewState();
}

class _TermisolTerminalViewState extends State<TermisolTerminalView> {
  late final TerminalClipboardManager _clipboard;
  late final GraphicsProtocolHandler _graphicsHandler;
  late final CustomHotkeyManager _hotkeyManager;
  final _deepL = DeepLTranslationService();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  bool _isSummarizing = false;
  bool _isTranslating = false;
  bool _isCopyMode = false;
  double _fontSize = _defaultTerminalFontSize;
  MouseCursor _mouseCursor = SystemMouseCursors.text;
  String _fontFamily = 'DroidSansMono';

  // autocomplete state
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  String? _currentInput;

  // command chaining state
  List<String> _chainSuggestions = [];
  bool _showChainSuggestions = false;
  void Function(String)? _originalOnOutput;

  @override
  void initState() {
    super.initState();
    PkmTheme.themeMode.addListener(_onThemeChanged);
    PkmTheme.bgOpacity.addListener(_onBgOpacityChanged);
    _deepL.initialize();
    _graphicsHandler = GraphicsProtocolHandler(
      widget.session.terminal,
      widget.session.controller,
    );
    _graphicsHandler.initialize();
    _clipboard = TerminalClipboardManager(
      widget.session.terminal,
      widget.session.controller,
    );
    _hotkeyManager = CustomHotkeyManager(
      session: widget.session,
      clipboard: _clipboard,
      onNewTab: widget.onNewTab,
      onSaveFile: _saveCurrentFile,
      onSearch: _showSearchOverlay,
      onCopyAll: _copyAllContent,
    );
    widget.session.addListener(_onSessionChanged);
    _loadTerminalStyle();
    _hookOutputForChaining();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode?.requestFocus();
    });
  }

  void _hookOutputForChaining() {
    _originalOnOutput = widget.session.onOutputReceived;
    widget.session.onOutputReceived = (output) {
      _originalOnOutput?.call(output);
      _updateChainSuggestions();
    };
  }

  void _updateChainSuggestions() {
    final lastCommand = widget.session.commandHistory.commands.isNotEmpty
        ? widget.session.commandHistory.commands.first
        : null;
    if (lastCommand == null) return;
    final suggestions = widget.session.getChainedSuggestions(lastCommand);
    if (mounted) {
      setState(() {
        _chainSuggestions = suggestions;
        _showChainSuggestions = suggestions.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    PkmTheme.themeMode.removeListener(_onThemeChanged);
    PkmTheme.bgOpacity.removeListener(_onBgOpacityChanged);
    widget.session.removeListener(_onSessionChanged);
    widget.session.onOutputReceived = _originalOnOutput;
    _graphicsHandler.dispose();
    _clipboard.dispose();
    _hotkeyManager.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onBgOpacityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTerminalStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSize = prefs.getDouble('termisol_font_size');
    if (savedSize != null && mounted) {
      setState(() => _fontSize = savedSize.clamp(_minFontSize, _maxFontSize));
    }
    final savedFont = prefs.getString('termisol_font_family');
    if (savedFont != null && mounted) {
      setState(() => _fontFamily = savedFont);
    }
    final savedOpacity = prefs.getDouble('termisol_bg_opacity');
    if (savedOpacity != null && mounted) {
      PkmTheme.bgOpacity.value = savedOpacity.clamp(0.5, 1.0);
    }
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('termisol_font_size', _fontSize);
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _zoomIn() {
    setState(() {
      _fontSize = (_fontSize + 1.0).clamp(_minFontSize, _maxFontSize);
    });
    unawaited(_saveFontSize());
  }

  void _zoomOut() {
    setState(() {
      _fontSize = (_fontSize - 1.0).clamp(_minFontSize, _maxFontSize);
    });
    unawaited(_saveFontSize());
  }

  void _zoomReset() {
    setState(() {
      _fontSize = _defaultTerminalFontSize;
    });
    unawaited(_saveFontSize());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // First try custom hotkey manager
    final customResult = _hotkeyManager.handleKeyEvent(node, event);
    if (customResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
         event.logicalKey == LogicalKeyboardKey.numpadAdd ||
         (shift && event.logicalKey == LogicalKeyboardKey.equal))) {
      _zoomIn();
      return KeyEventResult.handled;
    }

    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
         event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _zoomOut();
      return KeyEventResult.handled;
    }

    if (ctrl &&
        !shift &&
        (event.logicalKey == LogicalKeyboardKey.digit0 ||
         event.logicalKey == LogicalKeyboardKey.numpad0)) {
      _zoomReset();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab && !ctrl) {
      _triggerAutocomplete();
      return KeyEventResult.handled;
    }

    // Hide suggestion popups on any other key
    if (_showSuggestions || _showChainSuggestions) {
      setState(() {
        _showSuggestions = false;
      });
    }

    return KeyEventResult.ignored;
  }

  String _extractCurrentInput() {
    final buffer = widget.session.terminal.buffer;
    if (buffer.height == 0) return '';
    final lastLine = buffer.lines[buffer.height - 1].getText();
    // heuristic: split on common prompt separators and take the last part
    final separators = RegExp(r'[\$>#%]\s*');
    final parts = lastLine.split(separators);
    return parts.isNotEmpty ? parts.last.trim() : lastLine.trim();
  }

  bool _autocompleteInProgress = false;

  Future<void> _triggerAutocomplete() async {
    if (_autocompleteInProgress) return;
    final input = _extractCurrentInput();
    if (input.isEmpty) return;
    _autocompleteInProgress = true;
    try {
      final suggestions = await widget.session.getCommandSuggestions(input);
      if (!mounted) return;
      setState(() {
        _currentInput = input;
        _suggestions = suggestions;
        _showSuggestions = suggestions.isNotEmpty;
      });
    } on Exception catch (e, stack) {
      debugPrint('autocomplete failed: $e\n$stack');
    } finally {
      _autocompleteInProgress = false;
    }
  }

  void _insertSuggestion(String suggestion) {
    final input = _currentInput ?? '';
    // Send backspaces to clear current input
    if (input.isNotEmpty) {
      widget.session.sendRawInput('\x7f' * input.length);
    }
    widget.session.sendRawInput('$suggestion\r');
    setState(() => _showSuggestions = false);
  }

  /// Save the currently opened file (for edit or nano)
  Future<void> _saveCurrentFile() async {
    // Check if we're in an editor session
    final buffer = widget.session.terminal.buffer;
    if (buffer.height == 0) return;
    
    final lastLine = buffer.lines[buffer.height - 1].getText();
    
    // Try to detect if we're in an editor by checking common editor patterns
    final isInEditor = RegExp(r'(nano|vi|vim|edit|emacs|code)\s+').hasMatch(lastLine) ||
                      lastLine.contains('-- INSERT --') ||
                      lastLine.contains('Normal mode');
    
    if (isInEditor) {
      // Send Ctrl+S to save in most editors
      widget.session.sendRawInput('\x13'); // Ctrl+S
      debugPrint('Termisol: Save command sent to editor');
    } else {
      debugPrint('Termisol: Not in an editor session');
    }
  }

  /// Show search overlay
  void _showSearchOverlay() {
    // This would integrate with the existing search functionality
    // For now, we'll send Ctrl+F to the terminal which many apps support
    widget.session.sendRawInput('\x06'); // Ctrl+F
    debugPrint('Termisol: Search command sent');
  }

  /// Copy all terminal content
  void _copyAllContent() {
    final buffer = widget.session.terminal.buffer;
    if (buffer.height == 0) return;
    
    final allText = buffer.getText(
      BufferPosition(0, 0),
      BufferPosition(buffer.columns - 1, buffer.height - 1),
    );
    
    Clipboard.setData(ClipboardData(text: allText));
    debugPrint('Termisol: All content copied to clipboard');
  }

  void _sendChainCommand(String command) {
    widget.session.sendRawInput('$command\r');
    setState(() => _showChainSuggestions = false);
  }

  void _handleTapUp(TapUpDetails details, CellOffset cellOffset) {
    if (HardwareKeyboard.instance.isControlPressed) {
      final url = widget.session.getHyperlinkAt(cellOffset.y, cellOffset.x);
      if (url != null) {
        _launchUrl(url);
      }
    }
  }

  void _handleHover(PointerHoverEvent event) {
    if (!HardwareKeyboard.instance.isControlPressed) {
      if (_mouseCursor != SystemMouseCursors.text) {
        setState(() => _mouseCursor = SystemMouseCursors.text);
      }
      return;
    }

    final terminalViewState = _terminalViewKey.currentState;
    if (terminalViewState == null) return;

    try {
      final cellOffset = terminalViewState.renderTerminal.getCellOffset(event.localPosition);
      final url = widget.session.getHyperlinkAt(cellOffset.y, cellOffset.x);
      final newCursor = url != null ? SystemMouseCursors.click : SystemMouseCursors.text;
      if (_mouseCursor != newCursor) {
        setState(() => _mouseCursor = newCursor);
      }
    } on Exception catch (e, stack) {
      debugPrint('hover handling failed: $e\n$stack');
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } on Exception catch (e, stack) {
      debugPrint('launch url failed: $e\n$stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GpuRenderer.wrapWithGpuBoundary(
      child: Container(
        color: PkmTheme.terminalBg.withValues(
          alpha: PkmTheme.bgOpacity.value,
        ),
        child: Stack(
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                    () => _handleCtrlC(),
                const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  control: true,
                  shift: true,
                ): () => _handleCtrlShiftC(),
                const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    () => _clipboard.paste(),
                const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  control: true,
                  shift: true,
                ): () => _clipboard.pasteBracketed(),
              },
              child: MouseRegion(
                onHover: _handleHover,
                cursor: _mouseCursor,
                child: TerminalView(
                  key: _terminalViewKey,
                  widget.session.terminal,
                  controller: widget.session.controller,
                  focusNode: widget.focusNode,
                  autofocus: widget.autofocus,
                  theme: termisolTerminalTheme,
                  scrollController: widget.scrollController,
                  textStyle: TerminalStyle(
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                  ),
                  onKeyEvent: _handleKeyEvent,
                  padding: EdgeInsets.zero,
                  onTapUp: _handleTapUp,
                  onSecondaryTapUp: (details, offset) => _showContextMenu(context, details.globalPosition),
                ),
              ),
            ),
            // Graphics overlay positioned over terminal
            Positioned.fill(
              child: _buildGraphicsOverlay(),
            ),
            if (_isCopyMode)
              Positioned.fill(
                child: CopyModeOverlay(
                  terminal: widget.session.terminal,
                  onClose: () => setState(() => _isCopyMode = false),
                ),
              ),
            // Autocomplete popup
            if (_showSuggestions)
              Positioned(
                left: 8,
                bottom: 8,
                child: Material(
                  color: PkmTheme.popup,
                  borderRadius: BorderRadius.circular(4),
                  elevation: 4,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300, maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            suggestion,
                            style: const TextStyle(
                              color: PkmTheme.text,
                              fontFamily: PkmTheme.fontTerminal,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => _insertSuggestion(suggestion),
                        );
                      },
                    ),
                  ),
                ),
              ),
            // Command chaining chips
            if (_showChainSuggestions)
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                child: Wrap(
                  spacing: 6,
                  children: _chainSuggestions.map((cmd) {
                    return ActionChip(
                      backgroundColor: PkmTheme.tabActiveBg,
                      label: Text(
                        cmd,
                        style: const TextStyle(
                          color: PkmTheme.primary,
                          fontFamily: PkmTheme.fontUi,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () => _sendChainCommand(cmd),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphicsOverlay() {
    final graphicsImages = _graphicsHandler.getCachedImages();
    final imagePositions = _graphicsHandler.imagePositions;
    if (graphicsImages.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: graphicsImages.entries.map((entry) {
        final imageId = entry.key;
        final image = entry.value;

        final charPosition = imagePositions[imageId] ?? Offset.zero;
        final pixelPosition = _convertCharToPixel(charPosition);

        return Positioned(
          left: pixelPosition.dx,
          top: pixelPosition.dy,
          child: FutureBuilder<Uint8List?>(
            future: _graphicsHandler.convertImageForDisplay(imageId),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Image.memory(
                    snapshot.data!,
                    width: image.width.toDouble().clamp(0, 400),
                    height: image.height.toDouble().clamp(0, 300),
                    fit: BoxFit.contain,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        );
      }).toList(),
    );
  }

  Offset _convertCharToPixel(Offset charPosition) {
    final charWidth = _fontSize * 0.6;
    final charHeight = _fontSize * 1.2;

    return Offset(
      charPosition.dx * charWidth,
      charPosition.dy * charHeight,
    );
  }

  Future<void> _handleCtrlC() async {
    if (_clipboard.hasSelection) {
      await _clipboard.copy();
    } else {
      _clipboard.sendSigInt();
    }
  }

  Future<void> _handleCtrlShiftC() async {
    if (_clipboard.hasSelection) {
      await _clipboard.copy();
    } else {
      setState(() => _isCopyMode = true);
    }
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSel = _clipboard.hasSelection;
    final items = <PopupMenuEntry<void>>[];

    if (hasSel) {
      items.add(
        _menuItem(
          label: 'copy',
          onTap: () async => _clipboard.copy(),
        ),
      );
      items.add(
        _menuItem(
          label: 'copy all',
          onTap: () async => _clipboard.copyAll(),
        ),
      );
      if (widget.onSummarize != null) {
        items.add(
          _menuItem(
            label: 'copy as summary',
            onTap: () async => _runSummarize(),
          ),
        );
      }
      items.add(
        _menuItem(
          label: 'translate',
          onTap: () async => _runTranslate(context),
        ),
      );
      items.add(const PopupMenuDivider());
      items.add(
        _menuItem(
          label: 'enter copy mode',
          onTap: () => setState(() => _isCopyMode = true),
        ),
      );
      items.add(const PopupMenuDivider());
      items.add(
        _menuItem(
          label: 'new tab',
          onTap: () => widget.onNewTab?.call(),
        ),
      );
      items.add(
        _menuItem(
          label: 'new window',
          onTap: () => widget.onNewWindow?.call(),
        ),
      );
    } else {
      items.add(
        _menuItem(
          label: 'enter copy mode',
          onTap: () => setState(() => _isCopyMode = true),
        ),
      );
      items.add(
        _menuItem(
          label: 'new tab',
          onTap: () => widget.onNewTab?.call(),
        ),
      );
      items.add(
        _menuItem(
          label: 'new window',
          onTap: () => widget.onNewWindow?.call(),
        ),
      );
      items.add(
        _menuItem(
          label: 'close tab',
          onTap: () => widget.onCloseTab?.call(),
        ),
      );
    }

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: PkmTheme.popup,
      items: items,
    );
  }

  PopupMenuItem<void> _menuItem({
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return PopupMenuItem<void>(
      onTap: onTap,
      enabled: enabled,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? PkmTheme.text : PkmTheme.secondary,
          fontFamily: PkmTheme.fontUi,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _runSummarize() async {
    if (_isSummarizing || widget.onSummarize == null) return;
    setState(() => _isSummarizing = true);

    try {
      final text = _clipboard.selectedText;
      if (text.isEmpty) return;

      final summary = await widget.onSummarize!(text);
      if (summary.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: summary));
        widget.session.terminal.write(
          '\r\n\x1b[36m[summary copied to clipboard]\x1b[0m\r\n',
        );
      }
    } on Exception catch (e, stack) {
      debugPrint('summary failed: $e\n$stack');
      widget.session.terminal.write(
        '\r\n\x1b[31m[summary failed: $e]\x1b[0m\r\n',
      );
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  Future<void> _runTranslate(BuildContext context) async {
    if (_isTranslating) return;
    if (!_deepL.isAvailable) {
      await _deepL.promptForApiKey(context);
      if (!_deepL.isAvailable) return;
    }
    setState(() => _isTranslating = true);

    try {
      final text = _clipboard.selectedText;
      if (text.isEmpty) return;

      final translation = await _deepL.translateToEnglish(text);
      if (translation != null && translation.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: translation));
        widget.session.terminal.write('\r\n');
        widget.session.terminal.write(
          '\x1b[33m[translated]\x1b[0m $translation\r\n',
        );
      } else {
        widget.session.terminal.write(
          '\r\n\x1b[31m[translation failed]\x1b[0m\r\n',
        );
      }
    } on Exception catch (e, stack) {
      debugPrint('translation error: $e\n$stack');
      widget.session.terminal.write(
        '\r\n\x1b[31m[translation error: $e]\x1b[0m\r\n',
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }
}
