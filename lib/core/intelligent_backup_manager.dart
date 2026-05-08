import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Intelligent backup manager with automated scheduling and optimization
/// 
/// Features:
/// - Smart backup scheduling based on usage patterns
/// - Incremental and differential backups
/// - Backup optimization with compression
/// - Multi-destination support
/// - Backup health monitoring and verification
class IntelligentBackupManager {
  final StreamController<BackupEvent> _eventController = StreamController<BackupEvent>.broadcast();
  
  final Map<String, BackupProfile> _profiles = {};
  final Map<String, BackupSchedule> _schedules = {};
  final List<BackupExecution> _executionHistory = [];
  final Map<String, BackupHealth> _backupHealth = {};
  
  Timer? _schedulerTimer;
  Timer? _healthCheckTimer;
  bool _isInitialized = false;
  bool _isBackupActive = false;
  late SharedPreferences _prefs;
  
  Stream<BackupEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isBackupActive => _isBackupActive;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load backup data
      await _loadBackupData();
      
      // Initialize default backup profiles
      _initializeDefaultProfiles();
      
      // Initialize default schedules
      _initializeDefaultSchedules();
      
      // Start backup scheduler
      _startBackupScheduler();
      
      // Start health monitoring
      _startHealthMonitoring();
      
      _isInitialized = true;
      
      _eventController.add(BackupEvent(
        type: BackupEventType.initialized,
        message: 'Intelligent backup manager initialized',
        data: {
          'profiles': _profiles.length,
          'schedules': _schedules.length,
        },
      ));
      
