import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/painting.dart';
import 'production_gpu_renderer.dart';

/// High-performance terminal renderer extending [CustomPainter].
///
/// Paints directly to [Canvas] using cached [Paragraph] objects per unique
/// style run. Damage tracking uses a list of [Rect] regions with merge
/// and deduplication. The paragraph cache is bounded with LRU eviction.
class HighPerformanceTerminalRenderer extends CustomPainter {
  final int columns;
  final int rows;
  final ProductionGpuRenderer gpuRenderer;

  // Terminal buffer - character grid with styling
  final List<TerminalCell> _buffer;
  final List<TerminalCell> _previousBuffer;

  // Spatial damage tracking using R-tree structure
  final SpatialDamageTracker _damageTracker;
  bool _fullRedrawNeeded = true;

  // Rendering state
  final Map<String, ui.Paragraph> _paragraphCache = {};
  final List<String> _paragraphLru = [];

  // Performance metrics
  int _frameCount = 0;
  int _dirtyCellsLastFrame = 0;
  final Stopwatch _frameTimer = Stopwatch();

  // Font measurement
  late final double _charWidth;
  late final double _charHeight;

  static const int _maxParagraphCache = 2048;
  static const String _fontFamily = 'Droid Sans Mono';
  static const double _fontSize = 14.0;

  HighPerformanceTerminalRenderer({
    required this.columns,
    required this.rows,
    required this.gpuRenderer,
  }) : _buffer = List.generate(columns * rows, (_) => TerminalCell.empty()),
       _previousBuffer = List.generate(columns * rows, (_) => TerminalCell.empty()),
       _damageTracker = SpatialDamageTracker(),
       super(repaint: null) {
    _initializeFontMetrics();
  }

