import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';

/// Docker integration for Termisol (limited to .233)
/// Provides comprehensive Docker container management
class DockerIntegration {
  static const String _targetHost = '.233';
  late String _dockerHost;
  bool _isConnected = false;
  List<DockerContainer> _containers = [];
  List<DockerImage> _images = [];
  List<DockerNetwork> _networks = [];
  List<DockerVolume> _volumes = [];
  
  final StreamController<DockerEvent> _eventController = StreamController<DockerEvent>.broadcast();

  Stream<DockerEvent> get events => _eventController.stream;
  bool get isConnected => _isConnected;
  List<DockerContainer> get containers => _containers;
  List<DockerImage> get images => _images;
  List<DockerNetwork> get networks => _networks;
  List<DockerVolume> get volumes => _volumes;

  Future<void> initialize({String? host}) async {
    _dockerHost = host ?? _targetHost;
    
    try {
      // Test Docker connection
      final result = await _runDockerCommand(['--version']);
      if (result.exitCode == 0) {
        _isConnected = true;
        await _loadDockerData();
        _eventController.add(DockerEvent(
          type: DockerEventType.connected,
          message: 'Connected to Docker daemon on $_dockerHost',
        ));
        debugPrint('🐳 Docker Integration initialized for $_dockerHost');
      } else {
        throw Exception('Docker daemon not running or not accessible');
      }
    } catch (e) {
      _isConnected = false;
      _eventController.add(DockerEvent(
        type: DockerEventType.error,
        message: 'Failed to connect to Docker: $e',
      ));
      debugPrint('❌ Failed to initialize Docker Integration: $e');
      rethrow;
    }
  }

  Future<void> _loadDockerData() async {
    await Future.wait([
      _loadContainers(),
      _loadImages(),
      _loadNetworks(),
      _loadVolumes(),
    ]);
  }

  Future<void> _loadContainers() async {
    try {
      final result = await _runDockerCommand([
        'ps', '-a', 
        '--format', '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}'
      ]);
      
      if (result.exitCode == 0) {
        _containers = _parseContainers(result.stdout.toString());
      }
    } catch (e) {
      debugPrint('Failed to load containers: $e');
    }
  }

  Future<void> _loadImages() async {
    try {
      final result = await _runDockerCommand([
        'images',
        '--format', '{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}'
      ]);
      
      if (result.exitCode == 0) {
        _images = _parseImages(result.stdout.toString());
      }
    } catch (e) {
      debugPrint('Failed to load images: $e');
    }
  }

  Future<void> _loadNetworks() async {
    try {
      final result = await _runDockerCommand([
        'network', 'ls',
        '--format', '{{.ID}}|{{.Name}}|{{.Driver}}|{{.Scope}}'
      ]);
      
      if (result.exitCode == 0) {
        _networks = _parseNetworks(result.stdout.toString());
      }
    } catch (e) {
      debugPrint('Failed to load networks: $e');
    }
  }

  Future<void> _loadVolumes() async {
    try {
      final result = await _runDockerCommand([
        'volume', 'ls',
        '--format', '{{.Name}}|{{.Driver}}'
      ]);
      
      if (result.exitCode == 0) {
        _volumes = _parseVolumes(result.stdout.toString());
      }
    } catch (e) {
      debugPrint('Failed to load volumes: $e');
    }
  }

  Future<ProcessResult> _runDockerCommand(List<String> args) async {
    return await run('docker', args);
  }

  List<DockerContainer> _parseContainers(String output) {
    final containers = <DockerContainer>[];
    final lines = output.split('\n');
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
      if (parts.length >= 6) {
        containers.add(DockerContainer(
          id: parts[0],
          name: parts[1],
          image: parts[2],
          status: parts[3],
          ports: parts[4],
          createdAt: DateTime.tryParse(parts[5]) ?? DateTime.now(),
        ));
      }
    }
    
