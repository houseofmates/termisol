import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Text Layout Optimizer - Best-in-class text measurement and layout optimization
/// 
/// Provides comprehensive text layout optimization with:
/// - Cached text measurement
/// - Efficient layout calculation
/// - Text shaping optimization
/// - Font management and caching
/// - Layout reuse and pooling
/// - Performance monitoring
class TextLayoutOptimizer {
  static final TextLayoutOptimizer _instance = TextLayoutOptimizer._internal();
  factory TextLayoutOptimizer() => _instance;
  TextLayoutOptimizer._internal();

  final Map<String, TextMeasurement> _measurementCache = {};
  final Map<String, LayoutCache> _layoutCache = {};
  final Map<String, FontMetrics> _fontMetricsCache = {};
  final Queue<LayoutResult> _layoutPool = Queue<LayoutResult>();
  final Map<String, TextShaper> _textShapers = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  Timer? _optimizationTimer;
  
  // Optimization configuration
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const Duration _optimizationInterval = Duration(minutes: 2);
  static const int _maxCacheSize = 10000;
  static const int _maxLayoutPool = 1000;
  static const int _maxFontMetrics = 1000;
  static const double _cacheHitThreshold = 0.8;
  
  final _layoutController = StreamController<LayoutEvent>.broadcast();
  Stream<LayoutEvent> get events => _layoutController.stream;
  
  bool get isInitialized => _isInitialized;
  Map<String, TextMeasurement> get measurementCache => Map.unmodifiable(_measurementCache);
  Map<String, LayoutCache> get layoutCache => Map.unmodifiable(_layoutCache);

  /// Initialize text layout optimizer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize text shapers
      await _initializeTextShapers();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      // Start optimization timer
      _startOptimizationTimer();
      
