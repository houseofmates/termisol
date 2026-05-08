import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Context-Aware Prompt Optimizer - Best-in-class AI prompt optimization
/// 
/// Provides comprehensive prompt optimization with:
/// - Intelligent context compression and selection
/// - Semantic similarity analysis
/// - Token usage optimization
/// - Context relevance scoring
/// - Dynamic prompt adaptation
/// - Performance monitoring
class ContextAwarePromptOptimizer {
  static final ContextAwarePromptOptimizer _instance = ContextAwarePromptOptimizer._internal();
  factory ContextAwarePromptOptimizer() => _instance;
  ContextAwarePromptOptimizer._internal();

  final Map<String, ContextCache> _contextCache = {};
  final Queue<PromptHistory> _promptHistory = Queue<PromptHistory>();
  final Map<String, OptimizationMetrics> _optimizationMetrics = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  
  // Optimization configuration
  static const Duration _cleanupInterval = Duration(minutes: 10);
  static const int _maxContextSize = 50000; // characters
  static const int _maxHistorySize = 100;
  static const int _maxTokens = 4096;
  static const double _relevanceThreshold = 0.7;
  
  final _optimizerController = StreamController<OptimizerEvent>.broadcast();
  Stream<OptimizerEvent> get events => _optimizerController.stream;
  
  bool get isInitialized => _isInitialized;
  Map<String, ContextCache> get contextCache => Map.unmodifiable(_contextCache);

