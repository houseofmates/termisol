import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../core/deep_l_service.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';
import 'damage_aware_terminal_renderer.dart';

/// xterm terminal theme using Termisol brand yellow (#f6b012) instead of
/// the default greenish-yellow (#e5e510).
const termisolTerminalTheme = TerminalTheme(
  cursor: Color(0xAAAEAFAD),
  selection: Color(0xFF000713),
  foreground: Color(0xFFf7da88),
  background: Color(0xFF000000),
  black: Color(0xFF000000),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFABB2BF),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

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
          child: DamageAwareTerminalRenderer(
            terminal: widget.session.terminal,
            controller: widget.session.controller,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onSecondaryTapUp: (details, _) => _showContextMenu(context, details.globalPosition),
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
        // Write the translated text to the terminal so it appears at the
        // cursor, effectively "replacing" the selection with the English
        // version for the user to use.
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
