import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'enhanced_search_engine.dart';
import '../ai/ai_terminal_assistant.dart';

/// Semantic Search Engine
///
/// Uses AI to understand search intent and provide intelligent results.
/// Supports natural language queries and context-aware search.
class SemanticSearchEngine {
  final EnhancedSearchEngine _searchEngine;
  final AITerminalAssistant _aiAssistant;
  final StreamController<SearchResult> _resultController =
      StreamController<SearchResult>.broadcast();

  Stream<SearchResult> get results => _resultController.stream;

  final Map<String, SearchContext> _contexts = {};
  final List<SearchQuery> _queryHistory = [];
  final int _maxHistorySize = 100;

  bool _isActive = false;
  bool get isActive => _isActive;

  SemanticSearchEngine(this._searchEngine, this._aiAssistant);

  /// Initialize the semantic search engine
  Future<void> initialize() async {
    if (_isActive) return;

    await _searchEngine.initialize();
    await _aiAssistant.initialize();

    _isActive = true;
    debugPrint('🔍 Semantic Search Engine initialized');
  }

  /// Perform semantic search with natural language understanding
  Future<SearchResult> semanticSearch(
    String query,
    {
      String? directory,
      SearchContext? context,
      bool useAI = true,
    }
  ) async {
    if (!_isActive) throw Exception('Semantic search engine not initialized');

    final startTime = DateTime.now();
    final searchQuery = SearchQuery(
      query: query,
      timestamp: startTime,
      context: context,
      useAI: useAI,
    );

    _queryHistory.add(searchQuery);
    if (_queryHistory.length > _maxHistorySize) {
      _queryHistory.removeAt(0);
    }

    try {
      // Parse query intent using AI
      final intent = useAI ? await _parseQueryIntent(query) : SearchIntent.literal;

      // Build search parameters based on intent
      final searchParams = await _buildSearchParams(query, intent, context);

      // Execute search
      final rawResults = await _searchEngine.search(
        searchParams.query,
        directory: searchParams.directory,
        include: searchParams.include,
        exclude: searchParams.exclude,
        caseSensitive: searchParams.caseSensitive,
        maxResults: searchParams.maxResults,
      );

      // Process and rank results semantically
      final processedResults = await _processResults(rawResults, intent, query);

      final result = SearchResult(
        query: searchQuery,
        intent: intent,
        results: processedResults,
        duration: DateTime.now().difference(startTime),
        success: true,
      );

      _resultController.add(result);
      return result;

    } catch (e) {
      debugPrint('❌ Semantic search failed: $e');

      final result = SearchResult(
        query: searchQuery,
        intent: SearchIntent.literal,
        results: [],
        duration: DateTime.now().difference(startTime),
        success: false,
        error: e.toString(),
      );

      _resultController.add(result);
      return result;
    }
  }

  /// Parse query intent using AI
  Future<SearchIntent> _parseQueryIntent(String query) async {
    final lowerQuery = query.toLowerCase();

    // Quick pattern-based intent detection
    if (lowerQuery.contains('error') || lowerQuery.contains('fail')) {
      return SearchIntent.error;
    }
    if (lowerQuery.contains('function') || lowerQuery.contains('method') || lowerQuery.contains('class')) {
      return SearchIntent.code;
    }
    if (lowerQuery.contains('log') || lowerQuery.contains('output')) {
      return SearchIntent.log;
    }
    if (lowerQuery.contains('config') || lowerQuery.contains('setting')) {
      return SearchIntent.config;
    }
    if (lowerQuery.contains('test') || lowerQuery.contains('spec')) {
      return SearchIntent.test;
    }

    // Use AI for complex queries
    try {
      final aiAnalysis = await _aiAssistant.processAiQuery(
        'Analyze this search query and determine the intent. Query: "$query". '
        'Possible intents: error, code, log, config, test, literal. '
        'Return only the intent type.'
      );

      switch (aiAnalysis.toLowerCase().trim()) {
        case 'error':
          return SearchIntent.error;
        case 'code':
          return SearchIntent.code;
        case 'log':
          return SearchIntent.log;
        case 'config':
          return SearchIntent.config;
        case 'test':
          return SearchIntent.test;
        default:
          return SearchIntent.literal;
      }
    } catch (e) {
      debugPrint('⚠️ AI intent parsing failed, using literal: $e');
      return SearchIntent.literal;
    }
  }

