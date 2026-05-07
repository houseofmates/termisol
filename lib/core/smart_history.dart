import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Smart shell history with semantic search capabilities
/// Uses embeddings and pattern matching for intelligent command retrieval
class SmartHistory {
  static const String _historyFile = '.termisol_smart_history';
  static const String _embeddingsFile = '.termisol_history_embeddings';
  
  final List<HistoryEntry> _history = [];
  final Map<String, List<double>> _embeddings = {};
  final Map<String, int> _commandFrequency = {};
  
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadHistory();
      await _loadEmbeddings();
      _isInitialized = true;
      debugPrint('🧠 Smart History initialized with ${_history.length} entries');
    } catch (e) {
      debugPrint('❌ Failed to initialize Smart History: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final file = File(_historyFile);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as List;
        
        _history.clear();
        _commandFrequency.clear();
        
        for (final item in data) {
          final entry = HistoryEntry.fromJson(item as Map<String, dynamic>);
          _history.add(entry);
          _commandFrequency[entry.command] = (_commandFrequency[entry.command] ?? 0) + 1;
        }
        
        // Sort by timestamp
        _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
  }

  Future<void> _loadEmbeddings() async {
    try {
      final file = File(_embeddingsFile);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _embeddings.clear();
        for (final entry in data.entries) {
          if (entry.value is List) {
            _embeddings[entry.key] = List<double>.from(entry.value);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load embeddings: $e');
    }
  }

  Future<void> addCommand(String command, {String? workingDirectory, int? exitCode}) async {
    if (!_isInitialized) await initialize();
    
    final entry = HistoryEntry(
      command: command,
      timestamp: DateTime.now(),
      workingDirectory: workingDirectory ?? Directory.current.path,
      exitCode: exitCode,
    );
    
    _history.insert(0, entry);
    _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
    
    // Generate embedding for semantic search
    final embedding = await _generateEmbedding(command);
    if (embedding != null) {
      _embeddings[command] = embedding;
    }
    
    // Keep history manageable (last 50000 entries)
    if (_history.length > 50000) {
      _history.removeRange(50000, _history.length);
    }
    
    // Debounce saving
    _scheduleSave();
  }

  List<double>? _generateEmbedding(String text) {
    // Simplified embedding generation (in production, use actual ML model)
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final embedding = List<double>.filled(128, 0.0);
    
    // Simple word-based embedding
    for (int i = 0; i < words.length && i < 128; i++) {
      embedding[i] = words[i].hashCode % 1000 / 1000.0;
    }
    
    return embedding;
  }

  double _calculateSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    normA = math.sqrt(normA);
    normB = math.sqrt(normB);
    
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (normA * normB);
  }

  Future<List<HistoryEntry>> search(String query, {int limit = 20}) async {
    if (!_isInitialized) await initialize();
    
    if (query.trim().isEmpty) {
      return _history.take(limit).toList();
    }
    
    final queryEmbedding = _generateEmbedding(query);
    if (queryEmbedding == null) {
      return _fuzzySearch(query, limit: limit);
    }
    
    final scoredEntries = <HistoryEntry, double>{};
    
    // Semantic similarity search
    for (final entry in _history) {
      final entryEmbedding = _embeddings[entry.command];
      if (entryEmbedding != null) {
        final similarity = _calculateSimilarity(queryEmbedding, entryEmbedding);
        scoredEntries[entry] = similarity;
      }
    }
    
    // Sort by similarity score
    final sortedEntries = scoredEntries.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEntries
        .take(limit)
        .map((e) => e.key)
        .toList();
  }

  List<HistoryEntry> _fuzzySearch(String query, {int limit = 20}) {
    final queryLower = query.toLowerCase();
    final scoredEntries = <HistoryEntry, double>{};
    
    for (final entry in _history) {
      final commandLower = entry.command.toLowerCase();
      double score = 0.0;
      
      // Exact match bonus
      if (commandLower.contains(queryLower)) {
        score += 1.0;
      }
      
      // Word matching
      final queryWords = queryLower.split(RegExp(r'\s+'));
      final commandWords = commandLower.split(RegExp(r'\s+'));
      
      int matchingWords = 0;
      for (final queryWord in queryWords) {
        for (final commandWord in commandWords) {
          if (commandWord.contains(queryWord)) {
            matchingWords++;
            break;
          }
        }
      }
      
      if (matchingWords > 0) {
        score += matchingWords / queryWords.length;
      }
      
      // Frequency bonus
      final frequency = _commandFrequency[entry.command] ?? 0;
      score += math.log(frequency + 1) / 10.0;
      
      // Recency bonus
      final daysSince = DateTime.now().difference(entry.timestamp).inDays;
      score += math.max(0, (30 - daysSince) / 30.0);
      
      if (score > 0) {
        scoredEntries[entry] = score;
      }
    }
    
    final sortedEntries = scoredEntries.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEntries
        .take(limit)
        .map((e) => e.key)
        .toList();
  }

  Future<List<HistoryEntry>> getCommandsByPattern(String pattern, {int limit = 20}) async {
    if (!_isInitialized) await initialize();
    
    final regex = RegExp(pattern, caseSensitive: false);
    final matches = <HistoryEntry>[];
    
    for (final entry in _history) {
      if (regex.hasMatch(entry.command)) {
        matches.add(entry);
        if (matches.length >= limit) break;
      }
    }
    
    return matches;
  }

  Future<List<HistoryEntry>> getCommandsByDateRange(DateTime start, DateTime end) async {
    if (!_isInitialized) await initialize();
    
    return _history.where((entry) {
      return entry.timestamp.isAfter(start) && entry.timestamp.isBefore(end);
    }).toList();
  }

  Future<List<HistoryEntry>> getMostUsedCommands({int limit = 10}) async {
    if (!_isInitialized) await initialize();
    
    final commandGroups = <String, List<HistoryEntry>>{};
    
    for (final entry in _history) {
      if (!commandGroups.containsKey(entry.command)) {
        commandGroups[entry.command] = [];
      }
      commandGroups[entry.command]!.add(entry);
    }
    
    final sortedCommands = commandGroups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    
    return sortedCommands
        .take(limit)
        .map((e) => e.value.first)
        .toList();
  }

  Future<Map<String, dynamic>> getStatistics() async {
    if (!_isInitialized) await initialize();
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = now.subtract(const Duration(days: 7));
    final thisMonth = DateTime(now.year, now.month, 1);
    
    final todayCommands = _history.where((e) => e.timestamp.isAfter(today)).length;
    final weekCommands = _history.where((e) => e.timestamp.isAfter(thisWeek)).length;
    final monthCommands = _history.where((e) => e.timestamp.isAfter(thisMonth)).length;
    
    final uniqueCommands = _commandFrequency.keys.length;
    final totalCommands = _history.length;
    
    final averageCommandsPerDay = totalCommands / math.max(1, now.difference(_history.last.timestamp).inDays);
    
    return {
      'totalCommands': totalCommands,
      'uniqueCommands': uniqueCommands,
      'todayCommands': todayCommands,
      'weekCommands': weekCommands,
      'monthCommands': monthCommands,
      'averageCommandsPerDay': averageCommandsPerDay.toStringAsFixed(1),
      'mostUsedCommands': _commandFrequency.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value))
          .take(10)
          .map((e) => {'command': e.key, 'count': e.value})
          .toList(),
    };
  }

  Timer? _saveTimer;
  
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      _saveHistory();
      _saveEmbeddings();
    });
  }

  Future<void> _saveHistory() async {
    try {
      final file = File(_historyFile);
      final data = _history.map((e) => e.toJson()).toList();
      final content = jsonEncode(data);
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save history: $e');
    }
  }

  Future<void> _saveEmbeddings() async {
    try {
      final file = File(_embeddingsFile);
      final content = jsonEncode(_embeddings);
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save embeddings: $e');
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    _embeddings.clear();
    _commandFrequency.clear();
    
    try {
      await File(_historyFile).delete();
      await File(_embeddingsFile).delete();
    } catch (e) {
      debugPrint('Failed to clear history: $e');
    }
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _saveHistory();
    await _saveEmbeddings();
    debugPrint('🧠 Smart History disposed');
  }
}

