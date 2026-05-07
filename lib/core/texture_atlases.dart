import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:math';

class TextureAtlases {
  static const int _maxAtlasSize = 4096; // 4K textures
  static const int _maxGlyphsPerAtlas = 1024;
  static const int _padding = 2; // Padding between glyphs
  
  final Map<String, TextureAtlas> _atlases = {};
  final Map<String, GlyphMetrics> _glyphMetrics = {};
  final Map<String, AtlasRegion> _regions = {};
  
  int _totalAtlases = 0;
  int _totalGlyphs = 0;
  int _totalTextureMemory = 0;
  
  final StreamController<AtlasEvent> _atlasController = 
      StreamController<AtlasEvent>.broadcast();

  void initialize() {
    _initializeDefaultAtlases();
    developer.log('🎨 Texture Atlases initialized');
  }

  void _initializeDefaultAtlases() {
    // Create default atlas for terminal glyphs
    _createAtlas('terminal', 512, 512, TextureFormat.rgba8);
    _createAtlas('icons', 256, 256, TextureFormat.rgba8);
    _createAtlas('ui', 1024, 1024, TextureFormat.rgba8);
  }

  String createAtlas(String name, int width, int height, TextureFormat format) {
    if (_atlases.containsKey(name)) {
      throw Exception('Atlas already exists: $name');
    }
    
    final atlasId = _generateAtlasId();
    
    final atlas = TextureAtlas(
      id: atlasId,
      name: name,
      width: width,
      height: height,
      format: format,
      data: Uint8List(width * height * _getBytesPerPixel(format)),
      regions: {},
      createdAt: DateTime.now(),
    );
    
    _atlases[name] = atlas;
    _totalAtlases++;
    _totalTextureMemory += width * height * _getBytesPerPixel(format);
    
    developer.log('🎨 Created atlas: $name (${width}x$height, $format)');
    
    _emitEvent(AtlasEvent(
      type: AtlasEventType.created,
      atlasId: atlasId,
      atlasName: name,
      width: width,
      height: height,
      format: format,
    ));
    
    return atlasId;
  }

  String addGlyph(String atlasName, String char, {
    required int glyphWidth,
    required int glyphHeight,
    required List<int> glyphData,
    int? advanceX,
    int? advanceY,
    int? bearingX,
    int? bearingY,
  }) {
    final atlas = _atlases[atlasName];
    if (atlas == null) {
      throw Exception('Atlas not found: $atlasName');
    }
    
    final charCode = char.codeUnitAt(0);
    final glyphId = '${atlasName}_glyph_$charCode';
    
    // Check if glyph already exists
    if (_regions.containsKey(glyphId)) {
      return _regions[glyphId]!.regionId;
    }
    
    // Find optimal position in atlas
    final position = _findOptimalPosition(atlas, glyphWidth, glyphHeight);
    if (position == null) {
      // Atlas is full, create new one
      final newAtlasName = '${atlasName}_${_totalAtlases}';
      createAtlas(newAtlasName, atlas.width, atlas.height, atlas.format);
      return addGlyph(newAtlasName, char,
        glyphWidth: glyphWidth,
        glyphHeight: glyphHeight,
        glyphData: glyphData,
        advanceX: advanceX,
        advanceY: advanceY,
        bearingX: bearingX,
        bearingY: bearingY,
      );
    }
    
    // Add glyph to atlas
    _writeGlyphToAtlas(atlas, position, glyphWidth, glyphHeight, glyphData);
    
    // Create region
    final region = AtlasRegion(
      id: _generateRegionId(),
      atlasId: atlas.id,
      glyphId: glyphId,
      char: char,
      x: position.x,
      y: position.y,
      width: glyphWidth,
      height: glyphHeight,
      uvX: position.x / atlas.width.toDouble(),
      uvY: position.y / atlas.height.toDouble(),
      uvWidth: glyphWidth / atlas.width.toDouble(),
      uvHeight: glyphHeight / atlas.height.toDouble(),
    );
    
    _regions[glyphId] = region;
    atlas.regions[region.id] = region;
    
    // Create glyph metrics
    final metrics = GlyphMetrics(
      char: char,
      width: glyphWidth,
      height: glyphHeight,
      advanceX: advanceX ?? glyphWidth,
      advanceY: advanceY ?? 0,
      bearingX: bearingX ?? 0,
      bearingY: bearingY ?? 0,
      regionId: region.id,
    );
    
    _glyphMetrics[glyphId] = metrics;
    _totalGlyphs++;
    
    developer.log('🎨 Added glyph: $char to atlas $atlasName at (${position.x}, ${position.y})');
    
    _emitEvent(AtlasEvent(
      type: AtlasEventType.glyphAdded,
      atlasId: atlas.id,
      atlasName: atlasName,
      glyphId: glyphId,
      char: char,
      regionId: region.id,
    ));
    
    return region.id;
  }

