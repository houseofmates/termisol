import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

class SmartTerminalBuffer {
  static const String _bufferConfigFile = '/home/house/.termisol_buffer_config.json';
  static const int _maxScrollbackLines = 100000;
  static const int _maxMemoryUsage = 512 * 1024 * 1024; // 512MB
  static const int _compressionThreshold = 1024; // Compress lines > 1KB
  static const Duration _cleanupInterval = Duration(minutes: 5);
  
  final Map<String, BufferPage> _pages = {};
  final Map<String, BufferIndex> _indexes = {};
  final Map<String, BufferStats> _stats = {};
  final Map<String, List<SearchMatch>>> _searchCache = {};
  
  Timer? _cleanupTimer;
  Timer? _compressionTimer;
  String? _activePage;
  int _totalLines = 0;
  int _totalPages = 0;
  int _currentMemoryUsage = 0;
  
  final StreamController<BufferEvent> _bufferController = 
      StreamController<BufferEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _initializePages();
    _startTimers();
    developer.log('📄 Smart Terminal Buffer initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_bufferConfigFile);
      if (!file.existsSync()) {
        developer.log('📄 No existing buffer configuration found, using defaults');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load pages
      for (final entry in data['pages']) {
        final page = BufferPage.fromJson(entry);
        _pages[page.id] = page;
        _totalPages++;
      }
      
      // Load indexes
      for (final entry in data['indexes']) {
        final index = BufferIndex.fromJson(entry);
        _indexes[index.pageId] = index;
      }
      
      // Load stats
      for (final entry in data['stats']) {
        final stats = BufferStats.fromJson(entry);
        _stats[stats.pageId] = stats;
      }
      
      developer.log('📄 Loaded ${_pages.length} buffer pages');
      
    } catch (e) {
      developer.log('📄 Failed to load buffer configuration: $e');
    }
  }

  void _initializePages() {
    if (_pages.isEmpty) {
      // Create default page
      _createDefaultPage();
    }
    
    // Set active page
    _activePage = _pages.keys.first;
  }

  void _createDefaultPage() {
    final pageId = _generatePageId();
    
    final page = BufferPage(
      id: pageId,
      name: 'Default Terminal',
      lines: [],
      scrollback: [],
      cursor: BufferPosition(line: 0, column: 0),
      viewport: BufferViewport(
        topLine: 0,
        leftColumn: 0,
        width: 80,
        height: 24,
      ),
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      isCompressed: false,
      compressionLevel: 0,
      memoryUsage: 0,
    );
    
    _pages[pageId] = page;
    _totalPages++;
    
    // Create index for the page
    _indexes[pageId] = BufferIndex(
      pageId: pageId,
      wordIndex: {},
      lineIndex: {},
      timestampIndex: {},
      lastIndexed: DateTime.now(),
    );
    
    // Initialize stats
    _stats[pageId] = BufferStats(
      pageId: pageId,
      totalLines: 0,
      scrollbackLines: 0,
      totalCharacters: 0,
      memoryUsage: 0,
      compressionRatio: 1.0,
      searchIndexSize: 0,
      lastCleanup: DateTime.now(),
    );
    
    developer.log('📄 Created default buffer page');
  }

  void _startTimers() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
    