  /// Build search parameters based on intent
  Future<SearchParams> _buildSearchParams(
    String query,
    SearchIntent intent,
    SearchContext? context,
  ) async {
    String processedQuery = query;
    String? directory = context?.directory;
    List<String>? include;
    List<String>? exclude;
    bool caseSensitive = false;
    int maxResults = 100;

    switch (intent) {
      case SearchIntent.error:
        // Search for error patterns
        include = ['*.log', '*.txt', '*.md', '*.js', '*.py', '*.dart'];
        processedQuery = r'(?i)(error|exception|fail|crash|bug|issue)';
        break;

      case SearchIntent.code:
        // Search in code files
        include = ['*.js', '*.ts', '*.dart', '*.py', '*.java', '*.cpp', '*.c', '*.h'];
        if (query.contains('function') || query.contains('method')) {
          processedQuery = r'function\s+\w+|def\s+\w+|void\s+\w+';
        } else if (query.contains('class')) {
          processedQuery = r'class\s+\w+';
        }
        break;

      case SearchIntent.log:
        // Search in log files
        include = ['*.log', '*.out', '*.txt'];
        exclude = ['node_modules/**', '.git/**'];
        break;

      case SearchIntent.config:
        // Search in config files
        include = ['*.json', '*.yaml', '*.yml', '*.toml', '*.ini', '*.conf', '*.env'];
        break;

      case SearchIntent.test:
        // Search in test files
        include = ['*test*.js', '*test*.ts', '*test*.dart', '*test*.py', '*spec*.js', '*spec*.ts'];
        break;

      case SearchIntent.literal:
        // Literal search
        break;
    }

    // Handle context-specific searches
    if (context != null) {
      if (context.currentFile != null) {
        directory = context.currentFile;
      }
      if (context.projectType != null) {
        include = _getProjectSpecificIncludes(context.projectType!);
      }
    }

    return SearchParams(
      query: processedQuery,
      directory: directory,
      include: include,
      exclude: exclude,
      caseSensitive: caseSensitive,
      maxResults: maxResults,
    );
  }

  /// Get project-specific file includes
  List<String>? _getProjectSpecificIncludes(String projectType) {
    switch (projectType.toLowerCase()) {
      case 'flutter':
      case 'dart':
        return ['*.dart', 'pubspec.yaml', '*.md'];
      case 'nodejs':
      case 'javascript':
      case 'typescript':
        return ['*.js', '*.ts', 'package.json', '*.md'];
      case 'python':
        return ['*.py', 'requirements.txt', 'setup.py', '*.md'];
      case 'react':
        return ['*.jsx', '*.tsx', '*.js', '*.ts', 'package.json'];
      case 'vue':
        return ['*.vue', '*.js', '*.ts', 'package.json'];
      default:
        return null;
    }
  }

  /// Process and rank search results semantically
  Future<List<SemanticSearchResult>> _processResults(
    List<SearchResultItem> rawResults,
    SearchIntent intent,
    String originalQuery,
  ) async {
    final processedResults = <SemanticSearchResult>[];

    for (final rawResult in rawResults) {
      // Calculate relevance score
      final relevanceScore = await _calculateRelevance(
        rawResult,
        intent,
        originalQuery,
      );

      // Generate AI-powered summary if relevant
      String? summary;
      if (relevanceScore > 0.7) {
        try {
          summary = await _aiAssistant.processAiQuery(
            'Summarize what this code/file does in 1-2 sentences: ${rawResult.content?.substring(0, 200) ?? rawResult.path}'
          );
        } catch (e) {
          // Ignore AI summary errors
        }
      }

      processedResults.add(SemanticSearchResult(
        path: rawResult.path,
        lineNumber: rawResult.lineNumber,
        content: rawResult.content,
        relevanceScore: relevanceScore,
        intent: intent,
        summary: summary,
        context: _extractContext(rawResult),
      ));
    }

    // Sort by relevance
    processedResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return processedResults.take(50).toList(); // Limit to top 50
  }

  /// Calculate relevance score for a result
  Future<double> _calculateRelevance(
    SearchResultItem result,
    SearchIntent intent,
    String query,
  ) async {
    double score = 0.5; // Base score

    final content = (result.content ?? '').toLowerCase();
    final path = result.path.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Keyword matching
    if (content.contains(lowerQuery)) {
      score += 0.3;
    }

    // Path relevance
    switch (intent) {
      case SearchIntent.error:
        if (path.contains('log') || path.contains('error')) score += 0.2;
        break;
      case SearchIntent.code:
        if (path.contains('src') || path.contains('lib')) score += 0.2;
        break;
      case SearchIntent.test:
        if (path.contains('test') || path.contains('spec')) score += 0.2;
        break;
      case SearchIntent.config:
        if (path.contains('config') || path.contains('.env')) score += 0.2;
        break;
      case SearchIntent.log:
        if (path.endsWith('.log') || path.contains('log')) score += 0.2;
        break;
      case SearchIntent.literal:
        break;
    }

    // AI-powered relevance if available
    try {
      final aiRelevance = await _aiAssistant.processAiQuery(
        'Rate the relevance of this search result to the query "$query" on a scale of 0-1. '
        'Result: ${result.content?.substring(0, 100) ?? result.path}. '
        'Return only the number.'
      );

      final aiScore = double.tryParse(aiRelevance.trim()) ?? 0.0;
      score = (score + aiScore) / 2; // Average with AI score
    } catch (e) {
      // Use algorithmic score only
    }

    return score.clamp(0.0, 1.0);
  }

