import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xterm;
import '../core/production_gpu_renderer.dart';
import '../config/pkm_theme.dart';

/// Damage-aware terminal renderer with hardware acceleration
/// Provides optimal performance through dirty region tracking and GPU acceleration
class DamageAwareTerminalRenderer extends StatefulWidget {
  final xterm.Terminal terminal;
  final xterm.TerminalController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onSecondaryTapUp;
  final Function(TapUpDetails, int)? onSecondaryTapUpWithPosition;

  const DamageAwareTerminalRenderer({
    super.key,
    required this.terminal,
    required this.controller,
    this.focusNode,
    this.autofocus = true,
    this.onSecondaryTapUp,
    this.onSecondaryTapUpWithPosition,
  });

  @override
  State<DamageAwareTerminalRenderer> createState() => _DamageAwareTerminalRendererState();
}

class _DamageAwareTerminalRendererState extends State<DamageAwareTerminalRenderer>
    with WidgetsBindingObserver {
  late final _DamageAwarePainter _painter;
  late final _DamageTracker _damageTracker;
  final _textPainter = TextPainter();
  Timer? _renderTimer;
  bool _needsFullRedraw = true;
  int _lastRenderTime = 0;
  
  // Performance optimization: batch render updates
  static const Duration _batchDelay = Duration(milliseconds: 4);
  static const int _maxBatchSize = 50;
  static const double _charWidth = 8.0;
  static const double _charHeight = 16.0;

  @override
  void initState() {
    super.initState();
    _painter = _DamageAwarePainter(
      terminal: widget.terminal,
      textPainter: _textPainter,
      damageTracker: _damageTracker,
      charWidth: _charWidth,
      charHeight: _charHeight,
    );
    _damageTracker = _DamageTracker(_charWidth, _charHeight);
    
    // Listen to terminal changes for damage tracking
    widget.terminal.onRender = _onTerminalChanged;
    widget.terminal.onResize = _onTerminalResized;
    widget.terminal.onTitleChange = _onTerminalChanged;
    
    // Start performance monitoring
    WidgetsBinding.instance.addObserver(this);
    _scheduleOptimizedRender();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _renderTimer?.cancel();
    widget.terminal.onRender = null;
    widget.terminal.onResize = null;
    widget.terminal.onTitleChange = null;
    _textPainter.dispose();
    _damageTracker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DamageAwareTerminalRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.onRender = null;
      oldWidget.terminal.onResize = null;
      oldWidget.terminal.onTitleChange = null;
      widget.terminal.onRender = _onTerminalChanged;
      widget.terminal.onResize = _onTerminalResized;
      widget.terminal.onTitleChange = _onTerminalChanged;
      _needsFullRedraw = true;
      _scheduleOptimizedRender();
    }
  }

  void _onTerminalChanged() {
    _trackTerminalChanges();
    _scheduleOptimizedRender();
  }

  void _onTerminalResized() {
    _needsFullRedraw = true;
    _damageTracker.markFullDirty();
    _scheduleOptimizedRender();
  }

  void _trackTerminalChanges() {
    final buffer = widget.terminal.buffer;
    final rows = widget.terminal.rows;
    final cols = widget.terminal.cols;
    
    // Track changes in each line for damage tracking
    for (int row = 0; row < rows; row++) {
      final line = buffer.getLine(row);
      if (line == null) continue;
      
      bool lineChanged = false;
      for (int col = 0; col < cols; col++) {
        final code = line.getCodePoint(col);
        if (code != 0) {
          final cellKey = '${row}_$col';
          if (_damageTracker.hasCellChanged(cellKey, code, line.getForeground(col), line.getBackground(col))) {
            _damageTracker.markCellDirty(row, col);
            lineChanged = true;
          }
        }
      }
      
      if (lineChanged) {
        _damageTracker.markLineDirty(row);
      }
    }
  }

  void _scheduleOptimizedRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(_batchDelay, () {
      if (mounted && (_needsFullRedraw || _damageTracker.hasDirtyRegions)) {
        setState(() {
          _needsFullRedraw = false;
        });
        _recordRenderTime();
        _damageTracker.clearDirty();
      }
    });
  }

  void _recordRenderTime() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRenderTime > 0) {
      final frameTime = now - _lastRenderTime;
      ProductionGpuRenderer.instance.recordFrame(frameTime.toDouble());
    }
    _lastRenderTime = now;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onSecondaryTapUp: _handleSecondaryTapUp,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKey: _handleKey,
        child: CustomPaint(
          painter: _painter,
          child: Container(
            color: PkmTheme.terminalBg,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );
  }

  void _handleTapDown(TapDownDetails details) {
    final position = _getTerminalPosition(details.localPosition);
    if (position != null) {
      widget.controller.select(position);
    }
  }

  void _handleSecondaryTapUp(TapUpDetails details) {
    widget.onSecondaryTapUp?.call(details, null);
    final position = _getTerminalPosition(details.localPosition);
    if (position != null) {
      widget.onSecondaryTapUpWithPosition?.call(details, position);
    }
  }

  xterm.Position? _getTerminalPosition(Offset localPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final size = renderBox.size;
    final charWidth = size.width / widget.terminal.cols;
    final charHeight = size.height / widget.terminal.rows;

    final col = (localPosition.dx / charWidth).floor();
    final row = (localPosition.dy / charHeight).floor();

    if (col >= 0 && col < widget.terminal.cols && row >= 0 && row < widget.terminal.rows) {
      return xterm.Position(col, row);
    }
    return null;
  }

  KeyEventResult _handleKey(FocusNode node, RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      return widget.controller.handleKeyEvent(event) 
          ? KeyEventResult.handled 
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }
}

