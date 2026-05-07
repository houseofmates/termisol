import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';
import 'dart:io';
import 'dart:convert';

class CodeIntelligence {
  static const int _maxSuggestions = 20;
  static const int _maxCacheSize = 1000;
  static const int _analysisTimeout = 5000; // 5 seconds
  
  final Map<String, List<CodeCompletion>> _completions = {};
  final Map<String, List<CodeDefinition>> _definitions = {};
  final Map<String, List<CodeReference>> _references = {};
  final Map<String, CodeAnalysis> _analysisCache = {};
  final Map<String, List<CodeError>> _errors = {};
  
  final Map<String, LanguageProfile> _languageProfiles = {};
  final Map<String, List<CodePattern>> _patterns = {};
  
  int _totalAnalyses = 0;
  int _totalCompletions = 0;
  int _totalErrors = 0;
  
  final StreamController<IntelligenceEvent> _intelligenceController = 
      StreamController<IntelligenceEvent>.broadcast();

  void initialize() {
    _initializeLanguageProfiles();
    _initializePatterns();
    developer.log('🧠 Code Intelligence initialized');
  }

  void _initializeLanguageProfiles() {
    // Dart
    _languageProfiles['dart'] = LanguageProfile(
      name: 'dart',
      keywords: ['class', 'void', 'final', 'const', 'static', 'async', 'await', 'import', 'export'],
      types: ['String', 'int', 'double', 'bool', 'List', 'Map', 'Future', 'Stream'],
      functions: ['print', 'debugPrint', 'assert', 'throw', 'rethrow'],
      classes: ['Object', 'String', 'List', 'Map', 'Set', 'Future', 'Stream'],
      patterns: [
        CodePattern(
          type: PatternType.classDeclaration,
          regex: r'class\s+(\w+)\s*(?:extends\s+(\w+))?\s*\{',
          description: 'Class declaration',
        ),
        CodePattern(
          type: PatternType.functionDeclaration,
          regex: r'(?:\w+\s+)?(\w+)\s*\([^)]*\)\s*(?:async\s*)?\{',
          description: 'Function declaration',
        ),
        CodePattern(
          type: PatternType.importStatement,
          regex: r'import\s+[\'"]([^\'"]+)[\'"]',
          description: 'Import statement',
        ),
      ],
    );
    
    // Python
    _languageProfiles['python'] = LanguageProfile(
      name: 'python',
      keywords: ['def', 'class', 'import', 'from', 'as', 'if', 'else', 'for', 'while', 'try', 'except', 'finally'],
      types: ['str', 'int', 'float', 'bool', 'list', 'dict', 'tuple', 'set'],
      functions: ['print', 'len', 'range', 'enumerate', 'zip', 'map', 'filter', 'open'],
      classes: ['object', 'str', 'list', 'dict', 'tuple', 'set'],
      patterns: [
        CodePattern(
          type: PatternType.classDeclaration,
          regex: r'class\s+(\w+)\s*(?:\([^)]*\))?\s*\:',
          description: 'Class declaration',
        ),
        CodePattern(
          type: PatternType.functionDeclaration,
          regex: r'def\s+(\w+)\s*\([^)]*\)\s*\:',
          description: 'Function declaration',
        ),
        CodePattern(
          type: PatternType.importStatement,
          regex: r'import\s+(\w+)(?:\s+as\s+(\w+))?',
          description: 'Import statement',
        ),
      ],
    );
    
    // JavaScript
    _languageProfiles['javascript'] = LanguageProfile(
      name: 'javascript',
      keywords: ['function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'try', 'catch', 'finally'],
      types: ['string', 'number', 'boolean', 'object', 'array', 'function', 'undefined', 'null'],
      functions: ['console.log', 'alert', 'prompt', 'parseInt', 'parseFloat', 'isNaN'],
      classes: ['Object', 'Array', 'String', 'Number', 'Boolean', 'Function'],
      patterns: [
        CodePattern(
          type: PatternType.functionDeclaration,
          regex: r'(?:const|let|var)?\s*(\w+)\s*=\s*(?:function\s*)?\([^)]*\)\s*\{',
          description: 'Function declaration',
        ),
        CodePattern(
          type: PatternType.classDeclaration,
          regex: r'class\s+(\w+)\s*(?:extends\s+(\w+))?\s*\{',
          description: 'Class declaration',
        ),
        CodePattern(
          type: PatternType.importStatement,
          regex: r'import\s+\{[^}]+\}\s+from\s+[\'"]([^\'"]+)[\'"]',
          description: 'Import statement',
        ),
      ],
    );
    
    // Add more languages as needed
  }

  void _initializePatterns() {
    // Common code patterns across languages
    _patterns['general'] = [
      CodePattern(
        type: PatternType.comment,
        regex: r'//.*$|/\*[\s\S]*?\*/',
        description: 'Comment',
      ),
      CodePattern(
        type: PatternType.stringLiteral,
        regex: r'["\']([^"\'\\]*(\\.[^"\'\\]*)*)["\']',
        description: 'String literal',
      ),
      CodePattern(
        type: PatternType.numberLiteral,
        regex: r'\b\d+(?:\.\d+)?\b',
        description: 'Number literal',
      ),
      CodePattern(
        type: PatternType.variableDeclaration,
        regex: r'(?:const|let|var|final|static)\s+(\w+)',
        description: 'Variable declaration',
      ),
    ];
  }

  Future<List<CodeCompletion>> getCompletions({
    required String filePath,
    required String code,
    required int line,
    required int column,
    String? language,
  }) async {
    final lang = language ?? _detectLanguage(filePath);
    final profile = _languageProfiles[lang];
    
    if (profile == null) {
      return [];
    }
    
    // Check cache first
    final cacheKey = _generateCacheKey(code, line, column, lang);
    final cached = _analysisCache[cacheKey];
    
    if (cached != null && !cached.isExpired()) {
      _totalCompletions++;
      
      developer.log('🧠 Using cached completions for $filePath');
      
      return cached.completions.take(_maxSuggestions).toList();
    }
    
    try {
      final completions = await _generateCompletions(code, line, column, profile);
      
      // Cache the result
      final analysis = CodeAnalysis(
        filePath: filePath,
        language: lang,
        code: code,
        line: line,
        column: column,
        completions: completions,
        errors: [],
        definitions: [],
        references: [],
        analyzedAt: DateTime.now(),
      );
      
      _analysisCache[cacheKey] = analysis;
      _totalCompletions++;
      
      // Keep cache size limited
      if (_analysisCache.length > _maxCacheSize) {
        final oldestKey = _analysisCache.keys.first;
        _analysisCache.remove(oldestKey);
      }
      
      developer.log('🧠 Generated ${completions.length} completions for $filePath');
      
      _emitEvent(IntelligenceEvent(
        type: IntelligenceEventType.completionsGenerated,
        filePath: filePath,
        language: lang,
        completions: completions,
      ));
      
      return completions.take(_maxSuggestions).toList();
      
    } catch (e) {
      developer.log('🧠 Failed to generate completions: $e');
      return [];
    }
  }

  Future<List<CodeCompletion>> _generateCompletions(
    String code,
    int line,
    int column,
    LanguageProfile profile,
  ) async {
    final completions = <CodeCompletion>[];
    final lines = code.split('\n');
    final currentLine = line < lines.length ? lines[line] : '';
    final prefix = _extractPrefix(currentLine, column);
    
    // Keyword completions
    for (final keyword in profile.keywords) {
      if (keyword.toLowerCase().startsWith(prefix.toLowerCase())) {
        completions.add(CodeCompletion(
          type: CompletionType.keyword,
          text: keyword,
          description: 'Keyword: $keyword',
          priority: 8,
          insertText: keyword,
        ));
      }
    }
    
    // Type completions
    for (final type in profile.types) {
      if (type.toLowerCase().startsWith(prefix.toLowerCase())) {
        completions.add(CodeCompletion(
          type: CompletionType.type,
          text: type,
          description: 'Type: $type',
          priority: 7,
          insertText: type,
        ));
      }
    }
    
    // Function completions
    for (final function in profile.functions) {
      if (function.toLowerCase().startsWith(prefix.toLowerCase())) {
        completions.add(CodeCompletion(
          type: CompletionType.function,
          text: function,
          description: 'Function: $function',
          priority: 9,
          insertText: '$function()',
          detail: 'Built-in function',
        ));
      }
    }
    
    // Class completions
    for (final className in profile.classes) {
      if (className.toLowerCase().startsWith(prefix.toLowerCase())) {
        completions.add(CodeCompletion(
          type: CompletionType.classType,
          text: className,
          description: 'Class: $className',
          priority: 6,
          insertText: className,
          detail: 'Built-in class',
        ));
      }
    }
    
    // Local symbol completions
    final localSymbols = _extractLocalSymbols(code, line, column);
    for (final symbol in localSymbols) {
      if (symbol.name.toLowerCase().startsWith(prefix.toLowerCase())) {
        completions.add(CodeCompletion(
          type: _getCompletionType(symbol.type),
          text: symbol.name,
          description: '${symbol.type}: ${symbol.name}',
          priority: 10,
          insertText: symbol.name,
          detail: 'Local ${symbol.type}',
        ));
      }
    }
    
    // Sort by priority and relevance
    completions.sort((a, b) {
      final priorityDiff = b.priority.compareTo(a.priority);
      if (priorityDiff != 0) return priorityDiff;
      
      final aStarts = a.text.toLowerCase().startsWith(prefix.toLowerCase());
      final bStarts = b.text.toLowerCase().startsWith(prefix.toLowerCase());
      
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      
      return a.text.compareTo(b.text);
    });
    
    return completions;
  }

  String _extractPrefix(String line, int column) {
    if (column > line.length) column = line.length;
    
    final prefix = line.substring(0, column);
    final lastSpace = prefix.lastIndexOf(RegExp(r'\s'));
    
    return lastSpace >= 0 ? prefix.substring(lastSpace + 1) : prefix;
  }

  List<LocalSymbol> _extractLocalSymbols(String code, int currentLine, int currentColumn) {
    final symbols = <LocalSymbol>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length && i <= currentLine; i++) {
      final line = lines[i];
      
      // Extract function declarations
      final functionMatches = RegExp(r'(?:\w+\s+)?(\w+)\s*\([^)]*\)\s*(?:async\s*)?\{').allMatches(line);
      for (final match in functionMatches) {
        final functionName = match.group(1)!;
        symbols.add(LocalSymbol(
          name: functionName,
          type: 'function',
          line: i,
          column: match.start,
        ));
      }
      
      // Extract variable declarations
      final variableMatches = RegExp(r'(?:const|let|var|final|static)\s+(\w+)').allMatches(line);
      for (final match in variableMatches) {
        final variableName = match.group(1)!;
        symbols.add(LocalSymbol(
          name: variableName,
          type: 'variable',
          line: i,
          column: match.start,
        ));
      }
      
      // Extract class declarations
      final classMatches = RegExp(r'class\s+(\w+)\s*(?:extends\s+(\w+))?\s*\{').allMatches(line);
      for (final match in classMatches) {
        final className = match.group(1)!;
        symbols.add(LocalSymbol(
          name: className,
          type: 'class',
          line: i,
          column: match.start,
        ));
      }
    }
    
    return symbols;
  }

