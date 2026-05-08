import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'production_gpu_renderer.dart';

/// High-performance terminal renderer with CustomPainter and damage tracking
/// 
/// Replaces the slow xterm package widget-based rendering with a retained
/// grid system that only redraws changed regions (damage tracking).
class HighPerformanceTerminalRenderer {
  final int columns;
  final int rows;
  final ProductionGpuRenderer gpuRenderer;
  
  // Terminal buffer - character grid with styling
  final List<TerminalCell> _buffer;
  final List<TerminalCell> _previousBuffer;
  
  // Damage tracking
  final Set<GridRegion> _dirtyRegions = {};
  bool _fullRedrawNeeded = true;
  
  // Rendering state
  final TextPainter _textPainter = TextPainter();
  final Map<String, ui.Paragraph> _paragraphCache = {};
  final Map<String, ui.Image> _imageCache = {};
  
  // Performance metrics
  int _frameCount = 0;
  int _dirtyCellsLastFrame = 0;
  final Stopwatch _frameTimer = Stopwatch()..start();
  
  // Font measurement
  late final double _charWidth;
  late final double _charHeight;
  late final double _lineHeight;
  
  HighPerformanceTerminalRenderer({
    required this.columns,
    required this.rows,
    required this.gpuRenderer,
  }) : _buffer = List.generate(columns * rows, (_) => TerminalCell.empty()),
       _previousBuffer = List.generate(columns * rows, (_) => TerminalCell.empty()) {
    _initializeFontMetrics();
  }
  
  void _initializeFontMetrics() {
    _textPainter.textDirection = TextDirection.ltr;
    _textPainter.text = const TextSpan(
      text: 'M',
      style: TextStyle(
        fontFamily: 'Droid Sans Mono',
        fontSize: 14,
        height: 1.0,
      ),
    );
    _textPainter.layout();
    
    _charWidth = _textPainter.width;
    _charHeight = _textPainter.height;
    _lineHeight = _charHeight * 1.2; // Add some line spacing
  }
  