    _compressionTimer = Timer.periodic(
      Duration(minutes: 10),
      (_) => _checkCompression(),
    );
  }

  Future<String> addLine({
    required String pageId,
    required String content,
    BufferLineType? type,
    Map<String, dynamic>? metadata,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    final line = BufferLine(
      id: _generateLineId(),
      content: content,
      type: type ?? BufferLineType.normal,
      metadata: metadata ?? {},
      timestamp: DateTime.now(),
      isCompressed: false,
      compressedData: null,
      originalSize: content.length,
      compressedSize: 0,
    );
    
    // Add to current lines
    page.lines.add(line);
    _totalLines++;
    
    // Update scrollback if needed
    if (page.lines.length > page.viewport.height * 2) {
      final scrollbackLines = page.lines.length - page.viewport.height;
      page.scrollback = page.lines.sublist(0, scrollbackLines);
      page.lines = page.lines.sublist(scrollbackLines);
    }
    
    // Update page metadata
    page.lastModified = DateTime.now();
    page.cursor = BufferPosition(
      line: page.lines.length - 1,
      column: content.length,
    );
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Added line to page $pageId: "${content.substring(0, 50)}..."');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.lineAdded,
      pageId: pageId,
      lineId: line.id,
      content: content,
    ));
    
    await _savePage(pageId);
    
    return line.id;
  }

  Future<void> addLines({
    required String pageId,
    required List<String> contents,
    BufferLineType? type,
    Map<String, dynamic>? metadata,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    final lines = contents.map((content) => BufferLine(
      id: _generateLineId(),
      content: content,
      type: type ?? BufferLineType.normal,
      metadata: metadata ?? {},
      timestamp: DateTime.now(),
      isCompressed: false,
      compressedData: null,
      originalSize: content.length,
      compressedSize: 0,
    )).toList();
    
    // Add all lines
    page.lines.addAll(lines);
    _totalLines += lines.length;
    
    // Update scrollback
    if (page.lines.length > page.viewport.height * 2) {
      final scrollbackLines = page.lines.length - page.viewport.height;
      page.scrollback = page.lines.sublist(0, scrollbackLines);
      page.lines = page.lines.sublist(scrollbackLines);
    }
    
    // Update page metadata
    page.lastModified = DateTime.now();
    page.cursor = BufferPosition(
      line: page.lines.length - 1,
      column: lines.last.content.length,
    );
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Added ${lines.length} lines to page $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.linesAdded,
      pageId: pageId,
      lineCount: lines.length,
    ));
    
    await _savePage(pageId);
  }

  Future<void> insertLine({
    required String pageId,
    required int lineIndex,
    required String content,
    BufferLineType? type,
    Map<String, dynamic>? metadata,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    if (lineIndex < 0 || lineIndex > page.lines.length) {
      throw Exception('Invalid line index: $lineIndex');
    }
    
    final line = BufferLine(
      id: _generateLineId(),
      content: content,
      type: type ?? BufferLineType.normal,
      metadata: metadata ?? {},
      timestamp: DateTime.now(),
      isCompressed: false,
      compressedData: null,
      originalSize: content.length,
      compressedSize: 0,
    );
    
    // Insert line at specified position
    page.lines.insert(lineIndex, line);
    _totalLines++;
    
    // Update scrollback if needed
    if (page.lines.length > page.viewport.height * 2) {
      final scrollbackLines = page.lines.length - page.viewport.height;
      page.scrollback = page.lines.sublist(0, scrollbackLines);
      page.lines = page.lines.sublist(scrollbackLines);
    }
    
    // Update page metadata
    page.lastModified = DateTime.now();
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Inserted line at index $lineIndex in page $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.lineInserted,
      pageId: pageId,
      lineId: line.id,
      lineIndex: lineIndex,
      content: content,
    ));
    
    await _savePage(pageId);
  }

  Future<void> deleteLine({
    required String pageId,
    required int lineIndex,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    if (lineIndex < 0 || lineIndex >= page.lines.length) {
      throw Exception('Invalid line index: $lineIndex');
    }
    
    final removedLine = page.lines.removeAt(lineIndex);
    _totalLines--;
    
    // Update cursor if needed
    if (page.cursor.line >= page.lines.length) {
      page.cursor = BufferPosition(
        line: math.max(0, page.lines.length - 1),
        column: page.cursor.column,
      );
    }
    
    // Update page metadata
    page.lastModified = DateTime.now();
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Deleted line at index $lineIndex from page $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.lineDeleted,
      pageId: pageId,
      lineIndex: lineIndex,
    ));
    
    await _savePage(pageId);
  }

  Future<void> clearPage(String pageId, {bool clearScrollback = false}) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    final linesCleared = page.lines.length;
    final scrollbackCleared = page.scrollback.length;
    
    page.lines.clear();
    if (clearScrollback) {
      page.scrollback.clear();
    }
    
    _totalLines -= linesCleared;
    
    // Reset cursor
    page.cursor = BufferPosition(line: 0, column: 0);
    page.lastModified = DateTime.now();
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Cleared page $pageId (${clearScrollback ? 'including' : 'excluding'} scrollback)');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.pageCleared,
      pageId: pageId,
      linesCleared: linesCleared,
      scrollbackCleared: scrollbackCleared,
    ));
    
    await _savePage(pageId);
  }

  Future<List<BufferLine>> getLines({
    required String pageId,
    int? startLine,
    int? endLine,
    bool? includeScrollback,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    List<BufferLine> lines = [];
    
    if (includeScrollback == true) {
      lines.addAll(page.scrollback);
    }
    
    lines.addAll(page.lines);
    
    // Apply range
    if (startLine != null) {
      final startIndex = includeScrollback == true 
          ? startLine! - page.scrollback.length 
          : startLine!;
      
      if (startIndex >= 0 && startIndex < lines.length) {
        lines = lines.sublist(startIndex);
      } else {
        lines = [];
      }
    }
    
    if (endLine != null) {
      final endIndex = includeScrollback == true 
          ? endLine! - page.scrollback.length 
          : endLine!;
      
      if (endIndex >= 0 && endIndex < lines.length) {
        lines = lines.sublist(0, endIndex + 1);
      } else if (endIndex < 0) {
        lines = [];
      }
    }
    
    return lines;
  }

  Future<List<SearchMatch>> search({
    required String pageId,
    required String query,
    SearchType? type,
    bool? caseSensitive,
    bool? regex,
    int? maxResults,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    // Check cache first
    final cacheKey = '${pageId}_${query}_${type?.name ?? 'text'}_${caseSensitive == true ? 'case' : 'nocase'}_${regex == true ? 'regex' : 'noregex'}';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }
    
    final searchType = type ?? SearchType.text;
    final isCaseSensitive = caseSensitive ?? false;
    final isRegex = regex ?? false;
    
    final matches = <SearchMatch>[];
    
    // Search in scrollback
    matches.addAll(_searchInLines(
      page.scrollback,
      query,
      searchType,
      isCaseSensitive,
      isRegex,
      page.scrollback.length - page.lines.length,
    ));
    
    // Search in current lines
    matches.addAll(_searchInLines(
      page.lines,
      query,
      searchType,
      isCaseSensitive,
      isRegex,
      page.lines.length,
    ));
    
    // Apply limit
    if (maxResults != null && maxResults! > 0) {
      matches.sort((a, b) => b.score.compareTo(a.score));
      matches.removeRange(maxResults!, matches.length);
    }
    
    // Cache results
    _searchCache[cacheKey] = matches;
    
    // Clean cache if too large
    if (_searchCache.length > 100) {
      final keysToRemove = _searchCache.keys.take(_searchCache.length - 50);
      for (final key in keysToRemove) {
        _searchCache.remove(key);
      }
    }
    
    developer.log('📄 Search in page $pageId: "$query" (${matches.length} matches)');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.searchPerformed,
      pageId: pageId,
      query: query,
      matchCount: matches.length,
    ));
    
    return matches;
  }

  List<SearchMatch> _searchInLines(
    List<BufferLine> lines,
    String query,
    SearchType type,
    bool caseSensitive,
    bool isRegex,
    int lineOffset,
  ) {
    final matches = <SearchMatch>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final content = line.content;
      
      int score = 0;
      int startIndex = -1;
      int endIndex = -1;
      
      switch (type) {
        case SearchType.text:
          final searchContent = caseSensitive ? content : content.toLowerCase();
          final searchQuery = caseSensitive ? query : query.toLowerCase();
          
          startIndex = searchContent.indexOf(searchQuery);
          if (startIndex >= 0) {
            endIndex = startIndex + query.length;
            score = 1.0;
          }
          break;
          
        case SearchType.fuzzy:
          score = _calculateFuzzyScore(content, query, caseSensitive);
          if (score > 0.3) {
            startIndex = content.toLowerCase().indexOf(query.toLowerCase());
            endIndex = startIndex + query.length;
          }
          break;
          
        case SearchType.regex:
          try {
            final pattern = RegExp(query, caseSensitive: caseSensitive);
            final match = pattern.firstMatch(content);
            if (match != null) {
              startIndex = match.start;
              endIndex = match.end;
              score = 1.0;
            }
          } catch (e) {
            // Invalid regex
          }
          break;
          
        case SearchType.semantic:
          score = _calculateSemanticScore(content, query);
          if (score > 0.2) {
            startIndex = content.toLowerCase().indexOf(query.toLowerCase());
            endIndex = startIndex + query.length;
          }
          break;
      }
      
      if (score > 0) {
        matches.add(SearchMatch(
          lineId: line.id,
          lineIndex: lineOffset + i,
          content: content,
          startIndex: startIndex,
          endIndex: endIndex,
          score: score,
          matchText: startIndex >= 0 ? content.substring(startIndex, endIndex) : '',
        ));
      }
    }
    
    return matches;
  }

  double _calculateFuzzyScore(String content, String query, bool caseSensitive) {
    final searchContent = caseSensitive ? content : content.toLowerCase();
    final searchQuery = caseSensitive ? query : query.toLowerCase();
    
    if (searchContent == searchQuery) return 1.0;
    
    // Simple fuzzy matching
    int matches = 0;
    int queryLength = searchQuery.length;
    
    for (int i = 0; i < queryLength; i++) {
      if (i < searchContent.length && searchContent[i] == searchQuery[i]) {
        matches++;
      }
    }
    
    return matches / queryLength;
  }

  double _calculateSemanticScore(String content, String query) {
    // Simplified semantic scoring based on word boundaries
    final contentWords = content.toLowerCase().split(RegExp(r'\s+'));
    final queryWords = query.toLowerCase().split(RegExp(r'\s+'));
    
    if (queryWords.isEmpty) return 0.0;
    
    int matchedWords = 0;
    for (final queryWord in queryWords) {
      if (contentWords.any((word) => word.contains(queryWord))) {
        matchedWords++;
      }
    }
    
    return matchedWords / queryWords.length;
  }

  Future<void> updateViewport({
    required String pageId,
    int? topLine,
    int? leftColumn,
    int? width,
    int? height,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    final viewport = page.viewport;
    
    if (topLine != null) viewport.topLine = topLine!;
    if (leftColumn != null) viewport.leftColumn = leftColumn!;
    if (width != null) viewport.width = width!;
    if (height != null) viewport.height = height!;
    
    page.lastModified = DateTime.now();
    
    developer.log('📄 Updated viewport for page $pageId: ${viewport.width}x${viewport.height}');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.viewportUpdated,
      pageId: pageId,
      topLine: viewport.topLine,
      leftColumn: viewport.leftColumn,
      width: viewport.width,
      height: viewport.height,
    ));
    
    await _savePage(pageId);
  }

  Future<void> moveCursor({
    required String pageId,
    required int line,
    required int column,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    // Clamp to valid range
    final maxLine = math.max(0, page.lines.length - 1);
    final targetLine = math.max(0, math.min(line, maxLine));
    
    final targetLineObj = page.lines.length > targetLine ? page.lines[targetLine] : null;
    final maxColumn = targetLineObj != null ? targetLineObj!.content.length : 0;
    final targetColumn = math.max(0, math.min(column, maxColumn));
    
    page.cursor = BufferPosition(line: targetLine, column: targetColumn);
    page.lastModified = DateTime.now();
    
    developer.log('📄 Moved cursor in page $pageId: ($targetLine, $targetColumn)');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.cursorMoved,
      pageId: pageId,
      line: targetLine,
      column: targetColumn,
    ));
    
    await _savePage(pageId);
  }

  Future<void> compressPage(String pageId, {int? level}) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    if (page.isCompressed) {
      return; // Already compressed
    }
    
    final compressionLevel = level ?? 6; // Default compression level
    final linesToCompress = page.lines.where((line) => 
        line.originalSize > _compressionThreshold).toList();
    
    if (linesToCompress.isEmpty) {
      return; // Nothing to compress
    }
    
    // Compress lines
    for (final line in linesToCompress) {
      try {
        final compressed = _compressLine(line.content, compressionLevel);
        line.compressedData = compressed;
        line.compressedSize = compressed.length;
        line.isCompressed = true;
      } catch (e) {
        developer.log('📄 Failed to compress line: $e');
      }
    }
    
    page.isCompressed = true;
    page.compressionLevel = compressionLevel;
    page.lastModified = DateTime.now();
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Compressed page $pageId (${linesToCompress.length} lines)');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.pageCompressed,
      pageId: pageId,
      compressionLevel: compressionLevel,
      linesCompressed: linesToCompress.length,
    ));
    
    await _savePage(pageId);
  }

  Future<void> decompressPage(String pageId) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    if (!page.isCompressed) {
      return; // Not compressed
    }
    
    // Decompress lines
    for (final line in page.lines) {
      if (line.isCompressed && line.compressedData != null) {
        try {
          final decompressed = _decompressLine(line.compressedData!);
          line.content = decompressed;
          line.compressedData = null;
          line.isCompressed = false;
          line.compressedSize = 0;
        } catch (e) {
          developer.log('📄 Failed to decompress line: $e');
        }
      }
    }
    
    page.isCompressed = false;
    page.compressionLevel = 0;
    page.lastModified = DateTime.now();
    
    // Update memory usage
    _updateMemoryUsage(pageId);
    
    developer.log('📄 Decompressed page $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.pageDecompressed,
      pageId: pageId,
    ));
    
    await _savePage(pageId);
  }

  Uint8List _compressLine(String content, int level) {
    // Simplified compression using run-length encoding
    final encoded = utf8.encode(content);
    final compressed = <int>[];
    
    int i = 0;
    while (i < encoded.length) {
      final byte = encoded[i];
      int count = 1;
      
      // Count consecutive bytes
      while (i + count < encoded.length && encoded[i + count] == byte) {
        count++;
        if (count == 255) break; // Max count for single byte
      }
      
      compressed.add(byte);
      compressed.add(count);
      i += count;
    }
    
    return Uint8List.from(compressed);
  }

  String _decompressLine(Uint8List compressed) {
    // Decompress run-length encoded data
    final decompressed = <int>[];
    
    for (int i = 0; i < compressed.length; i += 2) {
      if (i + 1 < compressed.length) {
        final byte = compressed[i];
        final count = compressed[i + 1];
        
        for (int j = 0; j < count; j++) {
          decompressed.add(byte);
        }
      }
    }
    
    return String.fromCharCodes(decompressed);
  }

  void _updateMemoryUsage(String pageId) {
    final page = _pages[pageId];
    if (page == null) return;
    
    int memoryUsage = 0;
    
    // Calculate memory usage for lines
    for (final line in page.lines) {
      if (line.isCompressed) {
        memoryUsage += line.compressedSize;
      } else {
        memoryUsage += line.originalSize;
      }
    }
    
    // Add overhead for page structure
    memoryUsage += 1024; // 1KB overhead
    
    page.memoryUsage = memoryUsage;
    
    // Update stats
    final stats = _stats[pageId];
    if (stats != null) {
      stats.memoryUsage = memoryUsage;
      stats.totalLines = page.lines.length + page.scrollback.length;
      stats.scrollbackLines = page.scrollback.length;
      stats.compressionRatio = page.lines.isNotEmpty 
          ? memoryUsage / page.lines.fold(0, (sum, line) => sum + line.originalSize)
          : 1.0;
    }
  }

  Future<void> _performCleanup() async {
    for (final entry in _pages.entries) {
      final pageId = entry.key;
      final page = entry.value;
      
      // Clean old scrollback
      if (page.scrollback.length > _maxScrollbackLines) {
        final toRemove = page.scrollback.length - _maxScrollbackLines;
        page.scrollback.removeRange(0, toRemove);
        
        developer.log('📄 Cleaned $toRemove old scrollback lines from page $pageId');
        
        _emitEvent(BufferEvent(
          type: BufferEventType.scrollbackCleaned,
          pageId: pageId,
          linesRemoved: toRemove,
        ));
      }
      
      // Check memory usage
      if (page.memoryUsage > _maxMemoryUsage) {
        await _compressPage(pageId);
      }
      
      // Update stats
      final stats = _stats[pageId];
      if (stats != null) {
        stats.lastCleanup = DateTime.now();
      }
    }
    
    await _saveAllPages();
  }

  Future<void> _checkCompression() async {
    for (final entry in _pages.entries) {
      final pageId = entry.key;
      final page = entry.value;
      
      // Check if compression should be enabled
      final shouldCompress = page.memoryUsage > (_maxMemoryUsage ~/ 2);
      
      if (shouldCompress && !page.isCompressed) {
        await _compressPage(pageId);
      } else if (!shouldCompress && page.isCompressed) {
        await _decompressPage(pageId);
      }
    }
  }

  Future<void> _savePage(String pageId) async {
    try {
      final file = File('${_bufferConfigFile}.pages');
      
      final pageData = _pages[pageId]!.toJson();
      
      // In practice, this would save to individual page files
      // For now, we'll update the in-memory data
      
      developer.log('📄 Saved page $pageId');
      
    } catch (e) {
      developer.log('📄 Failed to save page $pageId: $e');
    }
  }

  Future<void> _saveAllPages() async {
    try {
      final file = File(_bufferConfigFile);
      
      final pagesData = _pages.values.map((page) => page.toJson()).toList();
      final indexesData = _indexes.values.map((index) => index.toJson()).toList();
      final statsData = _stats.values.map((stats) => stats.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'pages': pagesData,
        'indexes': indexesData,
        'stats': statsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📄 Failed to save pages: $e');
    }
  }

  Future<String> createPage({
    required String name,
    int? width,
    int? height,
  }) async {
    final pageId = _generatePageId();
    
    final page = BufferPage(
      id: pageId,
      name: name,
      lines: [],
      scrollback: [],
      cursor: BufferPosition(line: 0, column: 0),
      viewport: BufferViewport(
        topLine: 0,
        leftColumn: 0,
        width: width ?? 80,
        height: height ?? 24,
      ),
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      isCompressed: false,
      compressionLevel: 0,
      memoryUsage: 0,
    );
    
    _pages[pageId] = page;
    _totalPages++;
    
    // Create index for the page
    _indexes[pageId] = BufferIndex(
      pageId: pageId,
      wordIndex: {},
      lineIndex: {},
      timestampIndex: {},
      lastIndexed: DateTime.now(),
    );
    
    // Initialize stats
    _stats[pageId] = BufferStats(
      pageId: pageId,
      totalLines: 0,
      scrollbackLines: 0,
      totalCharacters: 0,
      memoryUsage: 0,
      compressionRatio: 1.0,
      searchIndexSize: 0,
      lastCleanup: DateTime.now(),
    );
    
    developer.log('📄 Created buffer page: $name');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.pageCreated,
      pageId: pageId,
      pageName: name,
    ));
    
    await _saveAllPages();
    
    return pageId;
  }

  Future<void> deletePage(String pageId) async {
    final page = _pages.remove(pageId);
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    _indexes.remove(pageId);
    _stats.remove(pageId);
    _totalPages--;
    
    // Clear search cache for this page
    _searchCache.removeWhere((key, value) => key.startsWith('${pageId}_'));
    
    developer.log('📄 Deleted buffer page: $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.pageDeleted,
      pageId: pageId,
    ));
    
    await _saveAllPages();
  }

  Future<void> setActivePage(String pageId) async {
    final page = _pages[pageId];
    if (page == null) {
      throw Exception('Page not found: $pageId');
    }
    
    _activePage = pageId;
    
    developer.log('📄 Set active page: $pageId');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.activePageChanged,
      pageId: pageId,
    ));
  }

  BufferPage? getPage(String pageId) {
    return _pages[pageId];
  }

  List<BufferPage> getPages() {
    return _pages.values.toList();
  }

  String? getActivePage() {
    return _activePage;
  }

  BufferStats? getStats(String pageId) {
    return _stats[pageId];
  }

  BufferSystemStats getSystemStats() {
    return BufferSystemStats(
      totalPages: _totalPages,
      totalLines: _totalLines,
      activePage: _activePage,
      totalMemoryUsage: _currentMemoryUsage,
      averageMemoryUsage: _calculateAverageMemoryUsage(),
      compressionRatio: _calculateAverageCompressionRatio(),
      searchCacheSize: _searchCache.length,
    );
  }

  int _calculateAverageMemoryUsage() {
    if (_stats.isEmpty) return 0;
    
    final totalMemory = _stats.values
        .fold(0, (sum, stats) => sum + stats.memoryUsage);
    
    return totalMemory ~/ _stats.length;
  }

  double _calculateAverageCompressionRatio() {
    if (_stats.isEmpty) return 1.0;
    
    final totalRatio = _stats.values
        .fold(0.0, (sum, stats) => sum + stats.compressionRatio);
    
    return totalRatio / _stats.length;
  }

  String _generatePageId() {
    return 'page_${DateTime.now().millisecondsSinceEpoch}_$_totalPages';
  }

  String _generateLineId() {
    return 'line_${DateTime.now().millisecondsSinceEpoch}_$_totalLines';
  }

  void _emitEvent(BufferEvent event) {
    _bufferController.add(event);
  }

  Stream<BufferEvent> get bufferEventStream => _bufferController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    _compressionTimer?.cancel();
    
    _pages.clear();
    _indexes.clear();
    _stats.clear();
    _searchCache.clear();
    _bufferController.close();
    
    developer.log('📄 Smart Terminal Buffer disposed');
  }
}

