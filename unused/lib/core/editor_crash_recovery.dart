import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Editor Crash Recovery and Error Reporting System
/// 
/// Provides comprehensive crash recovery, error reporting, and state persistence
/// for the text editor to ensure data safety and debugging capabilities.
class EditorCrashRecovery {
  static const String _recoveryKey = 'editor_recovery_data';
  static const String _errorLogKey = 'editor_error_log';
  static const String _stateKey = 'editor_state';
  static const int _maxErrorLogEntries = 1000;
  static const int _maxRecoveryFiles = 10;
  
  static EditorCrashRecovery? _instance;
  static EditorCrashRecovery get instance => _instance ??= EditorCrashRecovery._();
  
  EditorCrashRecovery._();
  
  late SharedPreferences _prefs;
  late Directory _recoveryDir;
  final StreamController<EditorError> _errorStreamController = 
      StreamController<EditorError>.broadcast();
  
  Stream<EditorError> get errorStream => _errorStreamController.stream;
  
  /// Initialize the crash recovery system
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final appDir = await getApplicationDocumentsDirectory();
      _recoveryDir = Directory('${appDir.path}/editor_recovery');
      
      if (!await _recoveryDir.exists()) {
        await _recoveryDir.create(recursive: true);
      }
      
      // Clean up old recovery files on startup
      await _cleanupOldRecoveryFiles();
      
