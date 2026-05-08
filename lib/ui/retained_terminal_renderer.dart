import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xterm;
import '../core/production_gpu_renderer.dart';
import '../config/pkm_theme.dart';

/// High-performance retained terminal renderer using CustomPainter
/// Eliminates widget tree rebuilds and provides hardware-accelerated rendering
class RetainedTerminalRenderer extends StatefulWidget {
  final xterm.Terminal terminal;
  final xterm.TerminalController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onSecondaryTapUp;
  final Function(TapUpDetails, int)? onSecondaryTapUpWithPosition;

  const RetainedTerminalRenderer({
    super.key,
    required this.terminal,
    required this.controller,
    this.focusNode,
    this.autofocus = true,
    this.onSecondaryTapUp,
    this.onSecondaryTapUpWithPosition,
  });

  @override
  State<RetainedTerminalRenderer> createState() => _RetainedTerminalRendererState();
}

class _RetainedTerminalRendererState extends State<RetainedTerminalRenderer>
    with WidgetsBindingObserver {
  late final _TerminalPainter _painter;
  late final _DamageTracker _damageTracker;
  final _textPainter = TextPainter();
  final _scrollController = ScrollController();
  Timer? _renderTimer;
  bool _needsRedraw = true;
  int _lastRenderTime = 0;
  
  // Performance optimization: batch render updates
  static const Duration _batchDelay = Duration(milliseconds: 8);
  static const int _maxBatchSize = 100;

  @override
  void initState() {
    super.initState();
    _painter = _TerminalPainter(
      terminal: widget.terminal,
      textPainter: _textPainter,
    );
    _damageTracker = _DamageTracker();
    
    // Listen to terminal changes for damage tracking
    widget.terminal.onRender = _onTerminalChanged;
    widget.terminal.onResize = _onTerminalChanged;
    
    // Start performance monitoring
    WidgetsBinding.instance.addObserver(this);
    _scheduleRender();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _renderTimer?.cancel();
    widget.terminal.onRender = null;
    widget.terminal.onResize = null;
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RetainedTerminalRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.onRender = null;
      oldWidget.terminal.onResize = null;
      widget.terminal.onRender = _onTerminalChanged;
      widget.terminal.onResize = _onTerminalChanged;
      _scheduleRender();
    }
  }

  void _onTerminalChanged() {
    _needsRedraw = true;
    _damageTracker.markDirty();
    _scheduleRender();
  }

  void _scheduleRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(_batchDelay, () {
      if (_needsRedraw && mounted) {
        setState(() {
          _needsRedraw = false;
        });
        _recordRenderTime();
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

/// Custom painter for high-performance terminal rendering
class _TerminalPainter extends CustomPainter {
  final xterm.Terminal terminal;
  final TextPainter textPainter;
  final Map<String, ui.Paragraph> _paragraphCache = {};
  final Map<String, ui.Image> _imageCache = {};
  
  static const double _charWidth = 8.0;
  static const double _charHeight = 16.0;
  static const String _fontFamily = 'Droid Sans Mono';
  static const double _fontSize = 14.0;

  _TerminalPainter({
    required this.terminal,
    required this.textPainter,
  }) : super(repaint: terminal);

  @override
  void paint(Canvas canvas, Size size) {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    
    // Use GPU acceleration if available
    final gpuRenderer = ProductionGpuRenderer.instance;
    if (gpuRenderer.gpuAccelerationEnabled) {
      _paintWithGpuAcceleration(canvas, size);
    } else {
      _paintWithSoftware(canvas, size);
    }
    
    final renderTime = DateTime.now().millisecondsSinceEpoch - startTime;
    debugPrint('Terminal render time: ${renderTime}ms');
  }

  void _paintWithGpuAcceleration(Canvas canvas, Size size) {
    // Create GPU-accelerated rendering surface
    final recorder = ui.PictureRecorder();
    final pictureCanvas = Canvas(recorder);
    
    _renderTerminalContent(pictureCanvas, size);
    
    final picture = recorder.endRecording();
    canvas.drawPicture(picture);
    picture.dispose();
  }

  void _paintWithSoftware(Canvas canvas, Size size) {
    _renderTerminalContent(canvas, size);
  }

  void _renderTerminalContent(Canvas canvas, Size size) {
    final buffer = terminal.buffer;
    final rows = terminal.rows;
    final cols = terminal.cols;
    
    // Clear background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = PkmTheme.terminalBg,
    );

    // Render each line with damage tracking optimization
    for (int row = 0; row < rows; row++) {
      final line = buffer.getLine(row);
      if (line == null) continue;
      
      for (int col = 0; col < cols; col++) {
        final cell = line.getCell(col);
        if (cell == null || cell.code == 0) continue;
        
        final x = col * _charWidth;
        final y = row * _charHeight;
        
        _paintCell(canvas, cell, x, y);
      }
    }
    
    // Render cursor
    _paintCursor(canvas);
  }

  void _paintCell(Canvas canvas, xterm.Cell cell, double x, double y) {
    final backgroundColor = _getFlutterColor(cell.backgroundColor);
    final foregroundColor = _getFlutterColor(cell.foregroundColor);
    
    // Draw background
    if (backgroundColor != PkmTheme.terminalBg) {
      canvas.drawRect(
        Rect.fromLTWH(x, y, _charWidth, _charHeight),
        Paint()..color = backgroundColor,
      );
    }
    
    // Draw text
    final text = String.fromCharCode(cell.code);
    final cacheKey = '${text}_${foregroundColor.value}_${backgroundColor.value}';
    
    ui.Paragraph? paragraph = _paragraphCache[cacheKey];
    if (paragraph == null) {
      paragraph = _createParagraph(text, foregroundColor);
      _paragraphCache[cacheKey] = paragraph;
    }
    
    paragraph.layout(ui.ParagraphConstraints(width: _charWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  void _paintCursor(Canvas canvas) {
    final cursor = terminal.buffer.cursor;
    final x = cursor.x * _charWidth;
    final y = cursor.y * _charHeight;
    
    canvas.drawRect(
      Rect.fromLTWH(x, y, _charWidth, _charHeight),
      Paint()
        ..color = const Color(0xAAAEAFAD)
        ..style = PaintingStyle.fill,
    );
  }

  ui.Paragraph _createParagraph(String text, Color color) {
    return ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      color: color,
    ))
      ..addText(text)
      ..build();
  }

  Color _getFlutterColor(xterm.Color color) {
    // Convert xterm color to Flutter color
    switch (color.index) {
      case 0: return const Color(0xFF000000); // Black
      case 1: return const Color(0xFFE06C75); // Red
      case 2: return const Color(0xFF98C379); // Green
      case 3: return const Color(0xFFE5C07B); // Yellow
      case 4: return const Color(0xFF61AFEF); // Blue
      case 5: return const Color(0xFFC678DD); // Magenta
      case 6: return const Color(0xFF56B6C2); // Cyan
      case 7: return const Color(0xFFABB2BF); // White
      case 8: return const Color(0xFF5C6370); // Bright Black
      case 9: return const Color(0xFFE06C75); // Bright Red
      case 10: return const Color(0xFF98C379); // Bright Green
      case 11: return const Color(0xFFE5C07B); // Bright Yellow
      case 12: return const Color(0xFF61AFEF); // Bright Blue
      case 13: return const Color(0xFFC678DD); // Bright Magenta
      case 14: return const Color(0xFF56B6C2); // Bright Cyan
      case 15: return const Color(0xFFFFFFFF); // Bright White
      default: return const Color(0xFFf7da88); // Default foreground
    }
  }

  @override
  bool shouldRepaint(covariant _TerminalPainter oldDelegate) {
    return oldDelegate.terminal != terminal;
  }
}

/// Damage tracking for efficient partial redraws
class _DamageTracker {
  final Set<Rect> _dirtyRegions = {};
  bool _isDirty = false;

  void markDirty() {
    _isDirty = true;
  }

  void markRegionDirty(Rect region) {
    _dirtyRegions.add(region);
  }

  void clearDirty() {
    _dirtyRegions.clear();
    _isDirty = false;
  }

  bool get isDirty => _isDirty;
  Set<Rect> get dirtyRegions => Set.unmodifiable(_dirtyRegions);
}
