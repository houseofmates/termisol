import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'sixel_decoder.dart';
import 'kitty_image_cache.dart';

/// Unified graphics protocol handler for terminal multimedia.
///
/// Integrates SIXEL, Kitty, and iTerm2 graphics protocols with the terminal
/// grid system. Images occupy cell space and scroll with terminal content.
class GraphicsProtocolHandler {
  final SixelDecoder _sixelDecoder = SixelDecoder();
  final KittyImageCache _kittyCache = KittyImageCache();
  
  // Terminal grid integration
  final List<GridImage> _gridImages = [];
  int _terminalWidth = 80;
  int _terminalHeight = 24;
  double _cellWidth = 8.0;
  double _cellHeight = 16.0;

  /// Handle incoming graphics protocol sequence.
  Future<List<GraphicsAction>> handleSequence(String sequence) async {
    final actions = <GraphicsAction>[];

    try {
      if (sequence.contains('\x1bP')) {
        // SIXEL sequence
        final sixelImage = await _sixelDecoder.decodeSixel(sequence);
        if (sixelImage != null) {
          final gridImage = _createGridImage(sixelImage, sequence);
          _gridImages.add(gridImage);
          actions.add(GraphicsAction.displayImage(gridImage));
        }
      } else if (sequence.contains('\x1b_G')) {
        // Kitty graphics sequence
        final kittyActions = await _kittyCache.processSequence(sequence);
        for (final action in kittyActions) {
          if (action is KittyDisplayAction) {
            final gridImage = _createGridImageFromKitty(action.image, action.params);
            _gridImages.add(gridImage);
            actions.add(GraphicsAction.displayImage(gridImage));
          } else if (action is KittyDeleteAction) {
            _removeImageById(action.imageId);
            actions.add(GraphicsAction.deleteImage(action.imageId));
          }
        }
      } else if (sequence.contains('\x1b]1337')) {
        // iTerm2 inline image
        final itermImage = await _decodeITerm2Image(sequence);
        if (itermImage != null) {
          final gridImage = _createGridImage(itermImage, sequence);
          _gridImages.add(gridImage);
          actions.add(GraphicsAction.displayImage(gridImage));
        }
      }
    } catch (e) {
      debugPrint('[Graphics] Protocol handling failed: $e');
    }

    return actions;
  }

  /// Decode iTerm2 inline image.
  Future<ui.Image?> _decodeITerm2Image(String sequence) async {
    try {
      // Parse iTerm2 sequence: \x1b]1337;File=name=...;size=...:[base64]\x07
      final match = RegExp(r'\x1b\]1337;File=([^:]+):([^\x07]+)\x07').firstMatch(sequence);
      if (match == null) return null;

      final params = match.group(1)!;
      final base64Data = match.group(2)!;

      // Parse parameters
      final paramMap = <String, String>{};
      for (final param in params.split(';')) {
        final parts = param.split('=');
        if (parts.length == 2) {
          paramMap[parts[0]] = parts[1];
        }
      }

      // Decode image data
      final imageData = base64.decode(base64Data);
      return await _decodeImage(imageData);
    } catch (e) {
      debugPrint('[iTerm2] Image decode failed: $e');
      return null;
    }
  }

  /// Create grid image from ui.Image.
  GridImage _createGridImage(ui.Image image, String sequence) {
    // Calculate grid dimensions
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final gridWidth = (imageWidth / _cellWidth).ceil();
    final gridHeight = (imageHeight / _cellHeight).ceil();

    return GridImage(
      id: _generateImageId(),
      image: image,
      x: 0,
      y: 0,
      width: gridWidth,
      height: gridHeight,
      pixelWidth: imageWidth,
      pixelHeight: imageHeight,
      protocol: _detectProtocol(sequence),
    );
  }

  /// Create grid image from Kitty image.
  GridImage _createGridImageFromKitty(KittyImage kittyImage, KittyDisplayParams params) {
    final gridWidth = (params.width / _cellWidth).ceil();
    final gridHeight = (params.height / _cellHeight).ceil();

    return GridImage(
      id: kittyImage.id,
      image: kittyImage.image,
      x: (params.x / _cellWidth).floor(),
      y: (params.y / _cellHeight).floor(),
      width: gridWidth,
      height: gridHeight,
      pixelWidth: params.width.toDouble(),
      pixelHeight: params.height.toDouble(),
      protocol: 'kitty',
    );
  }

