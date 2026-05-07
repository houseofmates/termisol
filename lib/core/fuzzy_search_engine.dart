import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Fuzzy Search Engine - Advanced fuzzy finding with ranking algorithms
/// 
/// Implements sophisticated fuzzy search:
/// - Multiple ranking algorithms (Levenshtein, Jaro-Winkler, etc.)
/// - Context-aware scoring
/// - Performance optimization with caching
/// - Multi-dimensional ranking
/// - Smart suggestions and learning
class FuzzySearchEngine {
  bool _isInitialized = false;
  
  // Search algorithms
  final Map<String, RankingAlgorithm> _algorithms = {};
  RankingAlgorithm _currentAlgorithm = RankingAlgorithm.levenshtein;
  
  // Performance optimization
  final Map<String, List<FuzzyMatch>> _matchCache = {};
  final Map<String, double> _scoreCache = {};
  final Map<String, String> _patternCache = {};
  
  // Learning and adaptation
  final Map<String, double> _patternWeights = {};
  final Map<String, int> _patternFrequencies = {};
  final Map<String, DateTime> _lastUsedPatterns = {};
  
  // Configuration
  FuzzySearchConfig _config = FuzzySearchConfig();
  
  FuzzySearchEngine();
  
  bool get isInitialized => _isInitialized;
  RankingAlgorithm get currentAlgorithm => _currentAlgorithm;
  FuzzySearchConfig get config => _config;
  
  /// Initialize fuzzy search engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize ranking algorithms
      _initializeAlgorithms();
      
      // Load learning data
      await _loadLearningData();
      