  CompletionType _getCompletionType(String symbolType) {
    switch (symbolType) {
      case 'function':
        return CompletionType.function;
      case 'variable':
        return CompletionType.variable;
      case 'class':
        return CompletionType.classType;
      default:
        return CompletionType.snippet;
    }
  }

  Future<List<CodeDefinition>> getDefinitions({
    required String filePath,
    required String code,
    required int line,
    required int column,
    String? language,
  }) async {
    final lang = language ?? _detectLanguage(filePath);
    final profile = _languageProfiles[lang];
    
    if (profile == null) {
      return [];
    }
    
    try {
      final definitions = _findDefinitions(code, line, column, profile);
      
      _emitEvent(IntelligenceEvent(
        type: IntelligenceEventType.definitionsFound,
        filePath: filePath,
        language: lang,
        definitions: definitions,
      ));
      
      return definitions;
      
    } catch (e) {
      developer.log('🧠 Failed to find definitions: $e');
      return [];
    }
  }

  List<CodeDefinition> _findDefinitions(
    String code,
    int line,
    int column,
    LanguageProfile profile,
  ) {
    final definitions = <CodeDefinition>[];
    final lines = code.split('\n');
    final currentLine = line < lines.length ? lines[line] : '';
    
    // Extract word under cursor
    final word = _extractWordUnderCursor(currentLine, column);
    if (word.isEmpty) return definitions;
    
    // Search for function definitions
    for (int i = 0; i < lines.length; i++) {
      final searchLine = lines[i];
      final functionMatches = RegExp(r'(?:\w+\s+)?(\w+)\s*\([^)]*\)\s*(?:async\s*)?\{').allMatches(searchLine);
      
      for (final match in functionMatches) {
        final functionName = match.group(1)!;
        if (functionName == word) {
          definitions.add(CodeDefinition(
            name: word,
            type: 'function',
            filePath: '',
            line: i,
            column: match.start,
            signature: searchLine.trim(),
          ));
        }
      }
    }
    
    // Search for class definitions
    for (int i = 0; i < lines.length; i++) {
      final searchLine = lines[i];
      final classMatches = RegExp(r'class\s+(\w+)\s*(?:extends\s+(\w+))?\s*\{').allMatches(searchLine);
      
      for (final match in classMatches) {
        final className = match.group(1)!;
        if (className == word) {
          definitions.add(CodeDefinition(
            name: word,
            type: 'class',
            filePath: '',
            line: i,
            column: match.start,
            signature: searchLine.trim(),
          ));
        }
      }
    }
    
    return definitions;
  }

