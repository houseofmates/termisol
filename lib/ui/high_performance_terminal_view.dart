import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/high_performance_terminal_renderer.dart';
import '../core/terminal_session.dart';
import '../core/production_gpu_renderer.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';

/// High-performance terminal view using CustomPainter with damage tracking.
///
/// Uses [HighPerformanceTerminalRenderer] directly as a [CustomPainter]
/// to paint terminal cells with cached paragraphs and dirty-region tracking.
class HighPerformanceTerminalView extends StatefulWidget {
  final TerminalSession session;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onNewTab;
  final VoidCallback? onNewWindow;
  final VoidCallback? onCloseTab;
  final Future<String> Function(String text)? onSummarize;

  const HighPerformanceTerminalView({
    super.key,
    required this.session,
    this.autofocus = true,
    this.focusNode,
    this.onNewTab,
    this.onNewWindow,
    this.onCloseTab,
    this.onSummarize,
  });

  @override
  State<HighPerformanceTerminalView> createState() => _HighPerformanceTerminalViewState();
}

class _HighPerformanceTerminalViewState extends State<HighPerformanceTerminalView> 
    with WidgetsBindingObserver {
  late final HighPerformanceTerminalRenderer _renderer;
  late final ProductionGpuRenderer _gpuRenderer;
  late final TerminalClipboardManager _clipboard;
  late final FocusNode _focusNode;
  
  // Terminal dimensions
  static const int defaultColumns = 80;
  static const int defaultRows = 24;
  int _columns = defaultColumns;
  int _rows = defaultRows;
  
  // Performance monitoring
  Timer? _performanceTimer;
  double _averageFrameTime = 0.0;
  int _droppedFrames = 0;
  
  // Input handling
  final StringBuffer _inputBuffer = StringBuffer();
  bool _isComposing = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize GPU renderer
    _gpuRenderer = ProductionGpuRenderer.instance;
    
    // Initialize high-performance renderer
    _renderer = HighPerformanceTerminalRenderer(
      columns: _columns,
      rows: _rows,
      gpuRenderer: _gpuRenderer,
    );
    
    // Initialize clipboard
    _clipboard = TerminalClipboardManager(
      widget.session.terminal,
      widget.session.controller,
    );
    
    _focusNode = widget.focusNode ?? FocusNode();
    
    // Setup terminal session
    _setupTerminalSession();
    
    // Start performance monitoring
    _startPerformanceMonitoring();
  }
  
  void _setupTerminalSession() {
    // Listen for terminal output
    widget.session.onOutputReceived = _handleTerminalOutput;
    
    // Handle AI queries
    widget.session.onAiQuery = _handleAiQuery;
    
    // Handle edit commands
    widget.session.onEditCommand = _handleEditCommand;
    
    // Listen for focus changes
    widget.session.onFocusChanged = (hasFocus) {
      if (hasFocus) {
        _focusNode.requestFocus();
      }
    };
  }
  
  void _handleTerminalOutput(String output) {
    // Parse ANSI escape sequences and render
    _parseAndRenderAnsi(output);
  }
  
  void _parseAndRenderAnsi(String text) {
    // Simple ANSI parsing - in a real implementation, this would be more sophisticated
    final buffer = StringBuffer();
    TerminalStyle currentStyle = TerminalStyle.defaultStyle();
    int col = 0;
    int row = 0;
    
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      
      if (char == '\x1b' && i + 1 < text.length && text[i + 1] == '[') {
        // ANSI escape sequence
        i += 2; // Skip ESC and [
        final seq = StringBuffer();
        
        while (i < text.length && text[i] != 'm' && text[i] != 'H' && text[i] != 'J') {
          seq.write(text[i]);
          i++;
        }
        
        if (i < text.length) {
          final command = text[i];
          final params = seq.toString();
          
          switch (command) {
            case 'm': // SGR (Select Graphic Rendition)
              currentStyle = _parseSgrSequence(params, currentStyle);
              break;
            case 'H': // Cursor position
              final parts = params.split(';');
              if (parts.length >= 2) {
                row = int.tryParse(parts[0]) ?? 1;
                col = int.tryParse(parts[1]) ?? 1;
                row--; // Convert to 0-based
                col--;
              }
              break;
            case 'J': // Clear screen
              if (params == '2') {
                _renderer.clear(style: currentStyle);
                col = 0;
                row = 0;
              }
              break;
          }
        }
      } else if (char == '\n') {
        // Move to next line
        if (!buffer.isEmpty) {
          _renderer.write(buffer.toString(), col: col, row: row, style: currentStyle);
          buffer.clear();
        }
        col = 0;
        row++;
        if (row >= _rows) {
          row = _rows - 1;
          _scrollUp();
        }
      } else if (char == '\r') {
        // Carriage return
        if (!buffer.isEmpty) {
          _renderer.write(buffer.toString(), col: col, row: row, style: currentStyle);
          buffer.clear();
        }
        col = 0;
      } else if (char.codeUnitAt(0) >= 32) {
        // Printable character
        buffer.write(char);
        col++;
        
        if (col >= _columns) {
          _renderer.write(buffer.toString(), col: 0, row: row, style: currentStyle);
          buffer.clear();
          col = 0;
          row++;
          if (row >= _rows) {
            row = _rows - 1;
            _scrollUp();
          }
        }
      }
    }
    
    // Write any remaining buffer
    if (!buffer.isEmpty) {
      _renderer.write(buffer.toString(), col: col, row: row, style: currentStyle);
    }
    
    // Trigger repaint
    if (mounted) setState(() {});
  }
  
  TerminalStyle _parseSgrSequence(String params, TerminalStyle currentStyle) {
    if (params.isEmpty) {
      return TerminalStyle.defaultStyle();
    }
    
    final codes = params.split(';');
    var style = currentStyle;
    
    for (final code in codes) {
      final value = int.tryParse(code) ?? 0;
      
      switch (value) {
        case 0: // Reset
          style = TerminalStyle.defaultStyle();
          break;
        case 1: // Bold
          style = style.copyWith(bold: true);
          break;
        case 3: // Italic
          style = style.copyWith(italic: true);
          break;
        case 4: // Underline
          style = style.copyWith(underline: true);
          break;
        case 30: // Black foreground
          style = style.copyWith(foregroundColor: const Color(0xFF000000));
          break;
        case 31: // Red foreground
          style = style.copyWith(foregroundColor: const Color(0xFFE06C75));
          break;
        case 32: // Green foreground
          style = style.copyWith(foregroundColor: const Color(0xFF98C379));
          break;
        case 33: // Yellow foreground
          style = style.copyWith(foregroundColor: const Color(0xFFE5C07B));
          break;
        case 34: // Blue foreground
          style = style.copyWith(foregroundColor: const Color(0xFF61AFEF));
          break;
        case 35: // Magenta foreground
          style = style.copyWith(foregroundColor: const Color(0xFFC678DD));
          break;
        case 36: // Cyan foreground
          style = style.copyWith(foregroundColor: const Color(0xFF56B6C2));
          break;
        case 37: // White foreground
          style = style.copyWith(foregroundColor: const Color(0xFFABB2BF));
          break;
        case 40: // Black background
          style = style.copyWith(backgroundColor: const Color(0xFF000000));
          break;
        case 41: // Red background
          style = style.copyWith(backgroundColor: const Color(0xFFE06C75));
          break;
        case 42: // Green background
          style = style.copyWith(backgroundColor: const Color(0xFF98C379));
          break;
        case 43: // Yellow background
          style = style.copyWith(backgroundColor: const Color(0xFFE5C07B));
          break;
        case 44: // Blue background
          style = style.copyWith(backgroundColor: const Color(0xFF61AFEF));
          break;
        case 45: // Magenta background
          style = style.copyWith(backgroundColor: const Color(0xFFC678DD));
          break;
        case 46: // Cyan background
          style = style.copyWith(backgroundColor: const Color(0xFF56B6C2));
          break;
        case 47: // White background
          style = style.copyWith(backgroundColor: const Color(0xFFABB2BF));
          break;
      }
    }
    
    return style;
  }
  
  void _scrollUp() {
    // In a real implementation, this would scroll the buffer up
    // For now, we'll just clear the screen
    _renderer.clear();
  }
  
  Future<String> _handleAiQuery(String query) async {
    if (widget.onSummarize != null) {
      return await widget.onSummarize!(query);
    }
    return 'AI query not available';
  }
  
  Future<void> _handleEditCommand(String filePath) async {
    // Handle edit command - would open file editor
    debugPrint('Edit command for: $filePath');
  }
  
  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final metrics = _renderer.getMetrics();
        setState(() {
          _averageFrameTime = metrics['lastFrameTime'] ?? 0.0;
          if (_averageFrameTime > 16.67) { // Below 60fps
            _droppedFrames++;
          }
        });
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Reduce performance when backgrounded
        _gpuRenderer.setGpuAcceleration(false);
        break;
      case AppLifecycleState.resumed:
        // Restore performance when active
        _gpuRenderer.setGpuAcceleration(true);
        break;
      default:
        break;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        color: PkmTheme.terminalBg,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _handleKeyEvent,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                  () => _handleCtrlC(),
              const SingleActivator(
                LogicalKeyboardKey.keyC,
                control: true,
                shift: true,
              ): () => _clipboard.sendSigInt(),
              const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                  () => _handlePaste(),
              const SingleActivator(
                LogicalKeyboardKey.keyV,
                control: true,
                shift: true,
              ): () => _clipboard.pasteBracketed(),
            },
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              onSecondaryTapUp: (details) => _showContextMenu(
                context, 
                details.globalPosition,
              ),
              child: CustomPaint(
                painter: _renderer,
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final keyEvent = event;
      
      // Handle special keys
      switch (keyEvent.logicalKey.keyLabel) {
        case 'Backspace':
          _sendInput('\x7f'); // DEL
          return KeyEventResult.handled;
        case 'Enter':
          _sendInput('\r');
          return KeyEventResult.handled;
        case 'Tab':
          _sendInput('\t');
          return KeyEventResult.handled;
        case 'Escape':
          _sendInput('\x1b');
          return KeyEventResult.handled;
        case 'Arrow Up':
          _sendInput('\x1b[A');
          return KeyEventResult.handled;
        case 'Arrow Down':
          _sendInput('\x1b[B');
          return KeyEventResult.handled;
        case 'Arrow Right':
          _sendInput('\x1b[C');
          return KeyEventResult.handled;
        case 'Arrow Left':
          _sendInput('\x1b[D');
          return KeyEventResult.handled;
        case 'Home':
          _sendInput('\x1b[H');
          return KeyEventResult.handled;
        case 'End':
          _sendInput('\x1b[F');
          return KeyEventResult.handled;
        case 'Page Up':
          _sendInput('\x1b[5~');
          return KeyEventResult.handled;
        case 'Page Down':
          _sendInput('\x1b[6~');
          return KeyEventResult.handled;
        case 'Delete':
          _sendInput('\x1b[3~');
          return KeyEventResult.handled;
        case 'F1':
          _sendInput('\x1bOP');
          return KeyEventResult.handled;
        case 'F2':
          _sendInput('\x1bOQ');
          return KeyEventResult.handled;
        case 'F3':
          _sendInput('\x1bOR');
          return KeyEventResult.handled;
        case 'F4':
          _sendInput('\x1bOS');
          return KeyEventResult.handled;
        case 'F5':
          _sendInput('\x1b[15~');
          return KeyEventResult.handled;
        case 'F6':
          _sendInput('\x1b[17~');
          return KeyEventResult.handled;
        case 'F7':
          _sendInput('\x1b[18~');
          return KeyEventResult.handled;
        case 'F8':
          _sendInput('\x1b[19~');
          return KeyEventResult.handled;
        case 'F9':
          _sendInput('\x1b[20~');
          return KeyEventResult.handled;
        case 'F10':
          _sendInput('\x1b[21~');
          return KeyEventResult.handled;
        case 'F11':
          _sendInput('\x1b[23~');
          return KeyEventResult.handled;
        case 'F12':
          _sendInput('\x1b[24~');
          return KeyEventResult.handled;
      }
      
      // Handle printable characters
      if (keyEvent.character != null && keyEvent.character!.isNotEmpty) {
        _sendInput(keyEvent.character!);
        return KeyEventResult.handled;
      }
    }
    
    return KeyEventResult.ignored;
  }
  
  void _sendInput(String input) {
    widget.session.writeInput(input);
  }
  
  Future<void> _handleCtrlC() async {
    if (_clipboard.hasSelection) {
      await _clipboard.copy();
    } else {
      _clipboard.sendSigInt();
    }
  }
  
  Future<void> _handlePaste() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      _sendInput(clipboardData!.text!);
    }
  }
  
  void _showContextMenu(BuildContext context, Offset position) {
    final hasSel = _clipboard.hasSelection;
    final items = <PopupMenuEntry<void>>[];
    
    if (hasSel) {
      items.add(
        _menuItem(
          label: 'copy',
          onTap: () async => _clipboard.copy(),
        ),
      );
      items.add(
        _menuItem(
          label: 'copy all',
          onTap: () async => _clipboard.copyAll(),
        ),
      );
      if (widget.onSummarize != null) {
        items.add(
          _menuItem(
            label: 'copy as summary',
            onTap: () async => _runSummarize(),
          ),
        );
      }
      items.add(const PopupMenuDivider());
    }
    
    items.add(
      _menuItem(
        label: 'paste',
        onTap: () async => _handlePaste(),
      ),
    );
    
    items.add(const PopupMenuDivider());
    items.add(
      _menuItem(
        label: 'new tab',
        onTap: () => widget.onNewTab?.call(),
      ),
    );
    items.add(
      _menuItem(
        label: 'new window',
        onTap: () => widget.onNewWindow?.call(),
      ),
    );
    
    if (hasSel) {
      items.add(const PopupMenuDivider());
      items.add(
        _menuItem(
          label: 'close tab',
          onTap: () => widget.onCloseTab?.call(),
        ),
      );
    }
    
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: PkmTheme.popup,
      items: items,
    );
  }
  
  PopupMenuItem<void> _menuItem({
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return PopupMenuItem<void>(
      onTap: onTap,
      enabled: enabled,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? PkmTheme.text : PkmTheme.secondary,
          fontFamily: PkmTheme.fontUi,
          fontSize: 13,
        ),
      ),
    );
  }
  
  Future<void> _runSummarize() async {
    if (widget.onSummarize != null) {
      final text = _clipboard.selectedText;
      if (text.isNotEmpty) {
        final summary = await widget.onSummarize!(text);
        if (summary.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: summary));
          _sendInput('\r\n\x1b[36m[summary copied to clipboard]\x1b[0m\r\n');
        }
      }
    }
  }
  
  void resize(int cols, int rows) {
    if (cols != _columns || rows != _rows) {
      _columns = cols;
      _rows = rows;
      
      // Recreate renderer with new dimensions
      _renderer.dispose();
      _renderer = HighPerformanceTerminalRenderer(
        columns: _columns,
        rows: _rows,
        gpuRenderer: _gpuRenderer,
      );
      
      // Mark for full redraw
      _renderer.markFullRedraw();
      
      if (mounted) setState(() {});
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _performanceTimer?.cancel();
    _renderer.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