      _isInitialized = true;
      debugPrint('🔍 Fuzzy Search Engine initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Fuzzy Search Engine: $e');
    }
  }
  
  /// Initialize ranking algorithms
  void _initializeAlgorithms() {
    _algorithms.addAll({
      'levenshtein': LevenshteinAlgorithm(),
      'jaro_winkler': JaroWinklerAlgorithm(),
      'damerau_levenshtein': DamerauLevenshteinAlgorithm(),
      'qgram': QGramAlgorithm(),
      'soundex': SoundexAlgorithm(),
      'metaphone': MetaphoneAlgorithm(),
      'ngram': NGramAlgorithm(),
      'weighted': WeightedAlgorithm(),
    });
  }
  
  /// Load learning data
  Future<void> _loadLearningData() async {
    try {
      // Load pattern weights and frequencies
      final learningFile = File('${Directory.systemTemp.path}/fuzzy_learning.json');
      if (await learningFile.exists()) {
        final content = await learningFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _patternWeights = Map<String, double>.from(
          data['patternWeights'] as Map<String, dynamic>? ?? {}
        );
        _patternFrequencies = Map<String, int>.from(
          data['patternFrequencies'] as Map<String, dynamic>? ?? {}
        );
        _lastUsedPatterns = Map<String, DateTime>.from(
          data['lastUsedPatterns'] as Map<String, dynamic>? ?? {}
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load learning data: $e');
    }
  }
  
  /// Search with fuzzy finding
  List<FuzzyMatch> search(
    String pattern, {
    List<String> candidates,
    String? buffer,
    int maxResults = 10,
    double minScore = 0.3,
    bool useCache = true,
    RankingAlgorithm? algorithm,
    FuzzySearchOptions? options,
  }) {
    if (!_isInitialized) return [];
    
    try {
      final searchAlgorithm = algorithm ?? _currentAlgorithm;
      final searchOptions = options ?? _config.defaultOptions;
      
      // Update pattern usage
      _updatePatternUsage(pattern);
      
      // Check cache first
      if (useCache) {
        final cacheKey = _getCacheKey(pattern, candidates, searchAlgorithm, searchOptions);
        if (_matchCache.containsKey(cacheKey)) {
          return _matchCache[cacheKey]!;
        }
      }
      
      // Preprocess candidates
      final processedCandidates = _preprocessCandidates(candidates, searchOptions);
      
      // Perform fuzzy search
      final matches = _performFuzzySearch(
        pattern,
        processedCandidates,
        searchAlgorithm,
        searchOptions,
      );
      
      // Apply post-processing
      final finalMatches = _postProcessMatches(matches, pattern, searchOptions);
      
      // Filter by minimum score
      final filteredMatches = finalMatches
          .where((match) => match.score >= minScore)
          .take(maxResults)
          .toList();
      
      // Cache results
      if (useCache) {
        _matchCache[cacheKey] = filteredMatches;
      }
      
      debugPrint('🔍 Fuzzy search: $pattern -> ${filteredMatches.length} matches');
      return filteredMatches;
    } catch (e) {
      debugPrint('⚠️ Fuzzy search failed: $e');
      return [];
    }
  }
  
  /// Preprocess candidates
  List<String> _preprocessCandidates(List<String> candidates, FuzzySearchOptions options) {
    final processed = <String>[];
    
    for (final candidate in candidates) {
      String processed = candidate;
      
      // Apply preprocessing options
      if (options.ignoreCase) {
        processed = processed.toLowerCase();
      }
      
      if (options.ignoreWhitespace) {
        processed = processed.replaceAll(RegExp(r'\s+'), '');
      }
      
      if (options.normalizeUnicode) {
        processed = _normalizeUnicode(processed);
      }
      
      if (options.removeDiacritics) {
        processed = _removeDiacritics(processed);
      }
      
      processed.add(processed);
    }
    
    return processed;
  }
  
  /// Perform fuzzy search with specified algorithm
  List<FuzzyMatch> _performFuzzySearch(
    String pattern,
    List<String> candidates,
    RankingAlgorithm algorithm,
    FuzzySearchOptions options,
  ) {
    final algorithmImpl = _algorithms[algorithm.toString()];
    if (algorithmImpl == null) return [];
    
    final matches = <FuzzyMatch>[];
    
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final originalCandidate = options.ignoreCase 
          ? candidates[i].toUpperCase() 
          : candidates[i];
      
      // Calculate similarity score
      final score = algorithmImpl.calculateSimilarity(pattern, candidate, options);
      
      if (score > 0) {
        final match = FuzzyMatch(
          candidate: originalCandidate,
          score: score,
          algorithm: algorithm,
          index: i,
          details: _getMatchDetails(pattern, candidate, score, algorithm),
        );
        
        matches.add(match);
      }
    }
    
    // Sort by score (descending)
    matches.sort((a, b) => b.score.compareTo(a.score));
    
    return matches;
  }
  
  /// Get match details
  Map<String, dynamic> _getMatchDetails(
    String pattern,
    String candidate,
    double score,
    RankingAlgorithm algorithm,
  ) {
    final details = <String, dynamic>{
      'algorithm': algorithm.toString(),
      'score': score,
    };
    
    // Add algorithm-specific details
    switch (algorithm) {
      case RankingAlgorithm.levenshtein:
        details['distance'] = _levenshteinDistance(pattern, candidate);
        break;
      case RankingAlgorithm.jaro_winkler:
        details['jaroScore'] = _jaroWinklerScore(pattern, candidate);
        details['winklerScore'] = _winklerScore(pattern, candidate);
        break;
      case RankingAlgorithm.qgram:
        details['qgramSimilarity'] = _qgramSimilarity(pattern, candidate, 2);
        break;
      case RankingAlgorithm.soundex:
        details['soundexCode'] = _soundexCode(candidate);
        break;
      case RankingAlgorithm.metaphone:
        details['metaphoneCode'] = _metaphoneCode(candidate);
        break;
    }
    
    return details;
  }
  
  /// Post-process matches
  List<FuzzyMatch> _postProcessMatches(
    List<FuzzyMatch> matches,
    String pattern,
    FuzzySearchOptions options,
  ) {
    // Apply learning weights
    for (final match in matches) {
      final patternWeight = _patternWeights[pattern] ?? 1.0;
      final frequencyBonus = _getFrequencyBonus(match.candidate);
      final recencyBonus = _getRecencyBonus(match.candidate);
      
      match.score = match.score * patternWeight * frequencyBonus * recencyBonus;
    }
    
    // Apply context-aware scoring
    if (options.useContext && _config.contextScoring) {
      _applyContextScoring(matches, pattern, options);
    }
    
    return matches;
  }
  
  /// Get frequency bonus
  double _getFrequencyBonus(String pattern) {
    final frequency = _patternFrequencies[pattern] ?? 1;
    // Higher frequency = lower bonus (common patterns)
    return 1.0 / (1.0 + frequency * 0.1);
  }
  
  /// Get recency bonus
  double _getRecencyBonus(String pattern) {
    final lastUsed = _lastUsedPatterns[pattern];
    if (lastUsed == null) return 1.0;
    
    final daysSinceUsed = DateTime.now().difference(lastUsed!).inDays;
    // More recent = higher bonus
    return max(0.1, 1.0 - daysSinceUsed * 0.1);
  }
  
  /// Apply context-aware scoring
  void _applyContextScoring(List<FuzzyMatch> matches, String pattern, FuzzySearchOptions options) {
    // Implementation for context-aware scoring
    // This would consider factors like:
    // - Recent search history
    // - File type preferences
    // - Directory context
    // - User behavior patterns
  }
  
  /// Update pattern usage
  void _updatePatternUsage(String pattern) {
    _patternFrequencies[pattern] = (_patternFrequencies[pattern] ?? 0) + 1;
    _lastUsedPatterns[pattern] = DateTime.now();
  }
  
  /// Get cache key
  String _getCacheKey(
    String pattern,
    List<String> candidates,
    RankingAlgorithm algorithm,
    FuzzySearchOptions options,
  ) {
    final parts = [
      pattern,
      candidates.length.toString(),
      algorithm.toString(),
      options.toString(),
    ];
    return parts.join('|');
  }
  
  /// Normalize Unicode
  String _normalizeUnicode(String text) {
    // Implementation for Unicode normalization
    // This would handle:
    // - Unicode normalization forms
    // - Case folding
    // - Compatibility decomposition
    return text.toLowerCase();
  }
  
  /// Remove diacritics
  String _removeDiacritics(String text) {
    // Implementation for diacritic removal
    // This would strip accents and other diacritical marks
    return text;
  }
  
  // Algorithm implementations
  
  /// Levenshtein distance
  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(s1.length + 1, (_) => List.filled(s2.length + 1, 0));
    
    for (int i = 0; i <= s1.length; i++) {
      for (int j = 0; j <= s2.length; j++) {
        if (i == 0 && j == 0) {
          matrix[i][j] = 0;
        } else if (i == 0) {
          matrix[i][j] = matrix[i][j - 1] + 1;
        } else if (j == 0) {
          matrix[i][j] = matrix[i - 1][j] + 1;
        } else {
          final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
          matrix[i][j] = min(
            matrix[i - 1][j] + 1,
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost,
          );
        }
      }
    }
    
    return matrix[s1.length][s2.length];
  }
  
  /// Jaro-Winkler score
  double _jaroWinklerScore(String s1, String s2) {
    if (s1 == s2) return 1.0;
    
    final len1 = s1.length;
    final len2 = s2.length;
    final maxLen = max(len1, len2);
    final matchDistance = (maxLen / 2).floor();
    
    int matches = 0;
    int transpositions = 0;
    
    for (int i = 0; i < matchDistance; i++) {
      if (i < len1 && i < len2 && s1[i] == s2[i]) {
        matches++;
      }
    }
    
    if (matches == 0) return 0.0;
    
    // Calculate Jaro distance
    final jaroDistance = (
      (matches / len1) +
      (matches / len2) +
      ((matches - transpositions / 2) / maxLen)
    ) / 3.0;
    
    // Calculate Winkler bonus
    int prefix = 0;
    for (int i = 0; i < min(4, min(len1, len2)); i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      }
    }
    
    final winklerBonus = prefix / 10.0;
    
    return jaroDistance + winklerBonus;
  }
  
  /// Winkler score
  double _winklerScore(String s1, String s2) {
    return _jaroWinklerScore(s1, s2);
  }
  
  /// Q-gram similarity
  double _qgramSimilarity(String s1, String s2, int q) {
    final qgrams1 = _getQGrams(s1, q);
    final qgrams2 = _getQGrams(s2, q);
    
    final intersection = qgrams1.intersection(qgrams2.toSet()).length;
    final union = qgrams1.toSet().union(qgrams2.toSet()).length;
    
    return union == 0 ? 0.0 : (2.0 * intersection) / union;
  }
  
  /// Get Q-grams
  Set<String> _getQGrams(String text, int q) {
    final qgrams = <String>{};
    
    for (int i = 0; i <= text.length - q; i++) {
      qgrams.add(text.substring(i, i + q));
    }
    
    return qgrams;
  }
  
  /// Soundex code
  String _soundexCode(String text) {
    if (text.isEmpty) return '0000';
    
    final first = text[0].toUpperCase();
    String code = first;
    
    // Soundex encoding rules
    final Map<String, String> soundexMap = {
      'B': '1', 'F': '1', 'P': '1', 'V': '1',
      'C': '2', 'G': '2', 'J': '2', 'K': '2', 'Q': '2', 'S': '2', 'X': '2', 'Z': '2',
      'D': '3', 'T': '3',
      'L': '4', 'M': 'N', 'R': '5',
    };
    
    // Process remaining characters
    String lastCode = '0';
    for (int i = 1; i < text.length; i++) {
      final char = text[i].toUpperCase();
      final charCode = soundexMap[char] ?? '0';
      
      if (charCode != lastCode) {
        code += charCode;
        lastCode = charCode;
      }
    }
    
    // Pad to 4 characters
    while (code.length < 4) {
      code += '0';
    }
    
    return code.substring(0, 4);
  }
  
  /// Metaphone code
  String _metaphoneCode(String text) {
    if (text.isEmpty) return '';
    
    // Simplified Metaphone algorithm
    String code = '';
    String previousCode = '';
    
    for (int i = 0; i < text.length; i++) {
      final char = text[i].toUpperCase();
      String currentCode = '';
      
      // Metaphone encoding rules
      if (char.contains(RegExp(r'[AEIOUHWY]'))) {
        currentCode = '0';
      } else if (char.contains(RegExp(r'[BFPV]'))) {
        currentCode = '1';
      } else if (char.contains(RegExp(r'[CGJKQSXZ]'))) {
        currentCode = '2';
      } else if (char.contains(RegExp(r'[DT]'))) {
        currentCode = '3';
      } else if (char.contains(RegExp(r'[L]'))) {
        currentCode = '4';
      } else if (char.contains(RegExp(r'[MN]'))) {
        currentCode = '5';
      } else if (char.contains(RegExp(r'[R]'))) {
        currentCode = '6';
      }
      
      // Apply Metaphone rules
      if (currentCode != previousCode) {
        code += currentCode;
        previousCode = currentCode;
      }
    }
    
    return code;
  }
  
  /// Get suggestions based on learning
  List<String> getSmartSuggestions(String partial, {int maxSuggestions = 5}) {
    final suggestions = <String>[];
    
    // Get patterns that start with partial
    final matchingPatterns = _patternFrequencies.keys
        .where((pattern) => pattern.startsWith(partial))
        .toList();
    
    // Sort by frequency and recency
    matchingPatterns.sort((a, b) {
      final freqA = _patternFrequencies[a] ?? 0;
      final freqB = _patternFrequencies[b] ?? 0;
      
      if (freqA != freqB) {
        return freqB.compareTo(freqA);
      }
      
      final lastA = _lastUsedPatterns[a];
      final lastB = _lastUsedPatterns[b];
      
      if (lastA == null && lastB != null) {
        return -1; // A is more recent
      } else if (lastA != null && lastB == null) {
        return 1; // B is more recent
      } else if (lastA != null && lastB != null) {
        return lastB!.compareTo(lastA!);
      }
      
      return 0;
    });
    
    return matchingPatterns.take(maxSuggestions).toList();
  }
  
  /// Save learning data
  Future<void> saveLearningData() async {
    try {
      final learningFile = File('${Directory.systemTemp.path}/fuzzy_learning.json');
      final data = {
        'patternWeights': _patternWeights,
        'patternFrequencies': _patternFrequencies,
        'lastUsedPatterns': _lastUsedPatterns.map((k, v) => MapEntry(k, v.toIso8601String())),
        'lastSaved': DateTime.now().toIso8601String(),
      };
      
      await learningFile.writeAsString(jsonEncode(data));
      debugPrint('💾 Fuzzy search learning data saved');
    } catch (e) {
      debugPrint('⚠️ Failed to save learning data: $e');
    }
  }
  
  /// Clear cache
  void clearCache() {
    _matchCache.clear();
    _scoreCache.clear();
    _patternCache.clear();
    debugPrint('🗑️ Fuzzy search cache cleared');
  }
  
  /// Set algorithm
  void setAlgorithm(RankingAlgorithm algorithm) {
    _currentAlgorithm = algorithm;
    debugPrint('🔍 Fuzzy search algorithm changed to: $algorithm');
  }
  
  /// Get algorithm by name
  RankingAlgorithm? getAlgorithm(String name) {
    return _algorithms[name];
  }
  
  /// Update configuration
  void updateConfig(FuzzySearchConfig config) {
    _config = config;
    debugPrint('⚙️ Fuzzy search configuration updated');
  }
  
  /// Get search statistics
  FuzzySearchStatistics getStatistics() {
    return FuzzySearchStatistics(
      totalSearches: _patternFrequencies.values.fold(0, (a, b) => a + b),
      uniquePatterns: _patternFrequencies.length,
      cacheSize: _matchCache.length,
      currentAlgorithm: _currentAlgorithm,
      topPatterns: _patternFrequencies.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value))
          .take(10)
          .map((e) => e.key)
          .toList(),
    );
  }
  
  /// Dispose resources
  void dispose() {
    clearCache();
    _algorithms.clear();
    _patternWeights.clear();
    _patternFrequencies.clear();
    _lastUsedPatterns.clear();
    _isInitialized = false;
    debugPrint('🔍 Fuzzy Search Engine disposed');
  }
}