  String _extractWordUnderCursor(String line, int column) {
    if (column > line.length) column = line.length;
    
    // Find word boundaries
    int start = column;
    int end = column;
    
    // Find start of word
    while (start > 0 && RegExp(r'\w').hasMatch(line[start - 1])) {
      start--;
    }
    
    // Find end of word
    while (end < line.length && RegExp(r'\w').hasMatch(line[end])) {
      end++;
    }
    
    return line.substring(start, end);
  }

  Future<List<CodeReference>> getReferences({
    required String filePath,
    required String code,
    required int line,
    required int column,
    String? language,
  }) async {
    final lang = language ?? _detectLanguage(filePath);
    final profile = _languageProfiles[lang];
    
    if (profile == null) {
      return [];
    }
    
    try {
      final references = _findReferences(code, line, column, profile);
      
      _emitEvent(IntelligenceEvent(
        type: IntelligenceEventType.referencesFound,
        filePath: filePath,
        language: lang,
        references: references,
      ));
      
      return references;
      
    } catch (e) {
      developer.log('🧠 Failed to find references: $e');
      return [];
    }
  }

  List<CodeReference> _findReferences(
    String code,
    int line,
    int column,
    LanguageProfile profile,
  ) {
    final references = <CodeReference>[];
    final lines = code.split('\n');
    final currentLine = line < lines.length ? lines[line] : '';
    
    // Extract word under cursor
    final word = _extractWordUnderCursor(currentLine, column);
    if (word.isEmpty) return references;
    
    // Search for all occurrences of the word
    final wordRegex = RegExp(r'\b' + RegExp.escape(word) + r'\b');
    
    for (int i = 0; i < lines.length; i++) {
      final searchLine = lines[i];
      final matches = wordRegex.allMatches(searchLine);
      
      for (final match in matches) {
        references.add(CodeReference(
          name: word,
          filePath: '',
          line: i,
          column: match.start,
          context: searchLine.trim(),
        ));
      }
    }
    
    return references;
  }

