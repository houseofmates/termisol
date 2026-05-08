import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Documentation Integration - Inline docs and API references
class DocumentationIntegration {
  static final DocumentationIntegration _instance = DocumentationIntegration._internal();
  factory DocumentationIntegration() => _instance;
  DocumentationIntegration._internal();

  final Map<String, DocumentationCache> _docCache = {};
  final Map<String, APIReference> _apiReferences = {};
  final Map<String, List<CodeExample>> _codeExamples = {};
  final Map<String, DocumentationIndex> _indices = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  
  static const Duration _cleanupInterval = Duration(minutes: 10);
  static const Duration _cacheTimeout = Duration(hours: 1);
  static const int _maxCacheSize = 1000;
  
  final _docController = StreamController<DocumentationEvent>.broadcast();
  Stream<DocumentationEvent> get events => _docController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadDocumentationIndices();
    _startCleanupTimer();
    _isInitialized = true;
    debugPrint('📚 Documentation Integration initialized');
  }

  Future<DocumentationResult> getDocumentation({
    required String query,
    String? language,
    String? framework,
    DocumentationType type = DocumentationType.general,
  }) async {
    final cacheKey = _generateCacheKey(query, language, framework, type);
    
    // Check cache first
    if (_docCache.containsKey(cacheKey)) {
      final cached = _docCache[cacheKey]!;
      if (!cached.isExpired) {
        return DocumentationResult(
          success: true,
          documentation: cached.documentation,
          fromCache: true,
        );
      }
    }
    
    try {
      // Search local documentation first
      final localDocs = await _searchLocalDocumentation(query, language, framework, type);
      
      // If not found locally, search online
      DocumentationResult result;
      if (localDocs.isNotEmpty) {
        result = DocumentationResult(
          success: true,
          documentation: localDocs.first,
          fromCache: false,
        );
      } else {
        result = await _searchOnlineDocumentation(query, language, framework, type);
      }
      
      if (result.success && result.documentation != null) {
        // Cache the result
        _docCache[cacheKey] = DocumentationCache(
          key: cacheKey,
          documentation: result.documentation!,
          timestamp: DateTime.now(),
        );
        
        _docController.add(DocumentationEvent(
          type: DocumentationEventType.documentationRetrieved,
          data: {
            'query': query,
            'language': language,
            'type': type.toString(),
            'from_cache': false,
          },
        ));
      }
      
      return result;
      
    } catch (e) {
      debugPrint('❌ Failed to get documentation: $e');
      return DocumentationResult.error(e.toString());
    }
  }

  Future<APIReferenceResult> getAPIReference({
    required String symbol,
    String? language,
    String? library,
  }) async {
    final cacheKey = _generateAPIKey(symbol, language, library);
    
    // Check cache first
    if (_apiReferences.containsKey(cacheKey)) {
      final cached = _apiReferences[cacheKey]!;
      return APIReferenceResult(
        success: true,
        reference: cached,
        fromCache: true,
      );
    }
    
    try {
      final reference = await _fetchAPIReference(symbol, language, library);
      
      if (reference != null) {
        _apiReferences[cacheKey] = reference;
        
        _docController.add(DocumentationEvent(
          type: DocumentationEventType.apiReferenceRetrieved,
          data: {
            'symbol': symbol,
            'language': language,
            'library': library,
          },
        ));
        
        return APIReferenceResult(
          success: true,
          reference: reference,
          fromCache: false,
        );
      }
      
      return APIReferenceResult.error('API reference not found');
      
    } catch (e) {
      debugPrint('❌ Failed to get API reference: $e');
      return APIReferenceResult.error(e.toString());
    }
  }

  Future<CodeExampleResult> getCodeExamples({
    required String topic,
    String? language,
    String? framework,
    int maxExamples = 5,
  }) async {
    final cacheKey = _generateExampleKey(topic, language, framework);
    
    // Check cache first
    if (_codeExamples.containsKey(cacheKey)) {
      final cached = _codeExamples[cacheKey]!;
      return CodeExampleResult(
        success: true,
        examples: cached.take(maxExamples).toList(),
        fromCache: true,
      );
    }
    
    try {
      final examples = await _fetchCodeExamples(topic, language, framework);
      
      if (examples.isNotEmpty) {
        _codeExamples[cacheKey] = examples;
        
        _docController.add(DocumentationEvent(
          type: DocumentationEventType.codeExamplesRetrieved,
          data: {
            'topic': topic,
            'language': language,
            'examples_count': examples.length,
          },
        ));
        
        return CodeExampleResult(
          success: true,
          examples: examples.take(maxExamples).toList(),
          fromCache: false,
        );
      }
      
      return CodeExampleResult.error('No code examples found');
      
    } catch (e) {
      debugPrint('❌ Failed to get code examples: $e');
      return CodeExampleResult.error(e.toString());
    }
  }

  Future<List<String>> getQuickReference({
    required String language,
    QuickReferenceType type = QuickReferenceType.syntax,
  }) async {
    try {
      final reference = await _fetchQuickReference(language, type);
      return reference;
    } catch (e) {
      debugPrint('❌ Failed to get quick reference: $e');
      return [];
    }
  }

  Future<List<String>> getCompletions({
    required String partial,
    String? language,
    String? context,
  }) async {
    try {
      final completions = await _fetchCompletions(partial, language, context);
      return completions;
    } catch (e) {
      debugPrint('❌ Failed to get completions: $e');
      return [];
    }
  }

  Future<List<DocumentationItem>> searchDocumentation({
    required String query,
    String? language,
    int maxResults = 10,
  }) async {
    try {
      final results = <DocumentationItem>[];
      
      // Search in indices
      for (final index in _indices.values) {
        if (language == null || index.language == language) {
          final matches = index.search(query);
          results.addAll(matches);
        }
      }
      
      // Sort by relevance
      results.sort((a, b) => b.relevance.compareTo(a.relevance));
      
      return results.take(maxResults).toList();
      
    } catch (e) {
      debugPrint('❌ Failed to search documentation: $e');
      return [];
    }
  }

  Future<List<DocumentationItem>> _searchLocalDocumentation(
    String query,
    String? language,
    String? framework,
    DocumentationType type,
  ) async {
    final results = <DocumentationItem>[];
    
    // Search in local documentation files
    final docPaths = _getLocalDocumentationPaths(language, framework, type);
    
    for (final docPath in docPaths) {
      try {
        final file = File(docPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final relevance = _calculateRelevance(query, content);
          
          if (relevance > 0.3) {
            results.add(DocumentationItem(
              title: path.basenameWithoutExtension(docPath),
              content: content,
              path: docPath,
              relevance: relevance,
              type: type,
              language: language ?? 'unknown',
            ));
          }
        }
      } catch (e) {
        debugPrint('❌ Failed to read documentation file $docPath: $e');
      }
    }
    
    return results;
  }

  Future<DocumentationResult> _searchOnlineDocumentation(
    String query,
    String? language,
    String? framework,
    DocumentationType type,
  ) async {
    try {
      // Use online documentation APIs
      final documentation = await _fetchFromOnlineAPI(query, language, framework, type);
      
      if (documentation != null) {
        return DocumentationResult(
          success: true,
          documentation: documentation,
          fromCache: false,
        );
      }
      
      return DocumentationResult.error('No online documentation found');
      
    } catch (e) {
      debugPrint('❌ Failed to search online documentation: $e');
      return DocumentationResult.error(e.toString());
    }
  }

  Future<APIReference?> _fetchAPIReference(String symbol, String? language, String? library) async {
    // Simulate API reference fetching
    await Future.delayed(Duration(milliseconds: 100));
    
    // Create mock API reference
    return APIReference(
      symbol: symbol,
      signature: '$symbol(${_generateMockParameters()})',
      description: 'This is a mock description for $symbol',
      parameters: _generateMockParameterList(),
      returnType: _generateMockReturnType(language),
      examples: _generateMockExamples(symbol),
      language: language ?? 'javascript',
      library: library ?? 'standard',
    );
  }

  Future<List<CodeExample>> _fetchCodeExamples(String topic, String? language, String? framework) async {
    // Simulate code example fetching
    await Future.delayed(Duration(milliseconds: 150));
    
    return [
      CodeExample(
        title: 'Basic $topic example',
        code: _generateMockExampleCode(topic, language),
        language: language ?? 'javascript',
        description: 'A basic example of $topic',
      ),
      CodeExample(
        title: 'Advanced $topic example',
        code: _generateMockExampleCode(topic, language, advanced: true),
        language: language ?? 'javascript',
        description: 'An advanced example of $topic',
      ),
    ];
  }

  Future<List<String>> _fetchQuickReference(String language, QuickReferenceType type) async {
    // Simulate quick reference fetching
    await Future.delayed(Duration(milliseconds: 50));
    
    switch (type) {
      case QuickReferenceType.syntax:
        return _getSyntaxReference(language);
      case QuickReferenceType.commands:
        return _getCommandReference(language);
      case QuickReferenceType.shortcuts:
        return _getShortcutReference(language);
    }
  }

  Future<List<String>> _fetchCompletions(String partial, String? language, String? context) async {
    // Simulate completion fetching
    await Future.delayed(Duration(milliseconds: 30));
    
    return _generateMockCompletions(partial, language, context);
  }

  Future<DocumentationItem?> _fetchFromOnlineAPI(
    String query,
    String? language,
    String? framework,
    DocumentationType type,
  ) async {
    // Simulate online API call
    await Future.delayed(Duration(milliseconds: 200));
    
    // Create mock documentation item
    return DocumentationItem(
      title: 'Documentation for $query',
      content: 'This is mock documentation content for $query in ${language ?? 'unknown'}',
      path: 'online://docs/$query',
      relevance: 0.8,
      type: type,
      language: language ?? 'unknown',
    );
  }

  List<String> _getLocalDocumentationPaths(String? language, String? framework, DocumentationType type) {
    final paths = <String>[];
    
    // Add common documentation paths
    final homeDir = Platform.environment['HOME'] ?? '';
    final docDirs = [
      path.join(homeDir, '.local', 'share', 'doc'),
      path.join(homeDir, 'Documents', 'documentation'),
      '/usr/share/doc',
      '/usr/local/share/doc',
    ];
    
    for (final docDir in docDirs) {
      if (Directory(docDir).existsSync()) {
        paths.add(docDir);
      }
    }
    
    return paths;
  }

  double _calculateRelevance(String query, String content) {
    final queryWords = query.toLowerCase().split(' ');
    final contentWords = content.toLowerCase().split(' ');
    
    int matches = 0;
    for (final queryWord in queryWords) {
      for (final contentWord in contentWords) {
        if (contentWord.contains(queryWord)) {
          matches++;
          break;
        }
      }
    }
    
    return queryWords.isNotEmpty ? matches / queryWords.length : 0.0;
  }

  String _generateMockParameters() {
    final params = ['param1', 'param2', 'options'];
    return params.join(', ');
  }

  List<APIParameter> _generateMockParameterList() {
    return [
      APIParameter(
        name: 'param1',
        type: 'string',
        description: 'First parameter',
        optional: false,
      ),
      APIParameter(
        name: 'param2',
        type: 'number',
        description: 'Second parameter',
        optional: true,
      ),
      APIParameter(
        name: 'options',
        type: 'object',
        description: 'Configuration options',
        optional: true,
      ),
    ];
  }

  String _generateMockReturnType(String? language) {
    switch (language) {
      case 'javascript':
      case 'typescript':
        return 'any';
      case 'python':
        return 'Any';
      case 'java':
        return 'Object';
      case 'rust':
        return 'Result<T, Error>';
      default:
        return 'void';
    }
  }

  List<String> _generateMockExamples(String symbol) {
    return [
      'const result = $symbol("test");',
      '$symbol({ option: true });',
      'await $symbol();',
    ];
  }

  String _generateMockExampleCode(String topic, String? language, {bool advanced = false}) {
    final complexity = advanced ? 'advanced' : 'basic';
    
    switch (language) {
      case 'javascript':
      case 'typescript':
        return '''
// $complexity $topic example
function ${topic.toLowerCase()}Example() {
  const data = "sample data";
  return data.${topic.toLowerCase()}();
}

${topic.toLowerCase()}Example();
''';
      case 'python':
        return '''
# $complexity $topic example
def ${topic.toLowerCase()}_example():
    data = "sample data"
    return data.${topic.lower()}()

${topic.lower()}_example()
''';
      default:
        return '''
// $complexity $topic example
function example() {
  // Implementation for $topic
  return "result";
}
''';
    }
  }

  List<String> _getSyntaxReference(String language) {
    switch (language) {
      case 'javascript':
        return [
          'let variable = value;',
          'const constant = value;',
          'function name() {}',
          'array.map(item => item)',
          'object.property',
        ];
      case 'python':
        return [
          'variable = value',
          'def function():',
          'list comprehension: [x for x in items]',
          'dictionary access: dict[key]',
          'import module',
        ];
      default:
        return ['// Syntax reference not available'];
    }
  }

  List<String> _getCommandReference(String language) {
    switch (language) {
      case 'javascript':
        return ['npm install', 'npm run dev', 'npm test', 'npm build'];
      case 'python':
        return ['pip install', 'python -m pytest', 'python main.py', 'pip freeze'];
      case 'rust':
        return ['cargo build', 'cargo run', 'cargo test', 'cargo check'];
      default:
        return ['// Commands not available'];
    }
  }

  List<String> _getShortcutReference(String language) {
    switch (language) {
      case 'javascript':
        return ['Ctrl+S: Save', 'Ctrl+/: Toggle comment', 'F12: Go to definition'];
      case 'python':
        return ['Ctrl+S: Save', 'Ctrl+/: Toggle comment', 'F5: Run'];
      default:
        return ['// Shortcuts not available'];
    }
  }

  List<String> _generateMockCompletions(String partial, String? language, String? context) {
    final completions = <String>[];
    
    // Generate mock completions based on partial
    if (partial.startsWith('con')) {
      completions.addAll(['console', 'const', 'constructor']);
    } else if (partial.startsWith('fun')) {
      completions.addAll(['function', 'functional', 'functor']);
    }
    
    return completions;
  }

  Future<void> _loadDocumentationIndices() async {
    // Load or create documentation indices
    final languages = ['javascript', 'python', 'rust', 'go', 'dart'];
    
    for (final language in languages) {
      _indices[language] = DocumentationIndex(
        language: language,
        items: _generateMockIndexItems(language),
        lastUpdated: DateTime.now(),
      );
    }
  }

  List<IndexItem> _generateMockIndexItems(String language) {
    return [
      IndexItem(
        keyword: 'function',
        title: 'Function definition',
        path: '/docs/$language/functions',
        relevance: 1.0,
      ),
      IndexItem(
        keyword: 'class',
        title: 'Class definition',
        path: '/docs/$language/classes',
        relevance: 1.0,
      ),
      IndexItem(
        keyword: 'import',
        title: 'Import statement',
        path: '/docs/$language/modules',
        relevance: 0.9,
      ),
    ];
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupCache();
    });
  }

  void _cleanupCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _docCache.entries) {
      if (now.difference(entry.value.timestamp) > _cacheTimeout) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _docCache.remove(key);
    }
    
    // Limit cache size
    if (_docCache.length > _maxCacheSize) {
      final entries = _docCache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      
      final toRemove = entries.take(_docCache.length - _maxCacheSize);
      for (final entry in toRemove) {
        _docCache.remove(entry.key);
      }
    }
    
    if (expiredKeys.isNotEmpty) {
      debugPrint('📚 Cleaned ${expiredKeys.length} expired documentation cache entries');
    }
  }

  String _generateCacheKey(String query, String? language, String? framework, DocumentationType type) {
    return '${query}_${language ?? 'unknown'}_${framework ?? 'none'}_${type.toString()}';
  }

  String _generateAPIKey(String symbol, String? language, String? library) {
    return '${symbol}_${language ?? 'unknown'}_${library ?? 'standard'}';
  }

  String _generateExampleKey(String topic, String? language, String? framework) {
    return '${topic}_${language ?? 'unknown'}_${framework ?? 'none'}';
  }

  Map<String, dynamic> getStatistics() {
    return {
      'cached_documents': _docCache.length,
      'api_references': _apiReferences.length,
      'code_examples': _codeExamples.length,
      'indices': _indices.length,
    };
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _docController.close();
    _docCache.clear();
    _apiReferences.clear();
    _codeExamples.clear();
    _indices.clear();
  }
}