/// Ranking algorithm enumeration
enum RankingAlgorithm {
  levenshtein,
  jaro_winkler,
  damerau_levenshtein,
  qgram,
  soundex,
  metaphone,
  ngram,
  weighted,
}

/// Fuzzy match data structure
class FuzzyMatch {
  final String candidate;
  final double score;
  final RankingAlgorithm algorithm;
  final int index;
  final Map<String, dynamic> details;
  
  FuzzyMatch({
    required this.candidate,
    required this.score,
    required this.algorithm,
    required this.index,
    required this.details,
  });
  
  Map<String, dynamic> toJson() => {
    'candidate': candidate,
    'score': score,
    'algorithm': algorithm.toString(),
    'index': index,
    'details': details,
  };
  
  factory FuzzyMatch.fromJson(Map<String, dynamic> json) => FuzzyMatch(
    candidate: json['candidate'] as String,
    score: (json['score'] as num).toDouble(),
    algorithm: RankingAlgorithm.values.firstWhere(
      (a) => a.toString() == json['algorithm'],
      orElse: () => RankingAlgorithm.levenshtein,
    ),
    index: json['index'] as int,
    details: json['details'] as Map<String, dynamic>,
  );
}

/// Fuzzy search options
class FuzzySearchOptions {
  final bool ignoreCase;
  final bool ignoreWhitespace;
  final bool normalizeUnicode;
  final bool removeDiacritics;
  final bool useContext;
  final int minMatchLength;
  final double minScore;
  final int maxResults;
  
