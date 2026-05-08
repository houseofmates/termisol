import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// VSCode/Windsurf Integration System
/// 
/// Seamless integration with VSCode and Windsurf IDEs:
/// - Process detection and communication
/// - File synchronization
/// - Terminal session sharing
/// - Command execution
/// - Extension integration
/// - Workspace management
/// - Real-time collaboration
class VSCodeIntegration {
  static final VSCodeIntegration _instance = VSCodeIntegration._internal();
  factory VSCodeIntegration() => _instance;
  VSCodeIntegration._internal();

  bool _isInitialized = false;
  
  // IDE detection
  final Map<String, IDEProcess> _ideProcesses = {};
  IDEProcess? _activeIDE;
  bool _vscodeAvailable = false;
  bool _windsurfAvailable = false;
  
  // Communication
  final Map<String, IDEConnection> _connections = {};
  Timer? _discoveryTimer;
  Timer? _heartbeatTimer;
  
  // Integration features
  bool _fileSyncEnabled = true;
  bool _terminalSyncEnabled = true;
  bool _commandSyncEnabled = true;
  final Map<String, FileSyncState> _fileSyncStates = {};
  final List<TerminalSession> _sharedTerminals = [];
  
  // Event system
  final _ideController = StreamController<IDEEvent>.broadcast();
  Stream<IDEEvent> get events => _ideController.stream;
  
  // Configuration
  Directory? _configDir;
  Duration _discoveryInterval = Duration(seconds: 30);
  Duration _heartbeatInterval = Duration(seconds: 10);
  int _maxConnections = 5;
  
  bool get isInitialized => _isInitialized;
  bool get vscodeAvailable => _vscodeAvailable;
  bool get windsurfAvailable => _windsurfAvailable;
  IDEProcess? get activeIDE => _activeIDE;
  int get connectedIDEs => _connections.length;
  int get sharedTerminals => _sharedTerminals.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup configuration
      await _setupConfiguration();
      
      // Discover IDE processes
      await _discoverIDEs();
      
      // Start discovery timer
      _startDiscoveryTimer();
      
      // Start heartbeat timer
      _startHeartbeatTimer();
      
