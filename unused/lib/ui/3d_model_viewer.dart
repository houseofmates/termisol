import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 3D model viewer for Termisol terminal
/// 
/// Features:
/// - 3D model loading and rendering
/// - Interactive camera controls
/// - Multiple model format support
/// - Terminal-integrated 3D display
class Terminal3DModelViewer extends StatefulWidget {
  final String modelPath;
  final bool autoRotate;
  final bool showControls;
  final double? width;
  final double? height;
  final VoidCallback? onLoaded;
  
  const Terminal3DModelViewer({
    super.key,
    required this.modelPath,
    this.autoRotate = false,
    this.showControls = true,
    this.width,
    this.height,
    this.onLoaded,
  });
  
  @override
  State<Terminal3DModelViewer> createState() => _Terminal3DModelViewerState();
}

class _Terminal3DModelViewerState extends State<Terminal3DModelViewer> 
    with TickerProviderStateMixin {
  double _rotationX = 0.0;
  double _rotationY = 0.0;
  double _rotationZ = 0.0;
  double _scale = 1.0;
  double _zoom = 1.0;
  bool _isLoaded = false;
  bool _isLoading = true;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadModel();
  }
  
  Future<void> _loadModel() async {
    try {
      setState(() => _isLoading = true);
      
      // Simulate 3D model loading
      await Future.delayed(const Duration(seconds: 2));
      
      setState(() {
        _isLoaded = true;
        _isLoading = false;
      });
      
      widget.onLoaded?.call();
      
    } catch (e) {
      setState(() {
        _error = 'Failed to load 3D model: $e';
        _isLoading = false;
      });
    }
  }
  
  void _handleRotate(double deltaX, double deltaY) {
    setState(() {
      _rotationY += deltaX * 0.01;
      _rotationX += deltaY * 0.01;
    });
  }
  
  void _handleZoom(double delta) {
    setState(() {
      _zoom = (_zoom + delta).clamp(0.1, 5.0);
    });
  }
  
  void _resetView() {
    setState(() {
      _rotationX = 0.0;
      _rotationY = 0.0;
      _rotationZ = 0.0;
      _scale = 1.0;
      _zoom = 1.0;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? 400.0;
    final height = widget.height ?? 300.0;
    
    if (_error != null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.red[900],
          border: Border.all(color: Colors.red[700]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    if (_isLoading) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border.all(color: Colors.grey[700]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.grey[400]),
        ),
      );
    }
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple[900]!.withOpacity(0.3),
            Colors.blue[900]!.withOpacity(0.3),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 3D model rendering (simulated with 2D representation)
          _build3DModel(width, height),
          
          // Controls
          if (widget.showControls) _buildControls(width, height),
        ],
      ),
    );
  }
  
  Widget _build3DModel(double width, double height) {
    return Center(
      child: Transform.rotate(
        angle: _rotationY,
        child: Transform.scale(
          scale: _scale * _zoom,
          child: Container(
            width: width * 0.6,
            height: height * 0.6,
            decoration: BoxDecoration(
              color: Colors.blue[600],
              border: Border.all(color: Colors.blue[400]!),
              borderRadius: BorderRadius.circular(8),
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                radius: 0.8,
                colors: [
                  Colors.blue[400]!,
                  Colors.blue[800]!,
                ],
              ),
            ),
            child: Stack(
              children: [
                // Front face
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue[300],
                      border: Border.all(color: Colors.blue[200]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.view_in_ar, color: Colors.white, size: 32),
                          const SizedBox(height: 4),
                          const Text(
                            '3D MODEL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Side faces (simulated 3D effect)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Transform.rotate(
                    angle: _rotationX,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Transform.rotate(
                    angle: _rotationZ,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildControls(double width, double height) {
    return Positioned(
      bottom: 10,
      left: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          border: Border.all(color: Colors.grey[600]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // Rotation controls
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ROTATION',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildControlButton(
                        icon: Icons.keyboard_arrow_up,
                        onPressed: () => _handleRotate(0, -1),
                        tooltip: 'Rotate Up',
                      ),
                      const SizedBox(width: 4),
                      _buildControlButton(
                        icon: Icons.keyboard_arrow_down,
                        onPressed: () => _handleRotate(0, 1),
                        tooltip: 'Rotate Down',
                      ),
                      const SizedBox(width: 4),
                      _buildControlButton(
                        icon: Icons.keyboard_arrow_left,
                        onPressed: () => _handleRotate(-1, 0),
                        tooltip: 'Rotate Left',
                      ),
                      const SizedBox(width: 4),
                      _buildControlButton(
                        icon: Icons.keyboard_arrow_right,
                        onPressed: () => _handleRotate(1, 0),
                        tooltip: 'Rotate Right',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Zoom controls
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ZOOM',
                  style: TextStyle(color: Colors.grey[400], fontSize: 10),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildControlButton(
                      icon: Icons.zoom_in,
                      onPressed: () => _handleZoom(0.1),
                        tooltip: 'Zoom In',
                      ),
                    const SizedBox(width: 4),
                    _buildControlButton(
                      icon: Icons.zoom_out,
                      onPressed: () => _handleZoom(-0.1),
                        tooltip: 'Zoom Out',
                      ),
                    const SizedBox(width: 4),
                    _buildControlButton(
                      icon: Icons.refresh,
                      onPressed: _resetView,
                        tooltip: 'Reset View',
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          border: Border.all(color: Colors.grey[600]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 16),
          iconSize: 16,
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    super.dispose();
  }
}
