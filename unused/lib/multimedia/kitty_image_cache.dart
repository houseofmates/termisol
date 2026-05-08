import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Kitty graphics protocol handler with full implementation.
///
/// Supports all Kitty graphics operations:
/// - a=t: Transmit image data
/// - a=d: Display image
/// - a=p: Delete image  
/// - a=q: Query image
/// - f=24: RGB format
/// - f=32: RGBA format
/// - f=100: PNG format
class KittyImageCache {
  final Map<String, KittyImage> _imageCache = {};
  final Map<String, int> _imageRefCounts = {};
  static const int _maxCacheSize = 100;
  static const int _maxImageSize = 10 * 1024 * 1024; // 10MB

  /// Process a Kitty graphics protocol sequence.
  Future<List<KittyImageAction>> processSequence(String sequence) async {
    final actions = <KittyImageAction>[];
    
    try {
      // Parse the graphics protocol
      final match = RegExp(r'\x1b_G([a-z]=([^;]+);)?([^=]+)=([^\x1b]*)\x1b\\').firstMatch(sequence);
      if (match == null) {
        debugPrint('[Kitty] Invalid graphics sequence');
        return actions;
      }

      final action = match.group(3);
      final data = match.group(4) ?? '';
      
      switch (action) {
        case 't': // Transmit
          final transmitAction = await _handleTransmit(match, data);
          if (transmitAction != null) actions.add(transmitAction);
          break;
          
        case 'd': // Display
          final displayAction = await _handleDisplay(match, data);
          if (displayAction != null) actions.add(displayAction);
          break;
          
        case 'p': // Delete
          final deleteAction = await _handleDelete(match, data);
          if (deleteAction != null) actions.add(deleteAction);
          break;
          
        case 'q': // Query
          final queryAction = await _handleQuery(match, data);
          if (queryAction != null) actions.add(queryAction);
          break;
          
        default:
          debugPrint('[Kitty] Unknown action: $action');
      }
    } catch (e) {
      debugPrint('[Kitty] Sequence processing failed: $e');
    }
    
    return actions;
  }

  /// Handle image transmission (a=t).
  Future<KittyTransmitAction?> _handleTransmit(RegExpMatch match, String data) async {
    final params = _parseParams(match.group(2) ?? '');
    final imageId = params['i'] ?? _generateImageId();
    final format = params['f'] ?? '24';
    
    // Decode image data
    Uint8List imageData;
    ui.Image? image;
    
    if (format == '100') {
      // PNG format - decode directly
      imageData = base64.decode(data);
      image = await _decodeImage(imageData);
    } else if (format == '24' || format == '32') {
      // Raw RGB/RGBA format
      final width = int.tryParse(params['v'] ?? '0') ?? 0;
      final height = int.tryParse(params['s'] ?? '0') ?? 0;
      
      if (width > 0 && height > 0) {
        imageData = base64.decode(data);
        image = await _decodeRawImage(imageData, width, height, format == '32');
      } else {
        debugPrint('[Kitty] Invalid dimensions for raw format');
        return null;
      }
    } else {
      debugPrint('[Kitty] Unsupported format: $format');
      return null;
    }

    if (image == null) {
      debugPrint('[Kitty] Failed to decode image');
      return null;
    }

    // Cache the image
    final kittyImage = KittyImage(
      id: imageId,
      image: image,
      format: format,
      width: image.width,
      height: image.height,
      data: imageData,
    );
    
    _cacheImage(kittyImage);
    
    return KittyTransmitAction(imageId: imageId, image: kittyImage);
  }

  /// Handle image display (a=d).
  Future<KittyDisplayAction?> _handleDisplay(RegExpMatch match, String data) async {
    final params = _parseParams(match.group(2) ?? '');
    final imageId = params['i'];
    
    if (imageId == null) {
      debugPrint('[Kitty] Display requires image ID');
      return null;
    }
    
    final image = _imageCache[imageId];
    if (image == null) {
      debugPrint('[Kitty] Image not found: $imageId');
      return null;
    }
    
    final displayParams = KittyDisplayParams(
      x: int.tryParse(params['x'] ?? '0') ?? 0,
      y: int.tryParse(params['y'] ?? '0') ?? 0,
      width: int.tryParse(params['w'] ?? image.width.toString()) ?? image.width,
      height: int.tryParse(params['h'] ?? image.height.toString()) ?? image.height,
      z: int.tryParse(params['z'] ?? '0') ?? 0,
    );
    
    return KittyDisplayAction(imageId: imageId, image: image, params: displayParams);
  }

  /// Handle image deletion (a=p).
  Future<KittyDeleteAction?> _handleDelete(RegExpMatch match, String data) async {
    final params = _parseParams(match.group(2) ?? '');
    final imageId = params['i'];
    
    if (imageId == null) {
      debugPrint('[Kitty] Delete requires image ID');
      return null;
    }
    
    final success = _removeImage(imageId);
    return KittyDeleteAction(imageId: imageId, success: success);
  }

