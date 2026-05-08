import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';

class IntegratedDebugger {
  static const String _nvidiaApiUrl = 'https://api.nvidia.com/v1';
  static const String _deepseekModel = 'deepseek-ai/deepseek-v4-pro';
  static const int _maxContextLength = 1000000; // 1M tokens
  static const int _maxDebugSessions = 10;
  static const int _analysisTimeout = 30000; // 30 seconds
  
  final Map<String, DebugSession> _sessions = {};
  final Map<String, AnalysisResult> _analysisCache = {};
  final List<DebugBreakpoint> _breakpoints = [];
  final Map<String, CodeAnalysis> _codeCache = {};
  
  String? _apiKey;
  bool _isConnected = false;
  int _totalAnalyses = 0;
  int _totalBreakpoints = 0;
  
  final StreamController<DebugEvent> _debugController = 
      StreamController<DebugEvent>.broadcast();

  void initialize({String? apiKey}) {
    _apiKey = apiKey ?? _loadApiKey();
    _testConnection();
    developer.log('🐛 Integrated Debugger initialized');
  }

  String _loadApiKey() {
    // Try to load API key from environment or config
    final envKey = Platform.environment['NVIDIA_API_KEY'];
    if (envKey != null) {
      return envKey;
    }
    
    // Try loading from config file
    final configFile = File('${Platform.environment['HOME'] ?? ''}/.nvidia_api_key');
    if (configFile.existsSync()) {
      return configFile.readAsStringSync().trim();
    }
    
    throw Exception('NVIDIA API key not found. Set NVIDIA_API_KEY environment variable or create ~/.nvidia_api_key file');
  }

  Future<void> _testConnection() async {
    try {
      final response = await _makeNvidiaRequest('/models', {});
      
      if (response['success'] == true) {
        _isConnected = true;
        developer.log('🐛 NVIDIA API connection successful');
      } else {
        _isConnected = false;
        developer.log('🐛 NVIDIA API connection failed');
      }
    } catch (e) {
      _isConnected = false;
      developer.log('🐛 NVIDIA API connection test failed: $e');
    }
  }

  Future<Map<String, dynamic>> _makeNvidiaRequest(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    if (_apiKey == null) {
      throw Exception('API key not configured');
    }
    
    final url = Uri.parse('$_nvidiaApiUrl$endpoint');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    };
    
    final client = HttpClient();
    