  Future<List<CodeError>> analyzeCode({
    required String filePath,
    required String code,
    String? language,
  }) async {
    final lang = language ?? _detectLanguage(filePath);
    final profile = _languageProfiles[lang];
    
    if (profile == null) {
      return [];
    }
    
    try {
      final errors = _detectErrors(code, profile);
      
      _errors[filePath] = errors;
      _totalErrors += errors.length;
      
      _emitEvent(IntelligenceEvent(
        type: IntelligenceEventType.errorsDetected,
        filePath: filePath,
        language: lang,
        errors: errors,
      ));
      
      return errors;
      
    } catch (e) {
      developer.log('🧠 Failed to analyze code: $e');
      return [];
    }
  }

  List<CodeError> _detectErrors(String code, LanguageProfile profile) {
    final errors = <CodeError>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Check for syntax errors (basic)
      if (_hasUnmatchedBrackets(line)) {
        errors.add(CodeError(
          type: ErrorType.syntax,
          message: 'Unmatched brackets',
          line: i,
          column: 0,
          severity: ErrorSeverity.error,
        ));
      }
      
      if (_hasUnmatchedQuotes(line)) {
        errors.add(CodeError(
          type: ErrorType.syntax,
          message: 'Unmatched quotes',
          line: i,
          column: 0,
          severity: ErrorSeverity.error,
        ));
      }
      
      // Check for common issues
      if (_hasSemicolonAfterBrace(line)) {
        errors.add(CodeError(
          type: ErrorType.style,
          message: 'Unnecessary semicolon after brace',
          line: i,
          column: 0,
          severity: ErrorSeverity.warning,
        ));
      }
      
      if (_hasUnusedVariable(line, profile)) {
        errors.add(CodeError(
          type: ErrorType.lint,
          message: 'Potentially unused variable',
          line: i,
          column: 0,
          severity: ErrorSeverity.info,
        ));
      }
    }
    
