import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Adaptive Refresh Rate - Dynamic display refresh rate optimization
class AdaptiveRefreshRate {
  static final AdaptiveRefreshRate _instance = AdaptiveRefreshRate._internal();
  factory AdaptiveRefreshRate() => _instance;
  AdaptiveRefreshRate._internal();

  bool _isInitialized = false;
  double _currentRefreshRate = 60.0;
  double _targetRefreshRate = 60.0;
  RefreshRateMode _mode = RefreshRateMode.adaptive;
  final Queue<RefreshRateSample> _performanceHistory = Queue();
  final Map<String, RefreshProfile> _profiles = {};
  
  static const int _maxHistorySize = 300; // 5 minutes at 1-second intervals
  static const Duration _samplingInterval = Duration(seconds: 1);
  static const Duration _adjustmentInterval = Duration(seconds: 3);
  static const double _minRefreshRate = 30.0;
  static const double _maxRefreshRate = 240.0;
  
  Timer? _samplingTimer;
  Timer? _adjustmentTimer;
  final _refreshController = StreamController<RefreshRateEvent>.broadcast();
  Stream<RefreshRateEvent> get events => _refreshController.stream;
  
  bool get isInitialized => _isInitialized;
  double get currentRefreshRate => _currentRefreshRate;
  double get targetRefreshRate => _targetRefreshRate;
  RefreshRateMode get mode => _mode;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _detectDisplayCapabilities();
    _loadDefaultProfiles();
    _startSampling();
    _startAdjustment();
    
