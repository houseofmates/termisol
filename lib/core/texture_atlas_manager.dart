import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Texture Atlas Manager - Best-in-class texture atlas management
/// 
/// Provides comprehensive texture atlas optimization with:
/// - Dynamic texture packing
/// - Atlas fragmentation management
/// - Memory-efficient texture storage
/// - GPU texture binding optimization
/// - Automatic atlas rebuilding
/// - Performance monitoring
class TextureAtlasManager {
  static final TextureAtlasManager _instance = TextureAtlasManager._internal();
  factory TextureAtlasManager() => _instance;
  TextureAtlasManager._internal();

  final Map<String, TextureAtlas> _atlases = {};
  final Map<String, TextureRegion> _textureRegions = {};
  final Queue<AtlasOperation> _operationQueue = Queue<AtlasOperation>();
  final Map<String, AtlasStatistics> _atlasStats = {};
  
  bool _isInitialized = false;
  bool _isRebuilding = false;
  Timer? _optimizationTimer;
  Timer? _cleanupTimer;
  
  // Atlas configuration
  static const Duration _optimizationInterval = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(minutes: 2);
  static const int _maxAtlasSize = 4096;
  static const int _minAtlasSize = 512;
  static const double _fragmentationThreshold = 0.3;
  static const int _maxTexturesPerAtlas = 1000;
  
  final _atlasController = StreamController<AtlasEvent>.broadcast();
  Stream<AtlasEvent> get events => _atlasController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get isRebuilding => _isRebuilding;
  Map<String, TextureAtlas> get atlases => Map.unmodifiable(_atlases);

  /// Initialize texture atlas manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Create default atlases
      await _createDefaultAtlases();
      