  /// Initialize context-aware prompt optimizer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('🧠 Context-Aware Prompt Optimizer initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Context-Aware Prompt Optimizer: $e');
      rethrow;
    }
  }

  /// Optimize prompt with context
  Future<OptimizedPrompt> optimizePrompt({
    required String prompt,
    required Map<String, dynamic> context,
    String? model,
    int? maxTokens,
    bool enableContextCompression = true,
    bool enableSemanticAnalysis = true,
    Map<String, dynamic>? preferences,
  }) async {
    final startTime = DateTime.now();
    
    // Analyze prompt and context
    final analysis = await _analyzePromptAndContext(prompt, context, model);
    
    // Select relevant context
    final relevantContext = await _selectRelevantContext(analysis, context, preferences);
    
    // Compress context if enabled
    final compressedContext = enableContextCompression 
        ? await _compressContext(relevantContext, analysis)
        : relevantContext;
    
    // Optimize prompt structure
    final optimizedPrompt = await _optimizePromptStructure(prompt, compressedContext, analysis);
    
    // Calculate optimization metrics
    final metrics = _calculateOptimizationMetrics(prompt, optimizedPrompt, context, compressedContext);
    
    // Cache the optimization
    await _cacheOptimization(prompt, optimizedPrompt, context, metrics);
    
    // Add to history
    _addToHistory(prompt, optimizedPrompt, metrics);
    
    final endTime = DateTime.now();
    final optimizationTime = endTime.difference(startTime);
    
    _optimizerController.add(OptimizerEvent(
      type: OptimizerEventType.optimizationCompleted,
      timestamp: DateTime.now(),
      data: {
        'originalLength': prompt.length,
        'optimizedLength': optimizedPrompt.prompt.length,
        'contextSize': compressedContext.length,
        'optimizationTime': optimizationTime.inMilliseconds,
        'compressionRatio': metrics.compressionRatio,
      },
    ));

    debugPrint('🧠 Optimized prompt: ${prompt.length} -> ${optimizedPrompt.prompt.length} chars');
    
    return optimizedPrompt;
  }

  /// Get context suggestions for prompt
  Future<List<ContextSuggestion>> getContextSuggestions({
    required String prompt,
    required Map<String, dynamic> context,
    int? maxSuggestions = 10,
  }) async {
    final analysis = await _analyzePromptAndContext(prompt, context, null);
    final suggestions = <ContextSuggestion>[];
    
    // File-based suggestions
    if (context.containsKey('files')) {
      final fileSuggestions = _getFileSuggestions(prompt, context['files'] as List);
      suggestions.addAll(fileSuggestions);
    }
    
    // Command-based suggestions
    if (context.containsKey('commands')) {
      final commandSuggestions = _getCommandSuggestions(prompt, context['commands'] as List);
      suggestions.addAll(commandSuggestions);
    }
    
    // Directory-based suggestions
    if (context.containsKey('directories')) {
      final dirSuggestions = _getDirectorySuggestions(prompt, context['directories'] as List);
      suggestions.addAll(dirSuggestions);
    }
    
    // Sort by relevance and limit
    suggestions.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return suggestions.take(maxSuggestions!).toList();
  }

  /// Analyze prompt and context
  Future<PromptAnalysis> _analyzePromptAndContext(String prompt, Map<String, dynamic> context, String? model) async {
    return PromptAnalysis(
      promptType: _classifyPromptType(prompt),
      complexity: _calculatePromptComplexity(prompt),
      tokenEstimate: _estimateTokenCount(prompt, model),
      contextRelevance: _calculateContextRelevance(prompt, context),
      semanticKeywords: _extractSemanticKeywords(prompt),
      entities: _extractEntities(prompt),
      intent: _classifyIntent(prompt),
    );
  }

  /// Select relevant context
  Future<Map<String, dynamic>> _selectRelevantContext(
    PromptAnalysis analysis,
    Map<String, dynamic> context,
    Map<String, dynamic>? preferences,
  ) async {
    final selectedContext = <String, dynamic>{};
    
    // Select based on prompt type
    switch (analysis.promptType) {
      case PromptType.codeRelated:
        selectedContext.addAll(_selectCodeContext(context, analysis));
        break;
      case PromptType.fileOperation:
        selectedContext.addAll(_selectFileOperationContext(context, analysis));
        break;
      case PromptType.systemCommand:
        selectedContext.addAll(_selectSystemCommandContext(context, analysis));
        break;
      case PromptType.generalQuestion:
        selectedContext.addAll(_selectGeneralQuestionContext(context, analysis));
        break;
    }
    
    // Apply user preferences
    if (preferences != null) {
      _applyUserPreferences(selectedContext, preferences!);
    }
    
    return selectedContext;
  }

  /// Compress context
  Future<Map<String, dynamic>> _compressContext(
    Map<String, dynamic> context,
    PromptAnalysis analysis,
  ) async {
    final compressed = <String, dynamic>{};
    final totalSize = _calculateContextSize(context);
    
    // Compress based on importance and relevance
    for (final entry in context.entries) {
      final importance = _calculateContextImportance(entry.key, entry.value, analysis);
      final relevance = _calculateContextRelevanceForEntry(entry.key, entry.value, analysis);
      
      if (importance * relevance >= _relevanceThreshold) {
        // Keep high importance/relevance items
        compressed[entry.key] = entry.value;
      } else {
        // Compress lower importance items
        final compressedValue = await _compressContextValue(entry.value);
        compressed[entry.key] = compressedValue;
      }
    }
    
    // Ensure we don't exceed max context size
    final compressedSize = _calculateContextSize(compressed);
    if (compressedSize > _maxContextSize) {
      // Further compress if needed
      return await _aggressiveCompression(compressed, _maxContextSize);
    }
    
    return compressed;
  }

  /// Optimize prompt structure
  Future<OptimizedPrompt> _optimizePromptStructure(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    // Build optimized prompt based on type
    switch (analysis.promptType) {
      case PromptType.codeRelated:
        return await _optimizeCodePrompt(originalPrompt, compressedContext, analysis);
      case PromptType.fileOperation:
        return await _optimizeFileOperationPrompt(originalPrompt, compressedContext, analysis);
      case PromptType.systemCommand:
        return await _optimizeSystemCommandPrompt(originalPrompt, compressedContext, analysis);
      case PromptType.generalQuestion:
        return await _optimizeGeneralQuestionPrompt(originalPrompt, compressedContext, analysis);
      default:
        return await _optimizeGenericPrompt(originalPrompt, compressedContext, analysis);
    }
  }

  /// Optimize code-related prompt
  Future<OptimizedPrompt> _optimizeCodePrompt(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    final optimizedPrompt = StringBuffer();
    
    // Add system prompt for code tasks
    optimizedPrompt.writeln('You are an expert code assistant. Analyze the following request and provide precise, helpful responses.');
    
    // Add relevant context
    if (compressedContext.isNotEmpty) {
      optimizedPrompt.writeln('\nContext:');
      optimizedPrompt.writeln(_formatContextForCode(compressedContext));
    }
    
    // Add optimized user prompt
    optimizedPrompt.writeln('\nUser Request:');
    optimizedPrompt.writeln(_optimizeUserPromptForCode(originalPrompt, analysis));
    
    return OptimizedPrompt(
      prompt: optimizedPrompt.toString(),
      type: PromptType.codeRelated,
      estimatedTokens: _estimateTokenCount(optimizedPrompt.toString(), null),
      contextUsed: compressedContext,
      optimizations: ['code_expert_prompt', 'context_formatting', 'prompt_structure'],
    );
  }

  /// Optimize file operation prompt
  Future<OptimizedPrompt> _optimizeFileOperationPrompt(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    final optimizedPrompt = StringBuffer();
    
    optimizedPrompt.writeln('You are a file system expert. Help with file operations using the provided context.');
    
    if (compressedContext.isNotEmpty) {
      optimizedPrompt.writeln('\nCurrent Directory and Files:');
      optimizedPrompt.writeln(_formatContextForFiles(compressedContext));
    }
    
    optimizedPrompt.writeln('\nOperation:');
    optimizedPrompt.writeln(_optimizeUserPromptForFileOps(originalPrompt, analysis));
    
    return OptimizedPrompt(
      prompt: optimizedPrompt.toString(),
      type: PromptType.fileOperation,
      estimatedTokens: _estimateTokenCount(optimizedPrompt.toString(), null),
      contextUsed: compressedContext,
      optimizations: ['file_expert_prompt', 'directory_context', 'operation_clarification'],
    );
  }

  /// Optimize system command prompt
  Future<OptimizedPrompt> _optimizeSystemCommandPrompt(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    final optimizedPrompt = StringBuffer();
    
    optimizedPrompt.writeln('You are a system administration expert. Provide accurate command guidance.');
    
    if (compressedContext.isNotEmpty) {
      optimizedPrompt.writeln('\nSystem Context:');
      optimizedPrompt.writeln(_formatContextForSystem(compressedContext));
    }
    
    optimizedPrompt.writeln('\nCommand Request:');
    optimizedPrompt.writeln(_optimizeUserPromptForSystem(originalPrompt, analysis));
    
    return OptimizedPrompt(
      prompt: optimizedPrompt.toString(),
      type: PromptType.systemCommand,
      estimatedTokens: _estimateTokenCount(optimizedPrompt.toString(), null),
      contextUsed: compressedContext,
      optimizations: ['system_expert_prompt', 'environment_context', 'command_structure'],
    );
  }

  /// Optimize general question prompt
  Future<OptimizedPrompt> _optimizeGeneralQuestionPrompt(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    final optimizedPrompt = StringBuffer();
    
    optimizedPrompt.writeln('You are a helpful assistant. Use the provided context to answer accurately.');
    
    if (compressedContext.isNotEmpty) {
      optimizedPrompt.writeln('\nRelevant Context:');
      optimizedPrompt.writeln(_formatContextForGeneral(compressedContext));
    }
    
    optimizedPrompt.writeln('\nQuestion:');
    optimizedPrompt.writeln(_optimizeUserPromptForGeneral(originalPrompt, analysis));
    
    return OptimizedPrompt(
      prompt: optimizedPrompt.toString(),
      type: PromptType.generalQuestion,
      estimatedTokens: _estimateTokenCount(optimizedPrompt.toString(), null),
      contextUsed: compressedContext,
      optimizations: ['general_assistant_prompt', 'context_summarization', 'question_clarification'],
    );
  }

  /// Optimize generic prompt
  Future<OptimizedPrompt> _optimizeGenericPrompt(
    String originalPrompt,
    Map<String, dynamic> compressedContext,
    PromptAnalysis analysis,
  ) async {
    final optimizedPrompt = StringBuffer();
    
    optimizedPrompt.writeln('You are a helpful assistant. Use the provided context to respond accurately.');
    
    if (compressedContext.isNotEmpty) {
      optimizedPrompt.writeln('\nContext:');
      optimizedPrompt.writeln(_formatContextGeneric(compressedContext));
    }
    
    optimizedPrompt.writeln('\nRequest:');
    optimizedPrompt.writeln(originalPrompt);
    
    return OptimizedPrompt(
      prompt: optimizedPrompt.toString(),
      type: PromptType.generalQuestion,
      estimatedTokens: _estimateTokenCount(optimizedPrompt.toString(), null),
      contextUsed: compressedContext,
      optimizations: ['generic_prompt', 'basic_context'],
    );
  }

  /// Classify prompt type
  PromptType _classifyPromptType(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    
    // Code-related keywords
    final codeKeywords = ['code', 'function', 'class', 'method', 'debug', 'compile', 'run', 'test', 'implement', 'refactor'];
    if (codeKeywords.any((keyword) => lowerPrompt.contains(keyword))) {
      return PromptType.codeRelated;
    }
    
    // File operation keywords
    final fileKeywords = ['file', 'directory', 'folder', 'create', 'delete', 'move', 'copy', 'list', 'find', 'search'];
    if (fileKeywords.any((keyword) => lowerPrompt.contains(keyword))) {
      return PromptType.fileOperation;
    }
    
    // System command keywords
    final systemKeywords = ['command', 'terminal', 'shell', 'bash', 'zsh', 'fish', 'powershell', 'cmd'];
    if (systemKeywords.any((keyword) => lowerPrompt.contains(keyword))) {
      return PromptType.systemCommand;
    }
    
    // Question indicators
    if (lowerPrompt.contains('?') || lowerPrompt.contains('how') || lowerPrompt.contains('what') || lowerPrompt.contains('why')) {
      return PromptType.generalQuestion;
    }
    
    return PromptType.generalQuestion;
  }

  /// Calculate prompt complexity
  double _calculatePromptComplexity(String prompt) {
    // Simple complexity based on length, punctuation, and structure
    var complexity = 0.0;
    
    // Length factor
    complexity += prompt.length / 100.0;
    
    // Punctuation factor
    final punctuationCount = RegExp(r'[.!?;:]').allMatches(prompt).length;
    complexity += punctuationCount * 0.1;
    
    // Structure factor (multiple sentences/questions)
    final sentenceCount = RegExp(r'[.!?]').allMatches(prompt).length;
    if (sentenceCount > 1) {
      complexity += sentenceCount * 0.2;
    }
    
    return math.min(complexity, 10.0);
  }

  /// Estimate token count
  int _estimateTokenCount(String text, String? model) {
    // Simple token estimation (roughly 4 characters per token)
    return (text.length / 4).ceil();
  }

  /// Calculate context relevance
  double _calculateContextRelevance(String prompt, Map<String, dynamic> context) {
    if (context.isEmpty) return 0.0;
    
    var relevance = 0.0;
    final promptWords = prompt.toLowerCase().split(' ');
    
    for (final entry in context.entries) {
      final entryStr = entry.value.toString().toLowerCase();
      final entryWords = entryStr.split(' ');
      
      // Calculate word overlap
      int overlap = 0;
      for (final promptWord in promptWords) {
        if (entryWords.contains(promptWord)) {
          overlap++;
        }
      }
      
      relevance += overlap / math.max(promptWords.length, entryWords.length);
    }
    
    return math.min(relevance, 1.0);
  }

  /// Extract semantic keywords
  List<String> _extractSemanticKeywords(String prompt) {
    // Simple keyword extraction
    final words = prompt.toLowerCase().split(' ');
    final keywords = <String>[];
    
    // Filter out common stop words and keep important terms
    final stopWords = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by'};
    
    for (final word in words) {
      if (word.length > 2 && !stopWords.contains(word)) {
        keywords.add(word);
      }
    }
    
    return keywords.toSet().toList();
  }

  /// Extract entities
  List<String> _extractEntities(String prompt) {
    // Simple entity extraction (file paths, URLs, etc.)
    final entities = <String>[];
    
    // File paths
    final pathPattern = RegExp(r'[/\\][\w\-./]+');
    final pathMatches = pathPattern.allMatches(prompt);
    entities.addAll(pathMatches.map((match) => match.group(0)!));
    
    // URLs
    final urlPattern = RegExp(r'https?://[^\s]+');
    final urlMatches = urlPattern.allMatches(prompt);
    entities.addAll(urlMatches.map((match) => match.group(0)!));
    
    return entities.toSet().toList();
  }

  /// Classify intent
  String _classifyIntent(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    
    if (lowerPrompt.contains('help') || lowerPrompt.contains('how to')) {
      return 'help_request';
    } else if (lowerPrompt.contains('error') || lowerPrompt.contains('problem') || lowerPrompt.contains('issue')) {
      return 'problem_report';
    } else if (lowerPrompt.contains('create') || lowerPrompt.contains('make') || lowerPrompt.contains('build')) {
      return 'creation_request';
    } else if (lowerPrompt.contains('fix') || lowerPrompt.contains('solve') || lowerPrompt.contains('repair')) {
      return 'solution_request';
    }
    
    return 'general_inquiry';
  }

  /// Get file suggestions
  List<ContextSuggestion> _getFileSuggestions(String prompt, List files) {
    final suggestions = <ContextSuggestion>[];
    final promptWords = prompt.toLowerCase().split(' ');
    
    for (final file in files) {
      final fileName = file.toString().toLowerCase();
      var relevance = 0.0;
      
      // Check filename similarity
      for (final word in promptWords) {
        if (fileName.contains(word)) {
          relevance += 1.0;
        }
      }
      
      if (relevance > 0) {
        suggestions.add(ContextSuggestion(
          type: SuggestionType.file,
          content: file.toString(),
          relevanceScore: relevance,
          metadata: {'type': 'file', 'similarity': relevance},
        ));
      }
    }
    
    return suggestions;
  }

  /// Get command suggestions
  List<ContextSuggestion> _getCommandSuggestions(String prompt, List commands) {
    final suggestions = <ContextSuggestion>[];
    final promptWords = prompt.toLowerCase().split(' ');
    
    for (final command in commands) {
      final commandStr = command.toString().toLowerCase();
      var relevance = 0.0;
      
      // Check command similarity
      for (final word in promptWords) {
        if (commandStr.contains(word)) {
          relevance += 1.0;
        }
      }
      
      if (relevance > 0) {
        suggestions.add(ContextSuggestion(
          type: SuggestionType.command,
          content: command.toString(),
          relevanceScore: relevance,
          metadata: {'type': 'command', 'similarity': relevance},
        ));
      }
    }
    
    return suggestions;
  }

  /// Get directory suggestions
  List<ContextSuggestion> _getDirectorySuggestions(String prompt, List directories) {
    final suggestions = <ContextSuggestion>[];
    final promptWords = prompt.toLowerCase().split(' ');
    
    for (final directory in directories) {
      final dirStr = directory.toString().toLowerCase();
      var relevance = 0.0;
      
      // Check directory similarity
      for (final word in promptWords) {
        if (dirStr.contains(word)) {
          relevance += 1.0;
        }
      }
      
      if (relevance > 0) {
        suggestions.add(ContextSuggestion(
          type: SuggestionType.directory,
          content: directory.toString(),
          relevanceScore: relevance,
          metadata: {'type': 'directory', 'similarity': relevance},
        ));
      }
    }
    
    return suggestions;
  }

  /// Format context for code prompts
  String _formatContextForCode(Map<String, dynamic> context) {
    final formatted = StringBuffer();
    
    if (context.containsKey('currentFile')) {
      formatted.writeln('Current File: ${context['currentFile']}');
    }
    
    if (context.containsKey('openTabs')) {
      formatted.writeln('Open Tabs: ${(context['openTabs'] as List).join(', ')}');
    }
    
    if (context.containsKey('recentCommands')) {
      formatted.writeln('Recent Commands:');
      final commands = context['recentCommands'] as List;
      for (int i = 0; i < math.min(5, commands.length); i++) {
        formatted.writeln('  ${commands[i]}');
      }
    }
    
    return formatted.toString();
  }

  /// Format context for file operations
  String _formatContextForFiles(Map<String, dynamic> context) {
    final formatted = StringBuffer();
    
    if (context.containsKey('currentDirectory')) {
      formatted.writeln('Current Directory: ${context['currentDirectory']}');
    }
    
    if (context.containsKey('files')) {
      formatted.writeln('Files:');
      final files = context['files'] as List;
      for (final file in files.take(10)) {
        formatted.writeln('  $file');
      }
    }
    
    return formatted.toString();
  }

  /// Format context for system commands
  String _formatContextForSystem(Map<String, dynamic> context) {
    final formatted = StringBuffer();
    
    if (context.containsKey('environment')) {
      formatted.writeln('Environment Variables:');
      final env = context['environment'] as Map;
      env.forEach((key, value) {
        formatted.writeln('  $key=$value');
      });
    }
    
    if (context.containsKey('workingDirectory')) {
      formatted.writeln('Working Directory: ${context['workingDirectory']}');
    }
    
    return formatted.toString();
  }

  /// Format context for general prompts
  String _formatContextGeneric(Map<String, dynamic> context) {
    final formatted = StringBuffer();
    
    for (final entry in context.entries.take(10)) {
      formatted.writeln('${entry.key}: ${entry.value}');
    }
    
    return formatted.toString();
  }

  /// Optimize user prompt for code
  String _optimizeUserPromptForCode(String prompt, PromptAnalysis analysis) {
    // Remove redundant words and clarify intent
    var optimized = prompt;
    
    // Add clarification if ambiguous
    if (analysis.complexity > 5.0) {
      optimized += '\nPlease be specific about what you want to accomplish.';
    }
    
    return optimized;
  }

  /// Optimize user prompt for file operations
  String _optimizeUserPromptForFileOps(String prompt, PromptAnalysis analysis) {
    // Add specificity to file operations
    var optimized = prompt;
    
    if (!prompt.contains('path') && !prompt.contains('directory')) {
      optimized += '\nSpecify the target path if applicable.';
    }
    
    return optimized;
  }

  /// Optimize user prompt for system commands
  String _optimizeUserPromptForSystem(String prompt, PromptAnalysis analysis) {
    // Add context to system commands
    var optimized = prompt;
    
    if (analysis.entities.isEmpty) {
      optimized += '\nInclude relevant file paths or environment context.';
    }
    
    return optimized;
  }

  /// Optimize user prompt for general questions
  String _optimizeUserPromptForGeneral(String prompt, PromptAnalysis analysis) {
    // Add clarity to general questions
    var optimized = prompt;
    
    if (prompt.length < 10) {
      optimized += '\nPlease provide more details about what you need help with.';
    }
    
    return optimized;
  }

  /// Calculate context importance
  double _calculateContextImportance(String key, dynamic value, PromptAnalysis analysis) {
    var importance = 0.5; // Base importance
    
    // Boost importance based on key type
    if (key.contains('current') || key.contains('active')) {
      importance += 0.3;
    }
    
    if (key.contains('error') || key.contains('problem')) {
      importance += 0.4;
    }
    
    if (key.contains('file') && analysis.entities.isNotEmpty) {
      importance += 0.2;
    }
    
    return math.min(importance, 1.0);
  }

  /// Calculate context relevance for entry
  double _calculateContextRelevanceForEntry(String key, dynamic value, PromptAnalysis analysis) {
    // Simple relevance based on semantic keywords
    var relevance = 0.0;
    
    for (final keyword in analysis.semanticKeywords) {
      if (value.toString().toLowerCase().contains(keyword)) {
        relevance += 0.2;
      }
    }
    
    return math.min(relevance, 1.0);
  }

  /// Compress context value
  Future<dynamic> _compressContextValue(dynamic value) async {
    if (value is String) {
      final str = value as String;
      if (str.length > 200) {
        return '${str.substring(0, 200)}... [compressed]';
      }
    } else if (value is List) {
      final list = value as List;
      if (list.length > 10) {
        return list.take(10).toList()..add('[${list.length - 10} more items]');
      }
    }
    
    return value;
  }

  /// Aggressive compression
  Future<Map<String, dynamic>> _aggressiveCompression(
    Map<String, dynamic> context,
    int maxSize,
  ) async {
    final compressed = <String, dynamic>{};
    int currentSize = 0;
    
    // Prioritize by importance and add until size limit
    final sortedEntries = context.entries.toList()
      ..sort((a, b) => _calculateContextImportance(b.key, b.value, PromptAnalysis(promptType: PromptType.generalQuestion, complexity: 0.0, tokenEstimate: 0, contextRelevance: 0.0, semanticKeywords: [], entities: [], intent: ''))
        .compareTo(_calculateContextImportance(a.key, a.value, PromptAnalysis(promptType: PromptType.generalQuestion, complexity: 0.0, tokenEstimate: 0, contextRelevance: 0.0, semanticKeywords: [], entities: [], intent: ''))));
    
    for (final entry in sortedEntries) {
      final entrySize = _calculateEntrySize(entry.value);
      if (currentSize + entrySize > maxSize) break;
      
      compressed[entry.key] = entry.value;
      currentSize += entrySize;
    }
    
    return compressed;
  }

  /// Calculate context size
  int _calculateContextSize(Map<String, dynamic> context) {
    return context.toString().length;
  }

  /// Calculate entry size
  int _calculateEntrySize(dynamic value) {
    if (value is String) {
      return (value as String).length;
    } else if (value is List) {
      return (value as List).length;
    } else {
      return value.toString().length;
    }
  }

  /// Select code context
  Map<String, dynamic> _selectCodeContext(Map<String, dynamic> context, PromptAnalysis analysis) {
    final selected = <String, dynamic>{};
    
    // Prioritize code-related context
    if (context.containsKey('currentFile')) {
      selected['currentFile'] = context['currentFile'];
    }
    
    if (context.containsKey('openTabs')) {
      selected['openTabs'] = (context['openTabs'] as List).take(5);
    }
    
    if (context.containsKey('gitStatus')) {
      selected['gitStatus'] = context['gitStatus'];
    }
    
    return selected;
  }

  /// Select file operation context
  Map<String, dynamic> _selectFileOperationContext(Map<String, dynamic> context, PromptAnalysis analysis) {
    final selected = <String, dynamic>{};
    
    if (context.containsKey('currentDirectory')) {
      selected['currentDirectory'] = context['currentDirectory'];
    }
    
    if (context.containsKey('files')) {
      selected['files'] = (context['files'] as List).take(20);
    }
    
    if (context.containsKey('permissions')) {
      selected['permissions'] = context['permissions'];
    }
    
    return selected;
  }

  /// Select system command context
  Map<String, dynamic> _selectSystemCommandContext(Map<String, dynamic> context, PromptAnalysis analysis) {
    final selected = <String, dynamic>{};
    
    if (context.containsKey('environment')) {
      selected['environment'] = context['environment'];
    }
    
    if (context.containsKey('workingDirectory')) {
      selected['workingDirectory'] = context['workingDirectory'];
    }
    
    if (context.containsKey('path')) {
      selected['path'] = context['path'];
    }
    
    return selected;
  }

  /// Select general question context
  Map<String, dynamic> _selectGeneralQuestionContext(Map<String, dynamic> context, PromptAnalysis analysis) {
    final selected = <String, dynamic>{};
    
    // Include most relevant context for general questions
    final entries = context.entries.toList()
      ..sort((a, b) => _calculateContextImportance(b.key, b.value, analysis).compareTo(_calculateContextImportance(a.key, a.value, analysis)));
    
    for (final entry in entries.take(10)) {
      selected[entry.key] = entry.value;
    }
    
    return selected;
  }

  /// Apply user preferences
  void _applyUserPreferences(Map<String, dynamic> context, Map<String, dynamic> preferences) {
    // Apply user preferences to context selection
    if (preferences.containsKey('preferredContextTypes')) {
      // Filter context based on preferred types
      final preferredTypes = preferences['preferredContextTypes'] as List;
      // Implementation would filter context based on preferred types
    }
  }

  /// Calculate optimization metrics
  OptimizationMetrics _calculateOptimizationMetrics(
    String originalPrompt,
    OptimizedPrompt optimizedPrompt,
    Map<String, dynamic> originalContext,
    Map<String, dynamic> compressedContext,
  ) {
    return OptimizationMetrics(
      originalLength: originalPrompt.length,
      optimizedLength: optimizedPrompt.prompt.length,
      compressionRatio: 1.0 - (compressedContext.length / originalContext.length),
      tokenReduction: originalPrompt.length - optimizedPrompt.estimatedTokens,
      optimizations: optimizedPrompt.optimizations,
    );
  }

  /// Cache optimization
  Future<void> _cacheOptimization(
    String originalPrompt,
    OptimizedPrompt optimizedPrompt,
    Map<String, dynamic> context,
    OptimizationMetrics metrics,
  ) async {
    final cacheKey = _generateCacheKey(originalPrompt, context);
    
    _contextCache[cacheKey] = ContextCache(
      originalPrompt: originalPrompt,
      optimizedPrompt: optimizedPrompt,
      context: context,
      metrics: metrics,
      timestamp: DateTime.now(),
    );
    
    // Limit cache size
    if (_contextCache.length > 100) {
      final oldestKey = _contextCache.keys.first;
      _contextCache.remove(oldestKey);
    }
  }

  /// Generate cache key
  String _generateCacheKey(String prompt, Map<String, dynamic> context) {
    final contextHash = context.toString().length > 100 
        ? context.toString().substring(0, 100)
        : context.toString();
    
    return '${prompt.hashCode}_${contextHash.hashCode}';
  }

  /// Add to history
  void _addToHistory(String prompt, OptimizedPrompt optimizedPrompt, OptimizationMetrics metrics) {
    final history = PromptHistory(
      originalPrompt: prompt,
      optimizedPrompt: optimizedPrompt,
      metrics: metrics,
      timestamp: DateTime.now(),
    );
    
    _promptHistory.add(history);
    
    // Limit history size
    if (_promptHistory.length > _maxHistorySize) {
      _promptHistory.removeFirst();
    }
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Perform cleanup
  void _performCleanup() {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(hours: 1));
    
    // Remove old cache entries
    final expiredKeys = <String>[];
    for (final entry in _contextCache.entries) {
      if (entry.value.timestamp.isBefore(cutoff)) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _contextCache.remove(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      debugPrint('🧠 Cleaned ${expiredKeys.length} expired optimization cache entries');
    }
  }

  /// Dispose optimizer
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _optimizerController.close();
    
    _contextCache.clear();
    _promptHistory.clear();
    _optimizationMetrics.clear();
    
    debugPrint('🧠 Context-Aware Prompt Optimizer disposed');
  }
}