class DocumentationCache {
  final String key;
  final DocumentationItem documentation;
  final DateTime timestamp;
  
  DocumentationCache({
    required this.key,
    required this.documentation,
    required this.timestamp,
  });
  
  bool get isExpired => DateTime.now().difference(timestamp) > Duration(hours: 1);
}

class DocumentationItem {
  final String title;
  final String content;
  final String path;
  final double relevance;
  final DocumentationType type;
  final String language;
  
  DocumentationItem({
    required this.title,
    required this.content,
    required this.path,
    required this.relevance,
    required this.type,
    required this.language,
  });
}

class APIReference {
  final String symbol;
  final String signature;
  final String description;
  final List<APIParameter> parameters;
  final String returnType;
  final List<String> examples;
  final String language;
  final String library;
  
  APIReference({
    required this.symbol,
    required this.signature,
    required this.description,
    required this.parameters,
    required this.returnType,
    required this.examples,
    required this.language,
    required this.library,
  });
}

class APIParameter {
  final String name;
  final String type;
  final String description;
  final bool optional;
  
  APIParameter({
    required this.name,
    required this.type,
    required this.description,
    required this.optional,
  });
}

class CodeExample {
  final String title;
  final String code;
  final String language;
  final String description;
  
  CodeExample({
    required this.title,
    required this.code,
    required this.language,
    required this.description,
  });
}