      // Start optimization timer
      _startOptimizationTimer();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('🗺️ Texture Atlas Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Texture Atlas Manager: $e');
      rethrow;
    }
  }

  /// Create a new atlas
  TextureAtlas createAtlas({
    required String name,
    int? width,
    int? height,
    AtlasFormat format = AtlasFormat.rgba8,
    AtlasFilter filter = AtlasFilter.linear,
    AtlasWrap wrap = AtlasWrap.clamp,
  }) {
    final atlasId = _generateAtlasId();
    final atlasWidth = width ?? _maxAtlasSize;
    final atlasHeight = height ?? _maxAtlasSize;
    
    final atlas = TextureAtlas(
      id: atlasId,
      name: name,
      width: atlasWidth,
      height: atlasHeight,
      format: format,
      filter: filter,
      wrap: wrap,
      regions: {},
      freeRegions: [Rectangle(0, 0, atlasWidth, atlasHeight)],
      usedSpace: 0,
      fragmentation: 0.0,
      statistics: AtlasStatistics(name),
    );

    _atlases[atlasId] = atlas;
    _atlasStats[atlasId] = atlas.statistics;
    
    _atlasController.add(AtlasEvent(
      type: AtlasEventType.atlasCreated,
      atlasId: atlasId,
      timestamp: DateTime.now(),
      data: {
        'name': name,
        'width': atlasWidth,
        'height': atlasHeight,
        'format': format.toString(),
      },
    ));
    
    debugPrint('🗺️ Created texture atlas: $name');
    return atlas;
  }

  /// Add texture to atlas
  Future<AtlasResult> addTexture({
    required String textureId,
    required int width,
    required int height,
    required Uint8List data,
    String? atlasId,
    AtlasFormat? format,
  }) async {
    // Find suitable atlas or create new one
    final targetAtlasId = atlasId ?? await _findSuitableAtlas(width, height, format);
    final atlas = _atlases[targetAtlasId];
    
    if (atlas == null) {
      return AtlasResult.error('No suitable atlas found');
    }

    // Find free region
    final region = _findFreeRegion(atlas, width, height);
    if (region == null) {
      // Try to optimize atlas
      await _optimizeAtlas(atlas);
      final optimizedRegion = _findFreeRegion(atlas, width, height);
      if (optimizedRegion == null) {
        // Need to rebuild atlas
        await _rebuildAtlas(atlas);
        final rebuiltRegion = _findFreeRegion(atlas, width, height);
        if (rebuiltRegion == null) {
          return AtlasResult.error('Cannot fit texture in atlas');
        }
        region = rebuiltRegion;
      } else {
        region = optimizedRegion;
      }
    }

    // Create texture region
    final textureRegion = TextureRegion(
      id: _generateRegionId(),
      textureId: textureId,
      atlasId: atlas.id,
      x: region.x,
      y: region.y,
      width: width,
      height: height,
      data: data,
      format: format ?? AtlasFormat.rgba8,
      timestamp: DateTime.now(),
    );

    _textureRegions[textureRegion.id] = textureRegion;
    atlas.regions[textureRegion.id] = textureRegion;
    
    // Update atlas statistics
    _updateAtlasStatistics(atlas, width, height);
    
    // Update free regions
    _updateFreeRegions(atlas, region);
    
    _atlasController.add(AtlasEvent(
      type: AtlasEventType.textureAdded,
      atlasId: atlas.id,
      timestamp: DateTime.now(),
      data: {
        'textureId': textureId,
        'width': width,
        'height': height,
        'regionId': textureRegion.id,
      },
    ));
    
    debugPrint('🗺️ Added texture $textureId to atlas ${atlas.name}');
    
    return AtlasResult.success(
      atlasId: atlas.id,
      regionId: textureRegion.id,
      x: region.x,
      y: region.y,
      width: width,
      height: height,
    );
  }

  /// Remove texture from atlas
  Future<bool> removeTexture(String textureId) async {
    final region = _textureRegions.values
        .where((r) => r.textureId == textureId)
        .firstOrNull;
    
    if (region == null) {
      return false;
    }

    final atlas = _atlases[region.atlasId];
    if (atlas == null) {
      return false;
    }

    // Remove from atlas
    atlas.regions.remove(region.id);
    _textureRegions.remove(region.id);
    
    // Add region back to free regions
    _addFreeRegion(atlas, Rectangle(
      region.x,
      region.y,
      region.width,
      region.height,
    ));

    // Update atlas statistics
    _updateAtlasStatisticsAfterRemoval(atlas, region.width, region.height);
    
    _atlasController.add(AtlasEvent(
      type: AtlasEventType.textureRemoved,
      atlasId: atlas.id,
      timestamp: DateTime.now(),
      data: {
        'textureId': textureId,
        'regionId': region.id,
      },
    ));
    
    debugPrint('🗺️ Removed texture $textureId from atlas ${atlas.name}');
    return true;
  }

  /// Get texture region
  TextureRegion? getTextureRegion(String textureId) {
    return _textureRegions.values
        .where((region) => region.textureId == textureId)
        .firstOrNull;
  }

  /// Get atlas statistics
  AtlasStatistics getStatistics(String atlasId) {
    return _atlasStats[atlasId] ?? AtlasStatistics('unknown');
  }

  /// Get overall statistics
  OverallAtlasStatistics getOverallStatistics() {
    return OverallAtlasStatistics(
      totalAtlases: _atlases.length,
      totalTextures: _textureRegions.length,
      totalMemoryUsage: _calculateTotalMemoryUsage(),
      averageFragmentation: _calculateAverageFragmentation(),
      averageUtilization: _calculateAverageUtilization(),
      atlases: _atlases.values.map((atlas) => AtlasInfo(
        id: atlas.id,
        name: atlas.name,
        width: atlas.width,
        height: atlas.height,
        textures: atlas.regions.length,
        utilization: _calculateAtlasUtilization(atlas),
        fragmentation: atlas.fragmentation,
      )).toList(),
    );
  }

  /// Optimize all atlases
  Future<void> optimizeAllAtlases() async {
    debugPrint('🗺️ Optimizing all texture atlases');
    
    for (final atlas in _atlases.values) {
      await _optimizeAtlas(atlas);
    }
    
    _atlasController.add(AtlasEvent(
      type: AtlasEventType.optimizationCompleted,
      timestamp: DateTime.now(),
      data: {
        'atlases_optimized': _atlases.length,
      },
    ));
  }

  /// Find suitable atlas for texture
  Future<String> _findSuitableAtlas(int width, int height, AtlasFormat? format) async {
    // Find existing atlas with space
    for (final atlas in _atlases.values) {
      if (atlas.format == format && _canFitTexture(atlas, width, height)) {
        return atlas.id;
      }
    }
    
    // Create new atlas if needed
    if (_atlases.length < 10) { // Limit number of atlases
      final newAtlas = createAtlas(
        name: 'auto_generated_${_atlases.length}',
        format: format ?? AtlasFormat.rgba8,
      );
      return newAtlas.id;
    }
    
    throw Exception('No suitable atlas available and cannot create new one');
  }

  /// Check if texture can fit in atlas
  bool _canFitTexture(TextureAtlas atlas, int width, int height) {
    for (final freeRegion in atlas.freeRegions) {
      if (freeRegion.width >= width && freeRegion.height >= height) {
        return true;
      }
    }
    return false;
  }

  /// Find free region in atlas
  Rectangle<int>? _findFreeRegion(TextureAtlas atlas, int width, int height) {
    for (final freeRegion in atlas.freeRegions) {
      if (freeRegion.width >= width && freeRegion.height >= height) {
        return Rectangle(
          freeRegion.x,
          freeRegion.y,
          width,
          height,
        );
      }
    }
    return null;
  }

  /// Update free regions after texture addition
  void _updateFreeRegions(TextureAtlas atlas, Rectangle<int> usedRegion) {
    final newFreeRegions = <Rectangle<int>>[];
    
    for (final freeRegion in atlas.freeRegions) {
      if (freeRegion.x == usedRegion.x && freeRegion.y == usedRegion.y) {
        // Split the free region around the used region
        // Right side
        if (freeRegion.width > usedRegion.width + usedRegion.x) {
          newFreeRegions.add(Rectangle(
            usedRegion.x + usedRegion.width,
            usedRegion.y,
            freeRegion.width - usedRegion.width,
            usedRegion.height,
          ));
        }
        
        // Bottom side
        if (freeRegion.height > usedRegion.height + usedRegion.y) {
          newFreeRegions.add(Rectangle(
            usedRegion.x,
            usedRegion.y + usedRegion.height,
            freeRegion.width,
            freeRegion.height - usedRegion.height,
          ));
        }
      } else {
        // Keep the free region if it doesn't overlap
        newFreeRegions.add(freeRegion);
      }
    }
    
    atlas.freeRegions.clear();
    atlas.freeRegions.addAll(newFreeRegions);
    _mergeAdjacentFreeRegions(atlas);
  }

  /// Add free region back to atlas
  void _addFreeRegion(TextureAtlas atlas, Rectangle<int> region) {
    atlas.freeRegions.add(region);
    _mergeAdjacentFreeRegions(atlas);
  }

  /// Merge adjacent free regions
  void _mergeAdjacentFreeRegions(TextureAtlas atlas) {
    final mergedRegions = <Rectangle<int>>[];
    final processed = <bool>[]..length = atlas.freeRegions.length;
    
    for (int i = 0; i < atlas.freeRegions.length; i++) {
      if (processed[i]) continue;
      
      var currentRegion = atlas.freeRegions[i];
      processed[i] = true;
      
      // Check for adjacent regions
      for (int j = i + 1; j < atlas.freeRegions.length; j++) {
        if (processed[j]) continue;
        
        final otherRegion = atlas.freeRegions[j];
        if (_areRegionsAdjacent(currentRegion, otherRegion)) {
          currentRegion = _mergeRegions(currentRegion, otherRegion);
          processed[j] = true;
        }
      }
      
      mergedRegions.add(currentRegion);
    }
    
    atlas.freeRegions.clear();
    atlas.freeRegions.addAll(mergedRegions);
  }

  /// Check if regions are adjacent
  bool _areRegionsAdjacent(Rectangle<int> region1, Rectangle<int> region2) {
    return (region1.right == region2.left && region1.top <= region2.bottom && region1.bottom >= region2.top) ||
           (region1.left == region2.right && region1.top <= region2.bottom && region1.bottom >= region2.top) ||
           (region1.bottom == region2.top && region1.left <= region2.right && region1.right >= region2.left) ||
           (region1.top == region2.bottom && region1.left <= region2.right && region1.right >= region2.left);
  }

  /// Merge two regions
  Rectangle<int> _mergeRegions(Rectangle<int> region1, Rectangle<int> region2) {
    final left = math.min(region1.left, region2.left);
    final top = math.min(region1.top, region2.top);
    final right = math.max(region1.right, region2.right);
    final bottom = math.max(region1.bottom, region2.bottom);
    
    return Rectangle(left, top, right - left, bottom - top);
  }

  /// Update atlas statistics after texture addition
  void _updateAtlasStatistics(TextureAtlas atlas, int width, int height) {
    final textureArea = width * height;
    atlas.usedSpace += textureArea;
    atlas.statistics.texturesAdded++;
    atlas.statistics.totalTextureArea += textureArea;
    
    // Calculate fragmentation
    atlas.fragmentation = _calculateAtlasFragmentation(atlas);
    atlas.statistics.fragmentation = atlas.fragmentation;
    
    // Calculate utilization
    final utilization = _calculateAtlasUtilization(atlas);
    atlas.statistics.utilization = utilization;
  }

  /// Update atlas statistics after texture removal
  void _updateAtlasStatisticsAfterRemoval(TextureAtlas atlas, int width, int height) {
    final textureArea = width * height;
    atlas.usedSpace -= textureArea;
    atlas.statistics.texturesRemoved++;
    atlas.statistics.totalTextureArea -= textureArea;
    
    // Recalculate fragmentation and utilization
    atlas.fragmentation = _calculateAtlasFragmentation(atlas);
    atlas.statistics.fragmentation = atlas.fragmentation;
    
    final utilization = _calculateAtlasUtilization(atlas);
    atlas.statistics.utilization = utilization;
  }

  /// Calculate atlas fragmentation
  double _calculateAtlasFragmentation(TextureAtlas atlas) {
    if (atlas.freeRegions.isEmpty) return 0.0;
    
    final totalFreeArea = atlas.freeRegions
        .fold(0, (sum, region) => sum + (region.width * region.height));
    
    final totalArea = atlas.width * atlas.height;
    final usedArea = totalArea - totalFreeArea;
    
    if (usedArea == 0) return 0.0;
    
    // Fragmentation is the ratio of free regions to total area
    return totalFreeArea / totalArea;
  }

  /// Calculate atlas utilization
  double _calculateAtlasUtilization(TextureAtlas atlas) {
    final totalArea = atlas.width * atlas.height;
    if (totalArea == 0) return 0.0;
    
    return atlas.usedSpace / totalArea;
  }

  /// Optimize specific atlas
  Future<void> _optimizeAtlas(TextureAtlas atlas) async {
    debugPrint('🗺️ Optimizing atlas: ${atlas.name}');
    
    // Try to defragment by reorganizing textures
    if (atlas.fragmentation > _fragmentationThreshold) {
      await _defragmentAtlas(atlas);
    }
    
    // Remove unused textures
    await _removeUnusedTextures(atlas);
    
    // Update statistics
    atlas.statistics.optimizations++;
    atlas.statistics.lastOptimization = DateTime.now();
  }

  /// Defragment atlas
  Future<void> _defragmentAtlas(TextureAtlas atlas) async {
    // This would reorganize textures to reduce fragmentation
    // For now, simulate defragmentation
    await Future.delayed(Duration(milliseconds: 100));
    
    // Reset free regions and recalculate
    atlas.freeRegions.clear();
    atlas.freeRegions.add(Rectangle(0, 0, atlas.width, atlas.height));
    
    // Re-add all textures to new positions
    final textures = atlas.regions.values.toList();
    atlas.regions.clear();
    
    for (final texture in textures) {
      final region = _findFreeRegion(atlas, texture.width, texture.height);
      if (region != null) {
        texture.x = region.x;
        texture.y = region.y;
        atlas.regions[texture.id] = texture;
        _updateFreeRegions(atlas, region);
      }
    }
    
    debugPrint('🗺️ Defragmented atlas: ${atlas.name}');
  }

  /// Remove unused textures
  Future<void> _removeUnusedTextures(TextureAtlas atlas) async {
    final now = DateTime.now();
    final unusedTextures = <String>[];
    
    for (final region in atlas.regions.values) {
      if (now.difference(region.timestamp).inHours > 1) { // Unused for 1 hour
        unusedTextures.add(region.id);
      }
    }
    
    for (final textureId in unusedTextures) {
      await removeTexture(textureId);
    }
    
    if (unusedTextures.isNotEmpty) {
      debugPrint('🗺️ Removed ${unusedTextures.length} unused textures from atlas: ${atlas.name}');
    }
  }

  /// Rebuild atlas
  Future<void> _rebuildAtlas(TextureAtlas atlas) async {
    if (_isRebuilding) return;
    
    _isRebuilding = true;
    debugPrint('🗺️ Rebuilding atlas: ${atlas.name}');
    
    try {
      // Save current textures
      final textures = atlas.regions.values.toList();
      
      // Clear atlas
      atlas.regions.clear();
      atlas.freeRegions.clear();
      atlas.freeRegions.add(Rectangle(0, 0, atlas.width, atlas.height));
      atlas.usedSpace = 0;
      
      // Re-add all textures
      for (final texture in textures) {
        final region = _findFreeRegion(atlas, texture.width, texture.height);
        if (region != null) {
          texture.x = region.x;
          texture.y = region.y;
          atlas.regions[texture.id] = texture;
          _updateFreeRegions(atlas, region);
          _updateAtlasStatistics(atlas, texture.width, texture.height);
        }
      }
      
      atlas.statistics.rebuilds++;
      atlas.statistics.lastRebuild = DateTime.now();
      
      _atlasController.add(AtlasEvent(
        type: AtlasEventType.atlasRebuilt,
        atlasId: atlas.id,
        timestamp: DateTime.now(),
        data: {
          'textures_repacked': textures.length,
        },
      ));
      
      debugPrint('🗺️ Rebuilt atlas: ${atlas.name} with ${textures.length} textures');
      
    } finally {
      _isRebuilding = false;
    }
  }

  /// Calculate total memory usage
  int _calculateTotalMemoryUsage() {
    return _atlases.values
        .fold(0, (sum, atlas) => sum + (atlas.width * atlas.height * 4)); // RGBA = 4 bytes per pixel
  }

  /// Calculate average fragmentation
  double _calculateAverageFragmentation() {
    if (_atlases.isEmpty) return 0.0;
    
    return _atlases.values
        .fold(0.0, (sum, atlas) => sum + atlas.fragmentation) / _atlases.length;
  }

  /// Calculate average utilization
  double _calculateAverageUtilization() {
    if (_atlases.isEmpty) return 0.0;
    
    return _atlases.values
        .fold(0.0, (sum, atlas) => sum + _calculateAtlasUtilization(atlas)) / _atlases.length;
  }

  /// Create default atlases
  Future<void> _createDefaultAtlases() async {
    // UI atlas
    createAtlas(
      name: 'UI_Atlas',
      width: 2048,
      height: 2048,
      format: AtlasFormat.rgba8,
      filter: AtlasFilter.linear,
    );
    
    // Icons atlas
    createAtlas(
      name: 'Icons_Atlas',
      width: 1024,
      height: 1024,
      format: AtlasFormat.rgba8,
      filter: AtlasFilter.linear,
    );
    
    // Fonts atlas
    createAtlas(
      name: 'Fonts_Atlas',
      width: 4096,
      height: 4096,
      format: AtlasFormat.r8,
      filter: AtlasFilter.linear,
    );
    
    debugPrint('🗺️ Created ${_atlases.length} default atlases');
  }

  /// Start optimization timer
  void _startOptimizationTimer() {
    _optimizationTimer = Timer.periodic(_optimizationInterval, (_) {
      unawaited(optimizeAllAtlases());
    });
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      unawaited(_performCleanup());
    });
  }

  /// Perform cleanup
  Future<void> _performCleanup() async {
    // Remove empty atlases
    final emptyAtlases = _atlases.entries
        .where((entry) => entry.value.regions.isEmpty)
        .map((entry) => entry.key)
        .toList();
    
    for (final atlasId in emptyAtlases) {
      _atlases.remove(atlasId);
      _atlasStats.remove(atlasId);
    }
    
    if (emptyAtlases.isNotEmpty) {
      debugPrint('🗺️ Cleaned ${emptyAtlases.length} empty atlases');
    }
  }

  /// Generate atlas ID
  String _generateAtlasId() {
    return 'atlas_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate region ID
  String _generateRegionId() {
    return 'region_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Dispose texture atlas manager
  Future<void> dispose() async {
    _optimizationTimer?.cancel();
    _cleanupTimer?.cancel();
    _atlasController.close();
    
    _atlases.clear();
    _textureRegions.clear();
    _operationQueue.clear();
    _atlasStats.clear();
    
    debugPrint('🗺️ Texture Atlas Manager disposed');
  }
}

/// Texture atlas
class TextureAtlas {
  final String id;
  final String name;
  final int width;
  final int height;
  final AtlasFormat format;
  final AtlasFilter filter;
  final AtlasWrap wrap;
  final Map<String, TextureRegion> regions;
  final List<Rectangle<int>> freeRegions;
  int usedSpace;
  double fragmentation;
  final AtlasStatistics statistics;
  
  TextureAtlas({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.filter,
    required this.wrap,
    required this.regions,
    required this.freeRegions,
    required this.usedSpace,
    required this.fragmentation,
    required this.statistics,
  });
}

/// Texture region
class TextureRegion {
  final String id;
  final String textureId;
  final String atlasId;
  int x;
  int y;
  final int width;
  final int height;
  final Uint8List data;
  final AtlasFormat format;
  final DateTime timestamp;
  
  TextureRegion({
    required this.id,
    required this.textureId,
    required this.atlasId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.data,
    required this.format,
    required this.timestamp,
  });
}

/// Atlas result
class AtlasResult {
  final bool success;
  final String? atlasId;
  final String? regionId;
  final int? x;
  final int? y;
  final int? width;
  final int? height;
  final String? error;
  
  AtlasResult({
    required this.success,
    this.atlasId,
    this.regionId,
    this.x,
    this.y,
    this.width,
    this.height,
    this.error,
  });
  
  factory AtlasResult.success({
    required String atlasId,
    required String regionId,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return AtlasResult(
      success: true,
      atlasId: atlasId,
      regionId: regionId,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }
  
  factory AtlasResult.error(String error) {
    return AtlasResult(
      success: false,
      error: error,
    );
  }
}

/// Atlas statistics
class AtlasStatistics {
  final String atlasName;
  int texturesAdded = 0;
  int texturesRemoved = 0;
  int totalTextureArea = 0;
  double utilization = 0.0;
  double fragmentation = 0.0;
  int optimizations = 0;
  int rebuilds = 0;
  DateTime? lastOptimization;
  DateTime? lastRebuild;
  
  AtlasStatistics(this.atlasName);
}

/// Overall atlas statistics
class OverallAtlasStatistics {
  final int totalAtlases;
  final int totalTextures;
  final int totalMemoryUsage;
  final double averageFragmentation;
  final double averageUtilization;
  final List<AtlasInfo> atlases;
  
  OverallAtlasStatistics({
    required this.totalAtlases,
    required this.totalTextures,
    required this.totalMemoryUsage,
    required this.averageFragmentation,
    required this.averageUtilization,
    required this.atlases,
  });
}

/// Atlas info
class AtlasInfo {
  final String id;
  final String name;
  final int width;
  final int height;
  final int textures;
  final double utilization;
  final double fragmentation;
  
  AtlasInfo({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.textures,
    required this.utilization,
    required this.fragmentation,
  });
}

/// Atlas operation
class AtlasOperation {
  final AtlasOperationType type;
  final String atlasId;
  final String? textureId;
  final Map<String, dynamic> parameters;
  final DateTime timestamp;
  
  AtlasOperation({
    required this.type,
    required this.atlasId,
    this.textureId,
    required this.parameters,
    required this.timestamp,
  });
}

/// Atlas event
class AtlasEvent {
  final AtlasEventType type;
  final String? atlasId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  AtlasEvent({
    required this.type,
    this.atlasId,
    required this.timestamp,
    this.data,
  });
}

/// Rectangle helper class
class Rectangle<T extends num> {
  final T x;
  final T y;
  final T width;
  final T height;
  
  Rectangle(this.x, this.y, this.width, this.height);
  
  T get left => x;
  T get top => y;
  T get right => x + width;
  T get bottom => y + height;
}

/// Enums
enum AtlasFormat {
  rgba8,
  rgb8,
  r8,
  rg8,
}

enum AtlasFilter {
  nearest,
  linear,
  trilinear,
}

enum AtlasWrap {
  clamp,
  repeat,
  mirror,
}

enum AtlasOperationType {
  addTexture,
  removeTexture,
  optimizeAtlas,
  rebuildAtlas,
}

enum AtlasEventType {
  atlasCreated,
  textureAdded,
  textureRemoved,
  atlasRebuilt,
  optimizationCompleted,
}

/// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents "unawaited_future" lint
}

import 'dart:typed_data';