  /// Decode image from bytes.
  Future<ui.Image?> _decodeImage(Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('[Graphics] Image decode failed: $e');
      return null;
    }
  }

  /// Detect graphics protocol from sequence.
  String _detectProtocol(String sequence) {
    if (sequence.contains('\x1bP')) return 'sixel';
    if (sequence.contains('\x1b_G')) return 'kitty';
    if (sequence.contains('\x1b]1337')) return 'iterm2';
    return 'unknown';
  }

  /// Generate unique image ID.
  String _generateImageId() {
    return 'img_${DateTime.now().millisecondsSinceEpoch}_${_gridImages.length}';
  }

  /// Remove image by ID.
  void _removeImageById(String imageId) {
    _gridImages.removeWhere((img) => img.id == imageId);
  }

  /// Update terminal dimensions for grid calculations.
  void updateTerminalDimensions(int width, int height, double cellWidth, double cellHeight) {
    _terminalWidth = width;
    _terminalHeight = height;
    _cellWidth = cellWidth;
    _cellHeight = cellHeight;
  }

  /// Handle terminal scroll - move images with content.
  void handleScroll(int linesUp) {
    for (final image in _gridImages) {
      image.y += linesUp;
    }
    
    // Remove images that scrolled out of view
    _gridImages.removeWhere((img) => img.y + img.height < 0 || img.y >= _terminalHeight);
  }

  /// Get images in a specific region.
  List<GridImage> getImagesInRegion(int x, int y, int width, int height) {
    return _gridImages.where((img) {
      return img.x < x + width && img.x + img.width > x &&
             img.y < y + height && img.y + img.height > y;
    }).toList();
  }

  /// Get all grid images.
  List<GridImage> get allImages => List.unmodifiable(_gridImages);

  /// Clear all images.
  void clearImages() {
    for (final image in _gridImages) {
      image.image.dispose();
    }
    _gridImages.clear();
  }

  /// Get memory usage statistics.
  Map<String, dynamic> getMemoryStats() {
    final totalImages = _gridImages.length;
    final totalMemory = _gridImages.fold<int>(0, (sum, img) => 
        sum + (img.pixelWidth * img.pixelHeight * 4).toInt()); // RGBA = 4 bytes per pixel
    
    return {
      'imageCount': totalImages,
      'estimatedMemoryBytes': totalMemory,
      'sixelCacheSize': _sixelDecoder.getPalette().length,
      'kittyCacheStats': _kittyCache.getCacheStats(),
    };
  }

  /// Dispose resources.
  void dispose() {
    clearImages();
    _sixelDecoder.dispose();
    _kittyCache.dispose();
  }
}

/// Image positioned on the terminal grid.
class GridImage {
  final String id;
  final ui.Image image;
  int x;
  int y;
  final int width;
  final int height;
  final double pixelWidth;
  final double pixelHeight;
  final String protocol;
  final DateTime createdAt;

  GridImage({
    required this.id,
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.protocol,
  }) : createdAt = DateTime.now();

  /// Check if this image intersects a grid region.
  bool intersectsRegion(int regionX, int regionY, int regionWidth, int regionHeight) {
    return x < regionX + regionWidth && x + width > regionX &&
           y < regionY + regionHeight && y + height > regionY;
  }

  /// Get the display rectangle for this image.
  ui.Rect getDisplayRect(double cellWidth, double cellHeight) {
    return ui.Rect.fromLTWH(
      x * cellWidth,
      y * cellHeight,
      width * cellWidth,
      height * cellHeight,
    );
  }

  /// Dispose image resources.
  void dispose() {
    image.dispose();
  }
}

/// Graphics action for terminal updates.
abstract class GraphicsAction {
  static GraphicsAction displayImage(GridImage image) => 
      _DisplayImageAction(image);
  static GraphicsAction deleteImage(String imageId) => 
      _DeleteImageAction(imageId);
}

/// Display image action.
class _DisplayImageAction extends GraphicsAction {
  final GridImage image;
  _DisplayImageAction(this.image);
}

/// Delete image action.
class _DeleteImageAction extends GraphicsAction {
  final String imageId;
  _DeleteImageAction(this.imageId);
}