    _isInitialized = true;
    debugPrint('🔄 Adaptive Refresh Rate initialized');
  }

  Future<void> setMode(RefreshRateMode mode) async {
    if (_mode == mode) return;
    
    _mode = mode;
    
    switch (mode) {
      case RefreshRateMode.fixed:
        await _setFixedRefreshRate(_targetRefreshRate);
        break;
      case RefreshRateMode.adaptive:
        _enableAdaptiveMode();
        break;
      case RefreshRateMode.powerSaving:
        await _enablePowerSavingMode();
        break;
      case RefreshRateMode.performance:
        await _enablePerformanceMode();
        break;
    }
    
    _refreshController.add(RefreshRateEvent(
      type: RefreshRateEventType.modeChanged,
      data: {
        'mode': mode.toString(),
        'current_rate': _currentRefreshRate,
      },
    ));
    
    debugPrint('🔄 Refresh rate mode changed to: $mode');
  }

  Future<void> setTargetRefreshRate(double rate) async {
    rate = rate.clamp(_minRefreshRate, _maxRefreshRate);
    
    if (_targetRefreshRate == rate) return;
    
    _targetRefreshRate = rate;
    
    if (_mode == RefreshRateMode.fixed) {
      await _setFixedRefreshRate(rate);
    }
    
    _refreshController.add(RefreshRateEvent(
      type: RefreshRateEventType.targetChanged,
      data: {
        'target_rate': rate,
        'current_rate': _currentRefreshRate,
      },
    ));
  }

  Future<void> applyProfile(String profileName) async {
    final profile = _profiles[profileName];
    if (profile == null) {
      debugPrint('❌ Profile not found: $profileName');
      return;
    }
    
    _targetRefreshRate = profile.targetRate;
    _mode = profile.mode;
    
    // Apply profile settings
    await setMode(_mode);
    await setTargetRefreshRate(_targetRefreshRate);
    
    _refreshController.add(RefreshRateEvent(
      type: RefreshRateEventType.profileApplied,
      data: {
        'profile_name': profileName,
        'target_rate': profile.targetRate,
        'mode': profile.mode.toString(),
      },
    ));
    
    debugPrint('🔄 Applied refresh rate profile: $profileName');
  }

  void recordPerformanceMetrics({
    required double frameTime,
    required double cpuUsage,
    required double gpuUsage,
    required double powerUsage,
    bool? userActive,
    int? droppedFrames,
  }) async {
    final sample = RefreshRateSample(
      timestamp: DateTime.now(),
      frameTime: frameTime,
      cpuUsage: cpuUsage,
      gpuUsage: gpuUsage,
      powerUsage: powerUsage,
      userActive: userActive ?? true,
      droppedFrames: droppedFrames ?? 0,
      currentRefreshRate: _currentRefreshRate,
    );
    
    _performanceHistory.add(sample);
    if (_performanceHistory.length > _maxHistorySize) {
      _performanceHistory.removeFirst();
    }
    
    _refreshController.add(RefreshRateEvent(
      type: RefreshRateEventType.metricsRecorded,
      data: {
        'frame_time_ms': frameTime,
        'cpu_usage': cpuUsage,
        'gpu_usage': gpuUsage,
        'power_usage': powerUsage,
        'dropped_frames': droppedFrames,
      },
    ));
  }

  RefreshRateAnalysis getAnalysis() {
    if (_performanceHistory.isEmpty) {
      return RefreshRateAnalysis(
        currentRefreshRate: _currentRefreshRate,
        targetRefreshRate: _targetRefreshRate,
        mode: _mode,
        averageFrameTime: 0.0,
        averageCPUUsage: 0.0,
        averageGPUUsage: 0.0,
        averagePowerUsage: 0.0,
        droppedFrames: 0,
        efficiency: 0.0,
        recommendation: 'Insufficient data for analysis',
      );
    }
    
    final recentSamples = _performanceHistory.takeLast(60).toList(); // Last minute
    
    final avgFrameTime = recentSamples
        .map((s) => s.frameTime)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final avgCPU = recentSamples
        .map((s) => s.cpuUsage)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final avgGPU = recentSamples
        .map((s) => s.gpuUsage)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final avgPower = recentSamples
        .map((s) => s.powerUsage)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final totalDroppedFrames = recentSamples
        .map((s) => s.droppedFrames)
        .reduce((a, b) => a + b);
    
    final efficiency = _calculateEfficiency(avgFrameTime, avgCPU, avgGPU, avgPower);
    final recommendation = _generateRecommendation(avgFrameTime, avgCPU, avgGPU, avgPower, efficiency);
    
    return RefreshRateAnalysis(
      currentRefreshRate: _currentRefreshRate,
      targetRefreshRate: _targetRefreshRate,
      mode: _mode,
      averageFrameTime: avgFrameTime,
      averageCPUUsage: avgCPU,
      averageGPUUsage: avgGPU,
      averagePowerUsage: avgPower,
      droppedFrames: totalDroppedFrames,
      efficiency: efficiency,
      recommendation: recommendation,
    );
  }

  List<String> getAvailableProfiles() {
    return _profiles.keys.toList();
  }

  Map<String, dynamic> getStatistics() {
    return {
      'current_refresh_rate': _currentRefreshRate,
      'target_refresh_rate': _targetRefreshRate,
      'mode': _mode.toString(),
      'history_size': _performanceHistory.length,
      'profiles_count': _profiles.length,
      'min_rate': _minRefreshRate,
      'max_rate': _maxRefreshRate,
    };
  }

  Future<void> _detectDisplayCapabilities() async {
    // Simulate display capability detection
    final supportedRates = [30.0, 48.0, 60.0, 72.0, 90.0, 120.0, 144.0, 240.0];
    _currentRefreshRate = 60.0; // Default to 60Hz
    _targetRefreshRate = 60.0;
    
    debugPrint('🔄 Display capabilities detected: supported rates = $supportedRates');
  }

  void _loadDefaultProfiles() {
    _profiles['power_saving'] = RefreshProfile(
      name: 'power_saving',
      targetRate: 30.0,
      mode: RefreshRateMode.powerSaving,
      description: 'Maximum power efficiency',
      triggers: [
        RefreshTrigger(type: TriggerType.cpuUsage, threshold: 0.8),
        RefreshTrigger(type: TriggerType.powerUsage, threshold: 0.7),
      ],
    );
    
    _profiles['balanced'] = RefreshProfile(
      name: 'balanced',
      targetRate: 60.0,
      mode: RefreshRateMode.adaptive,
      description: 'Balanced performance and power',
      triggers: [
        RefreshTrigger(type: TriggerType.frameTime, threshold: 16.67),
        RefreshTrigger(type: TriggerType.cpuUsage, threshold: 0.9),
      ],
    );
    
    _profiles['performance'] = RefreshProfile(
      name: 'performance',
      targetRate: 120.0,
      mode: RefreshRateMode.performance,
      description: 'Maximum performance',
      triggers: [
        RefreshTrigger(type: TriggerType.userActivity, threshold: 0.5),
        RefreshTrigger(type: TriggerType.frameTime, threshold: 8.33),
      ],
    );
    
    _profiles['gaming'] = RefreshProfile(
      name: 'gaming',
      targetRate: 144.0,
      mode: RefreshRateMode.performance,
      description: 'Optimized for gaming',
      triggers: [
        RefreshTrigger(type: TriggerType.userActivity, threshold: 0.8),
        RefreshTrigger(type: TriggerType.frameTime, threshold: 6.94),
      ],
    );
  }

  void _startSampling() {
    _samplingTimer = Timer.periodic(_samplingInterval, (_) {
      _collectSample();
    });
  }

  void _startAdjustment() {
    _adjustmentTimer = Timer.periodic(_adjustmentInterval, (_) {
      if (_mode == RefreshRateMode.adaptive) {
        _adjustRefreshRate();
      }
    });
  }

  Future<void> _collectSample() async {
    // Simulate performance metrics collection
    final frameTime = 16.67 + (math.Random().nextDouble() - 0.5) * 10; // 11.67-21.67ms
    final cpuUsage = 0.3 + math.Random().nextDouble() * 0.4; // 30-70%
    final gpuUsage = 0.2 + math.Random().nextDouble() * 0.3; // 20-50%
    final powerUsage = 5.0 + math.Random().nextDouble() * 10.0; // 5-15W
    final userActive = math.Random().nextDouble() > 0.3; // 70% active
    final droppedFrames = math.Random().nextInt(3); // 0-2 dropped frames
    
    recordPerformanceMetrics(
      frameTime: frameTime,
      cpuUsage: cpuUsage,
      gpuUsage: gpuUsage,
      powerUsage: powerUsage,
      userActive: userActive,
      droppedFrames: droppedFrames,
    );
  }

  Future<void> _adjustRefreshRate() async {
    if (_performanceHistory.length < 10) return;
    
    final recentSamples = _performanceHistory.takeLast(30).toList();
    
    // Calculate performance indicators
    final avgFrameTime = recentSamples
        .map((s) => s.frameTime)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final avgCPU = recentSamples
        .map((s) => s.cpuUsage)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final avgGPU = recentSamples
        .map((s) => s.gpuUsage)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    final userActivityRatio = recentSamples
        .where((s) => s.userActive)
        .length / recentSamples.length;
    
    final droppedFrameRate = recentSamples
        .map((s) => s.droppedFrames)
        .reduce((a, b) => a + b) / recentSamples.length;
    
    // Determine optimal refresh rate
    double newRate = _currentRefreshRate;
    
    // Increase refresh rate for better performance
    if (avgFrameTime < 12.0 && avgCPU < 0.6 && avgGPU < 0.5 && userActivityRatio > 0.7) {
      newRate = math.min(_currentRefreshRate * 1.2, _maxRefreshRate);
    }
    
    // Decrease refresh rate for power savings
    if (avgCPU > 0.8 || avgGPU > 0.7 || droppedFrameRate > 1.0 || userActivityRatio < 0.3) {
      newRate = math.max(_currentRefreshRate * 0.8, _minRefreshRate);
    }
    
    // Apply change if significant
    if ((newRate - _currentRefreshRate).abs() > 5.0) {
      await _setRefreshRate(newRate);
    }
  }

  Future<void> _setRefreshRate(double rate) async {
    rate = rate.clamp(_minRefreshRate, _maxRefreshRate);
    
    if (_currentRefreshRate == rate) return;
    
    final oldRate = _currentRefreshRate;
    _currentRefreshRate = rate;
    
    // Simulate hardware refresh rate change
    await Future.delayed(Duration(milliseconds: 100));
    
    _refreshController.add(RefreshRateEvent(
      type: RefreshRateEventType.rateChanged,
      data: {
        'old_rate': oldRate,
        'new_rate': rate,
        'change_ms': (1000.0 / rate - 1000.0 / oldRate).abs(),
      },
    ));
    
    debugPrint('🔄 Refresh rate changed: ${oldRate}Hz → ${rate}Hz');
  }

  Future<void> _setFixedRefreshRate(double rate) async {
    await _setRefreshRate(rate);
  }

  void _enableAdaptiveMode() {
    _mode = RefreshRateMode.adaptive;
    debugPrint('🔄 Adaptive refresh rate mode enabled');
  }

  Future<void> _enablePowerSavingMode() async {
    await _setRefreshRate(_minRefreshRate);
    debugPrint('🔄 Power saving mode enabled');
  }

  Future<void> _enablePerformanceMode() async {
    await _setRefreshRate(_maxRefreshRate);
    debugPrint('🔄 Performance mode enabled');
  }

  double _calculateEfficiency(double frameTime, double cpuUsage, double gpuUsage, double powerUsage) {
    // Calculate efficiency score (0.0-1.0)
    final frameTimeScore = math.max(0.0, 1.0 - (frameTime - 16.67) / 16.67);
    final cpuScore = 1.0 - cpuUsage;
    final gpuScore = 1.0 - gpuUsage;
    final powerScore = math.max(0.0, 1.0 - powerUsage / 20.0); // Assuming 20W max
    
    return (frameTimeScore * 0.4 + cpuScore * 0.2 + gpuScore * 0.2 + powerScore * 0.2);
  }

  String _generateRecommendation(double frameTime, double cpuUsage, double gpuUsage, double powerUsage, double efficiency) {
    if (efficiency > 0.8) {
      return 'Current refresh rate is optimal';
    } else if (frameTime > 20.0) {
      return 'Consider lowering refresh rate to reduce frame drops';
    } else if (cpuUsage > 0.8 || gpuUsage > 0.7) {
      return 'Consider lowering refresh rate to reduce system load';
    } else if (powerUsage > 15.0) {
      return 'Consider power saving mode to reduce energy consumption';
    } else if (frameTime < 10.0 && efficiency < 0.6) {
      return 'Consider increasing refresh rate for better responsiveness';
    } else {
      return 'Current settings are acceptable';
    }
  }

  Future<void> dispose() async {
    _samplingTimer?.cancel();
    _adjustmentTimer?.cancel();
    _refreshController.close();
    _performanceHistory.clear();
    _profiles.clear();
    _isInitialized = false;
    
    debugPrint('🔄 Adaptive Refresh Rate disposed');
  }
}

