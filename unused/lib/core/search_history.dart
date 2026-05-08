import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Search History - Intelligent search suggestions and history
/// 
/// Implements comprehensive search history:
/// - Persistent search history with metadata
/// - Intelligent suggestions based on usage patterns
/// - Context-aware recommendations
/// - Search analytics and insights
/// - Privacy-preserving history management
class SearchHistory {
  bool _isInitialized = false;
  
  // Search history storage
  final List<SearchEntry> _history = [];
  final Map<String, SearchPattern> _patterns = {};
  final Map<String, SearchContext> _contexts = {};
  
  // Analytics
  final SearchAnalytics _analytics = SearchAnalytics();
  
  // Configuration
  SearchHistoryConfig _config = SearchHistoryConfig();
  
  // Privacy and cleanup
  final Map<String, DateTime> _lastAccessed = {};
  Timer? _cleanupTimer;
  
  SearchHistory();
  
  bool get isInitialized => _isInitialized;
  List<SearchEntry> get history => List.unmodifiable(_history);
  Map<String, SearchPattern> get patterns => Map.unmodifiable(_patterns);
  SearchAnalytics get analytics => _analytics;
  
  /// Initialize search history
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Load persistent data
      await _loadHistoryData();
      
      // Setup cleanup timer
      _setupCleanupTimer();
      
