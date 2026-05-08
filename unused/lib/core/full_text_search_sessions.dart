import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Full-text search across terminal sessions
/// 
/// Features:
/// - Indexing of terminal session content for fast search
/// - Full-text search with highlighting and context
/// - Regular expression search support
/// - Search across multiple sessions simultaneously
/// - Search result ranking and relevance scoring
/// - Search history and bookmarking
/// - Advanced search filters (date, session type, command type)
class FullTextSearchSessions {
  static const int _maxIndexSize = 100000; // Max documents to index
  static const int _maxResults = 100;
  static const int _contextLines = 3; // Lines of context around matches
  static const Duration _indexingInterval = Duration(seconds: 30);
  
  final Map<String, SessionIndex> _sessionIndexes = {};
  final Map<String, List<SearchToken>> _invertedIndex = {};
  final Queue<SearchQuery> _searchHistory = Queue();
  final Map<String, SearchResult> _searchBookmarks = {};
  
  Timer? _indexingTimer;
  
  bool _isIndexing = false;
  bool _searchEnabled = true;
  int _totalDocuments = 0;
  int _totalSearches = 0;
  double _totalSearchTime = 0.0;

  FullTextSearchSessions() {
    _initializeSearchSystem();
  }

  /// Initialize the search system
  void _initializeSearchSystem() {
    _indexingTimer = Timer.periodic(_indexingInterval, (_) {
      _performIncrementalIndexing();
    });
  }

  /// Add or update session in search index
  Future<void> indexSession({
    required String sessionId,
    required String sessionName,
    required List<String> content,
    required DateTime createdAt,
    required DateTime lastModified,
    Map<String, dynamic>? metadata,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _isIndexing = true;
      
      // Remove old index if exists
      if (_sessionIndexes.containsKey(sessionId)) {
        await _removeSessionFromIndex(sessionId);
      }
      
      // Create new index
      final index = SessionIndex(
        sessionId: sessionId,
        sessionName: sessionName,
        content: content,
        createdAt: createdAt,
        lastModified: lastModified,
        metadata: metadata ?? {},
      );
      
      // Index content
      await _indexContent(index);
      
      // Add to session indexes
      _sessionIndexes[sessionId] = index;
      _totalDocuments++;
      
      debugPrint('🔍 Indexed session: $sessionName (${content.length} lines)');
      
    } catch (e) {
      debugPrint('Failed to index session: $e');
    } finally {
      _isIndexing = false;
      stopwatch.stop();
    }
  }

  /// Index session content
  Future<void> _indexContent(SessionIndex index) async {
    for (int lineNum = 0; lineNum < index.content.length; lineNum++) {
      final line = index.content[lineNum];
      
      // Tokenize line
      final tokens = _tokenizeText(line);
      
      // Add to inverted index
      for (final token in tokens) {
        _invertedIndex.putIfAbsent(token, () => []).add(SearchToken(
          token: token,
          sessionId: index.sessionId,
          lineNumber: lineNum,
          position: line.indexOf(token),
          context: _getContext(index.content, lineNum),
        ));
      }
    }
  }

  /// Tokenize text
  List<String> _tokenizeText(String text) {
    final tokens = <String>[];
    
    // Split by whitespace and punctuation
    final words = text.split(RegExp(r'[\s\W]+'));
    
    for (final word in words) {
      if (word.isNotEmpty) {
        // Add original word
        tokens.add(word.toLowerCase());
        
        // Add stemmed version (simplified)
        final stemmed = _stemWord(word.toLowerCase());
        if (stemmed != word.toLowerCase()) {
          tokens.add(stemmed);
        }
        
        // Add substrings for partial matching
        if (word.length > 3) {
          for (int i = 0; i <= word.length - 3; i++) {
            final substring = word.substring(i, i + 3).toLowerCase();
            tokens.add(substring);
          }
        }
      }
    }
    
    return tokens;
  }

