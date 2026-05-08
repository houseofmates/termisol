import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:process_run/process_run.dart';

/// Smart error detection with AI auto-fix system
/// 
/// Features:
/// - AI-powered error detection using NVIDIA NIM models
/// - Automatic error analysis and categorization
/// - Smart fix suggestions with confidence scores
/// - Auto-fix capabilities for common errors
/// - Learning from error patterns and fixes
class SmartErrorDetectionAI {
  static const String _nimEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const int _maxTokens = 4096;
  static const double _temperature = 0.3;

  String? _apiKey;

  final Map<String, ErrorPattern> _errorPatterns = {};
  final Queue<ErrorHistory> _errorHistory = Queue();
  final Map<String, List<FixSuggestion>> _fixCache = {};
  final List<ErrorDetector> _detectors = [];

  bool _isInitialized = false;
  int _totalDetections = 0;
  int _totalFixes = 0;
  int _autoFixes = 0;
  double _totalDetectionTime = 0.0;

  SmartErrorDetectionAI() {
    _loadApiKey();
    _initializeErrorDetection();
  }

  /// Load API key from environment variables.
  /// Hardcoded placeholders are a security risk and have been removed.
  void _loadApiKey() {
    _apiKey = Platform.environment['NVIDIA_NIM_API_KEY'] ??
              Platform.environment['NVIDIA_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('⚠️ NVIDIA NIM API key not configured. Set NVIDIA_NIM_API_KEY or NVIDIA_API_KEY environment variable.');
    }
  }

  bool get _apiKeyConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// Initialize the error detection system
  Future<void> _initializeErrorDetection() async {
    try {
      // Setup built-in error detectors
      _setupErrorDetectors();
      
      // Load common error patterns
      await _loadErrorPatterns();
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize error detection: $e');
    }
  }

  /// Setup built-in error detectors
  void _setupErrorDetectors() {
    _detectors.add(CommandErrorDetector());
    _detectors.add(SyntacticalErrorDetector());
    _detectors.add(FileSystemErrorDetector());
    _detectors.add(NetworkErrorDetector());
    _detectors.add(PermissionErrorDetector());
    _detectors.add(DependencyErrorDetector());
  }

  /// Load common error patterns
  Future<void> _loadErrorPatterns() async {
    // Command not found errors
    _errorPatterns['command_not_found'] = ErrorPattern(
      type: 'command_not_found',
      patterns: [
        RegExp(r'command not found: (.+)', caseSensitive: false),
        RegExp(r'(.+): command not found', caseSensitive: false),
        RegExp(r'bash: (.+): command not found', caseSensitive: false),
      ],
      severity: ErrorSeverity.medium,
      autoFixable: true,
      category: ErrorCategory.command,
    );

    // Permission denied errors
    _errorPatterns['permission_denied'] = ErrorPattern(
      type: 'permission_denied',
      patterns: [
        RegExp(r'permission denied: (.+)', caseSensitive: false),
        RegExp(r'operation not permitted', caseSensitive: false),
        RegExp(r'access denied', caseSensitive: false),
      ],
      severity: ErrorSeverity.medium,
      autoFixable: true,
      category: ErrorCategory.permission,
    );

    // File not found errors
    _errorPatterns['file_not_found'] = ErrorPattern(
      type: 'file_not_found',
      patterns: [
        RegExp(r'no such file or directory: (.+)', caseSensitive: false),
        RegExp(r'cannot access (.+): no such file', caseSensitive: false),
        RegExp(r'file not found: (.+)', caseSensitive: false),
      ],
      severity: ErrorSeverity.low,
      autoFixable: true,
      category: ErrorCategory.fileSystem,
    );

    // Syntax errors
    _errorPatterns['syntax_error'] = ErrorPattern(
      type: 'syntax_error',
      patterns: [
        RegExp(r'syntax error near unexpected token', caseSensitive: false),
        RegExp(r'unexpected token', caseSensitive: false),
        RegExp(r'invalid syntax', caseSensitive: false),
      ],
      severity: ErrorSeverity.high,
      autoFixable: true,
      category: ErrorCategory.syntax,
    );

    // Network errors
    _errorPatterns['network_error'] = ErrorPattern(
      type: 'network_error',
      patterns: [
        RegExp(r'connection (refused|timed out)', caseSensitive: false),
        RegExp(r'network is unreachable', caseSensitive: false),
        RegExp(r'no route to host', caseSensitive: false),
      ],
      severity: ErrorSeverity.medium,
      autoFixable: false,
      category: ErrorCategory.network,
    );

    // Dependency errors
    _errorPatterns['dependency_error'] = ErrorPattern(
      type: 'dependency_error',
      patterns: [
        RegExp(r'module not found: (.+)', caseSensitive: false),
        RegExp(r'cannot find module', caseSensitive: false),
        RegExp(r'dependency not found', caseSensitive: false),
      ],
      severity: ErrorSeverity.medium,
      autoFixable: true,
      category: ErrorCategory.dependency,
    );
  }

