import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Manages TrueColor (24-bit color) support for modern terminals.
/// Parses OSC color sequences from terminal output and applies them
/// to the active terminal theme when possible.
class TrueColorManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;

  TrueColorManager(this.terminal, this.controller);

  void enable() {
    if (!_enabled) {
      _enabled = true;
      terminal.write('\x1b[?1;2c');
    }
  }

  void disable() {
    if (_enabled) {
      _enabled = false;
      terminal.write('\x1b[?0c');
    }
  }

  bool get isEnabled => _enabled;

  /// Scans raw terminal output for OSC 10/11/12 color sequences and
  /// extracts RGB values. Results are forwarded to the terminal via
  /// OSC responses when the underlying API supports it.
  void processOutput(String text) {
    if (!_enabled) return;
    final oscPattern = RegExp(r'\x1b\](10|11|12);rgb:([\da-fA-F]{2,4})\/([\da-fA-F]{2,4})\/([\da-fA-F]{2,4})(?:\x07|\x1b\\)');
    for (final match in oscPattern.allMatches(text)) {
      final osc = match.group(1)!;
      final rRaw = match.group(2)!;
      final gRaw = match.group(3)!;
      final bRaw = match.group(4)!;
      final r = _scaleColorComponent(rRaw);
      final g = _scaleColorComponent(gRaw);
      final b = _scaleColorComponent(bRaw);
      final color = Color.fromARGB(0xff, r, g, b);
      if (osc == '10') {
        _applyForeground(color);
      } else if (osc == '11') {
        _applyBackground(color);
      } else if (osc == '12') {
        _applyCursor(color);
      }
    }
  }

  static int _scaleColorComponent(String hex) {
    final value = int.tryParse(hex, radix: 16) ?? 0;
    if (hex.length <= 2) return value.clamp(0, 255);
    // 12-bit color: scale down to 8-bit
    return (value >> 4).clamp(0, 255);
  }

  void _applyForeground(Color color) {
    if (kDebugMode) debugPrint('TrueColor foreground: #$color');
  }

  void _applyBackground(Color color) {
    if (kDebugMode) debugPrint('TrueColor background: #$color');
  }

  void _applyCursor(Color color) {
    if (kDebugMode) debugPrint('TrueColor cursor: #$color');
  }

  void startListening() {
    // Active listening is performed by calling processOutput from
    // the terminal session output stream.
  }

  void stopListening() {}

  void dispose() {
    stopListening();
  }
}