class BufferPage {
  final String id;
  final String name;
  List<BufferLine> lines;
  List<BufferLine> scrollback;
  BufferPosition cursor;
  BufferViewport viewport;
  final DateTime createdAt;
  DateTime lastModified;
  bool isCompressed;
  int compressionLevel;
  int memoryUsage;

  BufferPage({
    required this.id,
    required this.name,
    required this.lines,
    required this.scrollback,
    required this.cursor,
    required this.viewport,
    required this.createdAt,
    required this.lastModified,
    required this.isCompressed,
    required this.compressionLevel,
    required this.memoryUsage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lines': lines.map((line) => line.toJson()).toList(),
      'scrollback': scrollback.map((line) => line.toJson()).toList(),
      'cursor': {
        'line': cursor.line,
        'column': cursor.column,
      },
      'viewport': {
        'top_line': viewport.topLine,
        'left_column': viewport.leftColumn,
        'width': viewport.width,
        'height': viewport.height,
      },
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
      'is_compressed': isCompressed,
      'compression_level': compressionLevel,
      'memory_usage': memoryUsage,
    };
  }

  factory BufferPage.fromJson(Map<String, dynamic> json) {
    return BufferPage(
      id: json['id'],
      name: json['name'],
      lines: (json['lines'] as List).map((line) => BufferLine.fromJson(line)).toList(),
      scrollback: (json['scrollback'] as List).map((line) => BufferLine.fromJson(line)).toList(),
      cursor: BufferPosition(
        line: json['cursor']['line'],
        column: json['cursor']['column'],
      ),
      viewport: BufferViewport(
        topLine: json['viewport']['top_line'],
        leftColumn: json['viewport']['left_column'],
        width: json['viewport']['width'],
        height: json['viewport']['height'],
      ),
      createdAt: DateTime.parse(json['created_at']),
      lastModified: DateTime.parse(json['last_modified']),
      isCompressed: json['is_compressed'] ?? false,
      compressionLevel: json['compression_level'] ?? 0,
      memoryUsage: json['memory_usage'] ?? 0,
    );
  }
}