/// Optimized prompt
class OptimizedPrompt {
  final String prompt;
  final PromptType type;
  final int estimatedTokens;
  final Map<String, dynamic> contextUsed;
  final List<String> optimizations;
  
  OptimizedPrompt({
    required this.prompt,
    required this.type,
    required this.estimatedTokens,
    required this.contextUsed,
    required this.optimizations,
  });
}

/// Prompt analysis
class PromptAnalysis {
  final PromptType promptType;
  final double complexity;
  final int tokenEstimate;
  final double contextRelevance;
  final List<String> semanticKeywords;
  final List<String> entities;
  final String intent;
  
  PromptAnalysis({
    required this.promptType,
    required this.complexity,
    required this.tokenEstimate,
    required this.contextRelevance,
    required this.semanticKeywords,
    required this.entities,
    required this.intent,
  });
}

/// Context suggestion
class ContextSuggestion {
  final SuggestionType type;
  final String content;
  final double relevanceScore;
  final Map<String, dynamic> metadata;
  
  ContextSuggestion({
    required this.type,
    required this.content,
    required this.relevanceScore,
    required this.metadata,
  });
}

/// Context cache
class ContextCache {
  final String originalPrompt;
  final OptimizedPrompt optimizedPrompt;
  final Map<String, dynamic> context;
  final OptimizationMetrics metrics;
  final DateTime timestamp;
  