      debugPrint('💾 Intelligent Backup Manager initialized');
    } catch (e) {
      debugPrint('Failed to initialize intelligent backup manager: $e');
    }
  }
  
  Future<void> _loadBackupData() async {
    try {
      final profilesJson = _prefs.getString('backup_profiles');
      if (profilesJson != null) {
        final profilesMap = jsonDecode(profilesJson);
        _profiles = profilesMap.map((key, value) => 
          MapEntry(key, BackupProfile.fromJson(value)));
      }
      
      final schedulesJson = _prefs.getString('backup_schedules');
      if (schedulesJson != null) {
        final schedulesMap = jsonDecode(schedulesJson);
        _schedules = schedulesMap.map((key, value) => 
          MapEntry(key, BackupSchedule.fromJson(value)));
      }
      
      final historyJson = _prefs.getString('backup_history');
      if (historyJson != null) {
        final historyList = jsonDecode(historyJson);
        _executionHistory = historyList.map((item) => 
          BackupExecution.fromJson(item)).toList();
      }
      
      final healthJson = _prefs.getString('backup_health');
      if (healthJson != null) {
        final healthMap = jsonDecode(healthJson);
        _backupHealth = healthMap.map((key, value) => 
          MapEntry(key, BackupHealth.fromJson(value)));
      }
    } catch (e) {
      debugPrint('Failed to load backup data: $e');
    }
  }
  
  void _initializeDefaultProfiles() {
    // Home directory backup
    _profiles['home'] = BackupProfile(
      id: 'home',
      name: 'Home Directory',
      description: 'Backup user home directory',
      source: Platform.environment['HOME'] ?? '',
      destinations: [
        BackupDestination(
          type: DestinationType.local,
          path: '${Platform.environment['HOME']}/Backups',
          compression: CompressionType.gzip,
          encryption: false,
        ),
      ],
      includes: ['Documents', 'Downloads', 'Pictures', 'Videos', 'Music'],
      excludes: ['.cache', '.tmp', 'node_modules', '.git'],
      incremental: true,
      compression: CompressionType.gzip,
      encryption: false,
      priority: BackupPriority.high,
    );
    
    // Development projects backup
    _profiles['development'] = BackupProfile(
      id: 'development',
      name: 'Development Projects',
      description: 'Backup development projects and code',
      source: '${Platform.environment['HOME']}/Development',
      destinations: [
        BackupDestination(
          type: DestinationType.local,
          path: '${Platform.environment['HOME']}/Backups/Development',
          compression: CompressionType.gzip,
          encryption: true,
        ),
      ],
      includes: ['*.dart', '*.py', '*.js', '*.ts', '*.json', '*.yaml'],
      excludes: ['node_modules', '.git', 'build', 'dist', '.dart_tool'],
      incremental: true,
      compression: CompressionType.gzip,
      encryption: true,
      priority: BackupPriority.high,
    );
    
    // System configuration backup
    _profiles['system'] = BackupProfile(
      id: 'system',
      name: 'System Configuration',
      description: 'Backup system configuration files',
      source: '/etc',
      destinations: [
        BackupDestination(
          type: DestinationType.local,
          path: '${Platform.environment['HOME']}/Backups/System',
          compression: CompressionType.gzip,
          encryption: true,
        ),
      ],
      includes: ['*.conf', '*.yaml', '*.json', 'fstab', 'passwd'],
      excludes: ['*.log', '*.tmp'],
      incremental: false,
      compression: CompressionType.gzip,
      encryption: true,
      priority: BackupPriority.medium,
    );
  }
  
  void _initializeDefaultSchedules() {
    // Daily incremental backup
    _schedules['daily_incremental'] = BackupSchedule(
      id: 'daily_incremental',
      name: 'Daily Incremental Backup',
      description: 'Daily incremental backup of critical files',
      profileId: 'home',
      frequency: BackupFrequency.daily,
      time: const TimeOfDay(hour: 1, minute: 0),
      enabled: true,
      maxRetries: 3,
      healthCheck: true,
    );
    
    // Weekly full backup
    _schedules['weekly_full'] = BackupSchedule(
      id: 'weekly_full',
      name: 'Weekly Full Backup',
      description: 'Weekly full backup of all files',
      profileId: 'home',
      frequency: BackupFrequency.weekly,
      dayOfWeek: 1, // Monday
      time: const TimeOfDay(hour: 2, minute: 0),
      enabled: true,
      maxRetries: 5,
      healthCheck: true,
    );
    
    // Monthly development backup
    _schedules['monthly_dev'] = BackupSchedule(
      id: 'monthly_dev',
      name: 'Monthly Development Backup',
      description: 'Monthly backup of development projects',
      profileId: 'development',
      frequency: BackupFrequency.monthly,
      dayOfMonth: 1,
      time: const TimeOfDay(hour: 3, minute: 0),
      enabled: true,
      maxRetries: 3,
      healthCheck: true,
    );
  }
  
  void _startBackupScheduler() {
    _schedulerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAndExecuteBackups();
    });
  }
  
  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _performBackupHealthCheck();
    });
  }
  
  Future<void> _checkAndExecuteBackups() async {
    if (_isBackupActive) return;
    
    try {
      final now = DateTime.now();
      
      for (final schedule in _schedules.values) {
        if (!schedule.enabled) continue;
        
        if (_shouldExecuteBackup(schedule, now)) {
          await _executeBackupSchedule(schedule);
        }
      }
    } catch (e) {
      debugPrint('Failed to check backup schedules: $e');
    }
  }
  
  bool _shouldExecuteBackup(BackupSchedule schedule, DateTime now) {
    // Check if it's the right time
    final scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.time.hour,
      schedule.time.minute,
    );
    
    if (now.isBefore(scheduledTime)) return false;
    
    // Check frequency
    switch (schedule.frequency) {
      case BackupFrequency.daily:
        return _wasExecutedToday(schedule.id, now);
        
      case BackupFrequency.weekly:
        if (schedule.dayOfWeek != null && now.weekday != schedule.dayOfWeek) {
          return false;
        }
        return _wasExecutedThisWeek(schedule.id, now);
        
      case BackupFrequency.monthly:
        if (schedule.dayOfMonth != null && now.day != schedule.dayOfMonth) {
          return false;
        }
        return _wasExecutedThisMonth(schedule.id, now);
    }
  }
  
  bool _wasExecutedToday(String scheduleId, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.startedAt.isAfter(today.subtract(const Duration(days: 1))));
    
    return recentExecutions.isNotEmpty;
  }
  
  bool _wasExecutedThisWeek(String scheduleId, DateTime now) {
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.startedAt.isAfter(weekStart));
    
    return recentExecutions.isNotEmpty;
  }
  
  bool _wasExecutedThisMonth(String scheduleId, DateTime now) {
    final monthStart = DateTime(now.year, now.month, 1);
    final recentExecutions = _executionHistory.where((execution) =>
        execution.scheduleId == scheduleId &&
        execution.startedAt.isAfter(monthStart));
    
    return recentExecutions.isNotEmpty;
  }
  
  Future<void> _executeBackupSchedule(BackupSchedule schedule) async {
    if (_isBackupActive) return;
    
    try {
      _isBackupActive = true;
      
      final profile = _profiles[schedule.profileId];
      if (profile == null) {
        _eventController.add(BackupEvent(
          type: BackupEventType.error,
          message: 'Backup profile not found: ${schedule.profileId}',
        ));
        return;
      }
      
      _eventController.add(BackupEvent(
        type: BackupEventType.backup_started,
        message: 'Starting backup: ${schedule.name}',
        data: {
          'scheduleId': schedule.id,
          'profileId': profile.id,
        },
      ));
      
      final execution = BackupExecution(
        id: _generateExecutionId(),
        scheduleId: schedule.id,
        profileId: profile.id,
        startedAt: DateTime.now(),
        status: BackupStatus.running,
      );
      
      _executionHistory.add(execution);
      
      // Perform backup
      await _performBackup(profile, execution);
      
      // Update execution status
      execution.completedAt = DateTime.now();
      execution.status = BackupStatus.completed;
      execution.success = true;
      
      _eventController.add(BackupEvent(
        type: BackupEventType.backup_completed,
        message: 'Backup completed: ${schedule.name}',
        data: {
          'executionId': execution.id,
          'duration': execution.completedAt!.difference(execution.startedAt).inMinutes,
        },
      ));
      
      // Save backup data
      await _saveBackupData();
      
    } catch (e) {
      _eventController.add(BackupEvent(
        type: BackupEventType.error,
        message: 'Backup execution failed: $e',
      ));
    } finally {
      _isBackupActive = false;
    }
  }
  
  Future<void> _performBackup(BackupProfile profile, BackupExecution execution) async {
    try {
      for (final destination in profile.destinations) {
        await _executeBackupToDestination(profile, destination, execution);
      }
    } catch (e) {
      debugPrint('Failed to perform backup: $e');
      rethrow;
    }
  }
  
  Future<void> _executeBackupToDestination(
    BackupProfile profile, 
    BackupDestination destination, 
    BackupExecution execution
  ) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupName = '${profile.name}_$timestamp';
      
      // Create backup directory
      final backupDir = '${destination.path}/$backupName';
      await Directory(backupDir).create(recursive: true);
      
      // Build backup command
      final command = _buildBackupCommand(profile, destination, backupDir);
      
      // Execute backup
      final result = await run(command, runInShell: true);
      
      if (result.exitCode == 0) {
        // Verify backup
        await _verifyBackup(backupDir, execution);
        
        // Update backup health
        _updateBackupHealth(profile.id, destination, true);
      } else {
        throw Exception('Backup command failed: ${result.stderr}');
      }
      
      // Compress if needed
      if (destination.compression != CompressionType.none) {
        await _compressBackup(backupDir, destination.compression);
      }
      
      // Encrypt if needed
      if (destination.encryption) {
        await _encryptBackup(backupDir, destination);
      }
      
    } catch (e) {
      _updateBackupHealth(profile.id, destination, false);
      debugPrint('Failed to execute backup to destination: $e');
      rethrow;
    }
  }
  
  String _buildBackupCommand(BackupProfile profile, BackupDestination destination, String backupDir) {
    final source = profile.source;
    final includes = profile.includes.join(' ');
    final excludes = profile.excludes.map((e) => '--exclude="$e"').join(' ');
    
    if (profile.incremental) {
      // Incremental backup using rsync
      return 'rsync -av --progress $excludes --include="$includes" "$source/" "$backupDir/"';
    } else {
      // Full backup using tar
      return 'tar -czf "$backupDir/archive.tar.gz" -C "$source" $includes $excludes';
    }
  }
  
  Future<void> _verifyBackup(String backupDir, BackupExecution execution) async {
    try {
      // Check if backup files exist and are not empty
      final dir = Directory(backupDir);
      if (!await dir.exists()) {
        throw Exception('Backup directory does not exist');
      }
      
      final files = await dir.list().toList();
      if (files.isEmpty) {
        throw Exception('Backup directory is empty');
      }
      
      // Check file sizes
      double totalSize = 0.0;
      for (final file in files) {
        final stat = await file.stat();
        totalSize += stat.size;
      }
      
      if (totalSize < 1024 * 1024) { // Less than 1MB
        throw Exception('Backup size is too small');
      }
      
      execution.verified = true;
      execution.size = totalSize / (1024 * 1024 * 1024); // Convert to GB
      
    } catch (e) {
      execution.verified = false;
      execution.error = e.toString();
      rethrow;
    }
  }
  
  Future<void> _compressBackup(String backupDir, CompressionType compression) async {
    try {
      switch (compression) {
        case CompressionType.gzip:
          await run('tar', ['-czf', '$backupDir.tar.gz', '-C', backupDir, '.']);
          break;
        case CompressionType.bzip2:
          await run('tar', ['-cjf', '$backupDir.tar.bz2', '-C', backupDir, '.']);
          break;
        case CompressionType.xz:
          await run('tar', ['-cJf', '$backupDir.tar.xz', '-C', backupDir, '.']);
          break;
        case CompressionType.none:
          break;
      }
    } catch (e) {
      debugPrint('Failed to compress backup: $e');
    }
  }
  
  Future<void> _encryptBackup(String backupDir, BackupDestination destination) async {
    try {
      // Use gpg for encryption
      await run('gpg', ['-c', '--batch', '--yes', '--passphrase', 'backup123', '$backupDir.tar.gz']);
    } catch (e) {
      debugPrint('Failed to encrypt backup: $e');
    }
  }
  
  void _updateBackupHealth(String profileId, BackupDestination destination, bool success) {
    final healthKey = '${profileId}_${destination.path}';
    final health = _backupHealth[healthKey] ?? BackupHealth(
      profileId: profileId,
      destination: destination,
      lastBackup: DateTime.now(),
      successCount: 0,
      failureCount: 0,
      averageSize: 0.0,
      averageDuration: 0.0,
    );
    
    if (success) {
      health.successCount++;
      health.lastBackup = DateTime.now();
    } else {
      health.failureCount++;
    }
    
    _backupHealth[healthKey] = health;
  }
  
  Future<void> _performBackupHealthCheck() async {
    try {
      for (final health in _backupHealth.values) {
        // Check if backup is too old
        final daysSinceLastBackup = DateTime.now().difference(health.lastBackup).inDays;
        
        if (daysSinceLastBackup > 7) { // More than a week
          _eventController.add(BackupEvent(
            type: BackupEventType.health_warning,
            message: 'Backup is overdue for profile ${health.profileId}',
            data: {
              'profileId': health.profileId,
              'daysOverdue': daysSinceLastBackup,
            },
          ));
        }
        
        // Check success rate
        final totalBackups = health.successCount + health.failureCount;
        if (totalBackups > 0) {
          final successRate = (health.successCount / totalBackups) * 100;
          
          if (successRate < 80) {
            _eventController.add(BackupEvent(
              type: BackupEventType.health_warning,
              message: 'Backup success rate is low (${successRate.toStringAsFixed(1)}%)',
              data: {
                'profileId': health.profileId,
                'successRate': successRate,
              },
            ));
          }
        }
      }
      
      // Save health data
      await _saveBackupHealth();
      
    } catch (e) {
      debugPrint('Failed to perform backup health check: $e');
    }
  }
  
  String _generateExecutionId() {
    return 'backup_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  Future<void> _saveBackupData() async {
    try {
      final profilesMap = _profiles.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('backup_profiles', jsonEncode(profilesMap));
      
      final schedulesMap = _schedules.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('backup_schedules', jsonEncode(schedulesMap));
      
      final historyList = _executionHistory.take(100).map((item) => item.toJson()).toList();
      await _prefs.setString('backup_history', jsonEncode(historyList));
      
    } catch (e) {
      debugPrint('Failed to save backup data: $e');
    }
  }
  
  Future<void> _saveBackupHealth() async {
    try {
      final healthMap = _backupHealth.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('backup_health', jsonEncode(healthMap));
    } catch (e) {
      debugPrint('Failed to save backup health: $e');
    }
  }
  
  Future<void> addCustomProfile({
    required String name,
    required String description,
    required String source,
    required List<BackupDestination> destinations,
    List<String> includes = const [],
    List<String> excludes = const [],
    bool incremental = true,
    CompressionType compression = CompressionType.gzip,
    bool encryption = false,
    BackupPriority priority = BackupPriority.normal,
  }) async {
    final profileId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    
    final profile = BackupProfile(
      id: profileId,
      name: name,
      description: description,
      source: source,
      destinations: destinations,
      includes: includes,
      excludes: excludes,
      incremental: incremental,
      compression: compression,
      encryption: encryption,
      priority: priority,
    );
    
    _profiles[profileId] = profile;
    await _saveBackupData();
    
    _eventController.add(BackupEvent(
      type: BackupEventType.profile_added,
      message: 'Custom backup profile added: $name',
      data: {'profileId': profileId},
    ));
  }
  
  Future<void> createCustomSchedule({
    required String name,
    required String description,
    required String profileId,
    required BackupFrequency frequency,
    TimeOfDay? time,
    int? dayOfWeek,
    int? dayOfMonth,
    bool enabled = true,
    int maxRetries = 3,
    bool healthCheck = true,
  }) async {
    final scheduleId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    
    final schedule = BackupSchedule(
      id: scheduleId,
      name: name,
      description: description,
      profileId: profileId,
      frequency: frequency,
      time: time ?? const TimeOfDay(hour: 2, minute: 0),
      dayOfWeek: dayOfWeek,
      dayOfMonth: dayOfMonth,
      enabled: enabled,
      maxRetries: maxRetries,
      healthCheck: healthCheck,
    );
    
    _schedules[scheduleId] = schedule;
    await _saveBackupData();
    
    _eventController.add(BackupEvent(
      type: BackupEventType.schedule_added,
      message: 'Custom backup schedule added: $name',
      data: {'scheduleId': scheduleId},
    ));
  }
  
  Future<void> executeBackupNow(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) return;
    
    final execution = BackupExecution(
      id: _generateExecutionId(),
      profileId: profileId,
      startedAt: DateTime.now(),
      status: BackupStatus.running,
      manualExecution: true,
    );
    
    _executionHistory.add(execution);
    await _performBackup(profile, execution);
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isBackupActive': _isBackupActive,
      'totalProfiles': _profiles.length,
      'totalSchedules': _schedules.length,
      'executionHistory': _executionHistory.length,
      'healthRecords': _backupHealth.length,
      'enabledSchedules': _schedules.values.where((s) => s.enabled).length,
      'successRate': _calculateSuccessRate(),
    };
  }
  
  double _calculateSuccessRate() {
    if (_executionHistory.isEmpty) return 0.0;
    
    final successful = _executionHistory.where((e) => e.success == true).length;
    return (successful / _executionHistory.length) * 100.0;
  }
  
  Future<void> dispose() async {
    _schedulerTimer?.cancel();
    _healthCheckTimer?.cancel();
    
    await _saveBackupData();
    await _saveBackupHealth();
    
    _eventController.close();
    debugPrint('💾 Intelligent Backup Manager disposed');
  }
}