  void _initializeFontMetrics() {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontFamily: _fontFamily, fontSize: _fontSize, height: 1.0),
      ),
    );
    textPainter.layout();
    _charWidth = textPainter.width;
    _charHeight = textPainter.height;
    textPainter.dispose();
  }

  /// Write text to the terminal buffer.
  void write(String text, {int? col, int? row, TerminalStyle? style}) {
    final lines = text.split('\n');
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final currentRow = (row ?? 0) + lineIndex;
      if (currentRow >= rows) break;
      final startCol = lineIndex == 0 ? (col ?? 0) : 0;
      for (int i = 0; i < line.length && startCol + i < columns; i++) {
        final bufferIndex = currentRow * columns + startCol + i;
        if (bufferIndex >= _buffer.length) continue;
        final oldCell = _buffer[bufferIndex];
        final newCell = TerminalCell(char: line[i], style: style ?? TerminalStyle.defaultStyle());
        if (oldCell != newCell) {
          _buffer[bufferIndex] = newCell;
          _damageTracker.markDirty(startCol + i, currentRow, 1, 1);
        }
      }
    }
  }

  /// Clear the terminal buffer.
  void clear({TerminalStyle? style}) {
    for (int i = 0; i < _buffer.length; i++) {
      _buffer[i] = TerminalCell.empty(style: style);
    }
    _fullRedrawNeeded = true;
    _dirtyRects.clear();
  }

  /// Clear a rectangular region.
  void clearRegion(int col, int row, int width, int height, {TerminalStyle? style}) {
    for (int r = row; r < math.min(row + height, rows); r++) {
      for (int c = col; c < math.min(col + width, columns); c++) {
        final index = r * columns + c;
        if (index < _buffer.length) {
          _buffer[index] = TerminalCell.empty(style: style);
        }
      }
    }
    _damageTracker.markDirty(col, row, width, height);
  }


  /// Mark entire buffer as dirty.
  void markFullRedraw() {
    _fullRedrawNeeded = true;
    _damageTracker.clear();
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    _frameTimer.reset();
    _frameTimer.start();
    _dirtyCellsLastFrame = 0;

    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;

    if (_fullRedrawNeeded) {
      _renderRegion(canvas, 0, 0, columns, rows, cellWidth, cellHeight);
    } else {
      // Get optimized dirty regions from spatial tracker
      final dirtyRegions = _damageTracker.getOptimizedRegions();
      for (final region in dirtyRegions) {
        final startCol = math.max(region.left, 0);
        final endCol = math.min(region.right, columns);
        final startRow = math.max(region.top, 0);
        final endRow = math.min(region.bottom, rows);
        _renderRegion(canvas, startCol, startRow, endCol - startCol, endRow - startRow, cellWidth, cellHeight);
      }
    }

    _damageTracker.clear();
    _fullRedrawNeeded = false;
    _previousBuffer.setRange(0, _buffer.length, _buffer);

    _frameCount++;
    _frameTimer.stop();
    gpuRenderer.recordFrame(_frameTimer.elapsedMicroseconds / 1000.0);
  }

  void _renderRegion(ui.Canvas canvas, int startCol, int startRow, int width, int height, double cellWidth, double cellHeight) {
    for (int row = startRow; row < startRow + height && row < rows; row++) {
      for (int col = startCol; col < startCol + width && col < columns; col++) {
        final index = row * columns + col;
        if (index >= _buffer.length) continue;
        final cell = _buffer[index];
        if (cell.char == ' ' || cell.char.isEmpty) continue;
        _dirtyCellsLastFrame++;
        final x = col * cellWidth;
        final y = row * cellHeight;
        if (cell.style.backgroundColor != null) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x, y, cellWidth, cellHeight),
            ui.Paint()..color = cell.style.backgroundColor!,
          );
        }
        _renderCharacter(canvas, cell, x, y, cellWidth, cellHeight);
      }
    }
  }

  void _renderCharacter(ui.Canvas canvas, TerminalCell cell, double x, double y, double width, double height) {
    final cacheKey = _getParagraphCacheKey(cell.char, cell.style);
    ui.Paragraph? paragraph = _paragraphCache[cacheKey];
    if (paragraph == null) {
      paragraph = _createParagraph(cell.char, cell.style);
      _paragraphCache[cacheKey] = paragraph;
      _updateLru(cacheKey);
      if (_paragraphCache.length > _maxParagraphCache) {
        _evictOldestParagraphs(100);
      }
    } else {
      _updateLru(cacheKey);
    }
    canvas.drawParagraph(paragraph, ui.Offset(x, y + (height - paragraph.height) / 2));
  }

  ui.Paragraph _createParagraph(String text, TerminalStyle style) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      height: 1.0,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: style.foregroundColor ?? const ui.Color(0xFFf7da88),
        fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
      ))
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    return paragraph;
  }

  void _updateLru(String key) {
    _paragraphLru.remove(key);
    _paragraphLru.add(key);
  }

  void _evictOldestParagraphs(int count) {
    for (int i = 0; i < count && _paragraphLru.isNotEmpty; i++) {
      final key = _paragraphLru.removeAt(0);
      _paragraphCache.remove(key);
    }
  }

  String _getParagraphCacheKey(String text, TerminalStyle style) {
    return '${text.hashCode}_${style.foregroundColor?.value ?? 0}_${style.backgroundColor?.value ?? 0}_${style.bold}_${style.italic}_${style.underline}';
  }

  @override
  bool shouldRepaint(covariant HighPerformanceTerminalRenderer oldDelegate) {
    return true;
  }

  /// Get performance metrics.
  Map<String, dynamic> getMetrics() {
    return {
      'frameCount': _frameCount,
      'lastFrameTimeMs': _frameTimer.elapsedMicroseconds / 1000.0,
      'dirtyCellsLastFrame': _dirtyCellsLastFrame,
      'paragraphCacheSize': _paragraphCache.length,
      'fullRedrawNeeded': _fullRedrawNeeded,
      'damageRegions': _damageTracker.getRegionCount(),
    };
  }

  /// Dispose all resources.
  void dispose() {
    for (final paragraph in _paragraphCache.values) {
      paragraph.dispose();
    }
    _paragraphCache.clear();
    _paragraphLru.clear();
    _buffer.clear();
    _previousBuffer.clear();
    _damageTracker.dispose();
  }
}

/// Terminal cell with character and styling
class TerminalCell {
  final String char;
  final TerminalStyle style;
  
  const TerminalCell({
    required this.char,
    required this.style,
  });
  
  factory TerminalCell.empty({TerminalStyle? style}) {
    return TerminalCell(
      char: ' ',
      style: style ?? TerminalStyle.defaultStyle(),
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TerminalCell &&
        other.char == char &&
        other.style == style;
  }
  
  @override
  int get hashCode => char.hashCode ^ style.hashCode;
}

/// Spatial damage tracker for efficient region management.
class SpatialDamageTracker {
  final List<Rect> _dirtyRects = [];
  final List<Rect> _mergedRegions = [];
  static const int _maxRegions = 64;

  SpatialDamageTracker();

  void markDirty(int col, int row, int width, int height) {
    _dirtyRects.add(Rect.fromLTWH(col.toDouble(), row.toDouble(), width.toDouble(), height.toDouble()));
    _optimizeRegions();
  }