  FuzzySearchOptions({
    this.ignoreCase = true,
    this.ignoreWhitespace = false,
    this.normalizeUnicode = true,
    this.removeDiacritics = false,
    this.useContext = true,
    this.minMatchLength = 2,
    this.minScore = 0.3,
    this.maxResults = 10,
  });
  
  Map<String, dynamic> toJson() => {
    'ignoreCase': ignoreCase,
    'ignoreWhitespace': ignoreWhitespace,
    'normalizeUnicode': normalizeUnicode,
    'removeDiacritics': removeDiacritics,
    'useContext': useContext,
    'minMatchLength': minMatchLength,
    'minScore': minScore,
    'maxResults': maxResults,
  };
  
  factory FuzzySearchOptions.fromJson(Map<String, dynamic> json) => FuzzySearchOptions(
    ignoreCase: json['ignoreCase'] as bool? ?? true,
    ignoreWhitespace: json['ignoreWhitespace'] as bool? ?? false,
    normalizeUnicode: json['normalizeUnicode'] as bool? ?? true,
    removeDiacritics: json['removeDiacritics'] as bool? ?? false,
    useContext: json['useContext'] as bool? ?? true,
    minMatchLength: json['minMatchLength'] as int? ?? 2,
    minScore: (json['minScore'] as num?)?.toDouble() ?? 0.3,
    maxResults: json['maxResults'] as int? ?? 10,
  );
  
