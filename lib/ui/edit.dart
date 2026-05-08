import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as path;

/// Edit - A modern terminal text editor with WYSIWYG markdown, rainbow syntax highlighting,
/// and Windows Notepad-style hotkeys
class EditTerminal extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final Function(String)? onSave;
  final VoidCallback? onClose;
  final bool readOnly;

  const EditTerminal({
    super.key,
    required this.filePath,
    required this.initialContent,
    this.onSave,
    this.onClose,
    this.readOnly = false,
  });

  @override
  State<EditTerminal> createState() => _EditTerminalState();
}

class _EditTerminalState extends State<EditTerminal> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  late FocusNode _focusNode;
  
  // Editor settings
  bool _showLineNumbers = true;
  bool _wordWrap = true;
  double _fontSize = 14.0;
  final String _fontFamily = 'JetBrains Mono';
  String _currentTheme = 'rainbow';
  bool _showSettings = false;
  bool _rainbowSyntax = true;
  bool _showHotkeySettings = false;
  bool _italicMode = false;
  bool _showAIChat = false;
  
  // AI Chat
  final TextEditingController _aiChatController = TextEditingController();
  final List<Map<String, String>> _aiChatMessages = [];
  String _selectedModel = 'kimi-k2.6'; // Default to Kimi K2.6
  
  // Hotkey configuration
  final Map<String, String> _defaultHotkeys = {
    'save': 'Ctrl+Shift+S',
    'open': 'Ctrl+O',
    'new': 'Ctrl+N',
    'quit': 'Ctrl+W',
    'undo': 'Ctrl+Z',
    'redo': 'Ctrl+Y',
    'copy': 'Ctrl+C',
    'paste': 'Ctrl+V',
    'cut': 'Ctrl+X',
    'select_all': 'Ctrl+A',
    'find': 'Ctrl+F',
    'replace': 'Ctrl+H',
    'go_to_line': 'Ctrl+G',
    'italic': 'Ctrl+I',
    'settings': 'Ctrl+P',
    'ai_chat': '/ai + Tab',
  };
  
  final Map<String, String> _currentHotkeys = {};
  
  // Undo/Redo system - optimize memory usage
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentUndoIndex = -1;
  Timer? _undoTimer;
  static const int _maxUndoStackSize = 100; // Limit stack size
  
  // Mouse cursor support
  bool _mouseEnabled = true;
  
  // Multi-cursor support - optimize performance
  final List<TextSelection> _cursors = [];
  bool _multiCursorMode = false;
  static const int _maxCursors = 50; // Limit cursors for performance
  bool _isAIEnabled = false; // Add AI enable/disable flag
  
  // Search
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  int _currentSearchIndex = 0;
  List<int> _searchMatches = [];
  
  // Auto-save
  bool _hasUnsavedChanges = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    
    // Initialize undo stack
    _undoStack.add(widget.initialContent);
    _currentUndoIndex = 0;
    
    // Initialize hotkeys
    _currentHotkeys.addAll(_defaultHotkeys);
    
    // Check if AI is enabled via environment variable
    _isAIEnabled = Platform.environment['TERMISOL_AI_ENABLED'] == 'true';
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _undoTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _aiChatController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!widget.readOnly) {
      setState(() {
        _hasUnsavedChanges = true;
      });
      
      // Add to undo stack with debouncing
      _undoTimer?.cancel();
      _undoTimer = Timer(const Duration(milliseconds: 500), () {
        _addToUndoStack(_controller.text);
      });
      
      // Auto-save with debounce
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 2), () {
        _saveContent();
      });
    }
  }

  void _onFocusChanged() {
    // Handle focus changes if needed
  }

  void _addToUndoStack(String content) {
    // Remove any items after current index
    if (_currentUndoIndex < _undoStack.length - 1) {
      _undoStack.removeRange(_currentUndoIndex + 1, _undoStack.length);
    }
    
    // Add new content if different from last
    if (_undoStack.isEmpty || _undoStack.last != content) {
      _undoStack.add(content);
      _currentUndoIndex = _undoStack.length - 1;
      
      // Limit stack size for performance
      if (_undoStack.length > _maxUndoStackSize) {
        _undoStack.removeAt(0);
        _currentUndoIndex--;
      }
      
      // Clear redo stack
      _redoStack.clear();
    }
  }

  void _undo() {
    if (_canUndo()) {
      _redoStack.add(_controller.text);
      _currentUndoIndex--;
      _controller.text = _undoStack[_currentUndoIndex];
      
      // Restore cursor position if possible
      _restoreCursorPosition();
      
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  void _redo() {
    if (_canRedo()) {
      _undoStack[_currentUndoIndex] = _controller.text;
      _controller.text = _redoStack.removeLast();
      _currentUndoIndex++;
      
      // Restore cursor position if possible
      _restoreCursorPosition();
      
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  bool _canUndo() {
    return _currentUndoIndex > 0;
  }

  bool _canRedo() {
    return _redoStack.isNotEmpty || _currentUndoIndex < _undoStack.length - 1;
  }

  void _restoreCursorPosition() {
    // Simple cursor restoration - place at end of text
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _undoStack.add(_controller.text);
    _currentUndoIndex = 0;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History cleared')),
    );
  }

  void _clearMultiCursors() {
    setState(() {
      _multiCursorMode = false;
      _cursors.clear();
    });
  }

  void _addCursorAtSelection() {
    if (_controller.selection.isCollapsed && !_cursors.contains(_controller.selection)) {
      setState(() {
        _multiCursorMode = true;
        _cursors.add(_controller.selection);
      });
    }
  }

  void _removeCursorAt(TextSelection selection) {
    setState(() {
      _cursors.remove(selection);
      if (_cursors.isEmpty) {
        _multiCursorMode = false;
      }
    });
  }

  void _handleMultiCursorInput(String input) {
    if (!_multiCursorMode || _cursors.isEmpty) return;
    
    final text = _controller.text;
    final allCursors = List<TextSelection>.from(_cursors);
    allCursors.add(_controller.selection);
    
    // Sort cursors by position to handle offset changes correctly
    allCursors.sort((a, b) => a.baseOffset.compareTo(b.baseOffset));
    
    String newText = text;
    int offsetAdjustment = 0;
    
    for (final cursor in allCursors) {
      final adjustedOffset = cursor.baseOffset + offsetAdjustment;
      if (adjustedOffset >= 0 && adjustedOffset <= newText.length) {
        newText = newText.substring(0, adjustedOffset) + input + newText.substring(adjustedOffset);
        offsetAdjustment += input.length;
      }
    }
    
    _controller.text = newText;
    
    // Update all cursor positions
    setState(() {
      _cursors.clear();
      for (final cursor in allCursors) {
        final newOffset = cursor.baseOffset + input.length;
        _cursors.add(TextSelection.fromPosition(TextPosition(offset: newOffset)));
      }
      
      // Update main cursor
      final mainCursorOffset = _controller.selection.baseOffset + input.length;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: mainCursorOffset));
    });
    
    _onTextChanged();
  }

  void _handleMultiCursorSelection(TextSelection selection) {
    if (!_multiCursorMode || _cursors.isEmpty) return;
    
    // Apply selection to all cursors
    final text = _controller.text;
    final selectedText = selection.textInside(text);
    
    if (selectedText.isNotEmpty) {
      final allCursors = List<TextSelection>.from(_cursors);
      allCursors.add(_controller.selection);
      
      // Sort cursors by position (reverse for deletion)
      allCursors.sort((a, b) => b.baseOffset.compareTo(a.baseOffset));
      
      String newText = text;
      
      for (final cursor in allCursors) {
        if (cursor.baseOffset >= 0 && cursor.baseOffset <= newText.length) {
          newText = newText.substring(0, cursor.baseOffset) + selectedText + newText.substring(cursor.baseOffset);
        }
      }
      
      _controller.text = newText;
      
      // Update all cursor positions
      setState(() {
        _cursors.clear();
        for (final cursor in allCursors) {
          final newOffset = cursor.baseOffset + selectedText.length;
          _cursors.add(TextSelection.fromPosition(TextPosition(offset: newOffset)));
        }
        
        // Update main cursor
        final mainCursorOffset = _controller.selection.baseOffset + selectedText.length;
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: mainCursorOffset));
      });
      
      _onTextChanged();
    }
  }

  void _handleMultiCursorDeletion() {
    if (!_multiCursorMode || _cursors.isEmpty) return;
    
    final text = _controller.text;
    final allCursors = List<TextSelection>.from(_cursors);
    allCursors.add(_controller.selection);
    
    // Sort cursors by position (reverse for deletion)
    allCursors.sort((a, b) => b.baseOffset.compareTo(a.baseOffset));
    
    String newText = text;
    
    for (final cursor in allCursors) {
      if (cursor.baseOffset > 0 && cursor.baseOffset <= newText.length) {
        newText = newText.substring(0, cursor.baseOffset - 1) + newText.substring(cursor.baseOffset);
      }
    }
    
    _controller.text = newText;
    
    // Update all cursor positions
    setState(() {
      _cursors.clear();
      for (final cursor in allCursors) {
        final newOffset = cursor.baseOffset - 1;
        if (newOffset >= 0) {
          _cursors.add(TextSelection.fromPosition(TextPosition(offset: newOffset)));
        }
      }
      
      // Update main cursor
      final mainCursorOffset = _controller.selection.baseOffset - 1;
      if (mainCursorOffset >= 0) {
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: mainCursorOffset));
      }
    });
    
    _onTextChanged();
  }

  void _selectAllOccurrences() {
    final text = _controller.text;
    if (_controller.selection.isCollapsed || _controller.selection.textInside(text).isEmpty) return;
    
    final selectedText = _controller.selection.textInside(text);
    final matches = <int>[];
    int index = text.indexOf(selectedText);
    
    while (index != -1) {
      matches.add(index);
      index = text.indexOf(selectedText, index + 1);
    }
    
    setState(() {
      _multiCursorMode = true;
      _cursors.clear();
      for (final match in matches) {
        _cursors.add(TextSelection(
          baseOffset: match,
          extentOffset: match + selectedText.length,
        ));
      }
    });
  }

  String _getUndoDescription() {
    if (!_canUndo()) return 'No undo available';
    if (_currentUndoIndex > 0) {
      return 'Undo: ${_getActionDescription(_undoStack[_currentUndoIndex])}';
    }
    return 'Undo available';
  }

  String _getRedoDescription() {
    if (!_canRedo()) return 'No redo available';
    if (_redoStack.isNotEmpty) {
      return 'Redo: ${_getActionDescription(_redoStack.last)}';
    }
    return 'Redo available';
  }

  String _getActionDescription(String content) {
    // Simple action description based on content changes
    if (content.length > _controller.text.length + 10) {
      return 'Text deletion';
    } else if (content.length < _controller.text.length - 10) {
      return 'Text insertion';
    } else {
      return 'Text modification';
    }
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit History'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: _undoStack.length,
            itemBuilder: (context, index) {
              final isCurrent = index == _currentUndoIndex;
              final canUndo = index < _currentUndoIndex;
              final canRedo = index > _currentUndoIndex;
              
              return ListTile(
                title: Text(
                  'State ${index + 1}',
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? Colors.blue : Colors.grey[300],
                  ),
                ),
                subtitle: Text(
                  _getActionDescription(_undoStack[index]),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canUndo)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 16),
                        onPressed: () {
                          Navigator.of(context).pop();
                          while (_currentUndoIndex > index) {
                            _undo();
                          }
                        },
                      ),
                    if (canRedo)
                      IconButton(
                        icon: const Icon(Icons.redo, size: 16),
                        onPressed: () {
                          Navigator.of(context).pop();
                          while (_currentUndoIndex < index) {
                            _redo();
                          }
                        },
                      ),
                    if (isCurrent)
                      const Icon(Icons.check, color: Colors.green, size: 16),
                  ],
                ),
                tileColor: isCurrent ? Colors.blue.withValues(alpha: 0.1) : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _clearHistory();
              Navigator.of(context).pop();
            },
            child: const Text('Clear History'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveContent() async {
    try {
      if (widget.onSave != null) {
        await widget.onSave!(_controller.text);
        setState(() {
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to save content: $e');
    }
  }

  String _detectLanguage() {
    final extension = path.extension(widget.filePath).toLowerCase();
    
    switch (extension) {
      case '.dart': return 'dart';
      case '.py': return 'python';
      case '.js': return 'javascript';
      case '.ts': return 'typescript';
      case '.json': return 'json';
      case '.yaml':
      case '.yml': return 'yaml';
      case '.sh': return 'shell';
      case '.bash': return 'bash';
      case '.zsh': return 'zsh';
      case '.fish': return 'fish';
      case '.html':
      case '.htm': return 'html';
      case '.css': return 'css';
      case '.xml': return 'xml';
      case '.sql': return 'sql';
      case '.go': return 'go';
      case '.rs': return 'rust';
      case '.java': return 'java';
      case '.cpp':
      case '.cxx':
      case '.cc': return 'cpp';
      case '.c': return 'cpp';
      case '.cs': return 'csharp';
      case '.php': return 'php';
      case '.rb': return 'ruby';
      case '.swift': return 'swift';
      case '.kt':
      case '.kts': return 'kotlin';
      case 'Dockerfile': return 'dockerfile';
      case '.md':
      case '.markdown': return 'markdown';
      default: return 'plaintext';
    }
  }

  Map<String, dynamic> _getLanguageConfig() {
    final language = _detectLanguage();
    
    return {
      'lang': language,
      'name': language.toUpperCase(),
    };
  }

  Map<String, dynamic> _getThemeData() {
    switch (_currentTheme) {
      case 'monokai-sublime':
        return {'theme': monokaiSublimeTheme, 'name': 'Monokai Sublime'};
      case 'vs2015':
        return {'theme': vs2015Theme, 'name': 'VS 2015'};
      case 'atom-one-dark':
        return {'theme': atomOneDarkTheme, 'name': 'Atom One Dark'};
      case 'github':
        return {'theme': githubTheme, 'name': 'GitHub'};
      default:
        return {'theme': githubTheme, 'name': 'GitHub'};
    }
  }

  bool _isMarkdownFile() {
    return _detectLanguage() == 'markdown';
  }

  // Rainbow syntax highlighting colors
  static const Map<String, Color> _rainbowColors = {
    'keyword': Color(0xFFff79c6),      // Pink
    'string': Color(0xFFf1fa8c),      // Yellow
    'number': Color(0xFFbd93f9),      // Purple
    'comment': Color(0xFF6272a4),      // Blue-gray
    'function': Color(0xFF50fa7b),     // Green
    'variable': Color(0xFF8be9fd),    // Cyan
    'operator': Color(0xFFff79c6),    // Pink
    'type': Color(0xFFffb86c),        // Orange
    'constant': Color(0xFFbd93f9),     // Purple
    'error': Color(0xFFff5555),       // Red
    'warning': Color(0xFFf1fa8c),     // Yellow
    'info': Color(0xFF8be9fd),        // Cyan
  };

  // Language-specific keyword sets
  static const Set<String> _dartKeywords = {
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class',
    'const', 'continue', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum',
    'export', 'extends', 'external', 'factory', 'false', 'final', 'finally', 'for',
    'get', 'if', 'implements', 'import', 'in', 'interface', 'is', 'library', 'mixin',
    'new', 'null', 'operator', 'part', 'rethrow', 'return', 'set', 'static', 'super',
    'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'while',
    'with', 'yield'
  };

  static const Set<String> _pythonKeywords = {
    'and', 'as', 'assert', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else',
    'except', 'exec', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
    'lambda', 'not', 'or', 'pass', 'print', 'raise', 'return', 'try', 'while', 'with',
    'yield', 'True', 'False', 'None'
  };

  static const Set<String> _javascriptKeywords = {
    'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default',
    'delete', 'do', 'else', 'export', 'extends', 'finally', 'for', 'function', 'if',
    'import', 'in', 'instanceof', 'let', 'new', 'return', 'super', 'switch', 'this',
    'throw', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield', 'async', 'await'
  };

  static const Set<String> _shellKeywords = {
    'if', 'then', 'else', 'elif', 'fi', 'case', 'esac', 'for', 'select', 'while',
    'until', 'do', 'done', 'function', 'time', 'export', 'local', 'readonly', 'declare',
    'typeset', 'unset', 'alias', 'unalias', 'bg', 'fg', 'jobs', 'kill', 'wait',
    'cd', 'pwd', 'echo', 'printf', 'read', 'shift', 'test', 'true', 'false'
  };

  List<TextSpan> _applyRainbowSyntax(String text) {
    if (!_rainbowSyntax || _isMarkdownFile()) {
      return [TextSpan(text: text, style: _getDefaultTextStyle())];
    }

    final language = _detectLanguage();
    final spans = <TextSpan>[];
    final lines = text.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineSpans = _highlightLine(line, language);
      spans.addAll(lineSpans);
      
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return spans;
  }

  List<TextSpan> _highlightLine(String line, String language) {
    final spans = <TextSpan>[];
    int lastIndex = 0;
    
    // Get keywords for the current language
    Set<String> keywords = _getKeywordsForLanguage(language);
    
    // Highlight keywords
    for (final keyword in keywords) {
      final regex = RegExp('\\b$keyword\\b');
      for (final match in regex.allMatches(line)) {
        // Add text before match
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: line.substring(lastIndex, match.start),
            style: _getDefaultTextStyle(),
          ));
        }
        
        // Add highlighted keyword
        spans.add(TextSpan(
          text: match.group(0)!,
          style: _getDefaultTextStyle().copyWith(
            color: _rainbowColors['keyword'],
            fontWeight: FontWeight.bold,
          ),
        ));
        
        lastIndex = match.end;
      }
    }
    
    // Highlight strings
    final stringRegex = RegExp(r'"[^"]*"|\x27[^\x27]*\x27');
    for (final match in stringRegex.allMatches(line)) {
      if (match.start >= lastIndex) {
        // Add text before match
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: line.substring(lastIndex, match.start),
            style: _getDefaultTextStyle(),
          ));
        }
        
        // Add highlighted string
        spans.add(TextSpan(
          text: match.group(0)!,
          style: _getDefaultTextStyle().copyWith(
            color: _rainbowColors['string'],
          ),
        ));
        
        lastIndex = match.end;
      }
    }
    
    // Highlight numbers
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    for (final match in numberRegex.allMatches(line)) {
      if (match.start >= lastIndex) {
        // Add text before match
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: line.substring(lastIndex, match.start),
            style: _getDefaultTextStyle(),
          ));
        }
        
        // Add highlighted number
        spans.add(TextSpan(
          text: match.group(0)!,
          style: _getDefaultTextStyle().copyWith(
            color: _rainbowColors['number'],
          ),
        ));
        
        lastIndex = match.end;
      }
    }
    
    // Highlight comments
    final commentRegex = RegExp(r'(//.*$|#.*$|/\*.*?\*/)');
    for (final match in commentRegex.allMatches(line)) {
      if (match.start >= lastIndex) {
        // Add text before match
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: line.substring(lastIndex, match.start),
            style: _getDefaultTextStyle(),
          ));
        }
        
        // Add highlighted comment
        spans.add(TextSpan(
          text: match.group(0)!,
          style: _getDefaultTextStyle().copyWith(
            color: _rainbowColors['comment'],
            fontStyle: FontStyle.italic,
          ),
        ));
        
        lastIndex = match.end;
      }
    }
    
    // Add remaining text
    if (lastIndex < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastIndex),
        style: _getDefaultTextStyle(),
      ));
    }
    
    return spans.isEmpty ? [TextSpan(text: line, style: _getDefaultTextStyle())] : spans;
  }

  Set<String> _getKeywordsForLanguage(String language) {
    switch (language) {
      case 'dart':
        return _dartKeywords;
      case 'python':
        return _pythonKeywords;
      case 'javascript':
      case 'typescript':
        return _javascriptKeywords;
      case 'shell':
      case 'bash':
        return _shellKeywords;
      default:
        return <String>{};
    }
  }

  TextStyle _getDefaultTextStyle() {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      height: 1.2,
      color: const Color(0xFFD4D4D4),
    );
  }

  Widget _buildMarkdownRenderer(String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.trim().isEmpty) {
        // Empty line
        widgets.add(SizedBox(height: _fontSize * 0.5));
      } else if (line.startsWith('#')) {
        // Headers
        final level = line.indexOf(' ');
        final headerText = line.substring(level + 1);
        final headerSize = _fontSize * (2.0 - (level * 0.2));
        
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            headerText,
            style: TextStyle(
              fontFamily: _fontFamily,
              fontSize: headerSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        // List items
        final itemText = line.substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFffb110),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  itemText,
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                    color: Colors.grey[300],
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else if (line.startsWith('```')) {
        // Code blocks
        final codeText = line.substring(3);
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2d2d2d),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[600]!),
          ),
          child: Text(
            codeText,
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: _fontSize - 1,
              color: const Color(0xFFf1fa8c),
              height: 1.4,
            ),
          ),
        ));
      } else if (line.startsWith('>')) {
        // Blockquotes
        final quoteText = line.substring(1).trim();
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: const Color(0xFFffb110),
                width: 3,
              ),
            ),
          ),
          child: Text(
            quoteText,
            style: TextStyle(
              fontFamily: _fontFamily,
              fontSize: _fontSize,
              color: Colors.grey[300],
              fontStyle: FontStyle.italic,
              height: 1.2,
            ),
          ),
        ));
      } else {
        // Regular text with inline formatting
        widgets.add(_buildInlineMarkdown(line));
      }
    }
    
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  Widget _buildInlineMarkdown(String line) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*.*?\*\*|__.*?__|_.*?_|\*.*?\*|`.*?`|\[.*?\]\(.*?\))');
    int lastIndex = 0;
    
    for (final match in regex.allMatches(line)) {
      // Add text before match
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: line.substring(lastIndex, match.start),
          style: _getDefaultMarkdownTextStyle(),
        ));
      }
      
      // Handle matched markdown
      final matchedText = match.group(0)!;
      if (matchedText.startsWith('**') || matchedText.startsWith('__')) {
        // Bold text with custom color
        spans.add(TextSpan(
          text: matchedText.replaceAll(RegExp(r'\*\*|__'), ''),
          style: _getDefaultMarkdownTextStyle().copyWith(
            color: const Color(0xFFffb110), // Bold color
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (matchedText.startsWith('*') || matchedText.startsWith('_')) {
        // Italic text with custom color
        spans.add(TextSpan(
          text: matchedText.replaceAll(RegExp(r'\*|_'), ''),
          style: _getDefaultMarkdownTextStyle().copyWith(
            color: const Color(0xFFffdb86), // Italic color
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (matchedText.startsWith('`')) {
        // Inline code
        spans.add(TextSpan(
          text: matchedText.replaceAll('`', ''),
          style: _getDefaultMarkdownTextStyle().copyWith(
            color: Colors.cyan,
            backgroundColor: const Color(0xFF2d2d2d),
            fontFamily: 'Courier New',
          ),
        ));
      } else if (matchedText.startsWith('[') && matchedText.contains('](')) {
        // Links
        final linkRegex = RegExp(r'\[(.*?)\]\((.*?)\)');
        final linkMatch = linkRegex.firstMatch(matchedText);
        if (linkMatch != null) {
          final linkText = linkMatch.group(1)!;
          final linkUrl = linkMatch.group(2)!;
          spans.add(TextSpan(
            text: linkText,
            style: _getDefaultMarkdownTextStyle().copyWith(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ));
        }
      }
      
      lastIndex = match.end;
    }
    
    // Add remaining text
    if (lastIndex < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastIndex),
        style: _getDefaultMarkdownTextStyle(),
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  TextStyle _getDefaultMarkdownTextStyle() {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      height: 1.2,
      color: Colors.grey[300],
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                           HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
      
      final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
                            HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
      
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_multiCursorMode) {
          _clearMultiCursors();
        } else {
          _showExitDialog();
        }
        return;
      }
      
      // Handle multi-cursor shortcuts
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
        _addCursorAtSelection();
        return;
      }
      
      if (isCtrlPressed && isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
        _selectAllOccurrences();
        return;
      }
      
      if (isCtrlPressed) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyZ:
            if (isShiftPressed) {
              _redo();
            } else {
              _undo();
            }
            break;
          case LogicalKeyboardKey.keyY:
            _redo();
            break;
          case LogicalKeyboardKey.keyS:
            if (isShiftPressed) {
              _saveContent();
            }
            break;
          case LogicalKeyboardKey.keyA:
            _controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controller.text.length,
            );
            break;
          case LogicalKeyboardKey.keyF:
            setState(() {
              _showSearch = !_showSearch;
              if (_showSearch) {
                _searchController.clear();
                _searchMatches.clear();
              }
            });
            break;
          case LogicalKeyboardKey.keyP:
            setState(() {
              _showSettings = !_showSettings;
            });
            break;
          case LogicalKeyboardKey.keyC:
            _copySelection();
            break;
          case LogicalKeyboardKey.keyV:
            _pasteFromClipboard();
            break;
          case LogicalKeyboardKey.keyX:
            _cutSelection();
            break;
          case LogicalKeyboardKey.keyN:
            _newFile();
            break;
          case LogicalKeyboardKey.keyO:
            _openFile();
            break;
          case LogicalKeyboardKey.keyW:
            if (widget.onClose != null) {
              widget.onClose!();
            }
            break;
          case LogicalKeyboardKey.keyH:
            _replaceDialog();
            break;
          case LogicalKeyboardKey.keyG:
            _goToLine();
            break;
          case LogicalKeyboardKey.keyI:
            _toggleItalic();
            break;
        }
      }
      
      // Handle multi-cursor typing
      if (event.character != null && event.character!.isNotEmpty && !isCtrlPressed && !event.isMetaPressed) {
        if (_multiCursorMode) {
          _handleMultiCursorInput(event.character!);
          return;
        }
      }
      
      // Handle multi-cursor deletion
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_multiCursorMode) {
          _handleMultiCursorDeletion();
          return;
        }
      }
      
      // Handle tab completion for /ai
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        _handleTabCompletion();
      }
    }
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Exit Editor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose an option:'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _saveContent();
                      if (widget.onClose != null) {
                        widget.onClose!();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Save and Exit'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (widget.onClose != null) {
                        widget.onClose!();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Exit Without Saving'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copySelection() {
    final selectedText = _controller.selection.textInside(_controller.text);
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
    }
  }

  void _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData?.text != null) {
      final textToInsert = clipboardData!.text!;
      final currentSelection = _controller.selection;
      final newText = _controller.text.replaceRange(
        currentSelection.start,
        currentSelection.end,
        textToInsert,
      );
      
      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: currentSelection.start + textToInsert.length),
      );
      
      _onTextChanged();
    }
  }

  void _cutSelection() {
    final selectedText = _controller.selection.textInside(_controller.text);
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
      final currentSelection = _controller.selection;
      final newText = _controller.text.replaceRange(
        currentSelection.start,
        currentSelection.end,
        '',
      );
      
      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: currentSelection.start),
      );
      
      _onTextChanged();
    }
  }

  void _newFile() {
    if (_hasUnsavedChanges) {
      _showSaveDialog(() {
        _controller.text = '';
        _controller.selection = const TextSelection.collapsed(offset: 0);
        _onTextChanged();
      });
    } else {
      _controller.text = '';
      _controller.selection = const TextSelection.collapsed(offset: 0);
      _onTextChanged();
    }
  }

  void _openFile() {
    // This would integrate with a file picker
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open file dialog would appear here')),
    );
  }

  void _replaceDialog() {
    // Show find and replace dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find and Replace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Find:'),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Replace with:'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  void _goToLine() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to Line'),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Line number:'),
          onSubmitted: (value) {
            final lineNumber = int.tryParse(value);
            if (lineNumber != null && lineNumber > 0) {
              _navigateToLine(lineNumber);
            }
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  void _navigateToLine(int lineNumber) {
    final lines = _controller.text.split('\n');
    if (lineNumber <= lines.length) {
      final targetOffset = lines.take(lineNumber - 1).fold(0, (sum, line) => sum + line.length + 1);
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: targetOffset.clamp(0, _controller.text.length)),
      );
    }
  }

  void _showSaveDialog(VoidCallback onContinue) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Changes?'),
        content: const Text('Do you want to save your changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Don\'t Save'),
          ),
          TextButton(
            onPressed: () {
              _saveContent();
              Navigator.of(context).pop();
              onContinue();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _prettyPrintCode() {
    final language = _detectLanguage();
    String formattedText = '';
    
    try {
      switch (language) {
        case 'json':
          formattedText = _formatJson(_controller.text);
          break;
        case 'dart':
          formattedText = _formatDart(_controller.text);
          break;
        case 'python':
          formattedText = _formatPython(_controller.text);
          break;
        case 'javascript':
        case 'typescript':
          formattedText = _formatJavaScript(_controller.text);
          break;
        default:
          formattedText = _formatGeneric(_controller.text);
      }
      
      if (formattedText.isNotEmpty && formattedText != _controller.text) {
        _controller.text = formattedText;
        _controller.selection = const TextSelection.collapsed(offset: 0);
        _onTextChanged();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code formatted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No formatting needed or unsupported format')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Formatting error: $e')),
      );
    }
  }

  String _formatJson(String jsonText) {
    try {
      final dynamic jsonData = json.decode(jsonText);
      return const JsonEncoder.withIndent('  ').convert(jsonData);
    } catch (e) {
      return jsonText;
    }
  }

  String _formatDart(String dartCode) {
    // Basic Dart formatting - simple indentation
    final lines = dartCode.split('\n');
    final formattedLines = <String>[];
    int indentLevel = 0;
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.isEmpty) {
        formattedLines.add('');
        continue;
      }
      
      // Decrease indent for closing braces
      if (trimmedLine.startsWith('}') || trimmedLine.startsWith(']') || trimmedLine.startsWith(')')) {
        indentLevel = (indentLevel - 1).clamp(0, 10);
      }
      
      // Add current indentation
      final indentation = '  ' * indentLevel;
      formattedLines.add('$indentation$trimmedLine');
      
      // Increase indent for opening braces
      if (trimmedLine.endsWith('{') || trimmedLine.endsWith('[') || trimmedLine.endsWith('(')) {
        indentLevel++;
      }
    }
    
    return formattedLines.join('\n');
  }

  String _formatPython(String pythonCode) {
    // Basic Python formatting - ensure 4-space indentation
    final lines = pythonCode.split('\n');
    final formattedLines = <String>[];
    int indentLevel = 0;
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.isEmpty) {
        formattedLines.add('');
        continue;
      }
      
      // Decrease indent for dedent keywords
      if (trimmedLine.startsWith('elif ') || trimmedLine.startsWith('else:') || 
          trimmedLine.startsWith('except') || trimmedLine.startsWith('finally:')) {
        indentLevel = (indentLevel - 1).clamp(0, 10);
      }
      
      // Add current indentation
      final indentation = '    ' * indentLevel;
      formattedLines.add('$indentation$trimmedLine');
      
      // Increase indent for indent keywords
      if (trimmedLine.endsWith(':') && !trimmedLine.startsWith('#')) {
        indentLevel++;
      }
    }
    
    return formattedLines.join('\n');
  }

  String _formatJavaScript(String jsCode) {
    // Basic JavaScript formatting - similar to Dart
    final lines = jsCode.split('\n');
    final formattedLines = <String>[];
    int indentLevel = 0;
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.isEmpty) {
        formattedLines.add('');
        continue;
      }
      
      // Decrease indent for closing braces
      if (trimmedLine.startsWith('}') || trimmedLine.startsWith(']') || trimmedLine.startsWith(')')) {
        indentLevel = (indentLevel - 1).clamp(0, 10);
      }
      
      // Add current indentation
      final indentation = '  ' * indentLevel;
      formattedLines.add('$indentation$trimmedLine');
      
      // Increase indent for opening braces
      if (trimmedLine.endsWith('{') || trimmedLine.endsWith('[') || trimmedLine.endsWith('(')) {
        indentLevel++;
      }
    }
    
    return formattedLines.join('\n');
  }

  String _formatGeneric(String text) {
    // Generic formatting - basic cleanup
    final lines = text.split('\n');
    final formattedLines = <String>[];
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        formattedLines.add(trimmedLine);
      }
    }
    
    return formattedLines.join('\n');
  }

  Widget _buildEditorSettings() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingToggle('Line Numbers', _showLineNumbers, (value) {
                setState(() => _showLineNumbers = value);
              }),
              _buildSettingToggle('Word Wrap', _wordWrap, (value) {
                setState(() => _wordWrap = value);
              }),
              _buildSettingToggle('Mouse Support', _mouseEnabled, (value) {
                setState(() => _mouseEnabled = value);
              }),
              _buildSettingToggle('Rainbow Syntax', _rainbowSyntax, (value) {
                setState(() => _rainbowSyntax = value);
              }),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildThemeSelector(),
              _buildFontSizeSelector(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHotkeySettings() {
    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hotkey Configuration',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: _fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            ..._currentHotkeys.entries.map((entry) => 
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        _getHotkeyDisplayName(entry.key),
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 11,
                          fontFamily: _fontFamily,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 11,
                          fontFamily: _fontFamily,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _editHotkey(entry.key),
                      child: Icon(
                        Icons.edit,
                        size: 14,
                        color: Colors.blue[300],
                      ),
                    ),
                  ],
                ),
              ),
            ).toList(),
          ],
        ),
      ),
    );
  }

  String _getHotkeyDisplayName(String key) {
    switch (key) {
      case 'save': return 'Save';
      case 'open': return 'Open';
      case 'new': return 'New';
      case 'quit': return 'Quit';
      case 'undo': return 'Undo';
      case 'redo': return 'Redo';
      case 'copy': return 'Copy';
      case 'paste': return 'Paste';
      case 'cut': return 'Cut';
      case 'select_all': return 'Select All';
      case 'find': return 'Find';
      case 'replace': return 'Replace';
      case 'go_to_line': return 'Go to Line';
      case 'italic': return 'Italic';
      case 'settings': return 'Settings';
      case 'ai_chat': return 'AI Chat';
      default: return key;
    }
  }

  void _editHotkey(String action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Hotkey: ${_getHotkeyDisplayName(action)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current: ${_currentHotkeys[action]}'),
            const SizedBox(height: 8),
            Text('Press new key combination...'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Click here and press keys',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _resetHotkey(action);
              Navigator.of(context).pop();
            },
            child: const Text('Reset to Default'),
          ),
        ],
      ),
    );
  }

  void _resetHotkey(String action) {
    setState(() {
      _currentHotkeys[action] = _defaultHotkeys[action]!;
    });
  }

  void _toggleItalic() {
    final selection = _controller.selection;
    if (selection.isCollapsed) {
      // Toggle italic mode for typing
      setState(() {
        _italicMode = !_italicMode;
      });
    } else {
      // Apply italic to selected text
      final selectedText = selection.textInside(_controller.text);
      final newText = selection.textBefore(_controller.text) + 
                     '*$selectedText*' + 
                     selection.textAfter(_controller.text);
      
      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: selection.baseOffset + 1),
      );
      _onTextChanged();
    }
  }

  void _handleTabCompletion() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final currentLine = text.substring(0, cursorPos).split('\n').last;
    
    if (currentLine.trim() == '/ai') {
      // Replace /ai with empty and open AI chat
      final lineStart = cursorPos - currentLine.length;
      final newText = text.substring(0, lineStart) + text.substring(cursorPos);
      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: lineStart),
      );
      _onTextChanged();
      
      _openAIChat();
    }
  }

  void _openAIChat() {
    setState(() {
      _showAIChat = true;
    });
    
    // Send initial context message
    _sendInitialContext();
  }

  void _sendInitialContext() {
    final context = _buildFileContext();
    setState(() {
      _aiChatMessages.add({
        'role': 'assistant',
        'content': 'I\'m ready to help you with your file! I have access to:\n\n• File: ${path.basename(widget.filePath)}\n• Directory: ${path.dirname(widget.filePath)}\n• File contents (${_controller.text.length} characters)\n\nWhat would you like me to help you with?',
      });
    });
  }

  String _buildFileContext() {
    final fileName = path.basename(widget.filePath);
    final directory = path.dirname(widget.filePath);
    final fileContent = _controller.text;
    
    return '''
FILE CONTEXT:
File: $fileName
Directory: $directory
Content Length: ${fileContent.length} characters

FILE CONTENTS:
$fileContent

DIRECTORY LISTING:
[Directory contents would be listed here]

USER PROMPT:
[Prompt will be added here]

Note: The above file and directory information is provided for context only and is not part of the user's actual prompt.
    ''';
  }

  Future<void> _sendAIMessage(String message) async {
    if (message.trim().isEmpty) return;
    
    // Add user message
    setState(() {
      _aiChatMessages.add({
        'role': 'user',
        'content': message,
      });
    });
    
    // Clear input
    _aiChatController.clear();
    
    // Show typing indicator
    setState(() {
      _aiChatMessages.add({
        'role': 'assistant',
        'content': 'Thinking...',
      });
    });
    
    try {
      // Build full context
      final fullContext = _buildFileContext().replaceFirst(
        '[Prompt will be added here]',
        message,
      );
      
      // Call NVIDIA NIM API
      final response = await _callNVIDIA_NIM(fullContext);
      
      // Remove typing indicator and add response
      setState(() {
        _aiChatMessages.removeLast();
        _aiChatMessages.add({
          'role': 'assistant',
          'content': response,
        });
      });
    } catch (e) {
      // Remove typing indicator and add error
      setState(() {
        _aiChatMessages.removeLast();
        _aiChatMessages.add({
          'role': 'assistant',
          'content': 'Error: $e\n\nPlease check your NVIDIA NIM configuration.',
        });
      });
    }
  }

  Future<String> _callNVIDIA_NIM(String prompt) async {
    // NVIDIA NIM endpoint
    const String nimEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
    
    // Select model based on user choice
    String model;
    switch (_selectedModel) {
      case 'kimi-k2.6':
        model = 'qwen/qwen2.5-72b-instruct';
        break;
      case 'deepseek-v4-flash':
        model = 'deepseek-ai/deepseek-chat';
        break;
      default:
        model = 'qwen/qwen2.5-72b-instruct'; // Fallback
    }
    
    final response = await http.post(
      Uri.parse(nimEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer YOUR_NVIDIA_API_KEY', // This should be configured
      },
      body: json.encode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': 'You are an AI assistant helping with code and file editing. You have access to file context including directory structure and file contents. Please provide helpful, accurate assistance based on provided context.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'max_tokens': 2048,
        'temperature': 0.7,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['choices'][0]['message']['content'] ?? 'No response received.';
    } else {
      throw Exception('NVIDIA NIM API error: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF1e1e1e),
        body: Column(
          children: [
            // Header bar
            Container(
              height: 40,
              color: const Color(0xFF2d2d2d),
              child: Row(
                children: [
                  // File info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(
                            path.basename(widget.filePath),
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontFamily: _fontFamily,
                            ),
                          ),
                          if (_hasUnsavedChanges) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          const Spacer(),
                          // Language indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getLanguageConfig()['name'],
                              style: TextStyle(
                                color: Colors.blue[300],
                                fontSize: 10,
                                fontFamily: _fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Control buttons
                  Row(
                    children: [
                      IconButton(
                        onPressed: _canUndo() ? _undo : null,
                        icon: Icon(Icons.undo, size: 16, color: _canUndo() ? Colors.grey[400] : Colors.grey[700]),
                        tooltip: _getUndoDescription(),
                      ),
                      IconButton(
                        onPressed: _canRedo() ? _redo : null,
                        icon: Icon(Icons.redo, size: 16, color: _canRedo() ? Colors.grey[400] : Colors.grey[700]),
                        tooltip: _getRedoDescription(),
                      ),
                      IconButton(
                        onPressed: _showHistoryDialog,
                        icon: Icon(Icons.history, size: 16, color: Colors.grey[400]),
                        tooltip: 'Show History',
                      ),
                      IconButton(
                        onPressed: _saveContent,
                        icon: Icon(Icons.save, size: 16, color: Colors.grey[400]),
                        tooltip: 'Save (Ctrl+Shift+S)',
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showSearch = !_showSearch),
                        icon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
                        tooltip: 'Find (Ctrl+F)',
                      ),
                      IconButton(
                        onPressed: _prettyPrintCode,
                        icon: Icon(Icons.format_paint, size: 16, color: Colors.grey[400]),
                        tooltip: 'Pretty Print',
                      ),
                      // Multi-cursor status indicator
                      if (_multiCursorMode)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.call_split, size: 14, color: Colors.orange[300]),
                              const SizedBox(width: 4),
                              Text(
                                '${_cursors.length + 1} cursors',
                                style: TextStyle(
                                  color: Colors.orange[300],
                                  fontSize: 10,
                                  fontFamily: _fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      IconButton(
                        onPressed: () => setState(() => _showSettings = !_showSettings),
                        icon: Icon(Icons.settings, size: 16, color: Colors.grey[400]),
                        tooltip: 'Settings (Ctrl+P)',
                      ),
                      if (widget.onClose != null)
                        IconButton(
                          onPressed: widget.onClose,
                          icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                          tooltip: 'Close',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Search bar
            if (_showSearch)
              Container(
                height: 40,
                color: const Color(0xFF252526),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontFamily: _fontFamily,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          _performSearch(value);
                        },
                      ),
                    ),
                    if (_searchMatches.isNotEmpty)
                      Text(
                        '${_currentSearchIndex + 1}/${_searchMatches.length}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontFamily: _fontFamily,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            
            // Settings panel
            if (_showSettings)
              Container(
                height: 200,
                color: const Color(0xFF252526),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: _fontFamily,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _showHotkeySettings = !_showHotkeySettings),
                          child: Text(
                            _showHotkeySettings ? 'Editor Settings' : 'Hotkey Settings',
                            style: TextStyle(
                              color: Colors.blue[300],
                              fontSize: 12,
                              fontFamily: _fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    if (_showHotkeySettings)
                      _buildHotkeySettings()
                    else
                      _buildEditorSettings(),
                  ],
                ),
              ),
            
            // Editor area
            Expanded(
              child: Container(
                color: const Color(0xFF1e1e1e),
                child: _isMarkdownFile() ? _buildMarkdownEditor() : _buildCodeEditor(),
              ),
            ),
            
            // AI Chat Panel
            if (_showAIChat)
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF252526),
                  border: Border(
                    top: BorderSide(color: Colors.grey[600]!),
                  ),
                ),
                child: Column(
                  children: [
                    // AI Chat Header
                    Container(
                      height: 40,
                      color: const Color(0xFF2d2d2d),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.smart_toy, size: 16, color: Colors.blue[300]),
                                  const SizedBox(width: 8),
                                  DropdownButton<String>(
                                    value: _selectedModel,
                                    items: const [
                                      DropdownMenuItem(value: 'kimi-k2.6', child: Text('Kimi K2.6')),
                                      DropdownMenuItem(value: 'deepseek-v4-flash', child: Text('DeepSeek V4 Flash')),
                                    ],
                                    onChanged: (value) {
                                      setState(() => _selectedModel = value!);
                                    },
                                    style: DropdownButtonStyle<String>(
                                      backgroundColor: const Color(0xFF3c3c3c),
                                      textStyle: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 11,
                                        fontFamily: _fontFamily,
                                      ),
                                    ),
                                  ),
                                  if (_italicMode) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFffdb86),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'ITALIC',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _showAIChat = false),
                            icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                            tooltip: 'Close AI Chat',
                          ),
                        ],
                      ),
                    ),
                    
                    // AI Chat Messages
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: ListView.builder(
                          reverse: true,
                          itemCount: _aiChatMessages.length,
                          itemBuilder: (context, index) {
                            final message = _aiChatMessages[_aiChatMessages.length - 1 - index];
                            final isUser = message['role'] == 'user';
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isUser)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Icon(Icons.smart_toy, size: 20, color: Colors.blue[300]),
                                    ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isUser 
                                            ? const Color(0xFF0078d4)
                                            : const Color(0xFF3c3c3c),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        message['content'] ?? '',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontFamily: _fontFamily,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isUser)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(Icons.person, size: 20, color: Colors.grey[400]),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    // AI Chat Input
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey[600]!),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aiChatController,
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontFamily: _fontFamily,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ask AI assistant...',
                                hintStyle: TextStyle(color: Colors.grey[500]),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(color: Colors.grey[600]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide(color: Colors.blue[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onSubmitted: (value) => _sendAIMessage(value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _sendAIMessage(_aiChatController.text),
                            icon: Icon(Icons.send, size: 16, color: Colors.blue[300]),
                            tooltip: 'Send Message',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingToggle(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 12,
                fontFamily: _fontFamily,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.blue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              'Theme',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 12,
                fontFamily: _fontFamily,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _currentTheme,
            items: const [
              DropdownMenuItem(value: 'github', child: Text('GitHub')),
              DropdownMenuItem(value: 'monokai-sublime', child: Text('Monokai')),
              DropdownMenuItem(value: 'vs2015', child: Text('VS 2015')),
              DropdownMenuItem(value: 'atom-one-dark', child: Text('Atom Dark')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _currentTheme = value);
              }
            },
            style: TextStyle(
              color: Colors.grey[300],
              fontFamily: _fontFamily,
              fontSize: 12,
            ),
            dropdownColor: const Color(0xFF2d2d2d),
          ),
        ],
      ),
    );
  }

  Widget _buildFontSizeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              'Font Size',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 12,
                fontFamily: _fontFamily,
              ),
            ),
          ),
          DropdownButton<double>(
            value: _fontSize,
            items: const [
              DropdownMenuItem(value: 12.0, child: Text('12')),
              DropdownMenuItem(value: 14.0, child: Text('14')),
              DropdownMenuItem(value: 16.0, child: Text('16')),
              DropdownMenuItem(value: 18.0, child: Text('18')),
              DropdownMenuItem(value: 20.0, child: Text('20')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _fontSize = value);
              }
            },
            style: TextStyle(
              color: Colors.grey[300],
              fontFamily: _fontFamily,
              fontSize: 12,
            ),
            dropdownColor: const Color(0xFF2d2d2d),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownEditor() {
    return Row(
      children: [
        // Line numbers
        if (_showLineNumbers)
          Container(
            width: 50,
            color: const Color(0xFF252526),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _buildLineNumbers(),
          ),
        
        // Markdown editor
        Expanded(
          child: GestureDetector(
            onTapDown: _mouseEnabled ? (details) => _handleMouseClick(details) : null,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: _buildMarkdownRenderer(_controller.text),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeEditor() {
    return Row(
      children: [
        // Line numbers
        if (_showLineNumbers)
          Container(
            width: 50,
            color: const Color(0xFF252526),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _buildLineNumbers(),
          ),
        
        // Code editor with rainbow syntax highlighting
        Expanded(
          child: GestureDetector(
            onTapDown: _mouseEnabled ? (details) => _handleMouseClick(details) : null,
            child: Stack(
              children: [
                // Hidden text field for editing
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  readOnly: widget.readOnly,
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                    height: 1.2,
                    color: Colors.transparent, // Hide the actual text
                  ),
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  scrollController: _scrollController,
                  onChanged: (_) => _onTextChanged(),
                ),
                
                // Syntax highlighted display
                Positioned.fill(
                  child: IgnorePointer(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      child: Stack(
                        children: [
                          // Main text content
                          RichText(
                            text: TextSpan(children: _applyRainbowSyntax(_controller.text)),
                          ),
                          // Multi-cursor indicators
                          if (_multiCursorMode)
                            ..._buildMultiCursorIndicators(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineNumbers() {
    final lines = _controller.text.split('\n');
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return Container(
          height: _fontSize * 1.2,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: Colors.grey[500],
              fontFamily: _fontFamily,
              fontSize: _fontSize - 2,
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMultiCursorIndicators() {
    final indicators = <Widget>[];
    final text = _controller.text;
    final lines = text.split('\n');
    final lineHeight = _fontSize * 1.2;
    final charWidth = _fontSize * 0.6;
    
    for (int i = 0; i < _cursors.length; i++) {
      final cursor = _cursors[i];
      final offset = cursor.baseOffset;
      
      // Calculate line and column from offset
      int currentOffset = 0;
      int lineNumber = 0;
      int columnNumber = 0;
      
      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final lineLength = lines[lineIdx].length;
        if (currentOffset + lineLength >= offset) {
          lineNumber = lineIdx;
          columnNumber = offset - currentOffset;
          break;
        }
        currentOffset += lineLength + 1; // +1 for newline
      }
      
      // Calculate cursor position
      final cursorY = lineNumber * lineHeight;
      final cursorX = columnNumber * charWidth;
      
      indicators.add(
        Positioned(
          left: cursorX + (_showLineNumbers ? 50 : 0), // Account for line numbers
          top: cursorY,
          child: Container(
            width: 2,
            height: lineHeight,
            decoration: BoxDecoration(
              color: i == 0 ? Colors.blue : Colors.orange, // Main cursor blue, others orange
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      );
    }
    
    return indicators;
  }

  void _handleMouseClick(TapDownDetails details) {
    // Focus the editor when clicked
    _focusNode.requestFocus();
    
    // Check if Alt is pressed for multi-cursor
    final isAltPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
                        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);
    
    // Calculate cursor position from click coordinates
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(details.globalPosition);
    
    // For code editor, calculate approximate position
    if (!_isMarkdownFile()) {
      final text = _controller.text;
      final lines = text.split('\n');
      final lineHeight = _fontSize * 1.2;
      final charWidth = _fontSize * 0.6; // Approximate character width
      
      // Calculate line and column from click position
      final clickY = localOffset.dy - 12; // Account for padding
      final clickX = localOffset.dx - (_showLineNumbers ? 62 : 12); // Account for line numbers and padding
      
      final lineNumber = (clickY / lineHeight).floor();
      final columnNumber = (clickX / charWidth).floor();
      
      if (lineNumber >= 0 && lineNumber < lines.length) {
        final line = lines[lineNumber];
        final targetOffset = lines.take(lineNumber).fold(0, (sum, line) => sum + line.length + 1) + 
                            columnNumber.clamp(0, line.length);
        
        final newSelection = TextSelection.fromPosition(
          TextPosition(offset: targetOffset.clamp(0, text.length)),
        );
        
        if (isAltPressed) {
          // Add cursor for multi-cursor mode
          setState(() {
            _multiCursorMode = true;
            _cursors.add(newSelection);
          });
        } else {
          // Normal click - clear multi-cursors and set single cursor
          setState(() {
            _multiCursorMode = false;
            _cursors.clear();
            _controller.selection = newSelection;
          });
        }
      }
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchMatches.clear();
        _currentSearchIndex = 0;
      });
      return;
    }
    
    final text = _controller.text;
    final matches = <int>[];
    int index = text.indexOf(query);
    
    while (index != -1) {
      matches.add(index);
      index = text.indexOf(query, index + 1);
    }
    
    setState(() {
      _searchMatches = matches;
      _currentSearchIndex = 0;
    });
    
    if (matches.isNotEmpty) {
      _navigateToSearchMatch(0);
    }
  }

  void _navigateToSearchMatch(int index) {
    if (index >= 0 && index < _searchMatches.length) {
      final matchPosition = _searchMatches[index];
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: matchPosition),
      );
      
      // Scroll to match position
      // This would need more sophisticated implementation for accurate scrolling
    }
  }
}
