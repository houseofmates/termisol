import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// AI-powered code explanation on hover
/// Provides intelligent code analysis and explanations
class CodeExplainer {
  static const String _baseUrl = 'https://api.openai.com/v1';
  String? _apiKey;
  final Map<String, CodeExplanation> _explanationCache = {};
  final StreamController<ExplanationEvent> _eventController = StreamController<ExplanationEvent>.broadcast();
  
  Stream<ExplanationEvent> get events => _eventController.stream;

  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey ?? _getApiKeyFromConfig();
    
    if (_apiKey != null) {
      _eventController.add(ExplanationEvent(
        type: ExplanationEventType.initialized,
        message: 'Code Explainer initialized with AI API',
      ));
      debugPrint('🧠 Code Explainer initialized');
    } else {
      _eventController.add(ExplanationEvent(
        type: ExplanationEventType.error,
        message: 'No API key provided for code explanation',
      ));
      debugPrint('⚠️ Code Explainer initialized without AI API');
    }
  }

  String? _getApiKeyFromConfig() {
    // Try to get API key from environment or config file
    return Platform.environment['OPENAI_API_KEY'];
  }

  Future<CodeExplanation> explainCode(
    String code, {
    String? language,
    String? context,
    bool useCache = true,
  }) async {
    final cacheKey = _generateCacheKey(code, language, context);
    
    if (useCache && _explanationCache.containsKey(cacheKey)) {
      return _explanationCache[cacheKey]!;
    }

    if (_apiKey == null) {
      return _generateLocalExplanation(code, language: language);
    }

    try {
      final explanation = await _generateAIExplanation(code, language: language, context: context);
      
      _explanationCache[cacheKey] = explanation;
      
      _eventController.add(ExplanationEvent(
        type: ExplanationEventType.explanation_generated,
        message: 'Code explanation generated',
        data: {'language': language, 'codeLength': code.length},
      ));

      return explanation;
    } catch (e) {
      debugPrint('Failed to generate AI explanation: $e');
      return _generateLocalExplanation(code, language: language);
    }
  }

  String _generateCacheKey(String code, String? language, String? context) {
    final combined = '$code|$language|$context';
    return combined.hashCode.toString();
  }

  Future<CodeExplanation> _generateAIExplanation(
    String code, {
    String? language,
    String? context,
  }) async {
    final prompt = _buildPrompt(code, language: language, context: context);
    
    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an expert programmer who provides clear, concise code explanations. Focus on what the code does, why it works that way, and any important patterns or concepts used.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'max_tokens': 500,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final explanation = data['choices'][0]['message']['content'];
      
      return _parseExplanationResponse(explanation, code, language);
    } else {
      throw Exception('Failed to get AI explanation: ${response.statusCode}');
    }
  }

  String _buildPrompt(String code, {String? language, String? context}) {
    var prompt = 'Explain this code';
    
    if (language != null) {
      prompt += ' written in $language';
    }
    
    if (context != null) {
      prompt += ' with the following context: $context';
    }
    
    prompt += ':\n\n```\n$code\n```\n\n';
    prompt += 'Please provide:\n';
    prompt += '1. A brief summary of what this code does\n';
    prompt += '2. Key concepts or patterns used\n';
    prompt += '3. Line-by-line explanation of important parts\n';
    prompt += '4. Any potential issues or improvements\n';
    
    return prompt;
  }

  CodeExplanation _parseExplanationResponse(String response, String code, String? language) {
    final lines = response.split('\n');
    final summary = <String>[];
    final concepts = <String>[];
    final lineExplanations = <String, String>{};
    final issues = <String>[];
    
    String? currentSection;
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('1.') || trimmed.toLowerCase().contains('summary')) {
        currentSection = 'summary';
        continue;
      } else if (trimmed.startsWith('2.') || trimmed.toLowerCase().contains('concept')) {
        currentSection = 'concepts';
        continue;
      } else if (trimmed.startsWith('3.') || trimmed.toLowerCase().contains('line')) {
        currentSection = 'lines';
        continue;
      } else if (trimmed.startsWith('4.') || trimmed.toLowerCase().contains('issue') || trimmed.toLowerCase().contains('improvement')) {
        currentSection = 'issues';
        continue;
      }
      
      if (trimmed.isEmpty) continue;
      
      switch (currentSection) {
        case 'summary':
          summary.add(trimmed);
          break;
        case 'concepts':
          concepts.add(trimmed);
          break;
        case 'lines':
          // Try to extract line number and explanation
          final lineMatch = RegExp(r'(\d+):\s*(.+)').firstMatch(trimmed);
          if (lineMatch != null) {
            lineExplanations[lineMatch.group(1)!] = lineMatch.group(2)!;
          } else {
            lineExplanations['general'] = trimmed;
          }
          break;
        case 'issues':
          issues.add(trimmed);
          break;
      }
    }
    
    return CodeExplanation(
      code: code,
      language: language ?? 'unknown',
      summary: summary.join(' '),
      concepts: concepts,
      lineExplanations: lineExplanations,
      issues: issues,
      generatedAt: DateTime.now(),
      isAI: true,
    );
  }

  CodeExplanation _generateLocalExplanation(String code, {String? language}) {
    final lines = code.split('\n');
    final concepts = <String>[];
    final lineExplanations = <String, String>{};
    
    // Basic pattern recognition
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final lineNumber = (i + 1).toString();
      
      if (line.contains('function') || line.contains('def ') || line.contains('fn ')) {
        concepts.add('Function definition');
        lineExplanations[lineNumber] = 'Defines a function';
      } else if (line.contains('class ')) {
        concepts.add('Class definition');
        lineExplanations[lineNumber] = 'Defines a class';
      } else if (line.contains('if ')) {
        concepts.add('Conditional statement');
        lineExplanations[lineNumber] = 'Conditional logic';
      } else if (line.contains('for ') || line.contains('while ')) {
        concepts.add('Loop');
        lineExplanations[lineNumber] = 'Iteration logic';
      } else if (line.contains('return ')) {
        lineExplanations[lineNumber] = 'Returns a value from function';
      } else if (line.contains('import ') || line.contains('require(')) {
        concepts.add('Module import');
        lineExplanations[lineNumber] = 'Imports external module';
      } else if (line.contains('//') || line.contains('#')) {
        lineExplanations[lineNumber] = 'Comment';
      }
    }
    
    return CodeExplanation(
      code: code,
      language: language ?? 'unknown',
      summary: 'Code written in ${language ?? "unknown language"} with ${concepts.length} identified patterns',
      concepts: concepts,
      lineExplanations: lineExplanations,
      issues: [],
      generatedAt: DateTime.now(),
      isAI: false,
    );
  }

  Future<List<String>> suggestImprovements(String code, {String? language}) async {
    if (_apiKey == null) {
      return _generateLocalImprovements(code, language: language);
    }

    try {
      final prompt = '''
        Analyze this code and suggest specific improvements:
        
        Language: ${language ?? 'unknown'}
        Code:
        ```
        $code
        ```
        
        Focus on:
        1. Performance optimizations
        2. Code readability
        3. Best practices
        4. Security considerations
        5. Error handling
        
        Provide 3-5 specific, actionable suggestions.
      ''';

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content': 'You are an expert code reviewer who provides specific, actionable improvement suggestions.'
            },
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'max_tokens': 400,
          'temperature': 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final suggestions = data['choices'][0]['message']['content'];
        return suggestions.split('\n').where((s) => s.trim().isNotEmpty).toList();
      } else {
        throw Exception('Failed to get AI suggestions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Failed to generate AI suggestions: $e');
      return _generateLocalImprovements(code, language: language);
    }
  }

  List<String> _generateLocalImprovements(String code, {String? language}) {
    final improvements = <String>[];
    final lines = code.split('\n');
    
    // Basic improvement suggestions
    if (!code.contains('try') && !code.contains('catch') && !code.contains('except')) {
      improvements.add('Consider adding error handling with try-catch blocks');
    }
    
    if (code.contains('console.log') || code.contains('print(')) {
      improvements.add('Remove or replace debug logging statements');
    }
    
    if (code.contains('var ') && language == 'dart') {
      improvements.add('Use specific types instead of var in Dart');
    }
    
    if (code.contains('== null') || code.contains('!= null')) {
      improvements.add('Consider using null-aware operators where available');
    }
    
    if (lines.length > 50) {
      improvements.add('Consider breaking this into smaller functions for better maintainability');
    }
    
    if (!code.contains('//') && !code.contains('#') && !code.contains('/*')) {
      improvements.add('Add comments to explain complex logic');
    }
    
    return improvements;
  }

  void clearCache() {
    _explanationCache.clear();
    _eventController.add(ExplanationEvent(
      type: ExplanationEventType.cache_cleared,
      message: 'Code explanation cache cleared',
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'cacheSize': _explanationCache.length,
      'hasApiKey': _apiKey != null,
      'totalExplanations': _explanationCache.length,
    };
  }

  Future<void> dispose() async {
    _eventController.close();
    debugPrint('🧠 Code Explainer disposed');
  }
}

