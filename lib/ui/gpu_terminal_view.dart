import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show TerminalView, TerminalStyle, TerminalTheme, TerminalController;
import '../core/terminal_session.dart';
import '../core/gpu_renderer.dart';
import '../config/pkm_theme.dart';

/// GPU-accelerated terminal view that replaces the stock xterm renderer with
/// [GpuTerminalPainter].
///
/// All input, scrolling, and selection behaviour is inherited from the
/// underlying [TerminalView]; only the rasterisation path is swapped.
class GpuTerminalView extends StatelessWidget {
  final TerminalSession session;
  final TerminalTheme theme;
  final TerminalStyle textStyle;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTapUp;

  const GpuTerminalView({
    super.key,
    required this.session,
    required this.theme,
    required this.textStyle,
    this.focusNode,
    this.autofocus = true,
    this.onTapUp,
  });

  @override
  Widget build(BuildContext context) {
    final painter = GpuRenderer.instance.createPainter(
      theme: theme,
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    );

    return GpuRenderer.wrapWithGpuBoundary(
      child: TerminalView(
        session.terminal,
        controller: session.controller,
        theme: theme,
        textStyle: textStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        cursorType: TerminalCursorType.block,
        alwaysShowCursor: false,
        backgroundOpacity: PkmTheme.bgOpacity.value,
        painter: painter,
      ),
    );
  }
}
