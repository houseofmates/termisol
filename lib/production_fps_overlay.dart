import 'package:flutter/material.dart';
import '../core/performance_enforcer.dart';

/// Production FPS overlay widget
class ProductionFpsOverlay extends StatelessWidget {
  final PerformanceEnforcer enforcer;
  
  const ProductionFpsOverlay({
    super.key,
    required this.enforcer,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${enforcer.currentFps.toStringAsFixed(1)} FPS',
        style: const TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