      debugPrint('✅ Editor Crash Recovery initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize crash recovery: $e');
      rethrow;
    }
  }
  
  /// Save editor state for recovery
  Future<void> saveEditorState(EditorState state) async {
    try {
      final stateJson = jsonEncode(state.toJson());
      await _prefs.setString(_stateKey, stateJson);
      
      // Also save to file for additional safety
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final stateFile = File('${_recoveryDir.path}/state_$timestamp.json');
      await stateFile.writeAsString(stateJson);
      
      debugPrint('💾 Editor state saved for recovery');
    } catch (e) {
      debugPrint('❌ Failed to save editor state: $e');
      await _logError(EditorError(
        type: EditorErrorType.stateSaveFailed,
        message: 'Failed to save editor state',
        details: e.toString(),
        timestamp: DateTime.now(),
      ));
    }
  }
  
  /// Load editor state from recovery
  Future<EditorState?> loadEditorState() async {
    try {
      // Try to load from preferences first
      final stateJson = _prefs.getString(_stateKey);
      if (stateJson != null) {
        final state = EditorState.fromJson(jsonDecode(stateJson));
        debugPrint('📂 Editor state loaded from preferences');
        return state;
      }
      
      // Try to load from latest file
      final stateFiles = await _recoveryDir
          .list()
          .where((entity) => entity.path.contains('state_'))
          .cast<File>()
          .toList();
      
      if (stateFiles.isNotEmpty) {
        // Sort by timestamp (newest first)
        stateFiles.sort((a, b) {
          final aTime = int.tryParse(a.path.split('_').last.split('.').first) ?? 0;
          final bTime = int.tryParse(b.path.split('_').last.split('.').first) ?? 0;
          return bTime.compareTo(aTime);
        });
        
        final latestFile = stateFiles.first;
        final content = await latestFile.readAsString();
        final state = EditorState.fromJson(jsonDecode(content));
        
        debugPrint('📂 Editor state loaded from file: ${latestFile.path}');
        return state;
      }
      
      debugPrint('ℹ️ No recovery state found');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to load editor state: $e');
      await _logError(EditorError(
        type: EditorErrorType.stateLoadFailed,
        message: 'Failed to load editor state',
        details: e.toString(),
        timestamp: DateTime.now(),
      ));
      return null;
    }
  }
  
  /// Save text content for recovery
  Future<void> saveTextContent(String filePath, String content) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = filePath.split('/').last;
      final recoveryFile = File('${_recoveryDir.path}/content_${fileName}_$timestamp.txt');
      
      await recoveryFile.writeAsString(content);
      
      // Also save metadata
      final metadata = {
        'originalPath': filePath,
        'timestamp': timestamp,
        'contentLength': content.length,
        'checksum': _calculateChecksum(content),
      };
      
      final metadataFile = File('${recoveryFile.path}.meta');
      await metadataFile.writeAsString(jsonEncode(metadata));
      
      debugPrint('💾 Text content saved for recovery: $filePath');
    } catch (e) {
      debugPrint('❌ Failed to save text content: $e');
      await _logError(EditorError(
        type: EditorErrorType.contentSaveFailed,
        message: 'Failed to save text content',
        details: 'File: $filePath, Error: $e',
        timestamp: DateTime.now(),
      ));
    }
  }
  
  /// Load text content from recovery
  Future<String?> loadTextContent(String originalPath) async {
    try {
      final fileName = originalPath.split('/').last;
      final contentFiles = await _recoveryDir
          .list()
          .where((entity) => 
              entity.path.contains('content_$fileName') && 
              !entity.path.endsWith('.meta'))
          .cast<File>()
          .toList();
      
      if (contentFiles.isNotEmpty) {
        // Sort by timestamp (newest first)
        contentFiles.sort((a, b) {
          final aTime = int.tryParse(a.path.split('_').last.split('.').first) ?? 0;
          final bTime = int.tryParse(b.path.split('_').last.split('.').first) ?? 0;
          return bTime.compareTo(aTime);
        });
        
        final latestFile = contentFiles.first;
        final content = await latestFile.readAsString();
        
        // Verify checksum if metadata exists
        final metadataFile = File('${latestFile.path}.meta');
        if (await metadataFile.exists()) {
          final metadata = jsonDecode(await metadataFile.readAsString());
          final expectedChecksum = metadata['checksum'] as String?;
          final actualChecksum = _calculateChecksum(content);
          
          if (expectedChecksum != null && expectedChecksum != actualChecksum) {
            debugPrint('⚠️ Recovery content checksum mismatch for $originalPath');
            await _logError(EditorError(
              type: EditorErrorType.corruptedRecovery,
              message: 'Recovery content checksum mismatch',
              details: 'File: $originalPath, Expected: $expectedChecksum, Actual: $actualChecksum',
              timestamp: DateTime.now(),
            ));
            return null;
          }
        }
        
        debugPrint('📂 Text content loaded from recovery: $originalPath');
        return content;
      }
      
      debugPrint('ℹ️ No recovery content found for: $originalPath');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to load text content: $e');
      await _logError(EditorError(
        type: EditorErrorType.contentLoadFailed,
        message: 'Failed to load text content',
        details: 'File: $originalPath, Error: $e',
        timestamp: DateTime.now(),
      ));
      return null;
    }
  }
  
  /// Log an error
  Future<void> logError(EditorError error) async {
    await _logError(error);
    _errorStreamController.add(error);
  }
  
  /// Internal error logging
  Future<void> _logError(EditorError error) async {
    try {
      final errorLog = _prefs.getStringList(_errorLogKey) ?? [];
      
      final errorJson = jsonEncode({
        'type': error.type.name,
        'message': error.message,
        'details': error.details,
        'timestamp': error.timestamp.toIso8601String(),
        'stackTrace': error.stackTrace,
      });
      
      errorLog.add(errorJson);
      
      // Keep only the most recent entries
      if (errorLog.length > _maxErrorLogEntries) {
        errorLog.removeRange(0, errorLog.length - _maxErrorLogEntries);
      }
      
      await _prefs.setStringList(_errorLogKey, errorLog);
      
      debugPrint('🚨 Error logged: ${error.type.name} - ${error.message}');
    } catch (e) {
      debugPrint('❌ Failed to log error: $e');
    }
  }
  
  /// Get all logged errors
  Future<List<EditorError>> getErrorLog() async {
    try {
      final errorLog = _prefs.getStringList(_errorLogKey) ?? [];
      final errors = <EditorError>[];
      
      for (final errorJson in errorLog) {
        try {
          final errorData = jsonDecode(errorJson);
          final error = EditorError(
            type: EditorErrorType.values.firstWhere(
              (type) => type.name == errorData['type'],
              orElse: () => EditorErrorType.unknown,
            ),
            message: errorData['message'] ?? '',
            details: errorData['details'],
            timestamp: DateTime.parse(errorData['timestamp']),
            stackTrace: errorData['stackTrace'],
          );
          errors.add(error);
        } catch (e) {
          debugPrint('❌ Failed to parse error log entry: $e');
        }
      }
      
      return errors;
    } catch (e) {
      debugPrint('❌ Failed to get error log: $e');
      return [];
    }
  }
  
  /// Clear error log
  Future<void> clearErrorLog() async {
    try {
      await _prefs.remove(_errorLogKey);
      debugPrint('🧹 Error log cleared');
    } catch (e) {
      debugPrint('❌ Failed to clear error log: $e');
    }
  }
  
  /// Generate crash report
  Future<String> generateCrashReport() async {
    try {
      final errors = await getErrorLog();
      final buffer = StringBuffer();
      
      buffer.writeln('Editor Crash Report');
      buffer.writeln('====================');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln();
      
      buffer.writeln('System Information:');
      buffer.writeln('- Platform: ${defaultTargetPlatform}');
      buffer.writeln('- Flutter Version: ${const String.fromEnvironment('FLUTTER_VERSION', defaultValue: 'Unknown')}');
      buffer.writeln();
      
      buffer.writeln('Error Summary:');
      buffer.writeln('- Total Errors: ${errors.length}');
      buffer.writeln('- Recent Errors (Last 10):');
      
      final recentErrors = errors.take(10).toList();
      for (int i = 0; i < recentErrors.length; i++) {
        final error = recentErrors[i];
        buffer.writeln('  ${i + 1}. [${error.type.name}] ${error.message}');
        buffer.writeln('     Time: ${error.timestamp.toIso8601String()}');
        if (error.details != null) {
          buffer.writeln('     Details: ${error.details}');
        }
        buffer.writeln();
      }
      
      buffer.writeln('Error Types Distribution:');
      final errorTypes = <EditorErrorType, int>{};
      for (final error in errors) {
        errorTypes[error.type] = (errorTypes[error.type] ?? 0) + 1;
      }
      
      for (final entry in errorTypes.entries) {
        buffer.writeln('- ${entry.key.name}: ${entry.value}');
      }
      buffer.writeln();
      
      buffer.writeln('Recovery Files:');
      final recoveryFiles = await _recoveryDir.list().toList();
      buffer.writeln('- Total Files: ${recoveryFiles.length}');
      
      for (final file in recoveryFiles) {
        final stat = await file.stat();
        buffer.writeln('- ${file.path} (${stat.size} bytes, ${stat.modified})');
      }
      buffer.writeln();
      
      buffer.writeln('Full Error Log:');
      for (int i = 0; i < errors.length; i++) {
        final error = errors[i];
        buffer.writeln('=== Error ${i + 1} ===');
        buffer.writeln('Type: ${error.type.name}');
        buffer.writeln('Message: ${error.message}');
        buffer.writeln('Timestamp: ${error.timestamp.toIso8601String()}');
        if (error.details != null) {
          buffer.writeln('Details: ${error.details}');
        }
        if (error.stackTrace != null) {
          buffer.writeln('Stack Trace:');
          buffer.writeln(error.stackTrace);
        }
        buffer.writeln();
      }
      
      return buffer.toString();
    } catch (e) {
      debugPrint('❌ Failed to generate crash report: $e');
      return 'Failed to generate crash report: $e';
    }
  }
  
  /// Export crash report to file
  Future<File> exportCrashReport() async {
    try {
      final report = await generateCrashReport();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final reportFile = File('${_recoveryDir.path}/crash_report_$timestamp.txt');
      
      await reportFile.writeAsString(report);
      
      debugPrint('📄 Crash report exported: ${reportFile.path}');
      return reportFile;
    } catch (e) {
      debugPrint('❌ Failed to export crash report: $e');
      rethrow;
    }
  }
  
  /// Clear all recovery data
  Future<void> clearRecoveryData() async {
    try {
      // Clear preferences
      await _prefs.remove(_recoveryKey);
      await _prefs.remove(_stateKey);
      
      // Clear recovery directory
      if (await _recoveryDir.exists()) {
        await for (final entity in _recoveryDir.list()) {
          await entity.delete(recursive: true);
        }
      }
      
      debugPrint('🧹 All recovery data cleared');
    } catch (e) {
      debugPrint('❌ Failed to clear recovery data: $e');
    }
  }
  
  /// Check if recovery data exists
  Future<bool> hasRecoveryData() async {
    try {
      // Check preferences
      if (_prefs.containsKey(_stateKey)) {
        return true;
      }
      
      // Check recovery directory
      if (await _recoveryDir.exists()) {
        final files = await _recoveryDir.list().toList();
        return files.isNotEmpty;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Failed to check recovery data: $e');
      return false;
    }
  }
  
  /// Get recovery statistics
  Future<RecoveryStats> getRecoveryStats() async {
    try {
      final errors = await getErrorLog();
      int totalFiles = 0;
      int totalSize = 0;
      
      if (await _recoveryDir.exists()) {
        await for (final entity in _recoveryDir.list()) {
          if (entity is File) {
            totalFiles++;
            final stat = await entity.stat();
            totalSize += stat.size;
          }
        }
      }
      
      return RecoveryStats(
        totalErrors: errors.length,
        totalRecoveryFiles: totalFiles,
        totalRecoverySize: totalSize,
        oldestError: errors.isNotEmpty ? errors.first.timestamp : null,
        newestError: errors.isNotEmpty ? errors.last.timestamp : null,
        hasRecoveryData: await hasRecoveryData(),
      );
    } catch (e) {
      debugPrint('❌ Failed to get recovery stats: $e');
      return RecoveryStats(
        totalErrors: 0,
        totalRecoveryFiles: 0,
        totalRecoverySize: 0,
        hasRecoveryData: false,
      );
    }
  }
  
  /// Clean up old recovery files
  Future<void> _cleanupOldRecoveryFiles() async {
    try {
      if (!await _recoveryDir.exists()) return;
      
      final files = await _recoveryDir.list().cast<File>().toList();
      
      // Sort by modification time (oldest first)
      files.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return aTime.compareTo(bTime);
      });
      
      // Remove oldest files if we have too many
      if (files.length > _maxRecoveryFiles) {
        final filesToRemove = files.take(files.length - _maxRecoveryFiles);
        for (final file in filesToRemove) {
          await file.delete();
          debugPrint('🗑️ Removed old recovery file: ${file.path}');
        }
      }
      
      // Remove files older than 7 days
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final file in files) {
        final modified = file.statSync().modified;
        if (modified.isBefore(cutoff)) {
          await file.delete();
          debugPrint('🗑️ Removed old recovery file: ${file.path}');
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to cleanup old recovery files: $e');
    }
  }
  
  /// Calculate checksum for content integrity
  String _calculateChecksum(String content) {
    // Simple checksum implementation
    int hash = 0;
    for (int i = 0; i < content.length; i++) {
      hash = ((hash << 5) - hash) + content.codeUnitAt(i);
      hash &= 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
  
  /// Dispose resources
  void dispose() {
    _errorStreamController.close();
  }
}

/// Editor error types
enum EditorErrorType {
  unknown,
  stateSaveFailed,
  stateLoadFailed,
  contentSaveFailed,
  contentLoadFailed,
  corruptedRecovery,
  validationFailed,
  performanceIssue,
  memoryLeak,
  fileSystemError,
  networkError,
  userError,
  systemError,
}

/// Editor error information
class EditorError {
  final EditorErrorType type;
  final String message;
  final String? details;
  final DateTime timestamp;
  final String? stackTrace;
  
  EditorError({
    required this.type,
    required this.message,
    this.details,
    required this.timestamp,
    this.stackTrace,
  });
  
  @override
  String toString() {
    return 'EditorError(${type.name}): $message';
  }
}

/// Editor state for recovery
class EditorState {
  final String filePath;
  final String content;
  final int cursorPosition;
  final int selectionStart;
  final int selectionEnd;
  final List<int> multiCursorPositions;
  final bool multiCursorMode;
  final Map<String, dynamic> settings;
  final DateTime timestamp;
  
  EditorState({
    required this.filePath,
    required this.content,
    required this.cursorPosition,
    required this.selectionStart,
    required this.selectionEnd,
    required this.multiCursorPositions,
    required this.multiCursorMode,
    required this.settings,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'content': content,
      'cursorPosition': cursorPosition,
      'selectionStart': selectionStart,
      'selectionEnd': selectionEnd,
      'multiCursorPositions': multiCursorPositions,
      'multiCursorMode': multiCursorMode,
      'settings': settings,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  factory EditorState.fromJson(Map<String, dynamic> json) {
    return EditorState(
      filePath: json['filePath'] ?? '',
      content: json['content'] ?? '',
      cursorPosition: json['cursorPosition'] ?? 0,
      selectionStart: json['selectionStart'] ?? 0,
      selectionEnd: json['selectionEnd'] ?? 0,
      multiCursorPositions: List<int>.from(json['multiCursorPositions'] ?? []),
      multiCursorMode: json['multiCursorMode'] ?? false,
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Recovery statistics
class RecoveryStats {
  final int totalErrors;
  final int totalRecoveryFiles;
  final int totalRecoverySize;
  final DateTime? oldestError;
  final DateTime? newestError;
  final bool hasRecoveryData;
  
  RecoveryStats({
    required this.totalErrors,
    required this.totalRecoveryFiles,
    required this.totalRecoverySize,
    this.oldestError,
    this.newestError,
    required this.hasRecoveryData,
  });
  
  @override
  String toString() {
    return 'RecoveryStats(errors: $totalErrors, files: $totalRecoveryFiles, size: $totalRecoverySize, hasData: $hasRecoveryData)';
  }
}

/// Error monitoring and reporting utilities
class ErrorMonitor {
  static final EditorCrashRecovery _recovery = EditorCrashRecovery.instance;
  
  /// Monitor and report errors from try-catch blocks
  static Future<T?> monitorError<T>(
    String operation,
    Future<T> Function() operationFunction, {
    String? context,
    bool logError = true,
  }) async {
    try {
      return await operationFunction();
    } catch (e, stackTrace) {
      if (logError) {
        await _recovery.logError(EditorError(
          type: EditorErrorType.systemError,
          message: 'Operation failed: $operation',
          details: context != null ? 'Context: $context\nError: $e' : e.toString(),
          timestamp: DateTime.now(),
          stackTrace: stackTrace.toString(),
        ));
      }
      return null;
    }
  }
  
  /// Monitor synchronous operations
  static T? monitorSyncError<T>(
    String operation,
    T Function() operationFunction, {
    String? context,
    bool logError = true,
  }) {
    try {
      return operationFunction();
    } catch (e, stackTrace) {
      if (logError) {
        _recovery.logError(EditorError(
          type: EditorErrorType.systemError,
          message: 'Operation failed: $operation',
          details: context != null ? 'Context: $context\nError: $e' : e.toString(),
          timestamp: DateTime.now(),
          stackTrace: stackTrace.toString(),
        ));
      }
      return null;
    }
  }
  
  /// Report validation errors
  static Future<void> reportValidationError(
    String validationType,
    String message, {
    String? details,
  }) async {
    await _recovery.logError(EditorError(
      type: EditorErrorType.validationFailed,
      message: 'Validation failed: $validationType',
      details: details != null ? '$details\n$message' : message,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Report performance issues
  static Future<void> reportPerformanceIssue(
    String operation,
    Duration duration, {
    String? details,
  }) async {
    await _recovery.logError(EditorError(
      type: EditorErrorType.performanceIssue,
      message: 'Slow operation detected: $operation',
      details: details != null 
          ? 'Duration: ${duration.inMilliseconds}ms\n$details'
          : 'Duration: ${duration.inMilliseconds}ms',
      timestamp: DateTime.now(),
    ));
  }
  
  /// Report file system errors
  static Future<void> reportFileSystemError(
    String operation,
    String filePath,
    String error, {
    String? details,
  }) async {
    await _recovery.logError(EditorError(
      type: EditorErrorType.fileSystemError,
      message: 'File system error: $operation',
      details: 'File: $filePath\nError: $error${details != null ? '\n$details' : ''}',
      timestamp: DateTime.now(),
    ));
  }
}

/// Auto-save manager for periodic state saving
class AutoSaveManager {
  static const Duration _autoSaveInterval = Duration(minutes: 2);
  static const Duration _debounceInterval = Duration(seconds: 5);
  
  Timer? _autoSaveTimer;
  Timer? _debounceTimer;
  final EditorCrashRecovery _recovery = EditorCrashRecovery.instance;
  
  /// Start auto-save
  void startAutoSave(VoidCallback saveFunction) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      ErrorMonitor.monitorError('Auto-save', () async {
        saveFunction();
      });
    });
    
    debugPrint('⏰ Auto-save started (interval: ${_autoSaveInterval.inMinutes} minutes)');
  }
  
  /// Stop auto-save
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    debugPrint('⏹️ Auto-save stopped');
  }
  
  /// Debounced save (saves only after user stops typing)
  void debouncedSave(VoidCallback saveFunction) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceInterval, () {
      ErrorMonitor.monitorError('Debounced save', () async {
        saveFunction();
      });
    });
  }
  
  /// Force immediate save
  Future<void> forceSave(VoidCallback saveFunction) async {
    await ErrorMonitor.monitorError('Force save', () async {
      saveFunction();
    });
  }
  
  /// Dispose resources
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
  }
}