class HistoryEntry {
  final String command;
  final DateTime timestamp;
  final String workingDirectory;
  final int? exitCode;

  HistoryEntry({
    required this.command,
    required this.timestamp,
    required this.workingDirectory,
    this.exitCode,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      command: json['command'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      workingDirectory: json['workingDirectory'] as String? ?? '',
      exitCode: json['exitCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'timestamp': timestamp.toIso8601String(),
      'workingDirectory': workingDirectory,
      'exitCode': exitCode,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryEntry &&
        other.command == command &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(command, timestamp);
}

/// History search widget
class HistorySearchWidget extends StatefulWidget {
  final Function(HistoryEntry) onSelected;
  final VoidCallback? onDismiss;

  const HistorySearchWidget({
    super.key,
    required this.onSelected,
    this.onDismiss,
  });

  @override
  State<HistorySearchWidget> createState() => _HistorySearchWidgetState();
}

class _HistorySearchWidgetState extends State<HistorySearchWidget> {
  final SmartHistory _history = SmartHistory();
  final TextEditingController _searchController = TextEditingController();
  
  List<HistoryEntry> _results = [];
  bool _isLoading = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _results.clear();
        _isLoading = false;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final results = await _history.search(_searchController.text);
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _results.clear();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey700)),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey[400], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search command history...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    autofocus: true,
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  ),
              ],
            ),
          ),
          
          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No commands found',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final entry = _results[index];
                          return HistoryEntryWidget(
                            entry: entry,
                            onTap: () => widget.onSelected(entry),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class HistoryEntryWidget extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;

  const HistoryEntryWidget({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey700)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.command,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 12,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                if (entry.exitCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.exitCode == 0 ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      entry.exitCode.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inSeconds}s ago';
    }
  }
}