  AtlasPosition? _findOptimalPosition(TextureAtlas atlas, int width, int height) {
    // Try to find a position that fits
    for (int y = 0; y <= atlas.height - height - _padding; y += height + _padding) {
      for (int x = 0; x <= atlas.width - width - _padding; x += width + _padding) {
        if (_canPlaceGlyph(atlas, x, y, width, height)) {
          return AtlasPosition(x: x, y: y);
        }
      }
    }
    
    return null; // No space available
  }

  bool _canPlaceGlyph(TextureAtlas atlas, int x, int y, int width, int height) {
    // Check if the area is free
    for (final region in atlas.regions.values) {
      if (_regionsOverlap(x, y, width, height, region)) {
        return false;
      }
    }
    
    // Check bounds
    if (x + width > atlas.width || y + height > atlas.height) {
      return false;
    }
    
    return true;
  }

  bool _regionsOverlap(
    int x, int y, int width, int height,
    AtlasRegion region,
  ) {
    return !(x + width <= region.x ||
             x >= region.x + region.width ||
             y + height <= region.y ||
             y >= region.y + region.height);
  }

  void _writeGlyphToAtlas(
    TextureAtlas atlas,
    AtlasPosition position,
    int width,
    int height,
    List<int> glyphData,
  ) {
    final bytesPerPixel = _getBytesPerPixel(atlas.format);
    final atlasData = atlas.data;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final atlasX = position.x + x;
        final atlasY = position.y + y;
        final atlasIndex = (atlasY * atlas.width + atlasX) * bytesPerPixel;
        
        if (atlasIndex + 3 < atlasData.length) {
          // Copy glyph data to atlas
          final glyphIndex = (y * width + x) * bytesPerPixel;
          if (glyphIndex + 3 < glyphData.length) {
            atlasData[atlasIndex] = glyphData[glyphIndex];
            atlasData[atlasIndex + 1] = glyphData[glyphIndex + 1];
            atlasData[atlasIndex + 2] = glyphData[glyphIndex + 2];
            if (bytesPerPixel == 4) {
              atlasData[atlasIndex + 3] = glyphData[glyphIndex + 3];
            }
          }
        }
      }
    }
    
    atlas.lastModified = DateTime.now();
  }

  AtlasRegion? getGlyphRegion(String atlasName, String char) {
    final glyphId = '${atlasName}_glyph_${char.codeUnitAt(0)}';
    return _regions[glyphId];
  }

  GlyphMetrics? getGlyphMetrics(String atlasName, String char) {
    final glyphId = '${atlasName}_glyph_${char.codeUnitAt(0)}';
    return _glyphMetrics[glyphId];
  }

  List<String> getAvailableGlyphs(String atlasName) {
    final glyphs = <String>[];
    
    for (final entry in _regions.entries) {
      if (entry.value.atlasId == _atlases[atlasName]?.id) {
        glyphs.add(entry.value.char);
      }
    }
    
    return glyphs;
  }

  double getGlyphAdvance(String atlasName, String char) {
    final metrics = getGlyphMetrics(atlasName, char);
    return metrics?.advanceX.toDouble() ?? 0.0;
  }

  void optimizeAtlas(String atlasName) {
    final atlas = _atlases[atlasName];
    if (atlas == null) return;
    
    // Sort regions by usage frequency if available
    final regions = atlas.regions.values.toList();
    regions.sort((a, b) => (b.usageCount ?? 0).compareTo(a.usageCount ?? 0));
    
    // Rebuild atlas with optimal layout
    _rebuildAtlas(atlas, regions);
    
    developer.log('🎨 Optimized atlas: $atlasName');
    
    _emitEvent(AtlasEvent(
      type: AtlasEventType.optimized,
      atlasId: atlas.id,
      atlasName: atlasName,
    ));
  }

  void _rebuildAtlas(TextureAtlas atlas, List<AtlasRegion> regions) {
    // Clear current atlas
    atlas.data.fillRange(0, atlas.data.length, 0);
    atlas.regions.clear();
    
    // Re-add regions in optimal order
    for (final region in regions) {
      final position = _findOptimalPosition(atlas, region.width, region.height);
      if (position != null) {
        // Re-add region at new position
        region.x = position.x;
        region.y = position.y;
        region.uvX = position.x / atlas.width.toDouble();
        region.uvY = position.y / atlas.height.toDouble();
        
        atlas.regions[region.id] = region;
        _regions[region.glyphId] = region;
      }
    }
    
    atlas.lastModified = DateTime.now();
  }

  void removeGlyph(String atlasName, String char) {
    final glyphId = '${atlasName}_glyph_${char.codeUnitAt(0)}';
    final region = _regions.remove(glyphId);
    
    if (region != null) {
      final atlas = _atlases[atlasName];
      if (atlas != null) {
        atlas.regions.remove(region.id);
        atlas.lastModified = DateTime.now();
      }
      
      _glyphMetrics.remove(glyphId);
      _totalGlyphs--;
      
      developer.log('🎨 Removed glyph: $char from atlas $atlasName');
      
      _emitEvent(AtlasEvent(
        type: AtlasEventType.glyphRemoved,
        atlasId: atlas?.id,
        atlasName: atlasName,
        glyphId: glyphId,
        char: char,
      ));
    }
  }

  void clearAtlas(String atlasName) {
    final atlas = _atlases[atlasName];
    if (atlas == null) return;
    
    // Remove all regions
    for (final regionId in atlas.regions.keys.toList()) {
      final region = atlas.regions[regionId]!;
      _regions.remove(region.glyphId);
      _glyphMetrics.remove(region.glyphId);
    }
    
    // Clear atlas data
    atlas.data.fillRange(0, atlas.data.length, 0);
    atlas.regions.clear();
    atlas.lastModified = DateTime.now();
    
    _totalGlyphs = 0;
    
    developer.log('🎨 Cleared atlas: $atlasName');
    
    _emitEvent(AtlasEvent(
      type: AtlasEventType.cleared,
      atlasId: atlas.id,
      atlasName: atlasName,
    ));
  }

  void deleteAtlas(String atlasName) {
    final atlas = _atlases.remove(atlasName);
    if (atlas == null) return;
    
    // Remove all associated regions and metrics
    for (final regionId in atlas.regions.keys.toList()) {
      final region = atlas.regions[regionId]!;
      _regions.remove(region.glyphId);
      _glyphMetrics.remove(region.glyphId);
    }
    
    _totalAtlases--;
    _totalTextureMemory -= atlas.width * atlas.height * _getBytesPerPixel(atlas.format);
    
    developer.log('🎨 Deleted atlas: $atlasName');
    
    _emitEvent(AtlasEvent(
      type: AtlasEventType.deleted,
      atlasId: atlas.id,
      atlasName: atlasName,
    ));
  }

  int _getBytesPerPixel(TextureFormat format) {
    switch (format) {
      case TextureFormat.rgba8:
        return 4;
      case TextureFormat.rgb8:
        return 3;
      case TextureFormat.rgba16f:
        return 8;
      case TextureFormat.rgba32f:
        return 16;
      case TextureFormat.dxt1:
        return 1; // Compressed
      case TextureFormat.dxt3:
        return 1; // Compressed
      case TextureFormat.dxt5:
        return 1; // Compressed
    }
  }

  Uint8List getAtlasData(String atlasName) {
    final atlas = _atlases[atlasName];
    return atlas?.data ?? Uint8List(0);
  }

  AtlasInfo getAtlasInfo(String atlasName) {
    final atlas = _atlases[atlasName];
    if (atlas == null) {
      throw Exception('Atlas not found: $atlasName');
    }
    
    return AtlasInfo(
      id: atlas.id,
      name: atlas.name,
      width: atlas.width,
      height: atlas.height,
      format: atlas.format,
      regionCount: atlas.regions.length,
      memoryUsage: atlas.width * atlas.height * _getBytesPerPixel(atlas.format),
      lastModified: atlas.lastModified,
      createdAt: atlas.createdAt,
    );
  }

  List<AtlasInfo> getAllAtlasInfo() {
    return _atlases.values.map((atlas) => AtlasInfo(
      id: atlas.id,
      name: atlas.name,
      width: atlas.width,
      height: atlas.height,
      format: atlas.format,
      regionCount: atlas.regions.length,
      memoryUsage: atlas.width * atlas.height * _getBytesPerPixel(atlas.format),
      lastModified: atlas.lastModified,
      createdAt: atlas.createdAt,
    )).toList();
  }

  void compactAtlases() {
    // Remove unused glyphs and compact atlases
    for (final atlasName in _atlases.keys.toList()) {
      final atlas = _atlases[atlasName]!;
      final regionsToRemove = <String>[];
      
      for (final region in atlas.regions.values) {
        if ((region.usageCount ?? 0) == 0) {
          regionsToRemove.add(region.id);
        }
      }
      
      for (final regionId in regionsToRemove) {
        final region = atlas.regions[regionId]!;
        atlas.regions.remove(regionId);
        _regions.remove(region.glyphId);
        _glyphMetrics.remove(region.glyphId);
        _totalGlyphs--;
      }
      
      if (regionsToRemove.isNotEmpty) {
        _rebuildAtlas(atlas, atlas.regions.values.toList());
        developer.log('🎨 Compacted atlas: $atlasName (removed ${regionsToRemove.length} glyphs)');
      }
    }
  }

  String _generateAtlasId() {
    return 'atlas_${DateTime.now().millisecondsSinceEpoch}_$_totalAtlases';
  }

  String _generateRegionId() {
    return 'region_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(AtlasEvent event) {
    _atlasController.add(event);
  }

  Stream<AtlasEvent> get atlasEventStream => _atlasController.stream;

  TextureAtlasStats getStats() {
    return TextureAtlasStats(
      totalAtlases: _totalAtlases,
      totalGlyphs: _totalGlyphs,
      totalTextureMemory: _totalTextureMemory,
      averageGlyphsPerAtlas: _totalAtlases > 0 ? _totalGlyphs / _totalAtlases : 0.0,
      atlasCount: _atlases.length,
    );
  }

  void dispose() {
    _atlases.clear();
    _glyphMetrics.clear();
    _regions.clear();
    _atlasController.close();
    
    developer.log('🎨 Texture Atlases disposed');
  }
}

