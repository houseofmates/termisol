import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:system_info2/system_info2.dart';

/// Adaptive rendering system that optimizes Termisol for different devices
/// and usage contexts. Automatically adjusts rendering quality, memory usage,
/// and performance characteristics based on detected hardware capabilities.
class AdaptiveRenderingSystem {
  static AdaptiveRenderingSystem? _instance;
  static AdaptiveRenderingSystem get instance {
    _instance ??= AdaptiveRenderingSystem._();
    return _instance!;
  }

  AdaptiveRenderingSystem._();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final StreamController<RenderingProfile> _profileController = StreamController<RenderingProfile>.broadcast();

  RenderingProfile? _currentProfile;
  DeviceCapabilities? _deviceCapabilities;
  bool _isInitialized = false;

  /// Current rendering profile
  RenderingProfile? get currentProfile => _currentProfile;

  /// Device capabilities
  DeviceCapabilities? get deviceCapabilities => _deviceCapabilities;

  /// Stream of profile changes
  Stream<RenderingProfile> get profileChanges => _profileController.stream;

  /// Initialize the adaptive rendering system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _detectDeviceCapabilities();
      await _createOptimalProfile();
      _startPerformanceMonitoring();
      _isInitialized = true;

      debugPrint('🎨 Adaptive Rendering System initialized: ${_currentProfile?.name}');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize adaptive rendering: $e');
      // Fallback to conservative profile
      _currentProfile = RenderingProfile.conservative();
      _profileController.add(_currentProfile!);
    }
  }

  /// Detect device capabilities
  Future<void> _detectDeviceCapabilities() async {
    final capabilities = DeviceCapabilities();

    try {
      // Detect platform-specific capabilities
      if (Platform.isAndroid || Platform.isIOS) {
        await _detectMobileCapabilities(capabilities);
      } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await _detectDesktopCapabilities(capabilities);
      }

      // Detect hardware capabilities
      await _detectHardwareCapabilities(capabilities);

      // Detect display capabilities
      await _detectDisplayCapabilities(capabilities);

      _deviceCapabilities = capabilities;
    } catch (e) {
      debugPrint('⚠️ Failed to detect device capabilities: $e');
      _deviceCapabilities = DeviceCapabilities.basic();
    }
  }

  /// Detect mobile device capabilities
  Future<void> _detectMobileCapabilities(DeviceCapabilities capabilities) async {
    capabilities.platform = PlatformType.mobile;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        capabilities.deviceModel = androidInfo.model;
        capabilities.androidVersion = androidInfo.version.release;

        // Detect device class
        final deviceClass = _classifyAndroidDevice(androidInfo);
        capabilities.deviceClass = deviceClass;

        // Estimate memory based on device class
        switch (deviceClass) {
          case DeviceClass.unknown:
            capabilities.memoryGB = 6.0;
            capabilities.hasDedicatedGPU = false;
            break;
          case DeviceClass.desktop:
            capabilities.memoryGB = 16.0;
            capabilities.hasDedicatedGPU = true;
            break;
          case DeviceClass.flagship:
            capabilities.memoryGB = 12.0;
            capabilities.hasDedicatedGPU = true;
            break;
          case DeviceClass.midrange:
            capabilities.memoryGB = 8.0;
            capabilities.hasDedicatedGPU = false;
            break;
          case DeviceClass.budget:
            capabilities.memoryGB = 4.0;
            capabilities.hasDedicatedGPU = false;
            break;
        }

        // Check for specific features
        capabilities.hasHapticFeedback = true;
        capabilities.hasBiometricAuth = androidInfo.version.sdkInt >= 29; // Android 10+

      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        capabilities.deviceModel = iosInfo.utsname.machine;
        capabilities.iosVersion = iosInfo.systemVersion;

        // iOS devices generally have good performance
        capabilities.deviceClass = DeviceClass.flagship;
        capabilities.memoryGB = _estimateIOSMemory(iosInfo);
        capabilities.hasDedicatedGPU = true;
        capabilities.hasHapticFeedback = true;
        capabilities.hasBiometricAuth = true;
      }

      // Mobile-specific optimizations
      capabilities.supportsMultitasking = true;
      capabilities.batteryAware = true;
      capabilities.thermalThrottling = true;

    } catch (e) {
      debugPrint('⚠️ Failed to detect mobile capabilities: $e');
    }
  }

  /// Detect desktop capabilities
  Future<void> _detectDesktopCapabilities(DeviceCapabilities capabilities) async {
    capabilities.platform = PlatformType.desktop;

    try {
      if (Platform.isLinux) {
        // Check for specific Linux configurations
        capabilities.deviceModel = 'Linux System';

        // Check for NVIDIA GPU
        final nvidiaCheck = await _checkNVIDIAGPU();
        capabilities.hasNVIDIAGPU = nvidiaCheck;

        if (nvidiaCheck) {
          capabilities.hasDedicatedGPU = true;
          capabilities.gpuMemoryGB = await _getNVIDIAGPUMemory();
        }

        // Check system memory
        capabilities.memoryGB = SysInfo.getTotalPhysicalMemory().toDouble() / (1024 * 1024 * 1024);

      } else if (Platform.isWindows) {
        capabilities.deviceModel = 'Windows System';

        // Windows-specific detections
        capabilities.memoryGB = SysInfo.getTotalPhysicalMemory().toDouble() / (1024 * 1024 * 1024);

      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        capabilities.deviceModel = macInfo.model;
        capabilities.memoryGB = SysInfo.getTotalPhysicalMemory().toDouble() / (1024 * 1024 * 1024);
        capabilities.hasDedicatedGPU = true; // Most Macs have dedicated GPUs
      }

      capabilities.deviceClass = DeviceClass.desktop;
      capabilities.supportsMultitasking = true;

    } catch (e) {
      debugPrint('⚠️ Failed to detect desktop capabilities: $e');
    }
  }

  /// Detect hardware capabilities
  Future<void> _detectHardwareCapabilities(DeviceCapabilities capabilities) async {
    try {
      // CPU cores
      capabilities.cpuCores = SysInfo.cores.length;

      // System memory (if not already set)
      if (capabilities.memoryGB == 0) {
        capabilities.memoryGB = SysInfo.getTotalPhysicalMemory().toDouble() / (1024 * 1024 * 1024);
      }

      // CPU architecture
      capabilities.cpuArchitecture = SysInfo.kernelArchitecture.toString();

      // Detect GPU capabilities
      if (capabilities.hasNVIDIAGPU) {
        capabilities.gpuVendor = 'NVIDIA';
      } else if (Platform.isMacOS) {
        capabilities.gpuVendor = 'Apple';
      } else {
        capabilities.gpuVendor = 'Unknown';
      }

    } catch (e) {
      debugPrint('⚠️ Failed to detect hardware capabilities: $e');
    }
  }

  /// Detect display capabilities
  Future<void> _detectDisplayCapabilities(DeviceCapabilities capabilities) async {
    try {
      final window = WidgetsBinding.instance.window;
      final size = window.physicalSize;
      final pixelRatio = window.devicePixelRatio;

      capabilities.screenWidth = size.width / pixelRatio;
      capabilities.screenHeight = size.height / pixelRatio;
      capabilities.screenDensity = pixelRatio;
      capabilities.refreshRate = window.displayFeatures.isNotEmpty ?
        60.0 : 60.0; // Default assumption, could be improved

      // Classify display quality
      if (capabilities.screenDensity >= 3.0 && capabilities.screenWidth >= 1080) {
        capabilities.displayClass = DisplayClass.ultraHigh;
      } else if (capabilities.screenDensity >= 2.5 || capabilities.screenWidth >= 1440) {
        capabilities.displayClass = DisplayClass.high;
      } else if (capabilities.screenDensity >= 2.0 || capabilities.screenWidth >= 720) {
        capabilities.displayClass = DisplayClass.medium;
      } else {
        capabilities.displayClass = DisplayClass.low;
      }

    } catch (e) {
      debugPrint('⚠️ Failed to detect display capabilities: $e');
      capabilities.displayClass = DisplayClass.medium; // Safe default
    }
  }

  /// Classify Android device
  DeviceClass _classifyAndroidDevice(AndroidDeviceInfo info) {
    // Simple classification based on model and specs
    final model = info.model.toLowerCase();

    // Flagship devices (Pixel, Galaxy S/Note series, etc.)
    if (model.contains('pixel') && model.contains('10') ||
        model.contains('galaxy') && (model.contains('s') || model.contains('note')) ||
        model.contains('oneplus') && model.contains('10') ||
        model.contains('xiaomi') && model.contains('12')) {
      return DeviceClass.flagship;
    }

    // Mid-range devices
    if (model.contains('pixel') && model.contains('8') ||
        model.contains('galaxy') && model.contains('a') ||
        model.contains('oneplus') && model.contains('9') ||
        model.contains('xiaomi') && model.contains('11')) {
      return DeviceClass.midrange;
    }

    // Budget devices
    return DeviceClass.budget;
  }

  /// Estimate iOS device memory
  double _estimateIOSMemory(IosDeviceInfo info) {
    final machine = info.utsname.machine.toLowerCase();

    // Modern iOS devices generally have good memory
    if (machine.contains('iphone') && machine.contains('14') ||
        machine.contains('iphone') && machine.contains('15') ||
        machine.contains('ipad') && machine.contains('8') ||
        machine.contains('ipad') && machine.contains('9')) {
      return 6.0; // 6GB+ on modern devices
    }

    return 4.0; // Conservative estimate
  }

  /// Check for NVIDIA GPU on Linux
  Future<bool> _checkNVIDIAGPU() async {
    try {
      final result = await Process.run('nvidia-smi', ['--query-gpu=name', '--format=csv,noheader,nounits']);
      return result.exitCode == 0 && result.stdout.toString().isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get NVIDIA GPU memory
  Future<double> _getNVIDIAGPUMemory() async {
    try {
      final result = await Process.run('nvidia-smi', ['--query-gpu=memory.total', '--format=csv,noheader,nounits']);
      if (result.exitCode == 0) {
        final memoryStr = result.stdout.toString().trim().split(' ').first;
        return double.tryParse(memoryStr) ?? 4.0;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get NVIDIA GPU memory: $e');
    }
    return 4.0; // Conservative estimate
  }

  /// Create optimal rendering profile based on capabilities
  Future<void> _createOptimalProfile() async {
    if (_deviceCapabilities == null) {
      _currentProfile = RenderingProfile.conservative();
      return;
    }

    final caps = _deviceCapabilities!;

    // Desktop with NVIDIA GPU - maximum quality
    if (caps.platform == PlatformType.desktop && caps.hasNVIDIAGPU) {
      _currentProfile = RenderingProfile.maximum();
    }
    // Desktop without dedicated GPU - high quality
    else if (caps.platform == PlatformType.desktop) {
      _currentProfile = RenderingProfile.high();
    }
    // VR headset - optimized for performance
    else if (caps.deviceModel?.contains('Quest') == true || caps.deviceModel?.contains('VR') == true) {
      _currentProfile = RenderingProfile.vrOptimized();
    }
    // High-end mobile - balanced quality
    else if (caps.platform == PlatformType.mobile && caps.deviceClass == DeviceClass.flagship) {
      _currentProfile = RenderingProfile.balanced();
    }
    // Mid-range mobile - performance optimized
    else if (caps.platform == PlatformType.mobile && caps.deviceClass == DeviceClass.midrange) {
      _currentProfile = RenderingProfile.mobileOptimized();
    }
    // Budget mobile or unknown - conservative
    else {
      _currentProfile = RenderingProfile.conservative();
    }

    _profileController.add(_currentProfile!);
  }

  /// Start performance monitoring
  void _startPerformanceMonitoring() {
    // Monitor frame rate and memory usage
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isInitialized) return;

      try {
        await _monitorPerformance();
      } catch (e) {
        debugPrint('⚠️ Performance monitoring error: $e');
      }
    });
  }

  /// Monitor performance and adjust profile if needed
  Future<void> _monitorPerformance() async {
    if (_currentProfile == null) return;

    // Check memory pressure
    final memoryPressure = await _getMemoryPressure();

    // Check frame rate (simplified)
    final frameRateOk = await _checkFrameRate();

    // Adjust profile based on conditions
    RenderingProfile? newProfile;

    if (memoryPressure > 0.8 && _currentProfile!.memoryOptimization < 0.8) {
      // High memory pressure - increase memory optimization
      newProfile = _currentProfile!.copyWith(
        memoryOptimization: (_currentProfile!.memoryOptimization + 0.2).clamp(0.0, 1.0),
      );
    } else if (!frameRateOk && _currentProfile!.renderingQuality > 0.5) {
      // Poor frame rate - reduce quality
      newProfile = _currentProfile!.copyWith(
        renderingQuality: (_currentProfile!.renderingQuality - 0.1).clamp(0.1, 1.0),
      );
    }

    if (newProfile != null && newProfile != _currentProfile) {
      _currentProfile = newProfile;
      _profileController.add(_currentProfile!);
      debugPrint('🎨 Profile adjusted: ${newProfile.name}');
    }
  }

  /// Get current memory pressure (0.0 = no pressure, 1.0 = critical)
  Future<double> _getMemoryPressure() async {
    try {
      // Simplified memory pressure detection
      // In a real implementation, this would use platform-specific APIs
      return 0.3; // Conservative estimate
    } catch (e) {
      return 0.5; // Safe middle ground
    }
  }

  /// Check if frame rate is acceptable
  Future<bool> _checkFrameRate() async {
    // Simplified frame rate check
    // In a real implementation, this would monitor actual frame times
    return true;
  }

  /// Force a specific profile
  void forceProfile(RenderingProfile profile) {
    _currentProfile = profile;
    _profileController.add(profile);
    debugPrint('🎨 Profile forced: ${profile.name}');
  }

  /// Get recommended settings for current profile
  Map<String, dynamic> getRecommendedSettings() {
    if (_currentProfile == null) return {};

    return {
      'fontSize': _currentProfile!.recommendedFontSize,
      'bufferSize': _currentProfile!.recommendedBufferSize,
      'animationEnabled': _currentProfile!.animationsEnabled,
      'gpuAcceleration': _currentProfile!.gpuAcceleration,
      'memoryLimit': _currentProfile!.memoryLimitMB,
      'renderingQuality': _currentProfile!.renderingQuality,
      'memoryOptimization': _currentProfile!.memoryOptimization,
    };
  }

  /// Dispose of resources
  void dispose() {
    _profileController.close();
    _isInitialized = false;
  }
}

