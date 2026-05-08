import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Automatic Error Correction System
/// 
/// Automatically detects and fixes common terminal command errors
/// using AI-powered analysis and pattern recognition.
class AutomaticErrorCorrection {
  static final AutomaticErrorCorrection _instance = AutomaticErrorCorrection._internal();
  factory AutomaticErrorCorrection() => _instance;
  AutomaticErrorCorrection._internal();

  bool _isInitialized = false;
  
  // Error patterns and fixes
  final Map<String, ErrorPattern> _errorPatterns = {};
  final Map<String, CommandFix> _commandFixes = {};
  final List<CorrectionHistory> _correctionHistory = [];
  
  // Learning system
  final Map<String, int> _errorFrequency = {};
  final Map<String, String> _learnedFixes = {};
  
  // Event system
  final _correctionController = StreamController<ErrorCorrectionEvent>.broadcast();
  Stream<ErrorCorrectionEvent> get events => _correctionController.stream;
  
  // Configuration
  static const int _maxHistorySize = 1000;
  static const int _maxLearnedFixes = 500;
  static const double _confidenceThreshold = 0.7;
  
  bool get isInitialized => _isInitialized;
  int get knownPatterns => _errorPatterns.length;
  int get learnedFixesCount => _learnedFixes.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load error patterns
      await _loadErrorPatterns();
      
      // Load command fixes
      await _loadCommandFixes();
      
      // Load learned fixes
      await _loadLearnedFixes();
      
      // Load correction history
      await _loadCorrectionHistory();
      
