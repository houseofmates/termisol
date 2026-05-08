import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// ASCII Art Renderer - Perfect character grid alignment for ASCII art
/// 
/// Implements industry-leading ASCII art rendering:
/// - Character-level grid alignment with zero offset
/// - Box drawing character optimization
/// - Block character perfect alignment
/// - Monospace grid precision
/// - Anti-aliasing control for sharp edges
class AsciiArtRenderer {
  static const double _defaultFontSize = 14.0;
  static const double _charWidth = 8.4; // Standard monospace character width
  static const double _charHeight = 16.8; // Standard monospace character height
  static const double _baselineOffset = 0.0; // Zero offset for perfect alignment
  
  bool _isInitialized = false;
  ui.ParagraphBuilder? _paragraphBuilder;
  ui.ParagraphStyle? _paragraphStyle;
  ui.TextStyle? _textStyle;
  
  // Grid alignment cache
  final Map<String, ui.Image> _charCache = {};
  final Map<int, double> _charWidths = {};
  final Map<int, ui.Rect> _charBounds = {};
  
  // Box drawing characters (Unicode block elements)
  static const Set<int> _boxDrawingChars = {
    0x2500, 0x2501, 0x2502, 0x2503, 0x2504, 0x2505, 0x2506, 0x2507,
    0x2508, 0x2509, 0x250A, 0x250B, 0x250C, 0x250D, 0x250E, 0x250F,
    0x2510, 0x2511, 0x2512, 0x2513, 0x2514, 0x2515, 0x2516, 0x2517,
    0x2518, 0x2519, 0x251A, 0x251B, 0x251C, 0x251D, 0x251E, 0x251F,
    0x2520, 0x2521, 0x2522, 0x2523, 0x2524, 0x2525, 0x2526, 0x2527,
    0x2528, 0x2529, 0x252A, 0x252B, 0x252C, 0x252D, 0x252E, 0x252F,
    0x2530, 0x2531, 0x2532, 0x2533, 0x2534, 0x2535, 0x2536, 0x2537,
    0x2538, 0x2539, 0x253A, 0x253B, 0x253C, 0x253D, 0x253E, 0x253F,
    0x2540, 0x2541, 0x2542, 0x2543, 0x2544, 0x2545, 0x2546, 0x2547,
    0x2548, 0x2549, 0x254A, 0x254B, 0x254C, 0x254D, 0x254E, 0x254F,
    0x2550, 0x2551, 0x2552, 0x2553, 0x2554, 0x2555, 0x2556, 0x2557,
    0x2558, 0x2559, 0x255A, 0x255B, 0x255C, 0x255D, 0x255E, 0x255F,
    0x2560, 0x2561, 0x2562, 0x2563, 0x2564, 0x2565, 0x2566, 0x2567,
    0x2568, 0x2569, 0x256A, 0x256B, 0x256C, 0x256D, 0x256E, 0x256F,
    0x2570, 0x2571, 0x2572, 0x2573, 0x2574, 0x2575, 0x2576, 0x2577,
    0x2578, 0x2579, 0x257A, 0x257B, 0x257C, 0x257D, 0x257E, 0x257F,
  };
  
  // Block characters (Unicode block elements)
  static const Set<int> _blockChars = {
    0x2580, 0x2581, 0x2582, 0x2583, 0x2584, 0x2585, 0x2586, 0x2587,
    0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F,
    0x2590, 0x2591, 0x2592, 0x2593, 0x2594, 0x2595, 0x2596, 0x2597,
    0x2598, 0x2599, 0x259A, 0x259B, 0x259C, 0x259D, 0x259E, 0x259F,
  };
  
  // ASCII art characters that need special alignment
  static const Set<int> _asciiArtChars = {
    ..._boxDrawingChars,
    ..._blockChars,
    0x00A0, // Non-breaking space
    0x00B7, // Middle dot
    0x2022, // Bullet
    0x2219, // Bullet operator
    0x25CB, // White circle
    0x25CF, // Black circle
    0x25AA, // Black small square
    0x25AB, // White small square
    0x25A0, // Black square
    0x25A1, // White square
    0x25C6, // Black diamond
    0x25C7, // White diamond
    0x25BC, // Black triangle down
    0x25B2, // Black triangle up
    0x25C8, // White diamond containing black small diamond
  };
  
  String _currentFontFamily = 'JetBrains Mono';
  double _currentFontSize = _defaultFontSize;
  
  AsciiArtRenderer();
  
  bool get isInitialized => _isInitialized;
  String get currentFontFamily => _currentFontFamily;
  double get currentFontSize => _currentFontSize;
  
  /// Initialize ASCII art renderer with grid alignment
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load monospace fonts
      await _loadMonospaceFonts();
      
