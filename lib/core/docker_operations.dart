import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import 'package:ssh/ssh.dart';

/// Docker operations integration for Termisol (server .233)
/// 
/// Features:
/// - Remote Docker management on .233
/// - Container lifecycle management
/// - Image operations
/// - Volume management
/// - Network operations
/// - Docker compose support
/// - Resource monitoring
class DockerOperations {
  static const String _dockerHost = '192.168.4.233';
  static const int _dockerPort = 2375;
  static const String _sshHost = '192.168.4.233';
  static const int _sshPort = 22;
  
  SSHSession? _sshSession;
  bool _isConnected = false;
  final StreamController<DockerEvent> _eventController = StreamController<DockerEvent>.broadcast();
  
  Stream<DockerEvent> get events => _eventController.stream;
  bool get isConnected => _isConnected;
  
  /// Connect to Docker host via SSH
  Future<bool> connect({
    required String username,
    required String passwordOrKey,
    bool useKey = false,
  }) async {
    try {
      _sshSession = SSHSession(
        host: _sshHost,
        port: _sshPort,
        username: username,
        passwordOrKey: passwordOrKey,
        useKey: useKey,
      );
      
      await _sshSession!.connect();
      _isConnected = true;
      
      _eventController.add(DockerEvent(
        type: DockerEventType.connected,
        message: 'Connected to Docker host',
        data: {'host': _dockerHost},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to connect to Docker host: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Execute Docker command via SSH
  Future<DockerCommandResult> _executeDockerCommand(String command) async {
    if (!_isConnected || _sshSession == null) {
      throw Exception('Not connected to Docker host');
    }
    
    try {
      final result = await _sshSession!.execute('docker $command');
      
      return DockerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        success: result.exitCode == 0,
      );
    } catch (e) {
      throw Exception('Failed to execute Docker command: $e');
    }
  }
  
  /// Get list of containers
  Future<List<DockerContainer>> getContainers({bool all = false}) async {
    try {
      final command = all ? 'ps -a --format "{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}\t{{.Ports}}"' 
                           : 'ps --format "{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}\t{{.Ports}}"';
      
      final result = await _executeDockerCommand(command);
      
      final containers = <DockerContainer>[];
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split('\t');
        if (parts.length >= 4) {
          containers.add(DockerContainer(
            id: parts[0],
            image: parts[1],
            status: parts[2],
            name: parts[3],
            ports: parts.length > 4 ? parts[4] : '',
          ));
        }
      }
      
      return containers;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get containers: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Get list of images
  Future<List<DockerImage>> getImages() async {
    try {
      final result = await _executeDockerCommand('images --format "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}"');
      
      final images = <DockerImage>[];
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split('\t');
        if (parts.length >= 4) {
          images.add(DockerImage(
            repository: parts[0],
            tag: parts[1],
            id: parts[2],
            size: parts[3],
            createdAt: parts.length > 4 ? parts[4] : '',
          ));
        }
      }
      
      return images;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get images: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Get container stats
  Future<DockerContainerStats?> getContainerStats(String containerId) async {
    try {
      final result = await _executeDockerCommand('stats $containerId --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}"');
      
      final parts = result.stdout.split('\t');
      if (parts.length >= 5) {
        return DockerContainerStats(
          containerId: containerId,
          cpuPercent: parts[0],
          memoryUsage: parts[1],
          networkIO: parts[2],
          blockIO: parts[3],
          pids: parts[4],
        );
      }
      
      return null;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get container stats: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return null;
    }
  }
  
  /// Start container
  Future<bool> startContainer(String containerId) async {
    try {
      final result = await _executeDockerCommand('start $containerId');
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.container_started,
          message: 'Container started successfully',
          data: {'container': containerId},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to start container: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return false;
    }
  }
  
  /// Stop container
  Future<bool> stopContainer(String containerId) async {
    try {
      final result = await _executeDockerCommand('stop $containerId');
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.container_stopped,
          message: 'Container stopped successfully',
          data: {'container': containerId},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to stop container: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return false;
    }
  }
  
  /// Restart container
  Future<bool> restartContainer(String containerId) async {
    try {
      final result = await _executeDockerCommand('restart $containerId');
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.container_restarted,
          message: 'Container restarted successfully',
          data: {'container': containerId},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to restart container: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return false;
    }
  }
  
  /// Remove container
  Future<bool> removeContainer(String containerId, {bool force = false}) async {
    try {
      final command = force ? 'rm -f $containerId' : 'rm $containerId';
      final result = await _executeDockerCommand(command);
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.container_removed,
          message: 'Container removed successfully',
          data: {'container': containerId, 'force': force},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to remove container: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return false;
    }
  }
  
  /// Pull image
  Future<bool> pullImage(String image) async {
    try {
      final result = await _executeDockerCommand('pull $image');
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.image_pulled,
          message: 'Image pulled successfully',
          data: {'image': image},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to pull image: $e',
        data: {'error': e.toString(), 'image': image},
      ));
      return false;
    }
  }
  
  /// Build image
  Future<bool> buildImage(String dockerfilePath, String tag, {String? buildContext}) async {
    try {
      final context = buildContext ?? '.';
      final command = 'build -t $tag -f $dockerfilePath $context';
      final result = await _executeDockerCommand(command);
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.image_built,
          message: 'Image built successfully',
          data: {'tag': tag, 'dockerfile': dockerfilePath},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to build image: $e',
        data: {'error': e.toString(), 'tag': tag},
      ));
      return false;
    }
  }
  
  /// Remove image
  Future<bool> removeImage(String image, {bool force = false}) async {
    try {
      final command = force ? 'rmi -f $image' : 'rmi $image';
      final result = await _executeDockerCommand(command);
      
      if (result.success) {
        _eventController.add(DockerEvent(
          type: DockerEventType.image_removed,
          message: 'Image removed successfully',
          data: {'image': image, 'force': force},
        ));
        return true;
      }
      
      return false;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to remove image: $e',
        data: {'error': e.toString(), 'image': image},
      ));
      return false;
    }
  }
  
  /// Get container logs
  Future<String> getContainerLogs(String containerId, {int? tail, bool follow = false}) async {
    try {
      var command = 'logs $containerId';
      if (tail != null) command += ' --tail=$tail';
      if (follow) command += ' -f';
      
      final result = await _executeDockerCommand(command);
      return result.stdout;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get container logs: $e',
        data: {'error': e.toString(), 'container': containerId},
      ));
      return '';
    }
  }
  
  /// Execute command in container
  Future<String> execCommand(String containerId, String command) async {
    try {
      final result = await _executeDockerCommand('exec $containerId $command');
      return result.stdout;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to execute command in container: $e',
        data: {'error': e.toString(), 'container': containerId, 'command': command},
      ));
      return '';
    }
  }
  
  /// Get system info
  Future<DockerSystemInfo?> getSystemInfo() async {
    try {
      final result = await _executeDockerCommand('info --format "{{.ServerVersion}}\t{{.NCPU}}\t{{.MemTotal}}\t{{.Architecture}}"');
      
      final parts = result.stdout.split('\t');
      if (parts.length >= 4) {
        return DockerSystemInfo(
          serverVersion: parts[0],
          cpuCount: int.tryParse(parts[1]) ?? 0,
          memoryTotal: parts[2],
          architecture: parts[3],
        );
      }
      
      return null;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get system info: $e',
        data: {'error': e.toString()},
      ));
      return null;
    }
  }
  
  /// Get volumes
  Future<List<DockerVolume>> getVolumes() async {
    try {
      final result = await _executeDockerCommand('volume ls --format "{{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"');
      
      final volumes = <DockerVolume>[];
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split('\t');
        if (parts.length >= 3) {
          volumes.add(DockerVolume(
            name: parts[0],
            driver: parts[1],
            mountpoint: parts[2],
          ));
        }
      }
      
      return volumes;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get volumes: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Get networks
  Future<List<DockerNetwork>> getNetworks() async {
    try {
      final result = await _executeDockerCommand('network ls --format "{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"');
      
      final networks = <DockerNetwork>[];
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.split('\t');
        if (parts.length >= 4) {
          networks.add(DockerNetwork(
            id: parts[0],
            name: parts[1],
            driver: parts[2],
            scope: parts[3],
          ));
        }
      }
      
      return networks;
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to get networks: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  /// Disconnect from Docker host
  Future<void> disconnect() async {
    try {
      if (_sshSession != null) {
        await _sshSession!.disconnect();
        _sshSession = null;
      }
      
      _isConnected = false;
      
      _eventController.add(DockerEvent(
        type: DockerEventType.disconnected,
        message: 'Disconnected from Docker host',
        data: {'host': _dockerHost},
      ));
    } catch (e) {
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to disconnect: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Dispose
  void dispose() {
    disconnect();
    _eventController.close();
  }
}

/// Docker container information
class DockerContainer {
  final String id;
  final String image;
  final String status;
  final String name;
  final String ports;
  
  DockerContainer({
    required this.id,
    required this.image,
    required this.status,
    required this.name,
    required this.ports,
  });
  
  bool get isRunning => status.toLowerCase().contains('up');
  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
}

/// Docker image information
class DockerImage {
  final String repository;
  final String tag;
  final String id;
  final String size;
  final String createdAt;
  
  DockerImage({
    required this.repository,
    required this.tag,
    required this.id,
    required this.size,
    required this.createdAt,
  });
  
  String get fullName => '$repository:$tag';
  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
}

/// Docker container statistics
class DockerContainerStats {
  final String containerId;
  final String cpuPercent;
  final String memoryUsage;
  final String networkIO;
  final String blockIO;
  final String pids;
  
  DockerContainerStats({
    required this.containerId,
    required this.cpuPercent,
    required this.memoryUsage,
    required this.networkIO,
    required this.blockIO,
    required this.pids,
  });
}

/// Docker system information
class DockerSystemInfo {
  final String serverVersion;
  final int cpuCount;
  final String memoryTotal;
  final String architecture;
  
  DockerSystemInfo({
    required this.serverVersion,
    required this.cpuCount,
    required this.memoryTotal,
    required this.architecture,
  });
}

/// Docker volume information
class DockerVolume {
  final String name;
  final String driver;
  final String mountpoint;
  
  DockerVolume({
    required this.name,
    required this.driver,
    required this.mountpoint,
  });
}

/// Docker network information
class DockerNetwork {
  final String id;
  final String name;
  final String driver;
  final String scope;
  
  DockerNetwork({
    required this.id,
    required this.name,
    required this.driver,
    required this.scope,
  });
  
  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
}

/// Docker command result
class DockerCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;
  
  DockerCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.success,
  });
}