/// Device capabilities container
class DeviceCapabilities {
  PlatformType platform = PlatformType.unknown;
  DeviceClass deviceClass = DeviceClass.unknown;
  DisplayClass displayClass = DisplayClass.medium;

  String? deviceModel;
  String? androidVersion;
  String? iosVersion;
  String? cpuArchitecture;

  double memoryGB = 0.0;
  double gpuMemoryGB = 0.0;
  int cpuCores = 1;

  double screenWidth = 0.0;
  double screenHeight = 0.0;
  double screenDensity = 1.0;
  double refreshRate = 60.0;

  bool hasDedicatedGPU = false;
  bool hasNVIDIAGPU = false;
  String gpuVendor = 'Unknown';

  bool hasHapticFeedback = false;
  bool hasBiometricAuth = false;
  bool supportsMultitasking = false;
  bool batteryAware = false;
  bool thermalThrottling = false;

  DeviceCapabilities();

  factory DeviceCapabilities.basic() {
    return DeviceCapabilities()
      ..platform = PlatformType.unknown
      ..deviceClass = DeviceClass.budget
      ..displayClass = DisplayClass.low
      ..memoryGB = 4.0
      ..cpuCores = 2
      ..screenWidth = 720
      ..screenHeight = 1280
      ..hasDedicatedGPU = false;
  }
}