  /// Detect and analyze error
  Future<ErrorAnalysis?> detectError(
    String errorOutput,
    String command,
    String workingDirectory,
  ) async {
    if (!_isInitialized) {
      await _initializeErrorDetection();
    }

    _totalDetections++;
    final stopwatch = Stopwatch()..start();

    try {
      // Check cache first
      final cacheKey = _generateCacheKey(errorOutput, command);
      if (_fixCache.containsKey(cacheKey)) {
        final cachedFixes = _fixCache[cacheKey]!;
        return ErrorAnalysis(
          errorOutput: errorOutput,
          command: command,
          detectedError: _detectErrorType(errorOutput),
          fixes: cachedFixes,
          confidence: 0.8,
          source: 'cache',
        );
      }

      // Run through detectors
      ErrorDetection? detection;
      for (final detector in _detectors) {
        detection = await detector.detect(errorOutput, command, workingDirectory);
        if (detection != null) break;
      }

      if (detection == null) {
        // Use AI for unknown errors
      if (_apiKeyConfigured) {
        detection = await _analyzeErrorWithAI(errorOutput, command, workingDirectory);
      }
      }

      if (detection != null) {
        // Generate fix suggestions
        final fixes = await _generateFixes(detection, workingDirectory);
        
        // Cache results
        if (_fixCache.length < 1000) {
          _fixCache[cacheKey] = fixes;
        }

        // Add to history
        _errorHistory.add(ErrorHistory(
          errorOutput: errorOutput,
          command: command,
          detection: detection,
          timestamp: DateTime.now(),
        ));

        _totalDetectionTime += stopwatch.elapsedMilliseconds.toDouble();

        return ErrorAnalysis(
          errorOutput: errorOutput,
          command: command,
          detectedError: detection,
          fixes: fixes,
          confidence: detection.confidence,
          source: detection.source,
        );
      }

      return null;
    } catch (e) {
      debugPrint('Failed to detect error: $e');
      return null;
    } finally {
      stopwatch.stop();
    }
  }

  /// Detect error type using patterns
  ErrorDetection? _detectErrorType(String errorOutput) {
    for (final pattern in _errorPatterns.values) {
      for (final regex in pattern.patterns) {
        final match = regex.firstMatch(errorOutput);
        if (match != null) {
          return ErrorDetection(
            type: pattern.type,
            category: pattern.category,
            severity: pattern.severity,
            confidence: 0.9,
            autoFixable: pattern.autoFixable,
            description: _getErrorDescription(pattern.type),
            source: 'pattern',
            metadata: {
              'matched_text': match.group(0),
              'groups': match.groups,
            },
          );
        }
      }
    }
    return null;
  }