/// Docker event types
enum DockerEventType {
  connected,
  disconnected,
  container_started,
  container_stopped,
  container_restarted,
  container_removed,
  image_pulled,
  image_built,
  image_removed,
  error,
}

/// Docker event
class DockerEvent {
  final DockerEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  DockerEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}

/// SSH session for Docker operations
class SSHSession {
  final String host;
  final int port;
  final String username;
  final String passwordOrKey;
  final bool useKey;
  
  SSHSession({
    required this.host,
    required this.port,
    required this.username,
    required this.passwordOrKey,
    required this.useKey,
  });
  
  Future<void> connect() async {
    // In a real implementation, this would establish an SSH connection
    // For now, we'll simulate connection
    await Future.delayed(const Duration(seconds: 1));
  }
  
  Future<SSHCommandResult> execute(String command) async {
    // In a real implementation, this would execute the command via SSH
    // For now, we'll simulate execution
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Simulate different commands
    if (command.contains('ps')) {
      return SSHCommandResult(
        exitCode: 0,
        stdout: 'container1\tubuntu:latest\tUp 2 hours\tmy-container\t80/tcp\ncontainer2\tnginx:latest\tUp 1 hour\tweb-server\t80:8080/tcp',
        stderr: '',
      );
    } else if (command.contains('images')) {
      return SSHCommandResult(
        exitCode: 0,
        stdout: 'ubuntu\tlatest\tsha256:12345\t72.8MB\t2024-01-01\nnginx\tlatest\tsha256:67890\t142MB\t2024-01-02',
        stderr: '',
      );
    } else if (command.contains('start')) {
      return SSHCommandResult(exitCode: 0, stdout: '', stderr: '');
    } else if (command.contains('stop')) {
      return SSHCommandResult(exitCode: 0, stdout: '', stderr: '');
    } else {
      return SSHCommandResult(exitCode: 0, stdout: 'Command executed successfully', stderr: '');
    }
  }
  
  Future<void> disconnect() async {
    // In a real implementation, this would close the SSH connection
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

/// SSH command result
class SSHCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  
  SSHCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}
