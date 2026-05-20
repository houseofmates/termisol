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

  /// enable kitty graphics protocol.
  void enable() {
    if (!_enabled) {
      _enabled = true;
      terminal.write('\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\');
      debugPrint('✅ Kitty Graphics Protocol enabled');
    }
  }

  /// disable kitty graphics protocol.
  void disable() {
    if (_enabled) {
      _enabled = false;
      terminal.write('\x1b_Ga=d\x1b\\');
      debugPrint('❌ Kitty Graphics Protocol disabled');
    }
  }

  /// check if kitty graphics is enabled.
  bool get isEnabled => _enabled;

  /// display an inline image using kitty graphics protocol.
  Future<void> displayImage(
    Uint8List imageData, {
    int width = 80,
    int height = 24,
    String format = 'png',
  }) async {
    if (!_enabled) return;

    try {
      // validate image size (kitty has limits)
      if (width > 4096 || height > 4096) {
        debugPrint('⚠️ Image too large for Kitty protocol');
        return;
      }

      // convert image to base64
      final base64Image = base64Encode(imageData);

      // build kitty graphics command
      final command = [
        'a=T', // transmit to terminal
        'f=${format.length},t=$format', // format and transmission
        'i=$_imageId', // image id
        's=$width,v=$height', // dimensions
        'C=1', // more control data
      ];

      final header = 'G${command.join(',')};';

      // send in chunks to avoid terminal buffer limits
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

  /// clear all displayed images.
  void clearImages() {
    if (_enabled) {
      terminal.write('\x1b_Ga=d,x=1,y=1,q=2\x1b\\');
      debugPrint('🧹 Cleared Kitty images');
    }
  }

  /// handle kitty graphics responses.
  void handleResponse(String response) {
    if (!_enabled) return;

    // parse kitty graphics responses for debugging
    if (response.startsWith('\x1b_G')) {
      debugPrint('📡 Kitty graphics response: $response');
    }
  }

  void dispose() {
    disable();
  }
}
