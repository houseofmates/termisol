import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Code Intelligence stub.
class CodeIntelligence {
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    _isInitialized = true;
  }

  Future<Map<String, dynamic>> analyzeFile(String path) async {
    return {};
  }

  Future<double> estimateCodeQuality(String path) async {
    return 1.0;
  }

  void dispose() {}
}

class CodeSymbol {
  final String name;
  final String type;
  final int line;

  CodeSymbol({required this.name, required this.type, required this.line});
}

class CodeAnalysisResult {
  final String? error;
  final int lineCount;
  final int charCount;
  final int sizeBytes;
  final List<CodeSymbol> functions;
  final List<CodeSymbol> classes;
  final List<String> imports;
  final List<String> exports;
  final List<LintResult> lints;
  final double complexity;
  final int blankLines;
  final int commentLines;
  final int longestLine;

  CodeAnalysisResult({
    this.error,
    this.lineCount = 0,
    this.charCount = 0,
    this.sizeBytes = 0,
    this.functions = const [],
    this.classes = const [],
    this.imports = const [],
    this.exports = const [],
    this.lints = const [],
    this.complexity = 0,
    this.blankLines = 0,
    this.commentLines = 0,
    this.longestLine = 0,
  });
}

class LintResult {
  final String rule;
  final String message;
  final LintSeverity severity;
  final int line;

  LintResult({
    required this.rule,
    required this.message,
    this.severity = LintSeverity.warning,
    this.line = 0,
  });
}

enum LintSeverity { info, warning, error }
