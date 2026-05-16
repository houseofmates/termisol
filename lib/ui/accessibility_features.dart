import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../config/pkm_theme.dart';

/// Comprehensive accessibility system with screen reader, high contrast, and navigation support.
class AccessibilityFeatures {
  static final AccessibilityFeatures _instance = AccessibilityFeatures._internal();
  factory AccessibilityFeatures() => _instance;
  AccessibilityFeatures._internal();

  bool _isInitialized = false;
  bool _screenReaderEnabled = false;
  bool _highContrastMode = false;
  bool _colorBlindMode = false;
  bool _reducedMotion = false;
  bool _keyboardNavigation = true;
  double _fontScale = 1.0;
  double _cursorScale = 1.0;
  ColorBlindType _colorBlindType = ColorBlindType.none;

  FlutterTts? _tts;
  final _focusNode = FocusNode();
  final _semanticsController = StreamController<SemanticsEvent>.broadcast();

  bool get isInitialized => _isInitialized;
  bool get screenReaderEnabled => _screenReaderEnabled;
  bool get highContrastMode => _highContrastMode;
  bool get colorBlindMode => _colorBlindMode;
  bool get reducedMotion => _reducedMotion;
  bool get keyboardNavigation => _keyboardNavigation;
  double get fontScale => _fontScale;
  double get cursorScale => _cursorScale;
  ColorBlindType get colorBlindType => _colorBlindType;
  Stream<SemanticsEvent> get semanticsEvents => _semanticsController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadSettings();
      await _initializeScreenReader();
      await _setupSystemAccessibility();
      _setupKeyboardNavigation();
      _setupSemanticsHandling();

      _isInitialized = true;
      debugPrint('Accessibility features initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize accessibility features: $e\n$stack');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _screenReaderEnabled = prefs.getBool('accessibility_screen_reader') ?? false;
      _highContrastMode = prefs.getBool('accessibility_high_contrast') ?? false;
      _colorBlindMode = prefs.getBool('accessibility_color_blind') ?? false;
      _reducedMotion = prefs.getBool('accessibility_reduced_motion') ?? false;
      _keyboardNavigation = prefs.getBool('accessibility_keyboard_nav') ?? true;
      _fontScale = prefs.getDouble('accessibility_font_scale') ?? 1.0;
      _cursorScale = prefs.getDouble('accessibility_cursor_scale') ?? 1.0;
      
