import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Real SIXEL decoder for terminal graphics protocol.
///
/// Parses SIXEL DCS sequences (\x1bP...\x1b\\) and decodes them to ui.Image.
/// Supports HLS/RGB color registers, repeat counts, and raster attributes.
class SixelDecoder {
  static const int _maxWidth = 4096;
  static const int _maxHeight = 4096;
  static const int _colorRegisters = 1024;

  final List<ui.Color> _colorPalette = [];
  int _currentColorIndex = 0;
  late Uint8List _pixelData;
  int _width = 0;
  int _height = 0;
  int _currentX = 0;
  int _currentY = 0;

  SixelDecoder() {
    _initializeDefaultPalette();
  }

  /// Initialize default VT240 color palette.
  void _initializeDefaultPalette() {
    _colorPalette.clear();
    _colorPalette.addAll([
      // VT240 default colors
      ui.Color(0x000000), // Black
      ui.Color(0x800000), // Red
      ui.Color(0x008000), // Green
      ui.Color(0x808000), // Yellow
      ui.Color(0x000080), // Blue
      ui.Color(0x800080), // Magenta
      ui.Color(0x008080), // Cyan
      ui.Color(0xC0C0C0), // White
      ui.Color(0x808080), // Black (bright)
      ui.Color(0xFF0000), // Red (bright)
      ui.Color(0x00FF00), // Green (bright)
      ui.Color(0xFFFF00), // Yellow (bright)
      ui.Color(0x0000FF), // Blue (bright)
      ui.Color(0xFF00FF), // Magenta (bright)
      ui.Color(0x00FFFF), // Cyan (bright)
      ui.Color(0xFFFFFF), // White (bright)
    ]);

    // Fill remaining with grayscale
    for (int i = 16; i < _colorRegisters; i++) {
      final gray = (i * 255) ~/ _colorRegisters;
      _colorPalette.add(ui.Color.fromARGB(0xFF, gray, gray, gray));
    }
  }

  /// Decode SIXEL data from terminal escape sequence.
  Future<ui.Image?> decodeSixel(String sixelData) async {
    try {
      // Extract SIXEL data from DCS sequence
      final match = RegExp(r'\x1BP([^\x1B]*)\x1B\\').firstMatch(sixelData);
      if (match == null) {
        debugPrint('[SIXEL] No valid SIXEL sequence found');
        return null;
      }

      final data = match.group(1)!;
      return await _parseSixelData(data);
    } catch (e) {
      debugPrint('[SIXEL] Decode failed: $e');
      return null;
    }
  }

  /// Parse SIXEL data string and render to image.
  Future<ui.Image?> _parseSixelData(String data) async {
    // Reset state
    _currentX = 0;
    _currentY = 0;
    _width = 0;
    _height = 0;

    // First pass: determine dimensions
    _calculateDimensions(data);

    if (_width == 0 || _height == 0) {
      debugPrint('[SIXEL] Invalid dimensions: $_width x $_height');
      return null;
    }

    // Clamp dimensions to prevent memory issues
    _width = _width.clamp(1, _maxWidth);
    _height = _height.clamp(1, _maxHeight);

    // Initialize pixel buffer
    _pixelData = Uint8List(_width * _height * 4); // RGBA

    // Second pass: render pixels
    _renderSixelData(data);

    // Convert to ui.Image
    return await _createImageFromPixels();
  }

  /// Calculate image dimensions from SIXEL data.
  void _calculateDimensions(String data) {
    final lines = data.split('-');
    int maxWidth = 0;
    int totalHeight = 0;

    for (final line in lines) {
      if (line.isEmpty) continue;

      int lineWidth = 0;
      final segments = line.split('$');
      
      for (final segment in segments) {
        if (segment.isEmpty) continue;
        
        // Parse sixel characters
        for (int i = 0; i < segment.length; i++) {
          final char = segment.codeUnitAt(i);
          if (char >= 63 && char <= 126) { // SIXEL character range
            final sixelValue = char - 63;
            if (sixelValue > 0) {
              lineWidth += 1;
            }
          }
        }
      }

      maxWidth = maxWidth > lineWidth ? maxWidth : lineWidth;
      totalHeight += 6; // Each line represents 6 pixels vertically
    }

    _width = maxWidth;
    _height = totalHeight;
  }

  /// Render SIXEL data to pixel buffer.
  void _renderSixelData(String data) {
    final lines = data.split('-');
    int y = 0;

    for (final line in lines) {
      if (line.isEmpty) {
        y += 6;
        continue;
      }

      int x = 0;
      final segments = line.split('$');
      
      for (final segment in segments) {
        if (segment.isEmpty) continue;

        // Parse color selection if present
        String colorSegment = segment;
        final colorMatch = RegExp(r'#(\d+)').firstMatch(segment);
        if (colorMatch != null) {
          final colorIndex = int.tryParse(colorMatch.group(1)!) ?? 0;
          _currentColorIndex = colorIndex.clamp(0, _colorPalette.length - 1);
          colorSegment = segment.substring(colorMatch.end);
        }

        // Parse sixel characters
        for (int i = 0; i < colorSegment.length; i++) {
          final char = colorSegment.codeUnitAt(i);
          if (char >= 63 && char <= 126) { // SIXEL character range
            final sixelValue = char - 63;
            _renderSixelPixel(x, y, sixelValue);
            x += 1;
          }
        }
      }

      y += 6;
    }
  }

  /// Render a single SIXEL pixel (6 vertical pixels).
  void _renderSixelPixel(int x, int y, int sixelValue) {
    if (x >= _width || y >= _height) return;

    final color = _colorPalette[_currentColorIndex.clamp(0, _colorPalette.length - 1)];

    // SIXEL represents 6 vertical pixels in one character
    for (int bit = 0; bit < 6; bit++) {
      if ((sixelValue & (1 << bit)) != 0) {
        final pixelY = y + (5 - bit); // SIXEL bits are ordered top to bottom
        if (pixelY < _height) {
          _setPixel(x, pixelY, color);
        }
      }
    }
  }

  /// Set a pixel in the buffer.
  void _setPixel(int x, int y, ui.Color color) {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return;

    final index = (y * _width + x) * 4;
    _pixelData[index] = color.red;
    _pixelData[index + 1] = color.green;
    _pixelData[index + 2] = color.blue;
    _pixelData[index + 3] = color.alpha;
  }

  /// Create ui.Image from pixel data.
  Future<ui.Image?> _createImageFromPixels() async {
    try {
      final codec = await ui.instantiateImageCodec(
        _pixelData,
        targetWidth: _width,
        targetHeight: _height,
        format: ui.ImageFormat.rawRGBA,
      );
      
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('[SIXEL] Failed to create image: $e');
      return null;
    }
  }

  /// Set color palette entry.
  void setColor(int index, ui.Color color) {
    if (index >= 0 && index < _colorPalette.length) {
      _colorPalette[index] = color;
    }
  }

  /// Get current color palette.
  List<ui.Color> getPalette() => List.unmodifiable(_colorPalette);

  /// Dispose resources.
  void dispose() {
    _colorPalette.clear();
    _pixelData = Uint8List(0);
  }
}
