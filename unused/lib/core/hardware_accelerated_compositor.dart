import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Hardware-Accelerated Compositor - GPU-accelerated rendering pipeline
class HardwareAcceleratedCompositor {
  static final HardwareAcceleratedCompositor _instance = HardwareAcceleratedCompositor._internal();
  factory HardwareAcceleratedCompositor() => _instance;
  HardwareAcceleratedCompositor._internal();

  bool _isInitialized = false;
  bool _hardwareAccelerationEnabled = true;
  CompositorBackend _backend = CompositorBackend.opengl;
  final Map<String, CompositorLayer> _layers = {};
  final Queue<CompositorFrame> _frameHistory = Queue();
  final Map<String, TexturePool> _texturePools = {};
  
  static const int _maxFrameHistory = 60; // Keep 60 frames of history
  static const int _maxLayers = 1000;
  static const Duration _frameInterval = Duration(milliseconds: 16); // 60 FPS
  
  CompositorPerformanceMetrics _performanceMetrics = CompositorPerformanceMetrics();
  final _compositorController = StreamController<CompositorEvent>.broadcast();
  Stream<CompositorEvent> get events => _compositorController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get hardwareAccelerationEnabled => _hardwareAccelerationEnabled;
  CompositorBackend get backend => _backend;
  CompositorPerformanceMetrics get performanceMetrics => _performanceMetrics;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _detectHardwareCapabilities();
    await _initializeBackend();
    await _initializeTexturePools();
    _startFrameProcessing();
    