class BufferLine {
  final String id;
  String content;
  final BufferLineType type;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  bool isCompressed;
  Uint8List? compressedData;
  int originalSize;
  int compressedSize;

  BufferLine({
    required this.id,
    required this.content,
    required this.type,
    required this.metadata,
    required this.timestamp,
    required this.isCompressed,
    this.compressedData,
    required this.originalSize,
    required this.compressedSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': isCompressed ? '' : content,
      'type': type.name,
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
      'is_compressed': isCompressed,
      'compressed_data': isCompressed && compressedData != null 
          ? List<int>.from(compressedData!)
          : null,
      'original_size': originalSize,
      'compressed_size': compressedSize,
    };
  }

  factory BufferLine.fromJson(Map<String, dynamic> json) {
    return BufferLine(
      id: json['id'],
      content: json['content'],
      type: BufferLineType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => BufferLineType.normal,
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      timestamp: DateTime.parse(json['timestamp']),
      isCompressed: json['is_compressed'] ?? false,
      compressedData: json['compressed_data'] != null 
          ? Uint8List.fromList(json['compressed_data'])
          : null,
      originalSize: json['original_size'] ?? 0,
      compressedSize: json['compressed_size'] ?? 0,
    );
  }
}

class BufferPosition {
  final int line;
  final int column;