      _isInitialized = true;
      debugPrint('🔧 Automatic Error Correction initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Automatic Error Correction: $e');
    }
  }

  Future<void> _loadErrorPatterns() async {
    // Initialize common error patterns
    _errorPatterns.addAll({
      'command_not_found': ErrorPattern(
        id: 'command_not_found',
        pattern: RegExp(r'command not found|Command not found|not found'),
        severity: ErrorSeverity.high,
        description: 'Command not found in PATH',
      ),
      'permission_denied': ErrorPattern(
        id: 'permission_denied',
        pattern: RegExp(r'Permission denied|permission denied|Operation not permitted'),
        severity: ErrorSeverity.medium,
        description: 'Insufficient permissions',
      ),
      'file_not_found': ErrorPattern(
        id: 'file_not_found',
        pattern: RegExp(r'No such file or directory|cannot find|File not found'),
        severity: ErrorSeverity.high,
        description: 'File or directory does not exist',
      ),
      'syntax_error': ErrorPattern(
        id: 'syntax_error',
        pattern: RegExp(r'syntax error|Syntax error|unexpected token'),
        severity: ErrorSeverity.high,
        description: 'Command syntax error',
      ),
      'network_error': ErrorPattern(
        id: 'network_error',
        pattern: RegExp(r'Network is unreachable|Connection refused|Host unreachable'),
        severity: ErrorSeverity.medium,
        description: 'Network connectivity issue',
      ),
      'disk_full': ErrorPattern(
        id: 'disk_full',
        pattern: RegExp(r'No space left on device|Disk full|insufficient disk space'),
        severity: ErrorSeverity.critical,
        description: 'Insufficient disk space',
      ),
      'dependency_missing': ErrorPattern(
        id: 'dependency_missing',
        pattern: RegExp(r'module not found|package not found|dependency not found'),
        severity: ErrorSeverity.medium,
        description: 'Missing dependency or module',
      ),
      'port_in_use': ErrorPattern(
        id: 'port_in_use',
        pattern: RegExp(r'Address already in use|Port already in use|already in use'),
        severity: ErrorSeverity.medium,
        description: 'Port already in use',
      ),
    });
    
    debugPrint('🔧 Loaded ${_errorPatterns.length} error patterns');
  }

  Future<void> _loadCommandFixes() async {
    // Initialize command fixes
    _commandFixes.addAll({
      'sudo_fix': CommandFix(
        id: 'sudo_fix',
        originalPattern: RegExp(r'^(?!sudo)(.*)(permission denied|operation not permitted)', caseSensitive: false),
        fixedCommand: 'sudo $1',
        description: 'Add sudo for permission denied errors',
        confidence: 0.9,
      ),
      'path_fix': CommandFix(
        id: 'path_fix',
        originalPattern: RegExp(r'^(\w+)(.*)(command not found)', caseSensitive: false),
        fixedCommand: 'which $1 || echo "Install $1"',
        description: 'Check if command exists and suggest installation',
        confidence: 0.8,
      ),
      'file_path_fix': CommandFix(
        id: 'file_path_fix',
        originalPattern: RegExp(r'^(.*)(no such file or directory)(.*)', caseSensitive: false),
        fixedCommand: 'ls -la $3 && echo "File exists: $3" || echo "Create file: touch $3"',
        description: 'Check file existence and suggest creation',
        confidence: 0.7,
      ),
      'cd_directory_fix': CommandFix(
        id: 'cd_directory_fix',
        originalPattern: RegExp(r'^cd (.+)(no such file or directory)', caseSensitive: false),
        fixedCommand: 'mkdir -p $1 && cd $1',
        description: 'Create directory and change to it',
        confidence: 0.8,
      ),
      'git_add_fix': CommandFix(
        id: 'git_add_fix',
        originalPattern: RegExp(r'^git (?!add)(.*)(nothing to commit|nothing added)', caseSensitive: false),
        fixedCommand: 'git add . && git $1',
        description: 'Add files before git commit',
        confidence: 0.9,
      ),
      'npm_install_fix': CommandFix(
        id: 'npm_install_fix',
        originalPattern: RegExp(r'^(npm run|npm start)(.*)(module not found|cannot find module)', caseSensitive: false),
        fixedCommand: 'npm install && $1 $2',
        description: 'Install npm dependencies before running',
        confidence: 0.9,
      ),
      'docker_build_fix': CommandFix(
        id: 'docker_build_fix',
        originalPattern: RegExp(r'^docker run(.*)(no such file|file not found)', caseSensitive: false),
        fixedCommand: 'docker build -t temp-image . && docker run $1 temp-image',
        description: 'Build Docker image before running',
        confidence: 0.8,
      ),
      'port_kill_fix': CommandFix(
        id: 'port_kill_fix',
        originalPattern: RegExp(r'(.*)(port.*in use|address already in use)', caseSensitive: false),
        fixedCommand: 'lsof -ti:3000 | xargs kill -9 && $1',
        description: 'Kill process using port 3000',
        confidence: 0.7,
      ),
    });
    
    debugPrint('🔧 Loaded ${_commandFixes.length} command fixes');
  }

  Future<void> _loadLearnedFixes() async {
    try {
      final fixesFile = File('${Platform.environment['HOME']}/.termisol/learned_fixes.json');
      if (await fixesFile.exists()) {
        final content = await fixesFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _learnedFixes.addAll(Map<String, String>.from(data['fixes'] ?? {}));
        
        // Limit learned fixes
        if (_learnedFixes.length > _maxLearnedFixes) {
          final entries = _learnedFixes.entries.toList();
          entries.sort((a, b) => a.key.compareTo(b.key));
          _learnedFixes.clear();
          _learnedFixes.addEntries(entries.take(_maxLearnedFixes));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load learned fixes: $e');
    }
  }

  Future<void> _loadCorrectionHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/correction_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['history'] as List)) {
          _correctionHistory.add(CorrectionHistory.fromJson(entry));
        }
        
        // Limit history size
        if (_correctionHistory.length > _maxHistorySize) {
          _correctionHistory.removeRange(0, _correctionHistory.length - _maxHistorySize);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load correction history: $e');
    }
  }

  Future<ErrorCorrectionResult> analyzeAndFixError({
    required String originalCommand,
    required String errorOutput,
    required int exitCode,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      // Detect error pattern
      final errorPattern = _detectErrorPattern(errorOutput);
      if (errorPattern == null) {
        return ErrorCorrectionResult(
          success: false,
          reason: 'No error pattern detected',
          originalCommand: originalCommand,
          errorOutput: errorOutput,
        );
      }
      
      // Track error frequency
      _trackErrorFrequency(errorPattern.id);
      
      // Check for learned fix first
      final learnedFix = _learnedFixes[errorPattern.id];
      if (learnedFix != null) {
        return _applyFix(learnedFix, originalCommand, errorOutput, errorPattern, FixType.learned);
      }
      
      // Find matching command fix
      final commandFix = _findCommandFix(originalCommand, errorOutput);
      if (commandFix != null && commandFix.confidence >= _confidenceThreshold) {
        return _applyFix(commandFix.fixedCommand, originalCommand, errorOutput, errorPattern, FixType.pattern);
      }
      
      // Try AI-powered fix if available
      final aiFix = await _generateAIFix(originalCommand, errorOutput, errorPattern);
      if (aiFix != null) {
        return _applyFix(aiFix, originalCommand, errorOutput, errorPattern, FixType.ai);
      }
      
      return ErrorCorrectionResult(
        success: false,
        reason: 'No suitable fix found',
        originalCommand: originalCommand,
        errorOutput: errorOutput,
        detectedPattern: errorPattern,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to analyze and fix error: $e');
      return ErrorCorrectionResult(
        success: false,
        reason: 'Analysis failed: $e',
        originalCommand: originalCommand,
        errorOutput: errorOutput,
      );
    }
  }

  ErrorPattern? _detectErrorPattern(String errorOutput) {
    for (final pattern in _errorPatterns.values) {
      if (pattern.pattern.hasMatch(errorOutput)) {
        return pattern;
      }
    }
    return null;
  }

  CommandFix? _findCommandFix(String command, String errorOutput) {
    final combinedText = '$command $errorOutput'.toLowerCase();
    
    for (final fix in _commandFixes.values) {
      if (fix.originalPattern.hasMatch(combinedText)) {
        return fix;
      }
    }
    
    return null;
  }

  Future<String?> _generateAIFix(String command, String errorOutput, ErrorPattern pattern) async {
    try {
      // Check if NVIDIA API is available
      final nvidiaKeys = <String>[];
      for (int i = 1; i <= 24; i++) {
        final key = Platform.environment['NVIDIA_API_KEY_$i'];
        if (key != null && key.isNotEmpty) {
          nvidiaKeys.add(key);
        }
      }
      
      if (nvidiaKeys.isEmpty) {
        debugPrint('⚠️ No NVIDIA API keys available for AI error correction');
        return null;
      }
      
      final prompt = _buildAIFixPrompt(command, errorOutput, pattern);
      final apiKey = nvidiaKeys[math.Random().nextInt(nvidiaKeys.length)];
      
      final response = await _callNvidiaAPI(prompt, apiKey);
      final fixCommand = _parseAIFixResponse(response);
      
      if (fixCommand.isNotEmpty) {
        // Learn this fix for future use
        _learnedFixes[pattern.id] = fixCommand;
        await _saveLearnedFixes();
        
        return fixCommand;
      }
    } catch (e) {
      debugPrint('⚠️ AI fix generation failed: $e');
    }
    
    return null;
  }

  String _buildAIFixPrompt(String command, String errorOutput, ErrorPattern pattern) {
    return '''
You are an expert Linux/Unix terminal troubleshooter. Analyze this command error and provide a fix.

ORIGINAL COMMAND: $command
ERROR OUTPUT: $errorOutput
DETECTED ERROR TYPE: ${pattern.description}

TASK: Provide a single, executable command that fixes this error.

RULES:
1. Return ONLY the fixed command, no explanations
2. Ensure the fix is safe and appropriate
3. Use common Linux/Unix tools and commands
4. Consider the specific error type and context
5. If multiple steps are needed, use && or ; to chain them
6. Avoid destructive operations unless necessary

FIXED COMMAND:
''';
  }

  Future<String> _callNvidiaAPI(String prompt, String apiKey) async {
    final url = Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions');
    
    final requestBody = {
      'model': 'deepseek-ai/deepseek-v4-pro',
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'max_tokens': 200,
      'temperature': 0.1,
    };
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    ).timeout(Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List;
      
      if (choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>;
        return message['content'] as String;
      }
    }
    
    throw Exception('API request failed');
  }

  String _parseAIFixResponse(String response) {
    String command = response.trim();
    
    // Remove common prefixes
    command = command.replaceAll(RegExp(r'^(fixed:|command:|fix:)', caseSensitive: false), '');
    
    // Remove markdown code blocks
    command = command.replaceAll(RegExp(r'^```(?:bash|shell)?\s*'), '');
    command = command.replaceAll(RegExp(r'\s*```$'), '');
    
    // Remove quotes
    command = command.replaceAll(RegExp(r'^["\']|["\']$'), '');
    
    return command.trim();
  }

  ErrorCorrectionResult _applyFix(
    String fixedCommand,
    String originalCommand,
    String errorOutput,
    ErrorPattern pattern,
    FixType fixType,
  ) {
    final result = ErrorCorrectionResult(
      success: true,
      fixedCommand: fixedCommand,
      originalCommand: originalCommand,
      errorOutput: errorOutput,
      detectedPattern: pattern,
      fixType: fixType,
      confidence: _calculateConfidence(fixType, pattern),
    );
    
    // Add to history
    _addToHistory(result);
    
    // Emit event
    _correctionController.add(ErrorCorrectionEvent(
      type: ErrorCorrectionEventType.fixApplied,
      result: result,
    ));
    
    return result;
  }

  double _calculateConfidence(FixType fixType, ErrorPattern pattern) {
    switch (fixType) {
      case FixType.learned:
        return 0.9;
      case FixType.pattern:
        return 0.8;
      case FixType.ai:
        return 0.7;
    }
  }

  void _trackErrorFrequency(String errorPatternId) {
    _errorFrequency[errorPatternId] = (_errorFrequency[errorPatternId] ?? 0) + 1;
  }

  void _addToHistory(ErrorCorrectionResult result) {
    final history = CorrectionHistory(
      id: 'correction_${DateTime.now().millisecondsSinceEpoch}',
      originalCommand: result.originalCommand,
      fixedCommand: result.fixedCommand,
      errorOutput: result.errorOutput,
      patternId: result.detectedPattern?.id,
      fixType: result.fixType,
      confidence: result.confidence,
      timestamp: DateTime.now(),
      applied: false,
    );
    
    _correctionHistory.add(history);
    
    // Limit history size
    if (_correctionHistory.length > _maxHistorySize) {
      _correctionHistory.removeAt(0);
    }
  }

  Future<void> applyFix(String correctionId) async {
    try {
      final history = _correctionHistory.where((h) => h.id == correctionId).firstOrNull;
      if (history == null) {
        throw Exception('Correction not found: $correctionId');
      }
      
      // Mark as applied
      history.applied = true;
      await _saveCorrectionHistory();
      
      _correctionController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.fixApplied,
        correctionId: correctionId,
      ));
      
      debugPrint('🔧 Applied fix: ${history.fixedCommand}');
    } catch (e) {
      debugPrint('❌ Failed to apply fix: $e');
    }
  }

  Future<void> learnFix(String errorPatternId, String fixCommand) async {
    _learnedFixes[errorPatternId] = fixCommand;
    await _saveLearnedFixes();
    
    _correctionController.add(ErrorCorrectionEvent(
      type: ErrorCorrectionEventType.fixLearned,
      data: {
        'error_pattern_id': errorPatternId,
        'fix_command': fixCommand,
      },
    ));
    
    debugPrint('🧠 Learned fix for $errorPatternId: $fixCommand');
  }

  Future<void> _saveLearnedFixes() async {
    try {
      final fixesFile = File('${Platform.environment['HOME']}/.termisol/learned_fixes.json');
      await fixesFile.parent.create(recursive: true);
      
      final data = {
        'fixes': _learnedFixes,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await fixesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save learned fixes: $e');
    }
  }

  Future<void> _saveCorrectionHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/correction_history.json');
      await historyFile.parent.create(recursive: true);
      
      final data = {
        'history': _correctionHistory.map((h) => h.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save correction history: $e');
    }
  }

  ErrorCorrectionStatistics getStatistics() {
    final totalCorrections = _correctionHistory.length;
    final appliedCorrections = _correctionHistory.where((h) => h.applied).length;
    final averageConfidence = _correctionHistory.isNotEmpty
        ? _correctionHistory.map((h) => h.confidence).reduce((a, b) => a + b) / _correctionHistory.length
        : 0.0;
    
    final fixTypeDistribution = <FixType, int>{};
    for (final history in _correctionHistory) {
      fixTypeDistribution[history.fixType] = (fixTypeDistribution[history.fixType] ?? 0) + 1;
    }
    
    return ErrorCorrectionStatistics(
      totalCorrections: totalCorrections,
      appliedCorrections: appliedCorrections,
      knownPatterns: _errorPatterns.length,
      learnedFixes: _learnedFixes.length,
      averageConfidence: averageConfidence,
      fixTypeDistribution: fixTypeDistribution,
      mostCommonErrors: _getMostCommonErrors(),
    );
  }

  List<String> _getMostCommonErrors() {
    return _errorFrequency.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        .take(10)
        .map((e) => e.key)
        .toList();
  }

  Future<void> dispose() async {
    _correctionController.close();
    _errorPatterns.clear();
    _commandFixes.clear();
    _correctionHistory.clear();
    _errorFrequency.clear();
    _learnedFixes.clear();
    _isInitialized = false;
    
    debugPrint('🔧 Automatic Error Correction disposed');
  }
}