    try {
      final request = await client.postUrl(url, headers: headers);
      request.write(jsonEncode(data));
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      return jsonDecode(responseBody);
    } finally {
      client.close();
    }
  }

  String createDebugSession({
    required String filePath,
    required String language,
    Map<String, dynamic>? context,
  }) {
    if (_sessions.length >= _maxDebugSessions) {
      throw Exception('Maximum debug sessions reached');
    }
    
    final sessionId = _generateSessionId();
    
    final session = DebugSession(
      id: sessionId,
      filePath: filePath,
      language: language,
      context: context ?? {},
      createdAt: DateTime.now(),
      status: DebugSessionStatus.created,
      breakpoints: [],
      variables: {},
      callStack: [],
      analysis: null,
    );
    
    _sessions[sessionId] = session;
    
    developer.log('🐛 Created debug session: $sessionId for $filePath');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.sessionCreated,
      sessionId: sessionId,
      filePath: filePath,
      language: language,
    ));
    
    return sessionId;
  }

  Future<AnalysisResult> analyzeCode({
    required String sessionId,
    required String code,
    String? issue,
    Map<String, dynamic>? context,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Debug session not found: $sessionId');
    }
    
    // Check cache first
    final cacheKey = _generateCacheKey(code, issue, context);
    final cached = _analysisCache[cacheKey];
    
    if (cached != null && !cached.isExpired()) {
      session.analysis = cached;
      
      developer.log('🐛 Using cached analysis for session: $sessionId');
      
      _emitEvent(DebugEvent(
        type: DebugEventType.analysisCompleted,
        sessionId: sessionId,
        result: cached,
        fromCache: true,
      ));
      
      return cached;
    }
    
    try {
      developer.log('🐛 Analyzing code with DeepSeek-V4-Pro...');
      
      final analysis = await _performDeepAnalysis(code, issue, context, session);
      
      session.analysis = analysis;
      _totalAnalyses++;
      
      // Cache the result
      _analysisCache[cacheKey] = analysis;
      
      // Keep cache size limited
      if (_analysisCache.length > 100) {
        final oldestKey = _analysisCache.keys.first;
        _analysisCache.remove(oldestKey);
      }
      
      developer.log('🐛 Analysis completed for session: $sessionId');
      
      _emitEvent(DebugEvent(
        type: DebugEventType.analysisCompleted,
        sessionId: sessionId,
        result: analysis,
        fromCache: false,
      ));
      
      return analysis;
      
    } catch (e) {
      developer.log('🐛 Analysis failed: $e');
      
      _emitEvent(DebugEvent(
        type: DebugEventType.analysisFailed,
        sessionId: sessionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<AnalysisResult> _performDeepAnalysis(
    String code,
    String? issue,
    Map<String, dynamic>? context,
    DebugSession session,
  ) async {
    final prompt = _buildAnalysisPrompt(code, issue, context, session);
    
    final requestData = {
      'model': _deepseekModel,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'max_tokens': _maxContextLength,
      'temperature': 0.1,
      'stream': false,
    };
    
    final response = await _makeNvidiaRequest('/chat/completions', requestData);
    
    if (response['success'] != true) {
      throw Exception('DeepSeek analysis failed: ${response['error']}');
    }
    
    final content = response['choices'][0]['message']['content'];
    
    return _parseAnalysisResponse(content, code, session);
  }

  String _buildAnalysisPrompt(
    String code,
    String? issue,
    Map<String, dynamic>? context,
    DebugSession session,
  ) {
    final prompt = StringBuffer();
    
    prompt.writeln('You are an expert debugging assistant with deep knowledge of ${session.language} programming.');
    prompt.writeln('You have access to a 1 million token context window, allowing for comprehensive analysis.');
    prompt.writeln('');
    
    if (issue != null) {
      prompt.writeln('ISSUE TO DEBUG:');
      prompt.writeln(issue);
      prompt.writeln('');
    }
    
    if (context != null && context!.isNotEmpty) {
      prompt.writeln('CONTEXT:');
      for (final entry in context!.entries) {
        prompt.writeln('${entry.key}: ${entry.value}');
      }
      prompt.writeln('');
    }
    
    prompt.writeln('CODE TO ANALYZE:');
    prompt.writeln('```${session.language}');
    prompt.writeln(code);
    prompt.writeln('```');
    prompt.writeln('');
    
    prompt.writeln('Please provide a comprehensive analysis including:');
    prompt.writeln('1. Identify any syntax errors or potential runtime issues');
    prompt.writeln('2. Suggest specific fixes with code examples');
    prompt.writeln('3. Explain the root cause of any issues');
    prompt.writeln('4. Recommend best practices for this code');
    prompt.writeln('5. Suggest optimizations if applicable');
    prompt.writeln('6. Identify potential edge cases or error conditions');
    prompt.writeln('7. Provide step-by-step debugging approach');
    prompt.writeln('8. Suggest relevant test cases');
    
    return prompt.toString();
  }

  AnalysisResult _parseAnalysisResponse(String response, String originalCode, DebugSession session) {
    final lines = response.split('\n');
    
    final result = AnalysisResult(
      sessionId: session.id,
      timestamp: DateTime.now(),
      summary: _extractSection(lines, 'SUMMARY:'),
      issues: _extractIssues(lines),
      fixes: _extractFixes(lines),
      rootCause: _extractSection(lines, 'ROOT CAUSE:'),
      bestPractices: _extractSection(lines, 'BEST PRACTICES:'),
      optimizations: _extractSection(lines, 'OPTIMIZATIONS:'),
      edgeCases: _extractSection(lines, 'EDGE CASES:'),
      debuggingSteps: _extractSection(lines, 'DEBUGGING STEPS:'),
      testCases: _extractSection(lines, 'TEST CASES:'),
      confidence: _extractConfidence(lines),
      suggestions: _extractSuggestions(lines),
      codeChanges: _extractCodeChanges(lines, originalCode),
    );
    
    return result;
  }

  String _extractSection(List<String> lines, String sectionName) {
    final sectionStart = lines.indexWhere((line) => line.startsWith(sectionName));
    if (sectionStart == -1) return '';
    
    final sectionLines = <String>[];
    for (int i = sectionStart + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith(RegExp(r'^\d+\.'))) {
        break;
      }
      sectionLines.add(line);
    }
    
    return sectionLines.join('\n');
  }

  List<CodeIssue> _extractIssues(List<String> lines) {
    final issues = <CodeIssue>[];
    final issueSection = _extractSection(lines, 'ISSUES:');
    
    if (issueSection.isNotEmpty) {
      final issueLines = issueSection.split('\n');
      for (final line in issueLines) {
        if (line.trim().startsWith('-')) {
          issues.add(CodeIssue(
            type: IssueType.error,
            message: line.trim().substring(1).trim(),
            severity: ErrorSeverity.high,
            line: null,
            column: null,
          ));
        }
      }
    }
    
    return issues;
  }

  List<CodeFix> _extractFixes(List<String> lines) {
    final fixes = <CodeFix>[];
    final fixSection = _extractSection(lines, 'FIXES:');
    
    if (fixSection.isNotEmpty) {
      final fixLines = fixSection.split('\n');
      for (final line in fixLines) {
        if (line.trim().startsWith('-')) {
          fixes.add(CodeFix(
            description: line.trim().substring(1).trim(),
            code: _extractCodeFromLine(line),
            line: null,
            column: null,
          ));
        }
      }
    }
    
    return fixes;
  }

  List<CodeSuggestion> _extractSuggestions(List<String> lines) {
    final suggestions = <CodeSuggestion>[];
    final suggestionSection = _extractSection(lines, 'SUGGESTIONS:');
    
    if (suggestionSection.isNotEmpty) {
      final suggestionLines = suggestionSection.split('\n');
      for (final line in suggestionLines) {
        if (line.trim().startsWith('-')) {
          suggestions.add(CodeSuggestion(
            type: SuggestionType.general,
            message: line.trim().substring(1).trim(),
            priority: SuggestionPriority.medium,
          ));
        }
      }
    }
    
    return suggestions;
  }

  List<CodeChange> _extractCodeChanges(List<String> lines, String originalCode) {
    final changes = <CodeChange>[];
    final codeSection = _extractSection(lines, 'CODE CHANGES:');
    
    if (codeSection.isNotEmpty) {
      final codeLines = codeSection.split('\n');
      for (final line in codeLines) {
        if (line.contains('```')) {
          // Extract code from markdown blocks
          final codeBlock = _extractCodeFromLine(line);
          if (codeBlock.isNotEmpty) {
            changes.add(CodeChange(
              type: ChangeType.replacement,
              description: 'Suggested code replacement',
              oldCode: originalCode,
              newCode: codeBlock,
            ));
          }
        }
      }
    }
    
    return changes;
  }

  String _extractCodeFromLine(String line) {
    final codeRegex = RegExp(r'```(?:\w+)?\n?([\s\S]*?)\n?```');
    final match = codeRegex.firstMatch(line);
    return match?.group(1) ?? '';
  }

  double _extractConfidence(List<String> lines) {
    for (final line in lines) {
      if (line.contains('confidence:')) {
        final match = RegExp(r'confidence:\s*(\d+(?:\.\d+)?)%').firstMatch(line);
        if (match != null) {
          return double.tryParse(match.group(1)!) ?? 0.8;
        }
      }
    }
    return 0.8; // Default confidence
  }

  void addBreakpoint({
    required String sessionId,
    required int line,
    int? column,
    String? condition,
    bool? enabled,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Debug session not found: $sessionId');
    }
    
    final breakpoint = DebugBreakpoint(
      id: _generateBreakpointId(),
      sessionId: sessionId,
      line: line,
      column: column ?? 0,
      condition: condition,
      enabled: enabled ?? true,
      createdAt: DateTime.now(),
      hitCount: 0,
    );
    
    session.breakpoints.add(breakpoint);
    _breakpoints.add(breakpoint);
    _totalBreakpoints++;
    
    developer.log('🐛 Added breakpoint: line $line in session $sessionId');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.breakpointAdded,
      sessionId: sessionId,
      breakpointId: breakpoint.id,
      line: line,
      column: column,
    ));
  }

  void removeBreakpoint(String breakpointId) {
    final breakpoint = _breakpoints.firstWhere(
      (bp) => bp.id == breakpointId,
      orElse: () => null as DebugBreakpoint,
    );
    
    if (breakpoint == null) return;
    
    final session = _sessions[breakpoint.sessionId];
    if (session != null) {
      session.breakpoints.removeWhere((bp) => bp.id == breakpointId);
    }
    
    _breakpoints.removeWhere((bp) => bp.id == breakpointId);
    
    developer.log('🐛 Removed breakpoint: $breakpointId');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.breakpointRemoved,
      sessionId: breakpoint.sessionId,
      breakpointId: breakpointId,
    ));
  }

  void toggleBreakpoint(String breakpointId) {
    final breakpoint = _breakpoints.firstWhere(
      (bp) => bp.id == breakpointId,
      orElse: () => null as DebugBreakpoint,
    );
    
    if (breakpoint == null) return;
    
    breakpoint.enabled = !breakpoint.enabled;
    
    developer.log('🐛 Toggled breakpoint: $breakpointId (${breakpoint.enabled ? 'enabled' : 'disabled'})');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.breakpointToggled,
      breakpointId: breakpointId,
      enabled: breakpoint.enabled,
    ));
  }

  Future<void> stepDebug(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Debug session not found: $sessionId');
    }
    
    developer.log('🐛 Step debugging in session: $sessionId');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.step,
      sessionId: sessionId,
    ));
  }

  Future<void> continueDebug(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Debug session not found: $sessionId');
    }
    
    developer.log('🐛 Continue debugging in session: $sessionId');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.shouldContinue,
      sessionId: sessionId,
    ));
  }

  void closeDebugSession(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    
    // Remove associated breakpoints
    _breakpoints.removeWhere((bp) => bp.sessionId == sessionId);
    
    developer.log('🐛 Closed debug session: $sessionId');
    
    _emitEvent(DebugEvent(
      type: DebugEventType.sessionClosed,
      sessionId: sessionId,
    ));
  }

  DebugSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  List<DebugSession> getSessions() {
    return _sessions.values.toList();
  }

  List<DebugBreakpoint> getBreakpoints({String? sessionId}) {
    if (sessionId != null) {
      final session = _sessions[sessionId];
      return session?.breakpoints.toList() ?? [];
    }
    return _breakpoints.toList();
  }

  Future<CodeAnalysis> analyzeFile(String filePath) async {
    // Check cache first
    final cached = _codeCache[filePath];
    if (cached != null && !cached.isExpired()) {
      return cached;
    }
    
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('File not found: $filePath');
      }
      
      final content = file.readAsStringSync();
      final language = _detectLanguage(filePath);
      
      // Create temporary session for analysis
      final tempSessionId = _generateSessionId();
      final tempSession = DebugSession(
        id: tempSessionId,
        filePath: filePath,
        language: language,
        context: {},
        createdAt: DateTime.now(),
        status: DebugSessionStatus.analyzing,
        breakpoints: [],
        variables: {},
        callStack: [],
        analysis: null,
      );
      
      final analysis = await _performDeepAnalysis(content, null, null, tempSession);
      
      final codeAnalysis = CodeAnalysis(
        filePath: filePath,
        language: language,
        analysis: analysis,
        analyzedAt: DateTime.now(),
      );
      
      _codeCache[filePath] = codeAnalysis;
      
      // Clean up temporary session
      _sessions.remove(tempSessionId);
      
      return codeAnalysis;
      
    } catch (e) {
      developer.log('🐛 File analysis failed: $e');
      rethrow;
    }
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
      case 'hpp':
      case 'hxx':
        return 'cpp';
      case 'c':
      case 'h':
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
      case 'fish':
        return 'shell';
      default:
        return 'text';
    }
  }

  String _generateSessionId() {
    return 'debug_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateBreakpointId() {
    return 'bp_${DateTime.now().millisecondsSinceEpoch}_$_totalBreakpoints';
  }

  String _generateCacheKey(String code, String? issue, Map<String, dynamic>? context) {
    final codeHash = code.hashCode;
    final issueHash = issue?.hashCode ?? 0;
    final contextHash = context?.toString().hashCode ?? 0;
    return '${codeHash}_${issueHash}_$contextHash';
  }

  void _emitEvent(DebugEvent event) {
    _debugController.add(event);
  }

  Stream<DebugEvent> get debugEventStream => _debugController.stream;

  IntegratedDebuggerStats getStats() {
    return IntegratedDebuggerStats(
      isConnected: _isConnected,
      totalSessions: _sessions.length,
      totalAnalyses: _totalAnalyses,
      totalBreakpoints: _totalBreakpoints,
      cacheSize: _analysisCache.length,
      codeCacheSize: _codeCache.length,
    );
  }

  void dispose() {
    _sessions.clear();
    _analysisCache.clear();
    _breakpoints.clear();
    _codeCache.clear();
    _debugController.close();
    
    developer.log('🐛 Integrated Debugger disposed');
  }
}

