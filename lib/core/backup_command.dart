import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Backup Command System - /backup command for directory backups
class BackupCommand {
  static final BackupCommand _instance = BackupCommand._internal();
  factory BackupCommand() => _instance;
  BackupCommand._internal();

  static const String _remoteHost = '192.168.4.250';
  static const String _backupDir = '/home/house/backups';
  static const int _maxBackups = 50;
  
  bool _isInitialized = false;
  final Map<String, BackupInfo> _backupHistory = {};
  final Map<String, BackupProgress> _activeBackups = {};
  
  final _backupController = StreamController<BackupEvent>.broadcast();
  Stream<BackupEvent> get events => _backupController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Ensure backup directory exists
    await _ensureBackupDirectory();
    
    // Load backup history
    await _loadBackupHistory();
    
    _isInitialized = true;
    debugPrint('💾 Backup Command initialized');
  }

  Future<BackupResult> executeBackup({
    required String sourceDirectory,
    String? backupName,
    bool compress = true,
    bool incremental = false,
    List<String>? excludePatterns,
  }) async {
    try {
      final sourceDir = Directory(sourceDirectory);
      if (!await sourceDir.exists()) {
        return BackupResult.error('Source directory does not exist: $sourceDirectory');
      }
      
      final backupName = backupName ?? _generateBackupName(sourceDirectory);
      final backupPath = path.join(_backupDir, '$backupName.tar${compress ? '.gz' : ''}');
      
      // Check if backup already exists
      if (await File(backupPath).exists()) {
        return BackupResult.error('Backup already exists: $backupName');
      }
      
      // Create backup info
      final backupInfo = BackupInfo(
        name: backupName,
        sourcePath: sourceDirectory,
        backupPath: backupPath,
        createdAt: DateTime.now(),
        size: 0,
        compressed: compress,
        incremental: incremental,
        status: BackupStatus.inProgress,
      );
      
      _backupHistory[backupName] = backupInfo;
      
      // Start backup process
      final progress = BackupProgress(
        backupName: backupName,
        startTime: DateTime.now(),
        totalFiles: 0,
        processedFiles: 0,
        bytesProcessed: 0,
        totalBytes: 0,
        status: BackupStatus.inProgress,
      );
      
      _activeBackups[backupName] = progress;
      
      _backupController.add(BackupEvent(
        type: BackupEventType.backupStarted,
        data: {
          'backup_name': backupName,
          'source_directory': sourceDirectory,
          'backup_path': backupPath,
        },
      ));
      
      // Execute backup
      await _performBackup(
        sourceDirectory: sourceDirectory,
        backupPath: backupPath,
        progress: progress,
        compress: compress,
        incremental: incremental,
        excludePatterns: excludePatterns ?? [],
      );
      
      // Update backup info
      final backupFile = File(backupPath);
      backupInfo.size = await backupFile.length();
      backupInfo.status = BackupStatus.completed;
      backupInfo.completedAt = DateTime.now();
      
      // Clean up old backups if needed
      await _cleanupOldBackups();
      
      // Save backup history
      await _saveBackupHistory();
      
      _backupController.add(BackupEvent(
        type: BackupEventType.backupCompleted,
        data: {
          'backup_name': backupName,
          'size': backupInfo.size,
          'duration': backupInfo.completedAt!.difference(backupInfo.createdAt).inSeconds,
        },
      ));
      
      return BackupResult.success(backupInfo);
      
    } catch (e) {
      debugPrint('❌ Backup failed: $e');
      
      // Update backup info with error
      if (backupName != null && _backupHistory.containsKey(backupName)) {
        _backupHistory[backupName]!.status = BackupStatus.failed;
        _backupHistory[backupName]!.error = e.toString();
      }
      
      _backupController.add(BackupEvent(
        type: BackupEventType.backupFailed,
        data: {
          'backup_name': backupName,
          'error': e.toString(),
        },
      ));
      
      return BackupResult.error(e.toString());
    } finally {
      // Clean up active backup
      if (backupName != null) {
        _activeBackups.remove(backupName);
      }
    }
  }

  Future<List<BackupInfo>> listBackups() async {
    return _backupHistory.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<BackupResult?> restoreBackup({
    required String backupName,
    required String targetDirectory,
    bool overwrite = false,
  }) async {
    try {
      final backupInfo = _backupHistory[backupName];
      if (backupInfo == null) {
        return BackupResult.error('Backup not found: $backupName');
      }
      
      final backupFile = File(backupInfo.backupPath);
      if (!await backupFile.exists()) {
        return BackupResult.error('Backup file not found: ${backupInfo.backupPath}');
      }
      
      final targetDir = Directory(targetDirectory);
      if (await targetDir.exists()) {
        if (!overwrite) {
          return BackupResult.error('Target directory exists and overwrite is false: $targetDirectory');
        }
        await targetDir.delete(recursive: true);
      }
      
      await targetDir.create(recursive: true);
      
      _backupController.add(BackupEvent(
        type: BackupEventType.restoreStarted,
        data: {
          'backup_name': backupName,
          'target_directory': targetDirectory,
        },
      ));
      
      // Perform restore
      await _performRestore(
        backupPath: backupInfo.backupPath,
        targetDirectory: targetDirectory,
        compressed: backupInfo.compressed,
      );
      
      _backupController.add(BackupEvent(
        type: BackupEventType.restoreCompleted,
        data: {
          'backup_name': backupName,
          'target_directory': targetDirectory,
        },
      ));
      
      return BackupResult.success(backupInfo);
      
    } catch (e) {
      debugPrint('❌ Restore failed: $e');
      
      _backupController.add(BackupEvent(
        type: BackupEventType.restoreFailed,
        data: {
          'backup_name': backupName,
          'error': e.toString(),
        },
      ));
      
      return BackupResult.error(e.toString());
    }
  }

  Future<bool> deleteBackup(String backupName) async {
    try {
      final backupInfo = _backupHistory[backupName];
      if (backupInfo == null) {
        return false;
      }
      
      final backupFile = File(backupInfo.backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      
      _backupHistory.remove(backupName);
      await _saveBackupHistory();
      
      _backupController.add(BackupEvent(
        type: BackupEventType.backupDeleted,
        data: {
          'backup_name': backupName,
        },
      ));
      
      debugPrint('🗑️ Deleted backup: $backupName');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to delete backup: $e');
      return false;
    }
  }

  BackupProgress? getBackupProgress(String backupName) {
    return _activeBackups[backupName];
  }

  Map<String, dynamic> getStatistics() {
    final backups = _backupHistory.values.toList();
    final completedBackups = backups.where((b) => b.status == BackupStatus.completed);
    final totalSize = completedBackups.fold<int>(0, (sum, b) => sum + b.size);
    
    return {
      'total_backups': backups.length,
      'completed_backups': completedBackups.length,
      'failed_backups': backups.where((b) => b.status == BackupStatus.failed).length,
      'active_backups': _activeBackups.length,
      'total_size_bytes': totalSize,
      'total_size_gb': (totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2),
      'backup_directory': _backupDir,
    };
  }

  Future<void> _performBackup({
    required String sourceDirectory,
    required String backupPath,
    required BackupProgress progress,
    required bool compress,
    required bool incremental,
    required List<String> excludePatterns,
  }) async {
    final sourceDir = Directory(sourceDirectory);
    final files = await _collectFiles(sourceDir, excludePatterns);
    
    progress.totalFiles = files.length;
    progress.totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
    
    // Create tar command
    final tarCommand = _buildTarCommand(
      sourceDirectory: sourceDirectory,
      backupPath: backupPath,
      compress: compress,
      excludePatterns: excludePatterns,
    );
    
    // Execute tar command
    final result = await Process.run('bash', ['-c', tarCommand]);
    
    if (result.exitCode != 0) {
      throw Exception('Backup command failed: ${result.stderr}');
    }
    
    progress.processedFiles = files.length;
    progress.bytesProcessed = progress.totalBytes;
    progress.status = BackupStatus.completed;
  }

  Future<void> _performRestore({
    required String backupPath,
    required String targetDirectory,
    required bool compressed,
  }) async {
    // Create extract command
    final extractCommand = _buildExtractCommand(
      backupPath: backupPath,
      targetDirectory: targetDirectory,
      compressed: compressed,
    );
    
    // Execute extract command
    final result = await Process.run('bash', ['-c', extractCommand]);
    
    if (result.exitCode != 0) {
      throw Exception('Restore command failed: ${result.stderr}');
    }
  }

  Future<List<FileInfo>> _collectFiles(Directory directory, List<String> excludePatterns) async {
    final files = <FileInfo>[];
    
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final filePath = entity.path;
        final relativePath = filePath.substring(directory.path.length + 1);
        
        // Check exclude patterns
        bool shouldExclude = false;
        for (final pattern in excludePatterns) {
          if (relativePath.contains(RegExp(pattern))) {
            shouldExclude = true;
            break;
          }
        }
        
        if (!shouldExclude) {
          files.add(FileInfo(
            path: filePath,
            relativePath: relativePath,
            size: await entity.length(),
            modified: await entity.lastModified(),
          ));
        }
      }
    }
    
    return files;
  }

  String _buildTarCommand({
    required String sourceDirectory,
    required String backupPath,
    required bool compress,
    required List<String> excludePatterns,
  }) {
    final buffer = StringBuffer();
    buffer.write('tar -c');
    
    if (compress) {
      buffer.write('z');
    }
    
    buffer.write('f "$backupPath" -C "$sourceDirectory"');
    
    // Add exclude patterns
    for (final pattern in excludePatterns) {
      buffer.write(' --exclude="$pattern"');
    }
    
    // Add current directory contents
    buffer.write(' .');
    
    return buffer.toString();
  }

  String _buildExtractCommand({
    required String backupPath,
    required String targetDirectory,
    required bool compressed,
  }) {
    final buffer = StringBuffer();
    buffer.write('tar -x');
    
    if (compressed) {
      buffer.write('z');
    }
    
    buffer.write('f "$backupPath" -C "$targetDirectory"');
    
    return buffer.toString();
  }

  String _generateBackupName(String sourceDirectory) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final dirName = path.basename(sourceDirectory);
    return '${dirName}_backup_$timestamp';
  }

  Future<void> _ensureBackupDirectory() async {
    final backupDir = Directory(_backupDir);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
      debugPrint('📁 Created backup directory: $_backupDir');
    }
  }

  Future<void> _loadBackupHistory() async {
    try {
      final historyFile = File(path.join(_backupDir, '.backup_history.json'));
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in data.entries) {
          _backupHistory[entry.key] = BackupInfo.fromJson(entry.value as Map<String, dynamic>);
        }
        
        debugPrint('📚 Loaded ${_backupHistory.length} backup records');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load backup history: $e');
    }
  }

  Future<void> _saveBackupHistory() async {
    try {
      final historyFile = File(path.join(_backupDir, '.backup_history.json'));
      final data = {
        for (final entry in _backupHistory.entries) entry.key: entry.value.toJson()
      };
      
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save backup history: $e');
    }
  }

  Future<void> _cleanupOldBackups() async {
    try {
      final backups = _backupHistory.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      if (backups.length > _maxBackups) {
        final toDelete = backups.skip(_maxBackups);
        
        for (final backup in toDelete) {
          await deleteBackup(backup.name);
        }
        
        debugPrint('🧹 Cleaned up ${toDelete.length} old backups');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to cleanup old backups: $e');
    }
  }

  Future<void> dispose() async {
    _backupController.close();
    _backupHistory.clear();
    _activeBackups.clear();
  }
}