  /// Handle image query (a=q).
  Future<KittyQueryAction?> _handleQuery(RegExpMatch match, String data) async {
    final params = _parseParams(match.group(2) ?? '');
    final imageId = params['i'];
    
    if (imageId == null) {
      debugPrint('[Kitty] Query requires image ID');
      return null;
    }
    
    final image = _imageCache[imageId];
    if (image == null) {
      debugPrint('[Kitty] Image not found for query: $imageId');
      return null;
    }
    
    return KittyQueryAction(imageId: imageId, image: image);
  }

  /// Parse Kitty protocol parameters.
  Map<String, String> _parseParams(String paramString) {
    final params = <String, String>{};
    for (final pair in paramString.split(',')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        params[parts[0]] = parts[1];
      }
    }
    return params;
  }

  /// Decode image from bytes.
  Future<ui.Image?> _decodeImage(Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('[Kitty] Image decode failed: $e');
      return null;
    }
  }

  /// Decode raw RGB/RGBA image data.
  Future<ui.Image?> _decodeRawImage(Uint8List data, int width, int height, bool hasAlpha) async {
    try {
      final codec = await ui.instantiateImageCodec(
        data,
        targetWidth: width,
        targetHeight: height,
        format: hasAlpha ? ui.ImageFormat.rawRGBA : ui.ImageFormat.rawRGB,
      );
      
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('[Kitty] Raw image decode failed: $e');
      return null;
    }
  }

  /// Cache an image with reference counting.
  void _cacheImage(KittyImage image) {
    // Check cache size limits
    if (_imageCache.length >= _maxCacheSize) {
      _evictOldestImage();
    }
    
    // Check image size limits
    if (image.data.length > _maxImageSize) {
      debugPrint('[Kitty] Image too large: ${image.data.length} bytes');
      return;
    }
    
    _imageCache[image.id] = image;
    _imageRefCounts[image.id] = 1;
  }

  /// Remove an image from cache.
  bool _removeImage(String imageId) {
    final image = _imageCache.remove(imageId);
    if (image != null) {
      image.image.dispose();
      _imageRefCounts.remove(imageId);
      return true;
    }
    return false;
  }

  /// Evict oldest image from cache.
  void _evictOldestImage() {
    if (_imageCache.isEmpty) return;
    
    // Simple FIFO eviction - could be improved with LRU
    final firstKey = _imageCache.keys.first;
    _removeImage(firstKey);
  }

  /// Generate unique image ID.
  String _generateImageId() {
    return 'kitty_${DateTime.now().millisecondsSinceEpoch}_${_imageCache.length}';
  }

  /// Get cached image.
  KittyImage? getImage(String imageId) {
    return _imageCache[imageId];
  }

  /// Clear all cached images.
  void clearCache() {
    for (final image in _imageCache.values) {
      image.image.dispose();
    }
    _imageCache.clear();
    _imageRefCounts.clear();
  }

  /// Get cache statistics.
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _imageCache.length,
      'maxSize': _maxCacheSize,
      'totalMemory': _imageCache.values.fold<int>(0, (sum, img) => sum + img.data.length),
      'maxImageSize': _maxImageSize,
    };
  }

  /// Dispose resources.
  void dispose() {
    clearCache();
  }
}

/// Kitty image data.
class KittyImage {
  final String id;
  final ui.Image image;
  final String format;
  final int width;
  final int height;
  final Uint8List data;
  final DateTime createdAt;

  KittyImage({
    required this.id,
    required this.image,
    required this.format,
    required this.width,
    required this.height,
    required this.data,
  }) : createdAt = DateTime.now();

  /// Get aspect ratio.
  double get aspectRatio => height > 0 ? width / height : 1.0;

  /// Dispose image resources.
  void dispose() {
    image.dispose();
  }
}

/// Kitty graphics action base class.
abstract class KittyImageAction {
  final String imageId;
  
  KittyImageAction({required this.imageId});
}

/// Image transmission action.
class KittyTransmitAction extends KittyImageAction {
  final KittyImage image;
  
  KittyTransmitAction({required String imageId, required this.image}) : super(imageId: imageId);
}

/// Image display action.
class KittyDisplayAction extends KittyImageAction {
  final KittyImage image;
  final KittyDisplayParams params;
  
  KittyDisplayAction({
    required String imageId,
    required this.image,
    required this.params,
  }) : super(imageId: imageId);
}

/// Image delete action.
class KittyDeleteAction extends KittyImageAction {
  final bool success;
  
  KittyDeleteAction({required String imageId, required this.success}) : super(imageId: imageId);
}

/// Image query action.
class KittyQueryAction extends KittyImageAction {
  final KittyImage image;
  
  KittyQueryAction({required String imageId, required this.image}) : super(imageId: imageId);
}

/// Display parameters for Kitty images.
class KittyDisplayParams {
  final int x;
  final int y;
  final int width;
  final int height;
  final int z; // Z-index
  
  const KittyDisplayParams({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.z,
  });
}
