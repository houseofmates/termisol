import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show TerminalStyle, TerminalTheme, TextScaler;

import 'gpu/gpu_terminal_painter.dart';

/// Coordinates GPU-accelerated terminal rendering for Termisol.
///
/// The renderer uses a [GpuTerminalPainter] which batches background fills
/// into single [Vertices] calls and caches static lines as [Picture] objects
/// for near-zero-cost replay on subsequent frames.
class GpuRenderer {
  static final GpuRenderer instance = GpuRenderer._();
  GpuRenderer._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  GpuTerminalPainter? _painter;

  /// Warm up the GPU backend and mark the renderer ready.
  void initialize() {
    if (_initialized) return;
    _warmUpGpu();
    _initialized = true;
  }

  Future<void> _warmUpGpu() async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = Colors.white,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      image.dispose();
      picture.dispose();
    } catch (e, stack) {
      debugPrint('[gpu] warm-up failed: $e\n$stack');
    }
  }

  /// Creates or updates a [GpuTerminalPainter] configured with the given
  /// [theme], [textStyle] and [textScaler].
  GpuTerminalPainter createPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    TextScaler? textScaler,
  }) {
    final scaler = textScaler ?? TextScaler.noScaling;
    if (_painter == null) {
      _painter = GpuTerminalPainter(
        theme: theme,
        textStyle: textStyle,
        textScaler: scaler,
      );
    } else {
      _painter!.theme = theme;
      _painter!.textStyle = textStyle;
      _painter!.textScaler = scaler;
    }
    return _painter!;
  }

  /// Dispose the cached painter and release native picture resources.
  void dispose() {
    _painter?.clearFontCache();
    _painter = null;
  }

  /// Wrap a widget in a [RepaintBoundary] to isolate its paint cost.
  static Widget wrapWithGpuBoundary({required Widget child}) {
    return RepaintBoundary(child: child);
  }
}

/// Simple background painter for custom terminal backgrounds.
class TerminalBackgroundPainter extends CustomPainter {
  final Color color;

  TerminalBackgroundPainter({this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant TerminalBackgroundPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