/// Rendering profile with optimized settings
class RenderingProfile {
  final String name;
  final double renderingQuality; // 0.0 = lowest, 1.0 = highest
  final double memoryOptimization; // 0.0 = no optimization, 1.0 = maximum
  final int recommendedBufferSize;
  final double recommendedFontSize;
  final int memoryLimitMB;
  final bool gpuAcceleration;
  final bool animationsEnabled;
  final Map<String, dynamic> customSettings;

  const RenderingProfile({
    required this.name,
    required this.renderingQuality,
    required this.memoryOptimization,
    required this.recommendedBufferSize,
    required this.recommendedFontSize,
    required this.memoryLimitMB,
    required this.gpuAcceleration,
    required this.animationsEnabled,
    this.customSettings = const {},
  });

  /// Maximum quality profile for high-end desktop systems
  factory RenderingProfile.maximum() {
    return RenderingProfile(
      name: 'Maximum Quality',
      renderingQuality: 1.0,
      memoryOptimization: 0.0,
      recommendedBufferSize: 100000,
      recommendedFontSize: 14.0,
      memoryLimitMB: 2048,
      gpuAcceleration: true,
      animationsEnabled: true,
      customSettings: {
        'antiAliasing': true,
        'shadows': true,
        'particles': true,
        'postProcessing': true,
      },
    );
  }

