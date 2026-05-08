import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Advanced error detection with automatic fixes
/// Provides intelligent error analysis and solutions
class ErrorDetector {
  static const String _baseUrl = 'https://api.openai.com/v1';
  String? _apiKey;
  final Map<String, ErrorFix> _fixCache = {};
  final StreamController<ErrorEvent> _eventController = StreamController<ErrorEvent>.broadcast();
  
  Stream<ErrorEvent> get events => _eventController.stream;

  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey ?? _getApiKeyFromConfig();
    
    if (_apiKey != null) {
      _eventController.add(ErrorEvent(
        type: ErrorEventType.initialized,
        message: 'Error Detector initialized with AI API',
      ));
      debugPrint('🔍 Error Detector initialized');
    } else {
      _eventController.add(ErrorEvent(
        type: ErrorEventType.initialized,
        message: 'Error Detector initialized without AI API',
      ));
      debugPrint('🔍 Error Detector initialized (local mode)');
    }
  }

  String? _getApiKeyFromConfig() {
    return Platform.environment['OPENAI_API_KEY'];
  }

  Future<ErrorAnalysis> analyzeError(
    String error, {
    String? language,
    String? code,
    String? context,
    bool useCache = true,
  }) async {
    final cacheKey = _generateCacheKey(error, language, code, context);
    
    if (useCache && _fixCache.containsKey(cacheKey)) {
      final fix = _fixCache[cacheKey]!;
      return ErrorAnalysis(
        error: error,
        language: language ?? 'unknown',
        severity: fix.severity,
        category: fix.category,
        description: fix.description,
        suggestedFixes: [fix],
        generatedAt: DateTime.now(),
        isAI: fix.isAI,
      );
    }

    if (_apiKey == null) {
      return _generateLocalAnalysis(error, language: language, code: code);
    }

    try {
      final analysis = await _generateAIAnalysis(error, language: language, code: code, context: context);
      
      _fixCache[cacheKey] = analysis.suggestedFixes.first;
      
      _eventController.add(ErrorEvent(
        type: ErrorEventType.error_analyzed,
        message: 'Error analyzed and fix generated',
        data: {
          'error': error,
          'language': language,
          'hasFix': analysis.suggestedFixes.isNotEmpty,
        },
      ));

      return analysis;
    } catch (e) {
      debugPrint('Failed to generate AI analysis: $e');
      return _generateLocalAnalysis(error, language: language, code: code);
    }
  }

  String _generateCacheKey(String error, String? language, String? code, String? context) {
    final combined = '$error|$language|$code|$context';
    return combined.hashCode.toString();
  }

  Future<ErrorAnalysis> _generateAIAnalysis(
    String error, {
    String? language,
    String? code,
    String? context,
  }) async {
    final prompt = _buildAnalysisPrompt(error, language: language, code: code, context: context);
    
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
            'content': 'You are an expert debugger who analyzes errors and provides specific, actionable fixes. Always provide concrete code examples when suggesting fixes.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'max_tokens': 800,
        'temperature': 0.2,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final analysis = data['choices'][0]['message']['content'];
      
      return _parseAnalysisResponse(analysis, error, language);
    } else {
      throw Exception('Failed to get AI analysis: ${response.statusCode}');
    }
  }

  String _buildAnalysisPrompt(String error, {String? language, String? code, String? context}) {
    var prompt = 'Analyze this error';
    
    if (language != null) {
      prompt += ' in $language';
    }
    
    if (context != null) {
      prompt += ' with context: $context';
    }
    
    prompt += ':\n\nError: $error\n';
    
    if (code != null) {
      prompt += '\nCode:\n```\n$code\n```\n';
    }
    
    prompt += '\nPlease provide:\n';
    prompt += '1. Error severity (low/medium/high/critical)\n';
    prompt += '2. Error category (syntax/runtime/logic/configuration/environment)\n';
    prompt += '3. Clear explanation of what went wrong\n';
    prompt += '4. Specific fix with code example\n';
    prompt += '5. Prevention tips\n';
    
    return prompt;
  }

  ErrorAnalysis _parseAnalysisResponse(String response, String error, String? language) {
    final lines = response.split('\n');
    String? severity;
    String? category;
    String? description;
    String? fixCode;
    List<String> preventionTips = [];
    
    String? currentSection;
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('1.') || trimmed.toLowerCase().contains('severity')) {
        currentSection = 'severity';
        continue;
      } else if (trimmed.startsWith('2.') || trimmed.toLowerCase().contains('category')) {
        currentSection = 'category';
        continue;
      } else if (trimmed.startsWith('3.') || trimmed.toLowerCase().contains('explanation')) {
        currentSection = 'description';
        continue;
      } else if (trimmed.startsWith('4.') || trimmed.toLowerCase().contains('fix')) {
        currentSection = 'fix';
        continue;
      } else if (trimmed.startsWith('5.') || trimmed.toLowerCase().contains('prevention')) {
        currentSection = 'prevention';
        continue;
      }
      
      if (trimmed.isEmpty) continue;
      
      switch (currentSection) {
        case 'severity':
          if (trimmed.contains('low')) severity = 'low';
          else if (trimmed.contains('medium')) severity = 'medium';
          else if (trimmed.contains('high')) severity = 'high';
          else if (trimmed.contains('critical')) severity = 'critical';
          break;
        case 'category':
          if (trimmed.contains('syntax')) category = 'syntax';
          else if (trimmed.contains('runtime')) category = 'runtime';
          else if (trimmed.contains('logic')) category = 'logic';
          else if (trimmed.contains('configuration')) category = 'configuration';
          else if (trimmed.contains('environment')) category = 'environment';
          break;
        case 'description':
          description = (description ?? '') + trimmed + ' ';
          break;
        case 'fix':
          if (trimmed.contains('```')) {
            // Extract code block
            final codeMatch = RegExp(r'```(?:\w+)?\n?(.*?)\n?```', dotAll: true).firstMatch(trimmed);
            if (codeMatch != null) {
              fixCode = codeMatch.group(1);
            }
          } else {
            fixCode = (fixCode ?? '') + trimmed + '\n';
          }
          break;
        case 'prevention':
          preventionTips.add(trimmed);
          break;
      }
    }
    
    final errorSeverity = _parseSeverity(severity ?? 'medium');
    final errorCategory = _parseCategory(category ?? 'runtime');
    
    return ErrorAnalysis(
      error: error,
      language: language ?? 'unknown',
      severity: errorSeverity,
      category: errorCategory,
      description: description?.trim() ?? 'Error occurred',
      suggestedFixes: [
        ErrorFix(
          title: 'AI-Generated Fix',
          description: 'Fix based on AI analysis',
          code: fixCode?.trim(),
          severity: errorSeverity,
          category: errorCategory,
          isAI: true,
        ),
      ],
      preventionTips: preventionTips,
      generatedAt: DateTime.now(),
      isAI: true,
    );
  }

  ErrorSeverity _parseSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'low':
        return ErrorSeverity.low;
      case 'medium':
        return ErrorSeverity.medium;
      case 'high':
        return ErrorSeverity.high;
      case 'critical':
        return ErrorSeverity.critical;
      default:
        return ErrorSeverity.medium;
    }
  }

  ErrorCategory _parseCategory(String category) {
    switch (category.toLowerCase()) {
      case 'syntax':
        return ErrorCategory.syntax;
      case 'runtime':
        return ErrorCategory.runtime;
      case 'logic':
        return ErrorCategory.logic;
      case 'configuration':
        return ErrorCategory.configuration;
      case 'environment':
        return ErrorCategory.environment;
      default:
        return ErrorCategory.runtime;
    }
  }

  ErrorAnalysis _generateLocalAnalysis(String error, {String? language, String? code}) {
    final severity = _determineSeverity(error);
    final category = _determineCategory(error);
    final fix = _generateLocalFix(error, category, language: language, code: code);
    
    return ErrorAnalysis(
      error: error,
      language: language ?? 'unknown',
      severity: severity,
      category: category,
      description: _generateDescription(error, category),
      suggestedFixes: [fix],
      preventionTips: _generatePreventionTips(category),
      generatedAt: DateTime.now(),
      isAI: false,
    );
  }

  ErrorSeverity _determineSeverity(String error) {
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('fatal') || lowerError.contains('critical') || lowerError.contains('panic')) {
      return ErrorSeverity.critical;
    } else if (lowerError.contains('error') || lowerError.contains('exception')) {
      return ErrorSeverity.high;
    } else if (lowerError.contains('warning')) {
      return ErrorSeverity.medium;
    } else {
      return ErrorSeverity.low;
    }
  }

  ErrorCategory _determineCategory(String error) {
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('syntax') || lowerError.contains('parse')) {
      return ErrorCategory.syntax;
    } else if (lowerError.contains('null') || lowerError.contains('undefined')) {
      return ErrorCategory.runtime;
    } else if (lowerError.contains('permission') || lowerError.contains('access denied')) {
      return ErrorCategory.environment;
    } else if (lowerError.contains('config') || lowerError.contains('setting')) {
      return ErrorCategory.configuration;
    } else {
      return ErrorCategory.runtime;
    }
  }

  String _generateDescription(String error, ErrorCategory category) {
    switch (category) {
      case ErrorCategory.syntax:
        return 'The code contains a syntax error that prevents it from being parsed correctly.';
      case ErrorCategory.runtime:
        return 'A runtime error occurred during program execution.';
      case ErrorCategory.logic:
        return 'The program logic contains an issue that causes unexpected behavior.';
      case ErrorCategory.configuration:
        return 'There is a configuration problem preventing proper execution.';
      case ErrorCategory.environment:
        return 'An environmental issue is preventing the program from running correctly.';
    }
  }

  ErrorFix _generateLocalFix(String error, ErrorCategory category, {String? language, String? code}) {
    switch (category) {
      case ErrorCategory.syntax:
        return ErrorFix(
          title: 'Fix Syntax Error',
          description: 'Check for missing semicolons, brackets, or quotes',
          code: _generateSyntaxFix(error, language: language, code: code),
          severity: ErrorSeverity.high,
          category: category,
          isAI: false,
        );
      case ErrorCategory.runtime:
        return ErrorFix(
          title: 'Fix Runtime Error',
          description: 'Add proper error handling and null checks',
          code: _generateRuntimeFix(error, language: language, code: code),
          severity: ErrorSeverity.high,
          category: category,
          isAI: false,
        );
      case ErrorCategory.logic:
        return ErrorFix(
          title: 'Fix Logic Error',
          description: 'Review the algorithm and add validation',
          code: _generateLogicFix(error, language: language, code: code),
          severity: ErrorSeverity.medium,
          category: category,
          isAI: false,
        );
      case ErrorCategory.configuration:
        return ErrorFix(
          title: 'Fix Configuration',
          description: 'Check configuration files and environment variables',
          code: _generateConfigFix(error),
          severity: ErrorSeverity.medium,
          category: category,
          isAI: false,
        );
      case ErrorCategory.environment:
        return ErrorFix(
          title: 'Fix Environment Issue',
          description: 'Check file permissions and system requirements',
          code: _generateEnvironmentFix(error),
          severity: ErrorSeverity.medium,
          category: category,
          isAI: false,
        );
    }
  }

  String? _generateSyntaxFix(String error, {String? language, String? code}) {
    if (error.contains('missing semicolon')) {
      return 'Add semicolon at the end of the statement';
    } else if (error.contains('unexpected token')) {
      return 'Check for missing or extra brackets/quotes';
    } else if (error.contains('undefined variable')) {
      return 'Declare the variable before using it';
    }
    return null;
  }

  String? _generateRuntimeFix(String error, {String? language, String? code}) {
    if (error.contains('null') || error.contains('undefined')) {
      return '''
// Add null check
if (variable != null) {
  // Use variable safely
} else {
  // Handle null case
}
''';
    } else if (error.contains('out of bounds')) {
      return '''
// Add bounds checking
if (index >= 0 && index < array.length) {
  // Access array safely
} else {
  // Handle out of bounds
}
''';
    }
    return null;
  }

  String? _generateLogicFix(String error, {String? language, String? code}) {
    return '''
// Add validation and error handling
try {
  // Your logic here
  if (condition) {
    // Handle condition
  }
} catch (e) {
  print('Error: \${e.toString()}');
  // Handle error appropriately
}
''';
  }

  String? _generateConfigFix(String error) {
    return '''
# Check configuration file
config = {
    "setting": "value",
    # Ensure all required settings are present
}

# Verify environment variables
import os
required_vars = ["API_KEY", "DATABASE_URL"]
for var in required_vars:
    if not os.environ.get(var):
        raise ValueError(f"Missing environment variable: {var}")
''';
  }

  String? _generateEnvironmentFix(String error) {
    return '''
# Check file permissions
import os
import stat

file_path = "path/to/file"
if os.path.exists(file_path):
    permissions = stat.filemode(file_path)
    print(f"File permissions: {oct(permissions)}")
    
    # Fix permissions if needed
    os.chmod(file_path, 0o644)
else:
    print("File does not exist")
''';
  }

  List<String> _generatePreventionTips(ErrorCategory category) {
    switch (category) {
      case ErrorCategory.syntax:
        return [
          'Use a linter to catch syntax errors early',
          'Enable syntax highlighting in your editor',
          'Run code through a formatter to catch issues',
        ];
      case ErrorCategory.runtime:
        return [
          'Add comprehensive error handling',
          'Use type checking where available',
          'Test edge cases and boundary conditions',
        ];
      case ErrorCategory.logic:
        return [
          'Write unit tests for critical functions',
          'Use code review to catch logic errors',
          'Add logging to trace execution flow',
        ];
      case ErrorCategory.configuration:
        return [
          'Use configuration validation',
          'Document all configuration options',
          'Use environment-specific config files',
        ];
      case ErrorCategory.environment:
        return [
          'Check system requirements before deployment',
          'Use containerization for consistent environments',
          'Monitor system resources and permissions',
        ];
    }
  }

  Future<List<String>> suggestSimilarErrors(String error) async {
    // This would integrate with a knowledge base or error database for enhanced error analysis
    // For now, return some common similar errors
    final similarErrors = <String>[];
    
    if (error.toLowerCase().contains('null')) {
      similarErrors.addAll([
        'NullPointerException',
        'TypeError: Cannot read property of null',
        'AttributeError: NoneType object',
      ]);
    }
    
    if (error.toLowerCase().contains('permission')) {
      similarErrors.addAll([
        'AccessDeniedException',
        'PermissionError: [Errno 13] Permission denied',
        'File system permission error',
      ]);
    }
    
    return similarErrors;
  }

  void clearCache() {
    _fixCache.clear();
    _eventController.add(ErrorEvent(
      type: ErrorEventType.cache_cleared,
      message: 'Error fix cache cleared',
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'cacheSize': _fixCache.length,
      'hasApiKey': _apiKey != null,
      'totalFixes': _fixCache.length,
    };
  }

  Future<void> dispose() async {
    _eventController.close();
    debugPrint('🔍 Error Detector disposed');
  }
}