  void _optimizeRegions() {
    if (_dirtyRects.length < 2) return;

    // Merge overlapping and adjacent regions
    _mergedRegions.clear();
    final merged = <Rect>[];

    for (final rect in _dirtyRects) {
      bool absorbed = false;
      for (int i = 0; i < merged.length; i++) {
        if (_shouldMerge(merged[i], rect)) {
          merged[i] = _mergeRects(merged[i], rect);
          absorbed = true;
          break;
        }
      }
      if (!absorbed) merged.add(rect);
    }

    // Limit number of regions to prevent performance issues
    while (merged.length > _maxRegions) {
      _mergeLargestRegions(merged);
    }

    _dirtyRects.clear();
    _dirtyRects.addAll(merged);
  }

  bool _shouldMerge(Rect a, Rect b) {
    // Merge if overlapping or adjacent (within 1 cell tolerance)
    const tolerance = 1.0;
    return a.overlaps(b) ||
           (a.left <= b.right + tolerance && b.left <= a.right + tolerance &&
            a.top <= b.bottom + tolerance && b.top <= a.bottom + tolerance);
  }

  Rect _mergeRects(Rect a, Rect b) {
    return Rect.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
  }

  void _mergeLargestRegions(List<Rect> regions) {
    if (regions.length < 2) return;

    // Find the two largest regions by area
    int maxIdx1 = 0, maxIdx2 = 1;
    double maxArea1 = regions[0].width * regions[0].height;
    double maxArea2 = regions[1].width * regions[1].height;

    for (int i = 2; i < regions.length; i++) {
      final area = regions[i].width * regions[i].height;
      if (area > maxArea1) {
        maxArea2 = maxArea1;
        maxIdx2 = maxIdx1;
        maxArea1 = area;
        maxIdx1 = i;
      } else if (area > maxArea2) {
        maxArea2 = area;
        maxIdx2 = i;
      }
    }

    // Merge them
    final merged = _mergeRects(regions[maxIdx1], regions[maxIdx2]);
    regions.removeAt(math.max(maxIdx1, maxIdx2));
    regions.removeAt(math.min(maxIdx1, maxIdx2));
    regions.add(merged);
  }

  List<Rect> getOptimizedRegions() {
    return List.unmodifiable(_dirtyRects);
  }

  int getRegionCount() => _dirtyRects.length;

  void clear() {
    _dirtyRects.clear();
    _mergedRegions.clear();
  }

  void dispose() {
    clear();
  }
}

/// Terminal styling information
class TerminalStyle {
  final ui.Color? foregroundColor;
  final ui.Color? backgroundColor;
  final bool bold;
  final bool italic;
  final bool underline;
  
  const TerminalStyle({
    this.foregroundColor,
    this.backgroundColor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });
  
  factory TerminalStyle.defaultStyle() {
    return const TerminalStyle(
      foregroundColor: ui.Color(0xFFf7da88),
      backgroundColor: ui.Color(0xFF000000),
    );
  }
  
  TerminalStyle copyWith({
    ui.Color? foregroundColor,
    ui.Color? backgroundColor,
    bool? bold,
    bool? italic,
    bool? underline,
  }) {
    return TerminalStyle(
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TerminalStyle &&
        other.foregroundColor == foregroundColor &&
        other.backgroundColor == backgroundColor &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline;
  }
  
  @override
  int get hashCode {
    return foregroundColor.hashCode ^
        backgroundColor.hashCode ^
        bold.hashCode ^
        italic.hashCode ^
        underline.hashCode;
  }
}

/// Grid region for damage tracking
class GridRegion {
  final int col;
  final int row;
  final int width;
  final int height;
  
  const GridRegion(this.col, this.row, this.width, this.height);
  
  bool intersects(GridRegion other) {
    return col < other.col + other.width &&
           col + width > other.col &&
           row < other.row + other.height &&
           row + height > other.row;
  }
  
  GridRegion merge(GridRegion other) {
    final right = math.max(col + width, other.col + other.width);
    final bottom = math.max(row + height, other.row + other.height);
    final left = math.min(col, other.col);
    final top = math.min(row, other.row);
    
    return GridRegion(left, top, right - left, bottom - top);
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GridRegion &&
        other.col == col &&
        other.row == row &&
        other.width == width &&
        other.height == height;
  }
  
  @override
  int get hashCode => col.hashCode ^ row.hashCode ^ width.hashCode ^ height.hashCode;
  
  @override
  String toString() => 'GridRegion($col, $row, $width, $height)';
}
