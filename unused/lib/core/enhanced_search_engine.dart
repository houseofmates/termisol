import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Enhanced search engine with fuzzy matching, file content search,
/// and directory filtering.
class EnhancedSearchEngine {
  bool _initialized = false;

  Future<void> initialize() async {
    _initialized = true;
  }

  Future<List<SearchResultItem>> search(String query, {
    String? directory,
    List<String>? include,
    List<String>? exclude,
    bool caseSensitive = false,
    int maxResults = 100,
  }) async {
    if (!_initialized) await initialize();
    if (query.isEmpty) return [];

    final results = <SearchResultItem>[];
    final searchDir = directory ?? '.';
    final dir = Directory(searchDir);
    if (!await dir.exists()) return [];

    final includes = include?.map((e) => e.toLowerCase()).toSet() ?? <String>{};
    final excludes = exclude?.map((e) => e.toLowerCase()).toSet() ?? <String>{};

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (results.length >= maxResults) break;
      if (entity is! File) continue;

      final path = entity.path;
      final lowerPath = path.toLowerCase();

      // Apply extension filters
      if (includes.isNotEmpty) {
        final ext = '.${path.split('.').lastOrNull ?? ''}'.toLowerCase();
        if (!includes.contains(ext)) continue;
      }
      if (excludes.isNotEmpty) {
        final ext = '.${path.split('.').lastOrNull ?? ''}'.toLowerCase();
        if (excludes.contains(ext)) continue;
      }

      // Check filename match
      final fileName = path.split(Platform.pathSeparator).last;
      if (_fuzzyMatch(fileName, query, caseSensitive)) {
        results.add(SearchResultItem(path: path, lineNumber: 0));
        continue;
      }

      // Search file content for larger queries
      if (query.length >= 3) {
        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (_fuzzyMatch(lines[i], query, caseSensitive)) {
              results.add(SearchResultItem(
                path: path,
                lineNumber: i + 1,
                content: lines[i].trim(),
              ));
              break; // One match per file for performance
            }
          }
        } catch (_) {
          // Binary or unreadable file, skip
        }
      }
    }

    return results;
  }

  bool _fuzzyMatch(String text, String query, bool caseSensitive) {
    final t = caseSensitive ? text : text.toLowerCase();
    final q = caseSensitive ? query : query.toLowerCase();

    // Direct containment
    if (t.contains(q)) return true;

    // Fuzzy character matching
    var ti = 0;
    for (var qi = 0; qi < q.length; qi++) {
      final idx = t.indexOf(q[qi], ti);
      if (idx == -1) return false;
      ti = idx + 1;
    }
    return true;
  }
}

class SearchResultItem {
  final String path;
  final int lineNumber;
  final String? content;

  SearchResultItem({
    required this.path,
    this.lineNumber = 0,
    this.content,
  });
}
