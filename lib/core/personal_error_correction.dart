import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Personal error correction patterns with amnesia-proof persistence
/// 
/// Features:
/// - Personalized error patterns
/// - Context-aware responses based on projects (.233, .250)
/// - Machine learning of user's error handling
/// - Automatic fix suggestions
/// - Persistent storage that survives amnesia
class PersonalErrorCorrection {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<ErrorCorrectionEvent> _eventController = StreamController<ErrorCorrectionEvent>.broadcast();
  
  final List<PersonalErrorPattern> _personalPatterns = [];
  final Map<String, ErrorContext> _errorContexts = {};
  final Map<String, List<PersonalFix>> _fixHistory = {};
  final Map<String, UserErrorPreference> _userPreferences = {};
  
  Timer? _analysisTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<ErrorCorrectionEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  PersonalErrorCorrection({this.aiAssistant});
  
  /// Initialize personal error correction system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Start analysis timer
      _analysisTimer = Timer.periodic(const Duration(minutes: 3), (_) {
        _analyzeErrorPatterns();
      });
      
      _isInitialized = true;
      
      _eventController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.initialized,
        message: 'Personal error correction system initialized',
        data: {'patterns_count': _personalPatterns.length},
      ));
    } catch (e) {
      _eventController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.error,
        message: 'Failed to initialize error correction: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Record error occurrence
  void recordError(String command, String error, {String? project, String? workingDirectory}) {
    final context = ErrorContext(
      command: command,
      error: error,
      project: project ?? _extractProjectFromPath(workingDirectory),
      workingDirectory: workingDirectory,
      timestamp: DateTime.now(),
      environment: _extractEnvironment(workingDirectory),
    );
    
    // Analyze error pattern
    final pattern = _analyzeErrorPattern(context);
    
    // Get personalized fixes
    final fixes = _getPersonalizedFixes(pattern, context);
    
    // Record the error
    final errorRecord = PersonalErrorRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      context: context,
      pattern: pattern,
      fixes: fixes,
      resolved: false,
    );
    
    // Update user preferences based on this error
    _updateUserPreferences(context, fixes);
    
    // Persist immediately for amnesia protection
    _persistErrorImmediately(errorRecord);
    
    _eventController.add(ErrorCorrectionEvent(
      type: ErrorCorrectionEventType.error_recorded,
      message: 'Personal error recorded',
      data: {'error': errorRecord.toJson()},
    ));
  }
  
  String _extractProjectFromPath(String? path) {
    if (path == null) return 'unknown';
    
    if (path.contains('.233')) return 'server_233';
    if (path.contains('.250')) return 'server_250';
    if (path.contains('termisol')) return 'development';
    if (path.contains('Documents')) return 'documents';
    if (path.contains('Downloads')) return 'downloads';
    
    return 'unknown';
  }
  
  String _extractEnvironment(String? path) {
    if (path == null) return 'unknown';
    
    if (path.contains('/home/house/')) return 'local';
    if (path.contains('192.168.')) return 'remote';
    if (path.contains('ssh://')) return 'ssh';
    
    return 'unknown';
  }
  
  PersonalErrorPattern _analyzeErrorPattern(ErrorContext context) {
    // Check existing patterns
    for (final pattern in _personalPatterns) {
      if (_matchesPattern(context, pattern)) {
        return pattern;
      }
    }
    
    // Create new pattern
    final newPattern = PersonalErrorPattern(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      commandPattern: _extractCommandPattern(context.command),
      errorPattern: _extractErrorPattern(context.error),
      projectContext: context.project,
      environmentContext: context.environment,
      frequency: 1,
      confidence: 0.5,
      fixes: [],
      lastSeen: context.timestamp,
    );
    
    _personalPatterns.add(newPattern);
    
    // Limit patterns
    if (_personalPatterns.length > 500) {
      _personalPatterns.removeLast();
    }
    
    return newPattern;
  }
  
  bool _matchesPattern(ErrorContext context, PersonalErrorPattern pattern) {
    // Check if error matches existing pattern
    final commandMatch = _patternMatches(context.command, pattern.commandPattern);
    final errorMatch = _patternMatches(context.error, pattern.errorPattern);
    final projectMatch = context.project == pattern.projectContext;
    final environmentMatch = context.environment == pattern.environmentContext;
    
    return commandMatch && errorMatch && (projectMatch || pattern.projectContext == 'any') && (environmentMatch || pattern.environmentContext == 'any');
  }
  
  bool _patternMatches(String text, String pattern) {
    // Simple pattern matching with wildcards
    if (pattern.contains('*')) {
      final regexPattern = pattern.replaceAll('*', '.*');
      return RegExp(regexPattern).hasMatch(text);
    }
    return text.toLowerCase().contains(pattern.toLowerCase());
  }
  
  String _extractCommandPattern(String command) {
    // Extract command pattern for matching
    final parts = command.split(' ');
    if (parts.isEmpty) return command;
    
    // Get main command
    var mainCommand = parts[0];
    
    // Remove arguments and options
    if (mainCommand.contains('/')) {
      mainCommand = mainCommand.split('/').last;
    }
    
    // Handle common variations
    if (mainCommand.startsWith('./')) {
      mainCommand = mainCommand.substring(2);
    }
    
    return mainCommand.toLowerCase();
  }
  
  String _extractErrorPattern(String error) {
    // Extract error pattern for matching
    var pattern = error.toLowerCase();
    
    // Remove specific values and keep structure
    pattern = pattern.replaceAll(RegExp(r'\d+'), 'N');
    pattern = pattern.replaceAll(RegExp(r'[/\\][^/\\]*[/\\]'), '/PATH/');
    pattern = pattern.replaceAll(RegExp(r'[/\\][^/\\]*[/\\]'), '/FILE/');
    pattern = pattern.replaceAll(RegExp(r'"[^"]*"'), '/STRING/');
    pattern = pattern.replaceAll(RegExp(r'\'[^\']*\''), '/STRING/');
    
    return pattern;
  }
  
  List<PersonalFix> _getPersonalizedFixes(PersonalErrorPattern pattern, ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    // Get existing fixes for this pattern
    if (pattern.fixes.isNotEmpty) {
      // Sort by success rate
      final sortedFixes = List.from(pattern.fixes)
        ..sort((a, b) => b.successRate.compareTo(a.successRate));
      
      fixes.addAll(sortedFixes.take(3));
    }
    
    // Get context-aware fixes
    final contextualFixes = _getContextualFixes(context);
    fixes.addAll(contextualFixes);
    
    // Get AI-powered fixes
    if (aiAssistant != null) {
      final aiFixes = _getAIFixes(pattern, context);
      fixes.addAll(aiFixes);
    }
    
    // Remove duplicates and return
    return fixes.toSet().toList();
  }
  
  List<PersonalFix> _getContextualFixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    // Project-specific fixes
    switch (context.project) {
      case 'server_233':
        fixes.addAll(_getServer233Fixes(context));
        break;
      case 'server_250':
        fixes.addAll(_getServer250Fixes(context));
        break;
      case 'development':
        fixes.addAll(_getDevelopmentFixes(context));
        break;
    }
    
    // Environment-specific fixes
    switch (context.environment) {
      case 'remote':
        fixes.addAll(_getRemoteFixes(context));
        break;
      case 'ssh':
        fixes.addAll(_getSSHFixes(context));
        break;
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getServer233Fixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    if (context.error.contains('connection refused')) {
      fixes.add(PersonalFix(
        command: 'ssh house@192.168.1.233 "systemctl restart nginx"',
        description: 'Restart nginx service on .233',
        confidence: 0.9,
        successRate: 0.8,
        source: FixSource.personal_pattern,
      ));
    }
    
    if (context.error.contains('permission denied')) {
      fixes.add(PersonalFix(
        command: 'ssh house@192.168.1.233 "sudo chmod +x $SCRIPT"',
        description: 'Make script executable on .233',
        confidence: 0.8,
        successRate: 0.7,
        source: FixSource.personal_pattern,
      ));
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getServer250Fixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    if (context.error.contains('database connection failed')) {
      fixes.add(PersonalFix(
        command: 'ssh house@192.168.1.250 "docker restart memster-postgres"',
        description: 'Restart Memster PostgreSQL on .250',
        confidence: 0.9,
        successRate: 0.8,
        source: FixSource.personal_pattern,
      ));
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getDevelopmentFixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    if (context.error.contains('command not found')) {
      fixes.add(PersonalFix(
        command: 'which ${context.command.split(' ')[0]} || echo "Command not found, checking PATH..."',
        description: 'Check if command exists in PATH',
        confidence: 0.7,
        successRate: 0.6,
        source: FixSource.personal_pattern,
      ));
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getRemoteFixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    if (context.error.contains('network unreachable')) {
      fixes.add(PersonalFix(
        command: 'ping -c 3 ${context.command.split(' ')[1]}',
        description: 'Test network connectivity',
        confidence: 0.8,
        successRate: 0.7,
        source: FixSource.personal_pattern,
      ));
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getSSHFixes(ErrorContext context) {
    final fixes = <PersonalFix>[];
    
    if (context.error.contains('connection timed out')) {
      fixes.add(PersonalFix(
        command: 'ssh -o ConnectTimeout=30 ${context.command}',
        description: 'Increase SSH connection timeout',
        confidence: 0.8,
        successRate: 0.7,
        source: FixSource.personal_pattern,
      ));
    }
    
    return fixes;
  }
  
  Future<List<PersonalFix>> _getAIFixes(PersonalErrorPattern pattern, ErrorContext context) async {
    if (aiAssistant == null) return [];
    
    try {
      final prompt = '''Analyze this error and provide personalized fixes based on my history:

Error: ${context.error}
Command: ${context.command}
Project: ${context.project}
Environment: ${context.environment}

My error patterns: ${_personalPatterns.take(5).map((p) => p.errorPattern).join(', ')}

My successful fixes: ${_getSuccessfulFixes().take(3).map((f) => f.command).join(', ')}

Provide 2-3 specific fixes that:
1. Address the immediate error
2. Consider my project context (.233 or .250)
3. Match my personal error handling style
4. Include confidence levels based on my past success rates

Use these NVIDIA AI models for best results:
- deepseek-ai/deepseek-v4-pro for comprehensive analysis
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for technical solutions''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      // Parse AI response into fixes
      final aiFixes = _parseAIFixes(response);
      
      return aiFixes;
    } catch (e) {
      debugPrint('❌ AI fixes failed: $e');
      return [];
    }
  }
  
  List<PersonalFix> _parseAIFixes(String aiResponse) {
    final fixes = <PersonalFix>[];
    final lines = aiResponse.split('\n');
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      // Extract command and description
      final commandMatch = RegExp(r'(?:sudo\s+)?([^\s]+(?:\s+.+)?)(?=\s*.+)').firstMatch(line);
      if (commandMatch != null) {
        fixes.add(PersonalFix(
          command: commandMatch.group(1)!,
          description: commandMatch.group(2) ?? line.trim(),
          confidence: 0.8,
          successRate: 0.7,
          source: FixSource.ai_generated,
        ));
      }
    }
    
    return fixes;
  }
  
  List<PersonalFix> _getSuccessfulFixes() {
    return _fixHistory.values
        .expand((fixes) => fixes)
        .where((fix) => fix.success)
        .toList();
  }
  
  void _updateUserPreferences(ErrorContext context, List<PersonalFix> fixes) {
    // Update user preferences based on error and fixes
    final projectKey = 'project_${context.project}';
    final errorTypeKey = 'error_type_${_extractErrorType(context.error)}';
    
    // Update project preference
    _userPreferences[projectKey] = UserErrorPreference(
      key: projectKey,
      value: context.project,
      confidence: 0.8,
      lastUpdated: DateTime.now(),
    );
    
    // Update error type preference
    _userPreferences[errorTypeKey] = UserErrorPreference(
      key: errorTypeKey,
      value: _extractErrorType(context.error),
      confidence: 0.7,
      lastUpdated: DateTime.now(),
    );
  }
  
  String _extractErrorType(String error) {
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('permission')) return 'permission';
    if (lowerError.contains('connection')) return 'connection';
    if (lowerError.contains('not found')) return 'not_found';
    if (lowerError.contains('timeout')) return 'timeout';
    if (lowerError.contains('syntax')) return 'syntax';
    if (lowerError.contains('memory')) return 'memory';
    if (lowerError.contains('disk')) return 'disk';
    if (lowerError.contains('network')) return 'network';
    
    return 'unknown';
  }
  
  /// Apply fix and record result
  Future<bool> applyFix(PersonalFix fix, String errorId) async {
    try {
      _eventController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.fix_applying,
        message: 'Applying personal fix',
        data: {'fix': fix.toJson(), 'error_id': errorId},
      ));
      
      // Execute the fix command
      final result = await Process.run('bash', ['-c', fix.command]);
      
      final success = result.exitCode == 0;
      
      // Update fix success rate
      _updateFixSuccessRate(fix, success);
      
      // Record the fix application
      final fixRecord = FixApplication(
        fixId: fix.id,
        errorId: errorId,
        command: fix.command,
        success: success,
        output: result.stdout,
        errorOutput: result.stderr,
        timestamp: DateTime.now(),
      );
      
      _recordFixApplication(fixRecord);
      
      _eventController.add(ErrorCorrectionEvent(
        type: success ? ErrorCorrectionEventType.fix_successful : ErrorCorrectionEventType.fix_failed,
        message: success ? 'Fix applied successfully' : 'Fix failed',
        data: {
          'fix_record': fixRecord.toJson(),
          'exit_code': result.exitCode,
        },
      ));
      
      return success;
    } catch (e) {
      _eventController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.error,
        message: 'Failed to apply fix: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  void _updateFixSuccessRate(PersonalFix fix, bool success) {
    // Update success rate based on new result
    final currentRate = fix.successRate;
    final newRate = (currentRate * 0.8) + (success ? 0.2 : 0.0);
    fix.successRate = newRate.clamp(0.0, 1.0);
  }
  
  void _recordFixApplication(FixApplication record) {
    final fixId = record.fixId;
    
    if (!_fixHistory.containsKey(fixId)) {
      _fixHistory[fixId] = [];
    }
    
    _fixHistory[fixId]!.add(record);
    
    // Keep only last 50 applications per fix
    if (_fixHistory[fixId]!.length > 50) {
      _fixHistory[fixId]!.removeRange(0, _fixHistory[fixId]!.length - 50);
    }
  }
  
  /// Get personalized error suggestions
  Future<List<PersonalFix>> getErrorSuggestions(String error, {String? project}) async {
    final context = ErrorContext(
      command: '',
      error: error,
      project: project ?? 'unknown',
      workingDirectory: null,
      timestamp: DateTime.now(),
      environment: 'unknown',
    );
    
    // Find matching patterns
    final matchingPatterns = _personalPatterns.where((pattern) => 
        pattern.errorPattern.contains(_extractErrorPattern(error))).toList();
    
    final suggestions = <PersonalFix>[];
    
    // Add pattern-based fixes
    for (final pattern in matchingPatterns) {
      suggestions.addAll(pattern.fixes);
    }
    
    // Add AI-powered suggestions
    if (aiAssistant != null && matchingPatterns.isNotEmpty) {
      final aiFixes = await _getAIFixes(matchingPatterns.first, context);
      suggestions.addAll(aiFixes);
    }
    
    // Sort by confidence and success rate
    suggestions.sort((a, b) {
      final scoreA = a.confidence * a.successRate;
      final scoreB = b.confidence * b.successRate;
      return scoreB.compareTo(scoreA);
    });
    
    return suggestions.take(5).toList();
  }
  
  /// Analyze error patterns
  void _analyzeErrorPatterns() {
    if (_personalPatterns.length < 10) return;
    
    // Update pattern frequencies and confidence
    for (final pattern in _personalPatterns) {
      // Update confidence based on recent success
      final recentFixes = _fixHistory[pattern.id] ?? [];
      if (recentFixes.isNotEmpty) {
        final recentSuccess = recentFixes.take(10).where((f) => f.success).length;
        pattern.confidence = (recentSuccess / 10.0).clamp(0.0, 1.0);
      }
    }
    
    // Remove old patterns
    _personalPatterns.removeWhere((pattern) {
      final daysSinceLastSeen = DateTime.now().difference(pattern.lastSeen).inDays;
      return daysSinceLastSeen > 90; // Remove patterns not seen in 90 days
    });
    
    _eventController.add(ErrorCorrectionEvent(
      type: ErrorCorrectionEventType.patterns_analyzed,
      message: 'Error patterns analyzed',
      data: {'patterns_count': _personalPatterns.length},
    ));
  }
  
  /// Persist error immediately for amnesia protection
  Future<void> _persistErrorImmediately(PersonalErrorRecord error) async {
    try {
      // Immediate persistence
      final errorJson = jsonEncode(error.toJson());
      await _prefs.setString('last_error_${error.id}', errorJson);
      
      // Add to recent errors list
      final recentErrorsJson = _prefs.getString('recent_errors') ?? '[]';
      final recentErrors = List<Map<String, dynamic>>.from(jsonDecode(recentErrorsJson));
      recentErrors.insert(0, error.toJson());
      
      // Keep only last 100 errors
      if (recentErrors.length > 100) {
        recentErrors.removeRange(100, recentErrors.length);
      }
      
      await _prefs.setString('recent_errors', jsonEncode(recentErrors));
      
    } catch (e) {
      debugPrint('❌ Failed to persist error immediately: $e');
    }
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load personal patterns
      final patternsJson = _prefs.getString('personal_error_patterns') ?? '[]';
      final patternsList = jsonDecode(patternsJson) as List;
      _personalPatterns.clear();
      for (final item in patternsList) {
        _personalPatterns.add(PersonalErrorPattern.fromJson(item));
      }
      
      // Load fix history
      final fixesJson = _prefs.getString('personal_fix_history') ?? '{}';
      final fixesMap = jsonDecode(fixesJson) as Map;
      _fixHistory.clear();
      for (final entry in fixesMap.entries) {
        _fixHistory[entry.key] = (entry.value as List)
            .map((item) => FixApplication.fromJson(item))
            .toList();
      }
      
      // Load user preferences
      final preferencesJson = _prefs.getString('user_error_preferences') ?? '{}';
      final preferencesMap = jsonDecode(preferencesJson) as Map;
      _userPreferences.clear();
      for (final entry in preferencesMap.entries) {
        _userPreferences[entry.key] = UserErrorPreference.fromJson(entry.value);
      }
      
      _eventController.add(ErrorCorrectionEvent(
        type: ErrorCorrectionEventType.data_loaded,
        message: 'Persisted error correction data loaded',
        data: {
          'patterns_loaded': _personalPatterns.length,
          'fixes_loaded': _fixHistory.length,
          'preferences_loaded': _userPreferences.length,
        },
      ));
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save personal patterns
      final patternsJson = jsonEncode(_personalPatterns.map((p) => p.toJson()).toList());
      await _prefs.setString('personal_error_patterns', patternsJson);
      
      // Save fix history
      final fixesJson = jsonEncode(_fixHistory.map((k, v) => MapEntry(k, v.map((f) => f.toJson()).toList())));
      await _prefs.setString('personal_fix_history', fixesJson);
      
      // Save user preferences
      final preferencesJson = jsonEncode(_userPreferences.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('user_error_preferences', preferencesJson);
      
    } catch (e) {
      debugPrint('❌ Failed to persist data: $e');
    }
  }
  
  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    return {
      'patterns_count': _personalPatterns.length,
      'fix_history_count': _fixHistory.values.fold(0, (sum, fixes) => sum + fixes.length),
      'user_preferences_count': _userPreferences.length,
      'most_common_error_type': _getMostCommonErrorType(),
      'success_rate_average': _getAverageSuccessRate(),
      'project_error_counts': _getProjectErrorCounts(),
    };
  }
  
  String _getMostCommonErrorType() {
    final errorTypes = <String, int>{};
    
    for (final pattern in _personalPatterns) {
      final type = _extractErrorType(pattern.errorPattern);
      errorTypes[type] = (errorTypes[type] ?? 0) + 1;
    }
    
    if (errorTypes.isEmpty) return 'none';
    
    return errorTypes.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
  
  double _getAverageSuccessRate() {
    final allFixes = _fixHistory.values.expand((fixes) => fixes).toList();
    if (allFixes.isEmpty) return 0.0;
    
    final totalSuccess = allFixes.where((fix) => fix.success).length;
    return totalSuccess / allFixes.length;
  }
  
  Map<String, int> _getProjectErrorCounts() {
    final projectCounts = <String, int>{};
    
    for (final pattern in _personalPatterns) {
      final project = pattern.projectContext;
      projectCounts[project] = (projectCounts[project] ?? 0) + 1;
    }
    
    return projectCounts;
  }
  
  /// Clear all personal data
  Future<void> clearPersonalData() async {
    _personalPatterns.clear();
    _errorContexts.clear();
    _fixHistory.clear();
    _userPreferences.clear();
    
    await _prefs.clear();
    
    _eventController.add(ErrorCorrectionEvent(
      type: ErrorCorrectionEventType.data_cleared,
      message: 'All personal error correction data cleared',
      data: {},
    ));
  }
  
  /// Dispose
  void dispose() {
    _analysisTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Personal error pattern
class PersonalErrorPattern {
  final String id;
  final String commandPattern;
  final String errorPattern;
  final String projectContext;
  final String environmentContext;
  int frequency;
  double confidence;
  List<PersonalFix> fixes;
  DateTime lastSeen;
  
  PersonalErrorPattern({
    required this.id,
    required this.commandPattern,
    required this.errorPattern,
    required this.projectContext,
    required this.environmentContext,
    required this.frequency,
    required this.confidence,
    required this.fixes,
    required this.lastSeen,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'command_pattern': commandPattern,
    'error_pattern': errorPattern,
    'project_context': projectContext,
    'environment_context': environmentContext,
    'frequency': frequency,
    'confidence': confidence,
    'fixes': fixes.map((f) => f.toJson()).toList(),
    'last_seen': lastSeen.toIso8601String(),
  };
  
  factory PersonalErrorPattern.fromJson(Map<String, dynamic> json) {
    return PersonalErrorPattern(
      id: json['id'],
      commandPattern: json['command_pattern'],
      errorPattern: json['error_pattern'],
      projectContext: json['project_context'],
      environmentContext: json['environment_context'],
      frequency: json['frequency'],
      confidence: json['confidence'],
      fixes: (json['fixes'] as List?)
          ?.map((f) => PersonalFix.fromJson(f))
          .toList() ?? [],
      lastSeen: DateTime.parse(json['last_seen']),
    );
  }
}

/// Personal fix
class PersonalFix {
  final String id;
  final String command;
  final String description;
  double confidence;
  double successRate;
  FixSource source;
  
  PersonalFix({
    required this.id,
    required this.command,
    required this.description,
    required this.confidence,
    required this.successRate,
    required this.source,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'description': description,
    'confidence': confidence,
    'success_rate': successRate,
    'source': source.toString(),
  };
  
  factory PersonalFix.fromJson(Map<String, dynamic> json) {
    return PersonalFix(
      id: json['id'],
      command: json['command'],
      description: json['description'],
      confidence: json['confidence'],
      successRate: json['success_rate'],
      source: FixSource.values.firstWhere(
        (s) => s.toString() == json['source'],
        orElse: () => FixSource.personal_pattern,
      ),
    );
  }
}

/// Error context
class ErrorContext {
  final String command;
  final String error;
  final String project;
  final String? workingDirectory;
  final DateTime timestamp;
  final String environment;
  
  ErrorContext({
    required this.command,
    required this.error,
    required this.project,
    this.workingDirectory,
    required this.timestamp,
    required this.environment,
  });
}

/// Personal error record
class PersonalErrorRecord {
  final String id;
  final ErrorContext context;
  final PersonalErrorPattern pattern;
  final List<PersonalFix> fixes;
  bool resolved;
  
  PersonalErrorRecord({
    required this.id,
    required this.context,
    required this.pattern,
    required this.fixes,
    this.resolved = false,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'context': {
      'command': context.command,
      'error': context.error,
      'project': context.project,
      'working_directory': context.workingDirectory,
      'timestamp': context.timestamp.toIso8601String(),
      'environment': context.environment,
    },
    'pattern': pattern.toJson(),
    'fixes': fixes.map((f) => f.toJson()).toList(),
    'resolved': resolved,
  };
}

/// Fix application record
class FixApplication {
  final String fixId;
  final String errorId;
  final String command;
  final bool success;
  final String output;
  final String errorOutput;
  final DateTime timestamp;
  
  FixApplication({
    required this.fixId,
    required this.errorId,
    required this.command,
    required this.success,
    required this.output,
    required this.errorOutput,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'fix_id': fixId,
    'error_id': errorId,
    'command': command,
    'success': success,
    'output': output,
    'error_output': errorOutput,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory FixApplication.fromJson(Map<String, dynamic> json) {
    return FixApplication(
      fixId: json['fix_id'],
      errorId: json['error_id'],
      command: json['command'],
      success: json['success'],
      output: json['output'],
      errorOutput: json['error_output'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// User error preference
class UserErrorPreference {
  final String key;
  final String value;
  double confidence;
  DateTime lastUpdated;
  
  UserErrorPreference({
    required this.key,
    required this.value,
    required this.confidence,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'confidence': confidence,
    'last_updated': lastUpdated.toIso8601String(),
  };
  
  factory UserErrorPreference.fromJson(Map<String, dynamic> json) {
    return UserErrorPreference(
      key: json['key'],
      value: json['value'],
      confidence: json['confidence'],
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }
}

/// Fix source
enum FixSource {
  personal_pattern,
  ai_generated,
  contextual,
  learned,
}

/// Error correction event types
enum ErrorCorrectionEventType {
  initialized,
  error_recorded,
  fix_applying,
  fix_successful,
  fix_failed,
  patterns_analyzed,
  data_loaded,
  data_cleared,
  error,
}

/// Error correction event
class ErrorCorrectionEvent {
  final ErrorCorrectionEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  ErrorCorrectionEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
