import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Professional Color Accuracy - Developer-focused color management
class ProfessionalColorAccuracy {
  static final ProfessionalColorAccuracy _instance = ProfessionalColorAccuracy._internal();
  factory ProfessionalColorAccuracy() => _instance;
  ProfessionalColorAccuracy._internal();

  bool _isInitialized = false;
  ColorProfile _currentProfile = ColorProfile.sRGB;
  ColorSpace _colorSpace = ColorSpace.sRGB;
  final Map<String, ColorCalibration> _calibrations = {};
  final Map<String, ColorProfile> _profiles = {};
  final List<ColorMeasurement> _measurementHistory = [];
  
  static const Duration _calibrationInterval = Duration(minutes: 30);
  static const int _maxHistorySize = 100;
  
  Timer? _calibrationTimer;
  final _colorController = StreamController<ColorAccuracyEvent>.broadcast();
  Stream<ColorAccuracyEvent> get events => _colorController.stream;
  
  bool get isInitialized => _isInitialized;
  ColorProfile get currentProfile => _currentProfile;
  ColorSpace get colorSpace => _colorSpace;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _detectDisplayCapabilities();
    _loadDefaultProfiles();
    _loadCalibrations();
    _startCalibrationTimer();
    
    _isInitialized = true;
    debugPrint('🎨 Professional Color Accuracy initialized');
  }

  Future<void> setColorProfile(ColorProfile profile) async {
    if (_currentProfile == profile) return;
    
    final oldProfile = _currentProfile;
    _currentProfile = profile;
    _colorSpace = _getColorSpaceForProfile(profile);
    
    // Apply color profile
    await _applyColorProfile(profile);
    
    _colorController.add(ColorAccuracyEvent(
      type: ColorAccuracyEventType.profileChanged,
      data: {
        'old_profile': oldProfile.toString(),
        'new_profile': profile.toString(),
        'color_space': _colorSpace.toString(),
      },
    ));
    
    debugPrint('🎨 Color profile changed: ${oldProfile.toString()} → ${profile.toString()}');
  }

  Future<void> setColorSpace(ColorSpace colorSpace) async {
    if (_colorSpace == colorSpace) return;
    
    final oldSpace = _colorSpace;
    _colorSpace = colorSpace;
    
    // Update profile to match color space
    _currentProfile = _getProfileForColorSpace(colorSpace);
    await _applyColorProfile(_currentProfile);
    
    _colorController.add(ColorAccuracyEvent(
      type: ColorAccuracyEventType.colorSpaceChanged,
      data: {
        'old_space': oldSpace.toString(),
        'new_space': colorSpace.toString(),
        'profile': _currentProfile.toString(),
      },
    ));
    
    debugPrint('🎨 Color space changed: ${oldSpace.toString()} → ${colorSpace.toString()}');
  }

  Future<ColorCalibrationResult> calibrateDisplay({
    required String displayName,
    CalibrationType type = CalibrationType.full,
    bool autoAdjust = true,
  }) async {
    try {
      debugPrint('🎨 Starting display calibration: $displayName');
      
      final calibration = await _performCalibration(displayName, type);
      
      if (autoAdjust) {
        await _applyCalibration(calibration);
      }
      
      _calibrations[displayName] = calibration;
      _measurementHistory.add(ColorMeasurement(
        timestamp: DateTime.now(),
        displayName: displayName,
        calibration: calibration,
        type: type,
      ));
      
      if (_measurementHistory.length > _maxHistorySize) {
        _measurementHistory.removeAt(0);
      }
      
      _colorController.add(ColorAccuracyEvent(
        type: ColorAccuracyEventType.calibrationCompleted,
        data: {
          'display_name': displayName,
          'calibration_type': type.toString(),
          'auto_adjust': autoAdjust,
          'accuracy': calibration.accuracy,
        },
      ));
      
      return ColorCalibrationResult.success(calibration);
      
    } catch (e) {
      debugPrint('❌ Calibration failed: $e');
      
      _colorController.add(ColorAccuracyEvent(
        type: ColorAccuracyEventType.calibrationFailed,
        data: {
          'display_name': displayName,
          'error': e.toString(),
        },
      ));
      
      return ColorCalibrationResult.error(e.toString());
    }
  }

  Future<ColorCorrectionResult> correctColor({
    required Color inputColor,
    ColorSpace? sourceSpace,
    ColorSpace? targetSpace,
    bool applyProfile = true,
  }) async {
    try {
      sourceSpace ??= _colorSpace;
      targetSpace ??= _colorSpace;
      
      final correctedColor = await _performColorCorrection(
        inputColor,
        sourceSpace,
        targetSpace,
        applyProfile,
      );
      
      return ColorCorrectionResult.success(correctedColor);
      
    } catch (e) {
      debugPrint('❌ Color correction failed: $e');
      return ColorCorrectionResult.error(e.toString());
    }
  }

  Future<ColorValidationResult> validateColor({
    required Color color,
    ColorSpace? colorSpace,
    ValidationLevel level = ValidationLevel.standard,
  }) async {
    try {
      colorSpace ??= _colorSpace;
      
      final validation = await _performColorValidation(color, colorSpace, level);
      
      return ColorValidationResult.success(validation);
      
    } catch (e) {
      debugPrint('❌ Color validation failed: $e');
      return ColorValidationResult.error(e.toString());
    }
  }

  List<ColorProfile> getAvailableProfiles() {
    return _profiles.values.toList();
  }

  List<ColorSpace> getAvailableColorSpaces() {
    return ColorSpace.values;
  }

  ColorCalibration? getCalibration(String displayName) {
    return _calibrations[displayName];
  }

  List<ColorMeasurement> getMeasurementHistory({String? displayName}) {
    if (displayName != null) {
      return _measurementHistory
          .where((m) => m.displayName == displayName)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    
    return _measurementHistory.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  ColorAnalysis getAnalysis() {
    if (_measurementHistory.isEmpty) {
      return ColorAnalysis(
        currentProfile: _currentProfile,
        colorSpace: _colorSpace,
        averageAccuracy: 0.0,
        lastCalibration: null,
        calibrationCount: 0,
        recommendations: ['No calibration data available'],
      );
    }
    
    final recentMeasurements = _measurementHistory.takeLast(10).toList();
    final averageAccuracy = recentMeasurements
        .map((m) => m.calibration.accuracy)
        .reduce((a, b) => a + b) / recentMeasurements.length;
    
    final lastCalibration = _measurementHistory.isNotEmpty
        ? _measurementHistory.last.timestamp
        : null;
    
    final recommendations = _generateRecommendations(averageAccuracy, recentMeasurements);
    
    return ColorAnalysis(
      currentProfile: _currentProfile,
      colorSpace: _colorSpace,
      averageAccuracy: averageAccuracy,
      lastCalibration: lastCalibration,
      calibrationCount: _measurementHistory.length,
      recommendations: recommendations,
    );
  }

  Map<String, dynamic> getStatistics() {
    return {
      'current_profile': _currentProfile.toString(),
      'color_space': _colorSpace.toString(),
      'calibrations_count': _calibrations.length,
      'measurement_history': _measurementHistory.length,
      'profiles_count': _profiles.length,
    };
  }

  Future<void> _detectDisplayCapabilities() async {
    // Simulate display capability detection
    final supportsHDR = true; // Would check actual display capabilities
    final supportsWideGamut = true;
    final supports10Bit = true;
    
    debugPrint('🎨 Display capabilities: HDR=$supportsHDR, WideGamut=$supportsWideGamut, 10bit=$supports10Bit');
  }

  void _loadDefaultProfiles() {
    _profiles['srgb'] = ColorProfile.sRGB;
    _profiles['p3'] = ColorProfile.displayP3;
    _profiles['rec2020'] = ColorProfile.rec2020;
    _profiles['adobe_rgb'] = ColorProfile.adobeRGB;
    _profiles['prophoto_rgb'] = ColorProfile.proPhotoRGB;
    _profiles['aces'] = ColorProfile.aces;
  }

  void _loadCalibrations() {
    // Load saved calibrations
    debugPrint('🎨 Loading saved calibrations...');
  }

  Future<void> _applyColorProfile(ColorProfile profile) async {
    // Simulate color profile application
    await Future.delayed(Duration(milliseconds: 50));
    
    switch (profile) {
      case ColorProfile.sRGB:
        debugPrint('🎨 Applied sRGB color profile');
        break;
      case ColorProfile.displayP3:
        debugPrint('🎨 Applied Display P3 color profile');
        break;
      case ColorProfile.rec2020:
        debugPrint('🎨 Applied Rec. 2020 color profile');
        break;
      case ColorProfile.adobeRGB:
        debugPrint('🎨 Applied Adobe RGB color profile');
        break;
      case ColorProfile.proPhotoRGB:
        debugPrint('🎨 Applied ProPhoto RGB color profile');
        break;
      case ColorProfile.aces:
        debugPrint('🎨 Applied ACES color profile');
        break;
    }
  }

  ColorSpace _getColorSpaceForProfile(ColorProfile profile) {
    switch (profile) {
      case ColorProfile.sRGB:
        return ColorSpace.sRGB;
      case ColorProfile.displayP3:
        return ColorSpace.displayP3;
      case ColorProfile.rec2020:
        return ColorSpace.rec2020;
      case ColorProfile.adobeRGB:
        return ColorSpace.adobeRGB;
      case ColorProfile.proPhotoRGB:
        return ColorSpace.proPhotoRGB;
      case ColorProfile.aces:
        return ColorSpace.aces;
    }
  }

  ColorProfile _getProfileForColorSpace(ColorSpace colorSpace) {
    switch (colorSpace) {
      case ColorSpace.sRGB:
        return ColorProfile.sRGB;
      case ColorSpace.displayP3:
        return ColorProfile.displayP3;
      case ColorSpace.rec2020:
        return ColorProfile.rec2020;
      case ColorSpace.adobeRGB:
        return ColorProfile.adobeRGB;
      case ColorSpace.proPhotoRGB:
        return ColorProfile.proPhotoRGB;
      case ColorSpace.aces:
        return ColorProfile.aces;
    }
  }

  Future<ColorCalibration> _performCalibration(String displayName, CalibrationType type) async {
    // Simulate calibration process
    await Future.delayed(Duration(seconds: 2));
    
    // Generate mock calibration data
    final accuracy = 0.85 + math.Random().nextDouble() * 0.14; // 85-99%
    final gamma = 2.2 + (math.Random().nextDouble() - 0.5) * 0.2; // 2.1-2.3
    final whitePoint = Color.fromRGB(255, 255, 255); // D65
    final primaries = _generatePrimaries(_colorSpace);
    
    return ColorCalibration(
      displayName: displayName,
      timestamp: DateTime.now(),
      type: type,
      accuracy: accuracy,
      gamma: gamma,
      whitePoint: whitePoint,
      primaries: primaries,
      colorSpace: _colorSpace,
      profile: _currentProfile,
    );
  }

  List<Color> _generatePrimaries(ColorSpace colorSpace) {
    switch (colorSpace) {
      case ColorSpace.sRGB:
        return [
          Color.fromRGB(255, 0, 0),   // Red
          Color.fromRGB(0, 255, 0),   // Green
          Color.fromRGB(0, 0, 255),   // Blue
        ];
      case ColorSpace.displayP3:
        return [
          Color.fromRGB(214, 0, 0),   // P3 Red
          Color.fromRGB(0, 237, 0),   // P3 Green
          Color.fromRGB(0, 0, 255),   // P3 Blue
        ];
      case ColorSpace.rec2020:
        return [
          Color.fromRGB(188, 0, 0),   // Rec. 2020 Red
          Color.fromRGB(0, 242, 0),   // Rec. 2020 Green
          Color.fromRGB(0, 0, 255),   // Rec. 2020 Blue
        ];
      default:
        return [
          Color.fromRGB(255, 0, 0),
          Color.fromRGB(0, 255, 0),
          Color.fromRGB(0, 0, 255),
        ];
    }
  }

  Future<void> _applyCalibration(ColorCalibration calibration) async {
    // Simulate applying calibration
    await Future.delayed(Duration(milliseconds: 100));
    
    debugPrint('🎨 Applied calibration for ${calibration.displayName}');
    debugPrint('   Accuracy: ${(calibration.accuracy * 100).toStringAsFixed(1)}%');
    debugPrint('   Gamma: ${calibration.gamma.toStringAsFixed(2)}');
  }

  Future<Color> _performColorCorrection(
    Color inputColor,
    ColorSpace sourceSpace,
    ColorSpace targetSpace,
    bool applyProfile,
  ) async {
    if (sourceSpace == targetSpace && !applyProfile) {
      return inputColor;
    }
    
    // Simulate color space conversion
    await Future.delayed(Duration(microseconds: 500));
    
    // Convert RGB values
    final sourceRGB = _colorToRGB(inputColor);
    final targetRGB = _convertRGBSpace(sourceRGB, sourceSpace, targetSpace);
    
    return Color.fromRGB(
      (targetRGB.r * 255).round(),
      (targetRGB.g * 255).round(),
      (targetRGB.b * 255).round(),
      inputColor.alpha,
    );
  }

  RGB _colorToRGB(Color color) {
    return RGB(
      r: color.red / 255.0,
      g: color.green / 255.0,
      b: color.blue / 255.0,
    );
  }

  RGB _convertRGBSpace(RGB sourceRGB, ColorSpace sourceSpace, ColorSpace targetSpace) {
    // Simulate color space conversion
    if (sourceSpace == targetSpace) {
      return sourceRGB;
    }
    
    // Simple matrix conversion (in reality would use proper conversion matrices)
    double r = sourceRGB.r;
    double g = sourceRGB.g;
    double b = sourceRGB.b;
    
    // Apply conversion based on space differences
    switch (sourceSpace) {
      case ColorSpace.sRGB:
        if (targetSpace == ColorSpace.displayP3) {
          r = r * 0.85;
          g = g * 0.93;
          b = b * 1.0;
        }
        break;
      case ColorSpace.displayP3:
        if (targetSpace == ColorSpace.sRGB) {
          r = r / 0.85;
          g = g / 0.93;
          b = b / 1.0;
        }
        break;
      default:
        break;
    }
    
    return RGB(r: r, g: g, b: b);
  }

  Future<ColorValidation> _performColorValidation(
    Color color,
    ColorSpace colorSpace,
    ValidationLevel level,
  ) async {
    // Simulate color validation
    await Future.delayed(Duration(microseconds: 200));
    
    final issues = <String>[];
    double score = 1.0;
    
    // Check for out-of-gamut colors
    if (!_isInGamut(color, colorSpace)) {
      issues.add('Color is out of gamut for ${colorSpace.toString()}');
      score -= 0.3;
    }
    
    // Check for invalid values
    if (color.red < 0 || color.red > 255 ||
        color.green < 0 || color.green > 255 ||
        color.blue < 0 || color.blue > 255) {
      issues.add('Color contains invalid RGB values');
      score -= 0.5;
    }
    
    // Check for very low saturation (level-specific)
    if (level == ValidationLevel.strict) {
      final saturation = _calculateSaturation(color);
      if (saturation < 0.1) {
        issues.add('Very low saturation detected');
        score -= 0.1;
      }
    }
    
    return ColorValidation(
      color: color,
      colorSpace: colorSpace,
      level: level,
      score: math.max(0.0, score),
      issues: issues,
      isValid: score > 0.7,
      timestamp: DateTime.now(),
    );
  }

  bool _isInGamut(Color color, ColorSpace colorSpace) {
    // Simplified gamut check
    switch (colorSpace) {
      case ColorSpace.sRGB:
        // sRGB has standard gamut
        return true;
      case ColorSpace.displayP3:
        // Display P3 has wider gamut
        return true;
      case ColorSpace.rec2020:
        // Rec. 2020 has very wide gamut
        return true;
      default:
        return true;
    }
  }

  double _calculateSaturation(Color color) {
    final max = math.max(color.red, math.max(color.green, color.blue));
    final min = math.min(color.red, math.min(color.green, color.blue));
    final chroma = max - min;
    final brightness = (max + min) / 2.0;
    
    return brightness == 0 ? 0.0 : chroma / (255.0 - brightness);
  }

  List<String> _generateRecommendations(double averageAccuracy, List<ColorMeasurement> measurements) {
    final recommendations = <String>[];
    
    if (averageAccuracy < 0.9) {
      recommendations.add('Consider recalibrating display for better accuracy');
    }
    
    if (measurements.length < 5) {
      recommendations.add('Perform regular calibrations for consistent color accuracy');
    }
    
    if (_currentProfile == ColorProfile.sRGB) {
      recommendations.add('Consider using Display P3 for wider color gamut');
    }
    
    if (measurements.isNotEmpty) {
      final lastCalibration = measurements.last.timestamp;
      final daysSinceCalibration = DateTime.now().difference(lastCalibration).inDays;
      
      if (daysSinceCalibration > 30) {
        recommendations.add('Display calibration is over 30 days old');
      }
    }
    
    return recommendations;
  }

  void _startCalibrationTimer() {
    _calibrationTimer = Timer.periodic(_calibrationInterval, (_) {
      _checkCalibrationStatus();
    });
  }

  void _checkCalibrationStatus() {
    if (_measurementHistory.isNotEmpty) {
      final lastCalibration = _measurementHistory.last.timestamp;
      final daysSinceCalibration = DateTime.now().difference(lastCalibration).inDays;
      
      if (daysSinceCalibration > 30) {
        _colorController.add(ColorAccuracyEvent(
          type: ColorAccuracyEventType.calibrationNeeded,
          data: {
            'days_since_calibration': daysSinceCalibration,
          },
        ));
        
        debugPrint('🎨 Calibration reminder: ${daysSinceCalibration} days since last calibration');
      }
    }
  }

  Future<void> dispose() async {
    _calibrationTimer?.cancel();
    _colorController.close();
    _calibrations.clear();
    _profiles.clear();
    _measurementHistory.clear();
    _isInitialized = false;
    
    debugPrint('🎨 Professional Color Accuracy disposed');
  }
}

/// Data classes
class ColorCalibration {
  final String displayName;
  final DateTime timestamp;
  final CalibrationType type;
  final double accuracy;
  final double gamma;
  final Color whitePoint;
  final List<Color> primaries;
  final ColorSpace colorSpace;
  final ColorProfile profile;
  
  ColorCalibration({
    required this.displayName,
    required this.timestamp,
    required this.type,
    required this.accuracy,
    required this.gamma,
    required this.whitePoint,
    required this.primaries,
    required this.colorSpace,
    required this.profile,
  });
  
  String get accuracyPercentage => '${(accuracy * 100).toStringAsFixed(1)}%';
}

class ColorMeasurement {
  final DateTime timestamp;
  final String displayName;
  final ColorCalibration calibration;
  final CalibrationType type;
  
  ColorMeasurement({
    required this.timestamp,
    required this.displayName,
    required this.calibration,
    required this.type,
  });
}

class ColorValidation {
  final Color color;
  final ColorSpace colorSpace;
  final ValidationLevel level;
  final double score;
  final List<String> issues;
  final bool isValid;
  final DateTime timestamp;
  
  ColorValidation({
    required this.color,
    required this.colorSpace,
    required this.level,
    required this.score,
    required this.issues,
    required this.isValid,
    required this.timestamp,
  });
  
  String get scorePercentage => '${(score * 100).toStringAsFixed(1)}%';
}

class ColorAnalysis {
  final ColorProfile currentProfile;
  final ColorSpace colorSpace;
  final double averageAccuracy;
  final DateTime? lastCalibration;
  final int calibrationCount;
  final List<String> recommendations;
  
  ColorAnalysis({
    required this.currentProfile,
    required this.colorSpace,
    required this.averageAccuracy,
    this.lastCalibration,
    required this.calibrationCount,
    required this.recommendations,
  });
  
  String get averageAccuracyPercentage => '${(averageAccuracy * 100).toStringAsFixed(1)}%';
}

class RGB {
  final double r;
  final double g;
  final double b;
  
  RGB({
    required this.r,
    required this.g,
    required this.b,
  });
}

class ColorCalibrationResult {
  final bool success;
  final ColorCalibration? calibration;
  final String? error;
  
  ColorCalibrationResult({
    required this.success,
    this.calibration,
    this.error,
  });
  
  factory ColorCalibrationResult.success(ColorCalibration calibration) {
    return ColorCalibrationResult(
      success: true,
      calibration: calibration,
    );
  }
  
  factory ColorCalibrationResult.error(String error) {
    return ColorCalibrationResult(
      success: false,
      error: error,
    );
  }
}

class ColorCorrectionResult {
  final bool success;
  final Color? correctedColor;
  final String? error;
  
  ColorCorrectionResult({
    required this.success,
    this.correctedColor,
    this.error,
  });
  
  factory ColorCorrectionResult.success(Color correctedColor) {
    return ColorCorrectionResult(
      success: true,
      correctedColor: correctedColor,
    );
  }
  
  factory ColorCorrectionResult.error(String error) {
    return ColorCorrectionResult(
      success: false,
      error: error,
    );
  }
}

class ColorValidationResult {
  final bool success;
  final ColorValidation? validation;
  final String? error;
  
  ColorValidationResult({
    required this.success,
    this.validation,
    this.error,
  });
  
  factory ColorValidationResult.success(ColorValidation validation) {
    return ColorValidationResult(
      success: true,
      validation: validation,
    );
  }
  
  factory ColorValidationResult.error(String error) {
    return ColorValidationResult(
      success: false,
      error: error,
    );
  }
}

class ColorAccuracyEvent {
  final ColorAccuracyEventType type;
  final Map<String, dynamic>? data;
  
  ColorAccuracyEvent({
    required this.type,
    this.data,
  });
}

enum ColorProfile {
  sRGB,
  displayP3,
  rec2020,
  adobeRGB,
  proPhotoRGB,
  aces,
}

enum ColorSpace {
  sRGB,
  displayP3,
  rec2020,
  adobeRGB,
  proPhotoRGB,
  aces,
}

enum CalibrationType {
  quick,
  standard,
  full,
  custom,
}

enum ValidationLevel {
  basic,
  standard,
  strict,
}

enum ColorAccuracyEventType {
  profileChanged,
  colorSpaceChanged,
  calibrationCompleted,
  calibrationFailed,
  calibrationNeeded,
}
