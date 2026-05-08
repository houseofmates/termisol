import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Jump Navigation - Quick navigation with markers
/// 
/// Implements comprehensive jump navigation:
/// - Jump markers with single character shortcuts
/// - Quick navigation to lines and positions
/// - Bookmark system for important locations
/// - Navigation history with back/forward
/// - Smart jump suggestions
/// - Persistent marker storage
class JumpNavigation {
  bool _isInitialized = false;
  
  // Jump markers (single character)
  final Map<String, JumpMarker> _markers = {};
  final Map<String, MarkerPosition> _markerPositions = {};
  
  // Bookmarks
  final Map<String, Bookmark> _bookmarks = {};
  final List<String> _bookmarkNames = [];
  
  // Navigation history
  final List<NavigationHistory> _history = [];
  int _historyIndex = -1;
  
  // Quick navigation
  final Map<String, QuickNavigation> _quickNav = {};
  final Map<String, NavigationPattern> _patterns = {};
  
  // Configuration
  JumpNavigationConfig _config = JumpNavigationConfig();
  
  JumpNavigation();
  
  bool get isInitialized => _isInitialized;
  Map<String, JumpMarker> get markers => Map.unmodifiable(_markers);
  Map<String, Bookmark> get bookmarks => Map.unmodifiable(_bookmarks);
  List<NavigationHistory> get history => List.unmodifiable(_history);
  int get historyIndex => _historyIndex;
  
  /// Initialize jump navigation
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Load persistent data
      await _loadPersistentData();
      
      // Setup default patterns
      _setupDefaultPatterns();
      
