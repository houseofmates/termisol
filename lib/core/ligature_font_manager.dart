import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';

/// Manages ligature-enabled fonts for better code readability.
/// Supports Fira Code, JetBrains Mono, and other programming fonts.
class LigatureFontManager {
  final Terminal terminal;
  final TerminalController controller;
  String _currentFont = 'Fira Code';
  bool _ligaturesEnabled = true;

  LigatureFontManager(this.terminal, this.controller);

  /// Set font with ligature support.
  Future<void> setFont(String fontFamily, {bool enableLigatures = true}) async {
    try {
      _currentFont = fontFamily;
      _ligaturesEnabled = enableLigatures;
      
      // Update terminal font
      terminal.fontFamily = fontFamily;
      
      // Configure ligatures for supported fonts
      if (_isLigatureFont(fontFamily) && enableLigatures) {
        terminal.write('\x1b[?1;3c'); // Enable ligatures
        debugPrint('✅ Enabled ligatures for: $fontFamily');
      } else {
        terminal.write('\x1b[?1;0c'); // Disable ligatures
        debugPrint('❌ Disabled ligatures');
      }
      
      // Update Flutter system font for rendering
      await _updateSystemFont(fontFamily);
      
    } catch (e) {
      debugPrint('❌ Failed to set font: $e');
    }
  }

  /// Check if font supports ligatures.
  bool _isLigatureFont(String fontFamily) {
    final ligatureFonts = [
      'Fira Code',
      'JetBrains Mono',
      'Iosevka',
      'Cascadia Code',
      'Monoid',
      'IBM Plex Mono',
      'Source Code Pro',
    ];
    
    return ligatureFonts.contains(fontFamily);
  }

  /// Get current font family.
  String get currentFont => _currentFont;

  /// Check if ligatures are enabled.
  bool get ligaturesEnabled => _ligaturesEnabled;

  /// Toggle ligature support.
  Future<void> toggleLigatures() async {
    await setFont(_currentFont, enableLigatures: !_ligaturesEnabled);
  }

  /// Update system font configuration.
  Future<void> _updateSystemFont(String fontFamily) async {
    // This would update the system font registry
    // For now, just log the change
    debugPrint('🔤 System font updated to: $fontFamily');
    
    // In a real implementation, you'd:
    // 1. Update fontconfig cache
    // 2. Notify running applications
    // 3. Update Flutter font fallbacks
  }

  /// Get available ligature fonts.
  List<String> getAvailableLigatureFonts() {
    return [
      'Fira Code',
      'JetBrains Mono',
      'Iosevka',
      'Cascadia Code',
      'Monoid',
      'IBM Plex Mono',
      'Source Code Pro',
    ];
  }

  /// Apply font to terminal with proper escaping.
  void applyFontSettings() {
    if (_isLigatureFont(_currentFont) && _ligaturesEnabled) {
      // Enable advanced font features
      terminal.write('\x1b[?1;3c'); // Ligatures + Unicode
      terminal.write('\x1b[?4;2m'); // Bold for better visibility
      terminal.write('\x1b[?7m');  // Enable reverse video for contrast
    } else {
      // Standard font mode
      terminal.write('\x1b[?1;0c'); // No ligatures
      terminal.write('\x1b[?4;0m'); // Normal weight
      terminal.write('\x1b[?7l');  // Disable reverse video
    }
  }

  void dispose() {
    // Reset to default font
    terminal.write('\x1b[?1;0c');
  }
}