    return errors;
  }

  bool _hasUnmatchedBrackets(String line) {
    int openBrackets = 0;
    int openBraces = 0;
    int openParens = 0;
    
    for (final char in line.split('')) {
      switch (char) {
        case '[':
          openBrackets++;
          break;
        case ']':
          openBrackets--;
          break;
        case '{':
          openBraces++;
          break;
        case '}':
          openBraces--;
          break;
        case '(':
          openParens++;
          break;
        case ')':
          openParens--;
          break;
      }
    }
    
    return openBrackets != 0 || openBraces != 0 || openParens != 0;
  }

  bool _hasUnmatchedQuotes(String line) {
    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    bool escaped = false;
    
    for (final char in line.split('')) {
      if (escaped) {
        escaped = false;
        continue;
      }
      
      if (char == '\\') {
        escaped = true;
        continue;
      }
      
      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }
    }
    
    return inSingleQuote || inDoubleQuote;
  }

  bool _hasSemicolonAfterBrace(String line) {
    return RegExp(r'\}\s*;').hasMatch(line);
  }

  bool _hasUnusedVariable(String line, LanguageProfile profile) {
    // Simple heuristic for unused variables
    final variableMatches = RegExp(r'(?:const|let|var|final|static)\s+(\w+)').allMatches(line);
    
    for (final match in variableMatches) {
      final variableName = match.group(1)!;
      if (!line.contains(RegExp(r'\b' + RegExp.escape(variableName) + r'\b'), match.start + 1)) {
        return true;
      }
    }
    
    return false;
  }

  Future<List<CodeSuggestion>> getSuggestions({
    required String filePath,
    required String code,
    String? language,
  }) async {
    final lang = language ?? _detectLanguage(filePath);
    final profile = _languageProfiles[lang];
    
    if (profile == null) {
      return [];
    }
    
    try {
      final suggestions = _generateSuggestions(code, profile);
      
      _emitEvent(IntelligenceEvent(
        type: IntelligenceEventType.suggestionsGenerated,
        filePath: filePath,
        language: lang,
        suggestions: suggestions,
      ));
      
      return suggestions;
      
    } catch (e) {
      developer.log('🧠 Failed to generate suggestions: $e');
      return [];
    }
  }

  List<CodeSuggestion> _generateSuggestions(String code, LanguageProfile profile) {
    final suggestions = <CodeSuggestion>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Suggest adding missing semicolons
      if (RegExp(r'\w\s*$').hasMatch(line) && !line.endsWith(';')) {
        suggestions.add(CodeSuggestion(
          type: SuggestionType.syntax,
          message: 'Consider adding semicolon',
          line: i,
          column: line.length,
          fix: 'Add semicolon at end of line',
          code: line + ';',
        ));
      }
      
      // Suggest optimizing loops
      if (RegExp(r'for\s*\(\s*.*\s*;\s*.*\s*;\s*\)').hasMatch(line)) {
        suggestions.add(CodeSuggestion(
          type: SuggestionType.optimization,
          message: 'Consider using for...in loop',
          line: i,
          column: 0,
          fix: 'Use more readable loop syntax',
          code: '',
        ));
      }
      
      // Suggest adding comments
      if (line.length > 80 && !line.contains('//') && !line.contains('/*')) {
        suggestions.add(CodeSuggestion(
          type: SuggestionType.style,
          message: 'Consider adding comment for long line',
          line: i,
          column: 0,
          fix: 'Add explanatory comment',
          code: '',
        ));
      }
    }
    
    return suggestions;
  }

  String _detectLanguage(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'dart':
        return 'dart';
      case 'py':
      case 'pyw':
        return 'python';
      case 'js':
      case 'jsx':
      case 'mjs':
        return 'javascript';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'java':
        return 'java';
      case 'cpp':
      case 'cxx':
      case 'cc':
        return 'cpp';
      case 'c':
        return 'c';
      case 'rs':
        return 'rust';
      case 'go':
        return 'go';
      case 'php':
        return 'php';
      case 'rb':
        return 'ruby';
      case 'swift':
        return 'swift';
      case 'kt':
        return 'kotlin';
      case 'scala':
        return 'scala';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'shell';
      default:
        return 'text';
    }
  }

  String _generateCacheKey(String code, int line, int column, String language) {
    final codeHash = code.hashCode;
    return '${codeHash}_${line}_${column}_$language';
  }

  void _emitEvent(IntelligenceEvent event) {
    _intelligenceController.add(event);
  }

  Stream<IntelligenceEvent> get intelligenceEventStream => _intelligenceController.stream;

  CodeIntelligenceStats getStats() {
    return CodeIntelligenceStats(
      totalAnalyses: _totalAnalyses,
      totalCompletions: _totalCompletions,
      totalErrors: _totalErrors,
      cacheSize: _analysisCache.length,
      languageProfiles: _languageProfiles.length,
      patterns: _patterns.length,
    );
  }

  void dispose() {
    _completions.clear();
    _definitions.clear();
    _references.clear();
    _analysisCache.clear();
    _errors.clear();
    _languageProfiles.clear();
    _patterns.clear();
    _intelligenceController.close();
    
    developer.log('🧠 Code Intelligence disposed');
  }
}