  /// Simple stemming (Porter stemmer simplified)
  String _stemWord(String word) {
    if (word.endsWith('ing') && word.length > 4) {
      return word.substring(0, word.length - 3);
    }
    if (word.endsWith('ed') && word.length > 3) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && word.length > 2) {
      return word.substring(0, word.length - 1);
    }
    if (word.endsWith('ly') && word.length > 4) {
      return word.substring(0, word.length - 2);
    }
    return word;
  }

  /// Get context around a line
  List<String> _getContext(List<String> content, int lineNumber) {
    final context = <String>[];
    
    final start = max(0, lineNumber - _contextLines);
    final end = min(content.length - 1, lineNumber + _contextLines);
    
    for (int i = start; i <= end; i++) {
      context.add(content[i]);
    }
    
    return context;
  }

  /// Remove session from index
  Future<void> _removeSessionFromIndex(String sessionId) async {
    final index = _sessionIndexes[sessionId];
    if (index == null) return;
    
    // Remove from inverted index
    for (int lineNum = 0; lineNum < index.content.length; lineNum++) {
      final line = index.content[lineNum];
      final tokens = _tokenizeText(line);
      
      for (final token in tokens) {
        final tokenList = _invertedIndex[token];
        if (tokenList != null) {
          tokenList.removeWhere((t) => t.sessionId == sessionId);
          if (tokenList.isEmpty) {
            _invertedIndex.remove(token);
          }
        }
      }
    }
    
    _sessionIndexes.remove(sessionId);
    _totalDocuments--;
  }

  /// Search across all sessions
  Future<SearchResult> search(
    String query, {
    SearchType type = SearchType.text,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool regex = false,
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
    int? maxResults,
  }) async {
    if (!_searchEnabled || query.isEmpty) {
      return SearchResult.empty();
    }
    
    _totalSearches++;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Record search query
      _searchHistory.add(SearchQuery(
        query: query,
        type: type,
        timestamp: DateTime.now(),
        results: 0,
      ));
      
      // Keep only recent history
      if (_searchHistory.length > 1000) {
        _searchHistory.removeFirst();
      }
      
      List<SearchMatch> matches = [];
      
      switch (type) {
        case SearchType.text:
          matches = await _performTextSearch(
            query,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            sessionIds: sessionIds,
            startDate: startDate,
            endDate: endDate,
            fileTypes: fileTypes,
          );
          break;
        case SearchType.regex:
          matches = await _performRegexSearch(
            query,
            caseSensitive: caseSensitive,
            sessionIds: sessionIds,
            startDate: startDate,
            endDate: endDate,
            fileTypes: fileTypes,
          );
          break;
        case SearchType.fuzzy:
          matches = await _performFuzzySearch(
            query,
            sessionIds: sessionIds,
            startDate: startDate,
            endDate: endDate,
            fileTypes: fileTypes,
          );
          break;
      }
      
      // Rank and limit results
      matches = _rankResults(matches);
      final limitedMatches = matches.take(maxResults ?? _maxResults).toList();
      
      // Update search history
      if (_searchHistory.isNotEmpty) {
        _searchHistory.last.results = limitedMatches.length;
      }
      
      _totalSearchTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return SearchResult(
        query: query,
        type: type,
        matches: limitedMatches,
        totalMatches: matches.length,
        searchTime: stopwatch.elapsedMilliseconds.toDouble(),
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      debugPrint('Search failed: $e');
      return SearchResult.error(query, e.toString());
    } finally {
      stopwatch.stop();
    }
  }

  /// Perform text search
  Future<List<SearchMatch>> _performTextSearch(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
  }) async {
    final matches = <SearchMatch>[];
    final searchTerms = _tokenizeText(query);
    
    for (final term in searchTerms) {
      final tokens = _invertedIndex[term.toLowerCase()];
      if (tokens == null) continue;
      
      for (final token in tokens) {
        // Apply filters
        if (!_matchesFilters(token, sessionIds, startDate, endDate, fileTypes)) {
          continue;
        }
        
        // Check for exact match
        final session = _sessionIndexes[token.sessionId];
        if (session == null) continue;
        
        final line = session.content[token.lineNumber];
        if (!_matchesQuery(line, query, caseSensitive, wholeWord)) {
          continue;
        }
        
        matches.add(SearchMatch(
          sessionId: token.sessionId,
          sessionName: session.sessionName,
          lineNumber: token.lineNumber,
          content: line,
          context: token.context,
          position: token.position,
          score: _calculateScore(term, token, query),
        ));
      }
    }
    
    return matches;
  }

  /// Perform regex search
  Future<List<SearchMatch>> _performRegexSearch(
    String pattern, {
    bool caseSensitive = false,
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
  }) async {
    final matches = <SearchMatch>[];
    
    try {
      final regex = RegExp(
        pattern,
        caseSensitive: caseSensitive,
        multiLine: true,
      );
      
      for (final session in _sessionIndexes.values) {
        if (!_matchesSessionFilters(session, sessionIds, startDate, endDate, fileTypes)) {
          continue;
        }
        
        for (int lineNum = 0; lineNum < session.content.length; lineNum++) {
          final line = session.content[lineNum];
          final match = regex.firstMatch(line);
          
          if (match != null) {
            matches.add(SearchMatch(
              sessionId: session.sessionId,
              sessionName: session.sessionName,
              lineNumber: lineNum,
              content: line,
              context: _getContext(session.content, lineNum),
              position: match.start,
              score: _calculateRegexScore(match, line),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Invalid regex pattern: $e');
    }
    
    return matches;
  }

  /// Perform fuzzy search
  Future<List<SearchMatch>> _performFuzzySearch(
    String query, {
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
  }) async {
    final matches = <SearchMatch>[];
    final searchTerms = _tokenizeText(query);
    
    for (final session in _sessionIndexes.values) {
      if (!_matchesSessionFilters(session, sessionIds, startDate, endDate, fileTypes)) {
        continue;
      }
      
      for (int lineNum = 0; lineNum < session.content.length; lineNum++) {
        final line = session.content[lineNum];
        final lineTokens = _tokenizeText(line);
        
        // Calculate fuzzy match score
        double score = 0.0;
        int matchedTerms = 0;
        
        for (final term in searchTerms) {
          for (final lineToken in lineTokens) {
            final distance = _levenshteinDistance(term, lineToken);
            final maxLen = max(term.length, lineToken.length);
            final similarity = (maxLen - distance) / maxLen;
            
            if (similarity > 0.5) { // 50% similarity threshold
              score += similarity;
              matchedTerms++;
            }
          }
        }
        
        if (matchedTerms > 0) {
          final normalizedScore = score / searchTerms.length;
          
          if (normalizedScore > 0.3) { // Minimum score threshold
            matches.add(SearchMatch(
              sessionId: session.sessionId,
              sessionName: session.sessionName,
              lineNumber: lineNum,
              content: line,
              context: _getContext(session.content, lineNum),
              position: 0,
              score: normalizedScore,
            ));
          }
        }
      }
    }
    
    return matches;
  }

  /// Check if match meets filters
  bool _matchesFilters(
    SearchToken token,
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
  ) {
    final session = _sessionIndexes[token.sessionId];
    if (session == null) return false;
    
    // Session ID filter
    if (sessionIds != null && !sessionIds.contains(token.sessionId)) {
      return false;
    }
    
    // Date range filter
    if (startDate != null && session.lastModified.isBefore(startDate)) {
      return false;
    }
    if (endDate != null && session.lastModified.isAfter(endDate)) {
      return false;
    }
    
    // File type filter
    if (fileTypes != null) {
      final sessionType = session.metadata['type'] as String?;
      if (sessionType == null || !fileTypes.contains(sessionType)) {
        return false;
      }
    }
    
    return true;
  }

  /// Check if session meets filters
  bool _matchesSessionFilters(
    SessionIndex session,
    List<String>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? fileTypes,
  ) {
    // Session ID filter
    if (sessionIds != null && !sessionIds.contains(session.sessionId)) {
      return false;
    }
    
    // Date range filter
    if (startDate != null && session.lastModified.isBefore(startDate)) {
      return false;
    }
    if (endDate != null && session.lastModified.isAfter(endDate)) {
      return false;
    }
    
    // File type filter
    if (fileTypes != null) {
      final sessionType = session.metadata['type'] as String?;
      if (sessionType == null || !fileTypes.contains(sessionType)) {
        return false;
      }
    }
    
    return true;
  }

  /// Check if line matches query
  bool _matchesQuery(
    String line,
    String query,
    bool caseSensitive,
    bool wholeWord,
  ) {
    final searchLine = caseSensitive ? line : line.toLowerCase();
    final searchQuery = caseSensitive ? query : query.toLowerCase();
    
    if (wholeWord) {
      final words = searchLine.split(RegExp(r'[\s\W]+'));
      return words.contains(searchQuery);
    } else {
      return searchLine.contains(searchQuery);
    }
  }

  /// Calculate search score
  double _calculateScore(String term, SearchToken token, String query) {
    double score = 1.0;
    
    // Exact match bonus
    if (term == query.toLowerCase()) {
      score += 2.0;
    }
    
    // Position bonus (earlier in line)
    score += (1.0 - token.position / 100.0);
    
    // Length bonus (shorter lines are more relevant)
    score += (1.0 - token.content.length / 200.0);
    
    return score;
  }

  /// Calculate regex match score
  double _calculateRegexScore(RegExpMatch match, String line) {
    double score = 1.0;
    
    // Match length bonus
    score += match.group(0)!.length / 10.0;
    
    // Position bonus
    score += (1.0 - match.start / 100.0);
    
    return score;
  }

  /// Calculate Levenshtein distance
  int _levenshteinDistance(String a, String b) {
    if (a.length == 0) return b.length;
    if (b.length == 0) return a.length;
    
    final matrix = List.generate(
      b.length + 1,
      (i) => List.generate(a.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= b.length; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= a.length; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= b.length; i++) {
      for (int j = 1; j <= a.length; j++) {
        final cost = (b[i - 1] == a[j - 1]) ? 0 : 1;
        matrix[i][j] = min(
          matrix[i - 1][j] + 1,
          min(
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost,
          ),
        );
      }
    }
    
    return matrix[b.length][a.length];
  }

  /// Rank search results
  List<SearchMatch> _rankResults(List<SearchMatch> matches) {
    // Sort by score (descending)
    matches.sort((a, b) => b.score.compareTo(a.score));
    
    // Remove duplicates
    final seen = <String>{};
    final uniqueMatches = <SearchMatch>[];
    
    for (final match in matches) {
      final key = '${match.sessionId}:${match.lineNumber}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueMatches.add(match);
      }
    }
    
    return uniqueMatches;
  }

  /// Perform incremental indexing
  Future<void> _performIncrementalIndexing() async {
    if (_isIndexing) return;
    
    _isIndexing = true;
    try {
      debugPrint('🔍 Performing incremental indexing...');
      
      // Get list of all session files
      final sessionDir = Directory('${Platform.environment['HOME'] ?? ''}/.termisol/sessions');
      if (!await sessionDir.exists()) {
        return;
      }
      
      await for (final entity in sessionDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final lastModified = await entity.lastModified();
            final sessionIndex = _sessionIndexes[entity.path];
            
            // Only reindex if file was modified since last indexing
            if (sessionIndex == null || lastModified.isAfter(sessionIndex.lastIndexed)) {
              await _indexSessionFile(entity.path);
            }
          } catch (e) {
            debugPrint('⚠️ Error checking session file ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('✅ Incremental indexing completed');
    } catch (e) {
      debugPrint('❌ Error during incremental indexing: $e');
    } finally {
      _isIndexing = false;
    }
  }

  /// Get search suggestions
  List<String> getSearchSuggestions(String partialQuery) {
    final suggestions = <String>[];
    final partialLower = partialQuery.toLowerCase();
    
    // Get from search history
    for (final query in _searchHistory.reversed.take(50)) {
      if (query.query.toLowerCase().startsWith(partialLower)) {
        suggestions.add(query.query);
      }
    }
    
    // Get from indexed tokens
    for (final token in _invertedIndex.keys) {
      if (token.startsWith(partialLower)) {
        suggestions.add(token);
      }
    }
    
    // Remove duplicates and limit
    return suggestions.toSet().take(10).toList();
  }

  /// Bookmark search result
  void bookmarkResult(SearchResult result) {
    final key = '${result.query}:${result.timestamp.millisecondsSinceEpoch}';
    _searchBookmarks[key] = result;
  }

  /// Get bookmarked results
  List<SearchResult> getBookmarkedResults() {
    return _searchBookmarks.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Remove bookmark
  void removeBookmark(String query, DateTime timestamp) {
    final key = '${query}:${timestamp.millisecondsSinceEpoch}';
    _searchBookmarks.remove(key);
  }

  /// Get search statistics
  SearchStats getStats() {
    return SearchStats(
      totalDocuments: _totalDocuments,
      totalSearches: _totalSearches,
      averageSearchTime: _totalSearches > 0 ? _totalSearchTime / _totalSearches : 0.0,
      totalSearchTime: _totalSearchTime,
      indexedSessions: _sessionIndexes.length,
      indexedTokens: _invertedIndex.length,
      searchHistorySize: _searchHistory.length,
      bookmarkedResults: _searchBookmarks.length,
      isIndexing: _isIndexing,
      searchEnabled: _searchEnabled,
    );
  }

  /// Get search history
  List<SearchQuery> getSearchHistory({int? limit}) {
    final history = _searchHistory.reversed.toList();
    if (limit != null) {
      return history.take(limit).toList();
    }
    return history;
  }

  /// Clear search history
  void clearSearchHistory() {
    _searchHistory.clear();
  }

  /// Enable/disable search
  void setSearchEnabled(bool enabled) {
    _searchEnabled = enabled;
  }

  /// Rebuild entire index
  Future<void> rebuildIndex() async {
    debugPrint('🔍 Rebuilding search index...');
    
    _isIndexing = true;
    try {
      // Clear current index
      _sessionIndexes.clear();
      _invertedIndex.clear();
      _totalDocuments = 0;
      
      // Get list of all session files
      final sessionDir = Directory('${Platform.environment['HOME'] ?? ''}/.termisol/sessions');
      if (!await sessionDir.exists()) {
        debugPrint('⚠️ Session directory does not exist');
        return;
      }
      
      int indexedCount = 0;
      await for (final entity in sessionDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            await _indexSessionFile(entity.path);
            indexedCount++;
          } catch (e) {
            debugPrint('⚠️ Error indexing session file ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('✅ Search index rebuilt with $indexedCount sessions');
    } catch (e) {
      debugPrint('❌ Error rebuilding search index: $e');
    } finally {
      _isIndexing = false;
    }
  }

  /// Dispose search system
  void dispose() {
    _indexingTimer?.cancel();
    _sessionIndexes.clear();
    _invertedIndex.clear();
    _searchHistory.clear();
    _searchBookmarks.clear();
  }
}

/// Session index
class SessionIndex {
  final String sessionId;
  final String sessionName;
  final List<String> content;
  final DateTime createdAt;
  final DateTime lastModified;
  final Map<String, dynamic> metadata;

  const SessionIndex({
    required this.sessionId,
    required this.sessionName,
    required this.content,
    required this.createdAt,
    required this.lastModified,
    required this.metadata,
  });
}

/// Search token
class SearchToken {
  final String token;
  final String sessionId;
  final int lineNumber;
  final int position;
  final List<String> context;

  const SearchToken({
    required this.token,
    required this.sessionId,
    required this.lineNumber,
    required this.position,
    required this.context,
  });
}

/// Search query
class SearchQuery {
  final String query;
  final SearchType type;
  final DateTime timestamp;
  int results;

  SearchQuery({
    required this.query,
    required this.type,
    required this.timestamp,
    required this.results,
  });
}

/// Search match
class SearchMatch {
  final String sessionId;
  final String sessionName;
  final int lineNumber;
  final String content;
  final List<String> context;
  final int position;
  final double score;

  const SearchMatch({
    required this.sessionId,
    required this.sessionName,
    required this.lineNumber,
    required this.content,
    required this.context,
    required this.position,
    required this.score,
  });
}

/// Search result
class SearchResult {
  final String query;
  final SearchType type;
  final List<SearchMatch> matches;
  final int totalMatches;
  final double searchTime;
  final DateTime timestamp;
  final String? error;

  const SearchResult({
    required this.query,
    required this.type,
    required this.matches,
    required this.totalMatches,
    required this.searchTime,
    required this.timestamp,
    this.error,
  });

  factory SearchResult.empty() {
    return const SearchResult(
      query: '',
      type: SearchType.text,
      matches: [],
      totalMatches: 0,
      searchTime: 0.0,
      timestamp: null,
    );
  }

  factory SearchResult.error(String query, String error) {
    return SearchResult(
      query: query,
      type: SearchType.text,
      matches: [],
      totalMatches: 0,
      searchTime: 0.0,
      timestamp: DateTime.now(),
      error: error,
    );
  }
}

/// Search statistics
class SearchStats {
  final int totalDocuments;
  final int totalSearches;
  final double averageSearchTime;
  final double totalSearchTime;
  final int indexedSessions;
  final int indexedTokens;
  final int searchHistorySize;
  final int bookmarkedResults;
  final bool isIndexing;
  final bool searchEnabled;

  const SearchStats({
    required this.totalDocuments,
    required this.totalSearches,
    required this.averageSearchTime,
    required this.totalSearchTime,
    required this.indexedSessions,
    required this.indexedTokens,
    required this.searchHistorySize,
    required this.bookmarkedResults,
    required this.isIndexing,
    required this.searchEnabled,
  });
}

/// Search types
enum SearchType {
  text,
  regex,
  fuzzy,
}
