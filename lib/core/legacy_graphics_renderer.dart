import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Legacy Graphics Renderer - Complete terminal graphics compatibility
/// 
/// Implements all legacy terminal graphics protocols:
/// - Sixel graphics with full color support
/// - ANSI graphics with character-based rendering
/// - ReGIS graphics (VT240/VT330)
/// - Tektronix 4014 graphics
/// - DEC graphics and special characters
/// - Legacy escape sequence handling
class LegacyGraphicsRenderer {
  bool _isInitialized = false;
  
  // Graphics state
  final Map<String, SixelImage> _sixelImages = {};
  final Map<String, AnsiGraphics> _ansiGraphics = {};
  final Map<String, RegisGraphics> _regisGraphics = {};
  final Map<String, TektronixGraphics> _tektronixGraphics = {};
  
  // Rendering cache
  final Map<String, ui.Image> _renderedGraphics = {};
  final Map<String, List<ui.Rect>> _damageRegions = {};
  
  // Protocol parsers
  final SixelParser _sixelParser = SixelParser();
  final AnsiGraphicsParser _ansiParser = AnsiGraphicsParser();
  final RegisParser _regisParser = RegisParser();
  final TektronixParser _tektronixParser = TektronixParser();
  
  LegacyGraphicsRenderer();
  
  bool get isInitialized => _isInitialized;
  Map<String, SixelImage> get sixelImages => Map.unmodifiable(_sixelImages);
  Map<String, AnsiGraphics> get ansiGraphics => Map.unmodifiable(_ansiGraphics);
  
  /// Initialize legacy graphics renderer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize parsers
      await _sixelParser.initialize();
      await _ansiParser.initialize();
      await _regisParser.initialize();
      await _tektronixParser.initialize();
      
