import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

/// Texture atlas system for fonts and icons
/// 
/// Features:
/// - Efficient texture packing for multiple assets
/// - GPU memory optimization
/// - Dynamic atlas resizing
/// - Automatic texture compression
/// - Fast texture lookup and caching
class TextureAtlasSystem {
  static const int _initialAtlasSize = 2048;
  static const int _maxAtlasSize = 8192;
  static const int _padding = 2;
  static const int _maxTextures = 1000;
  
  final Map<String, AtlasTexture> _textureCache = {};
  final List<AtlasPage> _atlasPages = [];
  final Queue<AtlasTexture> _textureQueue = Queue();
  final Map<String, ui.Image> _loadedImages = {};
  
  int _currentAtlasSize = _initialAtlasSize;
  int _totalMemoryUsage = 0;
  int _textureCount = 0;
  
  /// Performance metrics
  int _packAttempts = 0;
  int _packSuccesses = 0;
  int _atlasResizes = 0;
  double _totalPackTime = 0.0;
  
  TextureAtlasSystem() {
    _initializeAtlas();
  }

  /// Initialize the texture atlas system
  void _initializeAtlas() {
    _atlasPages.add(AtlasPage(_currentAtlasSize, _currentAtlasSize));
  }

  /// Add texture to atlas
  Future<AtlasTexture> addTexture(
    String key, {
    required ui.Image image,
    String? category,
    bool compress = true,
  }) async {
    if (_textureCache.containsKey(key)) {
      return _textureCache[key]!;
    }
    
    final stopwatch = Stopwatch()..start();
    _packAttempts++;
    
    try {
      // Try to pack into existing atlas pages
      for (final page in _atlasPages) {
        final texture = await page.addTexture(key, image, category: category, compress: compress);
        if (texture != null) {
          _textureCache[key] = texture;
          _textureQueue.add(texture);
          _textureCount++;
          _totalMemoryUsage += texture.memoryUsage;
          _packSuccesses++;
          _totalPackTime += stopwatch.elapsedMilliseconds.toDouble();
          return texture;
        }
      }
      
      // Need to create new atlas page
      if (_atlasPages.length < 10) { // Limit number of atlas pages
        await _createNewAtlasPage();
        return await addTexture(key, image: image, category: category, compress: compress);
      } else {
        // Atlas is full, remove least recently used textures
        await _evictLeastRecentlyUsed();
        return await addTexture(key, image: image, category: category, compress: compress);
      }
    } catch (e) {
      debugPrint('Failed to add texture to atlas: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Add font glyph to atlas
  Future<AtlasTexture> addFontGlyph(
    String key, {
    required String character,
    required String fontFamily,
    required double fontSize,
    required ui.Color color,
  }) async {
    // Render character to image
    final image = await _renderCharacterToImage(character, fontFamily, fontSize, color);
    return await addTexture(
      key,
      image: image,
      category: 'font',
      compress: false, // Don't compress fonts for quality
    );
  }

  /// Add icon to atlas
  Future<AtlasTexture> addIcon(
    String key, {
    required String iconPath,
    double size = 24.0,
    ui.Color color = const ui.Color(0xFFFFFFFF),
  }) async {
    try {
      // Load icon image
      final imageData = await rootBundle.load(iconPath);
      final codec = await ui.instantiateImageCodec(imageData.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      return await addTexture(
        key,
        image: image,
        category: 'icon',
        compress: true,
      );
    } catch (e) {
      debugPrint('Failed to add icon $iconPath: $e');
      rethrow;
    }
  }

  /// Render character to image
  Future<ui.Image> _renderCharacterToImage(
    String character,
    String fontFamily,
    double fontSize,
    ui.Color color,
  ) async {
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize,
        fontFamily: fontFamily,
        fontWeight: ui.FontWeight.normal,
      ),
    );
    
    paragraphBuilder.pushStyle(ui.TextStyle(color: color, fontSize: fontSize));
    paragraphBuilder.addText(character);
    final paragraph = paragraphBuilder.build();
    
    // Measure text
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    final width = paragraph.width.ceil();
    final height = paragraph.height.ceil();
    
    // Render to image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = ui.Color.transparent,
    );
    canvas.drawParagraph(paragraph, Offset.zero);
    
    final picture = recorder.endRecording();
    return await picture.toImage(width, height);
  }

  /// Create new atlas page
  Future<void> _createNewAtlasPage() async {
    if (_currentAtlasSize < _maxAtlasSize) {
      _currentAtlasSize = (_currentAtlasSize * 2).clamp(_initialAtlasSize, _maxAtlasSize);
      _atlasResizes++;
    }
    
    final page = AtlasPage(_currentAtlasSize, _currentAtlasSize);
    await page.initialize();
    _atlasPages.add(page);
  }

  /// Evict least recently used textures
  Future<void> _evictLeastRecentlyUsed() async {
    final evictCount = _textureCount ~/ 4; // Evict 25% of textures
    
    for (int i = 0; i < evictCount && _textureQueue.isNotEmpty; i++) {
      final texture = _textureQueue.removeFirst();
      await texture.dispose();
      _textureCache.remove(texture.key);
      _totalMemoryUsage -= texture.memoryUsage;
      _textureCount--;
    }
  }

  /// Get texture from atlas
  AtlasTexture? getTexture(String key) {
    final texture = _textureCache[key];
    if (texture != null) {
      // Move to end of queue (most recently used)
      _textureQueue.remove(texture);
      _textureQueue.add(texture);
    }
    return texture;
  }

  /// Get all textures in category
  List<AtlasTexture> getTexturesInCategory(String category) {
    return _textureCache.values
        .where((texture) => texture.category == category)
        .toList();
  }

  /// Get atlas statistics
  AtlasStats getStats() {
    return AtlasStats(
      totalTextures: _textureCount,
      totalMemoryUsage: _totalMemoryUsage,
      atlasPages: _atlasPages.length,
      currentAtlasSize: _currentAtlasSize,
      packSuccessRate: _packAttempts > 0 ? _packSuccesses / _packAttempts : 0.0,
      averagePackTime: _packAttempts > 0 ? _totalPackTime / _packAttempts : 0.0,
      cacheSize: _textureCache.length,
      atlasResizes: _atlasResizes,
    );
  }

  /// Optimize atlas by defragmenting
  Future<void> optimizeAtlas() async {
    if (_textureCount < _maxTextures / 2) return; // Only optimize if more than half full
    
    // Create new atlas pages
    final newPages = <AtlasPage>[];
    for (final page in _atlasPages) {
      final newPage = AtlasPage(page.width, page.height);
      await newPage.initialize();
      newPages.add(newPage);
    }
    
    // Re-pack all textures
    final oldTextures = List<AtlasTexture>.from(_textureCache.values);
    _textureCache.clear();
    _textureQueue.clear();
    
    for (final texture in oldTextures) {
      await addTexture(
        texture.key,
        image: texture.image!,
        category: texture.category,
        compress: texture.compressed,
      );
    }
    
    // Dispose old pages
    for (final page in _atlasPages) {
      await page.dispose();
    }
    
    _atlasPages.clear();
    _atlasPages.addAll(newPages);
  }

  /// Clear all textures
  Future<void> clear() async {
    for (final texture in _textureCache.values) {
      await texture.dispose();
    }
    
    for (final page in _atlasPages) {
      await page.dispose();
    }
    
    _textureCache.clear();
    _textureQueue.clear();
    _atlasPages.clear();
    _loadedImages.clear();
    
    _totalMemoryUsage = 0;
    _textureCount = 0;
    _currentAtlasSize = _initialAtlasSize;
    
    _initializeAtlas();
  }

  /// Dispose resources
  Future<void> dispose() async {
    await clear();
  }
}

/// Single atlas page
class AtlasPage {
  final int width;
  final int height;
  final List<AtlasNode> _nodes = [];
  ui.Image? _atlasImage;
  ui.Canvas? _canvas;
  
