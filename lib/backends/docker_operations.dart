import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Docker Operations System
/// 
/// Provides comprehensive Docker container and image management
/// with real-time monitoring, resource tracking, and automation
class DockerOperations {
  final Map<String, DockerContainer> _containers = {};
  final Map<String, DockerImage> _images = {};
  final Map<String, DockerVolume> _volumes = {};
  final Map<String, DockerNetwork> _networks = {};
  Timer? _monitoringTimer;
  String? _dockerHost;
  String? _dockerCertPath;
  
  static const Duration _monitoringInterval = Duration(seconds: 10);
  static const Duration _operationTimeout = Duration(minutes: 5);
  
  /// Initialize Docker operations system
  Future<void> initialize({
    String? dockerHost,
    String? dockerCertPath,
  }) async {
    try {
      _dockerHost = dockerHost ?? Platform.environment['DOCKER_HOST'] ?? 'unix:///var/run/docker.sock';
      _dockerCertPath = dockerCertPath;
      
      // Test Docker connection
      final isConnected = await _testDockerConnection();
      if (!isConnected) {
        throw Exception('Failed to connect to Docker daemon');
      }
      
      // Load initial data
      await _loadContainers();
      await _loadImages();
      await _loadVolumes();
      await _loadNetworks();
      
      // Start monitoring
      _monitoringTimer = Timer.periodic(_monitoringInterval, (_) => _updateSystemStatus());
      
      debugPrint('🐳 Docker Operations initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Docker Operations: $e');
      rethrow;
    }
  }
  
