import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';
import '../core/terminal_session.dart';
import '../core/bracketed_paste_manager.dart';
import '../core/focus_manager.dart';
import '../core/truecolor_manager.dart';
import '../core/kitty_graphics_manager.dart';
import '../core/mouse_protocol_manager.dart';
import '../core/ligature_font_manager.dart';
import '../core/throttled_renderer.dart';

/// Enhanced terminal view with all advanced features.
/// Includes bracketed paste, TrueColor, Kitty graphics, mouse protocol,
/// ligature fonts, and throttled rendering.
class TermisolTerminalViewEnhanced extends StatefulWidget {
  final TerminalSession session;
  final FocusNode? focusNode;
  final VoidCallback? onNewTab;
  final VoidCallback? onCloseTab;

  const TermisolTerminalViewEnhanced({
    super.key,
    required this.session,
    this.focusNode,
    this.onNewTab,
    this.onCloseTab,
  });

  @override
  State<TermisolTerminalViewEnhanced> createState() => _TermisolTerminalViewEnhancedState();
}

class _TermisolTerminalViewEnhancedState extends State<TermisolTerminalViewEnhanced> {
  late final ThrottledRenderer _throttledRenderer;
  late final MouseProtocolManager _mouseProtocol;
  late final LigatureFontManager _fontManager;
  bool _contextMenuVisible = false;
  Offset? _lastTapPosition;

  @override
  void initState() {
    super.initState();
    
    // Initialize advanced managers
    _throttledRenderer = ThrottledRenderer(widget.session.terminal);
    _mouseProtocol = MouseProtocolManager(widget.session.terminal, widget.session.controller);
    _fontManager = LigatureFontManager(widget.session.terminal, widget.session.controller);
    
    // Setup advanced features
    _setupAdvancedFeatures();
    
    // Request focus if provided
    widget.focusNode?.requestFocus();
  }

  /// Setup all advanced terminal features.
  void _setupAdvancedFeatures() {
    // Enable mouse protocol for clicking links
    _mouseProtocol.enable(MouseProtocolManager.MouseMode.any);
    
    // Enable ligatures for better code readability
    _fontManager.setFont('Fira Code', enableLigatures: true);
    
    // Enable TrueColor for rich colors
    widget.session.trueColor.enable();
    
    // Enable bracketed paste for security
    widget.session.bracketedPaste.enable();
    
    debugPrint('🚀 Advanced terminal features enabled');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: GestureDetector(
        onTapDown: _handleTap,
        onSecondaryTap: _handleSecondaryTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Focus(
            focusNode: widget.focusNode,
            autofocus: true,
            onKey: _handleKeyEvent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: PkmTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: XtermWidget(
                terminal: widget.session.terminal,
                controller: widget.session.controller,
                style: TerminalStyle(
                  fontFamily: _fontManager.currentFont,
                  fontSize: 14,
                  foreground: Colors.white,
                  background: Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Font toggle
          FloatingActionButton(
            mini: true,
            onPressed: _toggleLigatures,
            backgroundColor: PkmTheme.primary,
            child: Icon(
              _fontManager.ligaturesEnabled ? Icons.text_format : Icons.text_fields,
              color: Colors.white,
              size: 16,
            ),
            tooltip: 'Toggle ligatures',
          ),
          
          // Mouse protocol toggle
          FloatingActionButton(
            mini: true,
            onPressed: _toggleMouseProtocol,
            backgroundColor: PkmTheme.primary,
            child: Icon(
              _mouseProtocol.isEnabled ? Icons.mouse : Icons.mouse_off,
              color: Colors.white,
              size: 16,
            ),
            tooltip: 'Toggle mouse protocol',
          ),
          
          // Context menu
          FloatingActionButton(
            mini: true,
            onPressed: _showContextMenu,
            backgroundColor: PkmTheme.primary,
            child: const Icon(
              Icons.more_vert,
              color: Colors.white,
              size: 16,
            ),
            tooltip: 'Terminal options',
          ),
        ],
      ),
      
      // Context menu overlay
      if (_contextMenuVisible)
        Positioned(
          left: _lastTapPosition?.dx ?? 0,
          top: _lastTapPosition?.dy ?? 0,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: PkmTheme.popup,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy, color: PkmTheme.primary),
                    title: const Text('Copy'),
                    onTap: _copySelection,
                  ),
                  ListTile(
                    leading: const Icon(Icons.paste, color: PkmTheme.primary),
                    title: const Text('Paste'),
                    onTap: _paste,
                  ),
                  ListTile(
                    leading: const Icon(Icons.link, color: PkmTheme.primary),
                    title: const Text('Copy URL'),
                    onTap: _copyLastUrl,
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.text_format,
                      color: _fontManager.ligaturesEnabled ? PkmTheme.primary : PkmTheme.secondary,
                    ),
                    title: Text(_fontManager.ligaturesEnabled ? 'Disable ligatures' : 'Enable ligatures'),
                    onTap: _toggleLigatures,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.mouse,
                      color: _mouseProtocol.isEnabled ? PkmTheme.primary : PkmTheme.secondary,
                    ),
                    title: Text(_mouseProtocol.isEnabled ? 'Disable mouse' : 'Enable mouse'),
                    onTap: _toggleMouseProtocol,
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  /// Handle tap events for context menu.
  void _handleTap(TapUpDetails details) {
    _lastTapPosition = details.globalPosition;
  }

  /// Handle secondary tap for context menu.
  void _handleSecondaryTap(TapUpDetails details) {
    _lastTapPosition = details.globalPosition;
    setState(() {
      _contextMenuVisible = true;
    });
  }

  /// Handle keyboard events with shortcuts.
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+Shift+P: Command palette
      if (HardwareKeyboard.instance.isControlPressed && 
          HardwareKeyboard.instance.isShiftPressed && 
          event.logicalKey == LogicalKeyboardKey.keyP) {
        // This would be handled by parent
        return;
      }
      
      // Ctrl+Shift+C: Copy
      if (HardwareKeyboard.instance.isControlPressed && 
          HardwareKeyboard.instance.isShiftPressed && 
          event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return;
      }
      
      // Ctrl+Shift+V: Paste with bracketed mode
      if (HardwareKeyboard.instance.isControlPressed && 
          HardwareKeyboard.instance.isShiftPressed && 
          event.logicalKey == LogicalKeyboardKey.keyV) {
        _paste();
        return;
      }
      
      // Ctrl+Shift+F: Toggle mouse
      if (HardwareKeyboard.instance.isControlPressed && 
          HardwareKeyboard.instance.isShiftPressed && 
          event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleMouseProtocol();
        return;
      }
    }
    