/// Data classes
class BackupInfo {
  final String name;
  final String sourcePath;
  final String backupPath;
  final DateTime createdAt;
  final DateTime? completedAt;
  int size;
  final bool compressed;
  final bool incremental;
  BackupStatus status;
  String? error;
  
  BackupInfo({
    required this.name,
    required this.sourcePath,
    required this.backupPath,
    required this.createdAt,
    this.completedAt,
    required this.size,
    required this.compressed,
    required this.incremental,
    required this.status,
    this.error,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'sourcePath': sourcePath,
    'backupPath': backupPath,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'size': size,
    'compressed': compressed,
    'incremental': incremental,
    'status': status.toString(),
    'error': error,
  };
  
  factory BackupInfo.fromJson(Map<String, dynamic> json) => BackupInfo(
    name: json['name'] as String,
    sourcePath: json['sourcePath'] as String,
    backupPath: json['backupPath'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
    size: json['size'] as int,
    compressed: json['compressed'] as bool,
    incremental: json['incremental'] as bool,
    status: BackupStatus.values.firstWhere((s) => s.toString() == json['status']),
    error: json['error'] as String?,
  );
  
  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
  
  Duration? get duration {
    if (completedAt == null) return null;
    return completedAt!.difference(createdAt);
  }
}

class BackupProgress {
  final String backupName;
  final DateTime startTime;
  int totalFiles;
  int processedFiles;
  int bytesProcessed;
  int totalBytes;
  BackupStatus status;
  
  BackupProgress({
    required this.backupName,
    required this.startTime,
    required this.totalFiles,
    this.processedFiles = 0,
    this.bytesProcessed = 0,
    required this.totalBytes,
    required this.status,
  });
  
  double get progressPercentage => totalBytes > 0 ? bytesProcessed / totalBytes : 0.0;
  double get filesProgressPercentage => totalFiles > 0 ? processedFiles / totalFiles : 0.0;
  
  Duration get elapsed => DateTime.now().difference(startTime);
}

class FileInfo {
  final String path;
  final String relativePath;
  final int size;
  final DateTime modified;
  
  FileInfo({
    required this.path,
    required this.relativePath,
    required this.size,
    required this.modified,
  });
}

class BackupResult {
  final bool success;
  final BackupInfo? backupInfo;
  final String? error;
  
  BackupResult({
    required this.success,
    this.backupInfo,
    this.error,
  });
  
  factory BackupResult.success(BackupInfo backupInfo) {
    return BackupResult(
      success: true,
      backupInfo: backupInfo,
    );
  }
  
  factory BackupResult.error(String error) {
    return BackupResult(
      success: false,
      error: error,
    );
  }
}

class BackupEvent {
  final BackupEventType type;
  final Map<String, dynamic>? data;
  
  BackupEvent({
    required this.type,
    this.data,
  });
}

enum BackupStatus {
  inProgress,
  completed,
  failed,
  cancelled,
}

enum BackupEventType {
  backupStarted,
  backupCompleted,
  backupFailed,
  backupDeleted,
  restoreStarted,
  restoreCompleted,
  restoreFailed,
}

// JSON encode function for compatibility
dynamic jsonEncode(Object object) {
  return const JsonEncoder().convert(object);
}

// JSON decode function for compatibility
dynamic jsonDecode(String source) {
  return const JsonDecoder().convert(source);
}
