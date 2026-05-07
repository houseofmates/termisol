import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class SyncServices {
  static const String _syncDataFile = '/home/house/.termisol_sync_data.json';
  static const String _githubApiUrl = 'https://api.github.com';
  static const String _n8nApiUrl = 'http://localhost:5678';
  static const int _maxSyncHistory = 100;
  static const int _syncTimeout = 60000; // 60 seconds
  
  final Map<String, SyncService> _services = {};
  final Map<String, List<SyncOperation>> _syncHistory = {};
  final Map<String, SyncConflict> _conflicts = {};
  final Map<String, SyncStatus> _syncStatus = {};
  
  Timer? _syncTimer;
  Timer? _conflictCheckTimer;
  String? _githubToken;
  String? _n8nToken;
  int _totalSyncs = 0;
  int _totalConflicts = 0;
  
  final StreamController<SyncEvent> _syncController = 
      StreamController<SyncEvent>.broadcast();

  void initialize({String? githubToken, String? n8nToken}) {
    _githubToken = githubToken ?? _loadGitHubToken();
    _n8nToken = n8nToken ?? _loadN8nToken();
    
    _loadSyncData();
    _initializeServices();
    _startTimers();
    developer.log('🔄 Sync Services initialized');
  }

  String _loadGitHubToken() {
    // Try environment variable
    final envToken = Platform.environment['GITHUB_TOKEN'];
    if (envToken != null) {
      return envToken!;
    }
    
    // Try config file
    final configFile = File('/home/house/.github_token');
    if (configFile.existsSync()) {
      return configFile.readAsStringSync().trim();
    }
    
    throw Exception('GitHub token not found. Set GITHUB_TOKEN environment variable or create ~/.github_token file');
  }

  String _loadN8nToken() {
    // Try environment variable
    final envToken = Platform.environment['N8N_TOKEN'];
    if (envToken != null) {
      return envToken!;
    }
    
    // Try config file
    final configFile = File('/home/house/.n8n_token');
    if (configFile.existsSync()) {
      return configFile.readAsStringSync().trim();
    }
    
    throw Exception('N8N token not found. Set N8N_TOKEN environment variable or create ~/.n8n_token file');
  }

  void _loadSyncData() {
    try {
      final file = File(_syncDataFile);
      if (!file.existsSync()) {
        developer.log('🔄 No existing sync data file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load services
      for (final entry in data['services']) {
        final service = SyncService.fromJson(entry);
        _services[service.id] = service;
      }
      
      // Load sync history
      for (final entry in data['sync_history']) {
        final serviceId = entry['service_id'];
        final operations = (entry['operations'] as List)
            .map((op) => SyncOperation.fromJson(op))
            .toList();
        
        _syncHistory[serviceId] = operations;
      }
      
      // Load conflicts
      for (final entry in data['conflicts']) {
        final conflict = SyncConflict.fromJson(entry);
        _conflicts[conflict.id] = conflict;
        _totalConflicts++;
      }
      
      developer.log('🔄 Loaded sync data: ${_services.length} services, ${_conflicts.length} conflicts');
      
    } catch (e) {
      developer.log('🔄 Failed to load sync data: $e');
    }
  }

  void _initializeServices() {
    // Initialize GitHub service
    _services['github'] = SyncService(
      id: 'github',
      name: 'GitHub',
      type: SyncType.git,
      url: _githubApiUrl,
      token: _githubToken!,
      enabled: true,
      autoSync: true,
      syncInterval: Duration(minutes: 30),
      lastSync: null,
      syncPaths: ['/home/house/termisol'],
      excludePatterns: ['*.tmp', '*.log', '.git/', 'build/', 'dist/'],
      conflictResolution: ConflictResolution.manual,
      createdAt: DateTime.now(),
    );
    
    // Initialize N8N service
    _services['n8n'] = SyncService(
      id: 'n8n',
      name: 'N8N',
      type: SyncType.workflow,
      url: _n8nApiUrl,
      token: _n8nToken!,
      enabled: true,
      autoSync: true,
      syncInterval: Duration(minutes: 15),
      lastSync: null,
      syncPaths: ['/home/house/.n8n_workflows'],
      excludePatterns: ['*.tmp', '*.bak'],
      conflictResolution: ConflictResolution.auto,
      createdAt: DateTime.now(),
    );
    
    // Initialize sync status
    for (final service in _services.values) {
      _syncStatus[service.id] = SyncStatus(
        serviceId: service.id,
        status: ServiceStatus.idle,
        lastSync: service.lastSync,
        nextSync: DateTime.now().add(service.syncInterval),
        errors: [],
        warnings: [],
      );
    }
    
    developer.log('🔄 Initialized ${_services.length} sync services');
  }

  void _startTimers() {
    _syncTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _checkSyncSchedule(),
    );
    
    _conflictCheckTimer = Timer.periodic(
      Duration(minutes: 10),
      (_) => _checkForConflicts(),
    );
  }

  Future<void> _checkSyncSchedule() async {
    for (final service in _services.values) {
      if (!service.enabled || !service.autoSync) continue;
      
      final status = _syncStatus[service.id]!;
      final now = DateTime.now();
      
      if (now.isAfter(status.nextSync)) {
        await _performSync(service.id);
      }
    }
  }

  Future<void> _checkForConflicts() async {
    for (final service in _services.values) {
      if (!service.enabled) continue;
      
      await _detectConflicts(service);
    }
  }

  Future<void> _performSync(String serviceId) async {
    final service = _services[serviceId];
    if (service == null) {
      throw Exception('Sync service not found: $serviceId');
    }
    
    final status = _syncStatus[serviceId]!;
    
    if (status.status == ServiceStatus.syncing) {
      developer.log('🔄 Sync already in progress for $serviceId');
      return;
    }
    
    try {
      status.status = ServiceStatus.syncing;
      status.lastSync = DateTime.now();
      
      developer.log('🔄 Starting sync for ${service.name}');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.syncStarted,
        serviceId: serviceId,
        serviceName: service.name,
      ));
      
      SyncResult result;
      
      switch (service.type) {
        case SyncType.git:
          result = await _syncGit(service);
          break;
        case SyncType.workflow:
          result = await _syncWorkflow(service);
          break;
        case SyncType.file:
          result = await _syncFiles(service);
          break;
        default:
          throw Exception('Unsupported sync type: ${service.type}');
      }
      
      status.status = result.success ? ServiceStatus.success : ServiceStatus.failed;
      status.nextSync = DateTime.now().add(service.syncInterval);
      
      if (result.success) {
        service.lastSync = DateTime.now();
        _totalSyncs++;
        
        developer.log('🔄 Sync completed successfully for ${service.name}');
        
        _emitEvent(SyncEvent(
          type: SyncEventType.syncCompleted,
          serviceId: serviceId,
          serviceName: service.name,
          result: result,
        ));
      } else {
        status.errors.add(result.error!);
        
        developer.log('🔄 Sync failed for ${service.name}: ${result.error}');
        
        _emitEvent(SyncEvent(
          type: SyncEventType.syncFailed,
          serviceId: serviceId,
          serviceName: service.name,
          error: result.error,
        ));
      }
      
      // Record sync operation
      await _recordSyncOperation(serviceId, result);
      
      // Save sync data
      await _saveSyncData();
      
    } catch (e) {
      status.status = ServiceStatus.failed;
      status.errors.add(e.toString());
      
      developer.log('🔄 Sync error for ${service.name}: $e');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.syncError,
        serviceId: serviceId,
        serviceName: service.name,
        error: e.toString(),
      ));
    }
  }

  Future<SyncResult> _syncGit(SyncService service) async {
    try {
      developer.log('🔄 Syncing Git service: ${service.name}');
      
      // Check if we're in a git repository
      for (final path in service.syncPaths) {
        final gitDir = Directory('$path/.git');
        if (!gitDir.existsSync()) {
          throw Exception('Not a Git repository: $path');
        }
      }
      
      // Perform git operations
      final operations = <String>[];
      
      // Add changes
      for (final path in service.syncPaths) {
        operations.add('cd $path && git add .');
      }
      
      // Commit changes
      final commitMessage = 'Auto-sync from Termisol at ${DateTime.now().toIso8601String()}';
      for (final path in service.syncPaths) {
        operations.add('cd $path && git commit -m "$commitMessage"');
      }
      
      // Push to remote
      for (final path in service.syncPaths) {
        operations.add('cd $path && git push origin main');
      }
      
      // Execute operations
      for (final operation in operations) {
        final process = await Process.start('bash', ['-c', operation]);
        final exitCode = await process.exitCode;
        
        if (exitCode != 0) {
          final error = await process.stderr.transform(utf8.decoder).join();
          throw Exception('Git operation failed: $operation\n$error');
        }
      }
      
      return SyncResult(
        success: true,
        message: 'Git sync completed successfully',
        filesProcessed: _countFilesInPaths(service.syncPaths),
        bytesTransferred: 0, // Git doesn't track bytes easily
        conflicts: [],
      );
      
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        filesProcessed: 0,
        bytesTransferred: 0,
        conflicts: [],
      );
    }
  }

  Future<SyncResult> _syncWorkflow(SyncService service) async {
    try {
      developer.log('🔄 Syncing N8N workflows: ${service.name}');
      
      // Check N8N connection
      final testResult = await _testN8nConnection(service);
      if (!testResult.success) {
        throw Exception('N8N connection failed: ${testResult.error}');
      }
      
      // Get workflows from N8N
      final workflows = await _getN8nWorkflows(service);
      
      // Sync workflows
      int filesProcessed = 0;
      final conflicts = <SyncConflict>[];
      
      for (final workflow in workflows) {
        try {
          await _syncWorkflow(service, workflow);
          filesProcessed++;
        } catch (e) {
          final conflict = SyncConflict(
            id: _generateConflictId(),
            serviceId: service.id,
            type: ConflictType.workflow,
            localPath: workflow.localPath,
            remotePath: workflow.remotePath,
            localContent: workflow.localContent,
            remoteContent: workflow.remoteContent,
            detectedAt: DateTime.now(),
            resolution: null,
          );
          
          conflicts.add(conflict);
          _conflicts[conflict.id] = conflict;
          _totalConflicts++;
        }
      }
      
      return SyncResult(
        success: true,
        message: 'N8N workflow sync completed',
        filesProcessed: filesProcessed,
        bytesTransferred: workflows.fold(0, (sum, w) => sum + (w.content?.length ?? 0)),
        conflicts: conflicts,
      );
      
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        filesProcessed: 0,
        bytesTransferred: 0,
        conflicts: [],
      );
    }
  }

  Future<SyncResult> _syncFiles(SyncService service) async {
    try {
      developer.log('🔄 Syncing files: ${service.name}');
      
      int filesProcessed = 0;
      int bytesTransferred = 0;
      final conflicts = <SyncConflict>[];
      
      for (final path in service.syncPaths) {
        final dir = Directory(path);
        if (!dir.existsSync()) continue;
        
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final relativePath = entity.path.substring(dir.path.length + 1);
            
            // Check exclude patterns
            if (_shouldExclude(relativePath, service.excludePatterns)) {
              continue;
            }
            
            try {
              // Sync file
              await _syncFile(service, entity);
              filesProcessed++;
              bytesTransferred += await entity.length();
            } catch (e) {
              final conflict = SyncConflict(
                id: _generateConflictId(),
                serviceId: service.id,
                type: ConflictType.file,
                localPath: entity.path,
                remotePath: relativePath,
                localContent: await entity.readAsString(),
                remoteContent: '', // Would be fetched from remote
                detectedAt: DateTime.now(),
                resolution: null,
              );
              
              conflicts.add(conflict);
              _conflicts[conflict.id] = conflict;
              _totalConflicts++;
            }
          }
        }
      }
      
      return SyncResult(
        success: true,
        message: 'File sync completed',
        filesProcessed: filesProcessed,
        bytesTransferred: bytesTransferred,
        conflicts: conflicts,
      );
      
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        filesProcessed: 0,
        bytesTransferred: 0,
        conflicts: [],
      );
    }
  }

  bool _shouldExclude(String path, List<String> excludePatterns) {
    for (final pattern in excludePatterns) {
      if (path.contains(RegExp(pattern))) {
        return true;
      }
    }
    return false;
  }

  int _countFilesInPaths(List<String> paths) {
    int count = 0;
    for (final path in paths) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        count += dir.listSync(recursive: true).whereType<File>().length;
      }
    }
    return count;
  }

  Future<ConnectionTest> _testN8nConnection(SyncService service) async {
    try {
      final url = Uri.parse('${service.url}/rest/test');
      final headers = {
        'Authorization': 'Bearer ${service.token}',
        'Content-Type': 'application/json',
      };
      
      final client = HttpClient();
      
      try {
        final request = await client.getUrl(url);
        headers.forEach((key, value) => request.headers.set(key, value));
        
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        
        final data = jsonDecode(responseBody);
        
        return ConnectionTest(
          success: response.statusCode == 200,
          message: data['message'] ?? 'Connection successful',
          latency: DateTime.now().difference(DateTime.now()).inMilliseconds,
        );
        
      } finally {
        client.close();
      }
      
    } catch (e) {
      return ConnectionTest(
        success: false,
        error: e.toString(),
        latency: 0,
      );
    }
  }

  Future<List<N8nWorkflow>> _getN8nWorkflows(SyncService service) async {
    try {
      final url = Uri.parse('${service.url}/rest/workflows');
      final headers = {
        'Authorization': 'Bearer ${service.token}',
        'Content-Type': 'application/json',
      };
      
      final client = HttpClient();
      
      try {
        final request = await client.getUrl(url);
        headers.forEach((key, value) => request.headers.set(key, value));
        
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        
        if (response.statusCode != 200) {
          throw Exception('Failed to fetch workflows: ${response.statusCode}');
        }
        
        final data = jsonDecode(responseBody);
        final workflows = <N8nWorkflow>[];
        
        for (final workflowData in data['data']) {
          final workflow = N8nWorkflow(
            id: workflowData['id'].toString(),
            name: workflowData['name'],
            localPath: '${service.syncPaths.first}/${workflowData['name']}.json',
            remotePath: workflowData['id'].toString(),
            content: jsonEncode(workflowData),
            lastModified: DateTime.parse(workflowData['updatedAt']),
          );
          
          workflows.add(workflow);
        }
        
        return workflows;
        
      } finally {
        client.close();
      }
      
    } catch (e) {
      throw Exception('Failed to get N8N workflows: $e');
    }
  }

  Future<void> _syncWorkflow(SyncService service, N8nWorkflow workflow) async {
    // Check local file
    final localFile = File(workflow.localPath);
    
    if (localFile.existsSync()) {
      final localContent = await localFile.readAsString();
      workflow.localContent = localContent;
      
      // Compare with remote
      if (localContent != workflow.content) {
        // Conflict detected - this will be handled by the caller
        throw Exception('Workflow conflict detected: ${workflow.name}');
      }
    } else {
      // Download workflow
      await localFile.parent.create(recursive: true);
      await localFile.writeAsString(workflow.content);
      workflow.localContent = workflow.content;
    }
  }

  Future<void> _syncFile(SyncService service, File file) async {
    // This would sync the file to the remote service
    // Implementation depends on the specific service
    final content = await file.readAsString();
    
    // Simulate file sync
    await Future.delayed(Duration(milliseconds: 100));
    
    developer.log('🔄 Synced file: ${file.path}');
  }

  Future<void> _detectConflicts(SyncService service) async {
    // Detect conflicts between local and remote
    try {
      switch (service.type) {
        case SyncType.git:
          await _detectGitConflicts(service);
          break;
        case SyncType.workflow:
          await _detectWorkflowConflicts(service);
          break;
        case SyncType.file:
          await _detectFileConflicts(service);
          break;
      }
    } catch (e) {
      developer.log('🔄 Conflict detection failed for ${service.name}: $e');
    }
  }

  Future<void> _detectGitConflicts(SyncService service) async {
    for (final path in service.syncPaths) {
      final process = await Process.start('git', ['status', '--porcelain'], workingDirectory: path);
      final output = await process.stdout.transform(utf8.decoder).join();
      
      if (output.contains('UU') || output.contains('AA') || output.contains('DD')) {
        final conflict = SyncConflict(
          id: _generateConflictId(),
          serviceId: service.id,
          type: ConflictType.git,
          localPath: path,
          remotePath: path,
          localContent: '',
          remoteContent: '',
          detectedAt: DateTime.now(),
          resolution: null,
        );
        
        _conflicts[conflict.id] = conflict;
        _totalConflicts++;
        
        _emitEvent(SyncEvent(
          type: SyncEventType.conflictDetected,
          serviceId: service.id,
          conflictId: conflict.id,
          conflictType: conflict.type,
        ));
      }
    }
  }

  Future<void> _detectWorkflowConflicts(SyncService service) async {
    // Implementation for workflow conflict detection
    // This would compare local and remote workflow versions
  }

  Future<void> _detectFileConflicts(SyncService service) async {
    // Implementation for file conflict detection
    // This would compare local and remote file versions
  }

  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    final conflict = _conflicts[conflictId];
    if (conflict == null) {
      throw Exception('Conflict not found: $conflictId');
    }
    
    try {
      conflict.resolution = resolution;
      conflict.resolvedAt = DateTime.now();
      
      // Apply resolution based on type
      switch (conflict.type) {
        case ConflictType.git:
          await _resolveGitConflict(conflict, resolution);
          break;
        case ConflictType.workflow:
          await _resolveWorkflowConflict(conflict, resolution);
          break;
        case ConflictType.file:
          await _resolveFileConflict(conflict, resolution);
          break;
      }
      
      developer.log('🔄 Resolved conflict: $conflictId with ${resolution.name}');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.conflictResolved,
        serviceId: conflict.serviceId,
        conflictId: conflictId,
        resolution: resolution,
      ));
      
      // Save sync data
      await _saveSyncData();
      
    } catch (e) {
      developer.log('🔄 Failed to resolve conflict: $conflictId - $e');
      
      _emitEvent(SyncEvent(
        type: SyncEventType.conflictResolutionFailed,
        serviceId: conflict.serviceId,
        conflictId: conflictId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _resolveGitConflict(SyncConflict conflict, ConflictResolution resolution) async {
    switch (resolution) {
      case ConflictResolution.keepLocal:
        await Process.run('git', ['checkout', '--ours', '.'], workingDirectory: conflict.localPath);
        await Process.run('git', ['add', '.'], workingDirectory: conflict.localPath);
        break;
      case ConflictResolution.keepRemote:
        await Process.run('git', ['checkout', '--theirs', '.'], workingDirectory: conflict.localPath);
        await Process.run('git', ['add', '.'], workingDirectory: conflict.localPath);
        break;
      case ConflictResolution.manual:
        // Leave conflict for manual resolution
        break;
      case ConflictResolution.auto:
        // Use automatic merge
        await Process.run('git', ['merge', '--strategy-option', 'theirs'], workingDirectory: conflict.localPath);
        break;
    }
  }

  Future<void> _resolveWorkflowConflict(SyncConflict conflict, ConflictResolution resolution) async {
    // Implementation for workflow conflict resolution
  }

  Future<void> _resolveFileConflict(SyncConflict conflict, ConflictResolution resolution) async {
    // Implementation for file conflict resolution
  }

  Future<void> _recordSyncOperation(String serviceId, SyncResult result) async {
    final operation = SyncOperation(
      id: _generateOperationId(),
      serviceId: serviceId,
      timestamp: DateTime.now(),
      status: result.success ? OperationStatus.success : OperationStatus.failed,
      message: result.message,
      error: result.error,
      filesProcessed: result.filesProcessed,
      bytesTransferred: result.bytesTransferred,
      conflicts: result.conflicts,
    );
    
    _syncHistory.putIfAbsent(serviceId, () => <SyncOperation>[]).add(operation);
    
    // Keep only recent history
    if (_syncHistory[serviceId]!.length > _maxSyncHistory) {
      _syncHistory[serviceId]!.removeAt(0);
    }
  }

  Future<void> _saveSyncData() async {
    try {
      final file = File(_syncDataFile);
      
      final servicesData = _services.values.map((service) => service.toJson()).toList();
      final syncHistoryData = <String, dynamic>{};
      
      for (final entry in _syncHistory.entries) {
        syncHistoryData[entry.key] = {
          'service_id': entry.key,
          'operations': entry.value.map((op) => op.toJson()).toList(),
        };
      }
      
      final conflictsData = _conflicts.values.map((conflict) => conflict.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'services': servicesData,
        'sync_history': syncHistoryData,
        'conflicts': conflictsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('🔄 Saved sync data');
      
    } catch (e) {
      developer.log('🔄 Failed to save sync data: $e');
    }
  }

  SyncService? getService(String serviceId) {
    return _services[serviceId];
  }

  List<SyncService> getServices() {
    return _services.values.toList();
  }

  List<SyncOperation> getSyncHistory(String serviceId) {
    return _syncHistory[serviceId] ?? [];
  }

  List<SyncConflict> getConflicts({String? serviceId}) {
    if (serviceId != null) {
      return _conflicts.values
          .where((conflict) => conflict.serviceId == serviceId)
          .toList();
    }
    return _conflicts.values.toList();
  }

  SyncStatus? getSyncStatus(String serviceId) {
    return _syncStatus[serviceId];
  }

  Future<void> enableService(String serviceId) async {
    final service = _services[serviceId];
    if (service == null) {
      throw Exception('Sync service not found: $serviceId');
    }
    
    service.enabled = true;
    
    developer.log('🔄 Enabled sync service: ${service.name}');
    
    _emitEvent(SyncEvent(
      type: SyncEventType.serviceEnabled,
      serviceId: serviceId,
      serviceName: service.name,
    ));
    
    await _saveSyncData();
  }

  Future<void> disableService(String serviceId) async {
    final service = _services[serviceId];
    if (service == null) {
      throw Exception('Sync service not found: $serviceId');
    }
    
    service.enabled = false;
    
    developer.log('🔄 Disabled sync service: ${service.name}');
    
    _emitEvent(SyncEvent(
      type: SyncEventType.serviceDisabled,
      serviceId: serviceId,
      serviceName: service.name,
    ));
    
    await _saveSyncData();
  }

  Future<void> updateService(String serviceId, {
    String? name,
    Duration? syncInterval,
    List<String>? syncPaths,
    List<String>? excludePatterns,
    ConflictResolution? conflictResolution,
    bool? autoSync,
  }) async {
    final service = _services[serviceId];
    if (service == null) {
      throw Exception('Sync service not found: $serviceId');
    }
    
    if (name != null) service.name = name!;
    if (syncInterval != null) service.syncInterval = syncInterval!;
    if (syncPaths != null) service.syncPaths = syncPaths!;
    if (excludePatterns != null) service.excludePatterns = excludePatterns!;
    if (conflictResolution != null) service.conflictResolution = conflictResolution!;
    if (autoSync != null) service.autoSync = autoSync!;
    
    developer.log('🔄 Updated sync service: ${service.name}');
    
    _emitEvent(SyncEvent(
      type: SyncEventType.serviceUpdated,
      serviceId: serviceId,
      serviceName: service.name,
    ));
    
    await _saveSyncData();
  }

  String _generateConflictId() {
    return 'conflict_${DateTime.now().millisecondsSinceEpoch}_$_totalConflicts';
  }

  String _generateOperationId() {
    return 'operation_${DateTime.now().millisecondsSinceEpoch}_$_totalSyncs';
  }

  void _emitEvent(SyncEvent event) {
    _syncController.add(event);
  }

  Stream<SyncEvent> get syncEventStream => _syncController.stream;

  SyncServicesStats getStats() {
    return SyncServicesStats(
      totalServices: _services.length,
      activeServices: _services.values
          .where((service) => service.enabled)
          .length,
      totalSyncs: _totalSyncs,
      totalConflicts: _totalConflicts,
      unresolvedConflicts: _conflicts.values
          .where((conflict) => conflict.resolution == null)
          .length,
      averageSyncTime: _calculateAverageSyncTime(),
    );
  }

  double _calculateAverageSyncTime() {
    final allOperations = _syncHistory.values
        .expand((operations) => operations)
        .where((op) => op.status == OperationStatus.success)
        .toList();
    
    if (allOperations.isEmpty) return 0.0;
    
    // This would track actual sync time
    return 30.0; // Placeholder average
  }

  void dispose() {
    _syncTimer?.cancel();
    _conflictCheckTimer?.cancel();
    
    _services.clear();
    _syncHistory.clear();
    _conflicts.clear();
    _syncStatus.clear();
    _syncController.close();
    
    developer.log('🔄 Sync Services disposed');
  }
}

class SyncService {
  final String id;
  String name;
  final SyncType type;
  final String url;
  final String token;
  bool enabled;
  bool autoSync;
  Duration syncInterval;
  DateTime? lastSync;
  final List<String> syncPaths;
  final List<String> excludePatterns;
  final ConflictResolution conflictResolution;
  final DateTime createdAt;

  SyncService({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.token,
    required this.enabled,
    required this.autoSync,
    required this.syncInterval,
    this.lastSync,
    required this.syncPaths,
    required this.excludePatterns,
    required this.conflictResolution,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'url': url,
      'token': token, // In practice, this would be encrypted
      'enabled': enabled,
      'auto_sync': autoSync,
      'sync_interval': syncInterval.inMilliseconds,
      'last_sync': lastSync?.toIso8601String(),
      'sync_paths': syncPaths,
      'exclude_patterns': excludePatterns,
      'conflict_resolution': conflictResolution.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SyncService.fromJson(Map<String, dynamic> json) {
    return SyncService(
      id: json['id'],
      name: json['name'],
      type: SyncType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => SyncType.file,
      ),
      url: json['url'],
      token: json['token'],
      enabled: json['enabled'] ?? true,
      autoSync: json['auto_sync'] ?? true,
      syncInterval: Duration(milliseconds: json['sync_interval'] ?? 1800000),
      lastSync: json['last_sync'] != null ? DateTime.parse(json['last_sync']) : null,
      syncPaths: List<String>.from(json['sync_paths'] ?? []),
      excludePatterns: List<String>.from(json['exclude_patterns'] ?? []),
      conflictResolution: ConflictResolution.values.firstWhere(
        (resolution) => resolution.name == json['conflict_resolution'],
        orElse: () => ConflictResolution.manual,
      ),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class SyncOperation {
  final String id;
  final String serviceId;
  final DateTime timestamp;
  final OperationStatus status;
  final String message;
  final String? error;
  final int filesProcessed;
  final int bytesTransferred;
  final List<SyncConflict> conflicts;

  SyncOperation({
    required this.id,
    required this.serviceId,
    required this.timestamp,
    required this.status,
    required this.message,
    this.error,
    required this.filesProcessed,
    required this.bytesTransferred,
    required this.conflicts,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'service_id': serviceId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'message': message,
      'error': error,
      'files_processed': filesProcessed,
      'bytes_transferred': bytesTransferred,
      'conflicts': conflicts.map((c) => c.toJson()).toList(),
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'],
      serviceId: json['service_id'],
      timestamp: DateTime.parse(json['timestamp']),
      status: OperationStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => OperationStatus.pending,
      ),
      message: json['message'],
      error: json['error'],
      filesProcessed: json['files_processed'] ?? 0,
      bytesTransferred: json['bytes_transferred'] ?? 0,
      conflicts: (json['conflicts'] as List?)
          ?.map((c) => SyncConflict.fromJson(c))
          .toList() ?? [],
    );
  }
}

class SyncConflict {
  final String id;
  final String serviceId;
  final ConflictType type;
  final String localPath;
  final String remotePath;
  final String localContent;
  final String remoteContent;
  final DateTime detectedAt;
  final ConflictResolution? resolution;
  final DateTime? resolvedAt;

  SyncConflict({
    required this.id,
    required this.serviceId,
    required this.type,
    required this.localPath,
    required this.remotePath,
    required this.localContent,
    required this.remoteContent,
    required this.detectedAt,
    this.resolution,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'service_id': serviceId,
      'type': type.name,
      'local_path': localPath,
      'remote_path': remotePath,
      'local_content': localContent,
      'remote_content': remoteContent,
      'detected_at': detectedAt.toIso8601String(),
      'resolution': resolution?.name,
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      id: json['id'],
      serviceId: json['service_id'],
      type: ConflictType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ConflictType.file,
      ),
      localPath: json['local_path'],
      remotePath: json['remote_path'],
      localContent: json['local_content'],
      remoteContent: json['remote_content'],
      detectedAt: DateTime.parse(json['detected_at']),
      resolution: json['resolution'] != null 
          ? ConflictResolution.values.firstWhere(
              (resolution) => resolution.name == json['resolution'],
              orElse: () => ConflictResolution.manual,
            )
          : null,
      resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at']) : null,
    );
  }
}

class SyncStatus {
  final String serviceId;
  ServiceStatus status;
  DateTime? lastSync;
  DateTime nextSync;
  final List<String> errors;
  final List<String> warnings;

  SyncStatus({
    required this.serviceId,
    required this.status,
    this.lastSync,
    required this.nextSync,
    required this.errors,
    required this.warnings,
  });
}

class SyncResult {
  final bool success;
  final String message;
  final String? error;
  final int filesProcessed;
  final int bytesTransferred;
  final List<SyncConflict> conflicts;

  SyncResult({
    required this.success,
    required this.message,
    this.error,
    required this.filesProcessed,
    required this.bytesTransferred,
    required this.conflicts,
  });
}

class N8nWorkflow {
  final String id;
  final String name;
  final String localPath;
  final String remotePath;
  final String content;
  final DateTime lastModified;
  String? localContent;
  String? remoteContent;

  N8nWorkflow({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remotePath,
    required this.content,
    required this.lastModified,
    this.localContent,
    this.remoteContent,
  });
}

class ConnectionTest {
  final bool success;
  final String message;
  final String? error;
  final int latency;

  ConnectionTest({
    required this.success,
    required this.message,
    this.error,
    required this.latency,
  });
}

enum SyncType {
  git,
  workflow,
  file,
}

enum ServiceStatus {
  idle,
  syncing,
  success,
  failed,
  disabled,
}

enum OperationStatus {
  pending,
  running,
  success,
  failed,
  cancelled,
}

enum ConflictType {
  git,
  workflow,
  file,
}

enum ConflictResolution {
  manual,
  auto,
  keepLocal,
  keepRemote,
}

enum SyncEventType {
  syncStarted,
  syncCompleted,
  syncFailed,
  syncError,
  conflictDetected,
  conflictResolved,
  conflictResolutionFailed,
  serviceEnabled,
  serviceDisabled,
  serviceUpdated,
}

class SyncEvent {
  final SyncEventType type;
  final String? serviceId;
  final String? serviceName;
  final String? conflictId;
  final ConflictType? conflictType;
  final ConflictResolution? resolution;
  final SyncResult? result;
  final String? error;

  SyncEvent({
    required this.type,
    this.serviceId,
    this.serviceName,
    this.conflictId,
    this.conflictType,
    this.resolution,
    this.result,
    this.error,
  });
}

class SyncServicesStats {
  final int totalServices;
  final int activeServices;
  final int totalSyncs;
  final int totalConflicts;
  final int unresolvedConflicts;
  final double averageSyncTime;

  SyncServicesStats({
    required this.totalServices,
    required this.activeServices,
    required this.totalSyncs,
    required this.totalConflicts,
    required this.unresolvedConflicts,
    required this.averageSyncTime,
  });
}