class TextureAtlas {
  final String id;
  final String name;
  final int width;
  final int height;
  final TextureFormat format;
  Uint8List data;
  final Map<String, AtlasRegion> regions;
  final DateTime createdAt;
  DateTime lastModified;

  TextureAtlas({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.data,
    required this.regions,
    required this.createdAt,
  }) : lastModified = createdAt;
}

class AtlasRegion {
  final String id;
  final String atlasId;
  final String glyphId;
  final String char;
  final int x;
  final int y;
  final int width;
  final int height;
  final double uvX;
  final double uvY;
  final double uvWidth;
  final double uvHeight;
  int? usageCount;

  AtlasRegion({
    required this.id,
    required this.atlasId,
    required this.glyphId,
    required this.char,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.uvX,
    required this.uvY,
    required this.uvWidth,
    required this.uvHeight,
    this.usageCount,
  });
}

class GlyphMetrics {
  final String char;
  final int width;
  final int height;
  final int advanceX;
  final int advanceY;
  final int bearingX;
  final int bearingY;
  final String regionId;

  GlyphMetrics({
    required this.char,
    required this.width,
    required this.height,
    required this.advanceX,
    required this.advanceY,
    required this.bearingX,
    required this.bearingY,
    required this.regionId,
  });
}

class AtlasPosition {
  final int x;
  final int y;

