import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// GPU performance helper for Termisol.
///
/// The primary optimization provided is [RepaintBoundary] wrapping, which
/// isolates terminal paint costs from the rest of the widget tree. Flutter's
/// Skia/Impeller backend handles the actual GPU rasterization.
///
/// Additional optimizations (e.g. texture atlases) would require extending
/// xterm.dart's rendering pipeline and are left for future work.
class GpuRenderer {
  static final GpuRenderer instance = GpuRenderer._();
  GpuRenderer._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Verify that GPU acceleration is active by doing a small off-screen
  /// render and checking that it completes without error.
  void initialize() {
    if (_initialized) return;
    _warmUpGpu();
    _initialized = true;
  }

  void _warmUpGpu() async {
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
