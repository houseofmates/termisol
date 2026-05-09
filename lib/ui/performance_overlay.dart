import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';
import '../core/termisol_core_integration.dart';

/// a small overlay that shows fps and frame timing in the top-right corner.
class TermisolPerformanceOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const TermisolPerformanceOverlay({
    super.key,
    required this.onDismiss,
  });

  @override
  State<TermisolPerformanceOverlay> createState() => _TermisolPerformanceOverlayState();
}

class _TermisolPerformanceOverlayState extends State<TermisolPerformanceOverlay> {
  @override
  void initState() {
    super.initState();
    TermisolCoreIntegration.instance.frameMetrics.addListener(_onMetricsChanged);
  }

  @override
  void dispose() {
    TermisolCoreIntegration.instance.frameMetrics.removeListener(_onMetricsChanged);
    super.dispose();
  }

  void _onMetricsChanged() {
    if (mounted) setState(() {});
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 30) return Colors.yellow;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TermisolCoreIntegration.instance.frameMetrics.value;
    final color = _getFpsColor(metrics.fps);

    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: PkmTheme.popup.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'FPS: ${metrics.fps.toStringAsFixed(0)} | frame: ${metrics.frameTimeMs.toStringAsFixed(1)}ms | build: ${metrics.buildTimeMs.toStringAsFixed(1)}ms | raster: ${metrics.rasterTimeMs.toStringAsFixed(1)}ms',
            style: TextStyle(
              color: color,
              fontFamily: PkmTheme.fontTerminal,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