  /// Extract context around search result
  List<String> _extractContext(SearchResultItem result, {int contextLines = 3}) {
    if (result.content == null) return [];

    final lines = result.content!.split('\n');
    final lineIndex = result.lineNumber - 1; // Convert to 0-based

    final start = (lineIndex - contextLines).clamp(0, lines.length - 1);
    final end = (lineIndex + contextLines + 1).clamp(0, lines.length);

    return lines.sublist(start, end);
  }

  /// Update search context
  void updateContext(String key, SearchContext context) {
    _contexts[key] = context;
  }

  /// Get search context
  SearchContext? getContext(String key) {
    return _contexts[key];
  }

  /// Get search history
  List<SearchQuery> getSearchHistory() {
    return List.unmodifiable(_queryHistory);
  }

  /// Clear search history
  void clearHistory() {
    _queryHistory.clear();
  }

  /// Get search suggestions based on history and context
  List<String> getSuggestions(String partialQuery) {
    final suggestions = <String>[];

    // Recent queries
    final recentQueries = _queryHistory.reversed
        .where((q) => q.query.startsWith(partialQuery))
        .take(5)
        .map((q) => q.query)
        .toList();
    suggestions.addAll(recentQueries);

    // Context-based suggestions
    if (partialQuery.toLowerCase().contains('error')) {
      suggestions.addAll(['find errors in logs', 'search for exceptions', 'check error codes']);
    }
    if (partialQuery.toLowerCase().contains('function')) {
      suggestions.addAll(['find function definitions', 'search methods', 'locate class methods']);
    }

    return suggestions.toSet().toList(); // Remove duplicates
  }

  /// Dispose resources
  void dispose() {
    _resultController.close();
    _isActive = false;
  }
}

/// Search intent types
enum SearchIntent {
  literal,  // Exact string matching
  error,    // Error and exception search
  code,     // Code structure search
  log,      // Log file search
  config,   // Configuration file search
  test,     // Test file search
}

/// Search parameters
class SearchParams {
  final String query;
  final String? directory;
  final List<String>? include;
  final List<String>? exclude;
  final bool caseSensitive;
  final int maxResults;

  SearchParams({
    required this.query,
    this.directory,
    this.include,
    this.exclude,
    required this.caseSensitive,
    required this.maxResults,
  });
}

/// Search context
class SearchContext {
  final String? directory;
  final String? currentFile;
  final String? projectType;
  final List<String>? recentFiles;
  final Map<String, dynamic>? metadata;

  SearchContext({
    this.directory,
    this.currentFile,
    this.projectType,
    this.recentFiles,
    this.metadata,
  });
}

/// Search query record
class SearchQuery {
  final String query;
  final DateTime timestamp;
  final SearchContext? context;
  final bool useAI;

  SearchQuery({
    required this.query,
    required this.timestamp,
    this.context,
    required this.useAI,
  });
}

/// Semantic search result
class SemanticSearchResult {
  final String path;
  final int? lineNumber;
  final String? content;
  final double relevanceScore;
  final SearchIntent intent;
  final String? summary;
  final List<String> context;

  SemanticSearchResult({
    required this.path,
    this.lineNumber,
    this.content,
    required this.relevanceScore,
    required this.intent,
    this.summary,
    required this.context,
  });

  String get displayPath => '$path${lineNumber != null ? ':$lineNumber' : ''}';
}

/// Overall search result
class SearchResult {
  final SearchQuery query;
  final SearchIntent intent;
  final List<SemanticSearchResult> results;
  final Duration duration;
  final bool success;
  final String? error;

  SearchResult({
    required this.query,
    required this.intent,
    required this.results,
    required this.duration,
    required this.success,
    this.error,
  });

  int get totalResults => results.length;
  double get averageRelevance => results.isEmpty
      ? 0.0
      : results.map((r) => r.relevanceScore).reduce((a, b) => a + b) / results.length;
}