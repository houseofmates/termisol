import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/shell.dart';
import 'package:highlight/languages/html.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/csharp.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/dockerfile.dart';
import 'package:highlight/languages/nginx.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/zsh.dart';
import 'package:highlight/languages/fish.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/markdown.dart';
import 'package:path/path.dart' as path;
import '../core/deep_l_service.dart';
import '../core/nvidia_ai_client.dart';

/// Advanced text editor with syntax highlighting for all languages
/// Supports multiple themes, auto-completion, and advanced editing features
class TextEditor extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final Function(String) onSave;
  final VoidCallback? onClose;
  final bool readOnly;

  const TextEditor({
    super.key,
    required this.filePath,
    required this.initialContent,
    required this.onSave,
    this.onClose,
    this.readOnly = false,
  });

  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  late FocusNode _focusNode;
  
  String _currentTheme = 'monokai-sublime';
  bool _hasUnsavedChanges = false;
  Timer? _saveTimer;
  
  // Editor settings
  bool _showLineNumbers = true;
  bool _showMiniMap = false;
  bool _wordWrap = true;
  double _fontSize = 14.0;
  String _fontFamily = 'JetBrains Mono';
  
  // Search
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  int _currentSearchIndex = 0;
  List<int> _searchMatches = [];
  bool _useRegex = false;
  bool _matchCase = false;
  bool _matchWholeWord = false;
  
  // Auto-completion
  bool _showCompletion = false;
  List<String> _completions = [];
  int _selectedCompletion = 0;
  
  // Translation
  final DeepLTranslationService _deepL = DeepLTranslationService();
  bool _showTranslation = false;
  String? _translatedText;
  bool _isTranslating = false;
  String? _selectedText;
  
  // Context menu
  bool _showContextMenu = false;
  Offset _contextMenuPosition = Offset.zero;
  String? _contextMenuSelectedText;
  
  // AI Summarization
  final NvidiaAIClient _nvidiaClient = NvidiaAIClient();
  bool _showSummary = false;
  String? _summaryText;
  bool _isSummarizing = false;
  
  // Multiple Cursors
  final List<TextSelection> _cursors = [];
  bool _multiCursorMode = false;
  int _activeCursorIndex = 0;
  bool _isAltPressed = false;
  int _dragStartOffset = -1;
  bool _isDragging = false;
  
  // Smart Indentation
  bool _autoIndent = true;
  int _indentSize = 2;
  bool _useSpaces = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    
    _detectLanguage();
    _deepL.initialize();
    _nvidiaClient.initialize();
    
    // Initialize with single cursor
    _cursors.add(TextSelection.collapsed(offset: 0));
    
    // Listen for Alt key changes
    HardwareKeyboard.instance.addHandler(_handleAltKeyChange);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _replaceController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleAltKeyChange);
    super.dispose();
  }
  
  bool _handleAltKeyChange(KeyEvent event) {
    final wasAltPressed = _isAltPressed;
    _isAltPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
                   HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);
    
    // If Alt was released and we're not in multi-cursor mode, clear extra cursors
    if (wasAltPressed && !_isAltPressed && !_multiCursorMode) {
      _clearExtraCursors();
    }
    
    return false; // Don't consume the event
  }
  
  void _clearExtraCursors() {
    if (_cursors.length > 1) {
      setState(() {
        _cursors.removeRange(1, _cursors.length);
        _activeCursorIndex = 0;
      });
    }
  }

  void _onTextChanged() {
    if (!widget.readOnly) {
      setState(() {
        _hasUnsavedChanges = true;
      });
      
      // Auto-indent on new line
      if (_autoIndent) {
        _handleAutoIndent();
      }
      
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
  
  void _handleAutoIndent() {
    final text = _controller.text;
    final selection = _controller.selection;
    
    // Check if user just pressed Enter
    if (selection.isValid && selection.baseOffset == selection.extentOffset) {
      final cursorPos = selection.baseOffset;
      
      // Look for the newline character before cursor
      if (cursorPos > 0 && text[cursorPos - 1] == '\n') {
        // Find the start of the previous line
        int lineStart = cursorPos - 2;
        while (lineStart >= 0 && text[lineStart] != '\n') {
          lineStart--;
        }
        lineStart++;
        
        // Calculate indentation of previous line
        String previousLine = text.substring(lineStart, cursorPos - 1);
        int indentLevel = _getIndentLevel(previousLine);
        
        // Check if we need extra indentation (e.g., after opening brace)
        if (_shouldIncreaseIndent(previousLine)) {
          indentLevel += _indentSize;
        }
        
        // Apply indentation
        if (indentLevel > 0) {
          final indent = _useSpaces ? ' ' * indentLevel : '\t' * (indentLevel ~/ _indentSize);
          final newText = text.substring(0, cursorPos) + indent + text.substring(cursorPos);
          final newCursorPos = cursorPos + indent.length;
          
          _controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newCursorPos),
          );
        }
      }
    }
  }
  
  int _getIndentLevel(String line) {
    int spaces = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        spaces++;
      } else if (line[i] == '\t') {
        spaces += _indentSize;
      } else {
        break;
      }
    }
    return spaces;
  }
  
  bool _shouldIncreaseIndent(String previousLine) {
    final trimmed = previousLine.trimRight();
    final language = _detectLanguage();
    
    switch (language) {
      case 'dart':
      case 'java':
      case 'javascript':
      case 'typescript':
      case 'csharp':
      case 'cpp':
        return trimmed.endsWith('{') || 
               trimmed.endsWith('(') || 
               trimmed.endsWith('[') ||
               trimmed.contains(':') && !trimmed.contains('//');
               
      case 'python':
        return trimmed.endsWith(':') && !trimmed.startsWith('#');
        
      case 'yaml':
      case 'yml':
        return trimmed.endsWith(':');
        
      case 'shell':
      case 'bash':
        return trimmed.contains('then') || 
               trimmed.contains('do') ||
               trimmed.endsWith('\\');
        
      default:
        return trimmed.endsWith('{') || trimmed.endsWith('(');
    }
  }
  
  void _formatDocument() {
    final text = _controller.text;
    final language = _detectLanguage();
    final formattedText = _formatText(text, language);
    
    _controller.text = formattedText;
    _onTextChanged();
  }
  
  String _formatText(String text, String language) {
    final lines = text.split('\n');
    final formattedLines = <String>[];
    int currentIndent = 0;
    
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trimRight();
      
      // Skip empty lines
      if (line.isEmpty) {
        formattedLines.add('');
        continue;
      }
      
      // Decrease indent for closing braces
      if (line.startsWith('}') || line.startsWith(']') || line.startsWith(')')) {
        currentIndent = (currentIndent - _indentSize).clamp(0, double.infinity).toInt();
      }
      
      // Add current indentation
      final indent = _useSpaces ? ' ' * currentIndent : '\t' * (currentIndent ~/ _indentSize);
      formattedLines.add(indent + line);
      
      // Increase indent for opening braces
      if (line.endsWith('{') || line.endsWith('[') || line.endsWith('(')) {
        currentIndent += _indentSize;
      }
    }
    
    return formattedLines.join('\n');
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // Update completions when focus is gained
      _updateCompletions();
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
    
    switch (language) {
      case 'dart': return {'lang': dartLang, 'name': 'Dart'};
      case 'python': return {'lang': pythonLang, 'name': 'Python'};
      case 'javascript': return {'lang': javascriptLang, 'name': 'JavaScript'};
      case 'typescript': return {'lang': typescriptLang, 'name': 'TypeScript'};
      case 'json': return {'lang': jsonLang, 'name': 'JSON'};
      case 'yaml': return {'lang': yamlLang, 'name': 'YAML'};
      case 'shell':
      case 'bash': return {'lang': bashLang, 'name': 'Bash'};
      case 'zsh': return {'lang': zshLang, 'name': 'Zsh'};
      case 'fish': return {'lang': fishLang, 'name': 'Fish'};
      case 'html': return {'lang': htmlLang, 'name': 'HTML'};
      case 'css': return {'lang': cssLang, 'name': 'CSS'};
      case 'xml': return {'lang': xmlLang, 'name': 'XML'};
      case 'sql': return {'lang': sqlLang, 'name': 'SQL'};
      case 'go': return {'lang': goLang, 'name': 'Go'};
      case 'rust': return {'lang': rustLang, 'name': 'Rust'};
      case 'java': return {'lang': javaLang, 'name': 'Java'};
      case 'cpp': return {'lang': cppLang, 'name': 'C++'};
      case 'csharp': return {'lang': csharpLang, 'name': 'C#'};
      case 'php': return {'lang': phpLang, 'name': 'PHP'};
      case 'ruby': return {'lang': rubyLang, 'name': 'Ruby'};
      case 'swift': return {'lang': swiftLang, 'name': 'Swift'};
      case 'kotlin': return {'lang': kotlinLang, 'name': 'Kotlin'};
      case 'dockerfile': return {'lang': dockerfileLang, 'name': 'Dockerfile'};
      case 'markdown': return {'lang': markdownLang, 'name': 'Markdown'};
      default: return {'lang': null, 'name': 'Plain Text'};
    }
  }

  Map<String, dynamic> _getThemeData() {
    switch (_currentTheme) {
      case 'monokai-sublime':
        return {'theme': monokaiSublimeTheme, 'name': 'Monokai Sublime'};
      case 'vs2015':
        return {'theme': vs2015Theme, 'name': 'VS 2015'};
      case 'atom-one-dark':
        return {'theme': atomOneDarkTheme, 'name': 'Atom One Dark'};
      default:
        return {'theme': monokaiSublimeTheme, 'name': 'Monokai Sublime'};
    }
  }

  Future<void> _saveContent() async {
    try {
      await widget.onSave(_controller.text);
      setState(() {
        _hasUnsavedChanges = false;
      });
    } catch (e) {
      debugPrint('Failed to save content: $e');
    }
  }

  void _updateCompletions() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final currentLine = text.substring(0, cursorPos).split('\n').last;
    
    _completions = _generateCompletions(currentLine);
    _selectedCompletion = 0;
    
    setState(() {
      _showCompletion = _completions.isNotEmpty;
    });
  }

  List<String> _generateCompletions(String currentLine) {
    final words = currentLine.split(RegExp(r'\s+'));
    final lastWord = words.last.toLowerCase();
    
    if (lastWord.isEmpty) return [];
    
    final language = _detectLanguage();
    final completions = <String>[];
    
    // Language-specific completions
    switch (language) {
      case 'dart':
        completions.addAll([
          'class', 'extends', 'implements', 'with', 'mixin', 'enum',
          'import', 'as', 'show', 'hide', 'export', 'library',
          'void', 'int', 'String', 'bool', 'double', 'List', 'Map',
          'if', 'else', 'for', 'while', 'do', 'switch', 'case',
          'break', 'continue', 'return', 'async', 'await', 'try', 'catch', 'finally',
          'final', 'const', 'static', 'var', 'late', 'required',
          'Widget', 'State', 'BuildContext', 'Key', 'StatefulWidget', 'StatelessWidget',
        ]);
        break;
      case 'python':
        completions.addAll([
          'def', 'class', 'import', 'from', 'as', 'if', 'elif', 'else',
          'for', 'while', 'try', 'except', 'finally', 'with', 'lambda',
          'return', 'yield', 'async', 'await', 'self', 'cls', 'pass',
          'break', 'continue', 'global', 'nonlocal', 'assert', 'del',
          'str', 'int', 'float', 'bool', 'list', 'dict', 'tuple', 'set',
        ]);
        break;
      case 'javascript':
        completions.addAll([
          'function', 'class', 'extends', 'const', 'let', 'var',
          'if', 'else', 'for', 'while', 'do', 'switch', 'case',
          'break', 'continue', 'return', 'try', 'catch', 'finally',
          'import', 'export', 'default', 'async', 'await',
          'Array', 'Object', 'String', 'Number', 'Boolean',
          'console.log', 'document.getElementById', 'document.querySelector',
        ]);
        break;
    }
    
    // Filter by current word
    return completions
        .where((completion) => completion.toLowerCase().startsWith(lastWord))
        .take(10)
        .toList();
  }

  void _acceptCompletion() {
    if (_selectedCompletion < _completions.length) {
      final completion = _completions[_selectedCompletion];
      final text = _controller.text;
      final cursorPos = _controller.selection.baseOffset;
      final currentLine = text.substring(0, cursorPos).split('\n').last;
      final words = currentLine.split(RegExp(r'\s+'));
      
      final newText = text.substring(0, cursorPos - words.last.length) + completion + text.substring(cursorPos);
      final newCursorPos = cursorPos - words.last.length + completion.length;
      
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorPos),
      );
      
      setState(() {
        _showCompletion = false;
        _completions.clear();
      });
    }
  }

  void _searchText() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _searchMatches.clear();
        _currentSearchIndex = 0;
      });
      return;
    }
    
    final text = _controller.text;
    final matches = <int>[];
    
    if (_useRegex) {
      try {
        final regex = RegExp(
          query,
          caseSensitive: _matchCase,
          multiLine: true,
        );
        
        for (final match in regex.allMatches(text)) {
          matches.add(match.start);
        }
      } catch (e) {
        // Invalid regex, fall back to literal search
        _literalSearch(query, text, matches);
      }
    } else {
      _literalSearch(query, text, matches);
    }
    
    setState(() {
      _searchMatches = matches;
      _currentSearchIndex = 0;
    });
    
    if (matches.isNotEmpty) {
      _scrollToMatch(matches[0]);
    }
  }
  
  void _literalSearch(String query, String text, List<int> matches) {
    if (_matchWholeWord) {
      final wordPattern = RegExp(r'\b' + RegExp.escape(query) + r'\b', 
        caseSensitive: _matchCase);
      for (final match in wordPattern.allMatches(text)) {
        matches.add(match.start);
      }
    } else {
      int index = text.indexOf(query, 0);
      while (index != -1) {
        matches.add(index);
        index = text.indexOf(query, index + 1);
      }
    }
  }
  
  void _replaceAll() {
    final searchText = _searchController.text;
    final replaceText = _replaceController.text;
    
    if (searchText.isEmpty) return;
    
    String newText = _controller.text;
    
    if (_useRegex) {
      try {
        final regex = RegExp(
          searchText,
          caseSensitive: _matchCase,
          multiLine: true,
        );
        newText = newText.replaceAll(regex, replaceText);
      } catch (e) {
        // Invalid regex, don't replace
        return;
      }
    } else {
      if (_matchWholeWord) {
        final wordPattern = RegExp(r'\b' + RegExp.escape(searchText) + r'\b', 
          caseSensitive: _matchCase);
        newText = newText.replaceAll(wordPattern, replaceText);
      } else {
        newText = newText.replaceAll(searchText, replaceText);
      }
    }
    
    _controller.text = newText;
    _searchText(); // Refresh search
    _onTextChanged();
  }

  void _nextSearchMatch() {
    if (_searchMatches.isEmpty) return;
    
    _currentSearchIndex = (_currentSearchIndex + 1) % _searchMatches.length;
    _scrollToMatch(_searchMatches[_currentSearchIndex]);
  }

  void _previousSearchMatch() {
    if (_searchMatches.isEmpty) return;
    
    _currentSearchIndex = (_currentSearchIndex - 1 + _searchMatches.length) % _searchMatches.length;
    _scrollToMatch(_searchMatches[_currentSearchIndex]);
  }

  void _scrollToMatch(int position) {
    // Simple scroll to match (would need more complex implementation for actual highlighting)
    final lines = _controller.text.substring(0, position).split('\n').length;
    final lineHeight = _fontSize * 1.2;
    final scrollPosition = (lines - 1) * lineHeight;
    
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageConfig = _getLanguageConfig();
    final themeData = _getThemeData();
    
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                // Language indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    languageConfig['name'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Save indicator
                if (_hasUnsavedChanges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '●',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                
                const Spacer(),
                
                // Multi-cursor indicator
                if (_multiCursorMode || _isAltPressed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isAltPressed ? Colors.orange[700] : Colors.purple[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isAltPressed ? Icons.keyboard_alt : Icons.control_point,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isAltPressed ? 'Alt Mode' : '${_cursors.length} Cursors',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Search
                if (_showSearch)
                  Expanded(
                    child: Column(
                      children: [
                        // Search input row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Search...',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey[600]!),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                onChanged: (_) => _searchText(),
                                onSubmitted: (_) => _nextSearchMatch(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_currentSearchIndex + 1}/${_searchMatches.length}',
                              style: TextStyle(color: Colors.grey[400], fontSize: 10),
                            ),
                            IconButton(
                              onPressed: _previousSearchMatch,
                              icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                              color: Colors.grey[400],
                            ),
                            IconButton(
                              onPressed: _nextSearchMatch,
                              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                              color: Colors.grey[400],
                            ),
                            IconButton(
                              onPressed: () => setState(() => _showSearch = false),
                              icon: const Icon(Icons.close, size: 16),
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                        
                        // Search options row
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              // Regex checkbox
                              Row(
                                children: [
                                  Checkbox(
                                    value: _useRegex,
                                    onChanged: (value) {
                                      setState(() => _useRegex = value!);
                                      _searchText();
                                    },
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  Text(
                                    'Regex',
                                    style: TextStyle(color: Colors.grey[300], fontSize: 10),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(width: 8),
                              
                              // Match case checkbox
                              Row(
                                children: [
                                  Checkbox(
                                    value: _matchCase,
                                    onChanged: (value) {
                                      setState(() => _matchCase = value!);
                                      _searchText();
                                    },
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  Text(
                                    'Case',
                                    style: TextStyle(color: Colors.grey[300], fontSize: 10),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(width: 8),
                              
                              // Whole word checkbox
                              Row(
                                children: [
                                  Checkbox(
                                    value: _matchWholeWord,
                                    onChanged: (value) {
                                      setState(() => _matchWholeWord = value!);
                                      _searchText();
                                    },
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  Text(
                                    'Word',
                                    style: TextStyle(color: Colors.grey[300], fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Replace row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replaceController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Replace...',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: Colors.grey[600]!),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: _replaceAll,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[700],
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                              child: const Text(
                                'Replace All',
                                style: TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                
                // Actions
                if (!_showSearch) ...[
                  IconButton(
                    onPressed: () => setState(() => _showSearch = true),
                    icon: const Icon(Icons.search, size: 16),
                    color: Colors.grey[400],
                    tooltip: 'Search',
                  ),
                  IconButton(
                    onPressed: _saveContent,
                    icon: const Icon(Icons.save, size: 16),
                    color: _hasUnsavedChanges ? Colors.green[400] : Colors.grey[400],
                    tooltip: 'Save',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 16),
                    color: Colors.grey[400],
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'theme',
                        child: Row(
                          children: [
                            const Icon(Icons.palette, size: 16),
                            const SizedBox(width: 8),
                            Text('Theme: ${themeData['name']}'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'font_size',
                        child: Row(
                          children: [
                            const Icon(Icons.format_size, size: 16),
                            const SizedBox(width: 8),
                            Text('Font Size: ${_fontSize.toInt()}'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'word_wrap',
                        child: Row(
                          children: [
                            const Icon(Icons.wrap_text, size: 16),
                            const SizedBox(width: 8),
                            Text('Word Wrap: ${_wordWrap ? "On" : "Off"}'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'line_numbers',
                        child: Row(
                          children: [
                            const Icon(Icons.format_list_numbered, size: 16),
                            const SizedBox(width: 8),
                            Text('Line Numbers: ${_showLineNumbers ? "On" : "Off"}'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'theme':
                          _cycleTheme();
                          break;
                        case 'font_size':
                          _cycleFontSize();
                          break;
                        case 'word_wrap':
                          setState(() => _wordWrap = !_wordWrap);
                          break;
                        case 'line_numbers':
                          setState(() => _showLineNumbers = !_showLineNumbers);
                          break;
                      }
                    },
                  ),
                ],
                
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 16),
                    color: Colors.grey[400],
                    tooltip: 'Close',
                  ),
              ],
            ),
          ),
          
          // Editor area
          Expanded(
            child: Stack(
              children: [
                // Line numbers
                if (_showLineNumbers)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 50,
                    child: Container(
                      color: const Color(0xFF252526),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: CustomPaint(
                        painter: LineNumbersPainter(
                          text: _controller.text,
                          fontSize: _fontSize,
                          lineHeight: _fontSize * 1.2,
                        ),
                      ),
                    ),
                  ),
                
                // Code editor
                Positioned(
                  left: _showLineNumbers ? 50 : 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    readOnly: widget.readOnly,
                    style: TextStyle(
                      fontFamily: _fontFamily,
                      fontSize: _fontSize,
                      height: 1.2,
                      color: const Color(0xFFD4D4D4),
                    ),
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 8,
                        bottom: 8,
                      ),
                    ),
                    scrollController: _scrollController,
                    onChanged: (_) => _onTextChanged(),
                    onKey: (event) {
                      if (event is RawKeyDownEvent) {
                        // Multi-cursor shortcuts
                        if (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                            HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight)) {
                          
                          if (event.logicalKey == LogicalKeyboardKey.keyD && _multiCursorMode) {
                            _addCursorAtPosition(_contextMenuPosition);
                            return KeyEventResult.handled;
                          }
                          
                          if (event.logicalKey == LogicalKeyboardKey.keyU) {
                            _removeAllCursors();
                            return KeyEventResult.handled;
                          }
                          
                          if (event.logicalKey == LogicalKeyboardKey.keyAlt) {
                            _toggleMultiCursorMode();
                            return KeyEventResult.handled;
                          }
                        }
                        
                        if (event.logicalKey == LogicalKeyboardKey.tab && _showCompletion) {
                          _acceptCompletion();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown && _showCompletion) {
                          setState(() {
                            _selectedCompletion = (_selectedCompletion + 1) % _completions.length;
                          });
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp && _showCompletion) {
                          setState(() {
                            _selectedCompletion = (_selectedCompletion - 1 + _completions.length) % _completions.length;
                          });
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape && _showCompletion) {
                          setState(() {
                            _showCompletion = false;
                            _completions.clear();
                          });
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    onTapDown: (details) {
                      if (_isAltPressed) {
                        _handleAltClick(details.globalPosition);
                      } else {
                        // Check if right-click
                        if (details.kind == PointerDeviceKind.mouse && 
                            details.buttons == kSecondaryButton) {
                          _handleRightClick(details.globalPosition);
                        }
                      }
                    },
                    onTapUp: (details) {
                      if (_isDragging) {
                        _handleAltDragEnd();
                      }
                    },
                    onPanStart: (details) {
                      if (_isAltPressed) {
                        _handleAltDragStart(details.globalPosition);
                      }
                    },
                    onPanUpdate: (details) {
                      if (_isAltPressed) {
                        _handleAltDragUpdate(details.globalPosition);
                      }
                    },
                    onPanEnd: (details) {
                      if (_isDragging) {
                        _handleAltDragEnd();
                      }
                    },
                  ),
                ),
                
                // Auto-completion popup
                if (_showCompletion && _completions.isNotEmpty)
                  Positioned(
                    left: _showLineNumbers ? 50 : 0,
                    top: 100, // Would need to calculate actual position
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        border: Border.all(color: Colors.grey[600]!),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _completions.length,
                        itemBuilder: (context, index) {
                          final completion = _completions[index];
                          final isSelected = index == _selectedCompletion;
                          
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedCompletion = index;
                              });
                              _acceptCompletion();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.blue.withOpacity(0.3) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.code,
                                    size: 16,
                                    color: isSelected ? Colors.blue : Colors.grey[400],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      completion,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.grey[300],
                                        fontFamily: _fontFamily,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                
                // Translation popup
                if (_showTranslation)
                  Positioned(
                    right: 20,
                    top: 100,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        border: Border.all(color: Colors.blue[600]!),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[700],
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.translate, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  'DeepL Translation',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => setState(() => _showTranslation = false),
                                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                ),
                              ],
                            ),
                          ),
                          
                          // Content
                          Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Original text
                                if (_selectedText != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Original:',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _selectedText!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                
                                // Translation
                                Text(
                                  'Translation:',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (_isTranslating)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Translating...',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_translatedText != null)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _translatedText!,
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Translation unavailable',
                                      style: TextStyle(
                                        color: Colors.red[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Context menu
                if (_showContextMenu)
                  Positioned(
                    left: _contextMenuPosition.dx,
                    top: _contextMenuPosition.dy,
                    child: GestureDetector(
                      onTap: _hideContextMenu,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 200),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          border: Border.all(color: Colors.grey[600]!),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Cut
                            if (_contextMenuSelectedText != null)
                              _buildContextMenuItem(
                                icon: Icons.content_cut,
                                label: 'Cut',
                                onPressed: _cutSelection,
                              ),
                            
                            // Copy
                            if (_contextMenuSelectedText != null)
                              _buildContextMenuItem(
                                icon: Icons.content_copy,
                                label: 'Copy',
                                onPressed: _copySelection,
                              ),
                            
                            // Paste
                            _buildContextMenuItem(
                              icon: Icons.content_paste,
                              label: 'Paste',
                              onPressed: _pasteFromClipboard,
                            ),
                            
                            // Paste and Replace
                            _buildContextMenuItem(
                              icon: Icons.content_paste_off,
                              label: 'Paste & Replace',
                              onPressed: _pasteAndReplace,
                            ),
                            
                            if (_contextMenuSelectedText != null) ...[
                              const Divider(height: 1, color: Colors.grey),
                              
                              // Multi-cursor options
                              _buildContextMenuItem(
                                icon: Icons.control_point,
                                label: 'Add Cursor Here',
                                onPressed: () {
                                  _hideContextMenu();
                                  _addCursorAtPosition(_contextMenuPosition);
                                },
                              ),
                              
                              _buildContextMenuItem(
                                icon: Icons.select_all,
                                label: 'Select All Occurrences',
                                onPressed: () {
                                  _hideContextMenu();
                                  _selectAllOccurrences();
                                },
                              ),
                              
                              const Divider(height: 1, color: Colors.grey),
                              
                              // Translate
                              if (_deepL.isAvailable)
                                _buildContextMenuItem(
                                  icon: Icons.translate,
                                  label: 'Translate',
                                  onPressed: () {
                                    _hideContextMenu();
                                    _translateSelectedText(_contextMenuSelectedText!);
                                  },
                                ),
                              
                              // Summarize
                              if (_nvidiaClient.isInitialized)
                                _buildContextMenuItem(
                                  icon: Icons.summarize,
                                  label: 'Summarize',
                                  onPressed: () {
                                    _hideContextMenu();
                                    _summarizeText(_contextMenuSelectedText!);
                                  },
                                ),
                            ],
                            
                            const Divider(height: 1, color: Colors.grey),
                            
                            // Format Document
                            _buildContextMenuItem(
                              icon: Icons.format_align_left,
                              label: 'Format Document',
                              onPressed: () {
                                _hideContextMenu();
                                _formatDocument();
                              },
                            ),
                            
                            // Select All
                            _buildContextMenuItem(
                              icon: Icons.select_all,
                              label: 'Select All',
                              onPressed: _selectAll,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                
                // Summary popup
                if (_showSummary)
                  Positioned(
                    left: 20,
                    top: 100,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        border: Border.all(color: Colors.purple[600]!),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple[700],
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.summarize, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  'AI Summary',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => setState(() => _showSummary = false),
                                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                ),
                              ],
                            ),
                          ),
                          
                          // Content
                          Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Original text preview
                                if (_contextMenuSelectedText != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Original:',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _contextMenuSelectedText!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                
                                // Summary
                                Text(
                                  'Summary:',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (_isSummarizing)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Summarizing...',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_summaryText != null)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _summaryText!,
                                      style: const TextStyle(
                                        color: Colors.purple,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Summarization unavailable',
                                      style: TextStyle(
                                        color: Colors.red[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _cycleTheme() {
    final themes = ['monokai-sublime', 'vs2015', 'atom-one-dark'];
    final currentIndex = themes.indexOf(_currentTheme);
    final nextIndex = (currentIndex + 1) % themes.length;
    setState(() {
      _currentTheme = themes[nextIndex];
    });
  }

  void _handleRightClick(Offset position) {
    final selectedText = _controller.selection.textInside(_controller.text);
    
    if (_isAltPressed) {
      // Add cursor at position when Alt+Right-click
      _addCursorAtPosition(position);
      return;
    }
    
    setState(() {
      _showContextMenu = true;
      _contextMenuPosition = position;
      _contextMenuSelectedText = selectedText.isNotEmpty ? selectedText : null;
    });
  }
  
  void _addCursorAtPosition(Offset globalPosition) {
    if (_cursors.length >= 10) {
      // Limit to 10 cursors
      return;
    }
    
    // For simplicity, add cursor at current selection end
    // In a real implementation, you'd calculate the exact text position from the click coordinates
    final newOffset = _controller.selection.end;
    
    setState(() {
      _cursors.add(TextSelection.collapsed(offset: newOffset));
      _activeCursorIndex = _cursors.length - 1;
      _multiCursorMode = true;
    });
  }
  
  void _handleAltClick(Offset position) {
    if (_isAltPressed) {
      _addCursorAtPosition(position);
    }
  }
  
  void _handleAltDragStart(Offset position) {
    if (_isAltPressed) {
      setState(() {
        _isDragging = true;
        _dragStartOffset = _controller.selection.baseOffset;
      });
    }
  }
  
  void _handleAltDragUpdate(Offset position) {
    if (_isAltPressed && _isDragging && _dragStartOffset >= 0) {
      // Calculate current selection based on mouse position
      // This is simplified - in practice you'd calculate the text offset from position
      final currentOffset = _controller.selection.extentOffset;
      final selectionLength = currentOffset - _dragStartOffset;
      
      // Update all cursors to have the same selection
      setState(() {
        for (int i = 0; i < _cursors.length; i++) {
          final cursorStart = _cursors[i].baseOffset;
          _cursors[i] = TextSelection(
            baseOffset: cursorStart,
            extentOffset: cursorStart + selectionLength,
          );
        }
      });
    }
  }
  
  void _handleAltDragEnd() {
    setState(() {
      _isDragging = false;
      _dragStartOffset = -1;
    });
  }
  
  void _removeAllCursors() {
    setState(() {
      _cursors.clear();
      _cursors.add(TextSelection.collapsed(offset: _controller.selection.baseOffset));
      _activeCursorIndex = 0;
      _multiCursorMode = false;
    });
  }
  
  void _toggleMultiCursorMode() {
    setState(() {
      _multiCursorMode = !_multiCursorMode;
      if (!_multiCursorMode) {
        _removeAllCursors();
      }
    });
  }
  
  void _selectAllOccurrences() {
    final selectedText = _controller.selection.textInside(_controller.text);
    if (selectedText.isEmpty) return;
    
    final text = _controller.text;
    final matches = <int>[];
    int index = text.indexOf(selectedText);
    
    while (index != -1) {
      matches.add(index);
      index = text.indexOf(selectedText, index + 1);
    }
    
    setState(() {
      _cursors.clear();
      for (final match in matches) {
        _cursors.add(TextSelection.collapsed(offset: match));
      }
      _multiCursorMode = true;
      _activeCursorIndex = 0;
    });
  }
  
  void _hideContextMenu() {
    setState(() {
      _showContextMenu = false;
    });
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
    _hideContextMenu();
  }
  
  void _copySelection() {
    final selectedText = _controller.selection.textInside(_controller.text);
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
    }
    _hideContextMenu();
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
    _hideContextMenu();
  }
  
  void _pasteAndReplace() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData?.text != null) {
      final textToInsert = clipboardData!.text!;
      _controller.text = textToInsert;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: textToInsert.length),
      );
      _onTextChanged();
    }
    _hideContextMenu();
  }
  
  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _hideContextMenu();
  }
  
  Future<void> _summarizeText(String text) async {
    setState(() {
      _isSummarizing = true;
      _showSummary = true;
      _summaryText = null;
    });
    
    try {
      final response = await _nvidiaClient.chatCompletion(
        messages: [
          ChatMessage(
            role: 'system',
            content: 'You are a helpful AI assistant. Summarize the given text concisely while preserving the main points and key details.',
          ),
          ChatMessage(
            role: 'user',
            content: 'Please summarize this text:\n\n$text',
          ),
        ],
        model: 'moonshotai/kimi-k2.6',
        maxTokens: 500,
        temperature: 0.3,
      );
      
      setState(() {
        _summaryText = response.content;
        _isSummarizing = false;
      });
    } catch (e) {
      setState(() {
        _isSummarizing = false;
        _summaryText = 'Summarization failed: $e';
      });
    }
  }
  
  Future<void> _translateSelectedText(String text) async {
    setState(() {
      _selectedText = text;
      _isTranslating = true;
      _showTranslation = true;
      _translatedText = null;
    });
    
    try {
      final translation = await _deepL.translateToEnglish(text);
      setState(() {
        _translatedText = translation;
        _isTranslating = false;
      });
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translatedText = 'Translation failed: $e';
      });
    }
  }
  
  void _cycleFontSize() {
    final sizes = [12.0, 14.0, 16.0, 18.0, 20.0];
    final currentIndex = sizes.indexWhere((size) => (size - _fontSize).abs() < 0.1);
    final nextIndex = (currentIndex + 1) % sizes.length;
    setState(() {
      _fontSize = sizes[nextIndex];
    });
  }
  
  Widget _buildContextMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Colors.grey[300],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LineNumbersPainter extends CustomPainter {
  final String text;
  final double fontSize;
  final double lineHeight;

  LineNumbersPainter({
    required this.text,
    required this.fontSize,
    required this.lineHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lines = text.split('\n');
    final lineCount = lines.length;
    
    final paint = Paint()
      ..color = const Color(0xFF858585)
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < lineCount; i++) {
      final lineNumber = (i + 1).toString();
      final y = i * lineHeight + fontSize;
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: lineNumber,
          style: TextStyle(
            color: const Color(0xFF858585),
            fontSize: fontSize * 0.8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width - textPainter.width - 4, y),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LineNumbersPainter oldDelegate) {
    return oldDelegate.text != text ||
           oldDelegate.fontSize != fontSize ||
           oldDelegate.lineHeight != lineHeight;
  }
}
