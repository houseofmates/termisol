import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class AutoBackupSystem {
  static const String _backupDirectory = '/home/house/backups';
  static const String _backupConfigFile = '/home/house/.termisol_backup_config.json';
  static const int _maxBackups = 50;
  static const int _maxBackupHistory = 100;
  static const String _defaultBackupCommand = '/backup';
  
  final Map<String, BackupConfiguration> _configurations = {};
  final Map<String, List<BackupOperation>> _backupHistory = {};
  final Map<String, BackupSchedule> _schedules = {};
  final Map<String, BackupStats> _backupStats = {};
  
  Timer? _scheduleTimer;
  Timer? _cleanupTimer;
  int _totalBackups = 0;
  int _totalBytesBackedUp = 0;
  
  final StreamController<BackupEvent> _backupController = 
      StreamController<BackupEvent>.broadcast();

  void initialize() {
    _ensureBackupDirectory();
    _loadConfigurations();
    _loadBackupHistory();
    _loadSchedules();
    _setupBackupCommand();
    _startTimers();
    developer.log('💾 Auto Backup System initialized');
  }

  void _ensureBackupDirectory() {
    final backupDir = Directory(_backupDirectory);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
      backupDir.setPermissionsSync(0o755);
    }
  }

  void _loadConfigurations() {
    try {
      final file = File(_backupConfigFile);
      if (!file.existsSync()) {
        // Create default configuration
        _createDefaultConfiguration();
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['configurations']) {
        final config = BackupConfiguration.fromJson(entry);
        _configurations[config.id] = config;
      }
      
      developer.log('💾 Loaded ${_configurations.length} backup configurations');
      
    } catch (e) {
      developer.log('💾 Failed to load backup configurations: $e');
      _createDefaultConfiguration();
    }
  }

  void _createDefaultConfiguration() {
    final defaultConfig = BackupConfiguration(
      id: 'default',
      name: 'Default Backup',
      sourcePaths: ['/home/house/termisol'],
      destinationPath: _backupDirectory,
      excludePatterns: [
        '*.tmp',
        '*.log',
        '.git/',
        'build/',
        'dist/',
        'node_modules/',
        '.dart_tool/',
        'pubspec.lock',
      ],
      compressionEnabled: true,
      compressionLevel: 6,
      encryptionEnabled: false,
      incrementalBackup: true,
      maxBackupSize: 1024 * 1024 * 1024 * 10, // 10GB
      retentionDays: 30,
      createdAt: DateTime.now(),
      isActive: true,
      autoBackup: false,
      backupSchedule: BackupSchedule(
        id: 'default_schedule',
        configurationId: 'default',
        frequency: BackupFrequency.manual,
        enabled: false,
        lastRun: null,
        nextRun: null,
        createdAt: DateTime.now(),
      ),
    );
    
    _configurations['default'] = defaultConfig;
    _saveConfigurations();
    
    developer.log('💾 Created default backup configuration');
  }

  void _loadBackupHistory() {
    try {
      final historyFile = File('$_backupDirectory/backup_history.json');
      if (!historyFile.existsSync()) return;
      
      final content = historyFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['history']) {
        final operation = BackupOperation.fromJson(entry);
        
        _backupHistory.putIfAbsent(
          operation.configurationId,
          () => <BackupOperation>[],
        ).add(operation);
        
        _totalBackups++;
        _totalBytesBackedUp += operation.bytesTransferred;
      }
      
      developer.log('💾 Loaded backup history: $_totalBackups operations');
      
    } catch (e) {
      developer.log('💾 Failed to load backup history: $e');
    }
  }

  void _loadSchedules() {
    try {
      final schedulesFile = File('$_backupDirectory/schedules.json');
      if (!schedulesFile.existsSync()) return;
      
      final content = schedulesFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['schedules']) {
        final schedule = BackupSchedule.fromJson(entry);
        _schedules[schedule.id] = schedule;
      }
      
      developer.log('💾 Loaded ${_schedules.length} backup schedules');
      
    } catch (e) {
      developer.log('💾 Failed to load backup schedules: $e');
    }
  }

  void _setupBackupCommand() {
    // Create a symlink or script for /backup command
    final backupScript = File('/usr/local/bin/backup');
    
    try {
      final scriptContent = '''#!/bin/bash
# Termisol Backup Command
echo "Starting Termisol backup..."
curl -s -X POST http://localhost:8786/api/backup \\
  -H "Content-Type: application/json" \\
  -d '{"action": "backup", "configuration": "default"}'
echo "Backup command sent to Termisol"
''';
      
      backupScript.writeAsStringSync(scriptContent);
      backupScript.setPermissionsSync(0o755);
      
      developer.log('💾 Setup /backup command');
      
    } catch (e) {
      developer.log('💾 Failed to setup /backup command: $e');
    }
  }

  void _startTimers() {
    _scheduleTimer = Timer.periodic(
      Duration(minutes: 1),
      (_) => _checkSchedules(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(hours: 24),
      (_) => _cleanupOldBackups(),
    );
  }

  void _checkSchedules() {
    for (final schedule in _schedules.values) {
      if (!schedule.enabled) continue;
      
      final now = DateTime.now();
      
      if (schedule.nextRun != null && now.isAfter(schedule.nextRun!)) {
        _executeScheduledBackup(schedule);
      }
    }
  }

  Future<String> createBackup({
    String? configurationId,
    List<String>? sourcePaths,
    String? destinationPath,
    List<String>? excludePatterns,
    bool? compressionEnabled,
    int? compressionLevel,
    bool? encryptionEnabled,
    bool? incrementalBackup,
    String? name,
  }) async {
    final configId = configurationId ?? 'default';
    final config = _configurations[configId];
    
    if (config == null) {
      throw Exception('Backup configuration not found: $configId');
    }
    
    final backupId = _generateBackupId();
    final backupName = name ?? 'backup_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create backup operation
    final operation = BackupOperation(
      id: backupId,
      configurationId: configId,
      name: backupName,
      status: BackupStatus.preparing,
      startTime: DateTime.now(),
      endTime: null,
      sourcePaths: sourcePaths ?? config.sourcePaths,
      destinationPath: destinationPath ?? config.destinationPath,
      excludePatterns: excludePatterns ?? config.excludePatterns,
      compressionEnabled: compressionEnabled ?? config.compressionEnabled,
      compressionLevel: compressionLevel ?? config.compressionLevel,
      encryptionEnabled: encryptionEnabled ?? config.encryptionEnabled,
      incrementalBackup: incrementalBackup ?? config.incrementalBackup,
      filesProcessed: 0,
      bytesTransferred: 0,
      errors: [],
      warnings: [],
    );
    
    // Add to history
    _backupHistory.putIfAbsent(
      configId,
      () => <BackupOperation>[],
    ).add(operation);
    
    try {
      developer.log('💾 Starting backup: $backupName');
      
      _emitEvent(BackupEvent(
        type: BackupEventType.backupStarted,
        backupId: backupId,
        configurationId: configId,
        backupName: backupName,
      ));
      
      // Execute backup
      final result = await _executeBackup(operation);
      
      operation.status = result.success ? BackupStatus.completed : BackupStatus.failed;
      operation.endTime = DateTime.now();
      operation.filesProcessed = result.filesProcessed;
      operation.bytesTransferred = result.bytesTransferred;
      operation.errors = result.errors;
      operation.warnings = result.warnings;
      
      if (result.success) {
        _totalBackups++;
        _totalBytesBackedUp += result.bytesTransferred;
        
        developer.log('💾 Backup completed successfully: $backupName');
        
        _emitEvent(BackupEvent(
          type: BackupEventType.backupCompleted,
          backupId: backupId,
          configurationId: configId,
          backupName: backupName,
          result: result,
        ));
      } else {
        developer.log('💾 Backup failed: $backupName - ${result.errors.join(', ')}');
        
        _emitEvent(BackupEvent(
          type: BackupEventType.backupFailed,
          backupId: backupId,
          configurationId: configId,
          backupName: backupName,
          errors: result.errors,
        ));
      }
      
      // Update statistics
      _updateBackupStats(configId, operation);
      
      // Save history
      await _saveBackupHistory();
      
      return backupId;
      
    } catch (e) {
      operation.status = BackupStatus.failed;
      operation.endTime = DateTime.now();
      operation.errors.add(e.toString());
      
      developer.log('💾 Backup error: $backupName - $e');
      
      _emitEvent(BackupEvent(
        type: BackupEventType.backupError,
        backupId: backupId,
        configurationId: configId,
        backupName: backupName,
        error: e.toString(),
      ));
      
      await _saveBackupHistory();
      
      rethrow;
    }
  }

  Future<BackupResult> _executeBackup(BackupOperation operation) async {
    final result = BackupResult(
      success: false,
      filesProcessed: 0,
      bytesTransferred: 0,
      errors: [],
      warnings: [],
    );
    
    try {
      operation.status = BackupStatus.running;
      
      // Create backup directory
      final backupDir = Directory('${operation.destinationPath}/${operation.name}');
      await backupDir.create(recursive: true);
      
      // Process each source path
      for (final sourcePath in operation.sourcePaths) {
        final sourceDir = Directory(sourcePath);
        if (!sourceDir.existsSync()) {
          result.errors.add('Source path does not exist: $sourcePath');
          continue;
        }
        
        await _backupDirectory(
          sourceDir,
          backupDir,
          operation,
          result,
        );
      }
      
      // Create backup metadata
      await _createBackupMetadata(backupDir, operation);
      
      result.success = result.errors.isEmpty;
      
    } catch (e) {
      result.errors.add('Backup execution failed: $e');
    }
    
    return result;
  }

  Future<void> _backupDirectory(
    Directory sourceDir,
    Directory backupDir,
    BackupOperation operation,
    BackupResult result,
  ) async {
    await for (final entity in sourceDir.list(recursive: true)) {
      try {
        final relativePath = entity.path.substring(sourceDir.path.length + 1);
        
        // Check exclude patterns
        if (_shouldExclude(relativePath, operation.excludePatterns)) {
          continue;
        }
        
        if (entity is File) {
          await _backupFile(entity, backupDir, relativePath, operation, result);
        } else if (entity is Directory) {
          await _backupDirectoryStructure(entity, backupDir, relativePath, operation);
        }
        
        result.filesProcessed++;
        
      } catch (e) {
        result.errors.add('Failed to backup ${entity.path}: $e');
      }
    }
  }

  Future<void> _backupFile(
    File sourceFile,
    Directory backupDir,
    String relativePath,
    BackupOperation operation,
    BackupResult result,
  ) async {
    final backupFile = File('${backupDir.path}/$relativePath');
    
    // Ensure parent directory exists
    await backupFile.parent.create(recursive: true);
    
    // For incremental backup, check if file has changed
    if (operation.incrementalBackup) {
      final sourceModified = await sourceFile.lastModified();
      final backupModified = backupFile.existsSync() 
          ? await backupFile.lastModified()
          : DateTime.fromMillisecondsSinceEpoch(0);
      
      if (sourceModified.isBefore(backupModified) || sourceModified.isAtSameMomentAs(backupModified)) {
        return; // File hasn't changed
      }
    }
    
    // Copy file
    if (operation.compressionEnabled) {
      await _compressAndCopyFile(sourceFile, backupFile, operation.compressionLevel);
    } else {
      await sourceFile.copy(backupFile.path);
    }
    
    final fileSize = await sourceFile.length();
    result.bytesTransferred += fileSize;
  }

  Future<void> _backupDirectoryStructure(
    Directory sourceDir,
    Directory backupDir,
    String relativePath,
    BackupOperation operation,
  ) async {
    final backupSubDir = Directory('${backupDir.path}/$relativePath');
    await backupSubDir.create(recursive: true);
  }

  Future<void> _compressAndCopyFile(
    File sourceFile,
    File backupFile,
    int compressionLevel,
  ) async {
    // Simulate compression
    // In practice, this would use compression libraries
    final sourceData = await sourceFile.readAsBytes();
    
    // Simple compression simulation (not real compression)
    final compressedData = sourceData;
    
    await backupFile.writeAsBytes(compressedData);
  }

  bool _shouldExclude(String path, List<String> excludePatterns) {
    for (final pattern in excludePatterns) {
      if (path.contains(RegExp(pattern))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _createBackupMetadata(Directory backupDir, BackupOperation operation) async {
    final metadata = {
      'backup_id': operation.id,
      'configuration_id': operation.configurationId,
      'name': operation.name,
      'created_at': operation.startTime?.toIso8601String(),
      'completed_at': operation.endTime?.toIso8601String(),
      'status': operation.status.name,
      'source_paths': operation.sourcePaths,
      'destination_path': operation.destinationPath,
      'exclude_patterns': operation.excludePatterns,
      'compression_enabled': operation.compressionEnabled,
      'compression_level': operation.compressionLevel,
      'encryption_enabled': operation.encryptionEnabled,
      'incremental_backup': operation.incrementalBackup,
      'files_processed': operation.filesProcessed,
      'bytes_transferred': operation.bytesTransferred,
      'errors': operation.errors,
      'warnings': operation.warnings,
      'termisol_version': '1.0.0',
    };
    
    final metadataFile = File('${backupDir.path}/backup_metadata.json');
    await metadataFile.writeAsString(jsonEncode(metadata));
  }

  Future<void> _executeScheduledBackup(BackupSchedule schedule) async {
    try {
      developer.log('💾 Executing scheduled backup: ${schedule.configurationId}');
      
      await createBackup(configurationId: schedule.configurationId);
      
      // Update schedule
      schedule.lastRun = DateTime.now();
      schedule.nextRun = _calculateNextRun(schedule);
      
      _saveSchedules();
      
      _emitEvent(BackupEvent(
        type: BackupEventType.scheduledBackupExecuted,
        scheduleId: schedule.id,
        configurationId: schedule.configurationId,
      ));
      
    } catch (e) {
      developer.log('💾 Scheduled backup failed: $e');
      
      _emitEvent(BackupEvent(
        type: BackupEventType.scheduledBackupFailed,
        scheduleId: schedule.id,
        configurationId: schedule.configurationId,
        error: e.toString(),
      ));
    }
  }

  DateTime? _calculateNextRun(BackupSchedule schedule) {
    if (!schedule.enabled) return null;
    
    final now = DateTime.now();
    
    switch (schedule.frequency) {
      case BackupFrequency.hourly:
        return now.add(Duration(hours: 1));
      case BackupFrequency.daily:
        final nextRun = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
        return nextRun;
      case BackupFrequency.weekly:
        final nextRun = now.add(Duration(days: 7));
        return nextRun;
      case BackupFrequency.monthly:
        final nextRun = DateTime(now.year, now.month + 1, 1, 0, 0, 0);
        return nextRun;
      case BackupFrequency.manual:
        return null;
    }
  }

  Future<void> restoreBackup({
    required String backupId,
    required String restorePath,
    List<String>? restorePaths,
  }) async {
    final backupDir = Directory('$_backupDirectory/$backupId');
    if (!backupDir.existsSync()) {
      throw Exception('Backup not found: $backupId');
    }
    
    try {
      developer.log('💾 Restoring backup: $backupId to $restorePath');
      
      // Read backup metadata
      final metadataFile = File('${backupDir.path}/backup_metadata.json');
      if (!metadataFile.existsSync()) {
        throw Exception('Backup metadata not found');
      }
      
      final metadata = jsonDecode(await metadataFile.readAsString());
      final sourcePaths = List<String>.from(metadata['source_paths']);
      
      // Restore files
      for (final sourcePath in sourcePaths) {
        if (restorePaths != null && !restorePaths.contains(sourcePath)) {
          continue;
        }
        
        final backupSourceDir = Directory('${backupDir.path}/${path.basename(sourcePath)}');
        final restoreTargetDir = Directory('$restorePath/${path.basename(sourcePath)}');
        
        if (backupSourceDir.existsSync()) {
          await _copyDirectory(backupSourceDir, restoreTargetDir);
        }
      }
      
      developer.log('💾 Backup restored successfully: $backupId');
      
      _emitEvent(BackupEvent(
        type: BackupEventType.backupRestored,
        backupId: backupId,
        restorePath: restorePath,
        restorePaths: restorePaths,
      ));
      
    } catch (e) {
      developer.log('💾 Backup restore failed: $backupId - $e');
      
      _emitEvent(BackupEvent(
        type: BackupEventType.backupRestoreFailed,
        backupId: backupId,
        restorePath: restorePath,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    
    await for (final entity in source.list(recursive: true)) {
      final relativePath = entity.path.substring(source.path.length + 1);
      final targetPath = '${destination.path}/$relativePath';
      
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      }
    }
  }

  Future<void> _cleanupOldBackups() async {
    try {
      final backupDir = Directory(_backupDirectory);
      final now = DateTime.now();
      final backupsToRemove = <String>[];
      
      await for (final entity in backupDir.list()) {
        if (entity is Directory) {
          final metadataFile = File('${entity.path}/backup_metadata.json');
          
          if (metadataFile.existsSync()) {
            try {
              final metadata = jsonDecode(await metadataFile.readAsString());
              final createdAt = DateTime.parse(metadata['created_at']);
              
              // Check retention based on configuration
              final configId = metadata['configuration_id'] ?? 'default';
              final config = _configurations[configId];
              
              if (config != null) {
                final age = now.difference(createdAt);
                if (age.inDays > config.retentionDays) {
                  backupsToRemove.add(entity.path);
                }
              }
            } catch (e) {
              developer.log('💾 Failed to process backup metadata: $e');
            }
          } else {
            // No metadata, assume old backup
            backupsToRemove.add(entity.path);
          }
        }
      }
      
      // Remove old backups
      for (final backupPath in backupsToRemove) {
        await Directory(backupPath).delete(recursive: true);
        developer.log('💾 Removed old backup: $backupPath');
      }
      
      if (backupsToRemove.isNotEmpty) {
        _emitEvent(BackupEvent(
          type: BackupEventType.backupsCleaned,
          backupPaths: backupsToRemove,
        ));
      }
      
    } catch (e) {
      developer.log('💾 Failed to cleanup old backups: $e');
    }
  }

  void _updateBackupStats(String configurationId, BackupOperation operation) {
    final stats = _backupStats.putIfAbsent(
      configurationId,
      () => BackupStats(
        configurationId: configurationId,
        totalBackups: 0,
        totalBytesBackedUp: 0,
        averageBackupSize: 0.0,
        lastBackupTime: null,
        successRate: 0.0,
      ),
    );
    
    stats.totalBackups++;
    stats.totalBytesBackedUp += operation.bytesTransferred;
    stats.lastBackupTime = operation.endTime;
    
    // Calculate average backup size
    final history = _backupHistory[configurationId] ?? [];
    final completedBackups = history.where((op) => op.status == BackupStatus.completed);
    
    if (completedBackups.isNotEmpty) {
      stats.averageBackupSize = completedBackups
          .map((op) => op.bytesTransferred)
          .reduce((a, b) => a + b) / completedBackups.length;
    }
    
    // Calculate success rate
    final successfulBackups = completedBackups.length;
    stats.successRate = history.isNotEmpty 
        ? successfulBackups / history.length 
        : 0.0;
  }

  Future<void> _saveConfigurations() async {
    try {
      final file = File(_backupConfigFile);
      
      final configsData = _configurations.values.map((config) => config.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'configurations': configsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('💾 Saved backup configurations');
      
    } catch (e) {
      developer.log('💾 Failed to save configurations: $e');
    }
  }

  Future<void> _saveBackupHistory() async {
    try {
      final historyFile = File('$_backupDirectory/backup_history.json');
      
      final historyData = <String, dynamic>{};
      
      for (final entry in _backupHistory.entries) {
        historyData[entry.key] = {
          'configuration_id': entry.key,
          'operations': entry.value.map((op) => op.toJson()).toList(),
        };
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'history': historyData,
      };
      
      await historyFile.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('💾 Failed to save backup history: $e');
    }
  }

  Future<void> _saveSchedules() async {
    try {
      final schedulesFile = File('$_backupDirectory/schedules.json');
      
      final schedulesData = _schedules.values.map((schedule) => schedule.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'schedules': schedulesData,
      };
      
      await schedulesFile.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('💾 Failed to save schedules: $e');
    }
  }

  BackupConfiguration? getConfiguration(String configurationId) {
    return _configurations[configurationId];
  }

  List<BackupConfiguration> getConfigurations() {
    return _configurations.values.toList();
  }

  List<BackupOperation> getBackupHistory(String configurationId) {
    return _backupHistory[configurationId] ?? [];
  }

  List<String> getAvailableBackups() {
    final backups = <String>[];
    final backupDir = Directory(_backupDirectory);
    
    if (backupDir.existsSync()) {
      for (final entity in backupDir.listSync()) {
        if (entity is Directory) {
          backups.add(path.basename(entity.path));
        }
      }
    }
    
    return backups..sort();
  }

  BackupStats? getBackupStats(String configurationId) {
    return _backupStats[configurationId];
  }

  Future<void> createConfiguration({
    required String name,
    required List<String> sourcePaths,
    String? destinationPath,
    List<String>? excludePatterns,
    bool? compressionEnabled,
    int? compressionLevel,
    bool? encryptionEnabled,
    bool? incrementalBackup,
    int? maxBackupSize,
    int? retentionDays,
  }) async {
    final configId = _generateConfigurationId();
    
    final configuration = BackupConfiguration(
      id: configId,
      name: name,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath ?? _backupDirectory,
      excludePatterns: excludePatterns ?? [],
      compressionEnabled: compressionEnabled ?? true,
      compressionLevel: compressionLevel ?? 6,
      encryptionEnabled: encryptionEnabled ?? false,
      incrementalBackup: incrementalBackup ?? true,
      maxBackupSize: maxBackupSize ?? 1024 * 1024 * 1024 * 10, // 10GB
      retentionDays: retentionDays ?? 30,
      createdAt: DateTime.now(),
      isActive: true,
      autoBackup: false,
      backupSchedule: BackupSchedule(
        id: '${configId}_schedule',
        configurationId: configId,
        frequency: BackupFrequency.manual,
        enabled: false,
        lastRun: null,
        nextRun: null,
        createdAt: DateTime.now(),
      ),
    );
    
    _configurations[configId] = configuration;
    
    await _saveConfigurations();
    
    developer.log('💾 Created backup configuration: $name');
    
    _emitEvent(BackupEvent(
      type: BackupEventType.configurationCreated,
      configurationId: configId,
      configurationName: name,
    ));
  }

  Future<void> updateConfiguration(String configurationId, {
    String? name,
    List<String>? sourcePaths,
    String? destinationPath,
    List<String>? excludePatterns,
    bool? compressionEnabled,
    int? compressionLevel,
    bool? encryptionEnabled,
    bool? incrementalBackup,
    int? maxBackupSize,
    int? retentionDays,
  }) async {
    final config = _configurations[configurationId];
    if (config == null) {
      throw Exception('Backup configuration not found: $configurationId');
    }
    
    if (name != null) config.name = name!;
    if (sourcePaths != null) config.sourcePaths = sourcePaths!;
    if (destinationPath != null) config.destinationPath = destinationPath!;
    if (excludePatterns != null) config.excludePatterns = excludePatterns!;
    if (compressionEnabled != null) config.compressionEnabled = compressionEnabled!;
    if (compressionLevel != null) config.compressionLevel = compressionLevel!;
    if (encryptionEnabled != null) config.encryptionEnabled = encryptionEnabled!;
    if (incrementalBackup != null) config.incrementalBackup = incrementalBackup!;
    if (maxBackupSize != null) config.maxBackupSize = maxBackupSize!;
    if (retentionDays != null) config.retentionDays = retentionDays!;
    
    await _saveConfigurations();
    
    developer.log('💾 Updated backup configuration: $configurationId');
    
    _emitEvent(BackupEvent(
      type: BackupEventType.configurationUpdated,
      configurationId: configurationId,
    ));
  }

  Future<void> deleteConfiguration(String configurationId) async {
    final config = _configurations.remove(configurationId);
    if (config == null) {
      throw Exception('Backup configuration not found: $configurationId');
    }
    
    // Remove associated data
    _backupHistory.remove(configurationId);
    _backupStats.remove(configurationId);
    
    // Remove schedule
    _schedules.removeWhere((key, value) => value.configurationId == configurationId);
    
    await _saveConfigurations();
    await _saveBackupHistory();
    await _saveSchedules();
    
    developer.log('💾 Deleted backup configuration: $configurationId');
    
    _emitEvent(BackupEvent(
      type: BackupEventType.configurationDeleted,
      configurationId: configurationId,
    ));
  }

  String _generateBackupId() {
    return 'backup_${DateTime.now().millisecondsSinceEpoch}_$_totalBackups';
  }

  String _generateConfigurationId() {
    return 'config_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(BackupEvent event) {
    _backupController.add(event);
  }

  Stream<BackupEvent> get backupEventStream => _backupController.stream;

  BackupSystemStats getStats() {
    return BackupSystemStats(
      totalConfigurations: _configurations.length,
      totalBackups: _totalBackups,
      totalBytesBackedUp: _totalBytesBackedUp,
      activeSchedules: _schedules.values.where((s) => s.enabled).length,
      averageBackupSize: _calculateAverageBackupSize(),
      successRate: _calculateOverallSuccessRate(),
    );
  }

  double _calculateAverageBackupSize() {
    final allBackups = _backupHistory.values.expand((list) => list).toList();
    if (allBackups.isEmpty) return 0.0;
    
    final completedBackups = allBackups.where((op) => op.status == BackupStatus.completed);
    if (completedBackups.isEmpty) return 0.0;
    
    return completedBackups
        .map((op) => op.bytesTransferred)
        .reduce((a, b) => a + b) / completedBackups.length;
  }

  double _calculateOverallSuccessRate() {
    final allBackups = _backupHistory.values.expand((list) => list).toList();
    if (allBackups.isEmpty) return 0.0;
    
    final successfulBackups = allBackups.where((op) => op.status == BackupStatus.completed).length;
    return successfulBackups / allBackups.length;
  }

  void dispose() {
    _scheduleTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _configurations.clear();
    _backupHistory.clear();
    _schedules.clear();
    _backupStats.clear();
    _backupController.close();
    
    developer.log('💾 Auto Backup System disposed');
  }
}

class BackupConfiguration {
  final String id;
  String name;
  final List<String> sourcePaths;
  final String destinationPath;
  final List<String> excludePatterns;
  final bool compressionEnabled;
  final int compressionLevel;
  final bool encryptionEnabled;
  final bool incrementalBackup;
  final int maxBackupSize;
  final int retentionDays;
  final DateTime createdAt;
  bool isActive;
  bool autoBackup;
  final BackupSchedule backupSchedule;

  BackupConfiguration({
    required this.id,
    required this.name,
    required this.sourcePaths,
    required this.destinationPath,
    required this.excludePatterns,
    required this.compressionEnabled,
    required this.compressionLevel,
    required this.encryptionEnabled,
    required this.incrementalBackup,
    required this.maxBackupSize,
    required this.retentionDays,
    required this.createdAt,
    required this.isActive,
    required this.autoBackup,
    required this.backupSchedule,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'source_paths': sourcePaths,
      'destination_path': destinationPath,
      'exclude_patterns': excludePatterns,
      'compression_enabled': compressionEnabled,
      'compression_level': compressionLevel,
      'encryption_enabled': encryptionEnabled,
      'incremental_backup': incrementalBackup,
      'max_backup_size': maxBackupSize,
      'retention_days': retentionDays,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
      'auto_backup': autoBackup,
      'backup_schedule': backupSchedule.toJson(),
    };
  }

  factory BackupConfiguration.fromJson(Map<String, dynamic> json) {
    return BackupConfiguration(
      id: json['id'],
      name: json['name'],
      sourcePaths: List<String>.from(json['source_paths']),
      destinationPath: json['destination_path'],
      excludePatterns: List<String>.from(json['exclude_patterns']),
      compressionEnabled: json['compression_enabled'] ?? true,
      compressionLevel: json['compression_level'] ?? 6,
      encryptionEnabled: json['encryption_enabled'] ?? false,
      incrementalBackup: json['incremental_backup'] ?? true,
      maxBackupSize: json['max_backup_size'] ?? 1024 * 1024 * 1024 * 10,
      retentionDays: json['retention_days'] ?? 30,
      createdAt: DateTime.parse(json['created_at']),
      isActive: json['is_active'] ?? true,
      autoBackup: json['auto_backup'] ?? false,
      backupSchedule: BackupSchedule.fromJson(json['backup_schedule']),
    );
  }
}

class BackupOperation {
  final String id;
  final String configurationId;
  final String name;
  BackupStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<String> sourcePaths;
  final String destinationPath;
  final List<String> excludePatterns;
  final bool compressionEnabled;
  final int compressionLevel;
  final bool encryptionEnabled;
  final bool incrementalBackup;
  int filesProcessed;
  int bytesTransferred;
  final List<String> errors;
  final List<String> warnings;

  BackupOperation({
    required this.id,
    required this.configurationId,
    required this.name,
    required this.status,
    this.startTime,
    this.endTime,
    required this.sourcePaths,
    required this.destinationPath,
    required this.excludePatterns,
    required this.compressionEnabled,
    required this.compressionLevel,
    required this.encryptionEnabled,
    required this.incrementalBackup,
    required this.filesProcessed,
    required this.bytesTransferred,
    required this.errors,
    required this.warnings,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'configuration_id': configurationId,
      'name': name,
      'status': status.name,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'source_paths': sourcePaths,
      'destination_path': destinationPath,
      'exclude_patterns': excludePatterns,
      'compression_enabled': compressionEnabled,
      'compression_level': compressionLevel,
      'encryption_enabled': encryptionEnabled,
      'incremental_backup': incrementalBackup,
      'files_processed': filesProcessed,
      'bytes_transferred': bytesTransferred,
      'errors': errors,
      'warnings': warnings,
    };
  }

  factory BackupOperation.fromJson(Map<String, dynamic> json) {
    return BackupOperation(
      id: json['id'],
      configurationId: json['configuration_id'],
      name: json['name'],
      status: BackupStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => BackupStatus.preparing,
      ),
      startTime: json['start_time'] != null ? DateTime.parse(json['start_time']) : null,
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      sourcePaths: List<String>.from(json['source_paths']),
      destinationPath: json['destination_path'],
      excludePatterns: List<String>.from(json['exclude_patterns']),
      compressionEnabled: json['compression_enabled'] ?? true,
      compressionLevel: json['compression_level'] ?? 6,
      encryptionEnabled: json['encryption_enabled'] ?? false,
      incrementalBackup: json['incremental_backup'] ?? true,
      filesProcessed: json['files_processed'] ?? 0,
      bytesTransferred: json['bytes_transferred'] ?? 0,
      errors: List<String>.from(json['errors'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
    );
  }
}

class BackupSchedule {
  final String id;
  final String configurationId;
  final BackupFrequency frequency;
  final bool enabled;
  final DateTime? lastRun;
  final DateTime? nextRun;
  final DateTime createdAt;

  BackupSchedule({
    required this.id,
    required this.configurationId,
    required this.frequency,
    required this.enabled,
    this.lastRun,
    this.nextRun,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'configuration_id': configurationId,
      'frequency': frequency.name,
      'enabled': enabled,
      'last_run': lastRun?.toIso8601String(),
      'next_run': nextRun?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BackupSchedule.fromJson(Map<String, dynamic> json) {
    return BackupSchedule(
      id: json['id'],
      configurationId: json['configuration_id'],
      frequency: BackupFrequency.values.firstWhere(
        (frequency) => frequency.name == json['frequency'],
        orElse: () => BackupFrequency.manual,
      ),
      enabled: json['enabled'] ?? false,
      lastRun: json['last_run'] != null ? DateTime.parse(json['last_run']) : null,
      nextRun: json['next_run'] != null ? DateTime.parse(json['next_run']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class BackupStats {
  final String configurationId;
  int totalBackups;
  int totalBytesBackedUp;
  double averageBackupSize;
  DateTime? lastBackupTime;
  double successRate;

  BackupStats({
    required this.configurationId,
    required this.totalBackups,
    required this.totalBytesBackedUp,
    required this.averageBackupSize,
    this.lastBackupTime,
    required this.successRate,
  });
}

class BackupResult {
  final bool success;
  final int filesProcessed;
  final int bytesTransferred;
  final List<String> errors;
  final List<String> warnings;

  BackupResult({
    required this.success,
    required this.filesProcessed,
    required this.bytesTransferred,
    required this.errors,
    required this.warnings,
  });
}

enum BackupStatus {
  preparing,
  running,
  completed,
  failed,
  cancelled,
  restoring,
}

enum BackupFrequency {
  hourly,
  daily,
  weekly,
  monthly,
  manual,
}

enum BackupEventType {
  backupStarted,
  backupCompleted,
  backupFailed,
  backupError,
  backupRestored,
  backupRestoreFailed,
  configurationCreated,
  configurationUpdated,
  configurationDeleted,
  scheduledBackupExecuted,
  scheduledBackupFailed,
  backupsCleaned,
}

class BackupEvent {
  final BackupEventType type;
  final String? backupId;
  final String? configurationId;
  final String? backupName;
  final String? restorePath;
  final List<String>? restorePaths;
  final BackupResult? result;
  final List<String>? errors;
  final String? error;
  final String? configurationName;
  final String? scheduleId;
  final List<String>? backupPaths;

  BackupEvent({
    required this.type,
    this.backupId,
    this.configurationId,
    this.backupName,
    this.restorePath,
    this.restorePaths,
    this.result,
    this.errors,
    this.error,
    this.configurationName,
    this.scheduleId,
    this.backupPaths,
  });
}

class BackupSystemStats {
  final int totalConfigurations;
  final int totalBackups;
  final int totalBytesBackedUp;
  final int activeSchedules;
  final double averageBackupSize;
  final double successRate;

  BackupSystemStats({
    required this.totalConfigurations,
    required this.totalBackups,
    required this.totalBytesBackedUp,
    required this.activeSchedules,
    required this.averageBackupSize,
    required this.successRate,
  });
}