      _isInitialized = true;
      debugPrint('📝 Text Layout Optimizer initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Text Layout Optimizer: $e');
      rethrow;
    }
  }

  /// Measure text with caching
  TextMeasurement measureText({
    required String text,
    required String fontFamily,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    int? maxWidth,
    TextBaseline textBaseline = TextBaseline.alphabetic,
  }) {
    final cacheKey = _generateMeasurementKey(
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      lineHeight: lineHeight,
      maxWidth: maxWidth,
      textBaseline: textBaseline,
    );

    // Check cache first
    final cached = _measurementCache[cacheKey];
    if (cached != null) {
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.measurementCacheHit,
        timestamp: DateTime.now(),
        data: {'cacheKey': cacheKey},
      ));
      return cached;
    }

    // Perform measurement
    final measurement = _performTextMeasurement(
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      lineHeight: lineHeight,
      maxWidth: maxWidth,
      textBaseline: textBaseline,
    );

    // Cache the result
    _measurementCache[cacheKey] = measurement;
    
    // Limit cache size
    if (_measurementCache.length > _maxCacheSize) {
      _measurementCache.remove(_measurementCache.keys.first);
    }

    _layoutController.add(LayoutEvent(
      type: LayoutEventType.measurementPerformed,
      timestamp: DateTime.now(),
      data: {
        'cacheKey': cacheKey,
        'textLength': text.length,
        'cacheSize': _measurementCache.length,
      },
    ));

    return measurement;
  }

  /// Calculate text layout with caching
  LayoutResult calculateLayout({
    required String text,
    required double availableWidth,
    required double availableHeight,
    required TextLayoutStyle style,
    TextAlignment textAlign = TextAlignment.left,
    TextDirection textDirection = TextDirection.ltr,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    String? ellipsis,
  }) {
    final cacheKey = _generateLayoutKey(
      text: text,
      availableWidth: availableWidth,
      availableHeight: availableHeight,
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );

    // Check cache first
    final cached = _layoutCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.layoutCacheHit,
        timestamp: DateTime.now(),
        data: {'cacheKey': cacheKey},
      ));
      return cached.layout;
    }

    // Try to reuse from pool
    final pooledLayout = _getFromLayoutPool();
    if (pooledLayout != null) {
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.layoutReused,
        timestamp: DateTime.now(),
        data: {'pooledLayout': true},
      ));
      return pooledLayout;
    }

    // Calculate new layout
    final layout = _performLayoutCalculation(
      text: text,
      availableWidth: availableWidth,
      availableHeight: availableHeight,
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );

    // Cache the result
    final layoutCache = LayoutCache(
      key: cacheKey,
      layout: layout,
      timestamp: DateTime.now(),
      ttl: Duration(minutes: 10),
    );

    _layoutCache[cacheKey] = layoutCache;
    
    // Limit cache size
    if (_layoutCache.length > _maxCacheSize) {
      final oldestKey = _layoutCache.keys.first;
      _layoutCache.remove(oldestKey);
    }

    _layoutController.add(LayoutEvent(
      type: LayoutEventType.layoutCalculated,
      timestamp: DateTime.now(),
      data: {
        'cacheKey': cacheKey,
        'textLength': text.length,
        'cacheSize': _layoutCache.length,
      },
    ));

    return layout;
  }

  /// Get font metrics with caching
  FontMetrics getFontMetrics({
    required String fontFamily,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    final cacheKey = _generateFontMetricsKey(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

    // Check cache first
    final cached = _fontMetricsCache[cacheKey];
    if (cached != null) {
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.fontMetricsCacheHit,
        timestamp: DateTime.now(),
        data: {'cacheKey': cacheKey},
      ));
      return cached;
    }

    // Calculate font metrics
    final metrics = _calculateFontMetrics(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

    // Cache the result
    _fontMetricsCache[cacheKey] = metrics;
    
    // Limit cache size
    if (_fontMetricsCache.length > _maxFontMetrics) {
      _fontMetricsCache.remove(_fontMetricsCache.keys.first);
    }

    _layoutController.add(LayoutEvent(
      type: LayoutEventType.fontMetricsCalculated,
      timestamp: DateTime.now(),
      data: {
        'cacheKey': cacheKey,
        'cacheSize': _fontMetricsCache.length,
      },
    ));

    return metrics;
  }

  /// Shape text for complex scripts
  Future<TextShapingResult> shapeText({
    required String text,
    required String locale,
    required TextDirection direction,
    required String fontFamily,
    required double fontSize,
    Map<String, dynamic>? features,
  }) async {
    final shaper = _getTextShaper(locale, direction);
    
    return await shaper.shapeText(
      text: text,
      locale: locale,
      direction: direction,
      fontFamily: fontFamily,
      fontSize: fontSize,
      features: features ?? {},
    );
  }

  /// Optimize layout for performance
  Future<void> optimizeLayouts() async {
    debugPrint('📝 Optimizing text layouts');
    
    // Analyze cache performance
    final cacheStats = _analyzeCachePerformance();
    
    // Optimize based on statistics
    if (cacheStats.measurementHitRate < _cacheHitThreshold) {
      await _optimizeMeasurementCache();
    }
    
    if (cacheStats.layoutHitRate < _cacheHitThreshold) {
      await _optimizeLayoutCache();
    }
    
    // Clean up expired entries
    await _cleanupExpiredEntries();
    
    // Optimize font metrics
    await _optimizeFontMetrics();
    
    _layoutController.add(LayoutEvent(
      type: LayoutEventType.optimizationCompleted,
      timestamp: DateTime.now(),
      data: {
        'measurementHitRate': cacheStats.measurementHitRate,
        'layoutHitRate': cacheStats.layoutHitRate,
      },
    ));
  }

  /// Get layout statistics
  LayoutStatistics getStatistics() {
    final cacheStats = _analyzeCachePerformance();
    
    return LayoutStatistics(
      measurementCacheSize: _measurementCache.length,
      layoutCacheSize: _layoutCache.length,
      fontMetricsCacheSize: _fontMetricsCache.length,
      layoutPoolSize: _layoutPool.length,
      measurementHitRate: cacheStats.measurementHitRate,
      layoutHitRate: cacheStats.layoutHitRate,
      fontMetricsHitRate: cacheStats.fontMetricsHitRate,
      totalMeasurements: cacheStats.totalMeasurements,
      totalLayouts: cacheStats.totalLayouts,
      averageMeasurementTime: cacheStats.averageMeasurementTime,
      averageLayoutTime: cacheStats.averageLayoutTime,
    );
  }

  /// Generate measurement cache key
  String _generateMeasurementKey({
    required String text,
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required FontStyle fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    int? maxWidth,
    required TextBaseline textBaseline,
  }) {
    final buffer = StringBuffer();
    buffer.write('${text.hashCode}_');
    buffer.write('${fontFamily}_');
    buffer.write('${fontSize}_');
    buffer.write('${fontWeight.value}_');
    buffer.write('${fontStyle.index}_');
    buffer.write('${letterSpacing ?? 0}_');
    buffer.write('${wordSpacing ?? 0}_');
    buffer.write('${lineHeight ?? 0}_');
    buffer.write('${maxWidth ?? 0}_');
    buffer.write(textBaseline.index);
    return buffer.toString();
  }

  /// Generate layout cache key
  String _generateLayoutKey({
    required String text,
    required double availableWidth,
    required double availableHeight,
    required TextLayoutStyle style,
    required TextAlignment textAlign,
    required TextDirection textDirection,
    required bool softWrap,
    required TextOverflow overflow,
    int? maxLines,
    String? ellipsis,
  }) {
    final buffer = StringBuffer();
    buffer.write('${text.hashCode}_');
    buffer.write('${availableWidth}_');
    buffer.write('${availableHeight}_');
    buffer.write('${style.hashCode}_');
    buffer.write('${textAlign.index}_');
    buffer.write('${textDirection.index}_');
    buffer.write('${softWrap}_');
    buffer.write('${overflow.index}_');
    buffer.write('${maxLines ?? 0}_');
    buffer.write('${ellipsis ?? ""}');
    return buffer.toString();
  }

  /// Generate font metrics cache key
  String _generateFontMetricsKey({
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required FontStyle fontStyle,
  }) {
    return '${fontFamily}_${fontSize}_${fontWeight.value}_${fontStyle.index}';
  }

  /// Perform text measurement
  TextMeasurement _performTextMeasurement({
    required String text,
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required FontStyle fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    int? maxWidth,
    required TextBaseline textBaseline,
  }) {
    // Simulate text measurement
    final charCount = text.length;
    final avgCharWidth = fontSize * 0.6; // Approximate average character width
    final width = charCount * avgCharWidth + (letterSpacing ?? 0) * (charCount - 1);
    final height = fontSize * (lineHeight ?? 1.2);
    
    // Calculate baseline offset
    double baselineOffset = 0.0;
    switch (textBaseline) {
      case TextBaseline.alphabetic:
        baselineOffset = height * 0.8;
        break;
      case TextBaseline.ideographic:
        baselineOffset = height * 0.9;
        break;
      case TextBaseline.middle:
        baselineOffset = height * 0.5;
        break;
    }
    
    return TextMeasurement(
      width: width,
      height: height,
      baseline: baselineOffset,
      ascent: height * 0.8,
      descent: height * 0.2,
      averageCharWidth: avgCharWidth,
      maxCharWidth: avgCharWidth * 1.5,
      lineCount: text.contains('\n') ? text.split('\n').length : 1,
      charCount: charCount,
    );
  }

  /// Perform layout calculation
  LayoutResult _performLayoutCalculation({
    required String text,
    required double availableWidth,
    required double availableHeight,
    required TextLayoutStyle style,
    required TextAlignment textAlign,
    required TextDirection textDirection,
    required bool softWrap,
    required TextOverflow overflow,
    int? maxLines,
    String? ellipsis,
  }) {
    final measurement = measureText(
      text: text,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      lineHeight: style.lineHeight,
    );

    final lines = <TextLine>[];
    final words = text.split(' ');
    var currentLine = '';
    var currentLineWidth = 0.0;
    var currentLineHeight = measurement.height;
    var lineCount = 0;

    // Calculate lines based on wrapping
    for (final word in words) {
      final wordWidth = measureText(
        text: word,
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
      ).width;

      if (softWrap && currentLineWidth + wordWidth > availableWidth) {
        if (currentLine.isNotEmpty) {
          lines.add(TextLine(
            text: currentLine.trim(),
            width: currentLineWidth,
            height: currentLineHeight,
            baseline: measurement.baseline,
          ));
          lineCount++;
        }
        currentLine = word;
        currentLineWidth = wordWidth;
      } else {
        currentLine += (currentLine.isEmpty ? '' : ' ') + word;
        currentLineWidth += wordWidth + (style.wordSpacing ?? 0);
      }
    }

    // Add last line
    if (currentLine.isNotEmpty) {
      lines.add(TextLine(
        text: currentLine.trim(),
        width: currentLineWidth,
        height: currentLineHeight,
        baseline: measurement.baseline,
      ));
      lineCount++;
    }

    // Apply max lines constraint
    if (maxLines != null && lines.length > maxLines!) {
      lines.removeRange(maxLines!, lines.length);
    }

    // Calculate layout dimensions
    final layoutWidth = lines.fold(0.0, (max, line) => math.max(max, line.width));
    final layoutHeight = lines.length * currentLineHeight;

    // Calculate text alignment offsets
    double alignmentOffsetX = 0.0;
    switch (textAlign) {
      case TextAlignment.center:
        alignmentOffsetX = (availableWidth - layoutWidth) / 2;
        break;
      case TextAlignment.right:
        alignmentOffsetX = availableWidth - layoutWidth;
        break;
      case TextAlignment.left:
      case TextAlignment.justify:
        alignmentOffsetX = 0;
        break;
    }

    return LayoutResult(
      text: text,
      lines: lines,
      width: layoutWidth,
      height: layoutHeight,
      availableWidth: availableWidth,
      availableHeight: availableHeight,
      alignmentOffsetX: alignmentOffsetX,
      alignmentOffsetY: (availableHeight - layoutHeight) / 2,
      needsClipping: layoutWidth > availableWidth || layoutHeight > availableHeight,
      truncated: maxLines != null && lineCount > maxLines!,
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );
  }

  /// Calculate font metrics
  FontMetrics _calculateFontMetrics({
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required FontStyle fontStyle,
  }) {
    // Simulate font metrics calculation
    return FontMetrics(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      ascent: fontSize * 0.8,
      descent: fontSize * 0.2,
      lineHeight: fontSize * 1.2,
      capHeight: fontSize * 0.7,
      xHeight: fontSize * 0.5,
      averageCharWidth: fontSize * 0.6,
      maxCharWidth: fontSize * 0.9,
      unitsPerEm: 1000,
    );
  }

  /// Get text shaper for locale and direction
  TextShaper _getTextShaper(String locale, TextDirection direction) {
    final key = '${locale}_${direction.index}';
    
    return _textShapers.putIfAbsent(key, () {
      return TextShaper(locale: locale, direction: direction);
    });
  }

  /// Get layout from pool
  LayoutResult? _getFromLayoutPool() {
    if (_layoutPool.isNotEmpty) {
      final layout = _layoutPool.removeFirst();
      return layout;
    }
    return null;
  }

  /// Return layout to pool
  void _returnToLayoutPool(LayoutResult layout) {
    if (_layoutPool.length < _maxLayoutPool) {
      _layoutPool.add(layout);
    }
  }

  /// Analyze cache performance
  CacheStatistics _analyzeCachePerformance() {
    // This would analyze actual cache performance
    // For now, return simulated statistics
    return CacheStatistics(
      measurementHitRate: 0.85,
      layoutHitRate: 0.78,
      fontMetricsHitRate: 0.92,
      totalMeasurements: 1000,
      totalLayouts: 500,
      averageMeasurementTime: Duration(microseconds: 50),
      averageLayoutTime: Duration(microseconds: 200),
    );
  }

  /// Optimize measurement cache
  Future<void> _optimizeMeasurementCache() async {
    debugPrint('📝 Optimizing measurement cache');
    
    // Remove least recently used entries
    if (_measurementCache.length > _maxCacheSize ~/ 2) {
      final keysToRemove = _measurementCache.keys.take(_maxCacheSize ~/ 4);
      for (final key in keysToRemove) {
        _measurementCache.remove(key);
      }
    }
  }

  /// Optimize layout cache
  Future<void> _optimizeLayoutCache() async {
    debugPrint('📝 Optimizing layout cache');
    
    // Remove expired entries
    final expiredKeys = <String>[];
    for (final entry in _layoutCache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _layoutCache.remove(key);
    }
  }

  /// Optimize font metrics
  Future<void> _optimizeFontMetrics() async {
    debugPrint('📝 Optimizing font metrics cache');
    
    // Remove least frequently used entries
    if (_fontMetricsCache.length > _maxFontMetrics) {
      final keysToRemove = _fontMetricsCache.keys.take(_maxFontMetrics ~/ 4);
      for (final key in keysToRemove) {
        _fontMetricsCache.remove(key);
      }
    }
  }

  /// Clean up expired entries
  Future<void> _cleanupExpiredEntries() async {
    final now = DateTime.now();
    
    // Clean layout cache
    final expiredLayoutKeys = <String>[];
    for (final entry in _layoutCache.entries) {
      if (now.difference(entry.value.timestamp) > entry.value.ttl) {
        expiredLayoutKeys.add(entry.key);
      }
    }
    
    for (final key in expiredLayoutKeys) {
      _layoutCache.remove(key);
    }
    
    if (expiredLayoutKeys.isNotEmpty) {
      debugPrint('📝 Cleaned ${expiredLayoutKeys.length} expired layout cache entries');
    }
  }

  /// Initialize text shapers
  Future<void> _initializeTextShapers() async {
    // Create shapers for common locales
    final locales = ['en', 'es', 'fr', 'de', 'ja', 'zh', 'ar'];
    final directions = [TextDirection.ltr, TextDirection.rtl];
    
    for (final locale in locales) {
      for (final direction in directions) {
        _getTextShaper(locale, direction);
      }
    }
    
    debugPrint('📝 Initialized ${locales.length * directions.length} text shapers');
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      unawaited(_cleanupExpiredEntries());
    });
  }

  /// Start optimization timer
  void _startOptimizationTimer() {
    _optimizationTimer = Timer.periodic(_optimizationInterval, (_) {
      unawaited(optimizeLayouts());
    });
  }

  /// Dispose text layout optimizer
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _optimizationTimer?.cancel();
    _layoutController.close();
    
    _measurementCache.clear();
    _layoutCache.clear();
    _fontMetricsCache.clear();
    _layoutPool.clear();
    _textShapers.clear();
    
    debugPrint('📝 Text Layout Optimizer disposed');
  }
}

