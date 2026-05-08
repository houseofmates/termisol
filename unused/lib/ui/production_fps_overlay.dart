import 'package:flutter/material.dart';
import '../core/performance_enforcer.dart';
import '../core/production_gpu_renderer.dart';
import '../core/sub_16ms_latency_optimizer.dart';
import '../core/adaptive_frame_pacer.dart';
import '../config/pkm_theme.dart';

/// Production FPS Overlay with comprehensive performance metrics
/// 
/// Displays:
/// - Real-time FPS and frame time
/// - GPU acceleration status
/// - Latency optimization metrics
/// - Adaptive frame pacing info
/// - Memory usage indicators
class ProductionFpsOverlay extends StatelessWidget {
  final PerformanceEnforcer enforcer;
  final ProductionGpuRenderer gpuRenderer;
  final Sub16msLatencyOptimizer latencyOptimizer;
  final AdaptiveFramePacer framePacer;

  const ProductionFpsOverlay({
    super.key,
    required this.enforcer,
    required this.gpuRenderer,
    required this.latencyOptimizer,
    required this.framePacer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PkmTheme.popup,
        border: Border.all(
          color: _getStatusColor().withValues(alpha: 0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrimaryMetrics(),
          const SizedBox(height: 4),
          _buildSecondaryMetrics(),
          const SizedBox(height: 4),
          _buildOptimizationStatus(),
        ],
      ),
    );
  }

  Widget _buildPrimaryMetrics() {
    final fps = enforcer.currentFps.toStringAsFixed(1);
    final frameTime = enforcer.currentFrameTime.toStringAsFixed(2);
    final color = _getStatusColor();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _getStatusIcon(),
          size: 12,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          '$fps fps | $frameTime ms',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontFamily: PkmTheme.fontTerminal,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryMetrics() {
    final gpuFps = gpuRenderer.averageFrameTime > 0 
        ? (1000.0 / gpuRenderer.averageFrameTime).toStringAsFixed(1)
        : '0.0';
    final latency = latencyOptimizer.averageInputLatency.toStringAsFixed(1);
    final targetFps = latencyOptimizer.currentTargetFps.toStringAsFixed(0);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GPU: $gpuFps fps | Latency: ${latency}ms',
          style: TextStyle(
            color: PkmTheme.secondary,
            fontSize: 9,
            fontFamily: PkmTheme.fontTerminal,
          ),
        ),
        Text(
          'Target: ${targetFps} fps | Adaptive: ${latencyOptimizer.adaptiveMode ? "ON" : "OFF"}',
          style: TextStyle(
            color: PkmTheme.secondary,
            fontSize: 9,
            fontFamily: PkmTheme.fontTerminal,
          ),
        ),
      ],
    );
  }

  Widget _buildOptimizationStatus() {
    final metrics = gpuRenderer.performanceMetrics;
    final isHardwareAccelerated = metrics['hardware_accelerated'] as bool;
    final dirtyRegions = metrics['dirty_regions'] as int;
    final glyphCache = metrics['glyph_cache_size'] as int;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // GPU acceleration status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: isHardwareAccelerated 
                ? PkmTheme.primary.withValues(alpha: 0.2)
                : PkmTheme.statusDisconnected.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            isHardwareAccelerated ? 'GPU' : 'CPU',
            style: TextStyle(
              color: isHardwareAccelerated ? PkmTheme.primary : PkmTheme.statusDisconnected,
              fontSize: 8,
              fontFamily: PkmTheme.fontTerminal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        
        const SizedBox(width: 4),
        
        // Dirty regions indicator
        if (dirtyRegions > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: PkmTheme.secondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'DR:$dirtyRegions',
              style: TextStyle(
                color: PkmTheme.secondary,
                fontSize: 8,
                fontFamily: PkmTheme.fontTerminal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        
        const SizedBox(width: 4),
        
        // Glyph cache indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: PkmTheme.text.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            'GC:$glyphCache',
            style: TextStyle(
              color: PkmTheme.text,
              fontSize: 8,
              fontFamily: PkmTheme.fontTerminal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    final frameTime = enforcer.currentFrameTime;
    
    if (frameTime <= 16.0) {
      return PkmTheme.primary; // Green - excellent
    } else if (frameTime <= 33.0) {
      return PkmTheme.secondary; // Yellow - acceptable
    } else {
      return PkmTheme.statusDisconnected; // Red - poor
    }
  }

  IconData _getStatusIcon() {
    final frameTime = enforcer.currentFrameTime;
    
    if (frameTime <= 16.0) {
      return Icons.check_circle; // Excellent
    } else if (frameTime <= 33.0) {
      return Icons.warning; // Acceptable
    } else {
      return Icons.error; // Poor
    }
  }
}
