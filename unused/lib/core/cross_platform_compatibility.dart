import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-Platform Compatibility Layer
/// 
/// Ensures Termisol works seamlessly across:
/// - Ubuntu 24.04.3 (primary development platform)
/// - Android (Google Pixel 10 Pro)
/// - Oculus Quest 2 VR
/// - Windows 11 (dual boot)
/// 
/// Features:
/// - Platform-specific optimizations
/// - Hardware capability detection
/// - Fallback mechanisms
/// - Performance tuning per platform
class CrossPlatformCompatibility {
  static final CrossPlatformCompatibility _instance = CrossPlatformCompatibility._internal();
  factory CrossPlatformCompatibility() => _instance;
  CrossPlatformCompatibility._internal();

  PlatformInfo? _platformInfo;
  HardwareCapabilities? _hardwareCapabilities;
  final Map<String, dynamic> _platformSettings = {};
  
  /// Initialize cross-platform compatibility
  Future<void> initialize() async {
    _platformInfo = await _detectPlatform();
    _hardwareCapabilities = await _detectHardwareCapabilities();
    await _applyPlatformOptimizations();
    
    debugPrint('🌐 Cross-Platform Compatibility initialized');
    debugPrint('   Platform: ${_platformInfo?.type}');
    debugPrint('   Hardware: ${_hardwareCapabilities?.toString()}');
  }

  /// Detect current platform
  Future<PlatformInfo> _detectPlatform() async {
    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final architecture = Platform.operatingSystem;
    
    PlatformType type;
    bool isVrDevice = false;
    
    // Detect Quest 2 (special case of Android)
    if (os == 'android') {
      // Check for VR-specific features
      try {
        final result = await Process.run('getprop', ['ro.product.model']);
        final model = result.stdout.toString().trim();
        if (model.contains('Quest') || model.contains('Oculus')) {
          type = PlatformType.quest2;
          isVrDevice = true;
        } else {
          type = PlatformType.android;
        }
      } catch (e) {
        type = PlatformType.android;
      }
    } else if (os == 'linux') {
      type = PlatformType.linux;
    } else if (os == 'windows') {
      type = PlatformType.windows;
    } else {
      type = PlatformType.unknown;
    }
    
    return PlatformInfo(
      type: type,
      version: version,
      architecture: architecture,
      isVrDevice: isVrDevice,
    );
  }

  /// Detect hardware capabilities
  Future<HardwareCapabilities> _detectHardwareCapabilities() async {
    if (_platformInfo == null) {
      throw Exception('Platform info not detected');
    }
    
    final capabilities = HardwareCapabilities();
    
    switch (_platformInfo!.type) {
      case PlatformType.linux:
        await _detectLinuxCapabilities(capabilities);
        break;
      case PlatformType.android:
        await _detectAndroidCapabilities(capabilities);
        break;
      case PlatformType.quest2:
        await _detectQuest2Capabilities(capabilities);
        break;
      case PlatformType.windows:
        await _detectWindowsCapabilities(capabilities);
        break;
    }
    
    return capabilities;
  }

  /// Detect Linux-specific capabilities
  Future<void> _detectLinuxCapabilities(HardwareCapabilities capabilities) async {
    try {
      // CPU info
      final cpuinfo = File('/proc/cpuinfo');
      if (await cpuinfo.exists()) {
        final lines = await cpuinfo.readAsLines();
        int cores = 0;
        String? model;
        
        for (final line in lines) {
          if (line.startsWith('processor')) cores++;
          if (line.startsWith('model name')) {
            model = line.split(':')[1].trim();
          }
        }
        
        capabilities.cpuCores = cores;
        capabilities.cpuModel = model;
      }
      
      // Memory info
      final meminfo = File('/proc/meminfo');
      if (await meminfo.exists()) {
        final lines = await meminfo.readAsLines();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final kb = int.parse(line.split(RegExp(r'\s+'))[1]);
            capabilities.totalMemoryKB = kb;
            break;
          }
        }
      }
      
      // GPU detection
      await _detectLinuxGpu(capabilities);
      