class DebugSession {
  final String id;
  final String filePath;
  final String language;
  final Map<String, dynamic> context;
  final DateTime createdAt;
  DebugSessionStatus status;
  final List<DebugBreakpoint> breakpoints;
  final Map<String, dynamic> variables;
  final List<String> callStack;
  AnalysisResult? analysis;

  DebugSession({
    required this.id,
    required this.filePath,
    required this.language,
    required this.context,
    required this.createdAt,
    required this.status,
    required this.breakpoints,
    required this.variables,
    required this.callStack,
    this.analysis,
  });
}

class DebugBreakpoint {
  final String id;
  final String sessionId;
  final int line;
  final int column;
  final String? condition;
  bool enabled;
  final DateTime createdAt;
  int hitCount;
  DateTime? lastHit;

  DebugBreakpoint({
    required this.id,
    required this.sessionId,
    required this.line,
    required this.column,
    this.condition,
    required this.enabled,
    required this.createdAt,
    required this.hitCount,
    this.lastHit,
  });
}

class AnalysisResult {
  final String sessionId;
  final DateTime timestamp;
  final String summary;
  final List<CodeIssue> issues;
  final List<CodeFix> fixes;
  final String rootCause;
  final String bestPractices;
  final String optimizations;
  final String edgeCases;
  final String debuggingSteps;
  final String testCases;
  final double confidence;
  final List<CodeSuggestion> suggestions;
  final List<CodeChange> codeChanges;