  /// Analyze error with AI
  Future<ErrorDetection?> _analyzeErrorWithAI(
    String errorOutput,
    String command,
    String workingDirectory,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(_nimEndpoint),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': 'nvidia/nemotron-4-340b-instruct',
          'messages': [
            {
              'role': 'system',
              'content': _getErrorAnalysisPrompt(),
            },
            {
              'role': 'user',
              'content:': '''
Error Output: $errorOutput
Command: $command
Working Directory: $workingDirectory

Analyze this error and provide:
1. Error type/category
2. Severity level (low/medium/high/critical)
3. Whether it's auto-fixable
4. Brief description
5. Confidence score (0.0-1.0)

Respond in JSON format:
{
  "type": "error_type",
  "category": "command|syntax|file_system|network|permission|dependency",
  "severity": "low|medium|high|critical",
  "auto_fixable": true/false,
  "description": "Brief description",
  "confidence": 0.8
}''',
            },
          ],
          'max_tokens': _maxTokens,
          'temperature': _temperature,
          'stream': false,
        }),
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        try {
          final analysis = json.decode(content);
          return ErrorDetection(
            type: analysis['type'] as String,
            category: _parseCategory(analysis['category'] as String),
            severity: _parseSeverity(analysis['severity'] as String),
            confidence: (analysis['confidence'] as num).toDouble(),
            autoFixable: analysis['auto_fixable'] as bool,
            description: analysis['description'] as String,
            source: 'ai',
          );
        } catch (e) {
          debugPrint('Failed to parse AI response: $e');
        }
      }
    } catch (e) {
      debugPrint('AI analysis failed: $e');
    }

    return null;
  }

  /// Get error analysis prompt
  String _getErrorAnalysisPrompt() {
    return '''You are an expert error analyzer for terminal commands. Analyze the provided error output and categorize it accurately.

Categories:
- command: Command not found, invalid command
- syntax: Syntax errors, quoting issues
- file_system: File not found, permission issues
- network: Connection errors, network issues
- permission: Access denied, permission errors
- dependency: Missing dependencies, module errors

Severity levels:
- low: Minor issues, easy to fix
- medium: Requires some attention
- high: Serious issues, needs immediate attention
- critical: Blocking issues, prevents work

Be precise and accurate in your analysis.''';
  }

  /// Parse category from string
  ErrorCategory _parseCategory(String category) {
    switch (category.toLowerCase()) {
      case 'command':
        return ErrorCategory.command;
      case 'syntax':
        return ErrorCategory.syntax;
      case 'file_system':
        return ErrorCategory.fileSystem;
      case 'network':
        return ErrorCategory.network;
      case 'permission':
        return ErrorCategory.permission;
      case 'dependency':
        return ErrorCategory.dependency;
      default:
        return ErrorCategory.unknown;
    }
  }

  /// Parse severity from string
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

  /// Generate fix suggestions
  Future<List<FixSuggestion>> _generateFixes(
    ErrorDetection detection,
    String workingDirectory,
  ) async {
    final fixes = <FixSuggestion>[];

    // Generate built-in fixes
    fixes.addAll(_getBuiltinFixes(detection, workingDirectory));

    // Generate AI fixes for complex errors
    if (detection.severity == ErrorSeverity.high || detection.severity == ErrorSeverity.critical) {
      final aiFixes = await _generateAIFixes(detection, workingDirectory);
      fixes.addAll(aiFixes);
    }

    // Sort by confidence
    fixes.sort((a, b) => b.confidence.compareTo(a.confidence));

    return fixes.take(5).toList();
  }

  /// Get built-in fixes
  List<FixSuggestion> _getBuiltinFixes(ErrorDetection detection, String workingDirectory) {
    final fixes = <FixSuggestion>[];

    switch (detection.type) {
      case 'command_not_found':
        fixes.addAll(_getCommandNotFoundFixes(detection));
        break;
      case 'permission_denied':
        fixes.addAll(_getPermissionDeniedFixes(detection));
        break;
      case 'file_not_found':
        fixes.addAll(_getFileNotFoundFixes(detection));
        break;
      case 'syntax_error':
        fixes.addAll(_getSyntaxErrorFixes(detection));
        break;
      case 'network_error':
        fixes.addAll(_getNetworkErrorFixes(detection));
        break;
      case 'dependency_error':
        fixes.addAll(_getDependencyErrorFixes(detection));
        break;
    }

    return fixes;
  }

  /// Get command not found fixes
  List<FixSuggestion> _getCommandNotFoundFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'which \${command}',
        description: 'Check if command exists in PATH',
        autoApply: false,
        confidence: 0.9,
        category: FixCategory.diagnostic,
      ),
      FixSuggestion(
        command: 'sudo apt update && sudo apt install \${command}',
        description: 'Install command using apt',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.installation,
      ),
      FixSuggestion(
        command: 'brew install \${command}',
        description: 'Install command using brew',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.installation,
      ),
      FixSuggestion(
        command: 'pip install \${command}',
        description: 'Install command using pip',
        autoApply: false,
        confidence: 0.6,
        category: FixCategory.installation,
      ),
    ];
  }

  /// Get permission denied fixes
  List<FixSuggestion> _getPermissionDeniedFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'sudo \${command}',
        description: 'Run command with sudo',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.permission,
      ),
      FixSuggestion(
        command: 'chmod +x \${file}',
        description: 'Make file executable',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.permission,
      ),
      FixSuggestion(
        command: 'chown \${user}:\${user} \${file}',
        description: 'Change file ownership',
        autoApply: false,
        confidence: 0.6,
        category: FixCategory.permission,
      ),
    ];
  }

  /// Get file not found fixes
  List<FixSuggestion> _getFileNotFoundFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'ls -la',
        description: 'List files in current directory',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.diagnostic,
      ),
      FixSuggestion(
        command: 'find . -name "\${file}"',
        description: 'Search for file in current directory tree',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.search,
      ),
      FixSuggestion(
        command: 'touch \${file}',
        description: 'Create the missing file',
        autoApply: false,
        confidence: 0.5,
        category: FixCategory.creation,
      ),
    ];
  }

  /// Get syntax error fixes
  List<FixSuggestion> _getSyntaxErrorFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'echo "\${command}"',
        description: 'Check command quoting',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.diagnostic,
      ),
      FixSuggestion(
        command: 'bash -n \${script}',
        description: 'Check script syntax',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.diagnostic,
      ),
    ];
  }

  /// Get network error fixes
  List<FixSuggestion> _getNetworkErrorFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'ping \${host}',
        description: 'Test network connectivity',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.diagnostic,
      ),
      FixSuggestion(
        command: 'curl -I \${url}',
        description: 'Test HTTP connection',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.diagnostic,
      ),
    ];
  }

  /// Get dependency error fixes
  List<FixSuggestion> _getDependencyErrorFixes(ErrorDetection detection) {
    return [
      FixSuggestion(
        command: 'npm install',
        description: 'Install npm dependencies',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.installation,
      ),
      FixSuggestion(
        command: 'pip install -r requirements.txt',
        description: 'Install Python dependencies',
        autoApply: false,
        confidence: 0.8,
        category: FixCategory.installation,
      ),
      FixSuggestion(
        command: 'flutter pub get',
        description: 'Install Flutter dependencies',
        autoApply: false,
        confidence: 0.7,
        category: FixCategory.installation,
      ),
    ];
  }

  /// Generate AI fixes
  Future<List<FixSuggestion>> _generateAIFixes(
    ErrorDetection detection,
    String workingDirectory,
  ) async {
    if (!_apiKeyConfigured) {
      debugPrint('⚠️ AI fix generation skipped: NVIDIA NIM API key not configured');
      return [];
    }
    try {
      final response = await http.post(
        Uri.parse(_nimEndpoint),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': 'nvidia/nemotron-4-340b-instruct',
          'messages': [
            {
              'role': 'system',
              'content:': _getFixGenerationPrompt(),
            },
            {
              'role': 'user',
              'content:': '''
Error Type: ${detection.type}
Category: ${detection.category}
Severity: ${detection.severity}
Description: ${detection.description}

Generate 3 specific fix suggestions with commands that can resolve this error.
Each suggestion should include:
1. The command to run
2. Description of what it does
3. Whether it can be auto-applied
4. Confidence score (0.0-1.0)

Respond in JSON format:
{
  "fixes": [
    {
      "command": "command to run",
      "description": "description",
      "auto_apply": false,
      "confidence": 0.8,
      "category": "diagnostic|fix|installation"
    }
  ]
}''',
            },
          ],
          'max_tokens': _maxTokens,
          'temperature': _temperature,
          'stream': false,
        }),
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        try {
          final analysis = json.decode(content);
          final fixes = <FixSuggestion>[];
          
          for (final fix in analysis['fixes']) {
            fixes.add(FixSuggestion(
              command: fix['command'] as String,
              description: fix['description'] as String,
              autoApply: fix['auto_apply'] as bool,
              confidence: (fix['confidence'] as num).toDouble(),
              category: _parseFixCategory(fix['category'] as String),
            ));
          }
          
          return fixes;
        } catch (e) {
          debugPrint('Failed to parse AI fixes: $e');
        }
      }
    } catch (e) {
      debugPrint('AI fix generation failed: $e');
    }

    return [];
  }

  /// Get fix generation prompt
  String _getFixGenerationPrompt() {
    return '''You are an expert in fixing terminal errors. Generate specific, actionable fix suggestions for the given error.

Fix categories:
- diagnostic: Commands to diagnose the issue
- fix: Commands that directly fix the issue
- installation: Commands to install missing dependencies
- permission: Commands to fix permission issues
- configuration: Commands to fix configuration issues

Make sure commands are practical and safe to run. Avoid destructive operations.''';
  }

  /// Parse fix category
  FixCategory _parseFixCategory(String category) {
    switch (category.toLowerCase()) {
      case 'diagnostic':
        return FixCategory.diagnostic;
      case 'fix':
        return FixCategory.fix;
      case 'installation':
        return FixCategory.installation;
      case 'permission':
        return FixCategory.permission;
      case 'configuration':
        return FixCategory.configuration;
      default:
        return FixCategory.unknown;
    }
  }

  /// Apply fix automatically
  Future<FixResult> applyFix(FixSuggestion fix, String workingDirectory) async {
    if (!fix.autoApply) {
      return FixResult(
        success: false,
        output: 'Fix cannot be auto-applied',
        error: 'Manual intervention required',
      );
    }

    try {
      final result = await run(
        fix.command,
        workingDirectory: workingDirectory,
        timeout: Duration(seconds: 30),
      );

      _totalFixes++;
      if (result.exitCode == 0) {
        _autoFixes++;
      }

      return FixResult(
        success: result.exitCode == 0,
        output: result.stdout,
        error: result.stderr,
        exitCode: result.exitCode,
      );
    } catch (e) {
      return FixResult(
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  /// Get error description
  String _getErrorDescription(String type) {
    switch (type) {
      case 'command_not_found':
        return 'The specified command was not found in the system PATH';
      case 'permission_denied':
        return 'Permission denied - insufficient privileges to perform the operation';
      case 'file_not_found':
        return 'The specified file or directory does not exist';
      case 'syntax_error':
        return 'Syntax error in the command or script';
      case 'network_error':
        return 'Network connectivity issue';
      case 'dependency_error':
        return 'Missing dependency or module';
      default:
        return 'Unknown error occurred';
    }
  }

  /// Generate cache key
  String _generateCacheKey(String errorOutput, String command) {
    return '${errorOutput.hashCode}_${command.hashCode}';
  }

  /// Get detection statistics
  DetectionStats getStats() {
    return DetectionStats(
      totalDetections: _totalDetections,
      totalFixes: _totalFixes,
      autoFixes: _autoFixes,
      autoFixRate: _totalFixes > 0 ? _autoFixes / _totalFixes : 0.0,
      averageDetectionTime: _totalDetections > 0 ? _totalDetectionTime / _totalDetections : 0.0,
      totalDetectionTime: _totalDetectionTime,
      cacheSize: _fixCache.length,
      historySize: _errorHistory.length,
      patternCount: _errorPatterns.length,
    );
  }

  /// Clear cache and history
  void clear() {
    _fixCache.clear();
    _errorHistory.clear();
  }

  /// Dispose error detection system
  void dispose() {
    clear();
  }
}

/// Error analysis result
class ErrorAnalysis {
  final String errorOutput;
  final String command;
  final ErrorDetection? detectedError;
  final List<FixSuggestion> fixes;
  final double confidence;
  final String source;

  const ErrorAnalysis({
    required this.errorOutput,
    required this.command,
    this.detectedError,
    required this.fixes,
    required this.confidence,
    required this.source,
  });
}

/// Error detection result
class ErrorDetection {
  final String type;
  final ErrorCategory category;
  final ErrorSeverity severity;
  final double confidence;
  final bool autoFixable;
  final String description;
  final String source;
  final Map<String, dynamic> metadata;

  const ErrorDetection({
    required this.type,
    required this.category,
    required this.severity,
    required this.confidence,
    required this.autoFixable,
    required this.description,
    required this.source,
    required this.metadata,
  });
}

/// Fix suggestion
class FixSuggestion {
  final String command;
  final String description;
  final bool autoApply;
  final double confidence;
  final FixCategory category;

  const FixSuggestion({
    required this.command,
    required this.description,
    required this.autoApply,
    required this.confidence,
    required this.category,
  });
}

/// Fix result
class FixResult {
  final bool success;
  final String output;
  final String error;
  final int? exitCode;

  const FixResult({
    required this.success,
    required this.output,
    required this.error,
    this.exitCode,
  });
}

/// Error pattern
class ErrorPattern {
  final String type;
  final List<RegExp> patterns;
  final ErrorSeverity severity;
  final bool autoFixable;
  final ErrorCategory category;

  const ErrorPattern({
    required this.type,
    required this.patterns,
    required this.severity,
    required this.autoFixable,
    required this.category,
  });
}

/// Error history
class ErrorHistory {
  final String errorOutput;
  final String command;
  final ErrorDetection detection;
  final DateTime timestamp;

  const ErrorHistory({
    required this.errorOutput,
    required this.command,
    required this.detection,
    required this.timestamp,
  });
}

/// Error detector interface
abstract class ErrorDetector {
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory);
}

/// Command error detector
class CommandErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('command not found') || errorOutput.contains('not found')) {
      return ErrorDetection(
        type: 'command_not_found',
        category: ErrorCategory.command,
        severity: ErrorSeverity.medium,
        confidence: 0.9,
        autoFixable: true,
        description: 'Command not found',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// Syntactical error detector
class SyntacticalErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('syntax error') || errorOutput.contains('unexpected token')) {
      return ErrorDetection(
        type: 'syntax_error',
        category: ErrorCategory.syntax,
        severity: ErrorSeverity.high,
        confidence: 0.8,
        autoFixable: true,
        description: 'Syntax error in command',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// File system error detector
class FileSystemErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('no such file') || errorOutput.contains('file not found')) {
      return ErrorDetection(
        type: 'file_not_found',
        category: ErrorCategory.fileSystem,
        severity: ErrorSeverity.low,
        confidence: 0.9,
        autoFixable: true,
        description: 'File not found',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// Network error detector
class NetworkErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('connection') && (errorOutput.contains('refused') || errorOutput.contains('timed out'))) {
      return ErrorDetection(
        type: 'network_error',
        category: ErrorCategory.network,
        severity: ErrorSeverity.medium,
        confidence: 0.8,
        autoFixable: false,
        description: 'Network connection error',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// Permission error detector
class PermissionErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('permission denied') || errorOutput.contains('access denied')) {
      return ErrorDetection(
        type: 'permission_denied',
        category: ErrorCategory.permission,
        severity: ErrorSeverity.medium,
        confidence: 0.9,
        autoFixable: true,
        description: 'Permission denied',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// Dependency error detector
class DependencyErrorDetector implements ErrorDetector {
  @override
  Future<ErrorDetection?> detect(String errorOutput, String command, String workingDirectory) async {
    if (errorOutput.contains('module not found') || errorOutput.contains('dependency')) {
      return ErrorDetection(
        type: 'dependency_error',
        category: ErrorCategory.dependency,
        severity: ErrorSeverity.medium,
        confidence: 0.8,
        autoFixable: true,
        description: 'Missing dependency',
        source: 'detector',
        metadata: {},
      );
    }
    return null;
  }
}

/// Error categories
enum ErrorCategory {
  command,
  syntax,
  fileSystem,
  network,
  permission,
  dependency,
  unknown,
}

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// Fix categories
enum FixCategory {
  diagnostic,
  fix,
  installation,
  permission,
  configuration,
  creation,
  search,
  unknown,
}

/// Detection statistics
class DetectionStats {
  final int totalDetections;
  final int totalFixes;
  final int autoFixes;
  final double autoFixRate;
  final double averageDetectionTime;
  final double totalDetectionTime;
  final int cacheSize;
  final int historySize;
  final int patternCount;

  const DetectionStats({
    required this.totalDetections,
    required this.totalFixes,
    required this.autoFixes,
    required this.autoFixRate,
    required this.averageDetectionTime,
    required this.totalDetectionTime,
    required this.cacheSize,
    required this.historySize,
    required this.patternCount,
  });
}