  @override
  String toString() {
    return 'FuzzySearchOptions('
        'ignoreCase: $ignoreCase, '
        'ignoreWhitespace: $ignoreWhitespace, '
        'normalizeUnicode: $normalizeUnicode, '
        'removeDiacritics: $removeDiacritics, '
        'useContext: $useContext, '
        'minMatchLength: $minMatchLength, '
        'minScore: $minScore, '
        'maxResults: $maxResults'
        ')';
  }
}

/// Fuzzy search configuration
class FuzzySearchConfig {
  final bool contextScoring;
  final bool learningEnabled;
  final bool cacheEnabled;
  final int maxCacheSize;
  final Duration cacheTimeout;
  final FuzzySearchOptions defaultOptions;
  
  FuzzySearchConfig({
    this.contextScoring = true,
    this.learningEnabled = true,
    this.cacheEnabled = true,
    this.maxCacheSize = 1000,
    this.cacheTimeout = const Duration(minutes: 30),
    this.defaultOptions = const FuzzySearchOptions(),
  });
}

/// Algorithm interface
abstract class RankingAlgorithm {
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options);
}

/// Levenshtein algorithm
class LevenshteinAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    final distance = _levenshteinDistance(s1, s2);
    final maxLen = max(s1.length, s2.length);
    
    if (maxLen == 0) return 1.0;
    
    return 1.0 - (distance / maxLen);
  }
  
  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(s1.length + 1, (_) => List.filled(s2.length + 1, 0));
    
    for (int i = 0; i <= s1.length; i++) {
      for (int j = 0; j <= s2.length; j++) {
        if (i == 0 && j == 0) {
          matrix[i][j] = 0;
        } else if (i == 0) {
          matrix[i][j] = matrix[i][j - 1] + 1;
        } else if (j == 0) {
          matrix[i][j] = matrix[i - 1][j] + 1;
        } else {
          final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
          matrix[i][j] = min(
            matrix[i - 1][j] + 1,
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost,
          );
        }
      }
    }
    
    return matrix[s1.length][s2.length];
  }
}