  /// High quality profile for standard desktop systems
  factory RenderingProfile.high() {
    return RenderingProfile(
      name: 'High Quality',
      renderingQuality: 0.85,
      memoryOptimization: 0.2,
      recommendedBufferSize: 50000,
      recommendedFontSize: 13.0,
      memoryLimitMB: 1024,
      gpuAcceleration: true,
      animationsEnabled: true,
      customSettings: {
        'antiAliasing': true,
        'shadows': false,
        'particles': true,
        'postProcessing': false,
      },
    );
  }

  /// Balanced profile for high-end mobile devices
  factory RenderingProfile.balanced() {
    return RenderingProfile(
      name: 'Balanced',
      renderingQuality: 0.7,
      memoryOptimization: 0.4,
      recommendedBufferSize: 25000,
      recommendedFontSize: 12.0,
      memoryLimitMB: 512,
      gpuAcceleration: true,
      animationsEnabled: true,
      customSettings: {
        'antiAliasing': false,
        'shadows': false,
        'particles': false,
        'postProcessing': false,
      },
    );
  }

  /// VR optimized profile for Quest and other VR headsets
  factory RenderingProfile.vrOptimized() {
    return RenderingProfile(
      name: 'VR Optimized',
      renderingQuality: 0.8,
      memoryOptimization: 0.6,
      recommendedBufferSize: 15000,
      recommendedFontSize: 11.0,
      memoryLimitMB: 256,
      gpuAcceleration: true,
      animationsEnabled: false, // Reduce motion sickness
      customSettings: {
        'antiAliasing': false,
        'shadows': false,
        'particles': false,
        'postProcessing': false,
        'foveatedRendering': true,
        'fixedFoveation': true,
      },
    );
  }

