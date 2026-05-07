import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class IntelligentHermesSync {
  static const String _ubuntu250Host = '192.168.4.250';
  static const String _popos233Host = '192.168.4.233';
  static const String _hermesPath = '/home/house/.hermes';
  static const int _syncInterval = 30000; // 30 seconds
  static const int _maxConflictRetries = 3;
  static const int _syncTimeout = 60000; // 1 minute
  
  final Map<String, SyncFile> _fileRegistry = {};
  final List<SyncConflict> _conflicts = [];
  final Map<String, SyncSession> _activeSessions = {};
  
  Timer? _syncTimer;
  Timer? _conflictTimer;
  bool _isSyncing = false;
  int _totalSyncs = 0;
  int _totalConflicts = 0;
  int _totalFilesSynced = 0;
  
  final StreamController<SyncEvent> _syncEventController = 
      StreamController<SyncEvent>.broadcast();

  void initialize() {
    _startSyncTimer();
    _startConflictTimer();
    _initializeFileRegistry();
    developer.log('🔄 Intelligent Hermes Sync initialized');
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(
      Duration(milliseconds: _syncInterval),
      (_) => _performIntelligentSync(),
    );
  }

  void _startConflictTimer() {
    _conflictTimer = Timer.periodic(
      Duration(seconds: 10), // Check conflicts every 10 seconds
      (_) => _resolveConflicts(),
    );
  }

  void _initializeFileRegistry() {
    // Initialize file registry with known files
    final knownFiles = [
      'config.json',
      'workflows.json',
      'shortcuts.json',
      'themes.json',
      'plugins.json',
      'sessions.json',
      'history.json',
      'cache/',
      'logs/',
      'temp/',
    ];
    
    for (final file in knownFiles) {
      _fileRegistry[file] = SyncFile(
        path: file,
        lastModified250: DateTime.now(),
        lastModified233: DateTime.now(),
        checksum250: '',
        checksum233: '',
        status: SyncStatus.synced,
      );
    }
  }

  Future<void> _performIntelligentSync() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    _totalSyncs++;
    
    try {
      developer.log('🔄 Starting intelligent sync between .250 and .233');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.syncStarted,
        timestamp: DateTime.now(),
      ));

      // Get file states from both hosts
      final files250 = await _getFilesFromHost(_ubuntu250Host);
      final files233 = await _getFilesFromHost(_popos233Host);
      
      // Compare and determine sync actions
      final syncActions = _determineSyncActions(files250, files233);
      
      // Execute sync actions
      await _executeSyncActions(syncActions);
      
      // Update file registry
      _updateFileRegistry(syncActions);
      
      developer.log('🔄 Sync completed: ${syncActions.length} actions');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.syncCompleted,
        timestamp: DateTime.now(),
        actionsCount: syncActions.length,
      ));

    } catch (e) {
      developer.log('🔄 Sync failed: $e');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.syncFailed,
        timestamp: DateTime.now(),
        error: e.toString(),
      ));
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, FileState>> _getFilesFromHost(String host) async {
    final files = <String, FileState>{};
    
    try {
      // Simulate SSH connection to get file states
      final fileStates = await _executeRemoteCommand(host, 'ls -la $_hermesPath');
      
      // Parse file states
      final lines = fileStates.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 9) continue;
        
        final filename = parts[8];
        final permissions = parts[0];
        final size = int.tryParse(parts[4]) ?? 0;
        final modified = parts[5] + ' ' + parts[6] + ' ' + parts[7];
        
        files[filename] = FileState(
          path: filename,
          size: size,
          permissions: permissions,
          lastModified: _parseDateTime(modified),
          isDirectory: permissions.startsWith('d'),
        );
      }
      
    } catch (e) {
      developer.log('🔄 Failed to get files from $host: $e');
    }
    
    return files;
  }

  Future<String> _executeRemoteCommand(String host, String command) async {
    // Simulate SSH command execution
    // In practice, this would use actual SSH connection
    
    if (host == _ubuntu250Host) {
      // Simulate .250 response (can use localhost)
      if (command.contains('memster')) {
        return 'memster_config.json 1024 -rw-r--r-- house house Jan 1 12:00 memster_config.json';
      }
    } else if (host == _popos233Host) {
      // Simulate .233 response (must use .250 IP for memster)
      if (command.contains('memster')) {
        return 'memster_config.json 1024 -rw-r--r-- house house Jan 1 12:00 memster_config.json';
      }
    }
    
    // Default file listing
    return '''total 16
drwxr-xr-x 3 house house 4096 Jan 1 12:00 .
drwxr-xr-x 5 house house 4096 Jan 1 11:00 ..
-rw-r--r-- 1 house house 1024 Jan 1 12:00 config.json
-rw-r--r-- 1 house house 2048 Jan 1 12:05 workflows.json
-rw-r--r-- 1 house house 512 Jan 1 11:30 shortcuts.json
-rw-r--r-- 1 house house 1536 Jan 1 12:10 themes.json
-rw-r--r-- 1 house house 2560 Jan 1 11:45 plugins.json
-rw-r--r-- 1 house house 3072 Jan 1 12:15 sessions.json
-rw-r--r-- 1 house house 4096 Jan 1 11:20 history.json
drwxr-xr-x 2 house house 4096 Jan 1 10:00 cache
drwxr-xr-x 2 house house 4096 Jan 1 10:30 logs
drwxr-xr-x 2 house house 4096 Jan 1 10:15 temp''';
  }

  DateTime _parseDateTime(String dateStr) {
    // Simple date parsing - in practice, use proper date parsing
    try {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, 12, 0, 0);
    } catch (e) {
      return DateTime.now();
    }
  }

  List<SyncAction> _determineSyncActions(
    Map<String, FileState> files250,
    Map<String, FileState> files233,
  ) {
    final actions = <SyncAction>[];
    
    // Get all unique files
    final allFiles = <String>{...files250.keys, ...files233.keys};
    
    for (final filename in allFiles) {
      final file250 = files250[filename];
      final file233 = files233[filename];
      final registryFile = _fileRegistry[filename];
      
      if (file250 != null && file233 != null) {
        // File exists on both hosts
        final action = _determineBidirectionalSyncAction(filename, file250!, file233!, registryFile);
        if (action != null) actions.add(action);
      } else if (file250 != null) {
        // File only on .250
        final action = _determineUnidirectionalSyncAction(filename, file250!, null, registryFile);
        if (action != null) actions.add(action);
      } else if (file233 != null) {
        // File only on .233
        final action = _determineUnidirectionalSyncAction(filename, null, file233!, registryFile);
        if (action != null) actions.add(action);
      }
    }
    
    return actions;
  }

  SyncAction? _determineBidirectionalSyncAction(
    String filename,
    FileState file250,
    FileState file233,
    SyncFile? registryFile,
  ) {
    // Compare modification times
    final timeDiff = file250.lastModified.difference(file233.lastModified).inMilliseconds;
    
    if (timeDiff.abs() < 1000) {
      // Files are essentially the same time
      if (file250.size == file233.size) {
        // Same size, likely in sync
        return null;
      } else {
        // Same time but different size - conflict!
        return _createConflictAction(filename, file250, file233, 'size_mismatch');
      }
    }
    
    if (timeDiff > 0) {
      // .250 is newer
      if (_shouldSyncFrom250(filename)) {
        return SyncAction(
          type: SyncActionType.sync250to233,
          filename: filename,
          sourceHost: _ubuntu250Host,
          destinationHost: _popos233Host,
          reason: '250_newer',
        );
      } else {
        return _createConflictAction(filename, file250, file233, 'direction_conflict');
      }
    } else {
      // .233 is newer
      if (_shouldSyncFrom233(filename)) {
        return SyncAction(
          type: SyncActionType.sync233to250,
          filename: filename,
          sourceHost: _popos233Host,
          destinationHost: _ubuntu250Host,
          reason: '233_newer',
        );
      } else {
        return _createConflictAction(filename, file250, file233, 'direction_conflict');
      }
    }
  }

  SyncAction? _determineUnidirectionalSyncAction(
    String filename,
    FileState? file250,
    FileState? file233,
    SyncFile? registryFile,
  ) {
    if (file250 != null && file233 == null) {
      // File only on .250
      if (_shouldSyncFrom250(filename)) {
        return SyncAction(
          type: SyncActionType.sync250to233,
          filename: filename,
          sourceHost: _ubuntu250Host,
          destinationHost: _popos233Host,
          reason: 'exists_only_on_250',
        );
      }
    } else if (file233 != null && file250 == null) {
      // File only on .233
      if (_shouldSyncFrom233(filename)) {
        return SyncAction(
          type: SyncActionType.sync233to250,
          filename: filename,
          sourceHost: _popos233Host,
          destinationHost: _ubuntu250Host,
          reason: 'exists_only_on_233',
        );
      }
    }
    
    return null;
  }

  bool _shouldSyncFrom250(String filename) {
    // Special handling for memster-related files
    if (filename.toLowerCase().contains('memster')) {
      return true; // .250 is authoritative for memster
    }
    
    // Default rules
    return !filename.startsWith('.') && !filename.endsWith('~');
  }

  bool _shouldSyncFrom233(String filename) {
    // Special handling for memster-related files
    if (filename.toLowerCase().contains('memster')) {
      return false; // .233 should not override .250 for memster
    }
    
    // Default rules
    return !filename.startsWith('.') && !filename.endsWith('~');
  }

  SyncAction _createConflictAction(
    String filename,
    FileState file250,
    FileState file233,
    String conflictType,
  ) {
    final conflict = SyncConflict(
      id: _generateConflictId(),
      filename: filename,
      file250: file250,
      file233: file233,
      conflictType: conflictType,
      createdAt: DateTime.now(),
      retryCount: 0,
    );
    
    _conflicts.add(conflict);
    _totalConflicts++;
    
    return SyncAction(
      type: SyncActionType.conflict,
      filename: filename,
      conflictId: conflict.id,
      reason: conflictType,
    );
  }

  Future<void> _executeSyncActions(List<SyncAction> actions) async {
    for (final action in actions) {
      try {
        await _executeSyncAction(action);
        _totalFilesSynced++;
      } catch (e) {
        developer.log('🔄 Failed to execute sync action ${action.filename}: $e');
      }
    }
  }

  Future<void> _executeSyncAction(SyncAction action) async {
    switch (action.type) {
      case SyncActionType.sync250to233:
        await _syncFile(action.sourceHost, action.destinationHost, action.filename);
        break;
      case SyncActionType.sync233to250:
        await _syncFile(action.sourceHost, action.destinationHost, action.filename);
        break;
      case SyncActionType.conflict:
        // Conflict will be handled by conflict resolver
        break;
    }
  }

  Future<void> _syncFile(String sourceHost, String destinationHost, String filename) async {
    final sourcePath = '$_hermesPath/$filename';
    final destinationPath = '$_hermesPath/$filename';
    
    // Handle memster special case
    if (filename.toLowerCase().contains('memster') && destinationHost == _popos233Host) {
      // Replace localhost references with .250 IP for memster files
      await _syncMemsterFile(sourceHost, destinationHost, filename);
      return;
    }
    
    // Standard file sync
    final command = 'scp $sourceHost:$sourcePath $destinationHost:$destinationPath';
    await _executeRemoteCommand(sourceHost, command);
    
    developer.log('🔄 Synced $filename from $sourceHost to $destinationHost');
  }

  Future<void> _syncMemsterFile(String sourceHost, String destinationHost, String filename) async {
    // Read file content from source
    final content = await _executeRemoteCommand(sourceHost, 'cat $_hermesPath/$filename');
    
    // Replace localhost references with .250 IP
    final modifiedContent = content.replaceAll('localhost', _ubuntu250Host);
    final modifiedContent = content.replaceAll('127.0.0.1', _ubuntu250Host);
    
    // Write modified content to destination
    final tempFile = '/tmp/${filename}_sync_temp';
    await _executeRemoteCommand(destinationHost, 'echo "$modifiedContent" > $tempFile');
    await _executeRemoteCommand(destinationHost, 'mv $tempFile $_hermesPath/$filename');
    
    developer.log('🔄 Synced memster file $filename with localhost -> ${_ubuntu250Host} replacement');
  }

  void _updateFileRegistry(List<SyncAction> actions) {
    for (final action in actions) {
      final registryFile = _fileRegistry[action.filename];
      if (registryFile == null) continue;
      
      switch (action.type) {
        case SyncActionType.sync250to233:
          registryFile.lastModified233 = DateTime.now();
          registryFile.status = SyncStatus.synced;
          break;
        case SyncActionType.sync233to250:
          registryFile.lastModified250 = DateTime.now();
          registryFile.status = SyncStatus.synced;
          break;
        case SyncActionType.conflict:
          registryFile.status = SyncStatus.conflicted;
          break;
      }
    }
  }

  Future<void> _resolveConflicts() async {
    if (_conflicts.isEmpty) return;
    
    final conflictsToResolve = <SyncConflict>[];
    
    for (final conflict in _conflicts) {
      if (conflict.retryCount < _maxConflictRetries) {
        conflictsToResolve.add(conflict);
      }
    }
    
    for (final conflict in conflictsToResolve) {
      await _resolveConflict(conflict);
    }
  }

  Future<void> _resolveConflict(SyncConflict conflict) async {
    conflict.retryCount++;
    
    try {
      final resolution = _determineConflictResolution(conflict);
      
      switch (resolution) {
        case ConflictResolution.keep250:
          await _syncFile(_ubuntu250Host, _popos233Host, conflict.filename);
          break;
        case ConflictResolution.keep233:
          await _syncFile(_popos233Host, _ubuntu250Host, conflict.filename);
          break;
        case ConflictResolution.merge:
          await _mergeConflictFiles(conflict);
          break;
        case ConflictResolution.manual:
          // Leave for manual resolution
          break;
      }
      
      conflict.status = ConflictStatus.resolved;
      conflict.resolvedAt = DateTime.now();
      
      _conflicts.remove(conflict);
      
      developer.log('🔄 Resolved conflict for ${conflict.filename}: $resolution');
      
    } catch (e) {
      developer.log('🔄 Failed to resolve conflict for ${conflict.filename}: $e');
    }
  }

  ConflictResolution _determineConflictResolution(SyncConflict conflict) {
    // Use intelligent conflict resolution based on file type and content
    
    if (conflict.filename.toLowerCase().contains('memster')) {
      // For memster files, prefer .250 (authoritative source)
      return ConflictResolution.keep250;
    }
    
    if (conflict.filename.toLowerCase().contains('config')) {
      // For config files, prefer newer
      return conflict.file250.lastModified.isAfter(conflict.file233.lastModified)
          ? ConflictResolution.keep250
          : ConflictResolution.keep233;
    }
    
    if (conflict.conflictType == 'size_mismatch') {
      // For size mismatches, prefer larger file (likely more complete)
      return conflict.file250.size > conflict.file233.size
          ? ConflictResolution.keep250
          : ConflictResolution.keep233;
    }
    
    // Default: prefer newer
    return conflict.file250.lastModified.isAfter(conflict.file233.lastModified)
        ? ConflictResolution.keep250
        : ConflictResolution.keep233;
  }

  Future<void> _mergeConflictFiles(SyncConflict conflict) async {
    // For now, implement simple merge - in practice, this would be more sophisticated
    developer.log('🔄 Merging conflict files for ${conflict.filename}');
    
    // Create merged file with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final mergedFilename = '${conflict.filename}_merged_$timestamp';
    
    // Copy both files with suffixes
    await _executeRemoteCommand(_ubuntu250Host, 
        'cp $_hermesPath/${conflict.filename} $_hermesPath/${conflict.filename}_250');
    await _executeRemoteCommand(_popos233Host, 
        'cp $_hermesPath/${conflict.filename} $_hermesPath/${conflict.filename}_233');
  }

  Future<void> forceSync(String filename, {ConflictResolution? resolution}) async {
    final file250 = await _getFilesFromHost(_ubuntu250Host);
    final file233 = await _getFilesFromHost(_popos233Host);
    
    final fileState250 = file250[filename];
    final fileState233 = file233[filename];
    
    if (fileState250 != null && fileState233 != null) {
      final action = SyncAction(
        type: SyncActionType.sync250to233,
        filename: filename,
        sourceHost: _ubuntu250Host,
        destinationHost: _popos233Host,
        reason: 'manual_force',
      );
      
      await _executeSyncAction(action);
      
      developer.log('🔄 Forced sync of $filename completed');
    }
  }

  String _generateConflictId() {
    return 'conflict_${DateTime.now().millisecondsSinceEpoch}_$_totalConflicts';
  }

  void _emitEvent(SyncEvent event) {
    _syncEventController.add(event);
  }

  Stream<SyncEvent> get syncEventStream => _syncEventController.stream;

  IntelligentSyncStats getStats() {
    return IntelligentSyncStats(
      totalSyncs: _totalSyncs,
      totalConflicts: _totalConflicts,
      totalFilesSynced: _totalFilesSynced,
      activeConflicts: _conflicts.where((c) => c.status == ConflictStatus.active).length,
      resolvedConflicts: _conflicts.where((c) => c.status == ConflictStatus.resolved).length,
      fileRegistrySize: _fileRegistry.length,
      isSyncing: _isSyncing,
    );
  }

  void dispose() {
    _syncTimer?.cancel();
    _conflictTimer?.cancel();
    _fileRegistry.clear();
    _conflicts.clear();
    _activeSessions.clear();
    _syncEventController.close();
    developer.log('🔄 Intelligent Hermes Sync disposed');
  }
}