// Data models
class BackupProfile {
  final String id;
  final String name;
  final String description;
  final String source;
  final List<BackupDestination> destinations;
  final List<String> includes;
  final List<String> excludes;
  final bool incremental;
  final CompressionType compression;
  final bool encryption;
  final BackupPriority priority;
  
  BackupProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.destinations,
    required this.includes,
    required this.excludes,
    required this.incremental,
    required this.compression,
    required this.encryption,
    required this.priority,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'source': source,
    'destinations': destinations.map((d) => d.toJson()).toList(),
    'includes': includes,
    'excludes': excludes,
    'incremental': incremental,
    'compression': compression.name,
    'encryption': encryption,
    'priority': priority.name,
  };
  
  factory BackupProfile.fromJson(Map<String, dynamic> json) => BackupProfile(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    source: json['source'],
    destinations: (json['destinations'] as List<dynamic>?)
        ?.map((d) => BackupDestination.fromJson(d))
        .toList() ?? [],
    includes: (json['includes'] as List<dynamic>?)?.cast<String>() ?? [],
    excludes: (json['excludes'] as List<dynamic>?)?.cast<String>() ?? [],
    incremental: json['incremental'] ?? true,
    compression: CompressionType.values.firstWhere((c) => c.name == json['compression'], orElse: () => CompressionType.gzip),
    encryption: json['encryption'] ?? false,
    priority: BackupPriority.values.firstWhere((p) => p.name == json['priority'], orElse: () => BackupPriority.normal),
  );
}