      final colorBlindTypeIndex = prefs.getInt('accessibility_color_blind_type') ?? 0;
      _colorBlindType = ColorBlindType.values[colorBlindTypeIndex];
    } catch (e) {
      debugPrint('Failed to load accessibility settings: $e');
    }
  }

  Future<void> _initializeScreenReader() async {
    try {
      if (_screenReaderEnabled) {
        _tts = FlutterTts();
        await _tts!.setSharedInstance(true);
        await _tts!.setLanguage('en-US');
        await _tts!.setSpeechRate(0.5);
        debugPrint('Screen reader initialized');
      }
    } catch (e) {
      debugPrint('Failed to initialize screen reader: $e');
      _screenReaderEnabled = false;
    }
  }

  Future<void> _setupSystemAccessibility() async {
    try {
      // Check system accessibility settings
      if (Platform.isAndroid) {
        await _checkAndroidAccessibility();
      } else if (Platform.isIOS) {
        await _checkIOSAccessibility();
      } else if (Platform.isMacOS) {
        await _checkMacOSAccessibility();
      } else if (Platform.isWindows) {
        await _checkWindowsAccessibility();
      } else if (Platform.isLinux) {
        await _checkLinuxAccessibility();
      }
    } catch (e) {
      debugPrint('Failed to setup system accessibility: $e');
    }
  }

  Future<void> _checkAndroidAccessibility() async {
    try {
      const platform = MethodChannel('com.termisol/accessibility');
      final isScreenReaderOn = (await platform.invokeMethod('isScreenReaderOn') as bool?) ?? false;
      if (isScreenReaderOn && !_screenReaderEnabled) {
        await enableScreenReader(true);
      }
    } catch (e) {
      debugPrint('Failed to check Android accessibility: $e');
    }
  }

  Future<void> _checkIOSAccessibility() async {
    try {
      const platform = MethodChannel('com.termisol/accessibility');
      final isVoiceOverOn = (await platform.invokeMethod('isVoiceOverOn') as bool?) ?? false;
      if (isVoiceOverOn && !_screenReaderEnabled) {
        await enableScreenReader(true);
      }
    } catch (e) {
      debugPrint('Failed to check iOS accessibility: $e');
    }
  }

  Future<void> _checkMacOSAccessibility() async {
    try {
      const platform = MethodChannel('com.termisol/accessibility');
      final isVoiceOverOn = (await platform.invokeMethod('isVoiceOverOn') as bool?) ?? false;
      if (isVoiceOverOn && !_screenReaderEnabled) {
        await enableScreenReader(true);
      }
    } catch (e) {
      debugPrint('Failed to check macOS accessibility: $e');
    }
  }

  Future<void> _checkWindowsAccessibility() async {
    try {
      const platform = MethodChannel('com.termisol/accessibility');
      final isNarratorOn = (await platform.invokeMethod('isNarratorOn') as bool?) ?? false;
      if (isNarratorOn && !_screenReaderEnabled) {
        await enableScreenReader(true);
      }
    } catch (e) {
      debugPrint('Failed to check Windows accessibility: $e');
    }
  }

  Future<void> _checkLinuxAccessibility() async {
    try {
      const platform = MethodChannel('com.termisol/accessibility');
      final isScreenReaderOn = (await platform.invokeMethod('isScreenReaderOn') as bool?) ?? false;
      if (isScreenReaderOn && !_screenReaderEnabled) {
        await enableScreenReader(true);
      }
    } catch (e) {
      debugPrint('Failed to check Linux accessibility: $e');
    }
  }

  void _speak(String text) {
    // TODO: Implement TTS using platform channels
    debugPrint('TTS: $text');
  }
    } catch (e) {
      debugPrint('Failed to check Linux accessibility: $e');
    }
  }

  void _setupKeyboardNavigation() {
    if (_keyboardNavigation) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_keyboardNavigation) return false;

    // Handle accessibility keyboard shortcuts
    if (event is KeyDownEvent) {
      final isCtrl = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
      final isAlt = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
                    HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);

      if (isCtrl && isAlt) {
        switch (event.logicalKey.keyId) {
          case 0x00000061: // A key
            _toggleScreenReader();
            return true;
          case 0x00000068: // H key
            _toggleHighContrast();
            return true;
          case 0x00000066: // F key
            _increaseFontScale();
            return true;
          case 0x00000064: // D key
            _decreaseFontScale();
            return true;
        }
      }
    }

    return false;
  }

  void _setupSemanticsHandling() {
    SemanticsBinding.instance.addObserver(_handleSemanticsEvent);
  }

  void _handleSemanticsEvent(SemanticsEvent event) {
    if (_screenReaderEnabled && event is TapSemanticEvent) {
      _speak('Tapped ${event.label ?? 'element'}');
    }
  }

  Future<void> enableScreenReader(bool enabled) async {
    if (_screenReaderEnabled == enabled) return;

    try {
      _screenReaderEnabled = enabled;
      
      if (enabled) {
        await _initializeScreenReader();
        _speak('Screen reader enabled');
      } else {
        await _tts?.stop();
        _tts = null;
      }

      await _saveSettings();
      debugPrint('Screen reader ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Failed to toggle screen reader: $e');
    }
  }

  Future<void> enableHighContrast(bool enabled) async {
    if (_highContrastMode == enabled) return;

    try {
      _highContrastMode = enabled;
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('High contrast mode ${enabled ? 'enabled' : 'disabled'}');
      }
      
      debugPrint('High contrast ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Failed to toggle high contrast: $e');
    }
  }

  Future<void> enableColorBlindMode(bool enabled, {ColorBlindType? type}) async {
    if (_colorBlindMode == enabled && _colorBlindType == type) return;

    try {
      _colorBlindMode = enabled;
      if (type != null) {
        _colorBlindType = type;
      }
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('Color blind mode ${enabled ? 'enabled' : 'disabled'}');
      }
      
      debugPrint('Color blind mode ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Failed to toggle color blind mode: $e');
    }
  }

  Future<void> enableReducedMotion(bool enabled) async {
    if (_reducedMotion == enabled) return;

    try {
      _reducedMotion = enabled;
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('Reduced motion ${enabled ? 'enabled' : 'disabled'}');
      }
      
      debugPrint('Reduced motion ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Failed to toggle reduced motion: $e');
    }
  }

  Future<void> enableKeyboardNavigation(bool enabled) async {
    if (_keyboardNavigation == enabled) return;

    try {
      _keyboardNavigation = enabled;
      
      if (enabled) {
        HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      } else {
        HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      }
      
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('Keyboard navigation ${enabled ? 'enabled' : 'disabled'}');
      }
      
      debugPrint('Keyboard navigation ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Failed to toggle keyboard navigation: $e');
    }
  }

  Future<void> setFontScale(double scale) async {
    scale = scale.clamp(0.8, 2.0);
    if (_fontScale == scale) return;

    try {
      _fontScale = scale;
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('Font scale set to ${scale.toStringAsFixed(1)}');
      }
      
      debugPrint('Font scale set to $scale');
    } catch (e) {
      debugPrint('Failed to set font scale: $e');
    }
  }

  Future<void> setCursorScale(double scale) async {
    scale = scale.clamp(0.8, 3.0);
    if (_cursorScale == scale) return;

    try {
      _cursorScale = scale;
      await _saveSettings();
      
      if (_screenReaderEnabled) {
        _speak('Cursor scale set to ${scale.toStringAsFixed(1)}');
      }
      
      debugPrint('Cursor scale set to $scale');
    } catch (e) {
      debugPrint('Failed to set cursor scale: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('accessibility_screen_reader', _screenReaderEnabled);
      await prefs.setBool('accessibility_high_contrast', _highContrastMode);
      await prefs.setBool('accessibility_color_blind', _colorBlindMode);
      await prefs.setBool('accessibility_reduced_motion', _reducedMotion);
      await prefs.setBool('accessibility_keyboard_nav', _keyboardNavigation);
      await prefs.setDouble('accessibility_font_scale', _fontScale);
      await prefs.setDouble('accessibility_cursor_scale', _cursorScale);
      await prefs.setInt('accessibility_color_blind_type', _colorBlindType.index);
    } catch (e) {
      debugPrint('Failed to save accessibility settings: $e');
    }
  }

  Future<void> _toggleScreenReader() async {
    await enableScreenReader(!_screenReaderEnabled);
  }

  Future<void> _toggleHighContrast() async {
    await enableHighContrast(!_highContrastMode);
  }

  Future<void> _increaseFontScale() async {
    await setFontScale((_fontScale + 0.1).clamp(0.8, 2.0));
  }

  Future<void> _decreaseFontScale() async {
    await setFontScale((_fontScale - 0.1).clamp(0.8, 2.0));
  }

  Future<void> speak(String text) async {
    if (!_screenReaderEnabled || _tts == null) return;

    try {
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('Failed to speak: $e');
    }
  }

  Future<void> stopSpeaking() async {
    if (_tts == null) return;

    try {
      await _tts!.stop();
    } catch (e) {
      debugPrint('Failed to stop speaking: $e');
    }
  }

  Color adjustColor(Color color) {
    if (!_highContrastMode && !_colorBlindMode) return color;

    Color adjusted = color;

    if (_highContrastMode) {
      adjusted = _applyHighContrast(adjusted);
    }

    if (_colorBlindMode) {
      adjusted = _applyColorBlindFilter(adjusted);
    }

    return adjusted;
  }

  Color _applyHighContrast(Color color) {
    final hsl = HSLColor.fromColor(color);
    
    if (hsl.lightness > 0.5) {
      return HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.95).toColor();
    } else {
      return HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.05).toColor();
    }
  }

  Color _applyColorBlindFilter(Color color) {
    final hsl = HSLColor.fromColor(color);

    switch (_colorBlindType) {
      case ColorBlindType.protanopia:
        // Red-blind: shift reds to yellows/greens
        if (hsl.hue >= 0 && hsl.hue <= 60 || hsl.hue >= 300) {
          return HSLColor.fromAHSL(
            color.opacity,
            60, // Shift to yellow-green
            hsl.saturation * 0.8,
            hsl.lightness,
          ).toColor();
        }
        break;
      case ColorBlindType.deuteranopia:
        // Green-blind: shift greens to yellows/blues
        if (hsl.hue >= 60 && hsl.hue <= 180) {
          return HSLColor.fromAHSL(
            color.opacity,
            hsl.hue > 120 ? 240 : 30, // Shift to blue or yellow
            hsl.saturation * 0.8,
            hsl.lightness,
          ).toColor();
        }
        break;
      case ColorBlindType.tritanopia:
        // Blue-blind: shift blues to yellows/greens
        if (hsl.hue >= 180 && hsl.hue <= 300) {
          return HSLColor.fromAHSL(
            color.opacity,
            120, // Shift to green
            hsl.saturation * 0.8,
            hsl.lightness,
          ).toColor();
        }
        break;
      case ColorBlindType.achromatopsia:
        // Complete color blindness: convert to grayscale
        return color.withOpacity(color.opacity);
      case ColorBlindType.none:
        break;
    }

    return color;
  }

  TextStyle adjustTextStyle(TextStyle style) {
    return style.copyWith(
      fontSize: (style.fontSize ?? 14) * _fontScale,
      letterSpacing: _screenReaderEnabled ? 1.2 : style.letterSpacing,
      wordSpacing: _screenReaderEnabled ? 2.0 : style.wordSpacing,
    );
  }

  double adjustAnimationDuration(double duration) {
    return _reducedMotion ? 0.0 : duration;
  }

  Future<Map<String, dynamic>> getAccessibilityInfo() async {
    return {
      'screen_reader_enabled': _screenReaderEnabled,
      'high_contrast_mode': _highContrastMode,
      'color_blind_mode': _colorBlindMode,
      'color_blind_type': _colorBlindType.name,
      'reduced_motion': _reducedMotion,
      'keyboard_navigation': _keyboardNavigation,
      'font_scale': _fontScale,
      'cursor_scale': _cursorScale,
      'platform': Platform.operatingSystem,
    };
  }

  Future<void> dispose() async {
    try {
      await stopSpeaking();
      _tts = null;
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      SemanticsBinding.instance.removeObserver(_handleSemanticsEvent);
      await _semanticsController.close();
      debugPrint('Accessibility features disposed');
    } catch (e) {
      debugPrint('Error disposing accessibility features: $e');
    }
  }
}

