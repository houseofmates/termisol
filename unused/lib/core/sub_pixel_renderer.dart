import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Sub-Pixel Rendering - Enhanced text rendering precision
class SubPixelRenderer {
  static final SubPixelRenderer _instance = SubPixelRenderer._internal();
  factory SubPixelRenderer() => _instance;
  SubPixelRenderer._internal();

  bool _isInitialized = false;
  bool _subPixelEnabled = true;
  SubPixelMode _mode = SubPixelMode.rgb;
  double _pixelRatio = 1.0;
  final Map<String, SubPixelCache> _textCache = {};
  final Map<String, RenderMetrics> _metricsCache = {};
  
  static const int _maxCacheSize = 1000;
  static const Duration _cacheTimeout = Duration(minutes: 5);
  
  final _rendererController = StreamController<SubPixelEvent>.broadcast();
  Stream<SubPixelEvent> get events => _rendererController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get subPixelEnabled => _subPixelEnabled;
  SubPixelMode get mode => _mode;
  double get pixelRatio => _pixelRatio;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _detectDisplayCapabilities();
    _startCacheCleanup();
    _isInitialized = true;
    debugPrint('🔍 Sub-Pixel Renderer initialized');
  }

  Future<SubPixelRenderResult> renderText({
    required String text,
    required TextStyle style,
    required Size constraints,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
  }) async {
    if (!_subPixelEnabled) {
      return _renderStandardText(
        text: text,
        style: style,
        constraints: constraints,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      );
    }
    
    try {
      final cacheKey = _generateTextCacheKey(
        text, style, constraints, textAlign, textDirection, softWrap, overflow, maxLines);
      
      // Check cache first
      if (_textCache.containsKey(cacheKey)) {
        final cached = _textCache[cacheKey]!;
        if (!cached.isExpired) {
          return SubPixelRenderResult(
            success: true,
            renderedText: cached.renderedText,
            metrics: cached.metrics,
            fromCache: true,
          );
        }
      }
      
      // Perform sub-pixel rendering
      final result = await _performSubPixelRendering(
        text: text,
        style: style,
        constraints: constraints,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      );
      
      // Cache the result
      _textCache[cacheKey] = SubPixelCache(
        key: cacheKey,
        renderedText: result.renderedText,
        metrics: result.metrics,
        timestamp: DateTime.now(),
      );
      
      _rendererController.add(SubPixelEvent(
        type: SubPixelEventType.textRendered,
        data: {
          'text_length': text.length,
          'cache_hit': false,
          'sub_pixel_mode': _mode.toString(),
        },
      ));
      
      return result;
      
    } catch (e) {
      debugPrint('❌ Sub-pixel rendering failed: $e');
      
      // Fallback to standard rendering
      return _renderStandardText(
        text: text,
        style: style,
        constraints: constraints,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      );
    }
  }

  Future<RenderMetrics> calculateTextMetrics({
    required String text,
    required TextStyle style,
    double? maxWidth,
    int? maxLines,
  }) async {
    final cacheKey = _generateMetricsCacheKey(text, style, maxWidth, maxLines);
    
    // Check cache
    if (_metricsCache.containsKey(cacheKey)) {
      return _metricsCache[cacheKey]!;
    }
    
    try {
      final metrics = await _performMetricsCalculation(
        text: text,
        style: style,
        maxWidth: maxWidth,
        maxLines: maxLines,
      );
      
      _metricsCache[cacheKey] = metrics;
      return metrics;
      
    } catch (e) {
      debugPrint('❌ Metrics calculation failed: $e');
      
      // Fallback metrics
      return RenderMetrics(
        width: text.length * 10.0, // Rough estimate
        height: style.fontSize ?? 14.0,
        baseline: style.fontSize ?? 14.0,
        ascent: (style.fontSize ?? 14.0) * 0.8,
        descent: (style.fontSize ?? 14.0) * 0.2,
        lineCount: 1,
      );
    }
  }

  void setSubPixelMode(SubPixelMode mode) {
    _mode = mode;
    
    // Clear cache when mode changes
    _textCache.clear();
    _metricsCache.clear();
    
    _rendererController.add(SubPixelEvent(
      type: SubPixelEventType.modeChanged,
      data: {'mode': mode.toString()},
    ));
    
    debugPrint('🔍 Sub-pixel mode changed to: $mode');
  }

  void setSubPixelEnabled(bool enabled) {
    _subPixelEnabled = enabled;
    
    _rendererController.add(SubPixelEvent(
      type: SubPixelEventType.enabledChanged,
      data: {'enabled': enabled},
    ));
    
    debugPrint('🔍 Sub-pixel rendering ${enabled ? 'enabled' : 'disabled'}');
  }

  void updatePixelRatio(double ratio) {
    _pixelRatio = ratio;
    
    // Clear cache when pixel ratio changes
    _textCache.clear();
    _metricsCache.clear();
    
    _rendererController.add(SubPixelEvent(
      type: SubPixelEventType.pixelRatioChanged,
      data: {'pixel_ratio': ratio},
    ));
  }

  Future<SubPixelRenderResult> _performSubPixelRendering({
    required String text,
    required TextStyle style,
    required Size constraints,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
  }) async {
    // Simulate sub-pixel rendering process
    await Future.delayed(Duration(milliseconds: 1));
    
    // Enhanced text measurement with sub-pixel precision
    final metrics = await _performMetricsCalculation(
      text: text,
      style: style,
      maxWidth: constraints.width,
      maxLines: maxLines,
    );
    
    // Apply sub-pixel positioning
    final subPixelOffset = _calculateSubPixelOffset(style);
    final adjustedMetrics = _applySubPixelAdjustment(metrics, subPixelOffset);
    
    // Create rendered text with sub-pixel precision
    final renderedText = SubPixelRenderedText(
      text: text,
      style: style,
      metrics: adjustedMetrics,
      subPixelOffset: subPixelOffset,
      mode: _mode,
      pixelRatio: _pixelRatio,
    );
    
    return SubPixelRenderResult(
      success: true,
      renderedText: renderedText,
      metrics: adjustedMetrics,
      fromCache: false,
    );
  }

  Future<RenderMetrics> _performMetricsCalculation({
    required String text,
    required TextStyle style,
    double? maxWidth,
    int? maxLines,
  }) async {
    // Simulate enhanced metrics calculation
    final fontSize = style.fontSize ?? 14.0;
    final fontFamily = style.fontFamily;
    final fontWeight = style.fontWeight ?? FontWeight.normal;
    
    // Calculate with sub-pixel precision
    final charWidth = _calculateCharacterWidth(fontSize, fontFamily, fontWeight);
    final lineSpacing = style.height ?? 1.0;
    
    final lines = _calculateTextLines(text, maxWidth, charWidth);
    final actualMaxLines = maxLines != null ? math.min(maxLines, lines.length) : lines.length;
    
    final width = lines.isNotEmpty 
        ? lines.take(actualMaxLines).map((line) => line.length * charWidth).reduce(math.max)
        : 0.0;
    
    final height = actualMaxLines * fontSize * lineSpacing;
    final baseline = fontSize * 0.85;
    final ascent = baseline;
    final descent = fontSize - baseline;
    
    return RenderMetrics(
      width: _applySubPixelPrecision(width),
      height: _applySubPixelPrecision(height),
      baseline: _applySubPixelPrecision(baseline),
      ascent: _applySubPixelPrecision(ascent),
      descent: _applySubPixelPrecision(descent),
      lineCount: actualMaxLines,
      charWidth: _applySubPixelPrecision(charWidth),
    );
  }

  SubPixelRenderResult _renderStandardText({
    required String text,
    required TextStyle style,
    required Size constraints,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
  }) {
    // Standard rendering without sub-pixel precision
    final metrics = RenderMetrics(
      width: text.length * 10.0,
      height: style.fontSize ?? 14.0,
      baseline: style.fontSize ?? 14.0,
      ascent: (style.fontSize ?? 14.0) * 0.8,
      descent: (style.fontSize ?? 14.0) * 0.2,
      lineCount: 1,
    );
    
    final renderedText = SubPixelRenderedText(
      text: text,
      style: style,
      metrics: metrics,
      subPixelOffset: Offset.zero,
      mode: SubPixelMode.none,
      pixelRatio: _pixelRatio,
    );
    
    return SubPixelRenderResult(
      success: true,
      renderedText: renderedText,
      metrics: metrics,
      fromCache: false,
    );
  }

  double _calculateCharacterWidth(double fontSize, String? fontFamily, FontWeight fontWeight) {
    // Simulate character width calculation based on font properties
    double baseWidth = fontSize * 0.6; // Average character width ratio
    
    // Adjust for font family
    if (fontFamily != null) {
      if (fontFamily.contains('mono')) {
        baseWidth = fontSize * 0.6; // Monospace fonts
      } else if (fontFamily.contains('serif')) {
        baseWidth = fontSize * 0.55; // Serif fonts
      }
    }
    
    // Adjust for font weight
    switch (fontWeight) {
      case FontWeight.bold:
        baseWidth *= 1.1;
        break;
      case FontWeight.w100:
      case FontWeight.w200:
      case FontWeight.w300:
        baseWidth *= 0.95;
        break;
      default:
        break;
    }
    
    return baseWidth;
  }

  List<String> _calculateTextLines(String text, double? maxWidth, double charWidth) {
    if (maxWidth == null || maxWidth <= 0) {
      return [text];
    }
    
    final lines = <String>[];
    final words = text.split(' ');
    String currentLine = '';
    
    for (final word in words) {
      final testLine = currentLine.isEmpty ? word : '$currentLine $word';
      final testWidth = testLine.length * charWidth;
      
      if (testWidth <= maxWidth) {
        currentLine = testLine;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = word;
        } else {
          // Word is too long, break it
          lines.add(word);
        }
      }
    }
    
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    
    return lines;
  }

  Offset _calculateSubPixelOffset(TextStyle style) {
    if (!_subPixelEnabled || _mode == SubPixelMode.none) {
      return Offset.zero;
    }
    
    // Calculate sub-pixel offset based on text properties
    final fontSize = style.fontSize ?? 14.0;
    final subPixelX = (fontSize * 0.1) % 1.0; // Sub-pixel X offset
    final subPixelY = (fontSize * 0.05) % 1.0; // Sub-pixel Y offset
    
    return Offset(subPixelX, subPixelY);
  }

  RenderMetrics _applySubPixelAdjustment(RenderMetrics metrics, Offset subPixelOffset) {
    return RenderMetrics(
      width: metrics.width + subPixelOffset.dx,
      height: metrics.height + subPixelOffset.dy,
      baseline: metrics.baseline + subPixelOffset.dy,
      ascent: metrics.ascent,
      descent: metrics.descent,
      lineCount: metrics.lineCount,
      charWidth: metrics.charWidth,
    );
  }

  double _applySubPixelPrecision(double value) {
    if (!_subPixelEnabled) {
      return value;
    }
    
    // Apply sub-pixel precision (1/3 pixel precision)
    return (value * 3).roundToDouble() / 3.0;
  }

  void _detectDisplayCapabilities() {
    // Simulate display capability detection
    _pixelRatio = 2.0; // Default to 2x for retina displays
    
    // Detect sub-pixel rendering capability
    _subPixelEnabled = true;
    _mode = SubPixelMode.rgb; // Default to RGB sub-pixel rendering
    
    debugPrint('🔍 Display capabilities detected: pixelRatio=$_pixelRatio, subPixel=$_subPixelEnabled');
  }

  void _startCacheCleanup() {
    Timer.periodic(Duration(minutes: 1), (_) {
      _cleanupExpiredCache();
    });
  }

  void _cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    // Clean text cache
    for (final entry in _textCache.entries) {
      if (now.difference(entry.value.timestamp) > _cacheTimeout) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _textCache.remove(key);
    }
    
    // Clean metrics cache
    _metricsCache.clear(); // Metrics cache is smaller, clear entirely periodically
    
    // Limit cache size
    if (_textCache.length > _maxCacheSize) {
      final entries = _textCache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      
      final toRemove = entries.take(_textCache.length - _maxCacheSize);
      for (final entry in toRemove) {
        _textCache.remove(entry.key);
      }
    }
    
    if (expiredKeys.isNotEmpty) {
      debugPrint('🔍 Cleaned ${expiredKeys.length} expired sub-pixel cache entries');
    }
  }

  String _generateTextCacheKey(
    String text,
    TextStyle style,
    Size constraints,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
  ) {
    final styleHash = _hashTextStyle(style);
    final constraintsHash = '${constraints.width}_${constraints.height}';
    final optionsHash = '${textAlign?.toString()}_${textDirection?.toString()}_${softWrap}_${overflow?.toString()}_$maxLines';
    
    return '${text.hashCode}_$styleHash_$constraintsHash_$optionsHash';
  }

  String _generateMetricsCacheKey(String text, TextStyle style, double? maxWidth, int? maxLines) {
    final styleHash = _hashTextStyle(style);
    return '${text.hashCode}_$styleHash_${maxWidth ?? 'null'}_${maxLines ?? 'null'}';
  }

  String _hashTextStyle(TextStyle style) {
    final buffer = StringBuffer();
    buffer.write(style.fontSize ?? '');
    buffer.write(style.fontFamily ?? '');
    buffer.write(style.fontWeight?.toString() ?? '');
    buffer.write(style.fontStyle?.toString() ?? '');
    buffer.write(style.letterSpacing ?? '');
    buffer.write(style.wordSpacing ?? '');
    buffer.write(style.height ?? '');
    buffer.write(style.color?.toString() ?? '');
    return buffer.toString().hashCode.toString();
  }

  Map<String, dynamic> getStatistics() {
    return {
      'sub_pixel_enabled': _subPixelEnabled,
      'mode': _mode.toString(),
      'pixel_ratio': _pixelRatio,
      'text_cache_size': _textCache.length,
      'metrics_cache_size': _metricsCache.length,
      'max_cache_size': _maxCacheSize,
    };
  }

  Future<void> dispose() async {
    _rendererController.close();
    _textCache.clear();
    _metricsCache.clear();
    _isInitialized = false;
  }
}