class LanguageProfile {
  final String name;
  final List<String> keywords;
  final List<String> types;
  final List<String> functions;
  final List<String> classes;
  final List<CodePattern> patterns;

  LanguageProfile({
    required this.name,
    required this.keywords,
    required this.types,
    required this.functions,
    required this.classes,
    required this.patterns,
  });
}

class CodeCompletion {
  final CompletionType type;
  final String text;
  final String description;
  final int priority;
  final String insertText;
  final String? detail;

  CodeCompletion({
    required this.type,
    required this.text,
    required this.description,
    required this.priority,
    required this.insertText,
    this.detail,
  });
}

class CodeDefinition {
  final String name;
  final String type;
  final String filePath;
  final int line;
  final int column;
  final String signature;

  CodeDefinition({
    required this.name,
    required this.type,
    required this.filePath,
    required this.line,
    required this.column,
    required this.signature,
  });
}

class CodeReference {
  final String name;
  final String filePath;
  final int line;
  final int column;
  final String context;

  CodeReference({
    required this.name,
    required this.filePath,
    required this.line,
    required this.column,
    required this.context,
  });
}

class CodeError {
  final ErrorType type;
  final String message;
  final int line;
  final int column;
  final ErrorSeverity severity;

  CodeError({
    required this.type,
    required this.message,
    required this.line,
    required this.column,
    required this.severity,
  });
}