class BackupDestination {
  final DestinationType type;
  final String path;
  final CompressionType compression;
  final bool encryption;
  final String? credentials;
  
  BackupDestination({
    required this.type,
    required this.path,
    required this.compression,
    required this.encryption,
    this.credentials,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'path': path,
    'compression': compression.name,
    'encryption': encryption,
    'credentials': credentials,
  };
  
  factory BackupDestination.fromJson(Map<String, dynamic> json) => BackupDestination(
    type: DestinationType.values.firstWhere((t) => t.name == json['type'], orElse: () => DestinationType.local),
    path: json['path'],
    compression: CompressionType.values.firstWhere((c) => c.name == json['compression'], orElse: () => CompressionType.none),
    encryption: json['encryption'] ?? false,
    credentials: json['credentials'],
  );
}

class BackupSchedule {
  final String id;
  final String name;
  final String description;
  final String profileId;
  final BackupFrequency frequency;
  final TimeOfDay time;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final bool enabled;
  final int maxRetries;
  final bool healthCheck;
  
  BackupSchedule({
    required this.id,
    required this.name,
    required this.description,
    required this.profileId,
    required this.frequency,
    required this.time,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.enabled,
    required this.maxRetries,
    required this.healthCheck,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'profileId': profileId,
    'frequency': frequency.name,
    'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    'dayOfWeek': dayOfWeek,
    'dayOfMonth': dayOfMonth,
    'enabled': enabled,
    'maxRetries': maxRetries,
    'healthCheck': healthCheck,
  };
  
  factory BackupSchedule.fromJson(Map<String, dynamic> json) => BackupSchedule(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    profileId: json['profileId'],
    frequency: BackupFrequency.values.firstWhere((f) => f.name == json['frequency'], orElse: () => BackupFrequency.daily),
    time: _parseTimeOfDay(json['time'] ?? '02:00'),
    dayOfWeek: json['dayOfWeek'],
    dayOfMonth: json['dayOfMonth'],
    enabled: json['enabled'] ?? true,
    maxRetries: json['maxRetries'] ?? 3,
    healthCheck: json['healthCheck'] ?? true,
  );
  
  static TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }
}

class BackupExecution {
  final String id;
  final String? scheduleId;
  final String profileId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final BackupStatus status;
  final bool? success;
  final bool? verified;
  final double? size;
  final String? error;
  final bool manualExecution;
  