class ErrorAnalysis {
  final String error;
  final String language;
  final ErrorSeverity severity;
  final ErrorCategory category;
  final String description;
  final List<ErrorFix> suggestedFixes;
  final List<String> preventionTips;
  final DateTime generatedAt;
  final bool isAI;

  ErrorAnalysis({
    required this.error,
    required this.language,
    required this.severity,
    required this.category,
    required this.description,
    required this.suggestedFixes,
    required this.preventionTips,
    required this.generatedAt,
    required this.isAI,
  });
}

class ErrorFix {
  final String title;
  final String description;
  final String? code;
  final ErrorSeverity severity;
  final ErrorCategory category;
  final bool isAI;

  ErrorFix({
    required this.title,
    required this.description,
    this.code,
    required this.severity,
    required this.category,
    required this.isAI,
  });
}

enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

enum ErrorCategory {
  syntax,
  runtime,
  logic,
  configuration,
  environment,
}

enum ErrorEventType {
  initialized,
  error_analyzed,
  cache_cleared,
  error,
}

class ErrorEvent {
  final ErrorEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  ErrorEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Error detector widget
class ErrorDetectorWidget extends StatefulWidget {
  final String error;
  final String? language;
  final String? code;
  final String? context;

  const ErrorDetectorWidget({
    super.key,
    required this.error,
    this.language,
    this.code,
    this.context,
  });