    // Pass other keys to terminal
    return null;
  }

  /// Copy selected text to clipboard.
  Future<void> _copySelection() async {
    try {
      final selection = widget.session.terminal.selection;
      if (selection != null) {
        await Clipboard.setData(ClipboardData(text: selection!.text));
        debugPrint('📋 Copied: ${selection!.text}');
      }
    } catch (e) {
      debugPrint('❌ Failed to copy: $e');
    }
  }

  /// Paste from clipboard with bracketed mode.
  Future<void> _paste() async {
    try {
      await widget.session.bracketedPaste.handlePaste();
      debugPrint('📋 Pasted with bracketed mode');
    } catch (e) {
      debugPrint('❌ Failed to paste: $e');
    }
  }

  /// Copy last detected URL.
  Future<void> _copyLastUrl() async {
    try {
      if (widget.session.detectedUrls.isNotEmpty) {
        final url = widget.session.detectedUrls.last.url;
        await Clipboard.setData(ClipboardData(text: url));
        debugPrint('🔗 Copied URL: $url');
      }
    } catch (e) {
      debugPrint('❌ Failed to copy URL: $e');
    }
  }

  /// Toggle ligature support.
  Future<void> _toggleLigatures() async {
    await _fontManager.toggleLigatures();
    setState(() {});
  }

  /// Toggle mouse protocol.
  void _toggleMouseProtocol() {
    if (_mouseProtocol.isEnabled) {
      _mouseProtocol.disable();
    } else {
      _mouseProtocol.enable(MouseProtocolManager.MouseMode.any);
    }
    setState(() {});
  }

  /// Show context menu.
  void _showContextMenu() {
    setState(() {
      _contextMenuVisible = true;
    });
  }

  /// Hide context menu.
  void _hideContextMenu() {
    setState(() {
      _contextMenuVisible = false;
    });
  }

  @override
  void dispose() {
    _throttledRenderer.dispose();
    _mouseProtocol.dispose();
    _fontManager.dispose();
    super.dispose();
  }
}
