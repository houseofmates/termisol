import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Cross-Platform Optimizer for Termisol
/// 
/// Provides platform-specific optimizations for:
/// - Ubuntu 24.04.3 (house@192.168.4.250)
/// - Android (Google Pixel 10 Pro)
/// - Oculus Quest 2 VR
/// - Windows 11
class CrossPlatformOptimizer {
  static CrossPlatformOptimizer? _instance;
  static CrossPlatformOptimizer get instance {
    _instance ??= CrossPlatformOptimizer._();
    return _instance!;
  }

  CrossPlatformOptimizer._() {
    _initialize();
  }

  // Platform detection
  PlatformType _platformType = PlatformType.unknown;
  bool _isHighEndDevice = false;
  bool _hasGPUAcceleration = false;
  bool _isVRDevice = false;
  
  // Optimization settings
  final Map<String, dynamic> _optimizationSettings = {};
  final StreamController<OptimizationEvent> _eventController = 
      StreamController<OptimizationEvent>.broadcast();
  
  Timer? _optimizationTimer;
  bool _isOptimized = false;
  
  /// Stream of optimization events
  Stream<OptimizationEvent> get events => _eventController.stream;
  
  /// Current platform type
  PlatformType get platformType => _platformType;
  
  /// Optimization status
  bool get isOptimized => _isOptimized;
  
  /// Initialize cross-platform optimizer
  Future<void> _initialize() async {
    try {
      await _detectPlatform();
      await _detectHardwareCapabilities();
      await _applyPlatformSpecificOptimizations();
      
      debugPrint('Cross-Platform Optimizer initialized');
      debugPrint('Platform: ${_platformType.toString()}');
      debugPrint('High-end device: $_isHighEndDevice');
      debugPrint('GPU acceleration: $_hasGPUAcceleration');
      debugPrint('VR device: $_isVRDevice');
    } catch (e) {
      debugPrint('Failed to initialize cross-platform optimizer: $e');
    }
  }
  
  /// Detect current platform
  Future<void> _detectPlatform() async {
    if (Platform.isLinux) {
      _platformType = PlatformType.linux;
      await _detectLinuxDistribution();
    } else if (Platform.isAndroid) {
      _platformType = PlatformType.android;
      await _detectAndroidDevice();
    } else if (Platform.isWindows) {
      _platformType = PlatformType.windows;
      await _detectWindowsVersion();
    } else if (Platform.isIOS) {
      _platformType = PlatformType.ios;
      await _detectIOSDevice();
    } else {
      _platformType = PlatformType.unknown;
    }
  }
  
  /// Detect Linux distribution
  Future<void> _detectLinuxDistribution() async {
    try {
      // Check for Ubuntu 24.04
      final osRelease = File('/etc/os-release');
      if (await osRelease.exists()) {
        final content = await osRelease.readAsString();
        if (content.contains('Ubuntu') && content.contains('24.04')) {
          debugPrint('Ubuntu 24.04 detected');
          _platformType = PlatformType.ubuntu2404;
        }
      }
      
      // Check for NVIDIA GPU
      final nvidiaSmi = await Process.run('nvidia-smi', []);
      if (nvidiaSmi.exitCode == 0) {
        _hasGPUAcceleration = true;
        debugPrint('NVIDIA GPU detected');
      }
    } catch (e) {
      debugPrint('Failed to detect Linux distribution: $e');
    }
  }
  
  /// Detect Android device
  Future<void> _detectAndroidDevice() async {
    try {
      // Check for Pixel 10 Pro
      final buildProp = File('/system/build.prop');
      if (await buildProp.exists()) {
        final content = await buildProp.readAsString();
        if (content.contains('pixel') && content.contains('10')) {
          debugPrint('Google Pixel 10 Pro detected');
          _isHighEndDevice = true;
        }
      }
      
      // Check for Quest 2
      final questModel = Platform.environment['OCULUS_VR'] ?? '';
      if (questModel.contains('Quest') || questModel.contains('Monterey')) {
        debugPrint('Oculus Quest 2 detected');
        _platformType = PlatformType.quest2;
        _isVRDevice = true;
      }
      
      // Check for GPU acceleration
      _hasGPUAcceleration = true; // Most modern Android devices have GPU
    } catch (e) {
      debugPrint('Failed to detect Android device: $e');
    }
  }
  