  BufferPosition({
    required this.line,
    required this.column,
  });
}

class BufferViewport {
  final int topLine;
  final int leftColumn;
  final int width;
  final int height;

  BufferViewport({
    required this.topLine,
    required this.leftColumn,
    required this.width,
    required this.height,
  });
}

class BufferIndex {
  final String pageId;
  final Map<String, List<int>> wordIndex;
  final Map<String, List<int>> lineIndex;
  final Map<String, DateTime> timestampIndex;
  final DateTime lastIndexed;

  BufferIndex({
    required this.pageId,
    required this.wordIndex,
    required this.lineIndex,
    required this.timestampIndex,
    required this.lastIndexed,
  });

  Map<String, dynamic> toJson() {
    return {
      'page_id': pageId,
      'word_index': wordIndex,
      'line_index': lineIndex,
      'timestamp_index': timestampIndex,
      'last_indexed': lastIndexed.toIso8601String(),
    };
  }

  factory BufferIndex.fromJson(Map<String, dynamic> json) {
    return BufferIndex(
      pageId: json['page_id'],
      wordIndex: Map<String, List<int>>.from(json['word_index'] ?? {}),
      lineIndex: Map<String, List<int>>.from(json['line_index'] ?? {}),
      timestampIndex: Map<String, DateTime>.from(
        (json['timestamp_index'] as Map?)?.map((k, v) => MapEntry(k, DateTime.parse(v))) ?? {}
      ),
      lastIndexed: DateTime.parse(json['last_indexed']),
    );
  }
}

