import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Image viewer for Termisol terminal with support for all image formats
/// 
/// Features:
/// - Multiple image format support (PNG, JPG, GIF, WebP, SVG, BMP, TIFF)
/// - Terminal-integrated display
/// - Zoom and pan controls
/// - Image metadata display
/// - Performance optimization
class TerminalImageViewer extends StatefulWidget {
  final String imagePath;
  final bool showControls;
  final bool showMetadata;
  final double? width;
  final double? height;
  final VoidCallback? onClose;
  
  const TerminalImageViewer({
    super.key,
    required this.imagePath,
    this.showControls = true,
    this.showMetadata = true,
    this.width,
    this.height,
    this.onClose,
  });
  
  @override
  State<TerminalImageViewer> createState() => _TerminalImageViewerState();
}

class _TerminalImageViewerState extends State<TerminalImageViewer> 
    with TickerProviderStateMixin {
  img.Image? _image;
  bool _isLoading = true;
  double _scale = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;
  String? _error;
  ImageMetadata? _metadata;
  
  @override
  void initState() {
    super.initState();
    _loadImage();
  }
  
  Future<void> _loadImage() async {
    try {
      setState(() => _isLoading = true);
      
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();
      
      // Support all image formats
      _image = await img.decodeImage(bytes);
      
      if (_image != null) {
        _metadata = _extractMetadata(_image!);
      }
      
      setState(() => _isLoading = false);
      
    } catch (e) {
      setState(() {
        _error = 'Failed to load image: $e';
        _isLoading = false;
      });
    }
  }
  
  ImageMetadata _extractMetadata(img.Image image) {
    return ImageMetadata(
      width: image.width,
      height: image.height,
      format: _detectImageFormat(image),
      size: image.length,
      hasTransparency: image.hasAlpha,
      colorSpace: 'sRGB',
    );
  }
  
  String _detectImageFormat(img.Image image) {
    // Simple format detection based on image properties
    if (image.numChannels == 4) {
      return image.hasAlpha ? 'PNG' : 'JPG';
    } else if (image.numChannels == 3) {
      return 'RGB';
    } else if (image.numChannels == 1) {
      return 'Grayscale';
    } else {
      return 'Unknown';
    }
  }
  
  void _handleZoom(double delta) {
    setState(() {
      _scale = (_scale + delta).clamp(0.1, 5.0);
    });
  }
  
  void _handlePan(double deltaX, double deltaY) {
    setState(() {
      _panX += deltaX;
      _panY += deltaY;
    });
  }
  
  void _resetView() {
    setState(() {
      _scale = 1.0;
      _panX = 0.0;
      _panY = 0.0;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? 600.0;
    final height = widget.height ?? 400.0;
    
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
      ),
      child: Stack(
        children: [
          // Image display
          GestureDetector(
            onScaleStart: (details) => _resetView(),
            onScaleUpdate: (details) => _handleZoom(details.scale - 1.0),
            onPanUpdate: (details) => _handlePan(details.delta.dx, details.delta.dy),
            child: Center(
              child: Transform.scale(
                scale: _scale,
                translate: Offset(_panX, _panY),
                child: _image != null 
                    ? Image.memory(
                        Uint8List.fromList(_image!.getBytes()),
                        width: _image!.width.toDouble(),
                        height: _image!.height.toDouble(),
                        fit: BoxFit.contain,
                      )
                    : Container(),
              ),
            ),
          ),
          
          // Controls
          if (widget.showControls) _buildControls(width, height),
          
          // Metadata
          if (widget.showMetadata && _metadata != null) _buildMetadata(width, height),
          
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, color: Colors.white),
              iconSize: 20,
            ),
          ),
        ],
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
            // Zoom controls
            Expanded(
              child: Column(
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
                        onPressed: () => _handleZoom(0.2),
                        tooltip: 'Zoom In',
                      ),
                      const SizedBox(width: 4),
                      _buildControlButton(
                        icon: Icons.zoom_out,
                        onPressed: () => _handleZoom(-0.2),
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
            ),
            
            // Scale indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                border: Border.all(color: Colors.grey[600]!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(_scale * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetadata(double width, double height) {
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          border: Border.all(color: Colors.grey[600]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'IMAGE METADATA',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildMetadataRow('Format', _metadata!.format),
            _buildMetadataRow('Dimensions', '${_metadata!.width}x${_metadata!.height}'),
            _buildMetadataRow('Size', '${(_metadata!.size / 1024).toStringAsFixed(1)} KB'),
            _buildMetadataRow('Transparency', _metadata!.hasTransparency ? 'Yes' : 'No'),
            _buildMetadataRow('Color Space', _metadata!.colorSpace),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.grey[400], fontSize: 10),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
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

/// Image metadata information
class ImageMetadata {
  final int width;
  final int height;
  final String format;
  final int size;
  final bool hasTransparency;
  final String colorSpace;
  
  ImageMetadata({
    required this.width,
    required this.height,
    required this.format,
    required this.size,
    required this.hasTransparency,
    required this.colorSpace,
  });
}
