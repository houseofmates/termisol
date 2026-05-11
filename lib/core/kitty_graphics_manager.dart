import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// manages kitty graphics protocol for inline image rendering.
/// supports png, rgb, and 32-bit rgba formats.
class KittyGraphicsManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;
  int _imageId = 1;

  KittyGraphicsManager(this.terminal, this.controller);

  /// Enable Kitty graphics protocol.
  void enable() {
    if (!_enabled) {
      _enabled = true;
      terminal.write('\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\');
      debugPrint('✅ Kitty Graphics Protocol enabled');
    }
  }

  /// Disable Kitty graphics protocol.
  void disable() {
    if (_enabled) {
      _enabled = false;
      terminal.write('\x1b_Ga=d\x1b\\');
      debugPrint('❌ Kitty Graphics Protocol disabled');
    }
  }

  /// Check if Kitty graphics is enabled.
  bool get isEnabled => _enabled;

  /// Display an inline image using Kitty graphics protocol.
  Future<void> displayImage(
    Uint8List imageData, {
    int width = 80,
    int height = 24,
    String format = 'png',
  }) async {
    if (!_enabled) return;

    try {
      // Validate image size (Kitty has limits)
      if (width > 4096 || height > 4096) {
        debugPrint('⚠️ Image too large for Kitty protocol');
        return;
      }

      // Convert image to base64
      final base64Image = base64Encode(imageData);

      // Build Kitty graphics command
      final command = [
        'a=T', // Transmit to terminal
        'f=${format.length},t=$format', // Format and transmission
        'i=$_imageId', // Image ID
        's=$width,v=$height', // Dimensions
        'C=1', // More control data
      ];

      final header = 'G${command.join(',')};';

      // Send in chunks to avoid terminal buffer limits
      const chunkSize = 4096;
      for (int i = 0; i < base64Image.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, base64Image.length);
        final chunk = base64Image.substring(i, end);
        final isLast = end >= base64Image.length;
        final chunkHeader = isLast ? 'm=1;' : 'm=0;';

        terminal.write('\x1b_G$header${chunkHeader}$chunk\x1b\\');
      }

      _imageId++;
      debugPrint('🖼️ Displayed Kitty image (${width}x$height)');
    } catch (e) {
      debugPrint('❌ Error displaying Kitty image: $e');
    }
  }

  /// Clear all displayed images.
  void clearImages() {
    if (_enabled) {
      terminal.write('\x1b_Ga=d,x=1,y=1,q=2\x1b\\');
      debugPrint('🧹 Cleared Kitty images');
    }
  }

  /// Handle Kitty graphics responses.
  void handleResponse(String response) {
    if (!_enabled) return;

    // Parse Kitty graphics responses for debugging
    if (response.startsWith('\x1b_G')) {
      debugPrint('📡 Kitty graphics response: $response');
    }
  }

  void dispose() {
    disable();
  }
}