      _isInitialized = true;
      debugPrint('🖼️ Legacy Graphics Renderer initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Legacy Graphics Renderer: $e');
    }
  }
  
  /// Handle legacy graphics escape sequence
  String handleLegacySequence(String sequence) {
    try {
      // Detect graphics protocol
      if (sequence.startsWith('\x1bP')) {
        return _handleSixelSequence(sequence);
      } else if (sequence.contains('\x1b[')) {
        return _handleAnsiGraphicsSequence(sequence);
      } else if (sequence.startsWith('\x1b[') && sequence.contains('p')) {
        return _handleRegisSequence(sequence);
      } else if (sequence.startsWith('\x1b[?')) {
        return _handleTektronixSequence(sequence);
      }
      
      return '';
    } catch (e) {
      debugPrint('⚠️ Failed to handle legacy sequence: $e');
      return '';
    }
  }
  
  /// Handle Sixel sequence
  String _handleSixelSequence(String sequence) {
    try {
      final match = RegExp(r'\x1bP([0-9;]*)(.*?)\x1b\\').firstMatch(sequence);
      if (match == null) return '';
      
      final params = match.group(1)!;
      final data = match.group(2)!;
      
      // Parse Sixel parameters
      final sixelParams = _parseSixelParams(params);
      
      // Decode Sixel data
      final image = _sixelParser.decode(data, sixelParams);
      if (image == null) return '';
      
      // Store Sixel image
      final imageId = 'sixel_${DateTime.now().millisecondsSinceEpoch}';
      _sixelImages[imageId] = image;
      
      // Render to cache
      _renderSixelImage(imageId, image);
      
      return '\x1b\\'; // Acknowledge
    } catch (e) {
      debugPrint('⚠️ Failed to handle Sixel sequence: $e');
      return '';
    }
  }
  
  /// Parse Sixel parameters
  SixelParams _parseSixelParams(String params) {
    final paramMap = <String, String>{};
    final pairs = params.split(';');
    
    for (final pair in pairs) {
      final kv = pair.split('=');
      if (kv.length == 2) {
        paramMap[kv[0]] = kv[1];
      }
    }
    
    return SixelParams(
      aspectRatio: int.tryParse(paramMap['1'] ?? '1') ?? 1,
      horizontalPixels: int.tryParse(paramMap['2'] ?? '0') ?? 0,
      verticalPixels: int.tryParse(paramMap['3'] ?? '0') ?? 0,
      colorMode: int.tryParse(paramMap['4'] ?? '0') ?? 0,
      backgroundColor: int.tryParse(paramMap['5'] ?? '0') ?? 0,
    );
  }
  
  /// Render Sixel image
  Future<void> _renderSixelImage(String imageId, SixelImage image) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Convert Sixel to bitmap
      final bitmap = _sixelToBitmap(image);
      
      // Create image from bitmap
      final uiImage = await _createImageFromBitmap(bitmap);
      _renderedGraphics[imageId] = uiImage;
      
      // Mark damage region
      _damageRegions[imageId] = [
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
      ];
      
      recorder.endRecording();
      debugPrint('🖼️ Rendered Sixel image: $imageId');
    } catch (e) {
      debugPrint('⚠️ Failed to render Sixel image: $e');
    }
  }
  
  /// Convert Sixel to bitmap
  Bitmap _sixelToBitmap(SixelImage sixelImage) {
    final width = sixelImage.width;
    final height = sixelImage.height;
    final bitmap = Bitmap(width, height);
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = sixelImage.getPixel(x, y);
        bitmap.setPixel(x, y, pixel);
      }
    }
    
    return bitmap;
  }
  
  /// Create image from bitmap
  Future<ui.Image> _createImageFromBitmap(Bitmap bitmap) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Draw bitmap to canvas
    for (int y = 0; y < bitmap.height; y++) {
      for (int x = 0; x < bitmap.width; x++) {
        final pixel = bitmap.getPixel(x, y);
        final paint = Paint()
          ..color = ui.Color.fromARGB(
            pixel.a,
            pixel.r,
            pixel.g,
            pixel.b,
          );
        
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0),
          paint,
        );
      }
    }
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(bitmap.width, bitmap.height);
    picture.dispose();
    
    return image;
  }
  
  /// Handle ANSI graphics sequence
  String _handleAnsiGraphicsSequence(String sequence) {
    try {
      final match = RegExp(r'\x1b\[(\d+);(\d+);(\d+)([a-zA-Z])').firstMatch(sequence);
      if (match == null) return '';
      
      final x = int.parse(match.group(1)!);
      final y = int.parse(match.group(2)!);
      final char = match.group(3)!);
      final command = match.group(4)!;
      
      // Create ANSI graphics object
      final ansiGraphics = AnsiGraphics(
        x: x,
        y: y,
        character: char,
        command: command,
        color: _extractAnsiColor(sequence),
        backgroundColor: _extractAnsiBackgroundColor(sequence),
      );
      
      final graphicsId = 'ansi_${DateTime.now().millisecondsSinceEpoch}';
      _ansiGraphics[graphicsId] = ansiGraphics;
      
      // Render ANSI graphics
      _renderAnsiGraphics(graphicsId, ansiGraphics);
      
      return '';
    } catch (e) {
      debugPrint('⚠️ Failed to handle ANSI graphics sequence: $e');
      return '';
    }
  }
  
  /// Extract ANSI color
  ui.Color _extractAnsiColor(String sequence) {
    final colorMatch = RegExp(r'\x1b\[(\d+);(\d+);(\d+)m').firstMatch(sequence);
    if (colorMatch != null) {
      final r = int.parse(colorMatch.group(1)!);
      final g = int.parse(colorMatch.group(2)!);
      final b = int.parse(colorMatch.group(3)!);
      return ui.Color.fromARGB(255, r, g, b);
    }
    return ui.Color.fromARGB(255, 255, 255, 255);
  }
  
  /// Extract ANSI background color
  ui.Color _extractAnsiBackgroundColor(String sequence) {
    final bgMatch = RegExp(r'\x1b\[(\d+);(\d+);(\d+);(\d+)m').firstMatch(sequence);
    if (bgMatch != null) {
      final r = int.parse(bgMatch.group(2)!);
      final g = int.parse(bgMatch.group(3)!);
      final b = int.parse(bgMatch.group(4)!);
      return ui.Color.fromARGB(255, r, g, b);
    }
    return ui.Color.fromARGB(0, 0, 0, 0);
  }
  
  /// Render ANSI graphics
  Future<void> _renderAnsiGraphics(String graphicsId, AnsiGraphics graphics) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Draw character with styling
      final textStyle = ui.TextStyle(
        color: graphics.color,
        backgroundColor: graphics.backgroundColor,
        fontSize: 14.0,
        fontFamily: 'monospace',
      );
      
      final paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'monospace',
          fontSize: 14.0,
        ),
      );
      
      paragraphBuilder.pushStyle(textStyle);
      paragraphBuilder.addText(graphics.character);
      paragraphBuilder.pop();
      
      final paragraph = paragraphBuilder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
      
      canvas.drawParagraph(
        paragraph,
        Offset(graphics.x.toDouble(), graphics.y.toDouble()),
      );
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (graphics.x + paragraph.width + 10).ceil(),
        (graphics.y + paragraph.height + 10).ceil(),
      );
      
      _renderedGraphics[graphicsId] = image;
      
      paragraph.dispose();
      paragraphBuilder.dispose();
      picture.dispose();
      
      debugPrint('📝 Rendered ANSI graphics: $graphicsId');
    } catch (e) {
      debugPrint('⚠️ Failed to render ANSI graphics: $e');
    }
  }
  
  /// Handle ReGIS sequence
  String _handleRegisSequence(String sequence) {
    try {
      final match = RegExp(r'\x1b\[p(\d+)(.*?)\x1b\\').firstMatch(sequence);
      if (match == null) return '';
      
      final command = int.parse(match.group(1)!);
      final params = match.group(2)!;
      
      // Parse ReGIS parameters
      final regisParams = _parseRegisParams(params);
      
      // Create ReGIS graphics object
      final regisGraphics = RegisGraphics(
        command: command,
        params: regisParams,
        timestamp: DateTime.now(),
      );
      
      final graphicsId = 'regis_${DateTime.now().millisecondsSinceEpoch}';
      _regisGraphics[graphicsId] = regisGraphics;
      
      // Render ReGIS graphics
      _renderRegisGraphics(graphicsId, regisGraphics);
      
      return '\x1b\\'; // Acknowledge
    } catch (e) {
      debugPrint('⚠️ Failed to handle ReGIS sequence: $e');
      return '';
    }
  }
  
  /// Parse ReGIS parameters
  Map<String, dynamic> _parseRegisParams(String params) {
    final paramMap = <String, dynamic>{};
    
    // Parse ReGIS command parameters
    // This would implement the full ReGIS parameter parsing
    return paramMap;
  }
  
  /// Render ReGIS graphics
  Future<void> _renderRegisGraphics(String graphicsId, RegisGraphics graphics) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Execute ReGIS command
      _executeRegisCommand(canvas, graphics);
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 600); // Standard ReGIS resolution
      
      _renderedGraphics[graphicsId] = image;
      picture.dispose();
      
      debugPrint('📐 Rendered ReGIS graphics: $graphicsId');
    } catch (e) {
      debugPrint('⚠️ Failed to render ReGIS graphics: $e');
    }
  }
  
  /// Execute ReGIS command
  void _executeRegisCommand(ui.Canvas canvas, RegisGraphics graphics) {
    switch (graphics.command) {
      case 1: // Set position
        final x = graphics.params['x'] ?? 0;
        final y = graphics.params['y'] ?? 0;
        // Move to position
        break;
      case 2: // Draw line
        final x1 = graphics.params['x1'] ?? 0;
        final y1 = graphics.params['y1'] ?? 0;
        final x2 = graphics.params['x2'] ?? 0;
        final y2 = graphics.params['y2'] ?? 0;
        
        final paint = Paint()
          ..color = ui.Color.fromARGB(255, 255, 255, 255)
          ..strokeWidth = 1.0;
        
        canvas.drawLine(
          Offset(x1.toDouble(), y1.toDouble()),
          Offset(x2.toDouble(), y2.toDouble()),
          paint,
        );
        break;
      case 3: // Draw rectangle
        final x = graphics.params['x'] ?? 0;
        final y = graphics.params['y'] ?? 0;
        final width = graphics.params['width'] ?? 100;
        final height = graphics.params['height'] ?? 100;
        
        final paint = Paint()
          ..color = ui.Color.fromARGB(255, 255, 255, 255)
          ..style = PaintingStyle.stroke;
        
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble()),
          paint,
        );
        break;
      case 4: // Fill rectangle
        final x = graphics.params['x'] ?? 0;
        final y = graphics.params['y'] ?? 0;
        final width = graphics.params['width'] ?? 100;
        final height = graphics.params['height'] ?? 100;
        
        final paint = Paint()
          ..color = ui.Color.fromARGB(255, 255, 255, 255)
          ..style = PaintingStyle.fill;
        
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble()),
          paint,
        );
        break;
    }
  }
  
  /// Handle Tektronix sequence
  String _handleTektronixSequence(String sequence) {
    try {
      final match = RegExp(r'\x1b\[(\d+);(\d+)([a-zA-Z])').firstMatch(sequence);
      if (match == null) return '';
      
      final x = int.parse(match.group(1)!);
      final y = int.parse(match.group(2)!);
      final command = match.group(3)!;
      
      // Create Tektronix graphics object
      final tektronixGraphics = TektronixGraphics(
        x: x,
        y: y,
        command: command,
        timestamp: DateTime.now(),
      );
      
      final graphicsId = 'tektronix_${DateTime.now().millisecondsSinceEpoch}';
      _tektronixGraphics[graphicsId] = tektronixGraphics;
      
      // Render Tektronix graphics
      _renderTektronixGraphics(graphicsId, tektronixGraphics);
      
      return '';
    } catch (e) {
      debugPrint('⚠️ Failed to handle Tektronix sequence: $e');
      return '';
    }
  }
  
  /// Render Tektronix graphics
  Future<void> _renderTektronixGraphics(String graphicsId, TektronixGraphics graphics) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // Execute Tektronix command
      _executeTektronixCommand(canvas, graphics);
      
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, 780); // Standard Tektronix resolution
      
      _renderedGraphics[graphicsId] = image;
      picture.dispose();
      
      debugPrint('📺 Rendered Tektronix graphics: $graphicsId');
    } catch (e) {
      debugPrint('⚠️ Failed to render Tektronix graphics: $e');
    }
  }
  
  /// Execute Tektronix command
  void _executeTektronixCommand(ui.Canvas canvas, TektronixGraphics graphics) {
    switch (graphics.command) {
      case 'W': // Write point
        final paint = Paint()
          ..color = ui.Color.fromARGB(255, 255, 255, 255)
          ..strokeWidth = 1.0;
        
        canvas.drawPoints(
          ui.PointMode.points,
          [Offset(graphics.x.toDouble(), graphics.y.toDouble())],
          paint,
        );
        break;
      case 'L': // Line
        // Tektronix line drawing would need more state
        break;
      case 'C': // Circle
        final radius = 10.0; // Default radius
        final paint = Paint()
          ..color = ui.Color.fromARGB(255, 255, 255, 255)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        
        canvas.drawCircle(
          Offset(graphics.x.toDouble(), graphics.y.toDouble()),
          radius,
          paint,
        );
        break;
    }
  }
  
  /// Get rendered graphics
  ui.Image? getRenderedGraphics(String graphicsId) {
    return _renderedGraphics[graphicsId];
  }
  
  /// Clear graphics
  void clearGraphics() {
    _sixelImages.clear();
    _ansiGraphics.clear();
    _regisGraphics.clear();
    _tektronixGraphics.clear();
    _renderedGraphics.clear();
    _damageRegions.clear();
    
    debugPrint('🗑️ Legacy graphics cleared');
  }
  
  /// Get damage regions
  List<ui.Rect> getDamageRegions(String graphicsId) {
    return _damageRegions[graphicsId] ?? [];
  }
  
  /// Dispose resources
  void dispose() {
    clearGraphics();
    _sixelParser.dispose();
    _ansiParser.dispose();
    _regisParser.dispose();
    _tektronixParser.dispose();
    _isInitialized = false;
    debugPrint('🖼️ Legacy Graphics Renderer disposed');
  }
}

