import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../core/deep_l_service.dart';
import '../core/graphics_protocol_handler.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';
import 'copy_mode_overlay.dart';

/// Active terminal theme based on the current [PkmTheme.themeMode].
TerminalTheme get termisolTerminalTheme => PkmTheme.activeTerminalTheme;

const _defaultTerminalFontSize = 14.0;
const _minFontSize = 8.0;
const _maxFontSize = 32.0;

/// gpu-optimized terminal widget for termisol.
class TermisolTerminalView extends StatefulWidget {
  final TerminalSession session;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onNewTab;
  final VoidCallback? onNewWindow;
  final VoidCallback? onCloseTab;
  final Future<String> Function(String text)? onSummarize;

  const TermisolTerminalView({
    super.key,
    required this.session,
    this.autofocus = true,
    this.focusNode,
    this.onNewTab,
    this.onNewWindow,
    this.onCloseTab,
    this.onSummarize,
  });

  @override
  State<TermisolTerminalView> createState() => _TermisolTerminalViewState();
}

class _TermisolTerminalViewState extends State<TermisolTerminalView> {
  late final TerminalClipboardManager _clipboard;
  late final GraphicsProtocolHandler _graphicsHandler;
  final _deepL = DeepLTranslationService();
  bool _isSummarizing = false;
  bool _isTranslating = false;
  bool _isCopyMode = false;
  double _fontSize = _defaultTerminalFontSize;
  String _fontFamily = 'DroidSansMono';

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
    widget.session.addListener(_onSessionChanged);
    _loadTerminalStyle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode?.requestFocus();
    });
  }

  @override
  void dispose() {
    PkmTheme.themeMode.removeListener(_onThemeChanged);
    PkmTheme.bgOpacity.removeListener(_onBgOpacityChanged);
    widget.session.removeListener(_onSessionChanged);
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
    _saveFontSize();
  }

  void _zoomOut() {
    setState(() {
      _fontSize = (_fontSize - 1.0).clamp(_minFontSize, _maxFontSize);
    });
    _saveFontSize();
  }

  void _zoomReset() {
    setState(() {
      _fontSize = _defaultTerminalFontSize;
    });
    _saveFontSize();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // zoom: ctrl + (or ctrl shift + on us layouts)
    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
         event.logicalKey == LogicalKeyboardKey.numpadAdd ||
         (shift && event.logicalKey == LogicalKeyboardKey.equal))) {
      _zoomIn();
      return KeyEventResult.handled;
    }

    // zoom out: ctrl -
    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
         event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _zoomOut();
      return KeyEventResult.handled;
    }

    // reset zoom: ctrl 0
    if (ctrl &&
        !shift &&
        (event.logicalKey == LogicalKeyboardKey.digit0 ||
         event.logicalKey == LogicalKeyboardKey.numpad0)) {
      _zoomReset();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
              child: TerminalView(
                widget.session.terminal,
                controller: widget.session.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                theme: termisolTerminalTheme,
                textStyle: TerminalStyle(
                  fontFamily: _fontFamily,
                  fontSize: _fontSize,
                  height: 1.2,
                ),
                onKeyEvent: _handleKeyEvent,
                padding: EdgeInsets.zero,
                onSecondaryTapUp: (details, offset) => _showContextMenu(context, details.globalPosition),
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
          ],
        ),
      ),
    );
  }

  Widget _buildGraphicsOverlay() {
    // Build overlay for inline graphics from GraphicsProtocolHandler
    final graphicsImages = _graphicsHandler.getCachedImages();
    final imagePositions = _graphicsHandler.imagePositions;
    if (graphicsImages.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: graphicsImages.entries.map((entry) {
        final imageId = entry.key;
        final image = entry.value;

        // Get stored position in characters
        final charPosition = imagePositions[imageId] ?? Offset.zero;

        // Convert character position to pixel position
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
    // Convert character coordinates to pixel coordinates
    // Assuming monospace font, approximate character width as fontSize * 0.6
    final charWidth = _fontSize * 0.6;
    final charHeight = _fontSize * 1.2; // Line height

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
          onTap: () async => _runTranslate(),
          enabled: _deepL.isAvailable,
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
    } catch (e, stack) {
      debugPrint('summary failed: $e\n$stack');
      widget.session.terminal.write(
        '\r\n\x1b[31m[summary failed: $e]\x1b[0m\r\n',
      );
    } finally {
      if (mounted) setState(() => _isSummarizing = false);
    }
  }

  Future<void> _runTranslate() async {
    if (_isTranslating) return;
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
    } catch (e, stack) {
      debugPrint('translation error: $e\n$stack');
      widget.session.terminal.write(
        '\r\n\x1b[31m[translation error: $e]\x1b[0m\r\n',
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }
}