      _isInitialized = true;
      debugPrint('🔍 Search History initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Search History: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/search_history_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = SearchHistoryConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load search history config: $e');
    }
  }
  
  /// Load history data
  Future<void> _loadHistoryData() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/search_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        // Load history entries
        final historyData = data['history'] as List<dynamic>?;
        if (historyData != null) {
          _history.clear();
          for (final entry in historyData) {
            _history.add(SearchEntry.fromJson(entry as Map<String, dynamic>));
          }
        }
        
        // Load patterns
        final patternsData = data['patterns'] as Map<String, dynamic>?;
        if (patternsData != null) {
          for (final entry in patternsData.entries) {
            _patterns[entry.key] = SearchPattern.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        
        // Load contexts
        final contextsData = data['contexts'] as Map<String, dynamic>?;
        if (contextsData != null) {
          for (final entry in contextsData.entries) {
            _contexts[entry.key] = SearchContext.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        
        // Load analytics
        final analyticsData = data['analytics'] as Map<String, dynamic>?;
        if (analyticsData != null) {
          _analytics = SearchAnalytics.fromJson(analyticsData);
        }
        
        debugPrint('📂 Loaded ${_history.length} search history entries');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load search history data: $e');
    }
  }
  
  /// Setup cleanup timer
  void _setupCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      Duration(hours: _config.cleanupIntervalHours),
      (_) => _performCleanup(),
    );
    debugPrint('🧹 Search history cleanup timer started');
  }
  
  /// Add search to history
  void addSearch(
    String query,
    SearchType type,
    SearchSource source, {
    int? resultCount,
    Duration? duration,
    String? context,
    Map<String, dynamic>? metadata,
  }) {
    final entry = SearchEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      query: query,
      type: type,
      source: source,
      timestamp: DateTime.now(),
      resultCount: resultCount,
      duration: duration,
      context: context,
      metadata: metadata ?? {},
    );
    
    // Remove duplicate if exists
    _history.removeWhere((e) => e.query == query && e.type == type);
    
    // Add to history
    _history.insert(0, entry);
    
    // Limit history size
    while (_history.length > _config.maxHistorySize) {
      _history.removeLast();
    }
    
    // Update patterns
    _updateSearchPatterns(query);
    
    // Update context
    if (context != null) {
      _updateSearchContext(context, query);
    }
    
    // Update analytics
    _analytics.recordSearch(entry);
    
    // Update last accessed
    _lastAccessed[query] = DateTime.now();
    
    // Save to disk
    _saveHistoryData();
    
    debugPrint('🔍 Added search to history: $query');
  }
  
  /// Update search patterns
  void _updateSearchPatterns(String query) {
    final normalizedQuery = _normalizeQuery(query);
    
    // Extract patterns from query
    final patterns = _extractPatterns(normalizedQuery);
    
    for (final pattern in patterns) {
      if (!_patterns.containsKey(pattern)) {
        _patterns[pattern] = SearchPattern(
          pattern: pattern,
          frequency: 0,
          lastUsed: DateTime.now(),
          contexts: <String>[],
        );
      }
      
      final searchPattern = _patterns[pattern]!;
      searchPattern.frequency++;
      searchPattern.lastUsed = DateTime.now();
      
      // Add current context if available
      if (_history.isNotEmpty) {
        final currentContext = _history.first.context;
        if (currentContext != null && !searchPattern.contexts.contains(currentContext)) {
          searchPattern.contexts.add(currentContext);
        }
      }
    }
  }
  
  /// Update search context
  void _updateSearchContext(String context, String query) {
    if (!_contexts.containsKey(context)) {
      _contexts[context] = SearchContext(
        context: context,
        queries: <String>[],
        lastUsed: DateTime.now(),
        frequency: 0,
      );
    }
    
    final searchContext = _contexts[context]!;
    searchContext.queries.add(query);
    searchContext.lastUsed = DateTime.now();
    searchContext.frequency++;
    
    // Limit queries per context
    while (searchContext.queries.length > _config.maxQueriesPerContext) {
      searchContext.queries.removeAt(0);
    }
  }
  
  /// Normalize query for pattern matching
  String _normalizeQuery(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  /// Extract patterns from query
  List<String> _extractPatterns(String query) {
    final patterns = <String>[];
    final words = query.split(' ');
    
    // Add individual words
    patterns.addAll(words);
    
    // Add word prefixes
    for (final word in words) {
      if (word.length > 2) {
        for (int i = 2; i <= word.length; i++) {
          patterns.add(word.substring(0, i));
        }
      }
    }
    
    // Add word suffixes
    for (final word in words) {
      if (word.length > 2) {
        for (int i = word.length - 2; i < word.length; i++) {
          patterns.add(word.substring(i));
        }
      }
    }
    
    // Add common substrings
    for (final word in words) {
      if (word.length > 3) {
        for (int i = 0; i <= word.length - 3; i++) {
          for (int j = i + 3; j <= word.length; j++) {
            patterns.add(word.substring(i, j));
          }
        }
      }
    }
    
    return patterns.toSet().toList();
  }
  
  /// Get intelligent suggestions
  List<SearchSuggestion> getSuggestions(
    String partial, {
    SearchType? type,
    SearchSource? source,
    String? context,
    int maxSuggestions = 10,
    bool useAnalytics = true,
  }) {
    if (partial.trim().isEmpty) return [];
    
    final normalizedPartial = _normalizeQuery(partial);
    final suggestions = <SearchSuggestion>[];
    
    // History-based suggestions
    suggestions.addAll(_getHistorySuggestions(normalizedPartial, type, source));
    
    // Pattern-based suggestions
    suggestions.addAll(_getPatternSuggestions(normalizedPartial));
    
    // Context-based suggestions
    if (context != null) {
      suggestions.addAll(_getContextSuggestions(normalizedPartial, context));
    }
    
    // Analytics-based suggestions
    if (useAnalytics) {
      suggestions.addAll(_getAnalyticsSuggestions(normalizedPartial, type, source));
    }
    
    // Remove duplicates and sort by relevance
    final uniqueSuggestions = <String, SearchSuggestion>{};
    for (final suggestion in suggestions) {
      final key = suggestion.text.toLowerCase();
      if (!uniqueSuggestions.containsKey(key)) {
        uniqueSuggestions[key] = suggestion;
      }
    }
    
    final sortedSuggestions = uniqueSuggestions.values.toList()
      ..sort((a, b) => _calculateSuggestionScore(b, partial).compareTo(_calculateSuggestionScore(a, partial)));
    
    return sortedSuggestions.take(maxSuggestions).toList();
  }
  
  /// Get history-based suggestions
  List<SearchSuggestion> _getHistorySuggestions(
    String partial,
    SearchType? type,
    SearchSource? source,
  ) {
    final suggestions = <SearchSuggestion>[];
    
    for (final entry in _history) {
      if (type != null && entry.type != type) continue;
      if (source != null && entry.source != source) continue;
      
      final normalizedQuery = _normalizeQuery(entry.query);
      if (normalizedQuery.contains(partial)) {
        final score = _calculateHistoryScore(entry, partial);
        suggestions.add(SearchSuggestion(
          text: entry.query,
          type: SuggestionType.history,
          score: score,
          metadata: {
            'timestamp': entry.timestamp.toIso8601String(),
            'resultCount': entry.resultCount,
            'duration': entry.duration?.inMilliseconds,
          },
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Get pattern-based suggestions
  List<SearchSuggestion> _getPatternSuggestions(String partial) {
    final suggestions = <SearchSuggestion>[];
    
    for (final entry in _patterns.entries) {
      if (entry.key.contains(partial)) {
        final pattern = entry.value;
        final score = _calculatePatternScore(pattern, partial);
        suggestions.add(SearchSuggestion(
          text: entry.key,
          type: SuggestionType.pattern,
          score: score,
          metadata: {
            'frequency': pattern.frequency,
            'lastUsed': pattern.lastUsed.toIso8601String(),
            'contexts': pattern.contexts,
          },
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Get context-based suggestions
  List<SearchSuggestion> _getContextSuggestions(String partial, String context) {
    final suggestions = <SearchSuggestion>[];
    final searchContext = _contexts[context];
    
    if (searchContext != null) {
      for (final query in searchContext.queries) {
        if (_normalizeQuery(query).contains(partial)) {
          final score = _calculateContextScore(searchContext, query, partial);
          suggestions.add(SearchSuggestion(
            text: query,
            type: SuggestionType.context,
            score: score,
            metadata: {
              'context': context,
              'frequency': searchContext.frequency,
              'lastUsed': searchContext.lastUsed.toIso8601String(),
            },
          ));
        }
      }
    }
    
    return suggestions;
  }
  
  /// Get analytics-based suggestions
  List<SearchSuggestion> _getAnalyticsSuggestions(
    String partial,
    SearchType? type,
    SearchSource? source,
  ) {
    final suggestions = <SearchSuggestion>[];
    
    // Use analytics to suggest popular/trending searches
    final trending = _analytics.getTrendingSearches(type: type, source: source);
    
    for (final trend in trending) {
      if (_normalizeQuery(trend.query).contains(partial)) {
        final score = _calculateAnalyticsScore(trend, partial);
        suggestions.add(SearchSuggestion(
          text: trend.query,
          type: SuggestionType.analytics,
          score: score,
          metadata: {
            'trendScore': trend.score,
            'recentFrequency': trend.recentFrequency,
            'overallFrequency': trend.overallFrequency,
          },
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Calculate suggestion score
  double _calculateSuggestionScore(SearchSuggestion suggestion, String partial) {
    double score = suggestion.score;
    
    // Boost for exact prefix matches
    if (suggestion.text.toLowerCase().startsWith(partial.toLowerCase())) {
      score *= 1.5;
    }
    
    // Boost for recent usage
    final lastAccessed = _lastAccessed[suggestion.text.toLowerCase()];
    if (lastAccessed != null) {
      final hoursSince = DateTime.now().difference(lastAccessed!).inHours;
      score *= max(0.5, 1.0 - (hoursSince * 0.01));
    }
    
    return score;
  }
  
  /// Calculate history score
  double _calculateHistoryScore(SearchEntry entry, String partial) {
    double score = 1.0;
    
    // Recent usage bonus
    final hoursSince = DateTime.now().difference(entry.timestamp).inHours;
    score *= max(0.1, 1.0 - (hoursSince * 0.02));
    
    // Result count bonus
    if (entry.resultCount != null && entry.resultCount! > 0) {
      score *= 1.0 + (entry.resultCount! * 0.01);
    }
    
    // Duration penalty (slow searches get lower score)
    if (entry.duration != null) {
      final seconds = entry.duration!.inMilliseconds / 1000.0;
      score *= max(0.5, 1.0 - (seconds * 0.01));
    }
    
    return score;
  }
  
  /// Calculate pattern score
  double _calculatePatternScore(SearchPattern pattern, String partial) {
    double score = pattern.frequency.toDouble();
    
    // Recent usage bonus
    final hoursSince = DateTime.now().difference(pattern.lastUsed).inHours;
    score *= max(0.1, 1.0 - (hoursSince * 0.01));
    
    // Context diversity bonus
    score *= (1.0 + pattern.contexts.length * 0.1);
    
    return score;
  }
  
  /// Calculate context score
  double _calculateContextScore(SearchContext context, String query, String partial) {
    double score = context.frequency.toDouble();
    
    // Recent usage bonus
    final hoursSince = DateTime.now().difference(context.lastUsed).inHours;
    score *= max(0.1, 1.0 - (hoursSince * 0.01));
    
    return score;
  }
  
  /// Calculate analytics score
  double _calculateAnalyticsScore(TrendingSearch trend, String partial) {
    double score = trend.score;
    
    // Combine multiple factors
    score += trend.recentFrequency * 0.3;
    score += trend.overallFrequency * 0.2;
    
    return score;
  }
  
  /// Get popular searches
  List<SearchEntry> getPopularSearches({
    SearchType? type,
    SearchSource? source,
    int limit = 10,
    Duration? timeRange,
  }) {
    var filteredHistory = _history;
    
    // Filter by type
    if (type != null) {
      filteredHistory = filteredHistory.where((e) => e.type == type).toList();
    }
    
    // Filter by source
    if (source != null) {
      filteredHistory = filteredHistory.where((e) => e.source == source).toList();
    }
    
    // Filter by time range
    if (timeRange != null) {
      final cutoff = DateTime.now().subtract(timeRange!);
      filteredHistory = filteredHistory.where((e) => e.timestamp.isAfter(cutoff)).toList();
    }
    
    // Sort by frequency and recency
    filteredHistory.sort((a, b) {
      final scoreA = _calculateHistoryScore(a, '');
      final scoreB = _calculateHistoryScore(b, '');
      return scoreB.compareTo(scoreA);
    });
    
    return filteredHistory.take(limit).toList();
  }
  
  /// Get search trends
  List<SearchTrend> getSearchTrends({Duration? timeRange}) {
    final cutoff = timeRange != null 
        ? DateTime.now().subtract(timeRange!)
        : DateTime.now().subtract(const Duration(days: 7));
    
    final recentHistory = _history.where((e) => e.timestamp.isAfter(cutoff)).toList();
    final queryCounts = <String, int>{};
    
    // Count queries
    for (final entry in recentHistory) {
      final query = entry.query.toLowerCase();
      queryCounts[query] = (queryCounts[query] ?? 0) + 1;
    }
    
    // Create trends
    final trends = <SearchTrend>[];
    for (final entry in queryCounts.entries) {
      trends.add(SearchTrend(
        query: entry.key,
        count: entry.value,
        trend: _calculateTrend(entry.key, recentHistory),
      ));
    }
    
    // Sort by count
    trends.sort((a, b) => b.count.compareTo(a.count));
    
    return trends.take(20).toList();
  }
  
  /// Calculate trend for query
  SearchTrendType _calculateTrend(String query, List<SearchEntry> history) {
    final queryEntries = history.where((e) => e.query.toLowerCase() == query).toList();
    if (queryEntries.length < 2) return SearchTrendType.stable;
    
    // Compare recent vs older frequency
    final midPoint = queryEntries.length ~/ 2;
    final recentCount = queryEntries.take(midPoint).length;
    final olderCount = queryEntries.skip(midPoint).length;
    
    if (recentCount > olderCount * 1.5) {
      return SearchTrendType.rising;
    } else if (recentCount < olderCount * 0.5) {
      return SearchTrendType.falling;
    }
    
    return SearchTrendType.stable;
  }
  
  /// Clear search history
  void clearHistory({SearchType? type, SearchSource? source}) {
    if (type == null && source == null) {
      _history.clear();
      debugPrint('🗑️ Cleared all search history');
    } else {
      _history.removeWhere((entry) {
        if (type != null && entry.type != type) return false;
        if (source != null && entry.source != source) return false;
        return true;
      });
      debugPrint('🗑️ Cleared filtered search history');
    }
    
    _saveHistoryData();
  }
  
  /// Remove specific entry from history
  void removeEntry(String query, SearchType type) {
    _history.removeWhere((entry) => entry.query == query && entry.type == type);
    _saveHistoryData();
    debugPrint('🗑️ Removed search entry: $query');
  }
  
  /// Export search history
  String exportHistory({bool includeAnalytics = true}) {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'history': _history.map((e) => e.toJson()).toList(),
      'patterns': _patterns.map((k, v) => MapEntry(k, v.toJson())),
      'contexts': _contexts.map((k, v) => MapEntry(k, v.toJson())),
    };
    
    if (includeAnalytics) {
      data['analytics'] = _analytics.toJson();
    }
    
    return jsonEncode(data);
  }
  
  /// Import search history
  bool importHistory(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Validate version
      final version = data['version'] as String?;
      if (version != null && !version.startsWith('1.')) {
        debugPrint('⚠️ Unsupported search history version: $version');
        return false;
      }
      
      // Import history
      final historyData = data['history'] as List<dynamic>?;
      if (historyData != null) {
        _history.clear();
        for (final entry in historyData) {
          _history.add(SearchEntry.fromJson(entry as Map<String, dynamic>));
        }
      }
      
      // Import patterns
      final patternsData = data['patterns'] as Map<String, dynamic>?;
      if (patternsData != null) {
        for (final entry in patternsData.entries) {
          _patterns[entry.key] = SearchPattern.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      // Import contexts
      final contextsData = data['contexts'] as Map<String, dynamic>?;
      if (contextsData != null) {
        for (final entry in contextsData.entries) {
          _contexts[entry.key] = SearchContext.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      // Import analytics
      final analyticsData = data['analytics'] as Map<String, dynamic>?;
      if (analyticsData != null) {
        _analytics = SearchAnalytics.fromJson(analyticsData);
      }
      
      _saveHistoryData();
      debugPrint('📥 Imported search history successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import search history: $e');
      return false;
    }
  }
  
  /// Perform cleanup
  void _performCleanup() {
    try {
      // Remove old entries
      final cutoff = DateTime.now().subtract(Duration(days: _config.retentionDays));
      _history.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
      
      // Limit history size
      while (_history.length > _config.maxHistorySize) {
        _history.removeLast();
      }
      
      // Clean up patterns
      _patterns.removeWhere((key, pattern) {
        final daysSince = DateTime.now().difference(pattern.lastUsed).inDays;
        return daysSince > _config.patternRetentionDays;
      });
      
      // Clean up contexts
      _contexts.removeWhere((key, context) {
        final daysSince = DateTime.now().difference(context.lastUsed).inDays;
        return daysSince > _config.contextRetentionDays;
      });
      
      // Clean up last accessed
      final cutoffTime = DateTime.now().subtract(Duration(days: _config.lastAccessedRetentionDays));
      _lastAccessed.removeWhere((key, time) => time.isBefore(cutoffTime));
      
      _saveHistoryData();
      debugPrint('🧹 Search history cleanup completed');
    } catch (e) {
      debugPrint('⚠️ Failed to perform search history cleanup: $e');
    }
  }
  
  /// Save history data
  Future<void> _saveHistoryData() async {
    try {
      final data = {
        'version': '1.0',
        'lastSaved': DateTime.now().toIso8601String(),
        'history': _history.map((e) => e.toJson()).toList(),
        'patterns': _patterns.map((k, v) => MapEntry(k, v.toJson())),
        'contexts': _contexts.map((k, v) => MapEntry(k, v.toJson())),
        'analytics': _analytics.toJson(),
      };
      
      final historyFile = File('${Platform.environment['HOME']}/.termisol/search_history.json');
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save search history data: $e');
    }
  }
  
  /// Get search statistics
  SearchHistoryStatistics getStatistics() {
    return SearchHistoryStatistics(
      totalSearches: _history.length,
      uniqueQueries: _history.map((e) => e.query.toLowerCase()).toSet().length,
      averageResults: _history.isEmpty ? 0.0 : _history.map((e) => e.resultCount ?? 0).reduce((a, b) => a + b) / _history.length,
      averageDuration: _history.isEmpty ? 0.0 : _history.map((e) => e.duration?.inMilliseconds ?? 0).reduce((a, b) => a + b) / _history.length / 1000.0,
      topQueries: _analytics.getTopQueries(10),
      searchTypes: _analytics.getSearchTypeDistribution(),
      searchSources: _analytics.getSearchSourceDistribution(),
      lastCleanup: _lastAccessed.isNotEmpty ? _lastAccessed.values.reduce((a, b) => a.isBefore(b) ? a : b) : null,
    );
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await _saveHistoryData();
    
    _history.clear();
    _patterns.clear();
    _contexts.clear();
    _lastAccessed.clear();
    
    _isInitialized = false;
    debugPrint('🔍 Search History disposed');
  }
}

/// Search entry data structure
class SearchEntry {
  final String id;
  final String query;
  final SearchType type;
  final SearchSource source;
  final DateTime timestamp;
  final int? resultCount;
  final Duration? duration;
  final String? context;
  final Map<String, dynamic> metadata;
  
  SearchEntry({
    required this.id,
    required this.query,
    required this.type,
    required this.source,
    required this.timestamp,
    this.resultCount,
    this.duration,
    this.context,
    required this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'query': query,
    'type': type.toString(),
    'source': source.toString(),
    'timestamp': timestamp.toIso8601String(),
    'resultCount': resultCount,
    'duration': duration?.inMilliseconds,
    'context': context,
    'metadata': metadata,
  };
  
  factory SearchEntry.fromJson(Map<String, dynamic> json) => SearchEntry(
    id: json['id'] as String,
    query: json['query'] as String,
    type: SearchType.values.firstWhere(
      (t) => t.toString() == json['type'],
      orElse: () => SearchType.text,
    ),
    source: SearchSource.values.firstWhere(
      (s) => s.toString() == json['source'],
      orElse: () => SearchSource.manual,
    ),
    timestamp: DateTime.parse(json['timestamp'] as String),
    resultCount: json['resultCount'] as int?,
    duration: json['duration'] != null ? Duration(milliseconds: json['duration'] as int) : null,
    context: json['context'] as String?,
    metadata: json['metadata'] as Map<String, dynamic>? ?? {},
  );
}

/// Search pattern data structure
class SearchPattern {
  final String pattern;
  final int frequency;
  final DateTime lastUsed;
  final List<String> contexts;
  
  SearchPattern({
    required this.pattern,
    required this.frequency,
    required this.lastUsed,
    required this.contexts,
  });
  
  Map<String, dynamic> toJson() => {
    'pattern': pattern,
    'frequency': frequency,
    'lastUsed': lastUsed.toIso8601String(),
    'contexts': contexts,
  };
  
  factory SearchPattern.fromJson(Map<String, dynamic> json) => SearchPattern(
    pattern: json['pattern'] as String,
    frequency: json['frequency'] as int,
    lastUsed: DateTime.parse(json['lastUsed'] as String),
    contexts: List<String>.from(json['contexts'] as List? ?? []),
  );
}

/// Search context data structure
class SearchContext {
  final String context;
  final List<String> queries;
  final DateTime lastUsed;
  final int frequency;
  
  SearchContext({
    required this.context,
    required this.queries,
    required this.lastUsed,
    required this.frequency,
  });
  
  Map<String, dynamic> toJson() => {
    'context': context,
    'queries': queries,
    'lastUsed': lastUsed.toIso8601String(),
    'frequency': frequency,
  };
  
  factory SearchContext.fromJson(Map<String, dynamic> json) => SearchContext(
    context: json['context'] as String,
    queries: List<String>.from(json['queries'] as List? ?? []),
    lastUsed: DateTime.parse(json['lastUsed'] as String),
    frequency: json['frequency'] as int,
  );
}

/// Search suggestion data structure
class SearchSuggestion {
  final String text;
  final SuggestionType type;
  final double score;
  final Map<String, dynamic> metadata;
  
  SearchSuggestion({
    required this.text,
    required this.type,
    required this.score,
    required this.metadata,
  });
}

/// Search analytics data structure
class SearchAnalytics {
  final Map<String, TrendingSearch> _trendingSearches = {};
  final Map<SearchType, int> _typeDistribution = {};
  final Map<SearchSource, int> _sourceDistribution = {};
  
  SearchAnalytics();
  
  void recordSearch(SearchEntry entry) {
    // Update trending searches
    final query = entry.query.toLowerCase();
    if (!_trendingSearches.containsKey(query)) {
      _trendingSearches[query] = TrendingSearch(
        query: query,
        score: 0.0,
        recentFrequency: 0,
        overallFrequency: 0,
      );
    }
    
    final trend = _trendingSearches[query]!;
    trend.overallFrequency++;
    
    // Update recent frequency (last 24 hours)
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    if (entry.timestamp.isAfter(cutoff)) {
      trend.recentFrequency++;
    }
    
    // Update type distribution
    _typeDistribution[entry.type] = (_typeDistribution[entry.type] ?? 0) + 1;
    
    // Update source distribution
    _sourceDistribution[entry.source] = (_sourceDistribution[entry.source] ?? 0) + 1;
  }
  
  List<TrendingSearch> getTrendingSearches({SearchType? type, SearchSource? source}) {
    var trending = _trendingSearches.values.toList();
    
    // Sort by score
    trending.sort((a, b) => b.score.compareTo(a.score));
    
    return trending.take(20).toList();
  }
  
  List<String> getTopQueries(int limit) {
    return _trendingSearches.entries
        .toList()
        ..sort((a, b) => b.value.overallFrequency.compareTo(a.value.overallFrequency))
        .take(limit)
        .map((e) => e.key)
        .toList();
  }
  
  Map<SearchType, int> getSearchTypeDistribution() {
    return Map.unmodifiable(_typeDistribution);
  }
  
  Map<SearchSource, int> getSearchSourceDistribution() {
    return Map.unmodifiable(_sourceDistribution);
  }
  
  Map<String, dynamic> toJson() => {
    'trendingSearches': _trendingSearches.map((k, v) => MapEntry(k, v.toJson())),
    'typeDistribution': _typeDistribution.map((k, v) => MapEntry(k.toString(), v)),
    'sourceDistribution': _sourceDistribution.map((k, v) => MapEntry(k.toString(), v)),
  };
  
  factory SearchAnalytics.fromJson(Map<String, dynamic> json) {
    final analytics = SearchAnalytics();
    
    final trendingData = json['trendingSearches'] as Map<String, dynamic>?;
    if (trendingData != null) {
      for (final entry in trendingData.entries) {
        analytics._trendingSearches[entry.key] = TrendingSearch.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    
    final typeData = json['typeDistribution'] as Map<String, dynamic>?;
    if (typeData != null) {
      for (final entry in typeData.entries) {
        final type = SearchType.values.firstWhere(
          (t) => t.toString() == entry.key,
          orElse: () => SearchType.text,
        );
        analytics._typeDistribution[type] = entry.value as int;
      }
    }
    
    final sourceData = json['sourceDistribution'] as Map<String, dynamic>?;
    if (sourceData != null) {
      for (final entry in sourceData.entries) {
        final source = SearchSource.values.firstWhere(
          (s) => s.toString() == entry.key,
          orElse: () => SearchSource.manual,
        );
        analytics._sourceDistribution[source] = entry.value as int;
      }
    }
    
    return analytics;
  }
}

/// Trending search data structure
class TrendingSearch {
  final String query;
  final double score;
  final int recentFrequency;
  final int overallFrequency;
  
  TrendingSearch({
    required this.query,
    required this.score,
    required this.recentFrequency,
    required this.overallFrequency,
  });
  
  Map<String, dynamic> toJson() => {
    'query': query,
    'score': score,
    'recentFrequency': recentFrequency,
    'overallFrequency': overallFrequency,
  };
  
  factory TrendingSearch.fromJson(Map<String, dynamic> json) => TrendingSearch(
    query: json['query'] as String,
    score: (json['score'] as num).toDouble(),
    recentFrequency: json['recentFrequency'] as int,
    overallFrequency: json['overallFrequency'] as int,
  );
}

/// Search trend data structure
class SearchTrend {
  final String query;
  final int count;
  final SearchTrendType trend;
  
  SearchTrend({
    required this.query,
    required this.count,
    required this.trend,
  });
}

/// Search history configuration
class SearchHistoryConfig {
  final int maxHistorySize;
  final int retentionDays;
  final int patternRetentionDays;
  final int contextRetentionDays;
  final int maxQueriesPerContext;
  final int cleanupIntervalHours;
  final int lastAccessedRetentionDays;
  final bool enableAnalytics;
  final bool enablePrivacyMode;
  
  SearchHistoryConfig({
    this.maxHistorySize = 1000,
    this.retentionDays = 90,
    this.patternRetentionDays = 30,
    this.contextRetentionDays = 60,
    this.maxQueriesPerContext = 100,
    this.cleanupIntervalHours = 24,
    this.lastAccessedRetentionDays = 7,
    this.enableAnalytics = true,
    this.enablePrivacyMode = false,
  });
  
  Map<String, dynamic> toJson() => {
    'maxHistorySize': maxHistorySize,
    'retentionDays': retentionDays,
    'patternRetentionDays': patternRetentionDays,
    'contextRetentionDays': contextRetentionDays,
    'maxQueriesPerContext': maxQueriesPerContext,
    'cleanupIntervalHours': cleanupIntervalHours,
    'lastAccessedRetentionDays': lastAccessedRetentionDays,
    'enableAnalytics': enableAnalytics,
    'enablePrivacyMode': enablePrivacyMode,
  };
  
  factory SearchHistoryConfig.fromJson(Map<String, dynamic> json) => SearchHistoryConfig(
    maxHistorySize: json['maxHistorySize'] as int? ?? 1000,
    retentionDays: json['retentionDays'] as int? ?? 90,
    patternRetentionDays: json['patternRetentionDays'] as int? ?? 30,
    contextRetentionDays: json['contextRetentionDays'] as int? ?? 60,
    maxQueriesPerContext: json['maxQueriesPerContext'] as int? ?? 100,
    cleanupIntervalHours: json['cleanupIntervalHours'] as int? ?? 24,
    lastAccessedRetentionDays: json['lastAccessedRetentionDays'] as int? ?? 7,
    enableAnalytics: json['enableAnalytics'] as bool? ?? true,
    enablePrivacyMode: json['enablePrivacyMode'] as bool? ?? false,
  );
}

/// Search history statistics
class SearchHistoryStatistics {
  final int totalSearches;
  final int uniqueQueries;
  final double averageResults;
  final double averageDuration;
  final List<String> topQueries;
  final Map<SearchType, int> searchTypes;
  final Map<SearchSource, int> searchSources;
  final DateTime? lastCleanup;
  
  SearchHistoryStatistics({
    required this.totalSearches,
    required this.uniqueQueries,
    required this.averageResults,
    required this.averageDuration,
    required this.topQueries,
    required this.searchTypes,
    required this.searchSources,
    this.lastCleanup,
  });
}

/// Search type enumeration
enum SearchType {
  text,
  regex,
  fuzzy,
  file,
  command,
}

/// Search source enumeration
enum SearchSource {
  manual,
  suggestion,
  history,
  pattern,
  context,
  analytics,
}

/// Suggestion type enumeration
enum SuggestionType {
  history,
  pattern,
  context,
  analytics,
}

/// Search trend type enumeration
enum SearchTrendType {
  rising,
  falling,
  stable,
}