  AtlasPage(this.width, this.height);
  
  /// Initialize atlas page
  Future<void> initialize() async {
    _nodes.add(AtlasNode(0, 0, width, height));
    
    final recorder = ui.PictureRecorder();
    _canvas = Canvas(recorder);
    
    // Create initial atlas image
    final picture = recorder.endRecording();
    _atlasImage = await picture.toImage(width, height);
  }

  /// Add texture to this atlas page
  Future<AtlasTexture?> addTexture(
    String key,
    ui.Image image, {
    String? category,
    bool compress = true,
  }) async {
    final imageWidth = image.width;
    final imageHeight = image.height;
    
    // Find suitable node
    final node = _findNode(imageWidth + _padding * 2, imageHeight + _padding * 2);
    if (node == null) return null;
    
    // Split node
    _splitNode(node, imageWidth + _padding * 2, imageHeight + _padding * 2);
    
    // Create texture
    final texture = AtlasTexture(
      key: key,
      image: image,
      x: node.x + _padding,
      y: node.y + _padding,
      width: imageWidth,
      height: imageHeight,
      category: category,
      compressed: compress,
      atlasPage: this,
    );
    
    // Draw texture to atlas
    await _drawTextureToAtlas(texture);
    
    return texture;
  }

  /// Find suitable node for texture
  AtlasNode? _findNode(int width, int height) {
    for (final node in _nodes) {
      if (node.used) continue;
      if (node.width < width || node.height < height) continue;
      
      if (node.width == width && node.height == height) {
        return node;
      }
      
      return _findNodeRecursive(node, width, height);
    }
    return null;
  }