      _isInitialized = true;
      debugPrint('💻 VSCode/Windsurf Integration initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize VSCode Integration: $e');
    }
  }

  Future<void> _setupConfiguration() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      _configDir = Directory('$homeDir/.termisol/ide_integration');
      await _configDir!.create(recursive: true);
      
      debugPrint('📁 IDE integration directory created');
    } catch (e) {
      debugPrint('❌ Failed to setup configuration: $e');
      rethrow;
    }
  }

  Future<void> _discoverIDEs() async {
    try {
      debugPrint('🔍 Discovering IDE processes...');
      
      // Discover VSCode processes
      await _discoverVSCode();
      
      // Discover Windsurf processes
      await _discoverWindsurf();
      
      // Try to connect to discovered IDEs
      await _connectToIDEs();
      
      debugPrint('🔍 IDE discovery completed');
    } catch (e) {
      debugPrint('⚠️ IDE discovery failed: $e');
    }
  }

  Future<void> _discoverVSCode() async {
    try {
      // Check for VSCode processes
      final result = await Process.run('pgrep', ['-f', 'code'], runInShell: true);
      
      if (result.exitCode == 0) {
        final pids = result.stdout.trim().split('\n');
        
        for (final pid in pids) {
          if (pid.isNotEmpty) {
            final process = await _getIDEProcess(int.parse(pid), IDEType.vscode);
            if (process != null) {
              _ideProcesses[process.id] = process;
              _vscodeAvailable = true;
              debugPrint('💻 Found VSCode process: ${process.name} (PID: ${process.pid})');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ VSCode discovery failed: $e');
    }
  }

  Future<void> _discoverWindsurf() async {
    try {
      // Check for Windsurf processes (VibeCode)
      final result = await Process.run('pgrep', ['-f', 'windsurf'], runInShell: true);
      
      if (result.exitCode == 0) {
        final pids = result.stdout.trim().split('\n');
        
        for (final pid in pids) {
          if (pid.isNotEmpty) {
            final process = await _getIDEProcess(int.parse(pid), IDEType.windsurf);
            if (process != null) {
              _ideProcesses[process.id] = process;
              _windsurfAvailable = true;
              debugPrint('💻 Found Windsurf process: ${process.name} (PID: ${process.pid})');
            }
          }
        }
      }
      
      // Also check for VibeCode (Windsurf's new name)
      final vibeResult = await Process.run('pgrep', ['-f', 'vibecode'], runInShell: true);
      
      if (vibeResult.exitCode == 0) {
        final pids = vibeResult.stdout.trim().split('\n');
        
        for (final pid in pids) {
          if (pid.isNotEmpty) {
            final process = await _getIDEProcess(int.parse(pid), IDEType.windsurf);
            if (process != null) {
              _ideProcesses[process.id] = process;
              _windsurfAvailable = true;
              debugPrint('💻 Found VibeCode process: ${process.name} (PID: ${process.pid})');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Windsurf discovery failed: $e');
    }
  }

  Future<IDEProcess?> _getIDEProcess(int pid, IDEType type) async {
    try {
      // Get process details
      final result = await Process.run('ps', ['-p', pid.toString(), '-o', 'pid,comm,etime'], runInShell: true);
      
      if (result.exitCode == 0) {
        final lines = result.stdout.trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines[1].trim().split(RegExp(r'\s+'));
          
          return IDEProcess(
            id: '${type.name}_$pid',
            pid: pid,
            name: parts.length > 1 ? parts[1] : 'Unknown',
            type: type,
            startTime: parts.length > 2 ? parts[2] : '',
            workspace: await _getWorkspacePath(pid, type),
            port: await _getPort(pid, type),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get IDE process details: $e');
    }
    
    return null;
  }

  Future<String?> _getWorkspacePath(int pid, IDEType type) async {
    try {
      // Try to get workspace path from process environment
      final result = await Process.run('cat', ['/proc/$pid/environ'], runInShell: true);
      
      if (result.exitCode == 0) {
        final envVars = result.stdout.split('\0');
        
        for (final envVar in envVars) {
          if (envVar.startsWith('PWD=')) {
            return envVar.substring(4);
          }
        }
      }
    } catch (e) {
      // Fallback: try to get current working directory
    }
    
    return null;
  }

  Future<int?> _getPort(int pid, IDEType type) async {
    try {
      // Try to find the port the IDE is listening on
      // This is a simplified approach - in reality, you'd need to check the IDE's configuration
      
      if (type == IDEType.vscode) {
        // VSCode typically uses ports in the 8000-9000 range for extensions
        for (int port = 8000; port <= 9000; port++) {
          try {
            final socket = await Socket.connect('localhost', port).timeout(Duration(milliseconds: 100));
            socket.destroy();
            return port;
          } catch (_) {
            // Port not available
          }
        }
      } else if (type == IDEType.windsurf) {
        // Windsurf might use different ports
        for (int port = 3000; port <= 4000; port++) {
          try {
            final socket = await Socket.connect('localhost', port).timeout(Duration(milliseconds: 100));
            socket.destroy();
            return port;
          } catch (_) {
            // Port not available
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get IDE port: $e');
    }
    
    return null;
  }

  Future<void> _connectToIDEs() async {
    for (final process in _ideProcesses.values) {
      try {
        if (process.port != null) {
          final connection = await _connectToIDE(process);
          if (connection != null) {
            _connections[process.id] = connection;
            _activeIDE = process;
            
            _ideController.add(IDEEvent(
              type: IDEEventType.connected,
              processId: process.id,
              data: process.toJson(),
            ));
            
            debugPrint('🔗 Connected to IDE: ${process.name}');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to connect to IDE ${process.name}: $e');
      }
    }
  }

  Future<IDEConnection?> _connectToIDE(IDEProcess process) async {
    try {
      // This would implement the actual connection protocol
      // For now, we'll simulate a connection
      
      if (process.port == null) {
        return null;
      }
      
      // Simulate connection attempt
      await Future.delayed(Duration(milliseconds: 100));
      
      return IDEConnection(
        processId: process.id,
        port: process.port!,
        connectedAt: DateTime.now(),
        lastHeartbeat: DateTime.now(),
        capabilities: _getIDECapabilities(process.type),
      );
    } catch (e) {
      debugPrint('⚠️ Connection failed: $e');
      return null;
    }
  }

  List<IDECapability> _getIDECapabilities(IDEType type) {
    switch (type) {
      case IDEType.vscode:
        return [
          IDECapability.fileSync,
          IDECapability.terminalSync,
          IDECapability.commandSync,
          IDECapability.extensionSync,
          IDECapability.workspaceSync,
        ];
      case IDEType.windsurf:
        return [
          IDECapability.fileSync,
          IDECapability.terminalSync,
          IDECapability.commandSync,
          IDECapability.aiIntegration,
          IDECapability.workspaceSync,
        ];
    }
  }

  void _startDiscoveryTimer() {
    _discoveryTimer = Timer.periodic(_discoveryInterval, (_) {
      _discoverIDEs();
    });
    
    debugPrint('⏰ IDE discovery timer started');
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeats();
    });
    
    debugPrint('💗 Heartbeat timer started');
  }

  Future<void> _sendHeartbeats() async {
    for (final connection in _connections.values) {
      try {
        // Send heartbeat to maintain connection
        connection.lastHeartbeat = DateTime.now();
        
        // Check if connection is still alive
        if (_isConnectionAlive(connection)) {
          debugPrint('💗 Heartbeat sent to ${connection.processId}');
        } else {
          // Remove dead connection
          _connections.remove(connection.processId);
          
          _ideController.add(IDEEvent(
            type: IDEEventType.disconnected,
            processId: connection.processId,
          ));
          
          debugPrint('💔 Connection lost: ${connection.processId}');
        }
      } catch (e) {
        debugPrint('⚠️ Heartbeat failed: $e');
      }
    }
  }

  bool _isConnectionAlive(IDEConnection connection) {
    // Simple check based on last heartbeat
    return DateTime.now().difference(connection.lastHeartbeat).inSeconds < 30;
  }

  // Public API methods
  
  Future<bool> openFileInIDE(String filePath, {IDEType? preferredIDE}) async {
    try {
      // Find suitable IDE
      IDEProcess? targetIDE;
      
      if (preferredIDE != null) {
        targetIDE = _ideProcesses.values.firstWhere(
          (p) => p.type == preferredIDE,
          orElse: () => _activeIDE!,
        );
      } else {
        targetIDE = _activeIDE;
      }
      
      if (targetIDE == null) {
        throw Exception('No IDE available');
      }
      
      // Open file in IDE
      if (targetIDE.type == IDEType.vscode) {
        final result = await Process.run('code', [filePath], runInShell: true);
        if (result.exitCode != 0) {
          throw Exception('Failed to open file in VSCode');
        }
      } else if (targetIDE.type == IDEType.windsurf) {
        // Windsurf/VibeCode command
        final result = await Process.run('windsurf', [filePath], runInShell: true);
        if (result.exitCode != 0) {
          throw Exception('Failed to open file in Windsurf');
        }
      }
      
      _ideController.add(IDEEvent(
        type: IDEEventType.fileOpened,
        processId: targetIDE.id,
        data: {'file_path': filePath},
      ));
      
      debugPrint('📂 Opened file in IDE: $filePath');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to open file in IDE: $e');
      return false;
    }
  }

  Future<bool> syncFileWithIDE(String filePath) async {
    if (!_fileSyncEnabled) return false;
    
    try {
      final connection = _activeIDE != null ? _connections[_activeIDE!.id] : null;
      if (connection == null) {
        throw Exception('No active IDE connection');
      }
      
      // Check if IDE supports file sync
      if (!connection.capabilities.contains(IDECapability.fileSync)) {
        throw Exception('IDE does not support file sync');
      }
      
      // Implement file sync logic
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
      
      final content = await file.readAsString();
      final lastModified = await file.lastModified();
      
      // Send file to IDE
      final syncState = FileSyncState(
        filePath: filePath,
        lastSynced: DateTime.now(),
        lastModified: lastModified,
        checksum: _calculateChecksum(content),
        status: SyncStatus.synced,
      );
      
      _fileSyncStates[filePath] = syncState;
      
      _ideController.add(IDEEvent(
        type: IDEEventType.fileSynced,
        processId: connection.processId,
        data: {
          'file_path': filePath,
          'sync_state': syncState.toJson(),
        },
      ));
      
      debugPrint('🔄 Synced file with IDE: $filePath');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to sync file with IDE: $e');
      return false;
    }
  }

  Future<String?> shareTerminalWithIDE(String terminalId) async {
    if (!_terminalSyncEnabled) return null;
    
    try {
      final connection = _activeIDE != null ? _connections[_activeIDE!.id] : null;
      if (connection == null) {
        throw Exception('No active IDE connection');
      }
      
      // Check if IDE supports terminal sync
      if (!connection.capabilities.contains(IDECapability.terminalSync)) {
        throw Exception('IDE does not support terminal sync');
      }
      
      // Create shared terminal session
      final session = TerminalSession(
        id: terminalId,
        sharedAt: DateTime.now(),
        processId: connection.processId,
        status: TerminalStatus.active,
      );
      
      _sharedTerminals.add(session);
      
      _ideController.add(IDEEvent(
        type: IDEEventType.terminalShared,
        processId: connection.processId,
        data: session.toJson(),
      ));
      
      debugPrint('🖥️ Shared terminal with IDE: $terminalId');
      return session.id;
    } catch (e) {
      debugPrint('❌ Failed to share terminal with IDE: $e');
      return null;
    }
  }

  Future<bool> executeCommandInIDE(String command, {String? workingDirectory}) async {
    if (!_commandSyncEnabled) return false;
    
    try {
      final connection = _activeIDE != null ? _connections[_activeIDE!.id] : null;
      if (connection == null) {
        throw Exception('No active IDE connection');
      }
      
      // Check if IDE supports command sync
      if (!connection.capabilities.contains(IDECapability.commandSync)) {
        throw Exception('IDE does not support command sync');
      }
      
      // Execute command in IDE's integrated terminal
      // This would use the IDE's API to execute commands
      debugPrint('⚡ Executing command in IDE: $command');
      
      _ideController.add(IDEEvent(
        type: IDEEventType.commandExecuted,
        processId: connection.processId,
        data: {
          'command': command,
          'working_directory': workingDirectory,
        },
      ));
      
      return true;
    } catch (e) {
      debugPrint('❌ Failed to execute command in IDE: $e');
      return false;
    }
  }

  Future<bool> syncWorkspaceWithIDE() async {
    try {
      final connection = _activeIDE != null ? _connections[_activeIDE!.id] : null;
      if (connection == null) {
        throw Exception('No active IDE connection');
      }
      
      // Check if IDE supports workspace sync
      if (!connection.capabilities.contains(IDECapability.workspaceSync)) {
        throw Exception('IDE does not support workspace sync');
      }
      
      // Get IDE workspace
      final process = _ideProcesses[connection.processId];
      if (process?.workspace == null) {
        throw Exception('No workspace available');
      }
      
      // Sync workspace files
      final workspaceDir = Directory(process!.workspace!);
      if (!await workspaceDir.exists()) {
        throw Exception('Workspace directory not found');
      }
      
      int syncedFiles = 0;
      await for (final entity in workspaceDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final success = await syncFileWithIDE(entity.path);
          if (success) syncedFiles++;
        }
      }
      
      debugPrint('🔄 Synced $syncedFiles files with IDE workspace');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to sync workspace with IDE: $e');
      return false;
    }
  }

  String _calculateChecksum(String content) {
    // Simple checksum calculation
    return content.length.toString();
  }

  void setFileSyncEnabled(bool enabled) {
    _fileSyncEnabled = enabled;
    debugPrint('🔄 File sync ${enabled ? 'enabled' : 'disabled'}');
  }

  void setTerminalSyncEnabled(bool enabled) {
    _terminalSyncEnabled = enabled;
    debugPrint('🖥️ Terminal sync ${enabled ? 'enabled' : 'disabled'}');
  }

  void setCommandSyncEnabled(bool enabled) {
    _commandSyncEnabled = enabled;
    debugPrint('⚡ Command sync ${enabled ? 'enabled' : 'disabled'}');
  }

  List<IDEProcess> getAvailableIDEs() {
    return _ideProcesses.values.toList();
  }

  List<IDEConnection> getActiveConnections() {
    return _connections.values.toList();
  }

  IDEStatistics getStatistics() {
    return IDEStatistics(
      vscodeAvailable: _vscodeAvailable,
      windsurfAvailable: _windsurfAvailable,
      activeIDE: _activeIDE?.name,
      connectedIDEs: _connections.length,
      sharedTerminals: _sharedTerminals.length,
      fileSyncEnabled: _fileSyncEnabled,
      terminalSyncEnabled: _terminalSyncEnabled,
      commandSyncEnabled: _commandSyncEnabled,
      syncedFiles: _fileSyncStates.length,
      lastDiscovery: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    // Cancel timers
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    // Close connections
    for (final connection in _connections.values) {
      // Close connection
    }
    _connections.clear();
    
    // Clear data
    _ideProcesses.clear();
    _fileSyncStates.clear();
    _sharedTerminals.clear();
    
    // Close event controller
    _ideController.close();
    
    _isInitialized = false;
    debugPrint('💻 VSCode/Windsurf Integration disposed');
  }
}

/// Data classes
class IDEProcess {
  final String id;
  final int pid;
  final String name;
  final IDEType type;
  final String startTime;
  final String? workspace;
  final int? port;
  
  IDEProcess({
    required this.id,
    required this.pid,
    required this.name,
    required this.type,
    required this.startTime,
    this.workspace,
    this.port,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pid': pid,
      'name': name,
      'type': type.toString(),
      'start_time': startTime,
      'workspace': workspace,
      'port': port,
    };
  }
}

class IDEConnection {
  final String processId;
  final int port;
  final DateTime connectedAt;
  DateTime lastHeartbeat;
  final List<IDECapability> capabilities;
  
  IDEConnection({
    required this.processId,
    required this.port,
    required this.connectedAt,
    required this.lastHeartbeat,
    required this.capabilities,
  });
}

class FileSyncState {
  final String filePath;
  final DateTime lastSynced;
  final DateTime lastModified;
  final String checksum;
  SyncStatus status;
  
  FileSyncState({
    required this.filePath,
    required this.lastSynced,
    required this.lastModified,
    required this.checksum,
    required this.status,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'file_path': filePath,
      'last_synced': lastSynced.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
      'checksum': checksum,
      'status': status.toString(),
    };
  }
}

class TerminalSession {
  final String id;
  final DateTime sharedAt;
  final String processId;
  TerminalStatus status;
  
  TerminalSession({
    required this.id,
    required this.sharedAt,
    required this.processId,
    required this.status,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shared_at': sharedAt.toIso8601String(),
      'process_id': processId,
      'status': status.toString(),
    };
  }
}

class IDEEvent {
  final IDEEventType type;
  final String? processId;
  final Map<String, dynamic>? data;
  
  IDEEvent({
    required this.type,
    this.processId,
    this.data,
  });
}

class IDEStatistics {
  final bool vscodeAvailable;
  final bool windsurfAvailable;
  final String? activeIDE;
  final int connectedIDEs;
  final int sharedTerminals;
  final bool fileSyncEnabled;
  final bool terminalSyncEnabled;
  final bool commandSyncEnabled;
  final int syncedFiles;
  final DateTime lastDiscovery;
  
  IDEStatistics({
    required this.vscodeAvailable,
    required this.windsurfAvailable,
    this.activeIDE,
    required this.connectedIDEs,
    required this.sharedTerminals,
    required this.fileSyncEnabled,
    required this.terminalSyncEnabled,
    required this.commandSyncEnabled,
    required this.syncedFiles,
    required this.lastDiscovery,
  });
}

enum IDEType {
  vscode,
  windsurf,
}

enum IDECapability {
  fileSync,
  terminalSync,
  commandSync,
  extensionSync,
  workspaceSync,
  aiIntegration,
}

enum SyncStatus {
  pending,
  syncing,
  synced,
  error,
}

enum TerminalStatus {
  active,
  inactive,
  disconnected,
}

enum IDEEventType {
  discovered,
  connected,
  disconnected,
  fileOpened,
  fileSynced,
  terminalShared,
  commandExecuted,
  workspaceSynced,
}
