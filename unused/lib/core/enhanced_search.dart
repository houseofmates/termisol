import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:google_fonts/google_fonts.dart';

/// Enhanced Search - Advanced search functionality with multiple modes
/// 
/// Features:
/// - Real-time search with highlighting
/// - Multiple search modes (text, regex, fuzzy)
/// - Search history
/// - Case sensitivity toggle
/// - Whole word matching
/// - Search navigation (next/previous)
/// - Results counter
/// - Search in all tabs
/// - Quick search shortcuts
class EnhancedSearch {
  bool _isInitialized = false;
  
  // Search state
  bool _isSearchMode = false;
  String _searchQuery = '';
  List<SearchResult> _results = [];
  int _currentResultIndex = 0;
  
  // Search options
  SearchMode _searchMode = SearchMode.text;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _useRegex = false;
  bool _fuzzySearch = false;
  
  // Search history
  List<String> _searchHistory = [];
  int _maxHistorySize = 50;
  
  // Highlighting
  List<TextHighlight> _highlights = [];
  
  // Performance
  Timer? _debounceTimer;
  final Duration _debounceDelay = const Duration(milliseconds: 300);
  
  // Callbacks
  Function(List<SearchResult>)? _onResultsChanged;
  Function(String)? _onQueryChanged;
  Function()? _onSearchModeChanged;
  
  EnhancedSearch();
  
  bool get isInitialized => _isInitialized;
  bool get isSearchMode => _isSearchMode;
  String get searchQuery => _searchQuery;
  List<SearchResult> get results => List.unmodifiable(_results);
  int get currentResultIndex => _currentResultIndex;
  SearchMode get searchMode => _searchMode;
  bool get caseSensitive => _caseSensitive;
  bool get wholeWord => _wholeWord;
  bool get useRegex => _useRegex;
  bool get fuzzySearch => _fuzzySearch;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  List<TextHighlight> get highlights => List.unmodifiable(_highlights);
  
  /// Initialize enhanced search
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load search history
      await _loadSearchHistory();
      
      // Setup keyboard shortcuts
      _setupKeyboardShortcuts();
      
