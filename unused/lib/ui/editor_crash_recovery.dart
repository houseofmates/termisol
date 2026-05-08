import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

/// Automatic crash recovery and backup system for the editor
class EditorCrashRecovery {
  static const String _backupDir = '.termisol_backups';
  static const String _recoveryKey = 'editor_recovery_data';
  static const Duration _backupInterval = Duration(minutes: 2);
  static const int _maxBackups = 10;
  
  Timer? _backupTimer;
  String? _currentFilePath;
  String? _currentContent;
  DateTime? _lastSave;
  final Map<String, DateTime> _fileTimestamps = {};
  
  /// Initialize crash recovery for a file
  Future<void> initialize(String filePath) async {
    try {
      _currentFilePath = filePath;
      await _ensureBackupDirectory();
      
      // Check for existing recovery data
      await _checkForRecoveryData();
      
      // Start periodic backups
      _startPeriodicBackup();
      
      debugPrint('🛡️ Editor crash recovery initialized for: $filePath');
    } catch (e) {
      debugPrint('❌ Failed to initialize crash recovery: $e');
    }
  }
  
  /// Update current content (called on editor changes)
  void updateContent(String content) {
    _currentContent = content;
    _lastSave = DateTime.now();
  }
  
  /// Create an immediate backup
  Future<void> createBackup({String? reason}) async {
    if (_currentFilePath == null || _currentContent == null) return;
    
    try {
      final backup = EditorBackup(
        filePath: _currentFilePath!,
        content: _currentContent!,
        timestamp: DateTime.now(),
        reason: reason ?? 'manual',
      );
      
      await _saveBackup(backup);
      await _cleanupOldBackups();
      
      debugPrint('💾 Editor backup created: ${backup.reason}');
    } catch (e) {
      debugPrint('❌ Failed to create backup: $e');
    }
  }
  
  /// Restore from backup
  Future<String?> restoreFromBackup(String backupId) async {
    try {
      final backupFile = File(path.join(_backupDir, backupId));
      if (!await backupFile.exists()) return null;
      
      final content = await backupFile.readAsString();
      final backup = EditorBackup.fromJson(jsonDecode(content));
      
      _currentContent = backup.content;
      _lastSave = DateTime.now();
      
      debugPrint('🔄 Restored from backup: ${backup.reason}');
      return backup.content;
    } catch (e) {
      debugPrint('❌ Failed to restore from backup: $e');
      return null;
    }
  }
  