class SyncFile {
  final String path;
  DateTime lastModified250;
  DateTime lastModified233;
  String checksum250;
  String checksum233;
  SyncStatus status;

  SyncFile({
    required this.path,
    required this.lastModified250,
    required this.lastModified233,
    required this.checksum250,
    required this.checksum233,
    required this.status,
  });
}

class FileState {
  final String path;
  final int size;
  final String permissions;
  final DateTime lastModified;
  final bool isDirectory;

  FileState({
    required this.path,
    required this.size,
    required this.permissions,
    required this.lastModified,
    required this.isDirectory,
  });
}

class SyncAction {
  final SyncActionType type;
  final String filename;
  final String sourceHost;
  final String destinationHost;
  final String reason;
  final String? conflictId;

  SyncAction({
    required this.type,
    required this.filename,
    required this.sourceHost,
    required this.destinationHost,
    required this.reason,
    this.conflictId,
  });
}

enum SyncActionType {
  sync250to233,
  sync233to250,
  conflict,
}

class SyncConflict {
  final String id;
  final String filename;
  final FileState file250;
  final FileState file233;
  final String conflictType;
  final DateTime createdAt;
  int retryCount;
  ConflictStatus status;
  DateTime? resolvedAt;

  SyncConflict({
    required this.id,
    required this.filename,
    required this.file250,
    required this.file233,
    required this.conflictType,
    required this.createdAt,
    required this.retryCount,
  }) : status = ConflictStatus.active;
}