      _isInitialized = true;
      debugPrint('🔀 Jump Navigation initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Jump Navigation: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/jump_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = JumpNavigationConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load jump navigation config: $e');
    }
  }
  
  /// Load persistent data
  Future<void> _loadPersistentData() async {
    try {
      final dataFile = File('${Platform.environment['HOME']}/.termisol/jump_data.json');
      if (await dataFile.exists()) {
        final content = await dataFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        // Load markers
        final markersData = data['markers'] as Map<String, dynamic>?;
        if (markersData != null) {
          for (final entry in markersData.entries) {
            _markers[entry.key] = JumpMarker.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        
        // Load bookmarks
        final bookmarksData = data['bookmarks'] as Map<String, dynamic>?;
        if (bookmarksData != null) {
          for (final entry in bookmarksData.entries) {
            _bookmarks[entry.key] = Bookmark.fromJson(entry.value as Map<String, dynamic>);
          }
          _bookmarkNames.add(entry.key);
        }
        
        // Load history
        final historyData = data['history'] as List<dynamic>?;
        if (historyData != null) {
          _history.clear();
          for (final item in historyData) {
            _history.add(NavigationHistory.fromJson(item as Map<String, dynamic>));
          }
          _historyIndex = _history.length - 1;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load jump navigation data: $e');
    }
  }
  
  /// Setup default navigation patterns
  void _setupDefaultPatterns() {
    _patterns.addAll({
      'line': NavigationPattern(
        name: 'line',
        pattern: r'^\d+$',
        description: 'Jump to line number',
        action: _jumpToLine,
      ),
      'column': NavigationPattern(
        name: 'column',
        pattern: r'^:\d+$',
        description: 'Jump to column in current line',
        action: _jumpToColumn,
      ),
      'file': NavigationPattern(
        name: 'file',
        pattern: r'^[a-zA-Z]:.*$',
        description: 'Jump to file path',
        action: _jumpToFile,
      ),
      'function': NavigationPattern(
        name: 'function',
        pattern: r'^[a-zA-Z_][a-zA-Z0-9_]*\(',
        description: 'Jump to function definition',
        action: _jumpToFunction,
      ),
      'class': NavigationPattern(
        name: 'class',
        pattern: r'^class\s+[a-zA-Z_][a-zA-Z0-9_]*',
        description: 'Jump to class definition',
        action: _jumpToClass,
      ),
      'url': NavigationPattern(
        name: 'url',
        pattern: r'^https?://',
        description: 'Jump to URL',
        action: _jumpToURL,
      ),
      'email': NavigationPattern(
        name: 'email',
        pattern: r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        description: 'Jump to email address',
        action: _jumpToEmail,
      ),
      'ip': NavigationPattern(
        name: 'ip',
        pattern: r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',
        description: 'Jump to IP address',
        action: _jumpToIP,
      ),
    });
    
    debugPrint('🔀 Setup ${_patterns.length} navigation patterns');
  }
  
  /// Set jump marker
  void setMarker(String marker, int line, int column, {String? content, String? file}) {
    if (marker.length != 1) {
      debugPrint('⚠️ Jump marker must be single character');
      return;
    }
    
    _markers[marker] = JumpMarker(
      marker: marker,
      line: line,
      column: column,
      content: content,
      file: file,
      timestamp: DateTime.now(),
    );
    
    _markerPositions[marker] = MarkerPosition(line, column);
    
    debugPrint('🔀 Set jump marker: $marker at ($line, $column)');
  }
  
  /// Jump to marker
  bool jumpToMarker(String marker) {
    final jumpMarker = _markers[marker];
    if (jumpMarker == null) {
      debugPrint('⚠️ Jump marker not found: $marker');
      return false;
    }
    
    // Add to history
    _addToHistory(NavigationType.marker, marker, jumpMarker.line, jumpMarker.column);
    
    debugPrint('🔀 Jumped to marker: $marker at (${jumpMarker.line}, ${jumpMarker.column})');
    return true;
  }
  
  /// Get marker position
  MarkerPosition? getMarkerPosition(String marker) {
    return _markerPositions[marker];
  }
  
  /// Clear marker
  void clearMarker(String marker) {
    _markers.remove(marker);
    _markerPositions.remove(marker);
    debugPrint('🗑️ Cleared jump marker: $marker');
  }
  
  /// Clear all markers
  void clearAllMarkers() {
    _markers.clear();
    _markerPositions.clear();
    debugPrint('🗑️ Cleared all jump markers');
  }
  
  /// Add bookmark
  void addBookmark(String name, int line, int column, {String? content, String? file, List<String>? tags}) {
    _bookmarks[name] = Bookmark(
      name: name,
      line: line,
      column: column,
      content: content,
      file: file,
      tags: tags ?? [],
      timestamp: DateTime.now(),
    );
    
    if (!_bookmarkNames.contains(name)) {
      _bookmarkNames.add(name);
    }
    
    debugPrint('🔖 Added bookmark: $name at ($line, $column)');
  }
  
  /// Jump to bookmark
  bool jumpToBookmark(String name) {
    final bookmark = _bookmarks[name];
    if (bookmark == null) {
      debugPrint('⚠️ Bookmark not found: $name');
      return false;
    }
    
    // Add to history
    _addToHistory(NavigationType.bookmark, name, bookmark.line, bookmark.column);
    
    debugPrint('🔖 Jumped to bookmark: $name at (${bookmark.line}, ${bookmark.column})');
    return true;
  }
  
  /// Remove bookmark
  void removeBookmark(String name) {
    _bookmarks.remove(name);
    _bookmarkNames.remove(name);
    debugPrint('🗑️ Removed bookmark: $name');
  }
  
  /// Get bookmark suggestions
  List<Bookmark> getBookmarkSuggestions(String partial) {
    if (partial.isEmpty) return [];
    
    final lowerPartial = partial.toLowerCase();
    final suggestions = <Bookmark>[];
    
    for (final name in _bookmarkNames) {
      if (name.toLowerCase().contains(lowerPartial)) {
        final bookmark = _bookmarks[name]!;
        suggestions.add(bookmark);
      }
    }
    
    // Sort by relevance (name match, then recency)
    suggestions.sort((a, b) {
      final aScore = _calculateBookmarkScore(a, partial);
      final bScore = _calculateBookmarkScore(b, partial);
      return bScore.compareTo(aScore);
    });
    
    return suggestions.take(_config.maxSuggestions).toList();
  }
  
  /// Calculate bookmark score for suggestions
  double _calculateBookmarkScore(Bookmark bookmark, String partial) {
    double score = 0.0;
    
    // Name match score
    final name = bookmark.name.toLowerCase();
    final search = partial.toLowerCase();
    
    if (name.startsWith(search)) {
      score += 10.0;
    } else if (name.contains(search)) {
      score += 5.0;
    }
    
    // Recency score
    final daysOld = DateTime.now().difference(bookmark.timestamp).inDays;
    score += max(0.0, 5.0 - daysOld * 0.5);
    
    // Tag relevance
    for (final tag in bookmark.tags) {
      if (tag.toLowerCase().contains(search)) {
        score += 2.0;
      }
    }
    
    return score;
  }
  
  /// Quick jump to line
  bool jumpToLine(int line) {
    if (line < 0) return false;
    
    // Add to history
    _addToHistory(NavigationType.line, line.toString(), line, 0);
    
    debugPrint('🔀 Jumped to line: $line');
    return true;
  }
  
  /// Quick jump to column
  bool jumpToColumn(int column) {
    if (column < 0) return false;
    
    // Add to history
    _addToHistory(NavigationType.column, column.toString(), 0, column);
    
    debugPrint('🔀 Jumped to column: $column');
    return true;
  }
  
  /// Quick jump to position
  bool jumpToPosition(int line, int column) {
    if (line < 0 || column < 0) return false;
    
    // Add to history
    _addToHistory(NavigationType.position, '($line,$column)', line, column);
    
    debugPrint('🔀 Jumped to position: ($line, $column)');
    return true;
  }
  
  /// Jump to file
  bool jumpToFile(String filePath) {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('⚠️ File not found: $filePath');
        return false;
      }
      
      // Add to history
      _addToHistory(NavigationType.file, filePath, 0, 0);
      
      debugPrint('🔀 Jumped to file: $filePath');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to jump to file: $e');
      return false;
    }
  }
  
  /// Jump to function
  bool jumpToFunction(String functionName, String? file) {
    // Add to history
    _addToHistory(NavigationType.function, functionName, 0, 0);
    
    debugPrint('🔀 Jumped to function: $functionName');
    return true;
  }
  
  /// Jump to class
  bool jumpToClass(String className, String? file) {
    // Add to history
    _addToHistory(NavigationType.class, className, 0, 0);
    
    debugPrint('🔀 Jumped to class: $className');
    return true;
  }
  
  /// Jump to URL
  bool jumpToURL(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme) {
        url = 'https://$url';
      }
      
      // Add to history
      _addToHistory(NavigationType.url, url, 0, 0);
      
      debugPrint('🔀 Jumped to URL: $url');
      return true;
    } catch (e) {
      debugPrint('⚠️ Invalid URL: $url');
      return false;
    }
  }
  
  /// Jump to email
  bool jumpToEmail(String email) {
    try {
      if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
        debugPrint('⚠️ Invalid email: $email');
        return false;
      }
      
      // Add to history
      _addToHistory(NavigationType.email, email, 0, 0);
      
      debugPrint('🔀 Jumped to email: $email');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to jump to email: $e');
      return false;
    }
  }
  
  /// Jump to IP address
  bool jumpToIP(String ip) {
    try {
      if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip)) {
        debugPrint('⚠️ Invalid IP: $ip');
        return false;
      }
      
      // Add to history
      _addToHistory(NavigationType.ip, ip, 0, 0);
      
      debugPrint('🔀 Jumped to IP: $ip');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to jump to IP: $e');
      return false;
    }
  }
  
  /// Parse and execute navigation command
  bool parseAndExecute(String command) {
    try {
      // Check for jump markers (single character)
      if (command.length == 1 && _markers.containsKey(command)) {
        return jumpToMarker(command);
      }
      
      // Check for navigation patterns
      for (final entry in _patterns.entries) {
        final pattern = entry.value;
        if (RegExp(pattern.pattern).hasMatch(command)) {
          return pattern.action(command);
        }
      }
      
      // Check for line number
      final lineMatch = RegExp(r'^\d+$').firstMatch(command);
      if (lineMatch != null) {
        final line = int.parse(lineMatch.group(0)!);
        return jumpToLine(line);
      }
      
      // Check for column number
      final columnMatch = RegExp(r'^:\d+$').firstMatch(command);
      if (columnMatch != null) {
        final column = int.parse(columnMatch.group(0)!.substring(1));
        return jumpToColumn(column);
      }
      
      // Check for position (line:column)
      final positionMatch = RegExp(r'^(\d+):(\d+)$').firstMatch(command);
      if (positionMatch != null) {
        final line = int.parse(positionMatch.group(1)!);
        final column = int.parse(positionMatch.group(2)!);
        return jumpToPosition(line, column);
      }
      
      debugPrint('⚠️ Unknown navigation command: $command');
      return false;
    } catch (e) {
      debugPrint('⚠️ Failed to parse navigation command: $e');
      return false;
    }
  }
  
  /// Add to navigation history
  void _addToHistory(NavigationType type, String target, int line, int column) {
    final history = NavigationHistory(
      type: type,
      target: target,
      line: line,
      column: column,
      timestamp: DateTime.now(),
    );
    
    // Remove any forward history
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    
    _history.add(history);
    _historyIndex = _history.length - 1;
    
    // Limit history size
    if (_history.length > _config.maxHistorySize) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }
  
  /// Navigate back in history
  NavigationHistory? navigateBack() {
    if (_historyIndex <= 0) return null;
    
    _historyIndex--;
    final history = _history[_historyIndex];
    
    debugPrint('🔀 Navigate back to: ${history.target}');
    return history;
  }
  
  /// Navigate forward in history
  NavigationHistory? navigateForward() {
    if (_historyIndex >= _history.length - 1) return null;
    
    _historyIndex++;
    final history = _history[_historyIndex];
    
    debugPrint('🔀 Navigate forward to: ${history.target}');
    return history;
  }
  
  /// Get current history position
  NavigationHistory? getCurrentHistory() {
    if (_historyIndex < 0 || _historyIndex >= _history.length) {
      return null;
    }
    return _history[_historyIndex];
  }
  
  /// Get navigation suggestions
  List<NavigationSuggestion> getNavigationSuggestions(String partial) {
    final suggestions = <NavigationSuggestion>[];
    
    // Marker suggestions
    for (final entry in _markers.entries) {
      if (entry.key.contains(partial)) {
        suggestions.add(NavigationSuggestion(
          type: SuggestionType.marker,
          text: entry.key,
          description: 'Jump to marker ${entry.key}',
          target: entry.key,
          line: entry.value.line,
          column: entry.value.column,
        ));
      }
    }
    
    // Bookmark suggestions
    final bookmarkSuggestions = getBookmarkSuggestions(partial);
    for (final bookmark in bookmarkSuggestions) {
      suggestions.add(NavigationSuggestion(
        type: SuggestionType.bookmark,
        text: bookmark.name,
        description: 'Jump to bookmark ${bookmark.name}',
        target: bookmark.name,
        line: bookmark.line,
        column: bookmark.column,
      ));
    }
    
    // History suggestions
    for (final history in _history) {
      if (history.target.toLowerCase().contains(partial.toLowerCase())) {
        suggestions.add(NavigationSuggestion(
          type: SuggestionType.history,
          text: history.target,
          description: 'Jump to ${history.target}',
          target: history.target,
          line: history.line,
          column: history.column,
        ));
      }
    }
    
    // Sort by relevance
    suggestions.sort((a, b) => _calculateSuggestionScore(b, partial).compareTo(_calculateSuggestionScore(a, partial)));
    
    return suggestions.take(_config.maxSuggestions).toList();
  }
  
  /// Calculate suggestion score
  double _calculateSuggestionScore(NavigationSuggestion suggestion, String partial) {
    double score = 0.0;
    
    // Type priority
    switch (suggestion.type) {
      case SuggestionType.marker:
        score += 10.0;
        break;
      case SuggestionType.bookmark:
        score += 8.0;
        break;
      case SuggestionType.history:
        score += 6.0;
        break;
    }
    
    // Text match score
    final text = suggestion.text.toLowerCase();
    final search = partial.toLowerCase();
    
    if (text.startsWith(search)) {
      score += 10.0;
    } else if (text.contains(search)) {
      score += 5.0;
    }
    
    return score;
  }
  
  /// Get quick navigation options
  Map<String, QuickNavigation> getQuickNavigation() {
    return {
      'gg': QuickNavigation(
        name: 'gg',
        description: 'Jump to first line',
        action: () => jumpToLine(1),
      ),
      'G': QuickNavigation(
        name: 'G',
        description: 'Jump to last line',
        action: () => jumpToLine(-1), // -1 means last line
      ),
      '0': QuickNavigation(
        name: '0',
        description: 'Jump to beginning of line',
        action: () => jumpToColumn(0),
      ),
      '\$': QuickNavigation(
        name: '\$',
        description: 'Jump to end of line',
        action: () => jumpToColumn(-1), // -1 means end of line
      ),
      'h': QuickNavigation(
        name: 'h',
        description: 'Jump left',
        action: () => _quickMove(-1, 0),
      ),
      'j': QuickNavigation(
        name: 'j',
        description: 'Jump down',
        action: () => _quickMove(0, 1),
      ),
      'k': QuickNavigation(
        name: 'k',
        description: 'Jump up',
        action: () => _quickMove(0, -1),
      ),
      'l': QuickNavigation(
        name: 'l',
        description: 'Jump right',
        action: () => _quickMove(1, 0),
      ),
      'w': QuickNavigation(
        name: 'w',
        description: 'Jump word forward',
        action: () => _jumpWord(1),
      ),
      'b': QuickNavigation(
        name: 'b',
        description: 'Jump word backward',
        action: () => _jumpWord(-1),
      ),
      'e': QuickNavigation(
        name: 'e',
        description: 'Jump word end',
        action: () => _jumpWordEnd(1),
      ),
      'ge': QuickNavigation(
        name: 'ge',
        description: 'Jump word end backward',
        action: () => _jumpWordEnd(-1),
      ),
    };
  }
  
  /// Quick move
  void _quickMove(int dx, int dy) {
    // Implementation for quick movement
    debugPrint('🔀 Quick move: dx=$dx, dy=$dy');
  }
  
  /// Jump word
  void _jumpWord(int direction) {
    // Implementation for word jumping
    debugPrint('🔀 Jump word: direction=$direction');
  }
  
  /// Jump word end
  void _jumpWordEnd(int direction) {
    // Implementation for word end jumping
    debugPrint('🔀 Jump word end: direction=$direction');
  }
  
  /// Save persistent data
  Future<void> savePersistentData() async {
    try {
      final data = {
        'markers': _markers.map((key, marker) => MapEntry(key, marker.toJson())),
        'bookmarks': _bookmarks.map((key, bookmark) => MapEntry(key, bookmark.toJson())),
        'history': _history.map((history) => history.toJson()),
        'lastSaved': DateTime.now().toIso8601String(),
      };
      
      final dataFile = File('${Platform.environment['HOME']}/.termisol/jump_data.json');
      await dataFile.writeAsString(jsonEncode(data));
      
      debugPrint('💾 Jump navigation data saved');
    } catch (e) {
      debugPrint('⚠️ Failed to save jump navigation data: $e');
    }
  }
  
  /// Get navigation statistics
  NavigationStatistics getStatistics() {
    return NavigationStatistics(
      totalMarkers: _markers.length,
      totalBookmarks: _bookmarks.length,
      historySize: _history.length,
      historyIndex: _historyIndex,
      oldestBookmark: _bookmarks.values.isEmpty ? null : _bookmarks.values.reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b).timestamp,
      newestBookmark: _bookmarks.values.isEmpty ? null : _bookmarks.values.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b).timestamp,
    );
  }
  
  /// Export bookmarks
  String exportBookmarks() {
    final data = {
      'bookmarks': _bookmarks.map((key, bookmark) => MapEntry(key, bookmark.toJson())),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    
    return jsonEncode(data);
  }
  
  /// Import bookmarks
  bool importBookmarks(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final bookmarksData = data['bookmarks'] as Map<String, dynamic>?;
      
      if (bookmarksData != null) {
        for (final entry in bookmarksData.entries) {
          final bookmark = Bookmark.fromJson(entry.value as Map<String, dynamic>);
          _bookmarks[entry.key] = bookmark;
          if (!_bookmarkNames.contains(entry.key)) {
            _bookmarkNames.add(entry.key);
          }
        }
      }
      
      debugPrint('📥 Imported ${bookmarksData?.length ?? 0} bookmarks');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import bookmarks: $e');
      return false;
    }
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await savePersistentData();
    
    _markers.clear();
    _markerPositions.clear();
    _bookmarks.clear();
    _bookmarkNames.clear();
    _history.clear();
    _quickNav.clear();
    _patterns.clear();
    
    _isInitialized = false;
    debugPrint('🔀 Jump Navigation disposed');
  }
}