class CodeSuggestion {
  final SuggestionType type;
  final String message;
  final int line;
  final int column;
  final String fix;
  final String code;

  CodeSuggestion({
    required this.type,
    required this.message,
    required this.line,
    required this.column,
    required this.fix,
    required this.code,
  });
}

class LocalSymbol {
  final String name;
  final String type;
  final int line;
  final int column;

  LocalSymbol({
    required this.name,
    required this.type,
    required this.line,
    required this.column,
  });
}

class CodePattern {
  final PatternType type;
  final String regex;
  final String description;

  CodePattern({
    required this.type,
    required this.regex,
    required this.description,
  });
}

class CodeAnalysis {
  final String filePath;
  final String language;
  final String code;
  final int line;
  final int column;
  final List<CodeCompletion> completions;
  final List<CodeError> errors;
  final List<CodeDefinition> definitions;
  final List<CodeReference> references;
  final DateTime analyzedAt;

  CodeAnalysis({
    required this.filePath,
    required this.language,
    required this.code,
    required this.line,
    required this.column,
    required this.completions,
    required this.errors,
    required this.definitions,
    required this.references,
    required this.analyzedAt,
  });

  bool isExpired() {
    return DateTime.now().difference(analyzedAt).inMinutes > 30;
  }
}

enum CompletionType {
  keyword,
  type,
  function,
  variable,
  classType,
  snippet,
}

enum ErrorType {
  syntax,
  semantic,
  lint,
  style,
}

enum ErrorSeverity {
  error,
  warning,
  info,
  hint,
}

enum SuggestionType {
  syntax,
  optimization,
  style,
  refactoring,
}

enum PatternType {
  classDeclaration,
  functionDeclaration,
  importStatement,
  comment,
  stringLiteral,
  numberLiteral,
  variableDeclaration,
}

enum IntelligenceEventType {
  completionsGenerated,
  definitionsFound,
  referencesFound,
  errorsDetected,
  suggestionsGenerated,
}

class IntelligenceEvent {
  final IntelligenceEventType type;
  final String filePath;
  final String language;
  final List<CodeCompletion>? completions;
  final List<CodeDefinition>? definitions;
  final List<CodeReference>? references;
  final List<CodeError>? errors;
  final List<CodeSuggestion>? suggestions;

  IntelligenceEvent({
    required this.type,
    required this.filePath,
    required this.language,
    this.completions,
    this.definitions,
    this.references,
    this.errors,
    this.suggestions,
  });
}

class CodeIntelligenceStats {
  final int totalAnalyses;
  final int totalCompletions;
  final int totalErrors;
  final int cacheSize;
  final int languageProfiles;
  final int patterns;

  CodeIntelligenceStats({
    required this.totalAnalyses,
    required this.totalCompletions,
    required this.totalErrors,
    required this.cacheSize,
    required this.languageProfiles,
    required this.patterns,
  });
}