      // Display info
      capabilities.hasDisplay = true;
      capabilities.displayResolution = await _getLinuxDisplayResolution();
      
    } catch (e) {
      debugPrint('⚠️ Error detecting Linux capabilities: $e');
    }
  }

  /// Detect Linux GPU capabilities
  Future<void> _detectLinuxGpu(HardwareCapabilities capabilities) async {
    try {
      // Check for NVIDIA GPU
      final nvidiaSmi = await Process.run('which', ['nvidia-smi']);
      if (nvidiaSmi.exitCode == 0) {
        capabilities.hasNvidiaGpu = true;
        
        // Get GPU info
        final result = await Process.run('nvidia-smi', [
          '--query-gpu=name,memory.total',
          '--format=csv,noheader,nounits'
        ]);
        
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          if (lines.isNotEmpty) {
            final parts = lines.first.split(',').map((p) => p.trim()).toList();
            if (parts.length >= 2) {
              capabilities.gpuModel = parts[0];
              capabilities.gpuMemoryMB = int.tryParse(parts[1]) ?? 0;
            }
          }
        }
      }
      
      // Check for AMD GPU
      final amdGpu = File('/sys/class/drm');
      if (await amdGpu.exists()) {
        final files = await amdGpu.list().toList();
        for (final file in files) {
          if (file.path.contains('card') && 
              await File('${file.path}/device/vendor').exists()) {
            final vendor = await File('${file.path}/device/vendor').readAsString();
            if (vendor.contains('0x1002')) { // AMD vendor ID
              capabilities.hasAmdGpu = true;
              break;
            }
          }
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ Error detecting Linux GPU: $e');
    }
  }

  /// Get Linux display resolution
  Future<String?> _getLinuxDisplayResolution() async {
    try {
      final result = await Process.run('xrandr', []);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('*')) {
            final match = RegExp(r'(\d+)x(\d+)').firstMatch(line);
            if (match != null) {
              return '${match.group(1)}x${match.group(2)}';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error getting display resolution: $e');
    }
    return null;
  }

  /// Detect Android-specific capabilities
  Future<void> _detectAndroidCapabilities(HardwareCapabilities capabilities) async {
    try {
      // Use platform channels to get Android info
      const platform = MethodChannel('com.termisol/platform');
      
      try {
        final androidInfo = await platform.invokeMapMethod<String, dynamic>('getSystemInfo');
        if (androidInfo != null) {
          capabilities.cpuCores = androidInfo['cpuCores'] ?? 0;
          capabilities.totalMemoryKB = (androidInfo['totalMemory'] ?? 0) ~/ 1024;
          capabilities.gpuModel = androidInfo['gpuModel'];
          capabilities.displayResolution = androidInfo['displayResolution'];
          capabilities.hasDisplay = true;
        }
      } on PlatformException catch (e) {
        debugPrint('⚠️ Platform channel error: $e');
      }
      
      capabilities.isMobileDevice = true;
      capabilities.hasTouchScreen = true;
      
    } catch (e) {
      debugPrint('⚠️ Error detecting Android capabilities: $e');
    }
  }

  /// Detect Quest 2-specific capabilities
  Future<void> _detectQuest2Capabilities(HardwareCapabilities capabilities) async {
    // Start with Android capabilities
    await _detectAndroidCapabilities(capabilities);
    
    // Add Quest 2 specific features
    capabilities.isVrDevice = true;
    capabilities.hasHandTracking = true;
    capabilities.hasEyeTracking = true;
    capabilities.hasSpatialAudio = true;
    capabilities.displayRefreshRate = 90.0; // Quest 2 standard
    capabilities.displayResolution = '1832x1920'; // Per eye
  }

  /// Detect Windows-specific capabilities
  Future<void> _detectWindowsCapabilities(HardwareCapabilities capabilities) async {
    try {
      // Use systeminfo command
      final result = await Process.run('systeminfo', []);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        
        for (final line in lines) {
          if (line.contains('Processor(s):')) {
            final match = RegExp(r'(\d+)').firstMatch(line);
            if (match != null) {
              capabilities.cpuCores = int.tryParse(match.group(1)!) ?? 0;
            }
          } else if (line.contains('Total Physical Memory:')) {
            final match = RegExp(r'([\d,]+)\s*MB').firstMatch(line);
            if (match != null) {
              final mb = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
              capabilities.totalMemoryKB = mb * 1024;
            }
          }
        }
      }
      
      capabilities.hasDisplay = true;
      capabilities.displayResolution = await _getWindowsDisplayResolution();
      
    } catch (e) {
      debugPrint('⚠️ Error detecting Windows capabilities: $e');
    }
  }

  /// Get Windows display resolution
  Future<String?> _getWindowsDisplayResolution() async {
    try {
      final result = await Process.run('wmic', ['desktopmonitor', 'get', 'screenheight,screenwidth']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          final match = RegExp(r'(\d+)\s+(\d+)').firstMatch(line);
          if (match != null) {
            return '${match.group(1)}x${match.group(2)}';
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error getting Windows display resolution: $e');
    }
    return null;
  }

  /// Apply platform-specific optimizations
  Future<void> _applyPlatformOptimizations() async {
    if (_platformInfo == null || _hardwareCapabilities == null) return;
    
    switch (_platformInfo!.type) {
      case PlatformType.linux:
        await _applyLinuxOptimizations();
        break;
      case PlatformType.android:
        await _applyAndroidOptimizations();
        break;
      case PlatformType.quest2:
        await _applyQuest2Optimizations();
        break;
      case PlatformType.windows:
        await _applyWindowsOptimizations();
        break;
    }
  }

  /// Apply Linux-specific optimizations
  Future<void> _applyLinuxOptimizations() async {
    _platformSettings['rendering_backend'] = 
        _hardwareCapabilities!.hasNvidiaGpu ? 'opengl' : 'software';
    
    _platformSettings['font_rendering'] = 'freetype';
    _platformSettings['input_method'] = 'x11';
    _platformSettings['clipboard_integration'] = true;
    
    // Optimize for NVIDIA if available
    if (_hardwareCapabilities!.hasNvidiaGpu) {
      _platformSettings['gpu_acceleration'] = true;
      _platformSettings['vsync'] = true;
    }
  }

  /// Apply Android-specific optimizations
  Future<void> _applyAndroidOptimizations() async {
    _platformSettings['rendering_backend'] = 'vulkan';
    _platformSettings['font_rendering'] = 'system';
    _platformSettings['input_method'] = 'touch';
    _platformSettings['clipboard_integration'] = true;
    _platformSettings['battery_optimization'] = true;
    
    // Mobile-specific optimizations
    _platformSettings['reduced_animations'] = true;
    _platformSettings['adaptive_refresh_rate'] = true;
  }

  /// Apply Quest 2-specific optimizations
  Future<void> _applyQuest2Optimizations() async {
    await _applyAndroidOptimizations();
    
    // VR-specific optimizations
    _platformSettings['vr_mode'] = true;
    _platformSettings['stereoscopic_rendering'] = true;
    _platformSettings['hand_tracking'] = true;
    _platformSettings['spatial_audio'] = true;
    _platformSettings['fixed_fov'] = true;
    
    // Performance optimizations for VR
    _platformSettings['target_fps'] = 90;
    _platformSettings['resolution_scale'] = 1.0;
    _platformSettings['foveated_rendering'] = true;
  }

  /// Apply Windows-specific optimizations
  Future<void> _applyWindowsOptimizations() async {
    _platformSettings['rendering_backend'] = 'directx';
    _platformSettings['font_rendering'] = 'directwrite';
    _platformSettings['input_method'] = 'win32';
    _platformSettings['clipboard_integration'] = true;
    _platformSettings['windows_terminal_integration'] = true;
  }

  /// Get platform-specific setting
  T? getPlatformSetting<T>(String key) {
    return _platformSettings[key] as T?;
  }

  /// Set platform-specific setting
  void setPlatformSetting(String key, dynamic value) {
    _platformSettings[key] = value;
  }

  /// Get platform info
  PlatformInfo? get platformInfo => _platformInfo;

  /// Get hardware capabilities
  HardwareCapabilities? get hardwareCapabilities => _hardwareCapabilities;

  /// Check if feature is supported
  bool isFeatureSupported(String feature) {
    switch (feature.toLowerCase()) {
      case 'gpu_acceleration':
        return _hardwareCapabilities?.hasNvidiaGpu == true || 
               _hardwareCapabilities?.hasAmdGpu == true;
      case 'vr_mode':
        return _platformInfo?.isVrDevice == true;
      case 'hand_tracking':
        return _hardwareCapabilities?.hasHandTracking == true;
      case 'eye_tracking':
        return _hardwareCapabilities?.hasEyeTracking == true;
      case 'touch_screen':
        return _hardwareCapabilities?.hasTouchScreen == true;
      case 'spatial_audio':
        return _hardwareCapabilities?.hasSpatialAudio == true;
      case 'clipboard_integration':
        return _platformInfo?.type != PlatformType.unknown;
      default:
        return false;
    }
  }

  /// Get recommended settings for current platform
  Map<String, dynamic> getRecommendedSettings() {
    final settings = <String, dynamic>{};
    
    // Base settings
    settings['font_family'] = 'JetBrains Mono';
    settings['font_size'] = _platformInfo?.isVrDevice == true ? 16 : 14;
    settings['theme'] = 'dark';
    
    // Platform-specific settings
    switch (_platformInfo?.type) {
      case PlatformType.linux:
        settings['hardware_acceleration'] = _hardwareCapabilities?.hasNvidiaGpu == true;
        settings['gpu_acceleration'] = _hardwareCapabilities?.hasNvidiaGpu == true;
        settings['vsync'] = true;
        break;
        
      case PlatformType.android:
        settings['hardware_acceleration'] = true;
        settings['gpu_acceleration'] = true;
        settings['battery_optimization'] = true;
        settings['adaptive_refresh_rate'] = true;
        break;
        
      case PlatformType.quest2:
        settings['vr_mode'] = true;
        settings['target_fps'] = 90;
        settings['resolution_scale'] = 1.0;
        settings['foveated_rendering'] = true;
        settings['hand_tracking'] = true;
        break;
        
      case PlatformType.windows:
        settings['hardware_acceleration'] = true;
        settings['gpu_acceleration'] = true;
        settings['directx_backend'] = true;
        settings['windows_terminal_integration'] = true;
        break;
    }
    
    // Hardware-based settings
    if (_hardwareCapabilities?.totalMemoryKB != null) {
      final memoryGB = _hardwareCapabilities!.totalMemoryKB! / (1024 * 1024);
      settings['scrollback_lines'] = memoryGB > 8 ? 100000 : 50000;
      settings['cache_size_mb'] = memoryGB > 16 ? 1024 : 512;
    }
    
    return settings;
  }
}

/// Platform information
class PlatformInfo {
  final PlatformType type;
  final String version;
  final String architecture;
  final bool isVrDevice;
  
  PlatformInfo({
    required this.type,
    required this.version,
    required this.architecture,
    this.isVrDevice = false,
  });
  
  @override
  String toString() {
    return 'PlatformInfo(type: $type, version: $version, arch: $architecture, vr: $isVrDevice)';
  }
}

/// Hardware capabilities
class HardwareCapabilities {
  int cpuCores = 0;
  String? cpuModel;
  int totalMemoryKB = 0;
  String? gpuModel;
  int gpuMemoryMB = 0;
  bool hasNvidiaGpu = false;
  bool hasAmdGpu = false;
  bool hasDisplay = false;
  String? displayResolution;
  double displayRefreshRate = 60.0;
  bool isMobileDevice = false;
  bool isVrDevice = false;
  bool hasTouchScreen = false;
  bool hasHandTracking = false;
  bool hasEyeTracking = false;
  bool hasSpatialAudio = false;
  
  @override
  String toString() {
    return 'HardwareCapabilities('
        'cpu: $cpuCores cores ($cpuModel), '
        'memory: ${totalMemoryKB ~/ 1024}MB, '
        'gpu: $gpuModel (${gpuMemoryMB}MB), '
        'display: $displayResolution@${displayRefreshRate}Hz, '
        'vr: $isVrDevice, '
        'touch: $hasTouchScreen, '
        'hand_tracking: $hasHandTracking, '
        'eye_tracking: $hasEyeTracking)';
  }
}

/// Platform types
enum PlatformType {
  linux,
  android,
  windows,
  quest2,
  unknown,
}