  AnalysisResult({
    required this.sessionId,
    required this.timestamp,
    required this.summary,
    required this.issues,
    required this.fixes,
    required this.rootCause,
    required this.bestPractices,
    required this.optimizations,
    required this.edgeCases,
    required this.debuggingSteps,
    required this.testCases,
    required this.confidence,
    required this.suggestions,
    required this.codeChanges,
  });
}

class CodeIssue {
  final IssueType type;
  final String message;
  final ErrorSeverity severity;
  final int? line;
  final int? column;

  CodeIssue({
    required this.type,
    required this.message,
    required this.severity,
    this.line,
    this.column,
  });
}

class CodeFix {
  final String description;
  final String code;
  final int? line;
  final int? column;

  CodeFix({
    required this.description,
    required this.code,
    this.line,
    this.column,
  });
}

class CodeSuggestion {
  final SuggestionType type;
  final String message;
  final SuggestionPriority priority;

  CodeSuggestion({
    required this.type,
    required this.message,
    required this.priority,
  });
}

class CodeChange {
  final ChangeType type;
  final String description;
  final String oldCode;
  final String newCode;

  CodeChange({
    required this.type,
    required this.description,
    required this.oldCode,
    required this.newCode,
  });
}

class CodeAnalysis {
  final String filePath;
  final String language;
  final AnalysisResult analysis;
  final DateTime analyzedAt;