  ContextCache({
    required this.originalPrompt,
    required this.optimizedPrompt,
    required this.context,
    required this.metrics,
    required this.timestamp,
  });
}

/// Optimization metrics
class OptimizationMetrics {
  final int originalLength;
  final int optimizedLength;
  final double compressionRatio;
  final int tokenReduction;
  final List<String> optimizations;
  
  OptimizationMetrics({
    required this.originalLength,
    required this.optimizedLength,
    required this.compressionRatio,
    required this.tokenReduction,
    required this.optimizations,
  });
}

/// Prompt history
class PromptHistory {
  final String originalPrompt;
  final OptimizedPrompt optimizedPrompt;
  final OptimizationMetrics metrics;
  final DateTime timestamp;
  
  PromptHistory({
    required this.originalPrompt,
    required this.optimizedPrompt,
    required this.metrics,
    required this.timestamp,
  });
}

/// Optimizer event
class OptimizerEvent {
  final OptimizerEventType type;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  OptimizerEvent({
    required this.type,
    required this.timestamp,
    this.data,
  });
}

/// Enums
enum PromptType {
  codeRelated,
  fileOperation,
  systemCommand,
  generalQuestion,
}

enum SuggestionType {
  file,
  command,
  directory,
  general,
}

enum OptimizerEventType {
  optimizationCompleted,
  contextAnalyzed,
  suggestionGenerated,
}