  AtlasPosition({required this.x, required this.y});
}

enum TextureFormat {
  rgba8,
  rgb8,
  rgba16f,
  rgba32f,
  dxt1,
  dxt3,
  dxt5,
}

enum AtlasEventType {
  created,
  glyphAdded,
  glyphRemoved,
  optimized,
  cleared,
  deleted,
}

class AtlasEvent {
  final AtlasEventType type;
  final String? atlasId;
  final String? atlasName;
  final String? glyphId;
  final String? char;
  final String? regionId;
  final int? width;
  final int? height;
  final TextureFormat? format;

  AtlasEvent({
    required this.type,
    this.atlasId,
    this.atlasName,
    this.glyphId,
    this.char,
    this.regionId,
    this.width,
    this.height,
    this.format,
  });
}

class AtlasInfo {
  final String id;
  final String name;
  final int width;
  final int height;
  final TextureFormat format;
  final int regionCount;
  final int memoryUsage;
  final DateTime lastModified;
  final DateTime createdAt;

  AtlasInfo({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.regionCount,
    required this.memoryUsage,
    required this.lastModified,
    required this.createdAt,
  });
}

class TextureAtlasStats {
  final int totalAtlases;
  final int totalGlyphs;
  final int totalTextureMemory;
  final double averageGlyphsPerAtlas;
  final int atlasCount;

  TextureAtlasStats({
    required this.totalAtlases,
    required this.totalGlyphs,
    required this.totalTextureMemory,
    required this.averageGlyphsPerAtlas,
    required this.atlasCount,
  });
}