    _isInitialized = true;
    debugPrint('🚀 Hardware-Accelerated Compositor initialized');
  }

  Future<CompositorResult> createLayer({
    required String layerId,
    required Size size,
    LayerType type = LayerType.content,
    bool transparent = false,
    BlendMode blendMode = BlendMode.srcOver,
    int? zIndex,
  }) async {
    try {
      if (_layers.length >= _maxLayers) {
        return CompositorResult.error('Maximum number of layers reached');
      }
      
      final layer = CompositorLayer(
        id: layerId,
        size: size,
        type: type,
        transparent: transparent,
        blendMode: blendMode,
        zIndex: zIndex ?? _layers.length,
        texture: await _allocateTexture(size, type),
        created: DateTime.now(),
      );
      
      _layers[layerId] = layer;
      
      _compositorController.add(CompositorEvent(
        type: CompositorEventType.layerCreated,
        data: {
          'layer_id': layerId,
          'type': type.toString(),
          'size': '${size.width}x${size.height}',
        },
      ));
      
      return CompositorResult.success(layer);
      
    } catch (e) {
      debugPrint('❌ Failed to create layer: $e');
      return CompositorResult.error(e.toString());
    }
  }

  Future<CompositorResult> updateLayer({
    required String layerId,
    required Widget content,
    Rect? dirtyRegion,
  }) async {
    try {
      final layer = _layers[layerId];
      if (layer == null) {
        return CompositorResult.error('Layer not found: $layerId');
      }
      
      final stopwatch = Stopwatch()..start();
      
      // Render content to texture
      await _renderContentToTexture(layer, content, dirtyRegion);
      
      stopwatch.stop();
      layer.lastUpdated = DateTime.now();
      layer.renderTime = stopwatch.elapsedMicroseconds;
      
      _compositorController.add(CompositorEvent(
        type: CompositorEventType.layerUpdated,
        data: {
          'layer_id': layerId,
          'render_time_us': layer.renderTime,
          'dirty_region': dirtyRegion?.toString(),
        },
      ));
      
      return CompositorResult.success(layer);
      
    } catch (e) {
      debugPrint('❌ Failed to update layer: $e');
      return CompositorResult.error(e.toString());
    }
  }

  Future<CompositorResult> removeLayer(String layerId) async {
    try {
      final layer = _layers.remove(layerId);
      if (layer == null) {
        return CompositorResult.error('Layer not found: $layerId');
      }
      
      // Release texture back to pool
      await _releaseTexture(layer.texture);
      
      _compositorController.add(CompositorEvent(
        type: CompositorEventType.layerRemoved,
        data: {
          'layer_id': layerId,
        },
      ));
      
      return CompositorResult.success(layer);
      
    } catch (e) {
      debugPrint('❌ Failed to remove layer: $e');
      return CompositorResult.error(e.toString());
    }
  }

  Future<CompositorFrame> compositeFrame({
    required Size viewportSize,
    List<String>? layerOrder,
    bool enableCulling = true,
    bool enableBatching = true,
  }) async {
    final frameStart = Stopwatch()..start();
    
    try {
      // Collect visible layers
      final layers = _collectVisibleLayers(viewportSize, layerOrder, enableCulling);
      
      // Sort by z-index
      layers.sort((a, b) => a.zIndex.compareTo(b.zIndex));
      
      // Batch compatible layers
      final batches = enableBatching ? _batchCompatibleLayers(layers) : [layers];
      
      // Execute compositing
      final compositedTexture = await _executeCompositing(batches, viewportSize);
      
      frameStart.stop();
      
      final frame = CompositorFrame(
        timestamp: DateTime.now(),
        texture: compositedTexture,
        layers: layers,
        batches: batches.length,
        renderTime: frameStart.elapsedMicroseconds,
        viewportSize: viewportSize,
      );
      
      // Update frame history
      _frameHistory.add(frame);
      if (_frameHistory.length > _maxFrameHistory) {
        _frameHistory.removeFirst();
      }
      
      // Update performance metrics
      _updatePerformanceMetrics(frame);
      
      _compositorController.add(CompositorEvent(
        type: CompositorEventType.frameComposited,
        data: {
          'render_time_us': frame.renderTime,
          'layers_count': layers.length,
          'batches_count': batches.length,
        },
      ));
      
      return frame;
      
    } catch (e) {
      debugPrint('❌ Frame compositing failed: $e');
      
      // Return fallback frame
      return CompositorFrame(
        timestamp: DateTime.now(),
        texture: CompositorTexture.fallback(viewportSize),
        layers: [],
        batches: 0,
        renderTime: frameStart.elapsedMicroseconds,
        viewportSize: viewportSize,
        error: e.toString(),
      );
    }
  }

  Future<void> setBackend(CompositorBackend backend) async {
    if (_backend == backend) return;
    
    try {
      // Dispose current backend
      await _disposeBackend();
      
      // Initialize new backend
      _backend = backend;
      await _initializeBackend();
      
      // Recreate texture pools
      await _initializeTexturePools();
      
      _compositorController.add(CompositorEvent(
        type: CompositorEventType.backendChanged,
        data: {
          'backend': backend.toString(),
        },
      ));
      
      debugPrint('🚀 Compositor backend changed to: $backend');
      
    } catch (e) {
      debugPrint('❌ Failed to change backend: $e');
    }
  }

  Future<void> setHardwareAcceleration(bool enabled) async {
    if (_hardwareAccelerationEnabled == enabled) return;
    
    _hardwareAccelerationEnabled = enabled;
    
    if (!enabled) {
      await _disableHardwareAcceleration();
    } else {
      await _enableHardwareAcceleration();
    }
    
    _compositorController.add(CompositorEvent(
      type: CompositorEventType.accelerationChanged,
      data: {
        'enabled': enabled,
      },
    ));
    
    debugPrint('🚀 Hardware acceleration ${enabled ? 'enabled' : 'disabled'}');
  }

  List<CompositorLayer> getLayers() {
    return _layers.values.toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  List<CompositorFrame> getFrameHistory({int? count}) {
    final frames = _frameHistory.toList().reversed.toList();
    return count != null ? frames.take(count).toList() : frames;
  }

  Future<void> _detectHardwareCapabilities() async {
    // Simulate hardware capability detection
    final hasOpenGL = true; // Would check actual GPU capabilities
    final hasVulkan = false; // Would check Vulkan support
    final hasMetal = false; // Would check Metal support (macOS)
    final hasDirectX = false; // Would check DirectX support (Windows)
    
    // Select best available backend
    if (hasVulkan) {
      _backend = CompositorBackend.vulkan;
    } else if (hasMetal) {
      _backend = CompositorBackend.metal;
    } else if (hasDirectX) {
      _backend = CompositorBackend.directx;
    } else if (hasOpenGL) {
      _backend = CompositorBackend.opengl;
    } else {
      _backend = CompositorBackend.software;
      _hardwareAccelerationEnabled = false;
    }
    
    debugPrint('🔍 Hardware capabilities detected: backend=$_backend, acceleration=$_hardwareAccelerationEnabled');
  }

  Future<void> _initializeBackend() async {
    // Simulate backend initialization
    await Future.delayed(Duration(milliseconds: 10));
    
    switch (_backend) {
      case CompositorBackend.opengl:
        debugPrint('🎨 Initializing OpenGL backend');
        break;
      case CompositorBackend.vulkan:
        debugPrint('🎨 Initializing Vulkan backend');
        break;
      case CompositorBackend.metal:
        debugPrint('🎨 Initializing Metal backend');
        break;
      case CompositorBackend.directx:
        debugPrint('🎨 Initializing DirectX backend');
        break;
      case CompositorBackend.software:
        debugPrint('🎨 Initializing software backend');
        break;
    }
  }

  Future<void> _disposeBackend() async {
    // Simulate backend disposal
    await Future.delayed(Duration(milliseconds: 5));
    debugPrint('🎨 Disposing ${_backend.toString()} backend');
  }

  Future<void> _initializeTexturePools() async {
    // Create texture pools for different layer types
    for (final type in LayerType.values) {
      _texturePools[type.toString()] = TexturePool(
        type: type,
        availableTextures: Queue(),
        allocatedTextures: 0,
        maxTextures: 100,
      );
    }
    
    debugPrint('🎨 Initialized ${_texturePools.length} texture pools');
  }

  Future<CompositorTexture> _allocateTexture(Size size, LayerType type) async {
    final pool = _texturePools[type.toString()];
    
    if (pool != null && pool.availableTextures.isNotEmpty) {
      // Reuse existing texture
      final texture = pool.availableTextures.removeFirst();
      texture.reset(size);
      return texture;
    }
    
    // Create new texture
    final texture = CompositorTexture(
      id: 'texture_${DateTime.now().millisecondsSinceEpoch}',
      size: size,
      type: type,
      backend: _backend,
    );
    
    if (pool != null) {
      pool.allocatedTextures++;
    }
    
    return texture;
  }

  Future<void> _releaseTexture(CompositorTexture texture) async {
    final pool = _texturePools[texture.type.toString()];
    
    if (pool != null && pool.allocatedTextures > pool.maxTextures / 2) {
      // Return to pool if not too many are allocated
      pool.availableTextures.add(texture);
    } else {
      // Dispose excess textures
      await texture.dispose();
      if (pool != null) {
        pool.allocatedTextures--;
      }
    }
  }

  Future<void> _renderContentToTexture(
    CompositorLayer layer,
    Widget content,
    Rect? dirtyRegion,
  ) async {
    // Simulate content rendering to texture
    await Future.delayed(Duration(microseconds: layer.renderTime ?? 1000));
    
    // In a real implementation, this would:
    // 1. Create a render target with the texture
    // 2. Render the widget to the texture
    // 3. Handle dirty regions for partial updates
    // 4. Apply proper blending and transparency
    
    layer.texture.markDirty(dirtyRegion);
  }

  List<CompositorLayer> _collectVisibleLayers(
    Size viewportSize,
    List<String>? layerOrder,
    bool enableCulling,
  ) {
    final layers = <CompositorLayer>[];
    
    for (final layerId in layerOrder ?? _layers.keys) {
      final layer = _layers[layerId];
      if (layer == null) continue;
      
      // Frustum culling (simple bounds check)
      if (enableCulling && !_isLayerVisible(layer, viewportSize)) {
        continue;
      }
      
      layers.add(layer);
    }
    
    return layers;
  }

  bool _isLayerVisible(CompositorLayer layer, Size viewportSize) {
    // Simple visibility check - in reality would be more sophisticated
    return layer.size.width > 0 && layer.size.height > 0;
  }

  List<List<CompositorLayer>> _batchCompatibleLayers(List<CompositorLayer> layers) {
    final batches = <List<CompositorLayer>>[];
    final currentBatch = <CompositorLayer>[];
    
    for (final layer in layers) {
      if (currentBatch.isEmpty || _canBatchWith(currentBatch.last, layer)) {
        currentBatch.add(layer);
      } else {
        if (currentBatch.isNotEmpty) {
          batches.add(List.from(currentBatch));
          currentBatch.clear();
        }
        currentBatch.add(layer);
      }
      
      // Limit batch size
      if (currentBatch.length >= 10) {
        batches.add(List.from(currentBatch));
        currentBatch.clear();
      }
    }
    
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }
    
    return batches;
  }

  bool _canBatchWith(CompositorLayer layer1, CompositorLayer layer2) {
    // Layers can be batched if they have compatible properties
    return layer1.blendMode == layer2.blendMode &&
           layer1.transparent == layer2.transparent &&
           layer1.type == layer2.type;
  }

  Future<CompositorTexture> _executeCompositing(
    List<List<CompositorLayer>> batches,
    Size viewportSize,
  ) async {
    // Simulate GPU compositing
    await Future.delayed(Duration(microseconds: 500));
    
    // Create composited texture
    final compositedTexture = CompositorTexture(
      id: 'composited_${DateTime.now().millisecondsSinceEpoch}',
      size: viewportSize,
      type: LayerType.composite,
      backend: _backend,
    );
    
    // In a real implementation, this would:
    // 1. Set up GPU render pipeline
    // 2. Render each batch with appropriate blending
    // 3. Handle layer transformations
    // 4. Apply post-processing effects
    
    return compositedTexture;
  }

  void _updatePerformanceMetrics(CompositorFrame frame) {
    _performanceMetrics.totalFrames++;
    _performanceMetrics.totalRenderTime += frame.renderTime;
    _performanceMetrics.averageRenderTime = _performanceMetrics.totalRenderTime / _performanceMetrics.totalFrames;
    _performanceMetrics.layersComposited += frame.layers.length;
    _performanceMetrics.batchesComposited += frame.batches;
    
    // Calculate FPS
    if (_frameHistory.length >= 2) {
      final recentFrames = _frameHistory.takeLast(30).toList();
      final timeSpan = recentFrames.last.timestamp.difference(recentFrames.first.timestamp);
      _performanceMetrics.currentFPS = recentFrames.length / timeSpan.inSeconds;
    }
    
    // Update texture pool statistics
    for (final pool in _texturePools.values) {
      _performanceMetrics.totalTextures += pool.allocatedTextures;
      _performanceMetrics.availableTextures += pool.availableTextures.length;
    }
  }

  void _startFrameProcessing() {
    Timer.periodic(_frameInterval, (_) {
      if (_isInitialized && _layers.isNotEmpty) {
        // Auto-composite if there are active layers
        // In a real implementation, this would be driven by the display refresh
      }
    });
  }

  Future<void> _enableHardwareAcceleration() async {
    await _detectHardwareCapabilities();
    await _initializeBackend();
  }

  Future<void> _disableHardwareAcceleration() async {
    await _disposeBackend();
    _backend = CompositorBackend.software;
    await _initializeBackend();
  }

  Map<String, dynamic> getStatistics() {
    return {
      'hardware_acceleration_enabled': _hardwareAccelerationEnabled,
      'backend': _backend.toString(),
      'active_layers': _layers.length,
      'frame_history': _frameHistory.length,
      'performance_metrics': _performanceMetrics.toJson(),
      'texture_pools': _texturePools.map((key, pool) => MapEntry(key, {
        'allocated': pool.allocatedTextures,
        'available': pool.availableTextures.length,
        'max': pool.maxTextures,
      })),
    };
  }

  Future<void> dispose() async {
    await _disposeBackend();
    
    // Dispose all layers
    for (final layer in _layers.values) {
      await _releaseTexture(layer.texture);
    }
    _layers.clear();
    
    // Dispose texture pools
    for (final pool in _texturePools.values) {
      for (final texture in pool.availableTextures) {
        await texture.dispose();
      }
    }
    _texturePools.clear();
    
    _frameHistory.clear();
    _compositorController.close();
    _isInitialized = false;
    
    debugPrint('🚀 Hardware-Accelerated Compositor disposed');
  }
}