  /// Get list of available backups
  Future<List<EditorBackup>> getAvailableBackups() async {
    try {
      final backupDir = Directory(_backupDir);
      if (!await backupDir.exists()) return [];
      
      final backups = <EditorBackup>[];
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final backup = EditorBackup.fromJson(jsonDecode(content));
            backups.add(backup);
          } catch (e) {
            debugPrint('⚠️ Failed to parse backup file ${entity.path}: $e');
          }
        }
      }
      
      // Sort by timestamp (newest first)
      backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return backups;
    } catch (e) {
      debugPrint('❌ Failed to get available backups: $e');
      return [];
    }
  }
  
  /// Check for recovery data on app start
  Future<void> _checkForRecoveryData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recoveryData = prefs.getString(_recoveryKey);
      
      if (recoveryData != null) {
        final data = jsonDecode(recoveryData) as Map<String, dynamic>;
        final filePath = data['filePath'] as String;
        final content = data['content'] as String;
        final timestamp = DateTime.parse(data['timestamp'] as String);
        
        // Check if file was modified externally
        if (await _wasFileModifiedExternally(filePath, timestamp)) {
          debugPrint('⚠️ File was modified externally, skipping recovery');
          await prefs.remove(_recoveryKey);
          return;
        }
        
        // Offer recovery
        _currentContent = content;
        _lastSave = timestamp;
        
        debugPrint('🔄 Recovery data found for: $filePath');
      }
    } catch (e) {
      debugPrint('❌ Failed to check recovery data: $e');
    }
  }
  
  /// Save recovery data
  Future<void> _saveRecoveryData() async {
    if (_currentFilePath == null || _currentContent == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final recoveryData = {
        'filePath': _currentFilePath,
        'content': _currentContent,
        'timestamp': _lastSave?.toIso8601String(),
      };
      
      await prefs.setString(_recoveryKey, jsonEncode(recoveryData));
    } catch (e) {
      debugPrint('❌ Failed to save recovery data: $e');
    }
  }
  
  /// Clear recovery data
  Future<void> clearRecoveryData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recoveryKey);
      debugPrint('🧹 Recovery data cleared');
    } catch (e) {
      debugPrint('❌ Failed to clear recovery data: $e');
    }
  }
  
  /// Start periodic backup timer
  void _startPeriodicBackup() {
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(_backupInterval, (_) {
      if (_currentContent != null && _lastSave != null) {
        final timeSinceLastSave = DateTime.now().difference(_lastSave!);
        if (timeSinceLastSave > _backupInterval) {
          createBackup(reason: 'periodic');
        }
      }
    });
  }
  
  /// Ensure backup directory exists
  Future<void> _ensureBackupDirectory() async {
    final backupDir = Directory(_backupDir);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
  }
  
  /// Save backup to file
  Future<void> _saveBackup(EditorBackup backup) async {
    final backupId = '${backup.timestamp.millisecondsSinceEpoch}.json';
    final backupFile = File(path.join(_backupDir, backupId));
    
    await backupFile.writeAsString(jsonEncode(backup.toJson()));
  }
  
  /// Clean up old backups
  Future<void> _cleanupOldBackups() async {
    try {
      final backups = await getAvailableBackups();
      if (backups.length <= _maxBackups) return;
      
      // Remove oldest backups
      final toRemove = backups.skip(_maxBackups);
      for (final backup in toRemove) {
        final backupId = '${backup.timestamp.millisecondsSinceEpoch}.json';
        final backupFile = File(path.join(_backupDir, backupId));
        
        try {
          await backupFile.delete();
          debugPrint('🗑️ Deleted old backup: ${backup.reason}');
        } catch (e) {
          debugPrint('⚠️ Failed to delete backup file: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to cleanup old backups: $e');
    }
  }
  
  /// Check if file was modified externally
  Future<bool> _wasFileModifiedExternally(String filePath, DateTime lastSave) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      
      final stat = await file.stat();
      final fileModified = stat.modified;
      
      return fileModified.isAfter(lastSave);
    } catch (e) {
      debugPrint('⚠️ Failed to check file modification: $e');
      return false;
    }
  }
  
  /// Handle application crash detection
  Future<void> handlePotentialCrash() async {
    if (_currentContent != null && _lastSave != null) {
      await _saveRecoveryData();
      await createBackup(reason: 'crash_detection');
      debugPrint('🚨 Potential crash detected, recovery data saved');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _backupTimer?.cancel();
    _saveRecoveryData();
    debugPrint('🛡️ Editor crash recovery disposed');
  }
}

/// Editor backup data
class EditorBackup {
  final String filePath;
  final String content;
  final DateTime timestamp;
  final String reason;
  
  EditorBackup({
    required this.filePath,
    required this.content,
    required this.timestamp,
    required this.reason,
  });
  
  factory EditorBackup.fromJson(Map<String, dynamic> json) {
    return EditorBackup(
      filePath: json['filePath'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      reason: json['reason'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
    };
  }
  
  String get displayName {
    final timeStr = timestamp.toLocal().toString().substring(0, 19);
    return '$reason - $timeStr';
  }
  
  String get backupId {
    return '${timestamp.millisecondsSinceEpoch}.json';
  }
}

/// Editor error types
enum EditorErrorType {
  unknown,
  fileNotFound,
  permissionDenied,
  diskFull,
  networkError,
  parseError,
  encodingError,
}

/// Editor error
class EditorError {
  final EditorErrorType type;
  final String message;
  final String? stackTrace;
  final DateTime timestamp;
  final String? filePath;
  
  EditorError({
    required this.type,
    required this.message,
    this.stackTrace,
    required this.timestamp,
    this.filePath,
  });
  
  factory EditorError.fromJson(Map<String, dynamic> json) {
    return EditorError(
      type: EditorErrorType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => EditorErrorType.unknown,
      ),
      message: json['message'] as String,
      stackTrace: json['stackTrace'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      filePath: json['filePath'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'message': message,
      'stackTrace': stackTrace,
      'timestamp': timestamp.toIso8601String(),
      'filePath': filePath,
    };
  }
}
