import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart';

/// 3D Model Viewer for inline terminal 3D model display
/// Supports OBJ, GLB, GLTF formats
class Model3DViewer extends StatefulWidget {
  final String modelPath;
  final double? width;
  final double? height;
  final bool autoRotate;
  final Color backgroundColor;
  final VoidCallback? onClose;

  const Model3DViewer({
    super.key,
    required this.modelPath,
    this.width,
    this.height = 300,
    this.autoRotate = true,
    this.backgroundColor = Colors.black,
    this.onClose,
  });

  @override
  State<Model3DViewer> createState() => _Model3DViewerState();
}

class _Model3DViewerState extends State<Model3DViewer> {
  late Scene _scene;
  late Object _model;
  bool _isLoading = true;
  double _rotationX = 0.0;
  double _rotationY = 0.0;
  double _zoom = 1.0;
  Offset? _lastPanPosition;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      _scene = Scene(
        ambientColor: Colors.grey[800]!,
        backgroundColor: widget.backgroundColor,
      );

      // Load 3D model from provided path
      _model = Object(
        fileName: widget.modelPath,
        backfaceCulling: true,
        lighting: true,
      );

      _scene.world.add(_model);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Failed to load 3D model: $e');
    }
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_lastPanPosition != null) {
      final delta = details.localPosition - _lastPanPosition!;
      setState(() {
        _rotationY += delta.dx * 0.01;
        _rotationX += delta.dy * 0.01;
      });
    }
    _lastPanPosition = details.localPosition;
  }

  void _handlePanEnd(DragEndDetails details) {
    _lastPanPosition = null;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _zoom = (_zoom * details.scale).clamp(0.1, 5.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? 300,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                'Loading 3D model...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? 300,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 3D View
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onPanUpdate: _handlePanUpdate,
              onPanEnd: _handlePanEnd,
              onScaleUpdate: _handleScaleUpdate,
              child: Cube(
                scene: _scene,
                onSceneCreated: (Scene scene) {
                  scene.camera.position.z = 5.0 / _zoom;
                  scene.camera.position.y = 2.0;
                  scene.camera.target.y = 1.0;
                },
              ),
            ),
          ),
          
          // Controls overlay
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                // Close button
                if (widget.onClose != null)
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                
                const SizedBox(height: 8),
                
                // Auto-rotate toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      // Toggle auto-rotation
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.rotate_right,
                      color: widget.autoRotate ? Colors.blue : Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Instructions
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Drag to rotate • Pinch to zoom',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