  @override
  State<ErrorDetectorWidget> createState() => _ErrorDetectorWidgetState();
}

class _ErrorDetectorWidgetState extends State<ErrorDetectorWidget> {
  final ErrorDetector _detector = ErrorDetector();
  ErrorAnalysis? _analysis;
  bool _isLoading = false;
  bool _showSimilarErrors = false;
  List<String> _similarErrors = [];

  @override
  void initState() {
    super.initState();
    _analyzeError();
  }

  Future<void> _analyzeError() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final analysis = await _detector.analyzeError(
        widget.error,
        language: widget.language,
        code: widget.code,
        context: widget.context,
      );
      
      setState(() {
        _analysis = analysis;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSimilarErrors() async {
    setState(() {
      _showSimilarErrors = true;
    });

    try {
      final similar = await _detector.suggestSimilarErrors(widget.error);
      setState(() {
        _similarErrors = similar;
      });
    } catch (e) {
      debugPrint('Failed to load similar errors: $e');
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
              Text('Analyzing error...'),
            ],
          ),
        ),
      );
    }

    if (_analysis == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Text('Failed to analyze error'),
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
              color: _getSeverityColor(_analysis!.severity),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(
                  _getSeverityIcon(_analysis!.severity),
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error Analysis',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_analysis!.severity.name.toUpperCase()} • ${_analysis!.category.name.toUpperCase()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _analyzeError,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-analyze'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
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
                  // Error description
                  _buildSection('Error Description', Icons.info, [
                    Text(
                      _analysis!.description,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        widget.error,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ]),
                  
                  const SizedBox(height: 16),
                  
                  // Suggested fixes
                  if (_analysis!.suggestedFixes.isNotEmpty) ...[
                    _buildSection('Suggested Fixes', Icons.build, [
                      ..._analysis!.suggestedFixes.asMap().entries.map((entry) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green[700]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _analysis!.suggestedFixes[entry.key].isAI
                                      ? Icons.psychology
                                      : Icons.lightbulb,
                                  color: Colors.green[400],
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _analysis!.suggestedFixes[entry.key].title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _analysis!.suggestedFixes[entry.key].description,
                              style: TextStyle(color: Colors.grey[300]),
                            ),
                            if (_analysis!.suggestedFixes[entry.key].code != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  _analysis!.suggestedFixes[entry.key].code!,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Prevention tips
                  if (_analysis!.preventionTips.isNotEmpty) ...[
                    _buildSection('Prevention Tips', Icons.shield, [
                      ..._analysis!.preventionTips.map((tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle, color: Colors.blue[400], size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tip,
                                style: const TextStyle(color: Colors.blue[300], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Similar errors
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showSimilarErrors ? null : _loadSimilarErrors,
                      icon: const Icon(Icons.search, size: 16),
                      label: Text(_showSimilarErrors ? 'Loading...' : 'Find Similar Errors'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                      ),
                    ),
                  ),
                  
                  if (_showSimilarErrors && _similarErrors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSection('Similar Errors', Icons.find_replace, [
                      ..._similarErrors.map((similarError) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          similarError,
                          style: const TextStyle(color: Colors.grey[300], fontSize: 12),
                        ),
                      )),
                    ]),
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

  Color _getSeverityColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Colors.green[700]!;
      case ErrorSeverity.medium:
        return Colors.orange[700]!;
      case ErrorSeverity.high:
        return Colors.red[700]!;
      case ErrorSeverity.critical:
        return Colors.purple[700]!;
    }
  }

  IconData _getSeverityIcon(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Icons.info;
      case ErrorSeverity.medium:
        return Icons.warning;
      case ErrorSeverity.high:
        return Icons.error;
      case ErrorSeverity.critical:
        return Icons.dangerous;
    }
  }
}
