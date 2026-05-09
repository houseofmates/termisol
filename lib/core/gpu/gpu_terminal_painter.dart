import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show BufferLine, BufferRange, TerminalPainter, TerminalStyle, TerminalTheme;
import 'package:xterm/xterm.dart' show CellAttr, CellColor, CellContent, CellData;

import 'color_resolver.dart';
import 'line_picture_cache.dart';

/// a high-performance gpu-accelerated terminal painter.
///
/// this painter batches background rectangles into a single [vertices] draw call
/// and caches entire lines as [picture] objects so that static scrollback is
/// replayed from gpu instruction memory instead of being rebuilt every frame.
///
/// text is still shaped by skia/impeller via [paragraphbuilder]; each unique
/// glyph/style combination is cached in an internal lru map.
class GpuTerminalPainter extends TerminalPainter {
  GpuTerminalPainter({
    required super.theme,
    required super.textStyle,
    required super.textScaler,
  }) : _colorResolver = TerminalColorResolver(theme);

  final TerminalColorResolver _colorResolver;
  final LinePictureCache _lineCache = LinePictureCache();
  final Map<int, Paragraph> _paragraphCache = {};

  @override
  set theme(TerminalTheme value) {
    super.theme = value;
    _colorResolver.updateTheme(value);
    _lineCache.clear();
    _paragraphCache.clear();
  }

  @override
  set textStyle(TerminalStyle value) {
    super.textStyle = value;
    _lineCache.clear();
    _paragraphCache.clear();
  }

  @override
  set textScaler(TextScaler value) {
    super.textScaler = value;
    _lineCache.clear();
    _paragraphCache.clear();
  }

  @override
  void clearFontCache() {
    super.clearFontCache();
    _lineCache.clear();
    _paragraphCache.clear();
  }

  @override
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line, {
    int? lineIndex,
    BufferRange? selection,
  }) {
    if (lineIndex == null) {
      _drawLineDirect(canvas, offset, line);
      return;
    }

    final hasSelection = selection != null && _lineIntersectsSelection(lineIndex, selection);
    if (hasSelection) {
      _drawLineDirect(canvas, offset, line);
      return;
    }

    final cached = _lineCache.get(lineIndex, line);
    if (cached != null) {
      canvas.drawPicture(cached);
      return;
    }

    final recorder = PictureRecorder();
    final recordCanvas = Canvas(recorder);
    _drawLineDirect(recordCanvas, offset, line);
    final picture = recorder.endRecording();
    _lineCache.put(lineIndex, line, picture);
    canvas.drawPicture(picture);
  }

  /// Paints a line directly to [canvas] without picture caching.
  void _drawLineDirect(Canvas canvas, Offset offset, BufferLine line) {
    _drawBackgrounds(canvas, offset, line);
    _drawForegrounds(canvas, offset, line);
  }

  void _drawBackgrounds(Canvas canvas, Offset offset, BufferLine line) {
    final cellWidth = cellSize.width;
    final cellHeight = cellSize.height;
    final positions = <double>[];
    final colors = <int>[];
    final cellData = CellData.empty();

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);
      final width = cellData.content >> CellContent.widthShift;

      Color? color;
      if (cellData.flags & CellAttr.inverse != 0) {
        color = _colorResolver.resolveForeground(cellData.foreground);
      } else {
        final bgType = cellData.background & CellColor.typeMask;
        if (bgType != CellColor.normal) {
          color = _colorResolver.resolveBackground(cellData.background);
        }
      }

      if (color != null) {
        final left = offset.dx + i * cellWidth;
        final top = offset.dy;
        final right = left + cellWidth * (width == 2 ? 2 : 1);
        final bottom = top + cellHeight;
        _addRect(positions, colors, left, top, right, bottom, color.toARGB32());
      }

      if (width == 2) i++;
    }

    if (positions.isNotEmpty) {
      final vertices = Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(positions),
        colors: Int32List.fromList(colors),
      );
      canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    }
  }

  void _drawForegrounds(Canvas canvas, Offset offset, BufferLine line) {
    final cellWidth = cellSize.width;
    final cellData = CellData.empty();

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);
      final codepoint = cellData.content & CellContent.codepointMask;
      final width = cellData.content >> CellContent.widthShift;

      if (codepoint == 0) {
        if (width == 2) i++;
        continue;
      }

      if (cellData.flags & CellAttr.invisible != 0) {
        if (width == 2) i++;
        continue;
      }

      Color color;
      if (cellData.flags & CellAttr.inverse != 0) {
        color = _colorResolver.resolveBackground(cellData.background);
      } else {
        color = _colorResolver.resolveForeground(cellData.foreground);
      }

      if (cellData.flags & CellAttr.faint != 0) {
        color = color.withValues(alpha: 0.5);
      }

      final style = TextStyle(
        fontSize: textStyle.fontSize,
        height: textStyle.height,
        fontFamily: textStyle.fontFamily,
        fontFamilyFallback: textStyle.fontFamilyFallback,
        color: color,
        fontWeight: cellData.flags & CellAttr.bold != 0 ? FontWeight.bold : FontWeight.normal,
        fontStyle: cellData.flags & CellAttr.italic != 0 ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (cellData.flags & CellAttr.underline != 0) TextDecoration.underline,
          if (cellData.flags & CellAttr.strikethrough != 0) TextDecoration.lineThrough,
        ]),
      );

      final char = String.fromCharCode(codepoint);
      final paragraph = _getParagraph(char, style);
      canvas.drawParagraph(paragraph, Offset(offset.dx + i * cellWidth, offset.dy));

      if (width == 2) i++;
    }
  }

  Paragraph _getParagraph(String text, TextStyle style) {
    final key = Object.hash(
      text,
      style.color,
      style.fontWeight,
      style.fontStyle,
      style.decoration,
      textScaler.hashCode,
    );

    var paragraph = _paragraphCache[key];
    if (paragraph == null) {
      final builder = ParagraphBuilder(style.getParagraphStyle());
      builder.pushStyle(style.getTextStyle(textScaler: textScaler));
      builder.addText(text);
      paragraph = builder.build();
      paragraph.layout(const ParagraphConstraints(width: double.infinity));
      _paragraphCache[key] = paragraph;

      if (_paragraphCache.length > 4096) {
        _paragraphCache.remove(_paragraphCache.keys.first);
      }
    }
    return paragraph;
  }

  static void _addRect(
    List<double> positions,
    List<int> colors,
    double left,
    double top,
    double right,
    double bottom,
    int colorValue,
  ) {
    // First triangle: top-left, top-right, bottom-left
    positions.addAll([left, top, right, top, left, bottom]);
    colors.addAll([colorValue, colorValue, colorValue]);
    // Second triangle: top-right, bottom-right, bottom-left
    positions.addAll([right, top, right, bottom, left, bottom]);
    colors.addAll([colorValue, colorValue, colorValue]);
  }

  static bool _lineIntersectsSelection(int lineIndex, BufferRange selection) {
    final beginLine = selection.begin.y;
    final endLine = selection.end.y;
    return lineIndex >= beginLine && lineIndex <= endLine;
  }
}
