import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Code explanation on hover for Termisol
/// 
/// Features:
/// - Hover-based code explanation
/// - AI-powered analysis
/// - Multi-language support
/// - Syntax-aware explanations
/// - Performance optimization
/// - Context-aware suggestions
class CodeExplanationWidget extends StatefulWidget {
  final String code;
  final String language;
  final TextStyle? textStyle;
  final NvidiaAITerminalAssistant? aiAssistant;
  final bool enableHover;
  
  const CodeExplanationWidget({
    super.key,
    required this.code,
    this.language = 'text',
    this.textStyle,
    this.aiAssistant,
    this.enableHover = true,
  });
  
  @override
  State<CodeExplanationWidget> createState() => _CodeExplanationWidgetState();
}

class _CodeExplanationWidgetState extends State<CodeExplanationWidget> {
  final Map<String, String> _explanationCache = {};
  final Map<String, CodeElement> _codeElements = {};
  Timer? _debounceTimer;
  bool _isHovering = false;
  String? _hoveredElement;
  String? _currentExplanation;
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _parseCodeElements();
  }
  
  void _parseCodeElements() {
    // Parse code into elements for hover detection
    final lines = widget.code.split('\n');
    int lineIndex = 0;
    
    for (final line in lines) {
      _parseLine(line, lineIndex);
      lineIndex++;
    }
  }
  
  void _parseLine(String line, int lineIndex) {
    // Parse different language-specific elements
    switch (widget.language.toLowerCase()) {
      case 'dart':
        _parseDartLine(line, lineIndex);
        break;
      case 'python':
        _parsePythonLine(line, lineIndex);
        break;
      case 'javascript':
      case 'js':
        _parseJavaScriptLine(line, lineIndex);
        break;
      case 'bash':
      case 'shell':
        _parseBashLine(line, lineIndex);
        break;
      default:
        _parseGenericLine(line, lineIndex);
        break;
    }
  }
  
  void _parseDartLine(String line, int lineIndex) {
    // Parse Dart-specific elements
    final patterns = {
      'class': RegExp(r'\bclass\s+(\w+)'),
      'function': RegExp(r'\b(\w+)\s*\([^)]*\)\s*{'),
      'variable': RegExp(r'\b(\w+)\s*='),
      'import': RegExp(r'\bimport\s+([\'"][^\'"]+[\'"])'),
      'type': RegExp(r'\b(\w+)\s+\w+\s*[=;]'),
    };
    
    for (final entry in patterns.entries) {
      final matches = entry.value.allMatches(line);
      for (final match in matches) {
        final element = CodeElement(
          type: entry.key,
          name: match.group(1) ?? match.group(0)!,
          line: lineIndex,
          start: match.start,
          end: match.end,
          fullText: match.group(0)!,
        );
        _codeElements[element.key] = element;
      }
    }
  }
  
  void _parsePythonLine(String line, int lineIndex) {
    // Parse Python-specific elements
    final patterns = {
      'class': RegExp(r'\bclass\s+(\w+)'),
      'function': RegExp(r'\bdef\s+(\w+)\s*\([^)]*\):'),
      'variable': RegExp(r'\b(\w+)\s*='),
      'import': RegExp(r'\b(from\s+\w+\s+)?import\s+(\w+)'),
      'decorator': RegExp(r'@(\w+)'),
    };
    
    for (final entry in patterns.entries) {
      final matches = entry.value.allMatches(line);
      for (final match in matches) {
        final element = CodeElement(
          type: entry.key,
          name: match.group(1) ?? match.group(0)!,
          line: lineIndex,
          start: match.start,
          end: match.end,
          fullText: match.group(0)!,
        );
        _codeElements[element.key] = element;
      }
    }
  }
  
  void _parseJavaScriptLine(String line, int lineIndex) {
    // Parse JavaScript-specific elements
    final patterns = {
      'function': RegExp(r'\bfunction\s+(\w+)'),
      'variable': RegExp(r'\b(const|let|var)\s+(\w+)'),
      'class': RegExp(r'\bclass\s+(\w+)'),
      'method': RegExp(r'\b(\w+)\s*\([^)]*\)\s*{'),
      'import': RegExp(r'\bimport\s+.+from\s+[\'"]([^\'"]+)[\'"]'),
    };
    
    for (final entry in patterns.entries) {
      final matches = entry.value.allMatches(line);
      for (final match in matches) {
        final element = CodeElement(
          type: entry.key,
          name: match.group(1) ?? match.group(0)!,
          line: lineIndex,
          start: match.start,
          end: match.end,
          fullText: match.group(0)!,
        );
        _codeElements[element.key] = element;
      }
    }
  }
  
  void _parseBashLine(String line, int lineIndex) {
    // Parse Bash-specific elements
    final patterns = {
      'command': RegExp(r'\b(\w+)\s+'),
      'variable': RegExp(r'\$(\w+)'),
      'function': RegExp(r'\b(\w+)\s*\(\s*\)\s*{'),
      'alias': RegExp(r'\balias\s+(\w+)='),
    };
    
    for (final entry in patterns.entries) {
      final matches = entry.value.allMatches(line);
      for (final match in matches) {
        final element = CodeElement(
          type: entry.key,
          name: match.group(1) ?? match.group(0)!,
          line: lineIndex,
          start: match.start,
          end: match.end,
          fullText: match.group(0)!,
        );
        _codeElements[element.key] = element;
      }
    }
  }
  
  void _parseGenericLine(String line, int lineIndex) {
    // Generic parsing for unknown languages
    final words = line.split(RegExp(r'\s+'));
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isNotEmpty && word.length > 2) {
        final element = CodeElement(
          type: 'word',
          name: word,
          line: lineIndex,
          start: line.indexOf(word),
          end: line.indexOf(word) + word.length,
          fullText: word,
        );
        _codeElements[element.key] = element;
      }
    }
  }
  
  void _onHover(String elementKey) {
    if (!widget.enableHover) return;
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _showExplanation(elementKey);
    });
    
    setState(() {
      _isHovering = true;
      _hoveredElement = elementKey;
    });
  }
  
  void _onHoverExit() {
    _debounceTimer?.cancel();
    setState(() {
      _isHovering = false;
      _hoveredElement = null;
      _currentExplanation = null;
    });
  }
  
  Future<void> _showExplanation(String elementKey) async {
    final element = _codeElements[elementKey];
    if (element == null) return;
    
    // Check cache first
    if (_explanationCache.containsKey(elementKey)) {
      setState(() {
        _currentExplanation = _explanationCache[elementKey];
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      String explanation;
      
      if (widget.aiAssistant != null) {
        // Use AI for explanation
        explanation = await _getAIExplanation(element);
      } else {
        // Use local explanations
        explanation = _getLocalExplanation(element);
      }
      
      // Cache the explanation
      _explanationCache[elementKey] = explanation;
      
      setState(() {
        _currentExplanation = explanation;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _currentExplanation = 'Failed to get explanation: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<String> _getAIExplanation(CodeElement element) async {
    if (widget.aiAssistant == null) return 'AI assistant not available';
    
    final prompt = '''Explain this ${element.type} in ${widget.language}:

Code: ${element.fullText}
Name: ${element.name}
Line: ${element.line + 1}

Provide a concise explanation covering:
1. What it is
2. What it does
3. Common use cases
4. Important considerations''';
    
    return await widget.aiAssistant!.explainCommand(prompt);
  }
  
  String _getLocalExplanation(CodeElement element) {
    // Local explanations for common patterns
    switch (element.type) {
      case 'class':
        return 'A class is a blueprint for creating objects. It defines properties and methods that objects of this type will have.';
      case 'function':
        return 'A function is a reusable block of code that performs a specific task. It can take inputs and return outputs.';
      case 'variable':
        return 'A variable is a named storage location for data. It holds a value that can be changed during program execution.';
      case 'import':
        return 'An import statement brings code from other modules or libraries into the current scope.';
      case 'command':
        return 'A command is an instruction to the shell or terminal to perform a specific action.';
      case 'method':
        return 'A method is a function that belongs to a class. It operates on the data contained in objects of that class.';
      case 'type':
        return 'A type defines the kind of data a variable can hold, such as numbers, text, or more complex structures.';
      default:
        return '${element.type}: ${element.name} - A code element in ${widget.language}';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Code display with hover detection
        _buildCodeDisplay(),
        
        // Explanation popup
        if (_isHovering && _currentExplanation != null)
          _buildExplanationPopup(),
      ],
    );
  }
  
  Widget _buildCodeDisplay() {
    final lines = widget.code.split('\n');
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.language.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Code lines
          ...lines.asMap().entries.map((entry) {
            final lineIndex = entry.key;
            final line = entry.value;
            
            return _buildCodeLine(line, lineIndex);
          }).toList(),
        ],
      ),
    );
  }
  
  Widget _buildCodeLine(String line, int lineIndex) {
    final elements = _codeElements.values
        .where((element) => element.line == lineIndex)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    
    if (elements.isEmpty) {
      return Text(
        line,
        style: widget.textStyle ?? const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      );
    }
    
    return RichText(
      text: TextSpan(
        children: _buildTextSpans(line, elements),
      ),
    );
  }
  
  List<TextSpan> _buildTextSpans(String line, List<CodeElement> elements) {
    final spans = <TextSpan>[];
    int lastEnd = 0;
    
    for (final element in elements) {
      // Add text before element
      if (element.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, element.start),
          style: widget.textStyle ?? const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ));
      }
      
      // Add element with hover detection
      spans.add(TextSpan(
        text: element.fullText,
        style: (widget.textStyle ?? const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        )).copyWith(
          color: _getElementColor(element.type),
          decoration: _hoveredElement == element.key 
              ? TextDecoration.underline 
              : TextDecoration.none,
          decorationColor: Colors.blue[400],
        ),
        mouseCursor: SystemMouseCursors.click,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _onHover(element.key),
      ));
      
      lastEnd = element.end;
    }
    
    // Add remaining text
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: widget.textStyle ?? const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ));
    }
    
    return spans;
  }
  
  Color _getElementColor(String elementType) {
    switch (elementType) {
      case 'class':
        return Colors.blue[300]!;
      case 'function':
      case 'method':
        return Colors.green[300]!;
      case 'variable':
        return Colors.orange[300]!;
      case 'import':
        return Colors.purple[300]!;
      case 'command':
        return Colors.yellow[300]!;
      case 'type':
        return Colors.cyan[300]!;
      default:
        return Colors.grey[300]!;
    }
  }
  
  Widget _buildExplanationPopup() {
    return Positioned(
      top: 50,
      right: 10,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          border: Border.all(color: Colors.blue[400]!),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue[400],
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Code Explanation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _onHoverExit,
                  child: Icon(
                    Icons.close,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Loading indicator
            if (_isLoading)
              const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.blue,
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              // Explanation text
              Text(
                _currentExplanation!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Code element for hover detection
class CodeElement {
  final String type;
  final String name;
  final int line;
  final int start;
  final int end;
  final String fullText;
  
  CodeElement({
    required this.type,
    required this.name,
    required this.line,
    required this.start,
    required this.end,
    required this.fullText,
  });
  
  String get key => '${line}_${start}_${end}';
}