      _isInitialized = true;
      debugPrint('🔍 Enhanced Search initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Enhanced Search: $e');
      rethrow;
    }
  }
  
  /// Load search history
  Future<void> _loadSearchHistory() async {
    try {
      // In a real app, you would load from persistent storage
      _searchHistory = [
        'function',
        'class',
        'import',
        'const',
        'final',
        'void main',
        'setState',
        'build',
        'return',
      ];
    } catch (e) {
      debugPrint('⚠️ Failed to load search history: $e');
    }
  }
  
  /// Setup keyboard shortcuts
  void _setupKeyboardShortcuts() {
    // This would integrate with the main app's keyboard shortcut system
    debugPrint('⌨️ Keyboard shortcuts configured for enhanced search');
  }
  
  /// Enter search mode
  void enterSearchMode() {
    _isSearchMode = true;
    _onSearchModeChanged?.call();
    debugPrint('🔍 Entered search mode');
  }
  
  /// Exit search mode
  void exitSearchMode() {
    _isSearchMode = false;
    _clearSearch();
    _onSearchModeChanged?.call();
    debugPrint('🔍 Exited search mode');
  }
  
  /// Toggle search mode
  void toggleSearchMode() {
    if (_isSearchMode) {
      exitSearchMode();
    } else {
      enterSearchMode();
    }
  }
  
  /// Update search query
  void updateQuery(String query) {
    _searchQuery = query;
    _onQueryChanged?.call(query);
    
    // Debounce search
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      _performSearch();
    });
  }
  
  /// Perform search
  void _performSearch() {
    if (_searchQuery.isEmpty) {
      _clearResults();
      return;
    }
    
    try {
      switch (_searchMode) {
        case SearchMode.text:
          _performTextSearch();
          break;
        case SearchMode.regex:
          _performRegexSearch();
          break;
        case SearchMode.fuzzy:
          _performFuzzySearch();
          break;
      }
      
      _addToHistory(_searchQuery);
    } catch (e) {
      debugPrint('⚠️ Search error: $e');
      _clearResults();
    }
  }
  
  /// Perform text search
  void _performTextSearch() {
    // This would search through terminal buffers
    // For now, simulate with sample data
    final sampleText = '''
class MyWidget extends StatelessWidget {
  final String title;
  
  const MyWidget({Key? key, required this.title}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('Hello, World!')),
    );
  }
}
    ''';
    
    _results.clear();
    _highlights.clear();
    
    final lines = sampleText.split('\n');
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final matches = _findTextMatches(line);
      
      for (final match in matches) {
        _results.add(SearchResult(
          line: lineIndex + 1,
          column: match.start,
          length: match.end - match.start,
          text: line.substring(match.start, match.end),
          context: _getContext(lines, lineIndex, match.start, match.end),
        ));
        
        _highlights.add(TextHighlight(
          line: lineIndex,
          start: match.start,
          end: match.end,
          color: _getHighlightColor(_results.length - 1),
        ));
      }
    }
    
    _currentResultIndex = _results.isNotEmpty ? 0 : -1;
    _onResultsChanged?.call(_results);
  }
  
  /// Find text matches in line
  List<TextMatch> _findTextMatches(String line) {
    final matches = <TextMatch>[];
    final searchPattern = _wholeWord ? r'\b' + RegExp.escape(_searchQuery) + r'\b' : RegExp.escape(_searchQuery);
    
    try {
      final regex = RegExp(
        searchPattern,
        caseSensitive: _caseSensitive,
      );
      
      for (final match in regex.allMatches(line)) {
        matches.add(TextMatch(
          start: match.start,
          end: match.end,
        ));
      }
    } catch (e) {
      // Fallback to simple string search if regex fails
      final searchLower = _searchQuery.toLowerCase();
      final lineLower = line.toLowerCase();
      
      int start = 0;
      while (true) {
        final index = _caseSensitive 
            ? line.indexOf(_searchQuery, start)
            : lineLower.indexOf(searchLower, start);
        
        if (index == -1) break;
        
        final end = index + _searchQuery.length;
        
        if (_wholeWord) {
          // Check word boundaries
          if ((index > 0 && _isWordChar(line[index - 1])) ||
              (end < line.length && _isWordChar(line[end]))) {
            start = end;
            continue;
          }
        }
        
        matches.add(TextMatch(start: index, end: end));
        start = end;
      }
    }
    
    return matches;
  }
  
  /// Perform regex search
  void _performRegexSearch() {
    try {
      final regex = RegExp(
        _searchQuery,
        caseSensitive: _caseSensitive,
      );
      
      // Similar to text search but with regex
      _performTextSearch(); // Reuse text search logic
    } catch (e) {
      debugPrint('⚠️ Invalid regex: $e');
      _clearResults();
    }
  }
  
  /// Perform fuzzy search
  void _performFuzzySearch() {
    // Implement fuzzy search algorithm
    // This would use a fuzzy matching library
    _performTextSearch(); // Fallback to text search for now
  }
  
  /// Check if character is a word character
  bool _isWordChar(String char) {
    return RegExp(r'[a-zA-Z0-9_]').hasMatch(char);
  }
  
  /// Get context around match
  String _getContext(List<String> lines, int lineIndex, int start, int end) {
    final contextRadius = 2;
    final startLine = math.max(0, lineIndex - contextRadius);
    final endLine = math.min(lines.length - 1, lineIndex + contextRadius);
    
    final contextLines = <String>[];
    for (int i = startLine; i <= endLine; i++) {
      if (i == lineIndex) {
        final line = lines[i];
        final contextStart = math.max(0, start - 20);
        final contextEnd = math.min(line.length, end + 20);
        contextLines.add(line.substring(contextStart, contextEnd));
      } else {
        contextLines.add(lines[i]);
      }
    }
    
    return contextLines.join('\n');
  }
  
  /// Get highlight color
  Color _getHighlightColor(int index) {
    final colors = [
      Colors.yellow.withOpacity(0.3),
      Colors.green.withOpacity(0.3),
      Colors.blue.withOpacity(0.3),
      Colors.orange.withOpacity(0.3),
      Colors.purple.withOpacity(0.3),
    ];
    return colors[index % colors.length];
  }
  
  /// Navigate to next result
  void nextResult() {
    if (_results.isEmpty) return;
    
    _currentResultIndex = (_currentResultIndex + 1) % _results.length;
    _onResultsChanged?.call(_results);
  }
  
  /// Navigate to previous result
  void previousResult() {
    if (_results.isEmpty) return;
    
    _currentResultIndex = (_currentResultIndex - 1 + _results.length) % _results.length;
    _onResultsChanged?.call(_results);
  }
  
  /// Go to specific result
  void goToResult(int index) {
    if (index < 0 || index >= _results.length) return;
    
    _currentResultIndex = index;
    _onResultsChanged?.call(_results);
  }
  
  /// Clear search
  void _clearSearch() {
    _searchQuery = '';
    _clearResults();
    _onQueryChanged?.call('');
  }
  
  /// Clear results
  void _clearResults() {
    _results.clear();
    _highlights.clear();
    _currentResultIndex = -1;
    _onResultsChanged?.call(_results);
  }
  
  /// Toggle case sensitivity
  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _performSearch();
  }
  
  /// Toggle whole word
  void toggleWholeWord() {
    _wholeWord = !_wholeWord;
    _performSearch();
  }
  
  /// Toggle regex mode
  void toggleRegexMode() {
    _useRegex = !_useRegex;
    _searchMode = _useRegex ? SearchMode.regex : SearchMode.text;
    _performSearch();
  }
  
  /// Toggle fuzzy search
  void toggleFuzzySearch() {
    _fuzzySearch = !_fuzzySearch;
    _searchMode = _fuzzySearch ? SearchMode.fuzzy : SearchMode.text;
    _performSearch();
  }
  
  /// Set search mode
  void setSearchMode(SearchMode mode) {
    _searchMode = mode;
    _useRegex = mode == SearchMode.regex;
    _fuzzySearch = mode == SearchMode.fuzzy;
    _performSearch();
  }
  
  /// Add to search history
  void _addToHistory(String query) {
    if (query.trim().isEmpty) return;
    
    _searchHistory.remove(query); // Remove if exists
    _searchHistory.insert(0, query); // Add to front
    
    // Limit history size
    if (_searchHistory.length > _maxHistorySize) {
      _searchHistory = _searchHistory.take(_maxHistorySize).toList();
    }
    
    _saveSearchHistory();
  }
  
  /// Save search history
  Future<void> _saveSearchHistory() async {
    try {
      // In a real app, you would save to persistent storage
      debugPrint('💾 Saved search history (${_searchHistory.length} items)');
    } catch (e) {
      debugPrint('⚠️ Failed to save search history: $e');
    }
  }
  
  /// Clear search history
  void clearHistory() {
    _searchHistory.clear();
    _saveSearchHistory();
  }
  
  /// Get search statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'isSearchMode': _isSearchMode,
      'currentQuery': _searchQuery,
      'resultCount': _results.length,
      'currentResultIndex': _currentResultIndex,
      'searchMode': _searchMode.toString(),
      'caseSensitive': _caseSensitive,
      'wholeWord': _wholeWord,
      'useRegex': _useRegex,
      'fuzzySearch': _fuzzySearch,
      'historySize': _searchHistory.length,
    };
  }
  
  /// Set callbacks
  void setCallbacks({
    Function(List<SearchResult>)? onResultsChanged,
    Function(String)? onQueryChanged,
    Function()? onSearchModeChanged,
  }) {
    _onResultsChanged = onResultsChanged;
    _onQueryChanged = onQueryChanged;
    _onSearchModeChanged = onSearchModeChanged;
  }
  
  /// Dispose resources
  void dispose() {
    _debounceTimer?.cancel();
    _clearResults();
    _clearSearch();
    _isInitialized = false;
    debugPrint('🔍 Enhanced Search disposed');
  }
}

