import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Clipboard History Management System
/// 
/// Comprehensive clipboard history with:
/// - Automatic clipboard monitoring
/// - Item categorization and search
/// - Persistent storage
/// - Privacy controls
/// - Item pinning and favorites
/// - Duplicate detection
/// - Size limits and cleanup
class ClipboardHistory {
  static final ClipboardHistory _instance = ClipboardHistory._internal();
  factory ClipboardHistory() => _instance;
  ClipboardHistory._internal();

  bool _isInitialized = false;
  
  // Clipboard storage
  final List<ClipboardItem> _history = [];
  final List<ClipboardItem> _pinned = [];
  final Map<String, int> _duplicateCounts = {};
  
  // Monitoring
  Timer? _monitoringTimer;
  String? _lastClipboardContent;
  bool _monitoringEnabled = true;
  Duration _monitoringInterval = Duration(milliseconds: 500);
  
  // Configuration
  Directory? _storageDir;
  int _maxHistorySize = 1000;
  int _maxItemSize = 1024 * 1024; // 1MB
  int _maxPinnedItems = 50;
  bool _enableEncryption = false;
  
  // Event system
  final _clipboardController = StreamController<ClipboardEvent>.broadcast();
  Stream<ClipboardEvent> get events => _clipboardController.stream;
  
  // Privacy
  final Set<String> _sensitivePatterns = {
    'password',
    'token',
    'key',
    'secret',
    'credential',
    'api_key',
    'private_key',
  };
  
  bool get isInitialized => _isInitialized;
  bool get monitoringEnabled => _monitoringEnabled;
  int get historySize => _history.length;
  int get pinnedCount => _pinned.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup storage
      await _setupStorage();
      
      // Load configuration
      await _loadConfiguration();
      
      // Load existing history
      await _loadHistory();
      
      // Start monitoring
      if (_monitoringEnabled) {
        _startMonitoring();
      }
      
