import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../core/deep_l_service.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';

/// gnome terminal color palette extracted from the user's screenshot.
const termisolTerminalTheme = TerminalTheme(
  cursor: Color(0xFFFFAA00),
  selection: Color(0xFF0A0E1A),
  foreground: Color(0xFFFFD6A5),
  background: Color(0xFF000000),
  black: Color(0xFF000000),
  red: Color(0xFFFF0000),
  green: Color(0xFF00CC00),
  yellow: Color(0xFFCCCC00),
  blue: Color(0xFF0000FF),
  magenta: Color(0xFFFF00FF),
  cyan: Color(0xFF00CCCC),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF808080),
  brightRed: Color(0xFFFF0000),
  brightGreen: Color(0xFF00FF00),
  brightYellow: Color(0xFFFFFF00),
  brightBlue: Color(0xFF6666FF),
  brightMagenta: Color(0xFFFF00FF),
  brightCyan: Color(0xFF00FFFF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

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
  final _deepL = DeepLTranslationService();
  bool _isSummarizing = false;
  bool _isTranslating = false;
  double _fontSize = _defaultTerminalFontSize;

  @override
  void initState() {
    super.initState();
    _deepL.initialize();
    _clipboard = TerminalClipboardManager(
      widget.session.terminal,
      widget.session.controller,
    );
    widget.session.addListener(_onSessionChanged);
    _loadFontSize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode?.requestFocus();
    });
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('termisol_font_size');
    if (saved != null && mounted) {
      setState(() => _fontSize = saved.clamp(_minFontSize, _maxFontSize));
    }
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('termisol_font_size', _fontSize);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
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
        color: PkmTheme.terminalBg,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                () => _handleCtrlC(),
            const SingleActivator(
              LogicalKeyboardKey.keyC,
              control: true,
              shift: true,
            ): () => _clipboard.sendSigInt(),
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
              fontFamily: 'DroidSansMono',
              fontSize: _fontSize,
              height: 1.2,
            ),
            onKeyEvent: _handleKeyEvent,
            padding: EdgeInsets.zero,
            onSecondaryTapUp: (details, offset) => _showContextMenu(context, details.globalPosition),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCtrlC() async {
    if (_clipboard.hasSelection) {
      await _clipboard.copy();
    } else {
      _clipboard.sendSigInt();
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