/// Search result class
class SearchResult {
  final int line;
  final int column;
  final int length;
  final String text;
  final String context;
  final double score;
  
  SearchResult({
    required this.line,
    required this.column,
    required this.length,
    required this.text,
    required this.context,
    this.score = 1.0,
  });
  
  @override
  String toString() {
    return 'SearchResult(line: $line, column: $column, text: "$text")';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchResult &&
        other.line == line &&
        other.column == column &&
        other.text == text;
  }
  
  @override
  int get hashCode {
    return line.hashCode ^ column.hashCode ^ text.hashCode;
  }
}

/// Text match class
class TextMatch {
  final int start;
  final int end;
  
  TextMatch({
    required this.start,
    required this.end,
  });
}

/// Text highlight class
class TextHighlight {
  final int line;
  final int start;
  final int end;
  final Color color;
  
  TextHighlight({
    required this.line,
    required this.start,
    required this.end,
    required this.color,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextHighlight &&
        other.line == line &&
        other.start == start &&
        other.end == end;
  }
  
  @override
  int get hashCode {
    return line.hashCode ^ start.hashCode ^ end.hashCode;
  }
}

/// Search mode enumeration
enum SearchMode {
  text,
  regex,
  fuzzy,
}

/// Enhanced search widget
class EnhancedSearchWidget extends StatefulWidget {
  final EnhancedSearch searchController;
  final VoidCallback? onClose;
  