class BufferStats {
  final String pageId;
  int totalLines;
  int scrollbackLines;
  int totalCharacters;
  int memoryUsage;
  double compressionRatio;
  int searchIndexSize;
  final DateTime lastCleanup;

  BufferStats({
    required this.pageId,
    required this.totalLines,
    required this.scrollbackLines,
    required this.totalCharacters,
    required this.memoryUsage,
    required this.compressionRatio,
    required this.searchIndexSize,
    required this.lastCleanup,
  });

  Map<String, dynamic> toJson() {
    return {
      'page_id': pageId,
      'total_lines': totalLines,
      'scrollback_lines': scrollbackLines,
      'total_characters': totalCharacters,
      'memory_usage': memoryUsage,
      'compression_ratio': compressionRatio,
      'search_index_size': searchIndexSize,
      'last_cleanup': lastCleanup.toIso8601String(),
    };
  }

  factory BufferStats.fromJson(Map<String, dynamic> json) {
    return BufferStats(
      pageId: json['page_id'],
      totalLines: json['total_lines'] ?? 0,
      scrollbackLines: json['scrollback_lines'] ?? 0,
      totalCharacters: json['total_characters'] ?? 0,
      memoryUsage: json['memory_usage'] ?? 0,
      compressionRatio: (json['compression_ratio'] ?? 1.0).toDouble(),
      searchIndexSize: json['search_index_size'] ?? 0,
      lastCleanup: DateTime.parse(json['last_cleanup']),
    );
  }
}

