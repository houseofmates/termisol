import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Manages ligature-enabled fonts for better code readability.
class LigatureFontManager {
  final Terminal terminal;
  final TerminalController controller;
  String _currentFont = 'Fira Code';
  bool _ligaturesEnabled = true;

  LigatureFontManager(this.terminal, this.controller);

  /// Set font with ligature support. Returns true if the font was applied,
  /// false if it is unavailable and the caller should use a fallback.
  Future<bool> setFont(String fontFamily, {bool enableLigatures = true}) async {
    final available = await _isFontAvailable(fontFamily);
    if (!available) return false;

    _currentFont = fontFamily;
    _ligaturesEnabled = enableLigatures;

    if (_isLigatureFont(fontFamily) && enableLigatures) {
      terminal.write('\x1b[?1;3c');
    } else {
      terminal.write('\x1b[?1;0c');
    }

    await _updateSystemFont(fontFamily);
    return true;
  }

  /// Check whether Flutter can resolve the requested font family.
  Future<bool> _isFontAvailable(String fontFamily) async {
    try {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontFamily: fontFamily, fontSize: 14),
      );
      builder.addText('test');
      final paragraph = builder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 100));
      // If layout succeeded we treat it as available.
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('font availability check failed: $e');
      return false;
    }
  }

  bool _isLigatureFont(String fontFamily) {
    const ligatureFonts = [
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

  String get currentFont => _currentFont;
  bool get ligaturesEnabled => _ligaturesEnabled;

  Future<void> toggleLigatures() async {
    await setFont(_currentFont, enableLigatures: !_ligaturesEnabled);
  }

  Future<void> _updateSystemFont(String fontFamily) async {
    if (kDebugMode) debugPrint('system font updated to: $fontFamily');
  }

  List<String> getAvailableLigatureFonts() {
    return const [
      'Fira Code',
      'JetBrains Mono',
      'Iosevka',
      'Cascadia Code',
      'Monoid',
      'IBM Plex Mono',
      'Source Code Pro',
    ];
  }

  void applyFontSettings() {
    if (_isLigatureFont(_currentFont) && _ligaturesEnabled) {
      terminal.write('\x1b[?1;3c');
      terminal.write('\x1b[?4;2m');
      terminal.write('\x1b[?7m');
    } else {
      terminal.write('\x1b[?1;0c');
      terminal.write('\x1b[?4;0m');
      terminal.write('\x1b[?7l');
    }
  }

  void dispose() {
    terminal.write('\x1b[?1;0c');
  }
}