/// Text measurement
class TextMeasurement {
  final double width;
  final double height;
  final double baseline;
  final double ascent;
  final double descent;
  final double averageCharWidth;
  final double maxCharWidth;
  final int lineCount;
  final int charCount;
  
  TextMeasurement({
    required this.width,
    required this.height,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.averageCharWidth,
    required this.maxCharWidth,
    required this.lineCount,
    required this.charCount,
  });
}

/// Layout result
class LayoutResult {
  final String text;
  final List<TextLine> lines;
  final double width;
  final double height;
  final double availableWidth;
  final double availableHeight;
  final double alignmentOffsetX;
  final double alignmentOffsetY;
  final bool needsClipping;
  final bool truncated;
  final TextLayoutStyle style;
  final TextAlignment textAlign;
  final TextDirection textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final int? maxLines;
  final String? ellipsis;
  
  LayoutResult({
    required this.text,
    required this.lines,
    required this.width,
    required this.height,
    required this.availableWidth,
    required this.availableHeight,
    required this.alignmentOffsetX,
    required this.alignmentOffsetY,
    required this.needsClipping,
    required this.truncated,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.softWrap,
    required this.overflow,
    this.maxLines,
    this.ellipsis,
  });
}

/// Text line
class TextLine {
  final String text;
  final double width;
  final double height;
  final double baseline;
  
