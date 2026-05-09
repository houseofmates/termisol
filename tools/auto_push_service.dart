#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';
import 'dart:async';

/// amnesia-proof, restart-proof auto-push service for termisol
/// monitors file changes and automatically pushes changes older than 10 seconds
class AutoPushService {
  static const String _configFile = '.devin/auto_push_config.json';
  static const String _stateFile = '.devin/auto_push_state.json';
  static const String _lockFile = '.devin/auto_push.lock';
  static const int _pushDelaySeconds = 10;
  
  late Directory _repoDir;
  late File _stateFileHandle;
  Map<String, dynamic> _state = {};
  Timer? _monitorTimer;
  Process? _monitorProcess;
  
  Future<void> start() async {
    _repoDir = Directory.current;
    _stateFileHandle = File(_repoDir.path + '/' + _stateFile);
    
    print('🚀 Starting AutoPush Service for Termisol');
    print('📍 Repository: ${_repoDir.path}');
    
    // ensure .devin directory exists
    await Directory('.devin').create(recursive: true);
    
    // load previous state
    await _loadState();
    
    // Start monitoring
    await _startMonitoring();
    
    // Setup signal handlers for graceful shutdown
    ProcessSignal.sigint.watch().listen((signal) => _shutdown());
    ProcessSignal.sigterm.watch().listen((signal) => _shutdown());
    
    print('✅ AutoPush Service started successfully');
    print('⏱️  Pushing changes older than $_pushDelaySeconds seconds');
    
    // Keep the service running
    await _keepAlive();
  }
  
  Future<void> _loadState() async {
    if (await _stateFileHandle.exists()) {
      try {
        final content = await _stateFileHandle.readAsString();
        _state = jsonDecode(content);
        print('📂 Loaded previous state: ${_state.keys.length} tracked files');
      } catch (e) {
        print('⚠️  Could not load state file: $e');
        _state = {};
      }
    }
  }
  
  Future<void> _saveState() async {
    try {
      await _stateFileHandle.writeAsString(jsonEncode(_state));
    } catch (e) {
      print('❌ Failed to save state: $e');
    }
  }
  
  Future<void> _startMonitoring() async {
    // Use git to monitor changes more efficiently
    _monitorTimer = Timer.periodic(Duration(seconds: 5), (_) => _checkForChanges());
  }
  
  Future<void> _checkForChanges() async {
    try {
      // Check if we have a lock file (another instance running)
      if (await File(_lockFile).exists()) {
        return;
      }
      
      // Create lock file
      await File(_lockFile).writeAsString(DateTime.now().toIso8601String());
      
      // Get git status
      final result = await Process.run('git', ['status', '--porcelain'], 
          workingDirectory: _repoDir.path);
      
      if (result.exitCode != 0) {
        print('❌ Git status failed: ${result.stderr}');
        await _removeLock();
        return;
      }
      
      final lines = result.stdout.toString().split('\n').where((l) => l.isNotEmpty).toList();
      
      if (lines.isEmpty) {
        await _removeLock();
        return; // No changes
      }
      
      print('📝 Detected ${lines.length} changed files');
      
      // Check if changes are old enough to push
      final now = DateTime.now();
      final shouldPush = await _areChangesOldEnough(now, lines);
      
      if (shouldPush) {
        await _autoCommitAndPush(lines);
      }
      
      await _removeLock();
      
    } catch (e) {
      print('❌ Error checking for changes: $e');
      await _removeLock();
    }
  }
  
  Future<bool> _areChangesOldEnough(DateTime now, List<String> changedFiles) async {
    for (final line in changedFiles) {
      final status = line.substring(0, 2).trim();
      final filePath = line.substring(3);
      
      if (status == 'D') continue; // Skip deleted files for timestamp check
      
      final file = File(_repoDir.path + '/' + filePath);
      if (!await file.exists()) continue;
      
      final modified = await file.lastModified();
      final age = now.difference(modified);
      
      if (age.inSeconds < _pushDelaySeconds) {
        print('⏳ File $filePath is too recent (${age.inSeconds}s old)');
        return false;
      }
    }
    
    return true;
  }
  
  Future<void> _autoCommitAndPush(List<String> changedFiles) async {
    try {
      print('🔄 Auto-committing and pushing changes...');
      
      // Stage all changes
      final addResult = await Process.run('git', ['add', '.'], 
          workingDirectory: _repoDir.path);
      
      if (addResult.exitCode != 0) {
        print('❌ Git add failed: ${addResult.stderr}');
        return;
      }
      
      // Create commit message
      final timestamp = DateTime.now().toIso8601String();
      final commitMessage = '''Auto-commit: ${changedFiles.length} files changed

Files: ${changedFiles.map((f) => f.substring(3)).join(', ')}
Time: $timestamp

Generated with [Devin AutoPush](https://cli.devin.ai/docs)

Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>''';
      
      // Commit
      final commitResult = await Process.run('git', ['commit', '-m', commitMessage], 
          workingDirectory: _repoDir.path);
      
      if (commitResult.exitCode != 0) {
        if (commitResult.stderr.toString().contains('nothing to commit')) {
          print('✅ Nothing to commit');
          return;
        }
        print('❌ Git commit failed: ${commitResult.stderr}');
        return;
      }
      
      // Push to remote
      final pushResult = await Process.run('git', ['push', 'origin', 'HEAD'], 
          workingDirectory: _repoDir.path);
      
      if (pushResult.exitCode != 0) {
        print('❌ Git push failed: ${pushResult.stderr}');
        return;
      }
      
      print('✅ Successfully pushed ${changedFiles.length} files to GitHub');
      
      // Update state
      for (final line in changedFiles) {
        final filePath = line.substring(3);
        _state[filePath] = {
          'lastPushed': DateTime.now().toIso8601String(),
          'status': line.substring(0, 2).trim(),
        };
      }
      await _saveState();
      
    } catch (e) {
      print('❌ Error during auto-commit/push: $e');
    }
  }
  
  Future<void> _removeLock() async {
    try {
      await File(_lockFile).delete();
    } catch (e) {
      // Ignore lock file deletion errors
    }
  }
  
  Future<void> _keepAlive() async {
    print('🔄 AutoPush service is monitoring for changes...');
    
    // Keep running indefinitely
    while (true) {
      await Future.delayed(Duration(seconds: 30));
      
      // Heartbeat - update state file to show we're alive
      _state['heartbeat'] = DateTime.now().toIso8601String();
      await _saveState();
    }
  }
  
  Future<void> _shutdown() async {
    print('🛑 Shutting down AutoPush service...');
    _monitorTimer?.cancel();
    _monitorProcess?.kill();
    await _removeLock();
    exit(0);
  }
}

/// Bootstrap function to ensure service restarts after crashes/amnesia
Future<void> bootstrapService() async {
  print('🔧 Bootstrapping AutoPush Service...');
  
  // Check if service is already running
  final lockFile = File('.devin/auto_push.lock');
  if (await lockFile.exists()) {
    final lockContent = await lockFile.readAsString();
    final lockTime = DateTime.tryParse(lockContent);
    
    if (lockTime != null) {
      final age = DateTime.now().difference(lockTime);
      if (age.inMinutes < 5) {
        print('⚠️  Service appears to be running (lock file age: ${age.inMinutes}m)');
        return;
      }
    }
    
    // Lock file is stale, remove it
    await lockFile.delete();
    print('🗑️  Removed stale lock file');
  }
  
  // Start the service
  final service = AutoPushService();
  await service.start();
}

void main(List<String> args) async {
  await bootstrapService();
}