/// Data classes
class ErrorPattern {
  final String id;
  final RegExp pattern;
  final ErrorSeverity severity;
  final String description;
  
  ErrorPattern({
    required this.id,
    required this.pattern,
    required this.severity,
    required this.description,
  });
}

class CommandFix {
  final String id;
  final RegExp originalPattern;
  final String fixedCommand;
  final String description;
  final double confidence;
  
  CommandFix({
    required this.id,
    required this.originalPattern,
    required this.fixedCommand,
    required this.description,
    required this.confidence,
  });
}

class ErrorCorrectionResult {
  final bool success;
  final String? fixedCommand;
  final String originalCommand;
  final String errorOutput;
  final ErrorPattern? detectedPattern;
  final FixType? fixType;
  final double confidence;
  final String? reason;
  
  ErrorCorrectionResult({
    required this.success,
    this.fixedCommand,
    required this.originalCommand,
    required this.errorOutput,
    this.detectedPattern,
    this.fixType,
    this.confidence = 0.0,
    this.reason,
  });
}

class CorrectionHistory {
  final String id;
  final String originalCommand;
  final String fixedCommand;
  final String errorOutput;
  final String? patternId;
  final FixType fixType;
  final double confidence;
  final DateTime timestamp;
  bool applied;
  
  CorrectionHistory({
    required this.id,
    required this.originalCommand,
    required this.fixedCommand,
    required this.errorOutput,
    this.patternId,
    required this.fixType,
    required this.confidence,
    required this.timestamp,
    required this.applied,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'original_command': originalCommand,
      'fixed_command': fixedCommand,
      'error_output': errorOutput,
      'pattern_id': patternId,
      'fix_type': fixType.toString(),
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'applied': applied,
    };
  }
  