  /// Write text to the terminal buffer
  void write(String text, {
    int? col, 
    int? row, 
    TerminalStyle? style,
    bool moveCursor = true,
  }) {
    final lines = text.split('\n');
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final currentRow = (row ?? 0) + lineIndex;
      
      if (currentRow >= rows) break;
      
      final startCol = lineIndex == 0 ? (col ?? 0) : 0;
      for (int i = 0; i < line.length && startCol + i < columns; i++) {
        final bufferIndex = currentRow * columns + startCol + i;
        if (bufferIndex < _buffer.length) {
          final oldCell = _buffer[bufferIndex];
          _buffer[bufferIndex] = TerminalCell(
            char: line[i],
            style: style ?? TerminalStyle.defaultStyle(),
          );
          
          // Mark as dirty if changed
          if (oldCell != _buffer[bufferIndex]) {
            _markDirty(startCol + i, currentRow);
          }
        }
      }
    }
  }
  
  /// Clear the terminal buffer
  void clear({TerminalStyle? style}) {
    for (int i = 0; i < _buffer.length; i++) {
      _buffer[i] = TerminalCell.empty(style: style);
      _markDirtyByIndex(i);
    }
  }
  
  /// Clear a rectangular region
  void clearRegion(int col, int row, int width, int height, {TerminalStyle? style}) {
    for (int r = row; r < math.min(row + height, rows); r++) {
      for (int c = col; c < math.min(col + width, columns); c++) {
        final index = r * columns + c;
        if (index < _buffer.length) {
          _buffer[index] = TerminalCell.empty(style: style);
          _markDirty(c, r);
        }
      }
    }
  }
  
  /// Mark a cell as dirty
  void _markDirty(int col, int row) {
    _dirtyRegions.add(GridRegion(col, row, 1, 1));
  }
  
  /// Mark a cell as dirty by buffer index
  void _markDirtyByIndex(int index) {
    final col = index % columns;
    final row = index ~/ columns;
    _markDirty(col, row);
  }
  
  /// Mark entire buffer as dirty (full redraw)
  void markFullRedraw() {
    _fullRedrawNeeded = true;
    _dirtyRegions.clear();
  }
  
  /// Get dirty regions for rendering
  List<GridRegion> getDirtyRegions() {
    if (_fullRedrawNeeded) {
      return [GridRegion(0, 0, columns, rows)];
    }
    
    // Merge overlapping regions for efficiency
    final merged = <GridRegion>[];
    final regions = _dirtyRegions.toList();
    
    for (final region in regions) {
      bool merged = false;
      for (int i = 0; i < merged.length; i++) {
        if (merged[i].intersects(region)) {
          merged[i] = merged[i].merge(region);
          merged = true;
          break;
        }
      }
      if (!merged) {
        merged.add(region);
      }
    }
    
    return merged;
  }
  
  /// Render the terminal to a canvas
  void render(ui.Canvas canvas, Size size) {
    _frameTimer.reset();
    _dirtyCellsLastFrame = 0;
    
    final dirtyRegions = getDirtyRegions();
    
    for (final region in dirtyRegions) {
      _renderRegion(canvas, region, size);
    }
    
    // Clear dirty regions for next frame
    _dirtyRegions.clear();
    _fullRedrawNeeded = false;
    
    // Copy current buffer to previous for diffing
    _previousBuffer.setRange(0, _buffer.length, _buffer);
    
    _frameCount++;
    _frameTimer.stop();
    
    // Update GPU renderer metrics
    gpuRenderer.recordFrame(_frameTimer.elapsedMicroseconds / 1000.0);
  }
  
  /// Render a specific region
  void _renderRegion(ui.Canvas canvas, GridRegion region, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    
    for (int row = region.row; row < region.row + region.height && row < rows; row++) {
      for (int col = region.col; col < region.col + region.width && col < columns; col++) {
        final index = row * columns + col;
        if (index >= _buffer.length) continue;
        
        final cell = _buffer[index];
        if (cell.char.isEmpty) continue;
        
        _dirtyCellsLastFrame++;
        
        // Calculate cell position
        final x = col * cellWidth;
        final y = row * cellHeight;
        
        // Draw background if needed
        if (cell.style.backgroundColor != null) {
          final bgPaint = Paint()
            ..color = cell.style.backgroundColor!;
          canvas.drawRect(
            Rect.fromLTWH(x, y, cellWidth, cellHeight),
            bgPaint,
          );
        }
        
        // Draw character
        _renderCharacter(canvas, cell, x, y, cellWidth, cellHeight);
      }
    }
  }
  
  /// Render a single character
  void _renderCharacter(ui.Canvas canvas, TerminalCell cell, double x, double y, double width, double height) {
    final cacheKey = _getParagraphCacheKey(cell.char, cell.style);
    ui.Paragraph? paragraph = _paragraphCache[cacheKey];
    
    if (paragraph == null) {
      paragraph = _createParagraph(cell.char, cell.style);
      _paragraphCache[cacheKey] = paragraph;
      
      // Limit cache size
      if (_paragraphCache.length > 1000) {
        final keysToRemove = _paragraphCache.keys.take(100);
        for (final key in keysToRemove) {
          _paragraphCache.remove(key);
        }
      }
    }
    
    canvas.drawParagraph(
      paragraph,
      Offset(x, y + (height - paragraph.height) / 2),
    );
  }
  
  /// Create a text paragraph for rendering
  ui.Paragraph _createParagraph(String text, TerminalStyle style) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'Droid Sans Mono',
      fontSize: 14,
      height: 1.0,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: style.foregroundColor ?? const Color(0xFFf7da88),
        backgroundColor: style.backgroundColor,
        fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
      ))
      ..addText(text);
    
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: double.infinity));
    return paragraph;
  }
  
  /// Get cache key for paragraph
  String _getParagraphCacheKey(String text, TerminalStyle style) {
    return '${text}_${style.hashCode}';
  }
  
  /// Get performance metrics
  Map<String, dynamic> getMetrics() {
    return {
      'frameCount': _frameCount,
      'lastFrameTime': _frameTimer.elapsedMicroseconds / 1000.0,
      'dirtyCellsLastFrame': _dirtyCellsLastFrame,
      'paragraphCacheSize': _paragraphCache.length,
      'imageCacheSize': _imageCache.length,
      'fullRedrawNeeded': _fullRedrawNeeded,
      'dirtyRegionsCount': _dirtyRegions.length,
    };
  }
  
  /// Dispose resources
  void dispose() {
    _textPainter.dispose();
    _paragraphCache.clear();
    _imageCache.clear();
    _buffer.clear();
    _previousBuffer.clear();
    _dirtyRegions.clear();
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

/// Terminal styling information
class TerminalStyle {
  final Color? foregroundColor;
  final Color? backgroundColor;
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
      foregroundColor: Color(0xFFf7da88),
      backgroundColor: Color(0xFF000000),
    );
  }
  
  TerminalStyle copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
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