enum ColorBlindType {
  none,
  protanopia,    // Red-blind
  deuteranopia,  // Green-blind
  tritanopia,    // Blue-blind
  achromatopsia, // Complete color blindness
}

/// Accessibility settings widget for configuration UI.
class AccessibilitySettingsWidget extends StatefulWidget {
  final AccessibilityFeatures accessibility;

  const AccessibilitySettingsWidget({
    super.key,
    required this.accessibility,
  });

  @override
  State<AccessibilitySettingsWidget> createState() => _AccessibilitySettingsWidgetState();
}

class _AccessibilitySettingsWidgetState extends State<AccessibilitySettingsWidget> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('vision'),
          _buildScreenReaderToggle(),
          _buildHighContrastToggle(),
          _buildColorBlindSection(),
          _buildFontScaleSlider(),
          const SizedBox(height: 24),
          _buildSectionTitle('interaction'),
          _buildReducedMotionToggle(),
          _buildKeyboardNavigationToggle(),
          _buildCursorScaleSlider(),
          const SizedBox(height: 24),
          _buildSectionTitle('shortcuts'),
          _buildKeyboardShortcuts(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: PkmTheme.primary,
          fontFamily: PkmTheme.fontUi,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScreenReaderToggle() {
    return _buildToggleTile(
      title: 'screen reader',
      subtitle: 'read interface elements aloud',
      icon: Icons.record_voice_over,
      value: widget.accessibility.screenReaderEnabled,
      onChanged: (value) => widget.accessibility.enableScreenReader(value),
    );
  }

  Widget _buildHighContrastToggle() {
    return _buildToggleTile(
      title: 'high contrast',
      subtitle: 'increase contrast for better visibility',
      icon: Icons.contrast,
      value: widget.accessibility.highContrastMode,
      onChanged: (value) => widget.accessibility.enableHighContrast(value),
    );
  }

  Widget _buildColorBlindSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToggleTile(
          title: 'color blind mode',
          subtitle: 'adjust colors for color vision deficiency',
          icon: Icons.visibility,
          value: widget.accessibility.colorBlindMode,
          onChanged: (value) => widget.accessibility.enableColorBlindMode(value),
        ),
        if (widget.accessibility.colorBlindMode) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: DropdownButtonFormField<ColorBlindType>(
              value: widget.accessibility.colorBlindType,
              decoration: InputDecoration(
                labelText: 'type',
                labelStyle: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontFamily: PkmTheme.fontUi,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: Colors.black.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              dropdownColor: PkmTheme.tabActiveBg,
              style: TextStyle(
                color: Colors.white,
                fontFamily: PkmTheme.fontUi,
                fontSize: 14,
              ),
              items: ColorBlindType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(
                    type.name.replaceFirst('_', ' ').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: PkmTheme.fontUi,
                      fontSize: 14,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (type) {
                if (type != null) {
                  widget.accessibility.enableColorBlindMode(true, type: type);
                }
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFontScaleSlider() {
    return _buildSliderTile(
      title: 'font scale',
      subtitle: 'adjust text size',
      icon: Icons.format_size,
      value: widget.accessibility.fontScale,
      min: 0.8,
      max: 2.0,
      divisions: 12,
      label: '${(widget.accessibility.fontScale * 100).toInt()}%',
      onChanged: (value) => widget.accessibility.setFontScale(value),
    );
  }

  Widget _buildReducedMotionToggle() {
    return _buildToggleTile(
      title: 'reduced motion',
      subtitle: 'minimize animations and transitions',
      icon: Icons.motion_photos_off,
      value: widget.accessibility.reducedMotion,
      onChanged: (value) => widget.accessibility.enableReducedMotion(value),
    );
  }

  Widget _buildKeyboardNavigationToggle() {
    return _buildToggleTile(
      title: 'keyboard navigation',
      subtitle: 'enable keyboard shortcuts and navigation',
      icon: Icons.keyboard,
      value: widget.accessibility.keyboardNavigation,
      onChanged: (value) => widget.accessibility.enableKeyboardNavigation(value),
    );
  }

  Widget _buildCursorScaleSlider() {
    return _buildSliderTile(
      title: 'cursor scale',
      subtitle: 'adjust cursor size',
      icon: Icons.text_fields,
      value: widget.accessibility.cursorScale,
      min: 0.8,
      max: 3.0,
      divisions: 22,
      label: '${(widget.accessibility.cursorScale * 100).toInt()}%',
      onChanged: (value) => widget.accessibility.setCursorScale(value),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            icon,
            color: PkmTheme.primary,
            size: 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontFamily: PkmTheme.fontUi,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontFamily: PkmTheme.fontUi,
              fontSize: 12,
            ),
          ),
          trailing: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: PkmTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: PkmTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: PkmTheme.fontUi,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontFamily: PkmTheme.fontUi,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: PkmTheme.primary,
                    fontFamily: PkmTheme.fontUi,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              activeColor: PkmTheme.primary,
              inactiveColor: Colors.grey.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardShortcuts() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'accessibility shortcuts',
            style: TextStyle(
              color: Colors.white,
              fontFamily: PkmTheme.fontUi,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildShortcut('Ctrl+Alt+A', 'toggle screen reader'),
          _buildShortcut('Ctrl+Alt+H', 'toggle high contrast'),
          _buildShortcut('Ctrl+Alt+F', 'increase font scale'),
          _buildShortcut('Ctrl+Alt+D', 'decrease font scale'),
        ],
      ),
    );
  }

  Widget _buildShortcut(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: PkmTheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              keys,
              style: TextStyle(
                color: PkmTheme.primary,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontFamily: PkmTheme.fontUi,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}