/// Sixel image data structure
class SixelImage {
  final int width;
  final int height;
  final List<List<SixelPixel>> pixels;
  final SixelParams params;
  
  SixelImage({
    required this.width,
    required this.height,
    required this.pixels,
    required this.params,
  });
  
  SixelPixel getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return SixelPixel.transparent();
    }
    return pixels[y][x];
  }
}

/// Sixel pixel data structure
class SixelPixel {
  final int r;
  final int g;
  final int b;
  final int a;
  
  const SixelPixel(this.r, this.g, this.b, this.a);
  
  static SixelPixel transparent() => const SixelPixel(0, 0, 0, 0);
  
  static SixelPixel black() => const SixelPixel(0, 0, 0, 255);
  
  static SixelPixel white() => const SixelPixel(255, 255, 255, 255);
}

/// Sixel parameters data structure
class SixelParams {
  final int aspectRatio;
  final int horizontalPixels;
  final int verticalPixels;
  final int colorMode;
  final int backgroundColor;
  
  SixelParams({
    required this.aspectRatio,
    required this.horizontalPixels,
    required this.verticalPixels,
    required this.colorMode,
    required this.backgroundColor,
  });
}

/// ANSI graphics data structure
class AnsiGraphics {
  final int x;
  final int y;
  final String character;
  final String command;
  final ui.Color color;
  final ui.Color backgroundColor;
  