class CodeExplanation {
  final String code;
  final String language;
  final String summary;
  final List<String> concepts;
  final Map<String, String> lineExplanations;
  final List<String> issues;
  final DateTime generatedAt;
  final bool isAI;

  CodeExplanation({
    required this.code,
    required this.language,
    required this.summary,
    required this.concepts,
    required this.lineExplanations,
    required this.issues,
    required this.generatedAt,
    required this.isAI,
  });
}

enum ExplanationEventType {
  initialized,
  explanation_generated,
  cache_cleared,
  error,
}

class ExplanationEvent {
  final ExplanationEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  ExplanationEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Code explanation widget
class CodeExplanationWidget extends StatefulWidget {
  final String code;
  final String? language;
  final String? context;

  const CodeExplanationWidget({
    super.key,
    required this.code,
    this.language,
    this.context,
  });

  @override
  State<CodeExplanationWidget> createState() => _CodeExplanationWidgetState();
}

class _CodeExplanationWidgetState extends State<CodeExplanationWidget> {
  final CodeExplainer _explainer = CodeExplainer();
  CodeExplanation? _explanation;
  bool _isLoading = false;
  bool _showImprovements = false;
  List<String> _improvements = [];

  @override
  void initState() {
    super.initState();
    _loadExplanation();
  }