/// Jump marker data structure
class JumpMarker {
  final String marker;
  final int line;
  final int column;
  final String? content;
  final String? file;
  final DateTime timestamp;
  
  JumpMarker({
    required this.marker,
    required this.line,
    required this.column,
    this.content,
    this.file,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'marker': marker,
    'line': line,
    'column': column,
    'content': content,
    'file': file,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory JumpMarker.fromJson(Map<String, dynamic> json) => JumpMarker(
    marker: json['marker'] as String,
    line: json['line'] as int,
    column: json['column'] as int,
    content: json['content'] as String?,
    file: json['file'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Bookmark data structure
class Bookmark {
  final String name;
  final int line;
  final int column;
  final String? content;
  final String? file;
  final List<String> tags;
  final DateTime timestamp;
  
  Bookmark({
    required this.name,
    required this.line,
    required this.column,
    this.content,
    this.file,
    required this.tags,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'line': line,
    'column': column,
    'content': content,
    'file': file,
    'tags': tags,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    name: json['name'] as String,
    line: json['line'] as int,
    column: json['column'] as int,
    content: json['content'] as String?,
    file: json['file'] as String?,
    tags: List<String>.from(json['tags'] as List? ?? []),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Marker position data structure
class MarkerPosition {
  final int line;
  final int column;
  
  const MarkerPosition(this.line, this.column);
}

/// Navigation history data structure
class NavigationHistory {
  final NavigationType type;
  final String target;
  final int line;
  final int column;
  final DateTime timestamp;
  
  NavigationHistory({
    required this.type,
    required this.target,
    required this.line,
    required this.column,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'target': target,
    'line': line,
    'column': column,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory NavigationHistory.fromJson(Map<String, dynamic> json) => NavigationHistory(
    type: NavigationType.values.firstWhere(
      (t) => t.toString() == json['type'],
      orElse: () => NavigationType.marker,
    ),
    target: json['target'] as String,
    line: json['line'] as int,
    column: json['column'] as int,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Navigation pattern data structure
class NavigationPattern {
  final String name;
  final String pattern;
  final String description;
  final bool Function(String) action;
  
  NavigationPattern({
    required this.name,
    required this.pattern,
    required this.description,
    required this.action,
  });
}

/// Quick navigation data structure
class QuickNavigation {
  final String name;
  final String description;
  final VoidCallback action;
  
  QuickNavigation({
    required this.name,
    required this.description,
    required this.action,
  });
}

/// Navigation suggestion data structure
class NavigationSuggestion {
  final SuggestionType type;
  final String text;
  final String description;
  final String target;
  final int line;
  final int column;
  
  NavigationSuggestion({
    required this.type,
    required this.text,
    required this.description,
    required this.target,
    required this.line,
    required this.column,
  });
}

/// Navigation type enumeration
enum NavigationType {
  marker,
  bookmark,
  line,
  column,
  position,
  file,
  function,
  class,
  url,
  email,
  ip,
}

/// Suggestion type enumeration
enum SuggestionType {
  marker,
  bookmark,
  history,
}

/// Jump navigation configuration
class JumpNavigationConfig {
  final int maxHistorySize;
  final int maxSuggestions;
  final bool enableAutoSave;
  final Duration autoSaveInterval;
  final bool enableSmartSuggestions;
  
  JumpNavigationConfig({
    this.maxHistorySize = 100,
    this.maxSuggestions = 10,
    this.enableAutoSave = true,
    this.autoSaveInterval = const Duration(seconds: 30),
    this.enableSmartSuggestions = true,
  });
  
  Map<String, dynamic> toJson() => {
    'maxHistorySize': maxHistorySize,
    'maxSuggestions': maxSuggestions,
    'enableAutoSave': enableAutoSave,
    'autoSaveInterval': autoSaveInterval.inMilliseconds,
    'enableSmartSuggestions': enableSmartSuggestions,
  };
  
  factory JumpNavigationConfig.fromJson(Map<String, dynamic> json) => JumpNavigationConfig(
    maxHistorySize: json['maxHistorySize'] as int? ?? 100,
    maxSuggestions: json['maxSuggestions'] as int? ?? 10,
    enableAutoSave: json['enableAutoSave'] as bool? ?? true,
    autoSaveInterval: Duration(milliseconds: json['autoSaveInterval'] as int? ?? 30000),
    enableSmartSuggestions: json['enableSmartSuggestions'] as bool? ?? true,
  );
}

/// Navigation statistics data structure
class NavigationStatistics {
  final int totalMarkers;
  final int totalBookmarks;
  final int historySize;
  final int historyIndex;
  final DateTime? oldestBookmark;
  final DateTime? newestBookmark;
  
  NavigationStatistics({
    required this.totalMarkers,
    required this.totalBookmarks,
    required this.historySize,
    required this.historyIndex,
    this.oldestBookmark,
    this.newestBookmark,
  });
}