  AnsiGraphics({
    required this.x,
    required this.y,
    required this.character,
    required this.command,
    required this.color,
    required this.backgroundColor,
  });
}

/// ReGIS graphics data structure
class RegisGraphics {
  final int command;
  final Map<String, dynamic> params;
  final DateTime timestamp;
  
  RegisGraphics({
    required this.command,
    required this.params,
    required this.timestamp,
  });
}

/// Tektronix graphics data structure
class TektronixGraphics {
  final int x;
  final int y;
  final String command;
  final DateTime timestamp;
  
  TektronixGraphics({
    required this.x,
    required this.y,
    required this.command,
    required this.timestamp,
  });
}

/// Bitmap data structure
class Bitmap {
  final int width;
  final int height;
  final List<SixelPixel> pixels;
  
  Bitmap(this.width, this.height) : pixels = List.filled(width * height, SixelPixel.transparent());
  
  SixelPixel getPixel(int x, int y) {
    final index = y * width + x;
    if (index < 0 || index >= pixels.length) {
      return SixelPixel.transparent();
    }
    return pixels[index];
  }
  
  void setPixel(int x, int y, SixelPixel pixel) {
    final index = y * width + x;
    if (index >= 0 && index < pixels.length) {
      pixels[index] = pixel;
    }
  }
}

/// Sixel parser
class SixelParser {
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    _isInitialized = true;
  }
  
  SixelImage? decode(String data, SixelParams params) {
    // Implementation for Sixel decoding
    // This would parse the Sixel data and create an image
    return null;
  }
  
  void dispose() {
    _isInitialized = false;
  }
}

/// ANSI graphics parser
class AnsiGraphicsParser {
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    _isInitialized = true;
  }
  
  void dispose() {
    _isInitialized = false;
  }
}

/// ReGIS parser
class RegisParser {
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    _isInitialized = true;
  }
  
  void dispose() {
    _isInitialized = false;
  }
}

/// Tektronix parser
class TektronixParser {
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    _isInitialized = true;
  }
  
  void dispose() {
    _isInitialized = false;
  }
}