/// Jaro-Winkler algorithm
class JaroWinklerAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    return _jaroWinklerScore(s1, s2);
  }
  
  double _jaroWinklerScore(String s1, String s2) {
    if (s1 == s2) return 1.0;
    
    final len1 = s1.length;
    final len2 = s2.length;
    final maxLen = max(len1, len2);
    final matchDistance = (maxLen / 2).floor();
    
    int matches = 0;
    int transpositions = 0;
    
    for (int i = 0; i < matchDistance; i++) {
      if (i < len1 && i < len2 && s1[i] == s2[i]) {
        matches++;
      }
    }
    
    if (matches == 0) return 0.0;
    
    final jaroDistance = (
      (matches / len1) +
      (matches / len2) +
      ((matches - transpositions / 2) / maxLen)
    ) / 3.0;
    
    int prefix = 0;
    for (int i = 0; i < min(4, min(len1, len2)); i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      }
    }
    
    final winklerBonus = prefix / 10.0;
    
    return jaroDistance + winklerBonus;
  }
  
  double _winklerScore(String s1, String s2) {
    return _jaroWinklerScore(s1, s2);
  }
}

/// Damerau-Levenshtein algorithm
class DamerauLevenshteinAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    // Simplified Damerau-Levenshtein implementation
    final distance = _levenshteinDistance(s1, s2);
    final maxLen = max(s1.length, s2.length);
    
    if (maxLen == 0) return 1.0;
    
    return 1.0 - (distance / maxLen);
  }
}

/// Q-gram algorithm
class QGramAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    return _qgramSimilarity(s1, s2, 2);
  }
  
  double _qgramSimilarity(String s1, String s2, int q) {
    final qgrams1 = _getQGrams(s1, q);
    final qgrams2 = _getQGrams(s2, q);
    
    final intersection = qgrams1.intersection(qgrams2.toSet()).length;
    final union = qgrams1.toSet().union(qgrams2.toSet()).length;
    
    return union == 0 ? 0.0 : (2.0 * intersection) / union;
  }
  
  Set<String> _getQGrams(String text, int q) {
    final qgrams = <String>{};
    
    for (int i = 0; i <= text.length - q; i++) {
      qgrams.add(text.substring(i, i + q));
    }
    
    return qgrams;
  }
}