/// Data classes
class SubPixelRenderResult {
  final bool success;
  final SubPixelRenderedText? renderedText;
  final RenderMetrics? metrics;
  final bool fromCache;
  final String? error;
  
  SubPixelRenderResult({
    required this.success,
    this.renderedText,
    this.metrics,
    required this.fromCache,
    this.error,
  });
  
  factory SubPixelRenderResult.success(SubPixelRenderedText renderedText, RenderMetrics metrics, bool fromCache) {
    return SubPixelRenderResult(
      success: true,
      renderedText: renderedText,
      metrics: metrics,
      fromCache: fromCache,
    );
  }
  
  factory SubPixelRenderResult.error(String error) {
    return SubPixelRenderResult(
      success: false,
      fromCache: false,
      error: error,
    );
  }
}

class SubPixelRenderedText {
  final String text;
  final TextStyle style;
  final RenderMetrics metrics;
  final Offset subPixelOffset;
  final SubPixelMode mode;
  final double pixelRatio;
  
  SubPixelRenderedText({
    required this.text,
    required this.style,
    required this.metrics,
    required this.subPixelOffset,
    required this.mode,
    required this.pixelRatio,
  });
}

class RenderMetrics {
  final double width;
  final double height;
  final double baseline;
  final double ascent;
  final double descent;
  final int lineCount;
  final double? charWidth;
  
  RenderMetrics({
    required this.width,
    required this.height,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.lineCount,
    this.charWidth,
  });
}

class SubPixelCache {
  final String key;
  final SubPixelRenderedText renderedText;
  final RenderMetrics metrics;
  final DateTime timestamp;
  
  SubPixelCache({
    required this.key,
    required this.renderedText,
    required this.metrics,
    required this.timestamp,
  });
  
  bool get isExpired => DateTime.now().difference(timestamp) > Duration(minutes: 5);
}

class SubPixelEvent {
  final SubPixelEventType type;
  final Map<String, dynamic>? data;
  
  SubPixelEvent({
    required this.type,
    this.data,
  });
}

enum SubPixelMode {
  none,
  rgb,
  bgr,
  vertical,
}

enum SubPixelEventType {
  textRendered,
  modeChanged,
  enabledChanged,
  pixelRatioChanged,
}