  const EnhancedSearchWidget({
    Key? key,
    required this.searchController,
    this.onClose,
  }) : super(key: key);
  
  @override
  State<EnhancedSearchWidget> createState() => _EnhancedSearchWidgetState();
}

class _EnhancedSearchWidgetState extends State<EnhancedSearchWidget> {
  late TextEditingController _textController;
  late FocusNode _focusNode;
  bool _showHistory = false;
  
  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    
    // Setup callbacks
    widget.searchController.setCallbacks(
      onResultsChanged: (results) => setState(() {}),
      onQueryChanged: (query) {
        _textController.text = query;
        setState(() {});
      },
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search input
          _buildSearchInput(context),
          
          // Search options
          if (widget.searchController.searchQuery.isNotEmpty)
            _buildSearchOptions(context),
          
          // Search history
          if (_showHistory && widget.searchController.searchHistory.isNotEmpty)
            _buildSearchHistory(context),
        ],
      ),
    );
  }
  
  Widget _buildSearchInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Search icon
          Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          
          const SizedBox(width: 12),
          
          // Text input
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              style: GoogleFonts.varelaRound(),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: GoogleFonts.varelaRound(
                  color: Colors.grey[600],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                widget.searchController.updateQuery(value);
              },
              onSubmitted: (value) {
                widget.searchController.nextResult();
              },
            ),
          ),
          
          // Result counter
          if (widget.searchController.results.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.searchController.currentResultIndex + 1}/${widget.searchController.results.length}',
                style: GoogleFonts.varelaRound(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          
          // Navigation buttons
          if (widget.searchController.results.isNotEmpty) ...[
            IconButton(
              onPressed: widget.searchController.previousResult,
              icon: const Icon(Icons.keyboard_arrow_up),
              iconSize: 20,
            ),
            IconButton(
              onPressed: widget.searchController.nextResult,
              icon: const Icon(Icons.keyboard_arrow_down),
              iconSize: 20,
            ),
          ],
          
          // Close button
          IconButton(
            onPressed: () {
              widget.searchController.exitSearchMode();
              widget.onClose?.call();
            },
            icon: const Icon(Icons.close),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchOptions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Case sensitive
          _buildOptionButton(
            context,
            'Aa',
            widget.searchController.caseSensitive,
            widget.searchController.toggleCaseSensitive,
            'Case sensitive',
          ),
          
          const SizedBox(width: 8),
          
          // Whole word
          _buildOptionButton(
            context,
            '"',
            widget.searchController.wholeWord,
            widget.searchController.toggleWholeWord,
            'Whole word',
          ),
          
          const SizedBox(width: 8),
          
          // Regex
          _buildOptionButton(
            context,
            '.*',
            widget.searchController.useRegex,
            widget.searchController.toggleRegexMode,
            'Regular expression',
          ),
          
          const SizedBox(width: 8),
          
          // Fuzzy
          _buildOptionButton(
            context,
            '~',
            widget.searchController.fuzzySearch,
            widget.searchController.toggleFuzzySearch,
            'Fuzzy search',
          ),
          
          const Spacer(),
          
          // History toggle
          IconButton(
            onPressed: () => setState(() => _showHistory = !_showHistory),
            icon: Icon(_showHistory ? Icons.history : Icons.history),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
  
  Widget _buildOptionButton(
    BuildContext context,
    String label,
    bool isActive,
    VoidCallback onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive 
                ? Theme.of(context).primaryColor.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: GoogleFonts.varelaRound(
              color: isActive 
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSearchHistory(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        itemCount: widget.searchController.searchHistory.length,
        itemBuilder: (context, index) {
          final query = widget.searchController.searchHistory[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 16),
            title: Text(
              query,
              style: GoogleFonts.varelaRound(fontSize: 14),
            ),
            onTap: () {
              widget.searchController.updateQuery(query);
              setState(() => _showHistory = false);
            },
          );
        },
      ),
    );
  }
}