/// Damage-aware custom painter with GPU acceleration
class _DamageAwarePainter extends CustomPainter {
  final xterm.Terminal terminal;
  final TextPainter textPainter;
  final _DamageTracker damageTracker;
  final double charWidth;
  final double charHeight;
  
  final Map<String, ui.Paragraph> _paragraphCache = {};
  final Map<String, ui.Image> _imageCache = {};
  final Map<String, Paint> _paintCache = {};
  
  static const String _fontFamily = 'Droid Sans Mono';
  static const double _fontSize = 14.0;

  _DamageAwarePainter({
    required this.terminal,
    required this.textPainter,
    required this.damageTracker,
    required this.charWidth,
    required this.charHeight,
  }) : super(repaint: terminal);

  @override
  void paint(Canvas canvas, Size size) {
    final startTime = DateTime.now().microsecondsSinceEpoch;
    
    // Use GPU acceleration if available
    final gpuRenderer = ProductionGpuRenderer.instance;
    if (gpuRenderer.gpuAccelerationEnabled) {
      _paintWithGpuAcceleration(canvas, size);
    } else {
      _paintWithSoftware(canvas, size);
    }
    
    final renderTime = (DateTime.now().microsecondsSinceEpoch - startTime) / 1000.0;
    if (renderTime > 16.67) { // Log slow renders (>60fps)
      debugPrint('Slow terminal render: ${renderTime.toStringAsFixed(2)}ms');
    }
  }

  void _paintWithGpuAcceleration(Canvas canvas, Size size) {
    // Create GPU-accelerated layers for dirty regions only
    final dirtyRegions = damageTracker.dirtyRegions;
    
    if (dirtyRegions.isEmpty || damageTracker.needsFullRedraw) {
      // Full redraw
      _renderFullTerminal(canvas, size);
    } else {
      // Partial redraw of dirty regions only
      for (final region in dirtyRegions) {
        canvas.save();
        canvas.clipRect(region);
        _renderTerminalRegion(canvas, size, region);
        canvas.restore();
      }
    }
  }

  void _paintWithSoftware(Canvas canvas, Size size) {
    _renderFullTerminal(canvas, size);
  }

  void _renderFullTerminal(Canvas canvas, Size size) {
    final buffer = terminal.buffer;
    final rows = terminal.rows;
    final cols = terminal.cols;
    
    // Clear background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _getPaint(PkmTheme.terminalBg),
    );

    // Render each line
    for (int row = 0; row < rows; row++) {
      final line = buffer.getLine(row);
      if (line == null) continue;
      
      for (int col = 0; col < cols; col++) {
        final code = line.getCodePoint(col);
        if (code == 0) continue;
        
        final x = col * charWidth;
        final y = row * charHeight;
        
        _paintCell(canvas, code, line.getForeground(col), line.getBackground(col), x, y);
      }
    }
    