    return containers;
  }

  List<DockerImage> _parseImages(String output) {
    final images = <DockerImage>[];
    final lines = output.split('\n');
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
      if (parts.length >= 5) {
        images.add(DockerImage(
          id: parts[0],
          repository: parts[1],
          tag: parts[2],
          size: parts[3],
          createdAt: DateTime.tryParse(parts[4]) ?? DateTime.now(),
        ));
      }
    }
    
    return images;
  }

  List<DockerNetwork> _parseNetworks(String output) {
    final networks = <DockerNetwork>[];
    final lines = output.split('\n');
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
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
  }

  List<DockerVolume> _parseVolumes(String output) {
    final volumes = <DockerVolume>[];
    final lines = output.split('\n');
    
    for (final line in lines) {
      if (line.isEmpty) continue;
      
      final parts = line.split('|');
      if (parts.length >= 2) {
        volumes.add(DockerVolume(
          name: parts[0],
          driver: parts[1],
        ));
      }
    }
    
    return volumes;
  }

  // Container operations
  Future<DockerCommandResult> startContainer(String containerId) async {
    try {
      final result = await _runDockerCommand(['start', containerId]);
      await _loadContainers();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.container_started,
        message: 'Container $containerId started',
        data: {'containerId': containerId},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> stopContainer(String containerId) async {
    try {
      final result = await _runDockerCommand(['stop', containerId]);
      await _loadContainers();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.container_stopped,
        message: 'Container $containerId stopped',
        data: {'containerId': containerId},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> restartContainer(String containerId) async {
    try {
      final result = await _runDockerCommand(['restart', containerId]);
      await _loadContainers();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.container_restarted,
        message: 'Container $containerId restarted',
        data: {'containerId': containerId},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> removeContainer(String containerId, {bool force = false}) async {
    try {
      final args = ['rm'];
      if (force) args.add('-f');
      args.add(containerId);
      
      final result = await _runDockerCommand(args);
      await _loadContainers();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.container_removed,
        message: 'Container $containerId removed',
        data: {'containerId': containerId, 'force': force},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> execInContainer(String containerId, String command) async {
    try {
      final result = await _runDockerCommand(['exec', containerId, 'sh', '-c', command]);
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<String> getContainerLogs(String containerId, {int lines = 100}) async {
    try {
      final result = await _runDockerCommand(['logs', '--tail', lines.toString(), containerId]);
      return result.stdout.toString();
    } catch (e) {
      return 'Failed to get logs: $e';
    }
  }

  Future<String> getContainerStats(String containerId) async {
    try {
      final result = await _runDockerCommand(['stats', '--no-stream', '--format', 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}', containerId]);
      return result.stdout.toString();
    } catch (e) {
      return 'Failed to get stats: $e';
    }
  }

  // Image operations
  Future<DockerCommandResult> pullImage(String imageName) async {
    try {
      final result = await _runDockerCommand(['pull', imageName]);
      await _loadImages();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.image_pulled,
        message: 'Image $imageName pulled',
        data: {'imageName': imageName},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> removeImage(String imageId, {bool force = false}) async {
    try {
      final args = ['rmi'];
      if (force) args.add('-f');
      args.add(imageId);
      
      final result = await _runDockerCommand(args);
      await _loadImages();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.image_removed,
        message: 'Image $imageId removed',
        data: {'imageId': imageId, 'force': force},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> buildImage(String dockerfilePath, String imageName, {String? context}) async {
    try {
      final args = ['build'];
      if (context != null) {
        args.addAll(['-f', dockerfilePath, context]);
      } else {
        args.addAll(['-f', dockerfilePath, '.']);
      }
      args.addAll(['-t', imageName]);
      
      final result = await _runDockerCommand(args);
      await _loadImages();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.image_built,
        message: 'Image $imageName built',
        data: {'imageName': imageName, 'dockerfilePath': dockerfilePath},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Network operations
  Future<DockerCommandResult> createNetwork(String networkName, {String? driver}) async {
    try {
      final args = ['network', 'create'];
      if (driver != null) {
        args.addAll(['-d', driver]);
      }
      args.add(networkName);
      
      final result = await _runDockerCommand(args);
      await _loadNetworks();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.network_created,
        message: 'Network $networkName created',
        data: {'networkName': networkName, 'driver': driver},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> removeNetwork(String networkName) async {
    try {
      final result = await _runDockerCommand(['network', 'rm', networkName]);
      await _loadNetworks();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.network_removed,
        message: 'Network $networkName removed',
        data: {'networkName': networkName},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Volume operations
  Future<DockerCommandResult> createVolume(String volumeName) async {
    try {
      final result = await _runDockerCommand(['volume', 'create', volumeName]);
      await _loadVolumes();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.volume_created,
        message: 'Volume $volumeName created',
        data: {'volumeName': volumeName},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DockerCommandResult> removeVolume(String volumeName) async {
    try {
      final result = await _runDockerCommand(['volume', 'rm', volumeName]);
      await _loadVolumes();
      
      _eventController.add(DockerEvent(
        type: DockerEventType.volume_removed,
        message: 'Volume $volumeName removed',
        data: {'volumeName': volumeName},
      ));
      
      return DockerCommandResult(
        success: result.exitCode == 0,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } catch (e) {
      return DockerCommandResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Utility methods
  Future<void> refresh() async {
    if (_isConnected) {
      await _loadDockerData();
      _eventController.add(DockerEvent(
        type: DockerEventType.refreshed,
        message: 'Docker data refreshed',
      ));
    }
  }

  DockerStatistics getStatistics() {
    return DockerStatistics(
      totalContainers: _containers.length,
      runningContainers: _containers.where((c) => c.status.contains('Up')).length,
      stoppedContainers: _containers.where((c) => c.status.contains('Exited')).length,
      totalImages: _images.length,
      totalNetworks: _networks.length,
      totalVolumes: _volumes.length,
      host: _dockerHost,
    );
  }

  Future<void> dispose() async {
    _eventController.close();
    debugPrint('🐳 Docker Integration disposed');
  }
}

// Data classes
class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String status;
  final String ports;
  final DateTime createdAt;

  DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.ports,
    required this.createdAt,
  });

  bool get isRunning => status.contains('Up');
  String get shortId => id.substring(0, 12);
}

class DockerImage {
  final String id;
  final String repository;
  final String tag;
  final String size;
  final DateTime createdAt;

  DockerImage({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    required this.createdAt,
  });

  String get fullName => '$repository:$tag';
  String get shortId => id.substring(0, 12);
}

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

  String get shortId => id.substring(0, 12);
}

class DockerVolume {
  final String name;
  final String driver;

  DockerVolume({
    required this.name,
    required this.driver,
  });
}

class DockerCommandResult {
  final bool success;
  final String? stdout;
  final String? stderr;
  final String? error;

  DockerCommandResult({
    required this.success,
    this.stdout,
    this.stderr,
    this.error,
  });
}

class DockerStatistics {
  final int totalContainers;
  final int runningContainers;
  final int stoppedContainers;
  final int totalImages;
  final int totalNetworks;
  final int totalVolumes;
  final String host;

  DockerStatistics({
    required this.totalContainers,
    required this.runningContainers,
    required this.stoppedContainers,
    required this.totalImages,
    required this.totalNetworks,
    required this.totalVolumes,
    required this.host,
  });
}

enum DockerEventType {
  connected,
  container_started,
  container_stopped,
  container_restarted,
  container_removed,
  image_pulled,
  image_removed,
  image_built,
  network_created,
  network_removed,
  volume_created,
  volume_removed,
  refreshed,
  error,
}

class DockerEvent {
  final DockerEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  DockerEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Docker integration widget
class DockerIntegrationWidget extends StatefulWidget {
  final Function(DockerCommandResult)? onOperationComplete;

  const DockerIntegrationWidget({
    super.key,
    this.onOperationComplete,
  });

  @override
  State<DockerIntegrationWidget> createState() => _DockerIntegrationWidgetState();
}

class _DockerIntegrationWidgetState extends State<DockerIntegrationWidget> {
  final DockerIntegration _docker = DockerIntegration();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeDocker();
  }

  Future<void> _initializeDocker() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _docker.initialize(host: '.233');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    await _docker.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Docker Error',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeDocker,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          // Statistics bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              children: [
                Icon(Icons.dock, color: Colors.blue[400]),
                const SizedBox(width: 12),
                Text(
                  'Docker (.233)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, color: Colors.grey[400]),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Tab bar
          Container(
            color: Colors.grey[800],
            child: const TabBar(
              tabs: [
                Tab(text: 'Containers', icon: Icon(Icons.inventory_2)),
                Tab(text: 'Images', icon: Icon(Icons.image)),
                Tab(text: 'Networks', icon: Icon(Icons.hub)),
                Tab(text: 'Volumes', icon: Icon(Icons.storage)),
              ],
              labelColor: Colors.grey[400],
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Colors.blue,
            ),
          ),
          
          // Tab views
          Expanded(
            child: TabBarView(
              children: [
                _buildContainersTab(),
                _buildImagesTab(),
                _buildNetworksTab(),
                _buildVolumesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContainersTab() {
    final containers = _docker.containers;
    
    return Column(
      children: [
        // Container actions
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showRunContainerDialog(),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run Container'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Container list
        Expanded(
          child: ListView.builder(
            itemCount: containers.length,
            itemBuilder: (context, index) {
              final container = containers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: container.isRunning ? Colors.green : Colors.grey,
                  child: Icon(
                    container.isRunning ? Icons.play_arrow : Icons.stop,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                title: Text(
                  container.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      container.image,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    Text(
                      container.status,
                      style: TextStyle(
                        color: container.isRunning ? Colors.green : Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: container.isRunning ? 'stop' : 'start',
                      child: Row(
                        children: [
                          Icon(
                            container.isRunning ? Icons.stop : Icons.play_arrow,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(container.isRunning ? 'Stop' : 'Start'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'restart',
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, size: 16),
                          SizedBox(width: 8),
                          Text('Restart'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logs',
                      child: const Row(
                        children: [
                          Icon(Icons.list_alt, size: 16),
                          SizedBox(width: 8),
                          Text('Logs'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'stats',
                      child: const Row(
                        children: [
                          Icon(Icons.speed, size: 16),
                          SizedBox(width: 8),
                          Text('Stats'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'exec',
                      child: const Row(
                        children: [
                          Icon(Icons.terminal, size: 16),
                          SizedBox(width: 8),
                          Text('Exec'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: const Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Remove', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    switch (action) {
                      case 'start':
                        _docker.startContainer(container.id);
                        break;
                      case 'stop':
                        _docker.stopContainer(container.id);
                        break;
                      case 'restart':
                        _docker.restartContainer(container.id);
                        break;
                      case 'logs':
                        _showContainerLogs(container);
                        break;
                      case 'stats':
                        _showContainerStats(container);
                        break;
                      case 'exec':
                        _showExecDialog(container);
                        break;
                      case 'remove':
                        _removeContainer(container);
                        break;
                    }
                  },
                ),
                onTap: () => _showContainerDetails(container),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImagesTab() {
    final images = _docker.images;
    
    return Column(
      children: [
        // Image actions
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showPullImageDialog(),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Pull Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showBuildImageDialog(),
                  icon: const Icon(Icons.build, size: 16),
                  label: const Text('Build Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Image list
        Expanded(
          child: ListView.builder(
            itemCount: images.length,
            itemBuilder: (context, index) {
              final image = images[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[700],
                  child: const Icon(Icons.image, color: Colors.white, size: 16),
                ),
                title: Text(
                  image.fullName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Size: ${image.size}',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    Text(
                      'ID: ${image.shortId}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: const Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Remove', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'remove') {
                      _removeImage(image);
                    }
                  },
                ),
                onTap: () => _showImageDetails(image),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNetworksTab() {
    final networks = _docker.networks;
    
    return Column(
      children: [
        // Network actions
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateNetworkDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Network'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Network list
        Expanded(
          child: ListView.builder(
            itemCount: networks.length,
            itemBuilder: (context, index) {
              final network = networks[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple[700],
                  child: const Icon(Icons.hub, color: Colors.white, size: 16),
                ),
                title: Text(
                  network.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver: ${network.driver}',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    Text(
                      'Scope: ${network.scope}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: const Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Remove', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'remove') {
                      _removeNetwork(network);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVolumesTab() {
    final volumes = _docker.volumes;
    
    return Column(
      children: [
        // Volume actions
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateVolumeDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Volume'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Volume list
        Expanded(
          child: ListView.builder(
            itemCount: volumes.length,
            itemBuilder: (context, index) {
              final volume = volumes[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal[700],
                  child: const Icon(Icons.storage, color: Colors.white, size: 16),
                ),
                title: Text(
                  volume.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Driver: ${volume.driver}',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: const Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Remove', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'remove') {
                      _removeVolume(volume);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Dialog methods
  Future<void> _showRunContainerDialog() async {
    // Implementation for run container dialog
  }

  Future<void> _showPullImageDialog() async {
    // Implementation for pull image dialog
  }

  Future<void> _showBuildImageDialog() async {
    // Implementation for build image dialog
  }

  Future<void> _showCreateNetworkDialog() async {
    // Implementation for create network dialog
  }

  Future<void> _showCreateVolumeDialog() async {
    // Implementation for create volume dialog
  }

  Future<void> _showContainerDetails(DockerContainer container) async {
    // Implementation for container details
  }

  Future<void> _showImageDetails(DockerImage image) async {
    // Implementation for image details
  }

  Future<void> _showContainerLogs(DockerContainer container) async {
    final logs = await _docker.getContainerLogs(container.id);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logs: ${container.name}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showContainerStats(DockerContainer container) async {
    final stats = await _docker.getContainerStats(container.id);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stats: ${container.name}'),
        content: SelectableText(
          stats,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExecDialog(DockerContainer container) async {
    final controller = TextEditingController();
    final command = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Exec in ${container.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Command',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Execute'),
          ),
        ],
      ),
    );

    if (command != null && command.isNotEmpty) {
      final result = await _docker.execInContainer(container.id, command);
      if (widget.onOperationComplete != null) {
        widget.onOperationComplete!(DockerCommandResult(
          success: result.success,
          stdout: result.stdout,
          stderr: result.stderr,
        ));
      }
    }
  }

  Future<void> _removeContainer(DockerContainer container) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Container'),
        content: Text('Are you sure you want to remove container "${container.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _docker.removeContainer(container.id, force: true);
    }
  }

  Future<void> _removeImage(DockerImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Image'),
        content: Text('Are you sure you want to remove image "${image.fullName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _docker.removeImage(image.id, force: true);
    }
  }

  Future<void> _removeNetwork(DockerNetwork network) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Network'),
        content: Text('Are you sure you want to remove network "${network.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _docker.removeNetwork(network.name);
    }
  }

  Future<void> _removeVolume(DockerVolume volume) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Volume'),
        content: Text('Are you sure you want to remove volume "${volume.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _docker.removeVolume(volume.name);
    }
  }
}