/// Data classes
class CompositorLayer {
  final String id;
  final Size size;
  final LayerType type;
  final bool transparent;
  final BlendMode blendMode;
  final int zIndex;
  final CompositorTexture texture;
  final DateTime created;
  DateTime? lastUpdated;
  int? renderTime;
  
  CompositorLayer({
    required this.id,
    required this.size,
    required this.type,
    required this.transparent,
    required this.blendMode,
    required this.zIndex,
    required this.texture,
    required this.created,
  });
}

class CompositorTexture {
  final String id;
  Size size;
  final LayerType type;
  final CompositorBackend backend;
  Rect? dirtyRegion;
  bool isDirty = false;
  
  CompositorTexture({
    required this.id,
    required this.size,
    required this.type,
    required this.backend,
  });
  
  void reset(Size newSize) {
    size = newSize;
    dirtyRegion = null;
    isDirty = false;
  }
  
  void markDirty(Rect? region) {
    dirtyRegion = region;
    isDirty = true;
  }
  
  Future<void> dispose() async {
    // Simulate texture disposal
    await Future.delayed(Duration(microseconds: 100));
  }
  
  factory CompositorTexture.fallback(Size size) {
    return CompositorTexture(
      id: 'fallback',
      size: size,
      type: LayerType.content,
      backend: CompositorBackend.software,
    );
  }
}

