import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';

/// semantic search engine
class SemanticSearchEngine {
  final Map<String, DocumentIndex> _indexes = {};
  final Map<String, InvertedIndex> _invertedIndexes = {};
  final Map<String, double> _idfCache = {};
  int _totalDocuments = 0;
  Timer? _cacheTimer;
  String? _indexPath;

  static const double _k1 = 1.2;
  static const double _b = 0.75;
  static const int _ngramMin = 2;
  static const int _ngramMax = 4;
  static const int _maxResults = 50;

  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _indexPath = '${appDir.path}/semantic_indexes';
      final dir = Directory(_indexPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _rebuildIdfCache(),
      );
      debugPrint('SemanticSearchEngine initialized');
    } on Exception catch (e, stack) {
      debugPrint('Failed to initialize SemanticSearchEngine: $e\n$stack');
      rethrow;
    }
  }

  void indexDocument(
    String collection,
    String docId,
    String content, {
    Map<String, dynamic>? metadata,
  }) {
    final index = _getOrCreateIndex(collection);
    final isUpdate = index.documents.containsKey(docId);
    if (isUpdate) {
      _removeFromInverted(collection, docId);
    }
    final tokens = _tokenize(content);
    final termFrequencies = <String, int>{};
    for (final token in tokens) {
      termFrequencies[token] = (termFrequencies[token] ?? 0) + 1;
    }
    final ngramSet = _generateNgrams(content, _ngramMin, _ngramMax);
    final doc = IndexedDocument(
      id: docId,
      content: content,
      tokens: tokens,
      termFrequencies: termFrequencies,
      ngrams: ngramSet,
      metadata: metadata ?? {},
      indexedAt: DateTime.now(),
    );
    index.documents[docId] = doc;
    if (!isUpdate) {
      index.totalTokens += tokens.length;
      _totalDocuments++;
    } else {
      index.totalTokens = index.documents.values.fold(
        0,
        (sum, d) => sum + d.tokens.length,
      );
    }
    _updateInvertedIndex(collection, docId, termFrequencies, ngramSet);
  }

  void removeDocument(String collection, String docId) {
    final index = _indexes[collection];
    final hadDoc = index?.documents.containsKey(docId) ?? false;
    _removeFromInverted(collection, docId);
    index?.documents.remove(docId);
    if (hadDoc) {
      _totalDocuments = max(0, _totalDocuments - 1);
      index?.totalTokens = index.documents.values.fold(
        0,
        (sum, d) => sum + d.tokens.length,
      );
    }
  }

  List<SearchResult> search(
    String collection,
    String query, {
    int? maxResults,
    double minScore = 0.01,
    List<String>? filters,
  }) {
    maxResults ??= _maxResults;
    final index = _indexes[collection];
    if (index == null || index.documents.isEmpty) return [];

    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) return [];

    final results = <SearchResult>[];
    final docIds = _getCandidateDocs(collection, queryTokens);
    final avgLength = index.documents.isNotEmpty
        ? index.totalTokens / index.documents.length
        : 1.0;

    for (final docId in docIds) {
      final doc = index.documents[docId];
      if (doc == null) continue;
      if (filters != null && filters.isNotEmpty) {
        if (!_matchesFilters(doc, filters)) continue;
      }
      final score =
          _scoreBM25(doc, queryTokens, avgLength, collection) +
          _scoreNgrams(doc, query) * 0.3;
      if (score >= minScore) {
        results.add(
          SearchResult(
            documentId: docId,
            score: score,
            content: doc.content,
            metadata: doc.metadata,
            snippets: _generateSnippets(doc.content, queryTokens),
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(maxResults).toList();
  }

  SearchResult? findSimilar(
    String collection,
    String docId, {
    int maxResults = 5,
    double minScore = 0.1,
  }) {
    final index = _indexes[collection];
    if (index == null) return null;
    final doc = index.documents[docId];
    if (doc == null) return null;
    return search(
      collection,
      doc.content,
      maxResults: maxResults,
      minScore: minScore,
    ).firstWhereOrNull((r) => r.documentId != docId);
  }

  List<String> suggest(
    String collection,
    String prefix, {
    int maxSuggestions = 10,
  }) {
    final index = _indexes[collection];
    if (index == null) return [];
    final results = <String>{};
    for (final doc in index.documents.values) {
      for (final token in doc.tokens) {
        if (token.startsWith(prefix.toLowerCase())) {
          results.add(token);
        }
      }
      if (results.length >= maxSuggestions) break;
    }
    return results.take(maxSuggestions).toList();
  }

  Future<void> clearIndex(String collection) async {
    final index = _indexes.remove(collection);
    _invertedIndexes.remove(collection);
    if (index != null) {
      _totalDocuments = max(0, _totalDocuments - index.documents.length);
    }
  }

  Future<void> persist() async {
    if (_indexPath == null) return;
    for (final entry in _indexes.entries) {
      if (entry.value.documents.isEmpty) continue;
      final file = File('$_indexPath/${entry.key}_index.json');
      try {
        final data = entry.value.documents.map(
          (k, v) => MapEntry(k, {
            'id': v.id,
            'content': v.content,
            'tokens': v.tokens,
            'termFrequencies': v.termFrequencies,
            'ngrams': v.ngrams.toList(),
            'metadata': v.metadata,
            'indexedAt': v.indexedAt.toIso8601String(),
          }),
        );
        await file.writeAsString(json.encode(data));
      } on Exception catch (e, stack) {
        debugPrint('Failed to persist index ${entry.key}: $e\n$stack');
      }
    }
  }

  DocumentIndex _getOrCreateIndex(String collection) {
    return _indexes.putIfAbsent(
      collection,
      () => DocumentIndex(name: collection),
    );
  }

  void _updateInvertedIndex(
    String collection,
    String docId,
    Map<String, int> termFrequencies,
    Set<String> ngrams,
  ) {
    final inverted = _invertedIndexes.putIfAbsent(
      collection,
      () => InvertedIndex(),
    );
    for (final term in termFrequencies.keys) {
      inverted.terms.putIfAbsent(term, () => {});
      inverted.terms[term]!.add(docId);
    }
    for (final ngram in ngrams) {
      inverted.ngrams.putIfAbsent(ngram, () => {});
      inverted.ngrams[ngram]!.add(docId);
    }
  }

  void _removeFromInverted(String collection, String docId) {
    final index = _indexes[collection];
    if (index == null) return;
    final inverted = _invertedIndexes[collection];
    if (inverted == null) return;
    final doc = index.documents[docId];
    if (doc == null) return;
    for (final term in doc.termFrequencies.keys) {
      inverted.terms[term]?.remove(docId);
    }
    for (final ngram in doc.ngrams) {
      inverted.ngrams[ngram]?.remove(docId);
    }
  }

  Set<String> _getCandidateDocs(String collection, List<String> queryTokens) {
    final inverted = _invertedIndexes[collection];
    if (inverted == null) return {};
    Set<String>? candidates;
    for (final token in queryTokens) {
      final docs = inverted.terms[token];
      if (docs != null && docs.isNotEmpty) {
        candidates = candidates == null ? {...docs} : candidates.union(docs);
      }
      for (int n = _ngramMin; n <= _ngramMax; n++) {
        if (token.length < n) continue;
        final ngramDocs = inverted.ngrams[token.substring(0, n)];
        if (ngramDocs != null && ngramDocs.isNotEmpty) {
          candidates = candidates == null
              ? {...ngramDocs}
              : candidates.union(ngramDocs);
        }
      }
    }
    return candidates ?? {};
  }

  double _scoreBM25(
    IndexedDocument doc,
    List<String> queryTokens,
    double avgLength,
    String collection,
  ) {
    double score = 0.0;
    final docLength = doc.tokens.length.toDouble();
    final index = _indexes[collection];
    final collectionDocCount = index?.documents.length ?? 0;
    for (final token in queryTokens) {
      final tf = doc.termFrequencies[token]?.toDouble() ?? 0.0;
      if (tf == 0) continue;
      final inverted = _invertedIndexes[collection];
      final df = inverted == null
          ? 1
          : (inverted.terms[token]?.length ?? 1).toDouble();
      final idf = log((collectionDocCount - df + 0.5) / (df + 0.5) + 1.0);
      final numerator = tf * (_k1 + 1);
      final denominator =
          tf + _k1 * (1 - _b + _b * (docLength / max(avgLength, 1)));
      score += idf * (numerator / denominator);
    }
    return score;
  }

  double _scoreNgrams(IndexedDocument doc, String query) {
    if (query.length < _ngramMin) return 0.0;
    final queryNgrams = <String>{};
    for (int n = _ngramMin; n <= min(_ngramMax, query.length); n++) {
      for (int i = 0; i <= query.length - n; i++) {
        queryNgrams.add(query.substring(i, i + n));
      }
    }
    final overlap = queryNgrams.intersection(doc.ngrams);
    return queryNgrams.isNotEmpty ? overlap.length / queryNgrams.length : 0.0;
  }

  bool _matchesFilters(IndexedDocument doc, List<String> filters) {
    for (final filter in filters) {
      final parts = filter.split(':');
      if (parts.length == 2) {
        final key = parts[0];
        final value = parts[1];
        if (doc.metadata[key]?.toString() != value) return false;
      }
    }
    return true;
  }

  List<Snippet> _generateSnippets(String content, List<String> queryTokens) {
    final snippets = <Snippet>[];
    final lowerContent = content.toLowerCase();
    for (final token in queryTokens) {
      int startPos = 0;
      while (startPos < lowerContent.length) {
        final pos = lowerContent.indexOf(token, startPos);
        if (pos == -1) break;
        final snippetStart = max(0, pos - 30);
        final snippetEnd = min(content.length, pos + token.length + 30);
        snippets.add(
          Snippet(
            text: content.substring(snippetStart, snippetEnd),
            position: snippetStart,
            length: snippetEnd - snippetStart,
          ),
        );
        startPos = pos + 1;
      }
    }
    snippets.sort((a, b) => a.position.compareTo(b.position));
    return snippets.take(5).toList();
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s_\-/\.]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Set<String> _generateNgrams(String text, int minN, int maxN) {
    final ngrams = <String>{};
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (int n = minN; n <= min(maxN, normalized.length); n++) {
      for (int i = 0; i <= normalized.length - n; i++) {
        ngrams.add(normalized.substring(i, i + n));
      }
    }
    return ngrams;
  }

  void _rebuildIdfCache() {
    _idfCache.clear();
    for (final inverted in _invertedIndexes.values) {
      for (final entry in inverted.terms.entries) {
        final df = entry.value.length.toDouble();
        _idfCache[entry.key] = log(
          (_totalDocuments - df + 0.5) / (df + 0.5) + 1.0,
        );
      }
    }
  }

  Future<void> dispose() async {
    _cacheTimer?.cancel();
    await persist();
    _indexes.clear();
    _invertedIndexes.clear();
    _idfCache.clear();
  }
}

class DocumentIndex {
  final String name;
  final Map<String, IndexedDocument> documents;
  int totalTokens;

  DocumentIndex({required this.name, Map<String, IndexedDocument>? documents})
    : documents = documents ?? {},
      totalTokens = 0;
}

class InvertedIndex {
  final Map<String, Set<String>> terms;
  final Map<String, Set<String>> ngrams;

  InvertedIndex() : terms = {}, ngrams = {};
}

class IndexedDocument {
  final String id;
  final String content;
  final List<String> tokens;
  final Map<String, int> termFrequencies;
  final Set<String> ngrams;
  final Map<String, dynamic> metadata;
  final DateTime indexedAt;

  IndexedDocument({
    required this.id,
    required this.content,
    required this.tokens,
    required this.termFrequencies,
    required this.ngrams,
    required this.metadata,
    required this.indexedAt,
  });
}

class SearchResult {
  final String documentId;
  final double score;
  final String content;
  final Map<String, dynamic> metadata;
  final List<Snippet> snippets;

  SearchResult({
    required this.documentId,
    required this.score,
    required this.content,
    required this.metadata,
    required this.snippets,
  });
}

class Snippet {
  final String text;
  final int position;
  final int length;

  Snippet({required this.text, required this.position, required this.length});
}