  factory CorrectionHistory.fromJson(Map<String, dynamic> json) {
    return CorrectionHistory(
      id: json['id'],
      originalCommand: json['original_command'],
      fixedCommand: json['fixed_command'],
      errorOutput: json['error_output'],
      patternId: json['pattern_id'],
      fixType: FixType.values.firstWhere((f) => f.toString() == json['fix_type']),
      confidence: json['confidence'],
      timestamp: DateTime.parse(json['timestamp']),
      applied: json['applied'],
    );
  }
}

class ErrorCorrectionEvent {
  final ErrorCorrectionEventType type;
  final ErrorCorrectionResult? result;
  final String? correctionId;
  final Map<String, dynamic>? data;
  
  ErrorCorrectionEvent({
    required this.type,
    this.result,
    this.correctionId,
    this.data,
  });
}

class ErrorCorrectionStatistics {
  final int totalCorrections;
  final int appliedCorrections;
  final int knownPatterns;
  final int learnedFixes;
  final double averageConfidence;
  final Map<FixType, int> fixTypeDistribution;
  final List<String> mostCommonErrors;
  
  ErrorCorrectionStatistics({
    required this.totalCorrections,
    required this.appliedCorrections,
    required this.knownPatterns,
    required this.learnedFixes,
    required this.averageConfidence,
    required this.fixTypeDistribution,
    required this.mostCommonErrors,
  });
}

enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

enum FixType {
  learned,
  pattern,
  ai,
}

enum ErrorCorrectionEventType {
  fixApplied,
  fixLearned,
  fixRejected,
}