enum ConflictStatus {
  active,
  resolved,
  ignored,
}

enum ConflictResolution {
  keep250,
  keep233,
  merge,
  manual,
}

enum SyncStatus {
  synced,
  pending,
  conflicted,
  error,
}

enum SyncEventType {
  syncStarted,
  syncCompleted,
  syncFailed,
  conflictDetected,
  conflictResolved,
}

class SyncEvent {
  final SyncEventType type;
  final DateTime timestamp;
  final int? actionsCount;
  final String? error;

  SyncEvent({
    required this.type,
    required this.timestamp,
    this.actionsCount,
    this.error,
  });
}

class SyncSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  List<SyncAction> actions;
  SyncSessionStatus status;

  SyncSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.actions,
    required this.status,
  });
}

enum SyncSessionStatus {
  active,
  completed,
  failed,
}

class IntelligentSyncStats {
  final int totalSyncs;
  final int totalConflicts;
  final int totalFilesSynced;
  final int activeConflicts;
  final int resolvedConflicts;
  final int fileRegistrySize;
  final bool isSyncing;

  IntelligentSyncStats({
    required this.totalSyncs,
    required this.totalConflicts,
    required this.totalFilesSynced,
    required this.activeConflicts,
    required this.resolvedConflicts,
    required this.fileRegistrySize,
    required this.isSyncing,
  });
}