class DocumentationIndex {
  final String language;
  final List<IndexItem> items;
  final DateTime lastUpdated;
  
  DocumentationIndex({
    required this.language,
    required this.items,
    required this.lastUpdated,
  });
  
  List<DocumentationItem> search(String query) {
    final results = <DocumentationItem>[];
    
    for (final item in items) {
      if (item.keyword.contains(query.toLowerCase())) {
        results.add(DocumentationItem(
          title: item.title,
          content: 'Content for ${item.title}',
          path: item.path,
          relevance: item.relevance,
          type: DocumentationType.general,
          language: language,
        ));
      }
    }
    
    return results;
  }
}

class IndexItem {
  final String keyword;
  final String title;
  final String path;
  final double relevance;
  
  IndexItem({
    required this.keyword,
    required this.title,
    required this.path,
    required this.relevance,
  });
}

class DocumentationResult {
  final bool success;
  final DocumentationItem? documentation;
  final bool fromCache;
  final String? error;
  
  DocumentationResult({
    required this.success,
    this.documentation,
    required this.fromCache,
    this.error,
  });
  
  factory DocumentationResult.success(DocumentationItem documentation, bool fromCache) {
    return DocumentationResult(
      success: true,
      documentation: documentation,
      fromCache: fromCache,
    );
  }
  
