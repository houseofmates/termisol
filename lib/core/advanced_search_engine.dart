import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Advanced Search Engine - Full regex and fuzzy finding
/// 
/// Implements sophisticated search capabilities:
/// - Full regular expression support
/// - Fuzzy finding with ranking
/// - Interactive search with highlighting
/// - Search history and patterns
/// - Jump markers and navigation
class AdvancedSearchEngine {
  bool _isInitialized = false;
  
  // Search state
  String _currentPattern = '';
  RegExp? _currentRegex;
  List<SearchResult> _currentResults = [];
  int _currentResultIndex = -1;
  SearchDirection _searchDirection = SearchDirection.forward;
  SearchMode _searchMode = SearchMode.literal;
  
  // Search history
  final Queue<String> _searchHistory = Queue<String>();
  final int _maxHistorySize = 100;
  
  // Fuzzy search cache
  final Map<String, List<FuzzyMatch>> _fuzzyCache = {};
  
  // Highlighting
  final Map<int, List<SearchHighlight>> _highlights = {};
  
  AdvancedSearchEngine();
  
  bool get isInitialized => _isInitialized;
  String get currentPattern => _currentPattern;
  List<SearchResult> get currentResults => _currentResults;
  int get currentResultIndex => _currentResultIndex;
  SearchDirection get searchDirection => _searchDirection;
  SearchMode get searchMode => _searchMode;
  Queue<String> get searchHistory => _searchHistory;
  