class CompositorFrame {
  final DateTime timestamp;
  final CompositorTexture texture;
  final List<CompositorLayer> layers;
  final int batches;
  final int renderTime;
  final Size viewportSize;
  final String? error;
  
  CompositorFrame({
    required this.timestamp,
    required this.texture,
    required this.layers,
    required this.batches,
    required this.renderTime,
    required this.viewportSize,
    this.error,
  });
  
  bool get hasError => error != null;
  double get renderTimeMs => renderTime / 1000.0;
}

class CompositorPerformanceMetrics {
  int totalFrames = 0;
  int totalRenderTime = 0;
  double averageRenderTime = 0.0;
  double currentFPS = 0.0;
  int layersComposited = 0;
  int batchesComposited = 0;
  int totalTextures = 0;
  int availableTextures = 0;
  
  Map<String, dynamic> toJson() => {
    'total_frames': totalFrames,
    'average_render_time_us': averageRenderTime,
    'current_fps': currentFPS,
    'layers_composited': layersComposited,
    'batches_composited': batchesComposited,
    'total_textures': totalTextures,
    'available_textures': availableTextures,
  };
}

class TexturePool {
  final LayerType type;
  final Queue<CompositorTexture> availableTextures;
  int allocatedTextures;
  final int maxTextures;
  