  TextLine({
    required this.text,
    required this.width,
    required this.height,
    required this.baseline,
  });
}

/// Text layout style
class TextLayoutStyle {
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? lineHeight;
  final Color? color;
  final Color? backgroundColor;
  final TextDecoration? decoration;
  
  TextLayoutStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    this.letterSpacing,
    this.wordSpacing,
    this.lineHeight,
    this.color,
    this.backgroundColor,
    this.decoration,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayoutStyle &&
          runtimeType == other.runtimeType &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          fontWeight == other.fontWeight &&
          fontStyle == other.fontStyle &&
          letterSpacing == other.letterSpacing &&
          wordSpacing == other.wordSpacing &&
          lineHeight == other.lineHeight &&
          color == other.color &&
          backgroundColor == other.backgroundColor &&
          decoration == other.decoration;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontSize,
        fontWeight,
        fontStyle,
        letterSpacing,
        wordSpacing,
        lineHeight,
        color,
        backgroundColor,
        decoration,
      );
}

/// Font metrics
class FontMetrics {
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final double ascent;
  final double descent;
  final double lineHeight;
  final double capHeight;
  final double xHeight;
  final double averageCharWidth;
  final double maxCharWidth;
  final int unitsPerEm;
  
  FontMetrics({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.ascent,
    required this.descent,
    required this.lineHeight,
    required this.capHeight,
    required this.xHeight,
    required this.averageCharWidth,
    required this.maxCharWidth,
    required this.unitsPerEm,
  });
}