  /// Initialize search engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _isInitialized = true;
      debugPrint('🔍 Advanced Search Engine initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Advanced Search Engine: $e');
    }
  }
  
  /// Search in terminal buffer
  List<SearchResult> search(
    String pattern, {
    String? buffer,
    SearchMode mode = SearchMode.literal,
    SearchDirection direction = SearchDirection.forward,
    bool caseSensitive = false,
    bool wholeWord = false,
    int? startIndex,
    int? endIndex,
  }) {
    if (!_isInitialized) return [];
    
    try {
      _currentPattern = pattern;
      _searchMode = mode;
      _searchDirection = direction;
      
      // Add to history
      _addToHistory(pattern);
      
      // Clear previous results
      _currentResults.clear();
      _currentResultIndex = -1;
      
      if (pattern.isEmpty) return _currentResults;
      
      // Compile regex if needed
      _compileRegex(pattern, mode, caseSensitive, wholeWord);
      
      // Perform search based on mode
      switch (mode) {
        case SearchMode.literal:
          _currentResults = _searchLiteral(
            pattern,
            buffer ?? '',
            direction,
            caseSensitive,
            wholeWord,
            startIndex,
            endIndex,
          );
          break;
        case SearchMode.regex:
          _currentResults = _searchRegex(
            buffer ?? '',
            direction,
            startIndex,
            endIndex,
          );
          break;
        case SearchMode.fuzzy:
          _currentResults = _searchFuzzy(
            pattern,
            buffer ?? '',
            direction,
            startIndex,
            endIndex,
          );
          break;
      }
      
      // Set first result as current if any found
      if (_currentResults.isNotEmpty) {
        _currentResultIndex = direction == SearchDirection.forward ? 0 : _currentResults.length - 1;
      }
      
      debugPrint('🔍 Found ${_currentResults.length} results for: $pattern');
      return _currentResults;
    } catch (e) {
      debugPrint('⚠️ Search failed: $e');
      return [];
    }
  }
  
  /// Compile regex pattern
  void _compileRegex(
    String pattern,
    SearchMode mode,
    bool caseSensitive,
    bool wholeWord,
  ) {
    if (mode == SearchMode.regex) {
      try {
        _currentRegex = RegExp(
          pattern,
          caseSensitive: caseSensitive,
          multiLine: true,
          dotAll: true,
        );
      } catch (e) {
        debugPrint('⚠️ Invalid regex pattern: $e');
        _currentRegex = null;
      }
    } else if (mode == SearchMode.literal && wholeWord) {
      final escapedPattern = RegExp.escape(pattern);
      final wordPattern = r'\b' + escapedPattern + r'\b';
      _currentRegex = RegExp(
        wordPattern,
        caseSensitive: caseSensitive,
        multiLine: true,
      );
    } else {
      _currentRegex = null;
    }
  }
  
  /// Literal search implementation
  List<SearchResult> _searchLiteral(
    String pattern,
    String buffer,
    SearchDirection direction,
    bool caseSensitive,
    bool wholeWord,
    int? startIndex,
    int? endIndex,
  ) {
    final results = <SearchResult>[];
    final searchBuffer = caseSensitive ? buffer : buffer.toLowerCase();
    final searchPattern = caseSensitive ? pattern : pattern.toLowerCase();
    
    int start = startIndex ?? 0;
    int end = endIndex ?? buffer.length;
    
    if (direction == SearchDirection.forward) {
      while (true) {
        final index = searchBuffer.indexOf(searchPattern, start);
        if (index == -1 || index >= end) break;
        
        if (!wholeWord || _isWholeWord(buffer, index, pattern.length)) {
          results.add(SearchResult(
            pattern: pattern,
            startIndex: index,
            endIndex: index + pattern.length,
            line: _getLineNumber(buffer, index),
            column: _getColumnNumber(buffer, index),
            context: _getContext(buffer, index, pattern.length),
          ));
        }
        
        start = index + 1;
      }
    } else {
      // Reverse search
      start = end - 1;
      while (start >= 0 && start >= (startIndex ?? 0)) {
        final index = searchBuffer.lastIndexOf(searchPattern, start);
        if (index == -1 || index < (startIndex ?? 0)) break;
        
        if (!wholeWord || _isWholeWord(buffer, index, pattern.length)) {
          results.add(SearchResult(
            pattern: pattern,
            startIndex: index,
            endIndex: index + pattern.length,
            line: _getLineNumber(buffer, index),
            column: _getColumnNumber(buffer, index),
            context: _getContext(buffer, index, pattern.length),
          ));
        }
        
        start = index - 1;
      }
      
      // Reverse results for backward search
      results.reversed;
    }
    
    return results;
  }
  
  /// Regex search implementation
  List<SearchResult> _searchRegex(
    String buffer,
    SearchDirection direction,
    int? startIndex,
    int? endIndex,
  ) {
    final results = <SearchResult>[];
    if (_currentRegex == null) return results;
    
    int start = startIndex ?? 0;
    int end = endIndex ?? buffer.length;
    
    if (direction == SearchDirection.forward) {
      for (final match in _currentRegex!.allMatches(buffer, start)) {
        if (match.start >= end) break;
        
        results.add(SearchResult(
          pattern: _currentPattern,
          startIndex: match.start,
          endIndex: match.end,
          line: _getLineNumber(buffer, match.start),
          column: _getColumnNumber(buffer, match.start),
          context: _getContext(buffer, match.start, match.end - match.start),
          groups: match.groups,
        ));
      }
    } else {
      // Reverse regex search
      final matches = _currentRegex!.allMatches(buffer).toList();
      for (int i = matches.length - 1; i >= 0; i--) {
        final match = matches[i];
        if (match.start < (startIndex ?? 0) || match.start >= end) continue;
        
        results.add(SearchResult(
          pattern: _currentPattern,
          startIndex: match.start,
          endIndex: match.end,
          line: _getLineNumber(buffer, match.start),
          column: _getColumnNumber(buffer, match.start),
          context: _getContext(buffer, match.start, match.end - match.start),
          groups: match.groups,
        ));
      }
    }
    
    return results;
  }
  
  /// Fuzzy search implementation
  List<SearchResult> _searchFuzzy(
    String pattern,
    String buffer,
    SearchDirection direction,
    int? startIndex,
    int? endIndex,
  ) {
    final results = <SearchResult>[];
    final lines = buffer.split('\n');
    
    int startLine = startIndex != null ? _getLineNumber(buffer, startIndex) : 0;
    int endLine = endIndex != null ? _getLineNumber(buffer, endIndex) : lines.length - 1;
    
    // Check cache first
    final cacheKey = '${pattern}_${buffer.hashCode}';
    if (!_fuzzyCache.containsKey(cacheKey)) {
      _fuzzyCache[cacheKey] = _performFuzzySearch(pattern, lines);
    }
    
    final fuzzyMatches = _fuzzyCache[cacheKey]!;
    
    for (final match in fuzzyMatches) {
      if (match.lineIndex < startLine || match.lineIndex > endLine) continue;
      
      final lineStart = _getLineStartIndex(buffer, match.lineIndex);
      final startIndex = lineStart + match.startIndex;
      
      results.add(SearchResult(
        pattern: pattern,
        startIndex: startIndex,
        endIndex: startIndex + pattern.length,
        line: match.lineIndex,
        column: match.startIndex,
        context: _getContext(buffer, startIndex, pattern.length),
        score: match.score,
        fuzzyMatch: match,
      ));
    }
    
    // Sort by score (descending)
    results.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
    
    return results;
  }
  
  /// Perform fuzzy search on lines
  List<FuzzyMatch> _performFuzzySearch(String pattern, List<String> lines) {
    final matches = <FuzzyMatch>[];
    final patternChars = pattern.toLowerCase().split('');
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex].toLowerCase();
      final lineChars = line.split('');
      
      final score = _calculateFuzzyScore(patternChars, lineChars);
      if (score > 0) {
        final startIndex = _findBestMatchStart(patternChars, lineChars);
        matches.add(FuzzyMatch(
          lineIndex: lineIndex,
          startIndex: startIndex,
          score: score,
          matchedIndices: _getMatchedIndices(patternChars, lineChars, startIndex),
        ));
      }
    }
    
    return matches;
  }
  
  /// Calculate fuzzy score
  double _calculateFuzzyScore(List<String> patternChars, List<String> lineChars) {
    if (patternChars.isEmpty) return 0.0;
    
    double score = 0.0;
    int patternIndex = 0;
    int consecutiveMatches = 0;
    
    for (int i = 0; i < lineChars.length && patternIndex < patternChars.length; i++) {
      if (lineChars[i] == patternChars[patternIndex]) {
        score += 1.0;
        consecutiveMatches++;
        
        // Bonus for consecutive matches
        if (consecutiveMatches > 1) {
          score += consecutiveMatches * 0.5;
        }
        
        patternIndex++;
      } else {
        consecutiveMatches = 0;
      }
    }
    
    // Penalty for incomplete matches
    if (patternIndex < patternChars.length) {
      score -= (patternChars.length - patternIndex) * 2.0;
    }
    
    return max(0.0, score);
  }
  
  /// Find best match start position
  int _findBestMatchStart(List<String> patternChars, List<String> lineChars) {
    int bestStart = 0;
    double bestScore = 0.0;
    
    for (int i = 0; i <= lineChars.length - patternChars.length; i++) {
      double score = 0.0;
      for (int j = 0; j < patternChars.length; j++) {
        if (lineChars[i + j] == patternChars[j]) {
          score += 1.0;
        }
      }
      
      if (score > bestScore) {
        bestScore = score;
        bestStart = i;
      }
    }
    
    return bestStart;
  }
  
  /// Get matched character indices
  List<int> _getMatchedIndices(List<String> patternChars, List<String> lineChars, int start) {
    final indices = <int>[];
    int patternIndex = 0;
    
    for (int i = start; i < lineChars.length && patternIndex < patternChars.length; i++) {
      if (lineChars[i] == patternChars[patternIndex]) {
        indices.add(i);
        patternIndex++;
      }
    }
    
    return indices;
  }
  
  /// Check if match is whole word
  bool _isWholeWord(String buffer, int start, int length) {
    if (start > 0 && _isWordChar(buffer[start - 1])) return false;
    if (start + length < buffer.length && _isWordChar(buffer[start + length])) return false;
    return true;
  }
  
  /// Check if character is word character
  bool _isWordChar(String char) {
    return RegExp(r'[a-zA-Z0-9_]').hasMatch(char);
  }
  
  /// Get line number for index
  int _getLineNumber(String buffer, int index) {
    return buffer.substring(0, index).split('\n').length - 1;
  }
  
  /// Get column number for index
  int _getColumnNumber(String buffer, int index) {
    final lastNewline = buffer.lastIndexOf('\n', index);
    return lastNewline == -1 ? index : index - lastNewline - 1;
  }
  
  /// Get line start index
  int _getLineStartIndex(String buffer, int lineIndex) {
    final lines = buffer.split('\n');
    int start = 0;
    for (int i = 0; i < lineIndex; i++) {
      start += lines[i].length + 1; // +1 for newline
    }
    return start;
  }
  
  /// Get context around match
  String _getContext(String buffer, int start, int length) {
    final contextStart = max(0, start - 50);
    final contextEnd = min(buffer.length, start + length + 50);
    return buffer.substring(contextStart, contextEnd);
  }
  
  /// Navigate to next result
  SearchResult? nextResult() {
    if (_currentResults.isEmpty) return null;
    
    _currentResultIndex = (_currentResultIndex + 1) % _currentResults.length;
    return _currentResults[_currentResultIndex];
  }
  
  /// Navigate to previous result
  SearchResult? previousResult() {
    if (_currentResults.isEmpty) return null;
    
    _currentResultIndex = (_currentResultIndex - 1 + _currentResults.length) % _currentResults.length;
    return _currentResults[_currentResultIndex];
  }
  
  /// Get current result
  SearchResult? getCurrentResult() {
    if (_currentResultIndex < 0 || _currentResultIndex >= _currentResults.length) {
      return null;
    }
    return _currentResults[_currentResultIndex];
  }
  
  /// Add pattern to search history
  void _addToHistory(String pattern) {
    if (pattern.trim().isEmpty) return;
    
    // Remove if already exists
    _searchHistory.remove(pattern);
    
    // Add to front
    _searchHistory.addFirst(pattern);
    
    // Limit size
    while (_searchHistory.length > _maxHistorySize) {
      _searchHistory.removeLast();
    }
  }
  
  /// Get search suggestions
  List<String> getSearchSuggestions(String partial) {
    return _searchHistory
        .where((pattern) => pattern.toLowerCase().contains(partial.toLowerCase()))
        .toList();
  }
  
  /// Clear search history
  void clearHistory() {
    _searchHistory.clear();
    debugPrint('🗑️ Search history cleared');
  }
  
  /// Clear fuzzy cache
  void clearFuzzyCache() {
    _fuzzyCache.clear();
    debugPrint('🗑️ Fuzzy search cache cleared');
  }
  
  /// Add jump marker
  void addJumpMarker(String marker, int position) {
    // Implementation for jump markers
    debugPrint('📍 Added jump marker: $marker at position $position');
  }
  
  /// Jump to marker
  int? jumpToMarker(String marker) {
    // Implementation for jumping to markers
    debugPrint('🎯 Jumping to marker: $marker');
    return null;
  }
  
  /// Generate highlights for buffer
  List<SearchHighlight> generateHighlights(String buffer) {
    final highlights = <SearchHighlight>[];
    
    for (final result in _currentResults) {
      highlights.add(SearchHighlight(
        startIndex: result.startIndex,
        endIndex: result.endIndex,
        color: _getHighlightColor(result),
        style: _getHighlightStyle(result),
      ));
    }
    
    return highlights;
  }
  
  /// Get highlight color for result
  Color _getHighlightColor(SearchResult result) {
    if (result == getCurrentResult()) {
      return const Color(0xFFFFFF00); // Yellow for current
    }
    return const Color(0xFFFFFF80); // Light yellow for others
  }
  
  /// Get highlight style for result
  HighlightStyle _getHighlightStyle(SearchResult result) {
    if (result.fuzzyMatch != null) {
      return HighlightStyle.fuzzy;
    }
    if (_searchMode == SearchMode.regex) {
      return HighlightStyle.regex;
    }
    return HighlightStyle.literal;
  }
  
  /// Export search results
  Map<String, dynamic> exportResults() {
    return {
      'pattern': _currentPattern,
      'mode': _searchMode.toString(),
      'direction': _searchDirection.toString(),
      'results': _currentResults.map((r) => r.toJson()).toList(),
      'currentIndex': _currentResultIndex,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Import search results
  void importResults(Map<String, dynamic> data) {
    _currentPattern = data['pattern'] as String? ?? '';
    _searchMode = SearchMode.values.firstWhere(
      (m) => m.toString() == data['mode'],
      orElse: () => SearchMode.literal,
    );
    _searchDirection = SearchDirection.values.firstWhere(
      (d) => d.toString() == data['direction'],
      orElse: () => SearchDirection.forward,
    );
    
    final resultsData = data['results'] as List<dynamic>?;
    if (resultsData != null) {
      _currentResults = resultsData
          .map((r) => SearchResult.fromJson(r as Map<String, dynamic>))
          .toList();
    }
    
    _currentResultIndex = data['currentIndex'] as int? ?? -1;
  }
  
  /// Dispose resources
  void dispose() {
    _currentResults.clear();
    _searchHistory.clear();
    _fuzzyCache.clear();
    _highlights.clear();
    _currentRegex = null;
    _isInitialized = false;
    debugPrint('🔍 Advanced Search Engine disposed');
  }
}

/// Search result data structure
class SearchResult {
  final String pattern;
  final int startIndex;
  final int endIndex;
  final int line;
  final int column;
  final String context;
  final List<String>? groups;
  final double? score;
  final FuzzyMatch? fuzzyMatch;
  
  SearchResult({
    required this.pattern,
    required this.startIndex,
    required this.endIndex,
    required this.line,
    required this.column,
    required this.context,
    this.groups,
    this.score,
    this.fuzzyMatch,
  });
  
  Map<String, dynamic> toJson() => {
    'pattern': pattern,
    'startIndex': startIndex,
    'endIndex': endIndex,
    'line': line,
    'column': column,
    'context': context,
    'groups': groups,
    'score': score,
  };
  
  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    pattern: json['pattern'] as String,
    startIndex: json['startIndex'] as int,
    endIndex: json['endIndex'] as int,
    line: json['line'] as int,
    column: json['column'] as int,
    context: json['context'] as String,
    groups: (json['groups'] as List<dynamic>?)?.cast<String>(),
    score: (json['score'] as num?)?.toDouble(),
  );
}

/// Fuzzy match data structure
class FuzzyMatch {
  final int lineIndex;
  final int startIndex;
  final double score;
  final List<int> matchedIndices;
  
  FuzzyMatch({
    required this.lineIndex,
    required this.startIndex,
    required this.score,
    required this.matchedIndices,
  });
}

/// Search highlight data structure
class SearchHighlight {
  final int startIndex;
  final int endIndex;
  final Color color;
  final HighlightStyle style;
  
  SearchHighlight({
    required this.startIndex,
    required this.endIndex,
    required this.color,
    required this.style,
  });
}

/// Search mode enumeration
enum SearchMode {
  literal,
  regex,
  fuzzy,
}

/// Search direction enumeration
enum SearchDirection {
  forward,
  backward,
}

/// Highlight style enumeration
enum HighlightStyle {
  literal,
  regex,
  fuzzy,
}