  /// Detect Windows version
  Future<void> _detectWindowsVersion() async {
    try {
      final result = await Process.run('ver', []);
      final output = result.stdout as String;
      
      if (output.contains('10.0') || output.contains('11')) {
        debugPrint('Windows 11 detected');
        _platformType = PlatformType.windows11;
      }
      
      // Check for GPU acceleration
      final dxdiag = await Process.run('dxdiag', ['/t', '0']);
      if (dxdiag.exitCode == 0) {
        _hasGPUAcceleration = true;
        debugPrint('DirectX GPU detected');
      }
    } catch (e) {
      debugPrint('Failed to detect Windows version: $e');
    }
  }
  
  /// Detect iOS device
  Future<void> _detectIOSDevice() async {
    try {
      // iOS device detection would go here
      debugPrint('iOS device detected');
      _hasGPUAcceleration = true;
    } catch (e) {
      debugPrint('Failed to detect iOS device: $e');
    }
  }
  
  /// Detect hardware capabilities
  Future<void> _detectHardwareCapabilities() async {
    try {
      // CPU cores
      final cpuCores = Platform.numberOfProcessors;
      _isHighEndDevice = _isHighEndDevice || cpuCores >= 8;
      
      // Memory detection
      final totalMemory = await _getTotalMemory();
      _isHighEndDevice = _isHighEndDevice || totalMemory >= 8 * 1024 * 1024 * 1024; // 8GB+
      
      // Platform-specific high-end detection
      switch (_platformType) {
        case PlatformType.ubuntu2404:
          _isHighEndDevice = _isHighEndDevice || _hasGPUAcceleration;
          break;
        case PlatformType.android:
          _isHighEndDevice = _isHighEndDevice || _hasGPUAcceleration;
          break;
        case PlatformType.quest2:
          _isHighEndDevice = true; // Quest 2 is considered high-end for VR
          break;
        case PlatformType.windows11:
          _isHighEndDevice = _isHighEndDevice || _hasGPUAcceleration;
          break;
        default:
          break;
      }
      
      debugPrint('Hardware capabilities detected');
      debugPrint('CPU cores: $cpuCores');
      debugPrint('Total memory: ${(totalMemory / 1024 / 1024 / 1024).toStringAsFixed(1)}GB');
    } catch (e) {
      debugPrint('Failed to detect hardware capabilities: $e');
    }
  }
  
  /// Get total memory in bytes
  Future<int> _getTotalMemory() async {
    try {
      if (Platform.isLinux) {
        final meminfo = File('/proc/meminfo');
        if (await meminfo.exists()) {
          final content = await meminfo.readAsString();
          final lines = content.split('\n');
          
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final parts = line.split(RegExp(r'\s+'));
              final kb = int.parse(parts[1]);
              return kb * 1024; // Convert to bytes
            }
          }
        }
      }
      
