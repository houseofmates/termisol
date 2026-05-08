import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'high_performance_terminal_renderer.dart';
import 'ffi_pty_backend.dart';
import 'compressed_scrollback_buffer.dart';
import 'production_gpu_renderer.dart';
import '../ai/local_ai_fallback.dart';
import '../ai/nvidia_ai_client.dart';
import '../multimedia/multimedia_terminal_renderer.dart';
import '../vr/openxr_vr_terminal.dart';
import '../ui/high_performance_terminal_view.dart';
import 'terminal_session.dart';

/// Termisol Core Integration System
/// 
/// This is the main integration point that ties together all the high-performance
/// components we've built to replace the problematic legacy systems.
class TermisolCoreIntegration {
  static TermisolCoreIntegration? _instance;
  static TermisolCoreIntegration get instance => _instance ??= TermisolCoreIntegration._();
  
  TermisolCoreIntegration._();
  
  // Core components
  late final ProductionGpuRenderer _gpuRenderer;
  late final LocalAiFallback _localAi;
  late final NvidiaAIClient _cloudAi;
  late final OpenXrVrTerminal _vrTerminal;
  
  // Configuration
  late final TermisolCoreConfig _config;
  
  // Performance monitoring
  final Map<String, dynamic> _performanceMetrics = {};
  Timer? _metricsTimer;
  
  // State
  bool _isInitialized = false;
  
  /// Initialize the core integration system
  Future<bool> initialize({TermisolCoreConfig? config}) async {
    if (_isInitialized) return true;
    
    _config = config ?? TermisolCoreConfig.defaultConfig();
    
    try {
      debugPrint('🚀 Initializing Termisol Core Integration...');
      
      // Initialize GPU renderer
      await _initializeGpuRenderer();
      
      // Initialize AI systems
      await _initializeAiSystems();
      
      // Initialize VR if enabled
      if (_config.enableVr) {
        await _initializeVr();
      }
      
      // Start performance monitoring
      _startPerformanceMonitoring();
      
      _isInitialized = true;
      debugPrint('✅ Termisol Core Integration initialized successfully');
      
      return true;
    } catch (e) {
      debugPrint('❌ Core integration failed: $e');
      return false;
    }
  }
  
  /// Create a high-performance terminal session
  Future<TerminalSession> createTerminalSession({
    String? id,
    String? name,
    int maxLines = 50000,
    bool enableMultimedia = true,
    bool enableFfiPty = true,
  }) async {
    if (!_isInitialized) {
      throw StateError('Core integration not initialized');
    }
    
    final sessionId = id ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    final sessionName = name ?? 'Terminal $sessionId';
    
    // Create terminal session with enhanced backend
    final session = TerminalSession(
      id: sessionId,
      name: sessionName,
      maxLines: maxLines,
    );
    
    // Replace backend with FFI version if enabled
    if (enableFfiPty) {
      session._backend = FfiPtyBackend();
    }
    
    // Setup AI handlers
    session.onAiQuery = _handleAiQuery;
    
    debugPrint('📱 Created high-performance terminal session: $sessionId');
    return session;
  }
  
  /// Create high-performance terminal view
  HighPerformanceTerminalView createTerminalView({
    required TerminalSession session,
    bool enableMultimedia = true,
    bool enableGpuAcceleration = true,
  }) {
    // Create appropriate renderer based on configuration
    if (enableMultimedia && _config.enableMultimedia) {
      final renderer = MultimediaTerminalRenderer(
        columns: 80,
        rows: 24,
        gpuRenderer: _gpuRenderer,
        graphicsConfig: _config.graphicsConfig,
      );
      
      return HighPerformanceTerminalView.withCustomRenderer(
        session: session,
        renderer: renderer,
        enableGpuAcceleration: enableGpuAcceleration,
      );
    } else {
      final renderer = HighPerformanceTerminalRenderer(
        columns: 80,
        rows: 24,
        gpuRenderer: _gpuRenderer,
      );
      
      return HighPerformanceTerminalView.withCustomRenderer(
        session: session,
        renderer: renderer,
        enableGpuAcceleration: enableGpuAcceleration,
      );
    }
  }
  