/// Data classes
class RefreshRateSample {
  final DateTime timestamp;
  final double frameTime;
  final double cpuUsage;
  final double gpuUsage;
  final double powerUsage;
  final bool userActive;
  final int droppedFrames;
  final double currentRefreshRate;
  
  RefreshRateSample({
    required this.timestamp,
    required this.frameTime,
    required this.cpuUsage,
    required this.gpuUsage,
    required this.powerUsage,
    required this.userActive,
    required this.droppedFrames,
    required this.currentRefreshRate,
  });
  
  double get fps => currentRefreshRate;
  double get frameTimeMs => frameTime;
}

class RefreshProfile {
  final String name;
  final double targetRate;
  final RefreshRateMode mode;
  final String description;
  final List<RefreshTrigger> triggers;
  
  RefreshProfile({
    required this.name,
    required this.targetRate,
    required this.mode,
    required this.description,
    required this.triggers,
  });
}

class RefreshTrigger {
  final TriggerType type;
  final double threshold;
  final bool above; // true = trigger when above threshold, false = when below
  
  RefreshTrigger({
    required this.type,
    required this.threshold,
    this.above = true,
  });
}

class RefreshRateAnalysis {
  final double currentRefreshRate;
  final double targetRefreshRate;
  final RefreshRateMode mode;
  final double averageFrameTime;
  final double averageCPUUsage;
  final double averageGPUUsage;
  final double averagePowerUsage;
  final int droppedFrames;
  final double efficiency;
  final String recommendation;
  
  RefreshRateAnalysis({
    required this.currentRefreshRate,
    required this.targetRefreshRate,
    required this.mode,
    required this.averageFrameTime,
    required this.averageCPUUsage,
    required this.averageGPUUsage,
    required this.averagePowerUsage,
    required this.droppedFrames,
    required this.efficiency,
    required this.recommendation,
  });
  
  double get averageFPS => currentRefreshRate;
  double get frameTimeMs => averageFrameTime;
  String get efficiencyPercentage => '${(efficiency * 100).toStringAsFixed(1)}%';
}

class RefreshRateEvent {
  final RefreshRateEventType type;
  final Map<String, dynamic>? data;
  
  RefreshRateEvent({
    required this.type,
    this.data,
  });
}

enum RefreshRateMode {
  fixed,
  adaptive,
  powerSaving,
  performance,
}

enum TriggerType {
  frameTime,
  cpuUsage,
  gpuUsage,
  powerUsage,
  userActivity,
  droppedFrames,
}

enum RefreshRateEventType {
  modeChanged,
  targetChanged,
  rateChanged,
  profileApplied,
  metricsRecorded,
}