  /// Mobile optimized profile for mid-range mobile devices
  factory RenderingProfile.mobileOptimized() {
    return RenderingProfile(
      name: 'Mobile Optimized',
      renderingQuality: 0.5,
      memoryOptimization: 0.7,
      recommendedBufferSize: 10000,
      recommendedFontSize: 10.0,
      memoryLimitMB: 256,
      gpuAcceleration: true,
      animationsEnabled: false,
      customSettings: {
        'antiAliasing': false,
        'shadows': false,
        'particles': false,
        'postProcessing': false,
        'textureCompression': true,
      },
    );
  }

  /// Conservative profile for budget devices or unknown hardware
  factory RenderingProfile.conservative() {
    return RenderingProfile(
      name: 'Conservative',
      renderingQuality: 0.3,
      memoryOptimization: 0.9,
      recommendedBufferSize: 5000,
      recommendedFontSize: 9.0,
      memoryLimitMB: 128,
      gpuAcceleration: false,
      animationsEnabled: false,
      customSettings: {
        'antiAliasing': false,
        'shadows': false,
        'particles': false,
        'postProcessing': false,
        'textureCompression': true,
        'lowQualityTextures': true,
      },
    );
  }

  /// Create a copy with modified settings
  RenderingProfile copyWith({
    String? name,
    double? renderingQuality,
    double? memoryOptimization,
    int? recommendedBufferSize,
    double? recommendedFontSize,
    int? memoryLimitMB,
    bool? gpuAcceleration,
    bool? animationsEnabled,
    Map<String, dynamic>? customSettings,
  }) {
    return RenderingProfile(
      name: name ?? this.name,
      renderingQuality: renderingQuality ?? this.renderingQuality,
      memoryOptimization: memoryOptimization ?? this.memoryOptimization,
      recommendedBufferSize: recommendedBufferSize ?? this.recommendedBufferSize,
      recommendedFontSize: recommendedFontSize ?? this.recommendedFontSize,
      memoryLimitMB: memoryLimitMB ?? this.memoryLimitMB,
      gpuAcceleration: gpuAcceleration ?? this.gpuAcceleration,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      customSettings: customSettings ?? this.customSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RenderingProfile) return false;
    return name == other.name &&
           renderingQuality == other.renderingQuality &&
           memoryOptimization == other.memoryOptimization;
  }

  @override
  int get hashCode => Object.hash(name, renderingQuality, memoryOptimization);

  @override
  String toString() => 'RenderingProfile(name: $name, quality: $renderingQuality, memory: $memoryOptimization)';
}

/// Platform types
enum PlatformType {
  unknown,
  mobile,
  desktop,
  web,
}

/// Device classes
enum DeviceClass {
  unknown,
  budget,
  midrange,
  flagship,
  desktop,
}

/// Display quality classes
enum DisplayClass {
  low,      // < 720p or < 2.0 density
  medium,   // 720p-1080p or 2.0-2.5 density
  high,     // 1440p+ or > 2.5 density
  ultraHigh, // 4K+ or > 3.0 density
}