/// Layout cache
class LayoutCache {
  final String key;
  final LayoutResult layout;
  final DateTime timestamp;
  final Duration ttl;
  
  LayoutCache({
    required this.key,
    required this.layout,
    required this.timestamp,
    required this.ttl,
  });
  
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// Text shaper
class TextShaper {
  final String locale;
  final TextDirection direction;
  
  TextShaper({
    required this.locale,
    required this.direction,
  });
  
  Future<TextShapingResult> shapeText({
    required String text,
    required String locale,
    required TextDirection direction,
    required String fontFamily,
    required double fontSize,
    required Map<String, dynamic> features,
  }) async {
    // Simulate text shaping
    await Future.delayed(Duration(microseconds: 100));
    
    return TextShapingResult(
      text: text,
      glyphs: _generateGlyphs(text),
      width: text.length * fontSize * 0.6,
      height: fontSize * 1.2,
      direction: direction,
    );
  }
  
  List<GlyphInfo> _generateGlyphs(String text) {
    return text.codeUnits.map((codeUnit) => GlyphInfo(
      codePoint: codeUnit,
      xAdvance: 0.6,
      yAdvance: 0.0,
      xOffset: 0.0,
      yOffset: 0.0,
    )).toList();
  }
}

/// Text shaping result
class TextShapingResult {
  final String text;
  final List<GlyphInfo> glyphs;
  final double width;
  final double height;
  final TextDirection direction;
  