  /// Handle AI queries with fallback support
  Future<String> _handleAiQuery(String query) async {
    try {
      // Try cloud AI first
      if (_config.enableCloudAi && _cloudAi.isInitialized) {
        final response = await _cloudAi.chatCompletion(
          messages: [ChatMessage(role: 'user', content: query)],
        );
        
        if (response.success) {
          _recordMetric('ai_cloud_success', true);
          return response.content;
        }
      }
      
      // Fallback to local AI
      if (_config.enableLocalAi && _localAi._isInitialized) {
        final response = await _localAi.processText(
          input: query,
          capability: LocalAiCapability.textGeneration,
        );
        
        if (response.success) {
          _recordMetric('ai_local_success', true);
          return response.output!;
        }
      }
      
      _recordMetric('ai_failure', true);
      return 'AI services unavailable';
      
    } catch (e) {
      debugPrint('❌ AI query failed: $e');
      _recordMetric('ai_error', true);
      return 'AI query failed: $e';
    }
  }
  
  /// Initialize GPU renderer
  Future<void> _initializeGpuRenderer() async {
    _gpuRenderer = ProductionGpuRenderer.instance;
    
    if (_config.enableGpuAcceleration) {
      _gpuRenderer.setGpuAcceleration(true);
    }
    
    debugPrint('🎮 GPU renderer initialized');
  }
  
  /// Initialize AI systems
  Future<void> _initializeAiSystems() async {
    // Initialize local AI fallback
    if (_config.enableLocalAi) {
      _localAi = LocalAiFallback();
      await _localAi.initialize();
      debugPrint('🤖 Local AI fallback initialized');
    }
    
    // Initialize cloud AI
    if (_config.enableCloudAi) {
      _cloudAi = NvidiaAIClient();
      await _cloudAi.initialize();
      debugPrint('☁️ Cloud AI initialized');
    }
  }
  
  /// Initialize VR system
  Future<void> _initializeVr() async {
    _vrTerminal = OpenXrVrTerminal();
    final success = await _vrTerminal.initialize();
    
    if (success) {
      debugPrint('🥽 VR terminal initialized');
    } else {
      debugPrint('⚠️ VR initialization failed');
    }
  }
  
  /// Start VR session
  Future<bool> startVrSession() async {
    if (!_config.enableVr || _vrTerminal.sessionRunning) {
      return _vrTerminal.sessionRunning;
    }
    
    return await _vrTerminal.startSession();
  }
  
  /// Stop VR session
  Future<void> stopVrSession() async {
    if (_config.enableVr) {
      await _vrTerminal.stopSession();
    }
  }
  
  /// Get VR status
  VrStatus getVrStatus() {
    if (_config.enableVr) {
      return _vrTerminal.getVrStatus();
    }
    return VrStatus(
      isInitialized: false,
      sessionRunning: false,
      deviceInfo: null,
      frameRate: 0.0,
      droppedFrames: 0,
      controllers: {},
      handTrackingActive: false,
      eyeTrackingActive: false,
    );
  }
  