      // Setup paragraph styles for perfect alignment
      _paragraphStyle = ui.ParagraphStyle(
        fontFamily: _currentFontFamily,
        fontSize: _currentFontSize,
        height: 1.0, // Perfect line height
        textDirection: ui.TextDirection.ltr,
        textAlign: ui.TextAlign.left,
        fontWeight: ui.FontWeight.normal,
        fontStyle: ui.FontStyle.normal,
        strutStyle: const ui.StrutStyle(
          fontSize: _defaultFontSize,
          height: 1.0,
          leading: 0.0,
          forceStrutHeight: true,
        ),
      );
      
      _textStyle = ui.TextStyle(
        fontFamily: _currentFontFamily,
        fontSize: _currentFontSize,
        color: ui.Color.fromRGBO(255, 255, 255, 1.0),
        fontWeight: ui.FontWeight.normal,
        fontStyle: ui.FontStyle.normal,
        letterSpacing: 0.0, // No letter spacing for perfect alignment
        wordSpacing: 0.0, // No word spacing for perfect alignment
        height: 1.0, // Perfect line height
        decoration: ui.TextDecoration.none,
        decorationColor: ui.Color.transparent,
      );
      
      // Pre-cache common ASCII art characters
      await _precacheAsciiArtChars();
      
      _isInitialized = true;
      debugPrint('🎨 ASCII Art Renderer initialized with perfect grid alignment');
    } catch (e) {
      debugPrint('❌ Failed to initialize ASCII Art Renderer: $e');
      rethrow;
    }
  }
  
  /// Load monospace fonts for ASCII art
  Future<void> _loadMonospaceFonts() async {
    final fontFamilies = [
      'JetBrains Mono',
      'Fira Code',
      'Cascadia Code',
      'Consolas',
      'Monaco',
      'Ubuntu Mono',
      'Source Code Pro',
      'IBM Plex Mono',
      'Space Mono',
    ];
    
    for (final fontFamily in fontFamilies) {
      try {
        final fontData = await rootBundle.load('assets/fonts/${fontFamily.toLowerCase().replaceAll(' ', '_')}.ttf');
        final font = await ui.instantiateImageCodec(fontData.buffer.asUint8List());
        debugPrint('📝 Loaded monospace font: $fontFamily');
      } catch (e) {
        // Font not available, continue with next
        continue;
      }
    }
  }
  
  /// Pre-cache ASCII art characters for optimal rendering
  Future<void> _precacheAsciiArtChars() async {
    for (final charCode in _asciiArtChars) {
      final char = String.fromCharCode(charCode);
      await _renderCharacterToCache(char);
    }
    debugPrint('🎨 Pre-cached ${_asciiArtChars.length} ASCII art characters');
  }
  
  /// Render single character to cache
  Future<void> _renderCharacterToCache(String char) async {
    if (_charCache.containsKey(char)) return;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    final builder = ui.ParagraphBuilder(_paragraphStyle!);
    builder.pushStyle(_textStyle!);
    builder.addText(char);
    builder.pop();
    
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    
    // Render with zero offset for perfect alignment
    canvas.drawParagraph(paragraph, Offset.zero);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      _charWidth.ceil(),
      _charHeight.ceil(),
    );
    
    _charCache[char] = image;
    picture.dispose();
  }
  
  /// Check if character is ASCII art character
  bool _isAsciiArtChar(int charCode) {
    return _asciiArtChars.contains(charCode) ||
           (charCode >= 0x2500 && charCode <= 0x257F) || // Box drawing
           (charCode >= 0x2580 && charCode <= 0x259F) || // Block elements
           (charCode >= 0x25A0 && charCode <= 0x25FF);   // Geometric shapes
  }
  
  /// Check if text contains ASCII art
  bool _containsAsciiArt(String text) {
    for (final char in text.runes) {
      if (_isAsciiArtChar(char)) {
        return true;
      }
    }
    return false;
  }
  
  /// Render text with perfect ASCII art alignment
  Future<ui.Image> renderText(
    String text, {
    double fontSize = _defaultFontSize,
    ui.Color? color,
    bool enableGridAlignment = true,
    bool optimizeBoxDrawing = true,
    bool zeroOffsetBlockChars = true,
  }) async {
    if (!_isInitialized) await initialize();
    
    // If no ASCII art detected, use standard rendering
    if (!enableGridAlignment || !_containsAsciiArt(text)) {
      return _renderStandardText(text, fontSize, color);
    }
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Calculate grid dimensions
    final lines = text.split('\n');
    final maxWidth = lines.map((line) => line.length).reduce(math.max);
    final gridWidth = maxWidth * _charWidth;
    final gridHeight = lines.length * _charHeight;
    
    // Set canvas size to exact grid dimensions
    canvas.clipRect(Rect.fromLTWH(0, 0, gridWidth, gridHeight));
    
    // Render each line with perfect grid alignment
    double y = 0.0;
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      double x = 0.0;
      
      for (int charIndex = 0; charIndex < line.length; charIndex++) {
        final char = line[charIndex];
        final charCode = char.runes.first;
        
        if (_isAsciiArtChar(charCode)) {
          // Render ASCII art character with perfect alignment
          await _renderAsciiArtChar(canvas, char, x, y, color);
        } else {
          // Render regular character with grid alignment
          await _renderRegularChar(canvas, char, x, y, color);
        }
        
        x += _charWidth;
      }
      
      y += _charHeight;
    }
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      gridWidth.ceil(),
      gridHeight.ceil(),
    );
    
    picture.dispose();
    return image;
  }
  
  /// Render ASCII art character with perfect alignment
  Future<void> _renderAsciiArtChar(
    ui.Canvas canvas,
    String char,
    double x,
    double y,
    ui.Color? color,
  ) async {
    await _renderCharacterToCache(char);
    final cachedImage = _charCache[char];
    
    if (cachedImage != null) {
      // Draw with zero offset for perfect alignment
      final paint = Paint()
        ..filterQuality = FilterQuality.none // Sharp edges for ASCII art
        ..isAntiAlias = false; // No anti-aliasing for crisp edges
      
      if (color != null) {
        paint.colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn);
      }
      
      canvas.drawImage(
        cachedImage,
        Offset(x, y),
        paint,
      );
    }
  }
  
  /// Render regular character with grid alignment
  Future<void> _renderRegularChar(
    ui.Canvas canvas,
    String char,
    double x,
    double y,
    ui.Color? color,
  ) async {
    final builder = ui.ParagraphBuilder(_paragraphStyle!);
    builder.pushStyle(_textStyle!.copyWith(
      color: color ?? ui.Color.fromRGBO(255, 255, 255, 1.0),
    ));
    builder.addText(char);
    builder.pop();
    
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: _charWidth));
    
    // Render with grid alignment
    canvas.drawParagraph(
      paragraph,
      Offset(x, y + _baselineOffset),
    );
  }
  
  /// Render standard text (non-ASCII art)
  Future<ui.Image> _renderStandardText(
    String text,
    double fontSize,
    ui.Color? color,
  ) async {
    final builder = ui.ParagraphBuilder(_paragraphStyle!);
    builder.pushStyle(_textStyle!.copyWith(
      fontSize: fontSize,
      color: color ?? ui.Color.fromRGBO(255, 255, 255, 1.0),
    ));
    builder.addText(text);
    builder.pop();
    
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    canvas.drawParagraph(paragraph, Offset.zero);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      paragraph.width.ceil(),
      paragraph.height.ceil(),
    );
    
    picture.dispose();
    return image;
  }
  
  /// Measure text with grid precision
  ui.Size measureText(String text, {double fontSize = _defaultFontSize}) {
    if (!_containsAsciiArt(text)) {
      // Standard text measurement
      final builder = ui.ParagraphBuilder(_paragraphStyle!);
      builder.pushStyle(_textStyle!.copyWith(fontSize: fontSize));
      builder.addText(text);
      builder.pop();
      
      final paragraph = builder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
      
      return Size(paragraph.width, paragraph.height);
    }
    
    // Grid-based measurement for ASCII art
    final lines = text.split('\n');
    final maxWidth = lines.map((line) => line.length).reduce(math.max);
    final gridWidth = maxWidth * _charWidth;
    final gridHeight = lines.length * _charHeight;
    
    return Size(gridWidth, gridHeight);
  }
  
  /// Set font family
  Future<void> setFontFamily(String fontFamily) async {
    if (_currentFontFamily != fontFamily) {
      _currentFontFamily = fontFamily;
      _charCache.clear(); // Clear cache when font changes
      await initialize();
    }
  }
  
  /// Set font size
  Future<void> setFontSize(double fontSize) async {
    if (_currentFontSize != fontSize) {
      _currentFontSize = fontSize;
      _charCache.clear(); // Clear cache when size changes
      await initialize();
    }
  }
  
  /// Clear character cache
  void clearCache() {
    for (final image in _charCache.values) {
      image.dispose();
    }
    _charCache.clear();
    _charWidths.clear();
    _charBounds.clear();
  }
  
  /// Dispose resources
  void dispose() {
    clearCache();
    _isInitialized = false;
    debugPrint('🎨 ASCII Art Renderer disposed');
  }
}

/// Unicode range helper class
class UnicodeRange {
  final int start;
  final int end;
  final String name;
  
  const UnicodeRange(this.start, this.end, this.name);
  
  bool contains(int codePoint) => codePoint >= start && codePoint <= end;
  
  @override
  String toString() => 'UnicodeRange($name: 0x${start.toRadixString(16)}-0x${end.toRadixString(16)})';
}