/// Soundex algorithm
class SoundexAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    final code1 = _soundexCode(s1);
    final code2 = _soundexCode(s2);
    
    return code1 == code2 ? 1.0 : 0.0;
  }
  
  String _soundexCode(String text) {
    if (text.isEmpty) return '0000';
    
    final first = text[0].toUpperCase();
    String code = first;
    
    final Map<String, String> soundexMap = {
      'B': '1', 'F': '1', 'P': '1', 'V': '1',
      'C': '2', 'G': '2', 'J': '2', 'K': '2', 'Q': '2', 'S': '2', 'X': '2', 'Z': '2',
      'D': '3', 'T': '3',
      'L': '4', 'M': 'N', 'R': '5',
    };
    
    String lastCode = '0';
    for (int i = 1; i < text.length; i++) {
      final char = text[i].toUpperCase();
      final charCode = soundexMap[char] ?? '0';
      
      if (charCode != lastCode) {
        code += charCode;
        lastCode = charCode;
      }
    }
    
    while (code.length < 4) {
      code += '0';
    }
    
    return code.substring(0, 4);
  }
}

/// Metaphone algorithm
class MetaphoneAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    final code1 = _metaphoneCode(s1);
    final code2 = _metaphoneCode(s2);
    
    return code1 == code2 ? 1.0 : 0.0;
  }
  
  String _metaphoneCode(String text) {
    if (text.isEmpty) return '';
    
    String code = '';
    String previousCode = '';
    
    for (int i = 0; i < text.length; i++) {
      final char = text[i].toUpperCase();
      String currentCode = '';
      
      if (char.contains(RegExp(r'[AEIOUHWY]'))) {
        currentCode = '0';
      } else if (char.contains(RegExp(r'[BFPV]'))) {
        currentCode = '1';
      } else if (char.contains(RegExp(r'[CGJKQSXZ]'))) {
        currentCode = '2';
      } else if (char.contains(RegExp(r'[DT]'))) {
        currentCode = '3';
      } else if (char.contains(RegExp(r'[L]'))) {
        currentCode = '4';
      } else if (char.contains(RegExp(r'[MN]'))) {
        currentCode = '5';
      } else if (char.contains(RegExp(r'[R]'))) {
        currentCode = '6';
      }
      
      if (currentCode != previousCode) {
        code += currentCode;
        previousCode = currentCode;
      }
    }
    
    return code;
  }
}

/// N-gram algorithm
class NGramAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    final n = 2; // Bigrams
    final ngrams1 = _getNGrams(s1, n);
    final ngrams2 = _getNGrams(s2, n);
    
    final intersection = ngrams1.intersection(ngrams2.toSet()).length;
    final union = ngrams1.toSet().union(ngrams2.toSet()).length;
    
    return union == 0 ? 0.0 : (2.0 * intersection) / union;
  }
  
  Set<String> _getNGrams(String text, int n) {
    final ngrams = <String>{};
    
    for (int i = 0; i <= text.length - n; i++) {
      ngrams.add(text.substring(i, i + n));
    }
    
    return ngrams;
  }
}

/// Weighted algorithm
class WeightedAlgorithm implements RankingAlgorithm {
  @override
  double calculateSimilarity(String s1, String s2, FuzzySearchOptions options) {
    // Combine multiple algorithms with weights
    final levenshtein = LevenshteinAlgorithm().calculateSimilarity(s1, s2, options);
    final jaroWinkler = JaroWinklerAlgorithm().calculateSimilarity(s1, s2, options);
    final qgram = QGramAlgorithm().calculateSimilarity(s1, s2, options);
    
    // Weighted combination
    return (levenshtein * 0.4 + jaroWinkler * 0.3 + qgram * 0.3);
  }
}

/// Fuzzy search statistics
class FuzzySearchStatistics {
  final int totalSearches;
  final int uniquePatterns;
  final int cacheSize;
  final RankingAlgorithm currentAlgorithm;
  final List<String> topPatterns;
  
  FuzzySearchStatistics({
    required this.totalSearches,
    required this.uniquePatterns,
    required this.cacheSize,
    required this.currentAlgorithm,
    required this.topPatterns,
  });
}