  factory DocumentationResult.error(String error) {
    return DocumentationResult(
      success: false,
      fromCache: false,
      error: error,
    );
  }
}

class APIReferenceResult {
  final bool success;
  final APIReference? reference;
  final bool fromCache;
  final String? error;
  
  APIReferenceResult({
    required this.success,
    this.reference,
    required this.fromCache,
    this.error,
  });
  
  factory APIReferenceResult.success(APIReference reference, bool fromCache) {
    return APIReferenceResult(
      success: true,
      reference: reference,
      fromCache: fromCache,
    );
  }
  
  factory APIReferenceResult.error(String error) {
    return APIReferenceResult(
      success: false,
      fromCache: false,
      error: error,
    );
  }
}

class CodeExampleResult {
  final bool success;
  final List<CodeExample> examples;
  final bool fromCache;
  final String? error;
  
  CodeExampleResult({
    required this.success,
    required this.examples,
    required this.fromCache,
    this.error,
  });
  
  factory CodeExampleResult.success(List<CodeExample> examples, bool fromCache) {
    return CodeExampleResult(
      success: true,
      examples: examples,
      fromCache: fromCache,
    );
  }
  
  factory CodeExampleResult.error(String error) {
    return CodeExampleResult(
      success: false,
      examples: [],
      fromCache: false,
      error: error,
    );
  }
}

class DocumentationEvent {
  final DocumentationEventType type;
  final Map<String, dynamic>? data;
  
  DocumentationEvent({
    required this.type,
    this.data,
  });
}

enum DocumentationType {
  general,
  api,
  tutorial,
  reference,
  example,
}

enum QuickReferenceType {
  syntax,
  commands,
  shortcuts,
}

enum DocumentationEventType {
  documentationRetrieved,
  apiReferenceRetrieved,
  codeExamplesRetrieved,
}