  Future<void> _loadExplanation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final explanation = await _explainer.explainCode(
        widget.code,
        language: widget.language,
        context: widget.context,
      );
      
      setState(() {
        _explanation = explanation;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadImprovements() async {
    setState(() {
      _showImprovements = true;
    });

    try {
      final improvements = await _explainer.suggestImprovements(
        widget.code,
        language: widget.language,
      );
      
      setState(() {
        _improvements = improvements;
      });
    } catch (e) {
      debugPrint('Failed to load improvements: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Analyzing code...'),
            ],
          ),
        ),
      );
    }

    if (_explanation == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Text('Failed to analyze code'),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(
                  _explanation!.isAI ? Icons.psychology : Icons.code,
                  color: Colors.blue[400],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Code Analysis',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_explanation!.language} • ${_explanation!.isAI ? "AI-powered" : "Local analysis"}',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadExplanation,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary
                  _buildSection('Summary', Icons.summarize, [
                    Text(
                      _explanation!.summary,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ]),
                  
                  const SizedBox(height: 16),
                  
                  // Concepts
                  if (_explanation!.concepts.isNotEmpty) ...[
                    _buildSection('Key Concepts', Icons.lightbulb, [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _explanation!.concepts.map((concept) => Chip(
                          label: Text(concept),
                          backgroundColor: Colors.blue[700],
                          labelStyle: const TextStyle(color: Colors.white),
                        )).toList(),
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Line explanations
                  if (_explanation!.lineExplanations.isNotEmpty) ...[
                    _buildSection('Line-by-Line Explanation', Icons.format_list_numbered, [
                      ..._explanation!.lineExplanations.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.key == 'general' ? 'Note' : 'L${entry.key}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Issues
                  if (_explanation!.issues.isNotEmpty) ...[
                    _buildSection('Potential Issues', Icons.warning, [
                      ..._explanation!.issues.map((issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.orange[400], size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                issue,
                                style: const TextStyle(color: Colors.orange[300], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Improvements button
                  if (_explanation!.isAI) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showImprovements ? null : _loadImprovements,
                        icon: _showImprovements
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.trending_up, size: 16),
                        label: Text(_showImprovements ? 'Loading...' : 'Suggest Improvements'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                        ),
                      ),
                    ),
                    
                    if (_showImprovements && _improvements.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSection('Improvement Suggestions', Icons.trending_up, [
                        ..._improvements.map((improvement) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green[400], size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  improvement,
                                  style: const TextStyle(color: Colors.green[300], fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blue[400], size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}