  CodeAnalysis({
    required this.filePath,
    required this.language,
    required this.analysis,
    required this.analyzedAt,
  });

  bool isExpired() {
    return DateTime.now().difference(analyzedAt).inHours > 24;
  }
}

enum DebugSessionStatus {
  created,
  analyzing,
  debugging,
  paused,
  completed,
  error,
}

enum DebugEventType {
  sessionCreated,
  sessionClosed,
  analysisCompleted,
  analysisFailed,
  breakpointAdded,
  breakpointRemoved,
  breakpointToggled,
  step,
  shouldContinue,
}

enum IssueType {
  error,
  warning,
  info,
  style,
  performance,
}

enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

enum SuggestionType {
  general,
  optimization,
  security,
  bestPractice,
}

enum SuggestionPriority {
  low,
  medium,
  high,
  critical,
}

enum ChangeType {
  addition,
  removal,
  replacement,
  formatting,
}

class DebugEvent {
  final DebugEventType type;
  final String? sessionId;
  final String? breakpointId;
  final int? line;
  final int? column;
  final bool? enabled;
  final AnalysisResult? result;
  final bool? fromCache;
  final String? error;

  DebugEvent({
    required this.type,
    this.sessionId,
    this.breakpointId,
    this.line,
    this.column,
    this.enabled,
    this.result,
    this.fromCache,
    this.error,
  });
}

class IntegratedDebuggerStats {
  final bool isConnected;
  final int totalSessions;
  final int totalAnalyses;
  final int totalBreakpoints;
  final int cacheSize;
  final int codeCacheSize;

  IntegratedDebuggerStats({
    required this.isConnected,
    required this.totalSessions,
    required this.totalAnalyses,
    required this.totalBreakpoints,
    required this.cacheSize,
    required this.codeCacheSize,
  });
}