  TexturePool({
    required this.type,
    required this.availableTextures,
    required this.allocatedTextures,
    required this.maxTextures,
  });
}

class CompositorResult {
  final bool success;
  final CompositorLayer? layer;
  final String? error;
  
  CompositorResult({
    required this.success,
    this.layer,
    this.error,
  });
  
  factory CompositorResult.success(CompositorLayer layer) {
    return CompositorResult(
      success: true,
      layer: layer,
    );
  }
  
  factory CompositorResult.error(String error) {
    return CompositorResult(
      success: false,
      error: error,
    );
  }
}

class CompositorEvent {
  final CompositorEventType type;
  final Map<String, dynamic>? data;
  
  CompositorEvent({
    required this.type,
    this.data,
  });
}

enum LayerType {
  content,
  overlay,
  background,
  composite,
  effect,
}

enum BlendMode {
  srcOver,
  srcIn,
  srcOut,
  srcAtop,
  dstOver,
  dstIn,
  dstOut,
  dstAtop,
  xor,
  plus,
  modulate,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
}

enum CompositorBackend {
  opengl,
  vulkan,
  metal,
  directx,
  software,
}

enum CompositorEventType {
  layerCreated,
  layerUpdated,
  layerRemoved,
  frameComposited,
  backendChanged,
  accelerationChanged,
}