  /// Create a new container
  Future<ContainerResult> createContainer(ContainerConfig config) async {
    try {
      // Validate configuration
      _validateContainerConfig(config);
      
      // Check if image exists
      if (!_images.containsKey(config.image)) {
        final pullResult = await pullImage(config.image);
        if (!pullResult.success) {
          return ContainerResult(
            success: false,
            error: 'Failed to pull image ${config.image}: ${pullResult.error}',
          );
        }
      }
      
      // Create container
      final containerId = await _createContainer(config);
      if (containerId == null) {
        return ContainerResult(
          success: false,
          error: 'Failed to create container',
        );
      }
      
      // Start container if requested
      if (config.autoStart) {
        final startResult = await startContainer(containerId);
        if (!startResult.success) {
          return ContainerResult(
            success: false,
            error: 'Container created but failed to start: ${startResult.error}',
          );
        }
      }
      
      // Refresh container list
      await _loadContainers();
      
      debugPrint('🐳 Created container: $containerId');
      
      return ContainerResult(
        success: true,
        containerId: containerId,
      );
    } catch (e) {
      debugPrint('❌ Failed to create container: $e');
      return ContainerResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Start a container
  Future<ContainerResult> startContainer(String containerId) async {
    try {
      final response = await _dockerRequest('POST', '/containers/$containerId/start');
      
      if (response.statusCode == 204) {
        await _loadContainers();
        debugPrint('🐳 Started container: $containerId');
        return ContainerResult(success: true, containerId: containerId);
      } else {
        return ContainerResult(
          success: false,
          error: 'Failed to start container: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to start container $containerId: $e');
      return ContainerResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Stop a container
  Future<ContainerResult> stopContainer(String containerId, {Duration? timeout}) async {
    try {
      final timeoutSeconds = timeout?.inSeconds ?? 10;
      final response = await _dockerRequest(
        'POST',
        '/containers/$containerId/stop',
        queryParameters: {'t': timeoutSeconds.toString()},
      );
      
      if (response.statusCode == 204) {
        await _loadContainers();
        debugPrint('🐳 Stopped container: $containerId');
        return ContainerResult(success: true, containerId: containerId);
      } else {
        return ContainerResult(
          success: false,
          error: 'Failed to stop container: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to stop container $containerId: $e');
      return ContainerResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Restart a container
  Future<ContainerResult> restartContainer(String containerId, {Duration? timeout}) async {
    try {
      final timeoutSeconds = timeout?.inSeconds ?? 10;
      final response = await _dockerRequest(
        'POST',
        '/containers/$containerId/restart',
        queryParameters: {'t': timeoutSeconds.toString()},
      );
      
      if (response.statusCode == 204) {
        await _loadContainers();
        debugPrint('🐳 Restarted container: $containerId');
        return ContainerResult(success: true, containerId: containerId);
      } else {
        return ContainerResult(
          success: false,
          error: 'Failed to restart container: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to restart container $containerId: $e');
      return ContainerResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Remove a container
  Future<ContainerResult> removeContainer(String containerId, {bool force = false}) async {
    try {
      final response = await _dockerRequest(
        'DELETE',
        '/containers/$containerId',
        queryParameters: {'force': force.toString()},
      );
      
      if (response.statusCode == 204) {
        _containers.remove(containerId);
        debugPrint('🐳 Removed container: $containerId');
        return ContainerResult(success: true, containerId: containerId);
      } else {
        return ContainerResult(
          success: false,
          error: 'Failed to remove container: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to remove container $containerId: $e');
      return ContainerResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Pull an image
  Future<ImageResult> pullImage(String imageName) async {
    try {
      final response = await _dockerRequest('POST', '/images/create', queryParameters: {
        'fromImage': imageName,
      });
      
      if (response.statusCode == 200) {
        await _loadImages();
        debugPrint('🐳 Pulled image: $imageName');
        return ImageResult(success: true, imageName: imageName);
      } else {
        return ImageResult(
          success: false,
          error: 'Failed to pull image: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to pull image $imageName: $e');
      return ImageResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Get container logs
  Future<String> getContainerLogs(String containerId, {
    int? tail,
    bool follow = false,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final queryParameters = <String, String>{};
      if (tail != null) queryParameters['tail'] = tail.toString();
      if (follow) queryParameters['follow'] = 'true';
      if (since != null) queryParameters['since'] = since.millisecondsSinceEpoch.toString();
      if (until != null) queryParameters['until'] = until.millisecondsSinceEpoch.toString();
      
      final response = await _dockerRequest('GET', '/containers/$containerId/logs', queryParameters: queryParameters);
      
      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to get logs: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Failed to get logs for container $containerId: $e');
      rethrow;
    }
  }
  
  /// Get container statistics
  Future<ContainerStats> getContainerStats(String containerId) async {
    try {
      final response = await _dockerRequest('GET', '/containers/$containerId/stats', queryParameters: {'stream': 'false'});
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ContainerStats.fromJson(data);
      } else {
        throw Exception('Failed to get stats: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Failed to get stats for container $containerId: $e');
      rethrow;
    }
  }
  
  /// Execute command in container
  Future<ExecResult> execCommand(String containerId, List<String> command, {
    bool attachStdout = true,
    bool attachStderr = true,
  }) async {
    try {
      // Create exec instance
      final createResponse = await _dockerRequest('POST', '/containers/$containerId/exec', body: json.encode({
        'Cmd': command,
        'AttachStdout': attachStdout,
        'AttachStderr': attachStderr,
      }));
      
      if (createResponse.statusCode != 201) {
        return ExecResult(
          success: false,
          error: 'Failed to create exec instance: ${createResponse.body}',
        );
      }
      
      final execData = json.decode(createResponse.body) as Map<String, dynamic>;
      final execId = execData['Id'] as String;
      
      // Start exec
      final startResponse = await _dockerRequest('POST', '/exec/$execId/start', body: json.encode({
        'Detach': false,
        'Tty': false,
      }));
      
      if (startResponse.statusCode == 200) {
        return ExecResult(
          success: true,
          output: startResponse.body,
          exitCode: 0,
        );
      } else {
        return ExecResult(
          success: false,
          error: 'Failed to start exec: ${startResponse.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to exec command in container $containerId: $e');
      return ExecResult(
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Get all containers
  List<DockerContainer> getContainers({bool all = false}) {
    return _containers.values.where((c) => all || c.status != 'exited').toList();
  }
  
  /// Get all images
  List<DockerImage> getImages() {
    return _images.values.toList();
  }
  
  /// Get container by ID
  DockerContainer? getContainer(String containerId) {
    return _containers[containerId];
  }
  
  /// Get image by ID or name
  DockerImage? getImage(String imageId) {
    return _images[imageId];
  }
  
  /// Test Docker connection
  Future<bool> _testDockerConnection() async {
    try {
      final response = await _dockerRequest('GET', '/version');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// Load containers from Docker daemon
  Future<void> _loadContainers() async {
    try {
      final response = await _dockerRequest('GET', '/containers/json?all=true');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        _containers.clear();
        
        for (final item in data) {
          final container = DockerContainer.fromJson(item as Map<String, dynamic>);
          _containers[container.id] = container;
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load containers: $e');
    }
  }
  
  /// Load images from Docker daemon
  Future<void> _loadImages() async {
    try {
      final response = await _dockerRequest('GET', '/images/json');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        _images.clear();
        
        for (final item in data) {
          final image = DockerImage.fromJson(item as Map<String, dynamic>);
          _images[image.id] = image;
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load images: $e');
    }
  }
  
  /// Load volumes from Docker daemon
  Future<void> _loadVolumes() async {
    try {
      final response = await _dockerRequest('GET', '/volumes');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final volumes = data['Volumes'] as List;
        _volumes.clear();
        
        for (final item in volumes) {
          final volume = DockerVolume.fromJson(item as Map<String, dynamic>);
          _volumes[volume.name] = volume;
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load volumes: $e');
    }
  }
  
  /// Load networks from Docker daemon
  Future<void> _loadNetworks() async {
    try {
      final response = await _dockerRequest('GET', '/networks');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        _networks.clear();
        
        for (final item in data) {
          final network = DockerNetwork.fromJson(item as Map<String, dynamic>);
          _networks[network.id] = network;
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load networks: $e');
    }
  }
  
  /// Create container via Docker API
  Future<String?> _createContainer(ContainerConfig config) async {
    try {
      final createData = {
        'Image': config.image,
        'Cmd': config.command,
        'Env': config.environment,
        'ExposedPorts': config.exposedPorts.map((p, v) => MapEntry('$p/tcp', {})),
        'HostConfig': {
          'PortBindings': config.portBindings.map((p, v) => MapEntry('$p/tcp', v)),
          'Mounts': config.mounts.map((m) => {
            'Source': m.source,
            'Target': m.target,
            'Type': m.type,
            'ReadOnly': m.readOnly,
          }).toList(),
          'RestartPolicy': {
            'Name': config.restartPolicy.name.toLowerCase(),
            'MaximumRetryCount': config.restartPolicy.maxRetries,
          },
          'Resources': {
            'Memory': config.memoryLimit,
            'CpuShares': config.cpuShares,
          },
        },
        'Labels': config.labels,
      };
      
      final response = await _dockerRequest('POST', '/containers/create', body: json.encode(createData));
      
      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['Id'] as String;
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('❌ Failed to create container: $e');
      return null;
    }
  }
  
  /// Update system status
  Future<void> _updateSystemStatus() async {
    try {
      await Future.wait([
        _loadContainers(),
        _loadImages(),
      ]);
    } catch (e) {
      debugPrint('❌ Failed to update system status: $e');
    }
  }
  
  /// Make Docker API request
  Future<http.Response> _dockerRequest(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    String? body,
  }) async {
    final uri = _buildDockerUri(path, queryParameters);
    
    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri);
      case 'POST':
        return http.post(uri, body: body);
      case 'DELETE':
        return http.delete(uri);
      case 'PUT':
        return http.put(uri, body: body);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }
  
  /// Build Docker API URI
  Uri _buildDockerUri(String path, Map<String, String>? queryParameters) {
    if (_dockerHost?.startsWith('unix://') == true) {
      // Unix socket - would need special handling
      throw UnimplementedError('Unix socket communication not implemented in this stub');
    } else {
      // TCP connection
      final host = _dockerHost?.replaceFirst('tcp://', '') ?? 'localhost:2375';
      final parts = host.split(':');
      final hostname = parts[0];
      final port = int.tryParse(parts[1]) ?? 2375;
      
      return Uri.http('$hostname:$port', path, queryParameters);
    }
  }
  
  /// Validate container configuration
  void _validateContainerConfig(ContainerConfig config) {
    if (config.image.isEmpty) {
      throw ArgumentError('Image name cannot be empty');
    }
    if (config.name?.isEmpty == true) {
      throw ArgumentError('Container name cannot be empty');
    }
  }
  
  /// Dispose Docker operations
  Future<void> dispose() async {
    try {
      _monitoringTimer?.cancel();
      debugPrint('🐳 Docker Operations disposed');
    } catch (e) {
      debugPrint('❌ Error during disposal: $e');
    }
  }
}

/// Container configuration
class ContainerConfig {
  final String image;
  final String? name;
  final List<String>? command;
  final Map<String, String>? environment;
  final Map<String, List<String>> portBindings;
  final List<Mount> mounts;
  final RestartPolicy restartPolicy;
  final bool autoStart;
  final int? memoryLimit;
  final int? cpuShares;
  final Map<String, String> labels;
  final Map<String, dynamic> exposedPorts;
  
  ContainerConfig({
    required this.image,
    this.name,
    this.command,
    this.environment,
    this.portBindings = const {},
    this.mounts = const [],
    this.restartPolicy = RestartPolicy.no,
    this.autoStart = false,
    this.memoryLimit,
    this.cpuShares,
    this.labels = const {},
    this.exposedPorts = const {},
  });
}

/// Mount configuration
class Mount {
  final String source;
  final String target;
  final String type;
  final bool readOnly;
  
  Mount({
    required this.source,
    required this.target,
    this.type = 'bind',
    this.readOnly = false,
  });
}

/// Restart policy
enum RestartPolicy {
  no,
  onFailure,
  always,
  unlessStopped;
  
  int get maxRetries {
    switch (this) {
      case RestartPolicy.onFailure:
        return 3;
      default:
        return 0;
    }
  }
}

/// Docker container information
class DockerContainer {
  final String id;
  final List<String> names;
  final String image;
  final String status;
  final Map<String, String> ports;
  final DateTime createdAt;
  final Map<String, String> labels;
  
  DockerContainer({
    required this.id,
    required this.names,
    required this.image,
    required this.status,
    required this.ports,
    required this.createdAt,
    required this.labels,
  });
  
  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    return DockerContainer(
      id: json['Id'] as String,
      names: List<String>.from(json['Names'] ?? []),
      image: json['Image'] as String,
      status: json['Status'] as String,
      ports: Map<String, String>.from(json['Ports'] ?? {}),
      createdAt: DateTime.parse(json['Created'] ?? DateTime.now().toIso8601String()),
      labels: Map<String, String>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker image information
class DockerImage {
  final String id;
  final List<String> repoTags;
  final DateTime createdAt;
  final int size;
  final Map<String, String> labels;
  
  DockerImage({
    required this.id,
    required this.repoTags,
    required this.createdAt,
    required this.size,
    required this.labels,
  });
  
  factory DockerImage.fromJson(Map<String, dynamic> json) {
    return DockerImage(
      id: json['Id'] as String,
      repoTags: List<String>.from(json['RepoTags'] ?? []),
      createdAt: DateTime.parse(json['Created'] ?? DateTime.now().toIso8601String()),
      size: json['Size'] as int? ?? 0,
      labels: Map<String, String>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker volume information
class DockerVolume {
  final String name;
  final String driver;
  final String mountpoint;
  final DateTime createdAt;
  final Map<String, String> labels;
  
  DockerVolume({
    required this.name,
    required this.driver,
    required this.mountpoint,
    required this.createdAt,
    required this.labels,
  });
  
  factory DockerVolume.fromJson(Map<String, dynamic> json) {
    return DockerVolume(
      name: json['Name'] as String,
      driver: json['Driver'] as String,
      mountpoint: json['Mountpoint'] as String,
      createdAt: DateTime.parse(json['CreatedAt'] ?? DateTime.now().toIso8601String()),
      labels: Map<String, String>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker network information
class DockerNetwork {
  final String id;
  final String name;
  final String driver;
  final String scope;
  final DateTime createdAt;
  final Map<String, String> labels;
  
  DockerNetwork({
    required this.id,
    required this.name,
    required this.driver,
    required this.scope,
    required this.createdAt,
    required this.labels,
  });
  
  factory DockerNetwork.fromJson(Map<String, dynamic> json) {
    return DockerNetwork(
      id: json['Id'] as String,
      name: json['Name'] as String,
      driver: json['Driver'] as String,
      scope: json['Scope'] as String,
      createdAt: DateTime.parse(json['CreatedAt'] ?? DateTime.now().toIso8601String()),
      labels: Map<String, String>.from(json['Labels'] ?? {}),
    );
  }
}

/// Container statistics
class ContainerStats {
  final String id;
  final double cpuUsage;
  final int memoryUsage;
  final int memoryLimit;
  final double networkRx;
  final double networkTx;
  final double blockRead;
  final double blockWrite;
  
  ContainerStats({
    required this.id,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.memoryLimit,
    required this.networkRx,
    required this.networkTx,
    required this.blockRead,
    required this.blockWrite,
  });
  
  factory ContainerStats.fromJson(Map<String, dynamic> json) {
    // Parse CPU stats
    final cpuStats = json['cpu_stats'] as Map<String, dynamic>? ?? {};
    final preCpuStats = json['precpu_stats'] as Map<String, dynamic>? ?? {};
    final cpuDelta = cpuStats['cpu_usage']['total_usage'] as int? ?? 0;
    final systemCpuDelta = cpuStats['system_cpu_usage'] as int? ?? 0;
    final preSystemCpuDelta = preCpuStats['system_cpu_usage'] as int? ?? 0;
    final cpuUsage = systemCpuDelta > 0 ? (cpuDelta / systemCpuDelta) * 100.0 : 0.0;
    
    // Parse memory stats
    final memoryStats = json['memory_stats'] as Map<String, dynamic>? ?? {};
    final memoryUsage = memoryStats['usage'] as int? ?? 0;
    final memoryLimit = memoryStats['limit'] as int? ?? 0;
    
    // Parse network stats
    final networks = json['networks'] as Map<String, dynamic>? ?? {};
    double networkRx = 0, networkTx = 0;
    for (final network in networks.values) {
      networkRx += (network as Map<String, dynamic>)['rx_bytes'] as int? ?? 0;
      networkTx += network['tx_bytes'] as int? ?? 0;
    }
    
    // Parse block I/O stats
    final blkioStats = json['blkio_stats'] as Map<String, dynamic>? ?? {};
    final ioServiceBytesRecursive = blkioStats['io_service_bytes_recursive'] as List? ?? [];
    double blockRead = 0, blockWrite = 0;
    for (final entry in ioServiceBytesRecursive) {
      final op = entry['op'] as String;
      final value = entry['value'] as int? ?? 0;
      if (op == 'Read') blockRead += value.toDouble();
      if (op == 'Write') blockWrite += value.toDouble();
    }
    
    return ContainerStats(
      id: json['id'] as String,
      cpuUsage: cpuUsage,
      memoryUsage: memoryUsage,
      memoryLimit: memoryLimit,
      networkRx: networkRx,
      networkTx: networkTx,
      blockRead: blockRead,
      blockWrite: blockWrite,
    );
  }
}

/// Container operation result
class ContainerResult {
  final bool success;
  final String? containerId;
  final String? error;
  
  ContainerResult({
    required this.success,
    this.containerId,
    this.error,
  });
}

/// Image operation result
class ImageResult {
  final bool success;
  final String? imageName;
  final String? error;
  
  ImageResult({
    required this.success,
    this.imageName,
    this.error,
  });
}

/// Exec operation result
class ExecResult {
  final bool success;
  final String? output;
  final int? exitCode;
  final String? error;
  
  ExecResult({
    required this.success,
    this.output,
    this.exitCode,
    this.error,
  });
}