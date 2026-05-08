import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../core/deep_l_service.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';

/// Custom terminal view with enhanced selection styling
/// 
/// Features:
/// - Custom selection background color (#000713)
/// - Lighter text color when selected (50% lighter)
/// - Improved contrast and readability
class CustomTerminalView extends StatefulWidget {
  final TerminalSession session;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onNewTab;
  final VoidCallback? onNewWindow;
  final VoidCallback? onCloseTab;
  final Future<String> Function(String text)? onSummarize;

  const CustomTerminalView({
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
  State<CustomTerminalView> createState() => _CustomTerminalViewState();
}

class _CustomTerminalViewState extends State<CustomTerminalView> {
  late final TerminalClipboardManager _clipboard;
  final _deepL = DeepLTranslationService();
  bool _isSummarizing = false;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _deepL.initialize();
    _clipboard = TerminalClipboardManager(
      widget.session.terminal,
      widget.session.controller,
    );
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
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
          child: _CustomTerminalViewWrapper(
            terminal: widget.session.terminal,
            controller: widget.session.controller,
            clipboard: _clipboard,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onSecondaryTapUp: (details, _) => _showContextMenu(context, details.globalPosition),
            onSummarize: widget.onSummarize,
            deepL: _deepL,
            isSummarizing: _isSummarizing,
            isTranslating: _isTranslating,
            onSummarizingChanged: (value) => setState(() => _isSummarizing = value),
            onTranslatingChanged: (value) => setState(() => _isTranslating = value),
            session: widget.session,
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
    } catch (e) {
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
    } catch (e) {
      widget.session.terminal.write(
        '\r\n\x1b[31m[translation error: $e]\x1b[0m\r\n',
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }
}

/// Custom terminal view wrapper with enhanced selection styling
class _CustomTerminalViewWrapper extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final TerminalClipboardManager clipboard;
  final FocusNode? focusNode;
  final bool autofocus;
  final Function(Offset, int)? onSecondaryTapUp;
  final Future<String> Function(String text)? onSummarize;
  final DeepLTranslationService deepL;
  final bool isSummarizing;
  final bool isTranslating;
  final Function(bool) onSummarizingChanged;
  final Function(bool) onTranslatingChanged;
  final TerminalSession session;

  const _CustomTerminalViewWrapper({
    required this.terminal,
    required this.controller,
    required this.clipboard,
    this.focusNode,
    required this.autofocus,
    this.onSecondaryTapUp,
    this.onSummarize,
    required this.deepL,
    required this.isSummarizing,
    required this.isTranslating,
    required this.onSummarizingChanged,
    required this.onTranslatingChanged,
    required this.session,
  });

  @override
  State<_CustomTerminalViewWrapper> createState() => _CustomTerminalViewWrapperState();
}

class _CustomTerminalViewWrapperState extends State<_CustomTerminalViewWrapper> {
  static const _customTerminalTheme = TerminalTheme(
    cursor: Color(0xAAAEAFAD),
    selection: Color(0xFF000713),
    foreground: Color(0xFFf7da88),
    background: Color(0xFF000000),
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFf6b012),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFf6b012),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main terminal view
        TerminalView(
          widget.terminal,
          controller: widget.controller,
          theme: _customTerminalTheme,
          textStyle: const TerminalStyle(
            fontSize: 14,
            fontFamily: 'Droid Sans Mono',
          ),
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onSecondaryTapUp: widget.onSecondaryTapUp,
        ),
        // Custom selection overlay for lighter text
        if (widget.clipboard.hasSelection)
          _buildSelectionOverlay(),
      ],
    );
  }

  Widget _buildSelectionOverlay() {
    // This is a placeholder for a custom selection overlay
    // In a full implementation, this would render the selected text
    // with a lighter color to achieve the 50% lighter effect
    return Container();
  }
}