      _isInitialized = true;
      debugPrint('📋 Clipboard History initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Clipboard History: $e');
    }
  }

  Future<void> _setupStorage() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      _storageDir = Directory('$homeDir/.termisol/clipboard');
      await _storageDir!.create(recursive: true);
      
      debugPrint('📁 Clipboard storage directory created');
    } catch (e) {
      debugPrint('❌ Failed to setup storage: $e');
      rethrow;
    }
  }

  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${_storageDir!.path}/config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _maxHistorySize = data['max_history_size'] ?? 1000;
        _maxItemSize = data['max_item_size'] ?? 1024 * 1024;
        _maxPinnedItems = data['max_pinned_items'] ?? 50;
        _enableEncryption = data['enable_encryption'] ?? false;
        _monitoringEnabled = data['monitoring_enabled'] ?? true;
        _monitoringInterval = Duration(milliseconds: data['monitoring_interval_ms'] ?? 500);
      }
      
      debugPrint('📋 Configuration loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load configuration: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final historyFile = File('${_storageDir!.path}/history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['history'] as List)) {
          final item = ClipboardItem.fromJson(entry);
          _history.add(item);
        }
        
        // Sort by timestamp (newest first)
        _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // Limit history size
        if (_history.length > _maxHistorySize) {
          _history.removeRange(_maxHistorySize, _history.length);
        }
      }
      
      // Load pinned items
      final pinnedFile = File('${_storageDir!.path}/pinned.json');
      if (await pinnedFile.exists()) {
        final content = await pinnedFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['pinned'] as List)) {
          final item = ClipboardItem.fromJson(entry);
          _pinned.add(item);
        }
        
        // Limit pinned items
        if (_pinned.length > _maxPinnedItems) {
          _pinned.removeRange(_maxPinnedItems, _pinned.length);
        }
      }
      
      debugPrint('📋 Loaded ${_history.length} history items and ${_pinned.length} pinned items');
    } catch (e) {
      debugPrint('⚠️ Failed to load history: $e');
    }
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _checkClipboard();
    });
    
    debugPrint('📋 Started clipboard monitoring');
  }

  Future<void> _checkClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final currentContent = clipboardData?.text;
      
      if (currentContent == null || currentContent.isEmpty) {
        return;
      }
      
      // Check if content changed
      if (currentContent == _lastClipboardContent) {
        return;
      }
      
      // Check size limit
      if (currentContent.length > _maxItemSize) {
        debugPrint('⚠️ Clipboard content too large, skipping');
        return;
      }
      
      // Check for sensitive content
      if (_isSensitiveContent(currentContent)) {
        debugPrint('🔒 Sensitive content detected, not saving to history');
        return;
      }
      
      // Create clipboard item
      final item = ClipboardItem(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        content: currentContent,
        timestamp: DateTime.now(),
        type: _detectContentType(currentContent),
        size: currentContent.length,
        application: _detectApplication(),
        pinned: false,
      );
      
      // Check for duplicates
      final duplicateId = _findDuplicate(item);
      if (duplicateId != null) {
        _duplicateCounts[duplicateId] = (_duplicateCounts[duplicateId] ?? 0) + 1;
        debugPrint('📋 Duplicate detected: ${item.content.substring(0, 20)}...');
        return;
      }
      
      // Add to history
      _history.insert(0, item);
      _lastClipboardContent = currentContent;
      
      // Limit history size
      if (_history.length > _maxHistorySize) {
        final removed = _history.removeLast();
        _duplicateCounts.remove(removed.id);
      }
      
      // Save to disk
      await _saveHistory();
      
      // Emit event
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.itemAdded,
        itemId: item.id,
        data: item.toJson(),
      ));
      
      debugPrint('📋 Added to history: ${item.content.substring(0, 20)}...');
      
    } catch (e) {
      debugPrint('⚠️ Failed to check clipboard: $e');
    }
  }

  bool _isSensitiveContent(String content) {
    final lowerContent = content.toLowerCase();
    
    for (final pattern in _sensitivePatterns) {
      if (lowerContent.contains(pattern)) {
        return true;
      }
    }
    
    // Check for password-like patterns
    if (RegExp(r'password\s*[:=]\s*\S+').hasMatch(lowerContent)) {
      return true;
    }
    
    // Check for API key patterns
    if (RegExp(r'[a-zA-Z0-9]{20,}').hasMatch(content) && 
        (content.contains('key') || content.contains('token'))) {
      return true;
    }
    
    return false;
  }

  ClipboardType _detectContentType(String content) {
    // Check for URLs
    if (RegExp(r'https?://[^\s]+').hasMatch(content)) {
      return ClipboardType.url;
    }
    
    // Check for file paths
    if (RegExp(r'^[/\\]|^[a-zA-Z]:[/\\]').hasMatch(content)) {
      return ClipboardType.filePath;
    }
    
    // Check for email addresses
    if (RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(content)) {
      return ClipboardType.email;
    }
    
    // Check for JSON
    if (content.trim().startsWith('{') && content.trim().endsWith('}')) {
      try {
        jsonDecode(content);
        return ClipboardType.json;
      } catch (e) {
        debugPrint('Failed to parse JSON clipboard: $e');
      }
    }
    
    // Check for code
    if (RegExp(r'(function|class|def|import|export|var|let|const)').hasMatch(content)) {
      return ClipboardType.code;
    }
    
    // Check for multi-line content
    if (content.contains('\n') && content.split('\n').length > 3) {
      return ClipboardType.multiline;
    }
    
    return ClipboardType.text;
  }

  String _detectApplication() {
    // In a real implementation, this would detect the active application
    // For now, return empty string as fallback
    return 'unknown';
  }

  String? _findDuplicate(ClipboardItem newItem) {
    for (final item in _history) {
      if (item.content == newItem.content) {
        return item.id;
      }
    }
    return null;
  }

  // Public API methods
  
  List<ClipboardItem> getHistory({int limit = 50}) {
    return _history.take(limit).toList();
  }

  List<ClipboardItem> getPinnedItems() {
    return List.unmodifiable(_pinned);
  }

  List<ClipboardItem> search(String query, {ClipboardType? type}) {
    final lowerQuery = query.toLowerCase();
    final results = <ClipboardItem>[];
    
    // Search in history
    for (final item in _history) {
      if (type != null && item.type != type) continue;
      
      if (item.content.toLowerCase().contains(lowerQuery)) {
        results.add(item);
      }
    }
    
    // Search in pinned items
    for (final item in _pinned) {
      if (type != null && item.type != type) continue;
      
      if (item.content.toLowerCase().contains(lowerQuery)) {
        results.add(item);
      }
    }
    
    // Sort by timestamp (newest first)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return results;
  }

  Future<bool> copyToClipboard(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      _lastClipboardContent = content;
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.manualCopy,
        data: {'content_length': content.length},
      ));
      
      debugPrint('📋 Copied to clipboard: ${content.substring(0, 20)}...');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to copy to clipboard: $e');
      return false;
    }
  }

  Future<String?> copyFromHistory(String itemId) async {
    try {
      // Find item in history
      ClipboardItem? item = _history.firstWhere((i) => i.id == itemId);
      
      // Check pinned items if not found
      if (item == null) {
        item = _pinned.firstWhere((i) => i.id == itemId);
      }
      
      if (item == null) {
        throw ArgumentError('Item not found: $itemId');
      }
      
      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: item.content));
      _lastClipboardContent = item.content;
      
      // Update access time
      item.lastAccessed = DateTime.now();
      await _saveHistory();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.itemCopied,
        itemId: itemId,
        data: item.toJson(),
      ));
      
      debugPrint('📋 Copied from history: ${item.content.substring(0, 20)}...');
      return item.content;
    } catch (e) {
      debugPrint('❌ Failed to copy from history: $e');
      return null;
    }
  }

  Future<bool> pinItem(String itemId) async {
    try {
      // Find and remove from history
      ClipboardItem? item;
      int index = _history.indexWhere((i) => i.id == itemId);
      
      if (index != -1) {
        item = _history.removeAt(index);
      } else {
        // Check pinned items
        index = _pinned.indexWhere((i) => i.id == itemId);
        if (index != -1) {
          item = _pinned.removeAt(index);
        }
      }
      
      if (item == null) {
        throw ArgumentError('Item not found: $itemId');
      }
      
      // Pin the item
      item.pinned = true;
      item.pinnedAt = DateTime.now();
      _pinned.insert(0, item);
      
      // Limit pinned items
      if (_pinned.length > _maxPinnedItems) {
        final unpinned = _pinned.removeLast();
        unpinned.pinned = false;
        unpinned.pinnedAt = null;
        _history.insert(0, unpinned);
      }
      
      await _saveHistory();
      await _savePinned();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.itemPinned,
        itemId: itemId,
        data: item.toJson(),
      ));
      
      debugPrint('📋 Pinned item: ${item.content.substring(0, 20)}...');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to pin item: $e');
      return false;
    }
  }

  Future<bool> unpinItem(String itemId) async {
    try {
      final index = _pinned.indexWhere((i) => i.id == itemId);
      if (index == -1) {
        throw ArgumentError('Pinned item not found: $itemId');
      }
      
      final item = _pinned.removeAt(index);
      item.pinned = false;
      item.pinnedAt = null;
      
      // Add back to history
      _history.insert(0, item);
      
      await _saveHistory();
      await _savePinned();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.itemUnpinned,
        itemId: itemId,
        data: item.toJson(),
      ));
      
      debugPrint('📋 Unpinned item: ${item.content.substring(0, 20)}...');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to unpin item: $e');
      return false;
    }
  }

  Future<bool> deleteItem(String itemId) async {
    try {
      // Remove from history
      final historyIndex = _history.indexWhere((i) => i.id == itemId);
      if (historyIndex != -1) {
        _history.removeAt(historyIndex);
      }
      
      // Remove from pinned
      final pinnedIndex = _pinned.indexWhere((i) => i.id == itemId);
      if (pinnedIndex != -1) {
        _pinned.removeAt(pinnedIndex);
      }
      
      if (historyIndex == -1 && pinnedIndex == -1) {
        throw ArgumentError('Item not found: $itemId');
      }
      
      await _saveHistory();
      await _savePinned();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.itemDeleted,
        itemId: itemId,
      ));
      
      debugPrint('📋 Deleted item: $itemId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to delete item: $e');
      return false;
    }
  }

  Future<bool> clearHistory() async {
    try {
      _history.clear();
      _duplicateCounts.clear();
      
      await _saveHistory();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.historyCleared,
      ));
      
      debugPrint('📋 Cleared clipboard history');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to clear history: $e');
      return false;
    }
  }

  Future<bool> clearPinned() async {
    try {
      _pinned.clear();
      
      await _savePinned();
      
      _clipboardController.add(ClipboardEvent(
        type: ClipboardEventType.pinnedCleared,
      ));
      
      debugPrint('📋 Cleared pinned items');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to clear pinned items: $e');
      return false;
    }
  }

  void setMonitoringEnabled(bool enabled) {
    _monitoringEnabled = enabled;
    
    if (enabled && _monitoringTimer == null) {
      _startMonitoring();
    } else if (!enabled && _monitoringTimer != null) {
      _monitoringTimer?.cancel();
      _monitoringTimer = null;
    }
    
    debugPrint('📋 Monitoring ${enabled ? 'enabled' : 'disabled'}');
  }

  void setMonitoringInterval(Duration interval) {
    _monitoringInterval = interval;
    
    if (_monitoringTimer != null) {
      _monitoringTimer?.cancel();
      _startMonitoring();
    }
    
    debugPrint('📋 Monitoring interval set to ${interval.inMilliseconds}ms');
  }

  void setMaxHistorySize(int size) {
    _maxHistorySize = size;
    
    // Trim history if needed
    if (_history.length > _maxHistorySize) {
      _history.removeRange(_maxHistorySize, _history.length);
      _saveHistory();
    }
    
    debugPrint('📋 Max history size set to $size');
  }

  Future<void> _saveHistory() async {
    try {
      final historyFile = File('${_storageDir!.path}/history.json');
      
      final data = {
        'history': _history.map((item) => item.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save history: $e');
    }
  }

  Future<void> _savePinned() async {
    try {
      final pinnedFile = File('${_storageDir!.path}/pinned.json');
      
      final data = {
        'pinned': _pinned.map((item) => item.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await pinnedFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save pinned items: $e');
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final configFile = File('${_storageDir!.path}/config.json');
      
      final data = {
        'max_history_size': _maxHistorySize,
        'max_item_size': _maxItemSize,
        'max_pinned_items': _maxPinnedItems,
        'enable_encryption': _enableEncryption,
        'monitoring_enabled': _monitoringEnabled,
        'monitoring_interval_ms': _monitoringInterval.inMilliseconds,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await configFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save configuration: $e');
    }
  }

  ClipboardStatistics getStatistics() {
    final typeDistribution = <ClipboardType, int>{};
    final sizeDistribution = <String, int>{};
    
    for (final item in _history) {
      typeDistribution[item.type] = (typeDistribution[item.type] ?? 0) + 1;
      
      final sizeCategory = _getSizeCategory(item.size);
      sizeDistribution[sizeCategory] = (sizeDistribution[sizeCategory] ?? 0) + 1;
    }
    
    return ClipboardStatistics(
      historySize: _history.length,
      pinnedCount: _pinned.length,
      monitoringEnabled: _monitoringEnabled,
      maxHistorySize: _maxHistorySize,
      maxPinnedItems: _maxPinnedItems,
      typeDistribution: typeDistribution,
      sizeDistribution: sizeDistribution,
      totalDuplicates: _duplicateCounts.values.fold(0, (sum, count) => sum + count),
      oldestItem: _history.isNotEmpty ? _history.last.timestamp : null,
      newestItem: _history.isNotEmpty ? _history.first.timestamp : null,
    );
  }

  String _getSizeCategory(int size) {
    if (size < 100) return 'small';
    if (size < 1000) return 'medium';
    if (size < 10000) return 'large';
    return 'huge';
  }

  Future<void> dispose() async {
    // Save current state
    await _saveHistory();
    await _savePinned();
    await _saveConfiguration();
    
    // Stop monitoring
    _monitoringTimer?.cancel();
    
    // Clear data
    _history.clear();
    _pinned.clear();
    _duplicateCounts.clear();
    
    // Close event controller
    _clipboardController.close();
    
    _isInitialized = false;
    debugPrint('📋 Clipboard History disposed');
  }
}

/// Data classes
class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final ClipboardType type;
  final int size;
  final String application;
  bool pinned;
  DateTime? pinnedAt;
  DateTime? lastAccessed;
  
  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.type,
    required this.size,
    required this.application,
    required this.pinned,
    this.pinnedAt,
    this.lastAccessed,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'size': size,
      'application': application,
      'pinned': pinned,
      'pinned_at': pinnedAt?.toIso8601String(),
      'last_accessed': lastAccessed?.toIso8601String(),
    };
  }
  
  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      type: ClipboardType.values.firstWhere((t) => t.toString() == json['type']),
      size: json['size'],
      application: json['application'],
      pinned: json['pinned'] ?? false,
      pinnedAt: json['pinned_at'] != null ? DateTime.parse(json['pinned_at']) : null,
      lastAccessed: json['last_accessed'] != null ? DateTime.parse(json['last_accessed']) : null,
    );
  }
}

class ClipboardEvent {
  final ClipboardEventType type;
  final String? itemId;
  final Map<String, dynamic>? data;
  
  ClipboardEvent({
    required this.type,
    this.itemId,
    this.data,
  });
}

class ClipboardStatistics {
  final int historySize;
  final int pinnedCount;
  final bool monitoringEnabled;
  final int maxHistorySize;
  final int maxPinnedItems;
  final Map<ClipboardType, int> typeDistribution;
  final Map<String, int> sizeDistribution;
  final int totalDuplicates;
  final DateTime? oldestItem;
  final DateTime? newestItem;
  
  ClipboardStatistics({
    required this.historySize,
    required this.pinnedCount,
    required this.monitoringEnabled,
    required this.maxHistorySize,
    required this.maxPinnedItems,
    required this.typeDistribution,
    required this.sizeDistribution,
    required this.totalDuplicates,
    this.oldestItem,
    this.newestItem,
  });
}

enum ClipboardType {
  text,
  url,
  filePath,
  email,
  json,
  code,
  multiline,
}

enum ClipboardEventType {
  itemAdded,
  itemCopied,
  itemPinned,
  itemUnpinned,
  itemDeleted,
  historyCleared,
  pinnedCleared,
  manualCopy,
}