class SearchMatch {
  final String lineId;
  final int lineIndex;
  final String content;
  final int startIndex;
  final int endIndex;
  final double score;
  final String matchText;

  SearchMatch({
    required this.lineId,
    required this.lineIndex,
    required this.content,
    required this.startIndex,
    required this.endIndex,
    required this.score,
    required this.matchText,
  });
}

enum BufferLineType {
  normal,
  command,
  output,
  error,
  warning,
}

enum SearchType {
  text,
  fuzzy,
  regex,
  semantic,
}

enum BufferEventType {
  lineAdded,
  linesAdded,
  lineInserted,
  lineDeleted,
  pageCleared,
  scrollbackCleaned,
  pageCompressed,
  pageDecompressed,
  searchPerformed,
  viewportUpdated,
  cursorMoved,
  pageCreated,
  pageDeleted,
  activePageChanged,
}

class BufferEvent {
  final BufferEventType type;
  final String? pageId;
  final String? pageName;
  final String? lineId;
  final String? content;
  final int? lineIndex;
  final int? lineCount;
  final int? linesCleared;
  final int? scrollbackCleared;
  final int? linesCompressed;
  final int? compressionLevel;
  final String? query;
  final int? matchCount;
  final int? topLine;
  final int? leftColumn;
  final int? width;
  final int? height;
  final int? line;
  final int? column;

  BufferEvent({
    required this.type,
    this.pageId,
    this.pageName,
    this.lineId,
    this.content,
    this.lineIndex,
    this.lineCount,
    this.linesCleared,
    this.scrollbackCleared,
    this.linesCompressed,
    this.compressionLevel,
    this.query,
    this.matchCount,
    this.topLine,
    this.leftColumn,
    this.width,
    this.height,
    this.line,
    this.column,
  });
}

class BufferSystemStats {
  final int totalPages;
  final int totalLines;
  final String? activePage;
  final int totalMemoryUsage;
  final int averageMemoryUsage;
  final double averageCompressionRatio;
  final int searchCacheSize;

  BufferSystemStats({
    required this.totalPages,
    required this.totalLines,
    this.activePage,
    required this.totalMemoryUsage,
    required this.averageMemoryUsage,
    required this.averageCompressionRatio,
    required this.searchCacheSize,
  });
}