  BackupExecution({
    required this.id,
    this.scheduleId,
    required this.profileId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.success,
    this.verified,
    this.size,
    this.error,
    this.manualExecution = false,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleId': scheduleId,
    'profileId': profileId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'status': status.name,
    'success': success,
    'verified': verified,
    'size': size,
    'error': error,
    'manualExecution': manualExecution,
  };
  
  factory BackupExecution.fromJson(Map<String, dynamic> json) => BackupExecution(
    id: json['id'],
    scheduleId: json['scheduleId'],
    profileId: json['profileId'],
    startedAt: DateTime.parse(json['startedAt']),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    status: BackupStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => BackupStatus.pending),
    success: json['success'],
    verified: json['verified'],
    size: json['size']?.toDouble(),
    error: json['error'],
    manualExecution: json['manualExecution'] ?? false,
  );
}

class BackupHealth {
  final String profileId;
  final BackupDestination destination;
  final DateTime lastBackup;
  final int successCount;
  final int failureCount;
  final double averageSize;
  final double averageDuration;
  
  BackupHealth({
    required this.profileId,
    required this.destination,
    required this.lastBackup,
    required this.successCount,
    required this.failureCount,
    required this.averageSize,
    required this.averageDuration,
  });
  
  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'destination': destination.toJson(),
    'lastBackup': lastBackup.toIso8601String(),
    'successCount': successCount,
    'failureCount': failureCount,
    'averageSize': averageSize,
    'averageDuration': averageDuration,
  };
  
  factory BackupHealth.fromJson(Map<String, dynamic> json) => BackupHealth(
    profileId: json['profileId'],
    destination: BackupDestination.fromJson(json['destination']),
    lastBackup: DateTime.parse(json['lastBackup']),
    successCount: json['successCount'] ?? 0,
    failureCount: json['failureCount'] ?? 0,
    averageSize: json['averageSize']?.toDouble() ?? 0.0,
    averageDuration: json['averageDuration']?.toDouble() ?? 0.0,
  );
}

enum DestinationType {
  local,
  network,
  cloud,
}

enum CompressionType {
  none,
  gzip,
  bzip2,
  xz,
}

enum BackupPriority {
  low,
  normal,
  high,
  critical,
}

enum BackupFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
}

enum BackupStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

enum BackupEventType {
  initialized,
  profile_added,
  schedule_added,
  backup_started,
  backup_completed,
  health_warning,
  error,
}

class BackupEvent {
  final BackupEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  BackupEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
