import 'dart:async';
import 'package:xterm/xterm.dart';
import 'package:flutter/services.dart';

/// Manages TrueColor (24-bit color) support for modern terminals.
/// Enables rich colors beyond the basic 16 ANSI palette.
class TrueColorManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;
  StreamSubscription? _oscSubscription;

  TrueColorManager(this.terminal, this.controller);

  /// Enable TrueColor support.
  void enable() {
    if (!_enabled) {
      _enabled = true;
      terminal.write('\x1b[?1;2c');
      debugPrint('✅ TrueColor enabled');
    }
  }

  /// Disable TrueColor support.
  void disable() {
    if (_enabled) {
      _enabled = false;
      terminal.write('\x1b[?0c');
      debugPrint('❌ TrueColor disabled');
    }
  }

  /// Check if TrueColor is enabled.
  bool get isEnabled => _enabled;

  /// Handle OSC sequences for TrueColor.
  void _handleOscSequence(String sequence) {
    if (!_enabled) return;

    // Parse TrueColor sequences (OSC 4, 10, 11, 12)
    if (sequence.startsWith('\x1b]10;') || sequence.startsWith('\x1b]11;')) {
      // Set foreground color (RGB)
      final match = RegExp(r'\x1b\](\d+);rgb:([\da-f]{6}/([\da-f]{6})([\da-f]{6})').firstMatch(sequence);
      if (match != null) {
        final r = int.tryParse(match.group(1)!, radix: 16) ?? 0;
        final g = int.tryParse(match.group(2)!, radix: 16) ?? 0;
        final b = int.tryParse(match.group(3)!, radix: 16) ?? 0;
        final color = Color.fromARGB(0xff, r, g, b);
        controller.setForegroundColor(color);
        debugPrint('🎨 TrueColor foreground: #$color');
      }
    } else if (sequence.startsWith('\x1b]12;')) {
      // Set background color (RGB)
      final match = RegExp(r'\x1b\](\d+);rgb:([\da-f]{6}/([\da-f]{6})([\da-f]{6})').firstMatch(sequence);
      if (match != null) {
        final r = int.tryParse(match.group(1)!, radix: 16) ?? 0;
        final g = int.tryParse(match.group(2)!, radix: 16) ?? 0;
        final b = int.tryParse(match.group(3)!, radix: 16) ?? 0;
        final color = Color.fromARGB(0xff, r, g, b);
        controller.setBackgroundColor(color);
        debugPrint('🎨 TrueColor background: #$color');
      }
    }
  }

  /// Start listening for OSC sequences.
  void startListening() {
    _oscSubscription = terminal.onOsc?.listen(_handleOscSequence);
  }

  /// Stop listening for OSC sequences.
  void stopListening() {
    _oscSubscription?.cancel();
    _oscSubscription = null;
  }

  void dispose() {
    stopListening();
  }
}