      // Fallback estimation
      return _isHighEndDevice ? 16 * 1024 * 1024 * 1024 : 8 * 1024 * 1024 * 1024;
    } catch (e) {
      debugPrint('Failed to get total memory: $e');
      return 8 * 1024 * 1024 * 1024; // 8GB fallback
    }
  }
  
  /// Apply platform-specific optimizations
  Future<void> _applyPlatformSpecificOptimizations() async {
    try {
      switch (_platformType) {
        case PlatformType.ubuntu2404:
          await _applyUbuntuOptimizations();
          break;
        case PlatformType.android:
          await _applyAndroidOptimizations();
          break;
        case PlatformType.quest2:
          await _applyQuest2Optimizations();
          break;
        case PlatformType.windows11:
          await _applyWindowsOptimizations();
          break;
        default:
          await _applyGenericOptimizations();
          break;
      }
      
      _isOptimized = true;
      
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.optimizationsApplied,
        platform: _platformType,
        settings: _optimizationSettings,
        timestamp: DateTime.now(),
      ));
      
      debugPrint('Platform-specific optimizations applied');
    } catch (e) {
      debugPrint('Failed to apply platform-specific optimizations: $e');
    }
  }
  
  /// Apply Ubuntu 24.04 optimizations
  Future<void> _applyUbuntuOptimizations() async {
    debugPrint('Applying Ubuntu 24.04 optimizations...');
    
    // Image cache optimizations
    final imageCache = PaintingBinding.instance.imageCache;
    if (_isHighEndDevice) {
      imageCache.maximumSize = 200;
      imageCache.maximumSizeBytes = 100 * 1024 * 1024; // 100MB
    } else {
      imageCache.maximumSize = 100;
      imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
    }
    
    // System optimizations
    _optimizationSettings['preferOpenGL'] = true;
    _optimizationSettings['enableVulkan'] = _hasGPUAcceleration;
    _optimizationSettings['maxConcurrentOperations'] = _isHighEndDevice ? 16 : 8;
    _optimizationSettings['enableGPUAcceleration'] = _hasGPUAcceleration;
    
    // Ubuntu-specific settings
    _optimizationSettings['useNativeFileDialogs'] = true;
    _optimizationSettings['enableSystemIntegration'] = true;
    _optimizationSettings['preferDarkTheme'] = true;
    
    debugPrint('Ubuntu optimizations applied');
  }
  
  /// Apply Android optimizations
  Future<void> _applyAndroidOptimizations() async {
    debugPrint('Applying Android optimizations...');
    
    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    
    // Immersive mode for full screen
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // Image cache optimizations (mobile-specific)
    final imageCache = PaintingBinding.instance.imageCache;
    if (_isHighEndDevice) {
      imageCache.maximumSize = 150;
      imageCache.maximumSizeBytes = 75 * 1024 * 1024; // 75MB
    } else {
      imageCache.maximumSize = 75;
      imageCache.maximumSizeBytes = 30 * 1024 * 1024; // 30MB
    }
    
    // Android-specific settings
    _optimizationSettings['enableHapticFeedback'] = true;
    _optimizationSettings['preferMobileLayout'] = true;
    _optimizationSettings['enableGestures'] = true;
    _optimizationSettings['maxConcurrentOperations'] = _isHighEndDevice ? 12 : 6;
    _optimizationSettings['enableGPUAcceleration'] = _hasGPUAcceleration;
    
    debugPrint('Android optimizations applied');
  }
  
  /// Apply Quest 2 VR optimizations
  Future<void> _applyQuest2Optimizations() async {
    debugPrint('Applying Quest 2 VR optimizations...');
    
    // VR-specific image cache settings
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 100; // VR needs consistent performance
    imageCache.maximumSizeBytes = 40 * 1024 * 1024; // 40MB
    
    // VR-specific optimizations
    _optimizationSettings['enableVRMode'] = true;
    _optimizationSettings['targetFPS'] = 72; // Quest 2 native refresh rate
    _optimizationSettings['enableHandTracking'] = true;
    _optimizationSettings['enableEyeTracking'] = false; // Disabled for performance
    _optimizationSettings['enableSpatialAudio'] = true;
    _optimizationSettings['maxConcurrentOperations'] = 8; // Conservative for VR
    _optimizationSettings['enableGPUAcceleration'] = true;
    _optimizationSettings['reduceMotionSickness'] = true;
    _optimizationSettings['optimizeForLatency'] = true;
    
    debugPrint('Quest 2 optimizations applied');
  }
  
  /// Apply Windows 11 optimizations
  Future<void> _applyWindowsOptimizations() async {
    debugPrint('Applying Windows 11 optimizations...');
    
    // Image cache optimizations
    final imageCache = PaintingBinding.instance.imageCache;
    if (_isHighEndDevice) {
      imageCache.maximumSize = 180;
      imageCache.maximumSizeBytes = 90 * 1024 * 1024; // 90MB
    } else {
      imageCache.maximumSize = 90;
      imageCache.maximumSizeBytes = 45 * 1024 * 1024; // 45MB
    }
    
    // Windows-specific settings
    _optimizationSettings['preferDirectX'] = true;
    _optimizationSettings['enableWindowsIntegration'] = true;
    _optimizationSettings['useNativeFontRendering'] = true;
    _optimizationSettings['maxConcurrentOperations'] = _isHighEndDevice ? 14 : 7;
    _optimizationSettings['enableGPUAcceleration'] = _hasGPUAcceleration;
    
    debugPrint('Windows 11 optimizations applied');
  }
  
  /// Apply generic optimizations
  Future<void> _applyGenericOptimizations() async {
    debugPrint('Applying generic optimizations...');
    
    // Conservative image cache settings
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 50;
    imageCache.maximumSizeBytes = 25 * 1024 * 1024; // 25MB
    
    // Generic settings
    _optimizationSettings['maxConcurrentOperations'] = 4;
    _optimizationSettings['enableGPUAcceleration'] = _hasGPUAcceleration;
    
    debugPrint('Generic optimizations applied');
  }
  
  /// Get platform-specific recommendations
  List<OptimizationRecommendation> getPlatformRecommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    switch (_platformType) {
      case PlatformType.ubuntu2404:
        recommendations.addAll(_getUbuntuRecommendations());
        break;
      case PlatformType.android:
        recommendations.addAll(_getAndroidRecommendations());
        break;
      case PlatformType.quest2:
        recommendations.addAll(_getQuest2Recommendations());
        break;
      case PlatformType.windows11:
        recommendations.addAll(_getWindowsRecommendations());
        break;
      default:
        recommendations.addAll(_getGenericRecommendations());
        break;
    }
    
    return recommendations;
  }
  
  /// Get Ubuntu recommendations
  List<OptimizationRecommendation> _getUbuntuRecommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    if (!_hasGPUAcceleration) {
      recommendations.add(OptimizationRecommendation(
        type: RecommendationType.hardware,
        priority: RecommendationPriority.high,
        title: 'Enable GPU Acceleration',
        description: 'Install NVIDIA or AMD drivers for better performance',
        actions: [
          'sudo apt update',
          'sudo apt install nvidia-driver-535',
          'Reboot system',
        ],
      ));
    }
    
    if (!_isHighEndDevice) {
      recommendations.add(OptimizationRecommendation(
        type: RecommendationType.performance,
        priority: RecommendationPriority.medium,
        title: 'Optimize for Low-End Hardware',
        description: 'Reduce visual effects and background processes',
        actions: [
          'Enable reduced motion settings',
          'Close unnecessary applications',
          'Use lightweight terminal themes',
        ],
      ));
    }
    
    return recommendations;
  }
  
  /// Get Android recommendations
  List<OptimizationRecommendation> _getAndroidRecommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    recommendations.add(OptimizationRecommendation(
      type: RecommendationType.battery,
      priority: RecommendationPriority.medium,
      title: 'Optimize Battery Usage',
      description: 'Reduce battery consumption for longer usage',
      actions: [
        'Enable battery saver mode',
        'Reduce screen brightness',
        'Close background apps',
      ],
    ));
    
    if (!_isHighEndDevice) {
      recommendations.add(OptimizationRecommendation(
        type: RecommendationType.performance,
        priority: RecommendationPriority.high,
        title: 'Performance Mode',
        description: 'Enable performance mode for better terminal responsiveness',
        actions: [
          'Disable animations',
          'Clear app cache',
          'Use dark theme',
        ],
      ));
    }
    
    return recommendations;
  }
  
  /// Get Quest 2 recommendations
  List<OptimizationRecommendation> _getQuest2Recommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    recommendations.add(OptimizationRecommendation(
      type: RecommendationType.vr,
      priority: RecommendationPriority.high,
      title: 'VR Comfort Settings',
      description: 'Optimize for comfortable VR experience',
      actions: [
        'Enable 72Hz refresh rate',
        'Reduce motion sickness effects',
        'Optimize hand tracking sensitivity',
        'Ensure proper guardian setup',
      ],
    ));
    
    recommendations.add(OptimizationRecommendation(
      type: RecommendationType.performance,
      priority: RecommendationPriority.medium,
      title: 'VR Performance',
      description: 'Optimize rendering for VR performance',
      actions: [
        'Use fixed foveated rendering',
        'Reduce texture quality',
        'Disable unnecessary visual effects',
      ],
    ));
    
    return recommendations;
  }
  
  /// Get Windows recommendations
  List<OptimizationRecommendation> _getWindowsRecommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    if (!_hasGPUAcceleration) {
      recommendations.add(OptimizationRecommendation(
        type: RecommendationType.hardware,
        priority: RecommendationPriority.high,
        title: 'Update Graphics Drivers',
        description: 'Install latest graphics drivers for GPU acceleration',
        actions: [
          'Check Windows Update for drivers',
          'Visit manufacturer website',
          'Install DirectX 12 compatible drivers',
        ],
      ));
    }
    
    recommendations.add(OptimizationRecommendation(
      type: RecommendationType.performance,
      priority: RecommendationPriority.medium,
      title: 'Windows Game Mode',
      description: 'Enable Game Mode for better performance',
      actions: [
        'Enable Game Mode in Windows settings',
        'Disable unnecessary startup programs',
        'Optimize power settings',
      ],
    ));
    
    return recommendations;
  }
  
  /// Get generic recommendations
  List<OptimizationRecommendation> _getGenericRecommendations() {
    final recommendations = <OptimizationRecommendation>[];
    
    recommendations.add(OptimizationRecommendation(
      type: RecommendationType.performance,
      priority: RecommendationPriority.medium,
      title: 'General Performance',
      description: 'Basic performance optimizations',
      actions: [
        'Clear application cache',
        'Reduce visual effects',
        'Close background applications',
      ],
    ));
    
    return recommendations;
  }
  
  /// Apply optimization setting
  void applyOptimization(String key, dynamic value) {
    _optimizationSettings[key] = value;
    
    _eventController.add(OptimizationEvent(
      type: OptimizationEventType.settingChanged,
      platform: _platformType,
      settings: {key: value},
      timestamp: DateTime.now(),
    ));
    
    debugPrint('Applied optimization: $key = $value');
  }
  
  /// Get current optimization settings
  Map<String, dynamic> getOptimizationSettings() {
    return Map.unmodifiable(_optimizationSettings);
  }
  
  /// Reset optimizations to defaults
  void resetOptimizations() {
    _optimizationSettings.clear();
    _isOptimized = false;
    
    _eventController.add(OptimizationEvent(
      type: OptimizationEventType.optimizationsReset,
      platform: _platformType,
      settings: {},
      timestamp: DateTime.now(),
    ));
    
    debugPrint('Optimizations reset to defaults');
  }
  
  /// Get optimization report
  Map<String, dynamic> getOptimizationReport() {
    return {
      'platformType': _platformType.toString(),
      'isHighEndDevice': _isHighEndDevice,
      'hasGPUAcceleration': _hasGPUAcceleration,
      'isVRDevice': _isVRDevice,
      'isOptimized': _isOptimized,
      'optimizationSettings': _optimizationSettings,
      'recommendations': getPlatformRecommendations().map((r) => r.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Dispose resources
  void dispose() {
    _optimizationTimer?.cancel();
    _optimizationTimer = null;
    _eventController.close();
    _optimizationSettings.clear();
    _isOptimized = false;
  }
}

/// Platform types
enum PlatformType {
  unknown,
  linux,
  ubuntu2404,
  android,
  quest2,
  windows11,
  ios,
  windows,
}

/// Optimization event types
enum OptimizationEventType {
  optimizationsApplied,
  optimizationsReset,
  settingChanged,
  recommendationUpdated,
}

/// Optimization event
class OptimizationEvent {
  final OptimizationEventType type;
  final PlatformType platform;
  final Map<String, dynamic> settings;
  final DateTime timestamp;
  
  OptimizationEvent({
    required this.type,
    required this.platform,
    required this.settings,
    required this.timestamp,
  });
}

/// Optimization recommendation
class OptimizationRecommendation {
  final RecommendationType type;
  final RecommendationPriority priority;
  final String title;
  final String description;
  final List<String> actions;
  
  OptimizationRecommendation({
    required this.type,
    required this.priority,
    required this.title,
    required this.description,
    required this.actions,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'priority': priority.toString(),
    'title': title,
    'description': description,
    'actions': actions,
  };
}

/// Recommendation types
enum RecommendationType {
  hardware,
  performance,
  battery,
  vr,
  network,
}

/// Recommendation priority levels
enum RecommendationPriority {
  low,
  medium,
  high,
  critical,
}