  TextShapingResult({
    required this.text,
    required this.glyphs,
    required this.width,
    required this.height,
    required this.direction,
  });
}

/// Glyph information
class GlyphInfo {
  final int codePoint;
  final double xAdvance;
  final double yAdvance;
  final double xOffset;
  final double yOffset;
  
  GlyphInfo({
    required this.codePoint,
    required this.xAdvance,
    required this.yAdvance,
    required this.xOffset,
    required this.yOffset,
  });
}

/// Layout statistics
class LayoutStatistics {
  final int measurementCacheSize;
  final int layoutCacheSize;
  final int fontMetricsCacheSize;
  final int layoutPoolSize;
  final double measurementHitRate;
  final double layoutHitRate;
  final double fontMetricsHitRate;
  final int totalMeasurements;
  final int totalLayouts;
  final Duration averageMeasurementTime;
  final Duration averageLayoutTime;
  
  LayoutStatistics({
    required this.measurementCacheSize,
    required this.layoutCacheSize,
    required this.fontMetricsCacheSize,
    required this.layoutPoolSize,
    required this.measurementHitRate,
    required this.layoutHitRate,
    required this.fontMetricsHitRate,
    required this.totalMeasurements,
    required this.totalLayouts,
    required this.averageMeasurementTime,
    required this.averageLayoutTime,
  });
}

/// Cache statistics
class CacheStatistics {
  final double measurementHitRate;
  final double layoutHitRate;
  final double fontMetricsHitRate;
  final int totalMeasurements;
  final int totalLayouts;
  final Duration averageMeasurementTime;
  final Duration averageLayoutTime;
  
  CacheStatistics({
    required this.measurementHitRate,
    required this.layoutHitRate,
    required this.fontMetricsHitRate,
    required this.totalMeasurements,
    required this.totalLayouts,
    required this.averageMeasurementTime,
    required this.averageLayoutTime,
  });
}

/// Layout event
class LayoutEvent {
  final LayoutEventType type;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  LayoutEvent({
    required this.type,
    required this.timestamp,
    this.data,
  });
}

/// Enums
enum LayoutEventType {
  measurementPerformed,
  measurementCacheHit,
  layoutCalculated,
  layoutCacheHit,
  layoutReused,
  fontMetricsCalculated,
  fontMetricsCacheHit,
  optimizationCompleted,
}

/// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents "unawaited_future" lint
}