    // Render cursor
    _paintCursor(canvas);
  }

  void _renderTerminalRegion(Canvas canvas, Size size, Rect region) {
    final buffer = terminal.buffer;
    final cols = terminal.cols;
    
    final startCol = (region.left / charWidth).floor().clamp(0, cols - 1);
    final endCol = ((region.right / charWidth).ceil()).clamp(0, cols);
    final startRow = (region.top / charHeight).floor().clamp(0, terminal.rows - 1);
    final endRow = ((region.bottom / charHeight).ceil()).clamp(0, terminal.rows);
    
    for (int row = startRow; row <= endRow; row++) {
      final line = buffer.getLine(row);
      if (line == null) continue;
      
      for (int col = startCol; col <= endCol; col++) {
        final code = line.getCodePoint(col);
        if (code == 0) continue;
        
        final x = col * charWidth;
        final y = row * charHeight;
        
        _paintCell(canvas, code, line.getForeground(col), line.getBackground(col), x, y);
      }
    }
    
    // Render cursor if in dirty region
    final cursor = terminal.buffer.cursor;
    if (cursor.x >= startCol && cursor.x <= endCol && 
        cursor.y >= startRow && cursor.y <= endRow) {
      _paintCursor(canvas);
    }
  }

  void _paintCell(Canvas canvas, int code, int foreground, int background, double x, double y) {
    final backgroundColor = _resolveBackgroundColor(background);
    final foregroundColor = _resolveForegroundColor(foreground);
    
    // Draw background
    if (backgroundColor != PkmTheme.terminalBg) {
      canvas.drawRect(
        Rect.fromLTWH(x, y, charWidth, charHeight),
        _getPaint(backgroundColor),
      );
    }
    
    // Draw text
    final text = String.fromCharCode(code);
    final cacheKey = '${text}_${foregroundColor.value}_${backgroundColor.value}';
    
    ui.Paragraph? paragraph = _paragraphCache[cacheKey];
    if (paragraph == null) {
      paragraph = _createParagraph(text, foregroundColor);
      _paragraphCache[cacheKey] = paragraph;
    }
    
    paragraph.layout(ui.ParagraphConstraints(width: charWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  void _paintCursor(Canvas canvas) {
    final cursor = terminal.buffer.cursor;
    final x = cursor.x * charWidth;
    final y = cursor.y * charHeight;
    
    canvas.drawRect(
      Rect.fromLTWH(x, y, charWidth, charHeight),
      _getPaint(const Color(0xAAAEAFAD)),
    );
  }

  Paint _getPaint(Color color) {
    final key = 'paint_${color.value}';
    return _paintCache.putIfAbsent(key, () => Paint()..color = color);
  }

  ui.Paragraph _createParagraph(String text, Color color) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
    ));
    builder.pushStyle(ui.TextStyle(color: color));
    builder.addText(text);
    return builder.build();
  }

  Color _resolveForegroundColor(int cellColor) {
    final colorType = cellColor & xterm.CellColor.typeMask;
    final colorValue = cellColor & xterm.CellColor.valueMask;

    switch (colorType) {
      case xterm.CellColor.normal:
        return PkmTheme.text;
      case xterm.CellColor.named:
      case xterm.CellColor.palette:
        return _getPaletteColor(colorValue);
      case xterm.CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  Color _resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & xterm.CellColor.typeMask;
    final colorValue = cellColor & xterm.CellColor.valueMask;

    switch (colorType) {
      case xterm.CellColor.normal:
        return PkmTheme.terminalBg;
      case xterm.CellColor.named:
      case xterm.CellColor.palette:
        return _getPaletteColor(colorValue);
      case xterm.CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  Color _getPaletteColor(int index) {
    switch (index) {
      case 0: return const Color(0xFF000000);
      case 1: return const Color(0xFFE06C75);
      case 2: return const Color(0xFF98C379);
      case 3: return const Color(0xFFE5C07B);
      case 4: return const Color(0xFF61AFEF);
      case 5: return const Color(0xFFC678DD);
      case 6: return const Color(0xFF56B6C2);
      case 7: return const Color(0xFFABB2BF);
      case 8: return const Color(0xFF5C6370);
      case 9: return const Color(0xFFE06C75);
      case 10: return const Color(0xFF98C379);
      case 11: return const Color(0xFFE5C07B);
      case 12: return const Color(0xFF61AFEF);
      case 13: return const Color(0xFFC678DD);
      case 14: return const Color(0xFF56B6C2);
      case 15: return const Color(0xFFFFFFFF);
      default: return const Color(0xFFf7da88);
    }
  }

  @override
  bool shouldRepaint(covariant _DamageAwarePainter oldDelegate) {
    return oldDelegate.terminal != terminal || 
           damageTracker.hasDirtyRegions ||
           damageTracker.needsFullRedraw;
  }
}

/// Advanced damage tracking with cell-level granularity
class _DamageTracker {
  final double charWidth;
  final double charHeight;
  final Set<Rect> _dirtyRegions = {};
  final Set<int> _dirtyLines = {};
  final Map<String, String> _cellStates = {};
  bool _needsFullRedraw = false;
  
  static const int _maxDirtyRegions = 100;

  _DamageTracker(this.charWidth, this.charHeight);

  void markFullDirty() {
    _needsFullRedraw = true;
    _dirtyRegions.clear();
    _dirtyLines.clear();
  }

  void markCellDirty(int row, int col) {
    final region = Rect.fromLTWH(
      col * charWidth,
      row * charHeight,
      charWidth,
      charHeight,
    );
    _dirtyRegions.add(region);
    
    // Limit dirty regions to prevent performance issues
    if (_dirtyRegions.length > _maxDirtyRegions) {
      markFullDirty();
    }
  }

  void markLineDirty(int row) {
    _dirtyLines.add(row);
  }

  void markRegionDirty(Rect region) {
    _dirtyRegions.add(region);
  }

  bool hasCellChanged(String cellKey, int code, int foreground, int background) {
    final state = '${code}_${foreground}_${background}';
    final oldState = _cellStates[cellKey];
    _cellStates[cellKey] = state;
    return oldState != state;
  }

  void clearDirty() {
    _dirtyRegions.clear();
    _dirtyLines.clear();
    _needsFullRedraw = false;
  }

  bool get hasDirtyRegions => _dirtyRegions.isNotEmpty || _dirtyLines.isNotEmpty;
  bool get needsFullRedraw => _needsFullRedraw;
  Set<Rect> get dirtyRegions => Set.unmodifiable(_dirtyRegions);
  Set<int> get dirtyLines => Set.unmodifiable(_dirtyLines);

  void dispose() {
    _dirtyRegions.clear();
    _dirtyLines.clear();
    _cellStates.clear();
  }
}
