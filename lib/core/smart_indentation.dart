import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

class SmartIndentation {
  static const int _defaultIndentSize = 2;
  static const String _defaultIndentType = 'spaces';
  static const int _maxIndentLevel = 20;
  
  final Map<String, IndentProfile> _languageProfiles = {};
  final Map<String, List<String>> _fileExtensions = {};
  final List<IndentRule> _indentRules = [];
  final Map<String, int> _fileIndentLevels = {};
  
  void initialize() {
    _initializeLanguageProfiles();
    _initializeIndentRules();
    developer.log('📝 Smart Indentation initialized');
  }

  void _initializeLanguageProfiles() {
    // Dart
    _languageProfiles['dart'] = IndentProfile(
      language: 'dart',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'class': 0,
        'method': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'try': 1,
        'catch': 1,
        'finally': 1,
        'switch': 1,
        'case': 2,
      },
    );
    
    // Python
    _languageProfiles['python'] = IndentProfile(
      language: 'python',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: {
        'class': 0,
        'def': 1,
        'if': 1,
        'elif': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'try': 1,
        'except': 1,
        'finally': 1,
        'with': 1,
        'async': 1,
        'await': 2,
      },
    );
    
    // JavaScript/TypeScript
    _languageProfiles['javascript'] = IndentProfile(
      language: 'javascript',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'function': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'try': 1,
        'catch': 1,
        'finally': 1,
        'switch': 1,
        'case': 2,
        'default': 1,
        'class': 1,
        'method': 1,
      },
    );
    
    _languageProfiles['typescript'] = IndentProfile(
      language: 'typescript',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: _languageProfiles['javascript']!.patterns,
    );
    
    // Java
    _languageProfiles['java'] = IndentProfile(
      language: 'java',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: {
        'class': 0,
        'method': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'try': 1,
        'catch': 1,
        'finally': 1,
        'switch': 1,
        'case': 2,
        'default': 1,
      },
    );
    
    // C/C++
    _languageProfiles['c'] = IndentProfile(
      language: 'c',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: {
        'function': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'try': 1,
        'catch': 1,
        'finally': 1,
        'switch': 1,
        'case': 2,
        'default': 1,
      },
    );
    
    _languageProfiles['cpp'] = IndentProfile(
      language: 'cpp',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: _languageProfiles['c']!.patterns,
    );
    
    // Rust
    _languageProfiles['rust'] = IndentProfile(
      language: 'rust',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: {
        'fn': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'loop': 1,
        'match': 1,
        'impl': 1,
        'struct': 0,
        'enum': 0,
        'trait': 0,
      },
    );
    
    // Go
    _languageProfiles['go'] = IndentProfile(
      language: 'go',
      indentSize: 4,
      indentType: 'tabs',
      continuationIndentSize: 8,
      patterns: {
        'func': 1,
        'if': 1,
        'else': 1,
        'for': 1,
        'switch': 1,
        'case': 2,
        'default': 1,
        'select': 1,
        'type': 0,
        'struct': 0,
        'interface': 0,
      },
    );
    
    // Shell scripts
    _languageProfiles['bash'] = IndentProfile(
      language: 'bash',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 4,
      patterns: {
        'if': 1,
        'then': 1,
        'else': 1,
        'elif': 1,
        'for': 1,
        'while': 1,
        'case': 2,
        'function': 1,
      },
    );
    
    _languageProfiles['zsh'] = IndentProfile(
      language: 'zsh',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 4,
      patterns: _languageProfiles['bash']!.patterns,
    );
    
    _languageProfiles['fish'] = IndentProfile(
      language: 'fish',
      indentSize: 4,
      indentType: 'spaces',
      continuationIndentSize: 8,
      patterns: {
        'if': 1,
        'else': 1,
        'for': 1,
        'while': 1,
        'function': 1,
        'case': 2,
      },
    );
    
    // YAML
    _languageProfiles['yaml'] = IndentProfile(
      language: 'yaml',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'list': 1,
        'mapping': 1,
        'sequence': 1,
      },
    );
    
    // JSON
    _languageProfiles['json'] = IndentProfile(
      language: 'json',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'object': 1,
        'array': 1,
      },
    );
    
    // HTML
    _languageProfiles['html'] = IndentProfile(
      language: 'html',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'tag': 1,
        'attribute': 2,
      },
    );
    
    // CSS
    _languageProfiles['css'] = IndentProfile(
      language: 'css',
      indentSize: 2,
      indentType: 'spaces',
      continuationIndentSize: 2,
      patterns: {
        'selector': 0,
        'property': 1,
        'media': 1,
      },
    );
  }

  void _initializeIndentRules() {
    // File extension mappings
    _fileExtensions['dart'] = ['dart'];
    _fileExtensions['python'] = ['py', 'pyw'];
    _fileExtensions['javascript'] = ['js', 'jsx', 'mjs'];
    _fileExtensions['typescript'] = ['ts', 'tsx'];
    _fileExtensions['java'] = ['java'];
    _fileExtensions['c'] = ['c', 'h'];
    _fileExtensions['cpp'] = ['cpp', 'cxx', 'cc', 'hpp', 'hxx'];
    _fileExtensions['rust'] = ['rs'];
    _fileExtensions['go'] = ['go'];
    _fileExtensions['bash'] = ['sh', 'bash', 'ksh'];
    _fileExtensions['zsh'] = ['zsh'];
    _fileExtensions['fish'] = ['fish'];
    _fileExtensions['yaml'] = ['yaml', 'yml'];
    _fileExtensions['json'] = ['json'];
    _fileExtensions['html'] = ['html', 'htm'];
    _fileExtensions['css'] = ['css', 'scss', 'sass'];
    
    // Smart indent rules
    _indentRules.addAll([
      IndentRule(
        pattern: RegExp(r'^\s*class\s+\w+'),
        type: IndentRuleType.blockStart,
        language: 'dart',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*def\s+\w+'),
        type: IndentRuleType.blockStart,
        language: 'python',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*function\s+\w+'),
        type: IndentRuleType.blockStart,
        language: 'javascript',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*if\s+'),
        type: IndentRuleType.blockStart,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*for\s+'),
        type: IndentRuleType.blockStart,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*while\s+'),
        type: IndentRuleType.blockStart,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*try\s*'),
        type: IndentRuleType.blockStart,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*catch\s*'),
        type: IndentRuleType.blockEnd,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*finally\s*'),
        type: IndentRuleType.blockEnd,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*else\s*'),
        type: IndentRuleType.blockEnd,
        language: 'all',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*}\s*$'),
        type: IndentRuleType.blockEnd,
        language: 'bracket',
      ),
      IndentRule(
        pattern: RegExp(r'^\s*\)\s*$'),
        type: IndentRuleType.blockEnd,
        language: 'parenthesis',
      ),
    ]);
  }

  String detectLanguage(String filePath) {
    final extension = _getFileExtension(filePath);
    
    for (final entry in _fileExtensions.entries) {
      if (entry.value.contains(extension)) {
        return entry.key;
      }
    }
    
    // Try content-based detection
    return _detectLanguageByContent(filePath);
  }

  String _getFileExtension(String filePath) {
    final parts = filePath.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  String _detectLanguageByContent(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return '';
      
      final content = file.readAsStringSync();
      
      // Check for language-specific patterns
      if (RegExp(r'^\s*import\s+["\']dart:').hasMatch(content)) {
        return 'dart';
      }
      
      if (RegExp(r'^\s*#!/usr/bin/(python|python3)').hasMatch(content) ||
          RegExp(r'^\s*(import|from)\s+\w+').hasMatch(content)) {
        return 'python';
      }
      
      if (RegExp(r'^\s*(var|let|const)\s+\w+').hasMatch(content) ||
          RegExp(r'function\s+\w+').hasMatch(content)) {
        return 'javascript';
      }
      
      if (RegExp(r'^\s*package\s+\w+').hasMatch(content) ||
          RegExp(r'^\s*import\s+java\.').hasMatch(content)) {
        return 'java';
      }
      
      if (RegExp(r'^\s*#include\s+').hasMatch(content) ||
          RegExp(r'^\s*int\s+main\s*\(').hasMatch(content)) {
        return 'c';
      }
      
      if (RegExp(r'^\s*fn\s+\w+').hasMatch(content) ||
          RegExp(r'^\s*use\s+').hasMatch(content)) {
        return 'rust';
      }
      
      if (RegExp(r'^\s*package\s+main').hasMatch(content) ||
          RegExp(r'^\s*func\s+\w+').hasMatch(content)) {
        return 'go';
      }
      
      if (RegExp(r'^\s*#!/bin/(ba)?sh').hasMatch(content)) {
        return 'bash';
      }
      
      if (RegExp(r'^\s*#!/bin/zsh').hasMatch(content)) {
        return 'zsh';
      }
      
      if (RegExp(r'^\s*#!/usr/bin/fish').hasMatch(content)) {
        return 'fish';
      }
      
      if (RegExp(r'^\s*---\s*$').hasMatch(content) ||
          RegExp(r'^\s*\w+:').hasMatch(content)) {
        return 'yaml';
      }
      
      if (RegExp(r'^\s*\{').hasMatch(content) ||
          RegExp(r'^\s*\[').hasMatch(content)) {
        return 'json';
      }
      
      if (RegExp(r'^\s*<!DOCTYPE|<[hH][tT][mM][lL]').hasMatch(content)) {
        return 'html';
      }
      
      if (RegExp(r'^\s*[a-zA-Z-]+\s*\{').hasMatch(content)) {
        return 'css';
      }
      
    } catch (e) {
      developer.log('📝 Failed to detect language by content: $e');
    }
    
    return '';
  }

  String getIndentForLine(String line, String language, int currentIndentLevel) {
    final profile = _languageProfiles[language];
    if (profile == null) {
      return _getDefaultIndent(currentIndentLevel);
    }
    
    // Check if line should be indented
    final shouldIndent = _shouldIndentLine(line, language);
    final shouldDedent = _shouldDedentLine(line, language);
    
    if (shouldDedent) {
      return _getDefaultIndent((currentIndentLevel - 1).clamp(0, _maxIndentLevel));
    }
    
    if (shouldIndent) {
      final indentLevel = _calculateIndentLevel(line, language, currentIndentLevel);
      return _getDefaultIndent(indentLevel);
    }
    
    return _getDefaultIndent(currentIndentLevel);
  }

  bool _shouldIndentLine(String line, String language) {
    line = line.trimRight();
    
    // Check against indent rules
    for (final rule in _indentRules) {
      if (rule.language == language || rule.language == 'all') {
        if (rule.type == IndentRuleType.blockStart && rule.pattern.hasMatch(line)) {
          return true;
        }
      }
    }
    
    // Language-specific patterns
    switch (language) {
      case 'python':
        return RegExp(r'^\s*(if|elif|else|for|while|try|except|finally|with|def|class)\b').hasMatch(line) &&
               !line.endsWith(':');
      case 'dart':
        return RegExp(r'^\s*(class|if|else|for|while|try|catch|finally|switch|case)\b').hasMatch(line) &&
               !RegExp(r'\{$').hasMatch(line);
      case 'javascript':
      case 'typescript':
        return RegExp(r'^\s*(function|if|else|for|while|try|catch|finally|switch|case|class)\b').hasMatch(line) &&
               !RegExp(r'\{$').hasMatch(line);
      case 'java':
      case 'c':
      case 'cpp':
      case 'rust':
      case 'go':
        return RegExp(r'^\s*(if|else|for|while|try|catch|finally|switch|case|fn|func|class|struct|enum|trait|impl)\b').hasMatch(line) &&
               !RegExp(r'\{$').hasMatch(line);
      case 'yaml':
        return RegExp(r'^\s*[-:]\s').hasMatch(line) && line.endsWith(':');
      case 'json':
        return RegExp(r'^\s*["\']?\w+\s*:').hasMatch(line) && line.contains(':');
      case 'html':
        return RegExp(r'^\s*<[^/][^>]*[^/]>$').hasMatch(line) && !line.contains('/>');
      case 'css':
        return RegExp(r'^\s*[a-zA-Z-]+\s*\{').hasMatch(line);
      case 'bash':
      case 'zsh':
      case 'fish':
        return RegExp(r'^\s*(if|then|else|elif|for|while|case|function)\b').hasMatch(line);
    }
    
    return false;
  }

  bool _shouldDedentLine(String line, String language) {
    line = line.trimRight();
    
    // Check against dedent rules
    for (final rule in _indentRules) {
      if (rule.language == language || rule.language == 'all') {
        if (rule.type == IndentRuleType.blockEnd && rule.pattern.hasMatch(line)) {
          return true;
        }
      }
    }
    
    // Language-specific patterns
    switch (language) {
      case 'python':
        return RegExp(r'^\s*(elif|else|except|finally)\b').hasMatch(line);
      case 'dart':
      case 'javascript':
      case 'typescript':
      case 'java':
      case 'c':
      case 'cpp':
      case 'rust':
      case 'go':
        return RegExp(r'^\s*\}').hasMatch(line) ||
               RegExp(r'^\s*(else|catch|finally|case|default)\b').hasMatch(line);
      case 'yaml':
        return false; // YAML doesn't dedent in the same way
      case 'json':
        return RegExp(r'^\s*\}|\]').hasMatch(line);
      case 'html':
        return RegExp(r'^\s*</[^>]+>').hasMatch(line);
      case 'css':
        return RegExp(r'^\s*\}').hasMatch(line);
      case 'bash':
      case 'zsh':
      case 'fish':
        return RegExp(r'^\s*(else|elif|esac|fi|done)\b').hasMatch(line);
    }
    
    return false;
  }

  int _calculateIndentLevel(String line, String language, int currentLevel) {
    final profile = _languageProfiles[language];
    if (profile == null) return currentLevel;
    
    // Determine indent level based on pattern
    for (final entry in profile.patterns.entries) {
      final pattern = entry.key;
      final level = entry.value;
      
      if (RegExp(r'\b$pattern\b').hasMatch(line)) {
        return (currentLevel + level).clamp(0, _maxIndentLevel);
      }
    }
    
    return currentLevel + 1;
  }

  String _getDefaultIndent(int level) {
    if (level <= 0) return '';
    
    final indentChar = _defaultIndentType == 'tabs' ? '\t' : ' ';
    final indentSize = _defaultIndentSize;
    
    return indentChar * (level * indentSize);
  }

  String getIndentString(String language, int level) {
    final profile = _languageProfiles[language];
    if (profile == null) {
      return _getDefaultIndent(level);
    }
    
    final indentChar = profile.indentType == 'tabs' ? '\t' : ' ';
    final indentSize = profile.indentSize;
    
    return indentChar * (level * indentSize);
  }

  String autoIndentLine(String line, String language, int currentIndentLevel) {
    // Remove existing indentation
    final trimmedLine = line.replaceFirst(RegExp(r'^\s+'), '');
    
    // Calculate new indentation
    final newIndentLevel = _calculateIndentLevel(trimmedLine, language, currentIndentLevel);
    final newIndent = getIndentString(language, newIndentLevel);
    
    return '$newIndent$trimmedLine';
  }

  List<String> autoIndentLines(List<String> lines, String language) {
    final indentedLines = <String>[];
    int currentIndentLevel = 0;
    
    for (final line in lines) {
      final trimmedLine = line.trimRight();
      
      if (trimmedLine.isEmpty) {
        indentedLines.add(line);
        continue;
      }
      
      // Calculate indent for this line
      final indent = getIndentForLine(line, language, currentIndentLevel);
      final trimmedWithoutIndent = line.replaceFirst(RegExp(r'^\s+'), '');
      
      final newLine = '$indent$trimmedWithoutIndent';
      indentedLines.add(newLine);
      
      // Update current indent level
      currentIndentLevel = _updateIndentLevel(trimmedWithoutIndent, language, currentIndentLevel);
    }
    
    return indentedLines;
  }

  int _updateIndentLevel(String line, String language, int currentLevel) {
    if (_shouldDedentLine(line, language)) {
      return (currentLevel - 1).clamp(0, _maxIndentLevel);
    }
    
    if (_shouldIndentLine(line, language)) {
      final newLevel = _calculateIndentLevel(line, language, currentLevel);
      return newLevel.clamp(0, _maxIndentLevel);
    }
    
    return currentLevel;
  }

  void setFileIndentLevel(String filePath, int indentLevel) {
    _fileIndentLevels[filePath] = indentLevel.clamp(0, _maxIndentLevel);
  }

  int getFileIndentLevel(String filePath) {
    return _fileIndentLevels[filePath] ?? 0;
  }

  IndentProfile? getLanguageProfile(String language) {
    return _languageProfiles[language];
  }

  Map<String, dynamic> getIndentationStats(String filePath) {
    final language = detectLanguage(filePath);
    final profile = getLanguageProfile(language);
    final currentLevel = getFileIndentLevel(filePath);
    
    return {
      'language': language,
      'profile': profile?.toJson(),
      'currentLevel': currentLevel,
      'indentString': getIndentString(language, currentLevel),
    };
  }

  void dispose() {
    _languageProfiles.clear();
    _fileExtensions.clear();
    _indentRules.clear();
    _fileIndentLevels.clear();
    developer.log('📝 Smart Indentation disposed');
  }
}

class IndentProfile {
  final String language;
  final int indentSize;
  final String indentType;
  final int continuationIndentSize;
  final Map<String, int> patterns;

  IndentProfile({
    required this.language,
    required this.indentSize,
    required this.indentType,
    required this.continuationIndentSize,
    required this.patterns,
  });

  Map<String, dynamic> toJson() {
    return {
      'language': language,
      'indentSize': indentSize,
      'indentType': indentType,
      'continuationIndentSize': continuationIndentSize,
      'patterns': patterns,
    };
  }
}

class IndentRule {
  final RegExp pattern;
  final IndentRuleType type;
  final String language;

  IndentRule({
    required this.pattern,
    required this.type,
    required this.language,
  });
}

enum IndentRuleType {
  blockStart,
  blockEnd,
  continuation,
}
