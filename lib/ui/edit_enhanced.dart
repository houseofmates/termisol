import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as path;
import '../config/pkm_theme.dart';
import '../core/mouse_protocol_manager.dart';

/// Enhanced text editor with mouse protocol support for interactive editing.
/// Enables clicking links, selecting text, and better UX in terminal.
class EditEnhanced extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final bool readOnly;

  const EditEnhanced({
    super.key,
    required this.filePath,
    required this.initialContent,
    this.readOnly = false,
  });

  @override
  State<EditEnhanced> createState() => _EditEnhancedState();
}

class _EditEnhancedState extends State<EditEnhanced> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;
  late final MouseProtocolManager _mouseProtocol;
  
  bool _showLineNumbers = true;
  bool _showMiniMap = false;
  bool _showAIChat = false;
  String _fontFamily = 'Fira Code';
  double _fontSize = 14.0;
  bool _italicMode = false;
  bool _syntaxHighlighting = true;
  String _theme = 'atom-one-dark';
  Timer? _autoSaveTimer;
  bool _hasUnsavedChanges = false;
  
  // Mouse selection state
  TextSelection? _currentSelection;
  List<Rect> _linkRects = [];
  bool _mouseSelectionEnabled = true;

  @override
  void initState() {
    super.initState();
    
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    
    // Initialize mouse protocol for the editor
    _mouseProtocol = MouseProtocolManager(
      // Mock terminal for mouse protocol
      MockTerminal(),
      MockTerminalController(),
    );
    _mouseProtocol.enable(MouseProtocolManager.MouseMode.highlight);
    
    // Start auto-save
    _startAutoSave();
    
    // Load file content
    _loadFileContent();
  }

  /// Mock terminal for mouse protocol integration.
  class MockTerminal {
    void write(String data) => debugPrint('Mock terminal: $data');
    void Function(String)? get onFocus => null;
    set Function(String)? onFocus => debugPrint('Mock focus set');
  }

  /// Mock terminal controller for mouse protocol integration.
  class MockTerminalController {
    void paste(String text) => debugPrint('Mock paste: $text');
    TextSelection? get selection => null;
    set TextSelection?(selection) => debugPrint('Mock selection set');
  }

  Future<void> _loadFileContent() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        _controller.text = content;
        debugPrint('📂 Loaded file: ${widget.filePath}');
      }
    } catch (e) {
      debugPrint('❌ Failed to load file: $e');
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasUnsavedChanges) {
        _saveFile();
      }
    });
  }

  Future<void> _saveFile() async {
    try {
      final file = File(widget.filePath);
      await file.writeAsString(_controller.text);
      _hasUnsavedChanges = false;
      debugPrint('💾 Auto-saved: ${widget.filePath}');
    } catch (e) {
      debugPrint('❌ Failed to save file: $e');
    }
  }

  void _onTextChanged() {
    if (!widget.readOnly) {
      _hasUnsavedChanges = true;
      _detectLinks();
      _updateMouseSelection();
    }
  }

  /// Detect clickable links in the editor content.
  void _detectLinks() {
    _linkRects.clear();
    
    final urlRegex = RegExp(r'https?://[^\s<>\"\'`\)\]\}]+');
    final matches = urlRegex.allMatches(_controller.text);
    
    for (final match in matches) {
      // This would calculate actual text positions
      // For now, just track that we found links
      debugPrint('🔗 Detected link: ${match.group(0)}');
    }
  }

  /// Update mouse selection based on current text.
  void _updateMouseSelection() {
    if (!_mouseSelectionEnabled) return;
    
    // This would integrate with actual rendering
    // For now, just track selection state
    _currentSelection = _controller.selection;
  }

  /// Handle mouse events from protocol.
  void _handleMouseEvent(String event) {
    _mouseProtocol.handleMouseEvent(event);
  }

  /// Handle mouse selection for text.
  void _handleMouseSelection(Offset localPosition, {
    TextSelection? selection,
    bool isWordSelection = false,
  }) {
    if (!_mouseSelectionEnabled) return;
    
    setState(() {
      _currentSelection = selection;
      
      if (selection != null && !selection!.isCollapsed) {
        // User selected text
        debugPrint('🖱️ Selected: ${selection!.text}');
      }
    });
  }

  /// Copy selected text to clipboard.
  Future<void> _copySelection() async {
    try {
      final selection = _controller.selection;
      if (selection != null && !selection!.isCollapsed) {
        await Clipboard.setData(ClipboardData(text: selection!.text));
        debugPrint('📋 Copied: ${selection!.text}');
      }
    } catch (e) {
      debugPrint('❌ Failed to copy: $e');
    }
  }

  /// Paste from clipboard.
  Future<void> _paste() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final text = clipboardData!.text!;
        final selection = _controller.selection;
        
        if (selection != null) {
          _controller.text = text;
        } else {
          final before = _controller.text.substring(0, selection.start);
          final after = _controller.text.substring(selection.end);
          _controller.text = before + text + after;
        }
        
        debugPrint('📋 Pasted: $text');
      }
    } catch (e) {
      debugPrint('❌ Failed to paste: $e');
    }
  }

  /// Select all text.
  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  /// Get syntax highlighting for current language.
  Map<String, TextStyle> _getSyntaxHighlighting(String content) {
    if (!_syntaxHighlighting) return {};
    
    final extension = path.extension(widget.filePath).toLowerCase();
    final language = _getLanguageFromExtension(extension);
    
    if (language != null) {
      final theme = _theme == 'atom-one-dark' ? atomOneDarkTheme : githubTheme;
      return flutterHighlight(
        content,
        language: language!,
        theme: theme,
      );
    }
    
    return {};
  }

  /// Get highlight language from file extension.
  String? _getLanguageFromExtension(String extension) {
    final languageMap = {
      'dart': 'dart',
      'py': 'python',
      'js': 'javascript',
      'ts': 'typescript',
      'jsx': 'jsx',
      'tsx': 'tsx',
      'json': 'json',
      'yaml': 'yaml',
      'yml': 'yaml',
      'md': 'markdown',
      'html': 'html',
      'css': 'css',
      'sh': 'bash',
      'bash': 'bash',
      'zsh': 'bash',
      'sql': 'sql',
      'go': 'go',
      'rs': 'rust',
      'cpp': 'cpp',
      'c': 'c',
      'h': 'c',
      'hpp': 'cpp',
      'java': 'java',
      'kt': 'kotlin',
      'swift': 'swift',
      'php': 'php',
      'rb': 'ruby',
      'lua': 'lua',
      'r': 'r',
      'toml': 'toml',
      'xml': 'xml',
    };
    
    return languageMap[extension];
  }

  @override
  Widget build(BuildContext context) {
    final highlightedContent = _getSyntaxHighlighting(_controller.text);
    
    return Scaffold(
      backgroundColor: PkmTheme.background,
      appBar: AppBar(
        backgroundColor: PkmTheme.terminalBg,
        title: Text(
          path.basename(widget.filePath),
          style: const TextStyle(
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _saveFile,
            icon: const Icon(Icons.save, color: PkmTheme.primary),
            tooltip: 'Save (Ctrl+S)',
          ),
          IconButton(
            onPressed: _copySelection,
            icon: const Icon(Icons.copy, color: PkmTheme.primary),
            tooltip: 'Copy (Ctrl+C)',
          ),
          IconButton(
            onPressed: _paste,
            icon: const Icon(Icons.paste, color: PkmTheme.primary),
            tooltip: 'Paste (Ctrl+V)',
          ),
        ],
      ),
      body: Row(
        children: [
          // Line numbers
          if (_showLineNumbers)
            Container(
              width: 60,
              color: PkmTheme.lineNumberBg,
              child: ListView.builder(
                itemCount: _controller.text.split('\n').length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: PkmTheme.lineNumber,
                        fontFamily: _fontFamily,
                        fontSize: _fontSize - 2,
                      ),
                    ),
                  );
                },
              ),
            ),
          
          // Editor area
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: Focus(
                focusNode: _focusNode,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                    fontStyle: _italicMode ? FontStyle.italic : FontStyle.normal,
                    color: PkmTheme.text,
                    height: 1.4,
                  ),
                  maxLines: null,
                  expands: true,
                  onChanged: _onTextChanged,
                  onKey: _handleKeyEvent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle keyboard events with shortcuts.
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+S: Save
      if (HardwareKeyboard.instance.isControlPressed && 
          event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveFile();
        return;
      }
      
      // Ctrl+A: Select all
      if (HardwareKeyboard.instance.isControlPressed && 
          event.logicalKey == LogicalKeyboardKey.keyA) {
        _selectAll();
        return;
      }
      
      // Ctrl+C: Copy
      if (HardwareKeyboard.instance.isControlPressed && 
          event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return;
      }
      
      // Ctrl+V: Paste
      if (HardwareKeyboard.instance.isControlPressed && 
          event.logicalKey == LogicalKeyboardKey.keyV) {
        _paste();
        return;
      }
    }
    
    return null;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _mouseProtocol.dispose();
    super.dispose();
  }
}