  /// Start performance monitoring
  void _startPerformanceMonitoring() {
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updatePerformanceMetrics();
    });
  }
  
  /// Update performance metrics
  void _updatePerformanceMetrics() {
    _performanceMetrics['timestamp'] = DateTime.now().toIso8601String();
    _performanceMetrics['gpu_frame_rate'] = _gpuRenderer.currentFrameRate;
    _performanceMetrics['gpu_acceleration'] = _gpuRenderer.gpuAccelerationEnabled;
    
    if (_config.enableLocalAi) {
      _performanceMetrics['local_ai_status'] = _localAi.getStatus();
    }
    
    if (_config.enableVr) {
      _performanceMetrics['vr_status'] = getVrStatus();
    }
    
    // Log performance warnings
    _checkPerformanceWarnings();
  }
  
  /// Check for performance warnings
  void _checkPerformanceWarnings() {
    final frameRate = _performanceMetrics['gpu_frame_rate'] as double? ?? 0.0;
    
    if (frameRate < 30.0) {
      debugPrint('⚠️ Low frame rate detected: ${frameRate.toStringAsFixed(1)}fps');
    }
    
    if (_performanceMetrics.containsKey('ai_failure')) {
      final failures = _performanceMetrics['ai_failure'] as int? ?? 0;
      if (failures > 5) {
        debugPrint('⚠️ High AI failure rate detected: $failures failures');
      }
    }
  }
  
  /// Record performance metric
  void _recordMetric(String metric, dynamic value) {
    _performanceMetrics[metric] = value;
    _performanceMetrics['last_${metric}_timestamp'] = DateTime.now().toIso8601String();
  }
  
  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return Map.unmodifiable(_performanceMetrics);
  }
  
  /// Optimize performance based on current metrics
  Future<void> optimizePerformance() async {
    debugPrint('🔧 Optimizing performance...');
    
    final frameRate = _gpuRenderer.currentFrameRate;
    
    if (frameRate < 30.0) {
      // Reduce GPU quality
      _gpuRenderer.setGpuAcceleration(false);
      _recordMetric('gpu_optimization_applied', 'reduced_quality');
    } else if (frameRate > 60.0) {
      // Can enable higher quality
      _gpuRenderer.setGpuAcceleration(true);
      _recordMetric('gpu_optimization_applied', 'high_quality');
    }
    
    // Clear caches if memory usage is high
    final memoryStats = _gpuRenderer.getMemoryStats();
    final estimatedMemory = memoryStats['estimatedMemoryUsage'] as int? ?? 0;
    
    if (estimatedMemory > 100 * 1024 * 1024) { // 100MB
      _gpuRenderer.clearCaches();
      _recordMetric('gpu_optimization_applied', 'cache_cleared');
    }
    
    debugPrint('✅ Performance optimization completed');
  }
  
  /// Get system status
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _isInitialized,
      'config': _config.toJson(),
      'performance': getPerformanceMetrics(),
      'gpu_renderer': {
        'acceleration_enabled': _gpuRenderer.gpuAccelerationEnabled,
        'frame_rate': _gpuRenderer.currentFrameRate,
        'memory_stats': _gpuRenderer.getMemoryStats(),
      },
      'ai': {
        'local_enabled': _config.enableLocalAi,
        'cloud_enabled': _config.enableCloudAi,
        'local_status': _config.enableLocalAi ? _localAi.getStatus() : null,
        'cloud_status': _config.enableCloudAi ? _cloudAi.getMetrics() : null,
      },
      'vr': {
        'enabled': _config.enableVr,
        'status': _config.enableVr ? getVrStatus() : null,
      },
    };
  }
  
  /// Dispose all resources
  Future<void> dispose() async {
    debugPrint('🗑️ Disposing Termisol Core Integration...');
    
    _metricsTimer?.cancel();
    
    await _gpuRenderer.dispose();
    await _localAi.dispose();
    await _cloudAi.dispose();
    await _vrTerminal.dispose();
    
    _isInitialized = false;
    debugPrint('✅ Core integration disposed');
  }
}

/// Configuration for Termisol core
class TermisolCoreConfig {
  final bool enableGpuAcceleration;
  final bool enableMultimedia;
  final bool enableVr;
  final bool enableLocalAi;
  final bool enableCloudAi;
  final GraphicsConfig graphicsConfig;
  
  const TermisolCoreConfig({
    required this.enableGpuAcceleration,
    required this.enableMultimedia,
    required this.enableVr,
    required this.enableLocalAi,
    required this.enableCloudAi,
    required this.graphicsConfig,
  });
  
  factory TermisolCoreConfig.defaultConfig() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: true,
      enableMultimedia: true,
      enableVr: false, // Disabled by default due to hardware requirements
      enableLocalAi: true,
      enableCloudAi: true,
      graphicsConfig: GraphicsConfig(
        enableSixel: true,
        enableKitty: true,
        enableIterm: true,
        maxCacheSize: 50,
        maxImageSize: 5 * 1024 * 1024,
        enableAnimations: true,
      ),
    );
  }
  
  factory TermisolCoreConfig.highPerformance() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: true,
      enableMultimedia: true,
      enableVr: false,
      enableLocalAi: true,
      enableCloudAi: true,
      graphicsConfig: GraphicsConfig(
        enableSixel: true,
        enableKitty: true,
        enableIterm: true,
        maxCacheSize: 100,
        maxImageSize: 10 * 1024 * 1024,
        enableAnimations: true,
      ),
    );
  }
  
  factory TermisolCoreConfig.lowMemory() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: false,
      enableMultimedia: false,
      enableVr: false,
      enableLocalAi: true,
      enableCloudAi: false,
      graphicsConfig: GraphicsConfig(
        enableSixel: false,
        enableKitty: false,
        enableIterm: false,
        maxCacheSize: 10,
        maxImageSize: 1024 * 1024,
        enableAnimations: false,
      ),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enableGpuAcceleration': enableGpuAcceleration,
      'enableMultimedia': enableMultimedia,
      'enableVr': enableVr,
      'enableLocalAi': enableLocalAi,
      'enableCloudAi': enableCloudAi,
      'graphicsConfig': {
        'enableSixel': graphicsConfig.enableSixel,
        'enableKitty': graphicsConfig.enableKitty,
        'enableIterm': graphicsConfig.enableIterm,
        'maxCacheSize': graphicsConfig.maxCacheSize,
        'maxImageSize': graphicsConfig.maxImageSize,
        'enableAnimations': graphicsConfig.enableAnimations,
      },
    };
  }
}