  /// Find node recursively
  AtlasNode? _findNodeRecursive(AtlasNode node, int width, int height) {
    if (node.used) return null;
    
    if (node.width >= width && node.height >= height) {
      return node;
    }
    
    return null;
  }

  /// Split node to accommodate texture
  void _splitNode(AtlasNode node, int width, int height) {
    node.used = true;
    
    // Create right node
    if (node.width > width) {
      _nodes.add(AtlasNode(
        node.x + width,
        node.y,
        node.width - width,
        height,
      ));
    }
    
    // Create bottom node
    if (node.height > height) {
      _nodes.add(AtlasNode(
        node.x,
        node.y + height,
        node.width,
        node.height - height,
      ));
    }
  }

  /// Draw texture to atlas
  Future<void> _drawTextureToAtlas(AtlasTexture texture) async {
    if (_canvas == null || _atlasImage == null) return;
    
    try {
      // Draw texture to atlas canvas
      final srcRect = Rect.fromLTWH(0, 0, texture.width.toDouble(), texture.height.toDouble());
      final dstRect = Rect.fromLTWH(
        texture.x.toDouble(),
        texture.y.toDouble(),
        texture.width.toDouble(),
        texture.height.toDouble(),
      );
      
      _canvas!.drawImageRect(
        texture.image!,
        srcRect,
        dstRect,
        Paint(),
      );
      
      // Update atlas image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(_atlasImage!, Offset.zero, Paint());
      
      final picture = recorder.endRecording();
      _atlasImage = await picture.toImage(width, height);
    } catch (e) {
      debugPrint('Failed to draw texture to atlas: $e');
    }
  }

  /// Dispose atlas page
  Future<void> dispose() async {
    _atlasImage?.dispose();
    _nodes.clear();
  }
}

/// Atlas node for texture packing
class AtlasNode {
  final int x;
  final int y;
  final int width;
  final int height;
  bool used = false;

  AtlasNode(this.x, this.y, this.width, this.height);
}

/// Atlas texture
class AtlasTexture {
  final String key;
  final ui.Image? image;
  final int x;
  final int y;
  final int width;
  final int height;
  final String? category;
  final bool compressed;
  final AtlasPage atlasPage;

  AtlasTexture({
    required this.key,
    this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.category,
    required this.compressed,
    required this.atlasPage,
  });

  /// Get texture coordinates
  Rect get uvRect => Rect.fromLTWH(
    x.toDouble() / atlasPage.width,
    y.toDouble() / atlasPage.height,
    width.toDouble() / atlasPage.width,
    height.toDouble() / atlasPage.height,
  );

  /// Get memory usage
  int get memoryUsage => width * height * 4; // 4 bytes per pixel (RGBA)

  /// Dispose texture
  Future<void> dispose() async {
    image?.dispose();
  }
}

/// Atlas statistics
class AtlasStats {
  final int totalTextures;
  final int totalMemoryUsage;
  final int atlasPages;
  final int currentAtlasSize;
  final double packSuccessRate;
  final double averagePackTime;
  final int cacheSize;
  final int atlasResizes;

  const AtlasStats({
    required this.totalTextures,
    required this.totalMemoryUsage,
    required this.atlasPages,
    required this.currentAtlasSize,
    required this.packSuccessRate,
    required this.averagePackTime,
    required this.cacheSize,
    required this.atlasResizes,
  });
}
