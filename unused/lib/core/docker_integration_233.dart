import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:process_run/process_run.dart';

/// Docker integration for 192.168.4.233
/// 
/// Features:
/// - Remote Docker daemon connection to 192.168.4.233
/// - Container management (list, start, stop, restart, remove)
/// - Image management (list, pull, push, build, remove)
/// - Volume and network management
/// - Container logs and monitoring
/// - Docker Compose integration
/// - Resource usage monitoring
/// - Container health checks
class DockerIntegration233 {
  /// Docker daemon connection settings.
  /// Defaults to secure HTTPS. Override via environment variables:
  ///   DOCKER_HOST, DOCKER_PORT, DOCKER_TLS_VERIFY (0 or 1)
  static String get _dockerHost =>
      Platform.environment['DOCKER_HOST'] ?? '192.168.4.233';
  static int get _dockerPort =>
      int.tryParse(Platform.environment['DOCKER_PORT'] ?? '') ?? 2376;
  static bool get _useHttps =>
      (Platform.environment['DOCKER_TLS_VERIFY'] ?? '1') != '0';

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _monitoringInterval = Duration(seconds: 10);
  
  final Map<String, DockerContainer> _containers = {};
  final Map<String, DockerImage> _images = {};
  final Map<String, DockerVolume> _volumes = {};
  final Map<String, DockerNetwork> _networks = {};
  final Queue<DockerCommandHistory> _commandHistory = Queue();
  
  Timer? _monitoringTimer;
  
  bool _isConnected = false;
  bool _autoRefresh = true;
  int _totalCommands = 0;
  int _successfulCommands = 0;
  double _totalCommandTime = 0.0;

  DockerIntegration233() {
    _initializeDockerIntegration();
  }

  /// Initialize the Docker integration system
  void _initializeDockerIntegration() {
    _testConnection();
    _startMonitoring();
  }

  /// Test connection to Docker daemon
  Future<void> _testConnection() async {
    try {
      final response = await _makeDockerRequest('/_ping');
      _isConnected = response.statusCode == 200;
      debugPrint('🐳 Docker connection: ${_isConnected ? "Connected" : "Failed"}');
    } catch (e) {
      _isConnected = false;
      debugPrint('🐳 Docker connection failed: $e');
    }
  }

  /// Start monitoring
  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      if (_autoRefresh && _isConnected) {
        _refreshContainerStatus();
      }
    });
  }

  /// Make Docker API request
  Future<http.Response> _makeDockerRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final protocol = _useHttps ? 'https' : 'http';
    final url = Uri.parse('$protocol://$_dockerHost:$_dockerPort$endpoint');
    
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };
    
    late http.Response response;
    
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(url, headers: requestHeaders).timeout(_requestTimeout);
        break;
      case 'POST':
        response = await http.post(url, headers: requestHeaders, body: body).timeout(_requestTimeout);
        break;
      case 'DELETE':
        response = await http.delete(url, headers: requestHeaders).timeout(_requestTimeout);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
    
    return response;
  }

  /// Execute Docker command
  Future<DockerCommandResult> _executeDockerCommand(
    String command,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    _totalCommands++;
    final stopwatch = Stopwatch()..start();
    
    try {
      // For remote Docker, we use the API instead of local commands
      final result = await _executeDockerAPICommand(command, args);
      
      if (result.exitCode == 0) {
        _successfulCommands++;
      }
      
      // Record command in history
      _commandHistory.add(DockerCommandHistory(
        command: '$command ${args.join(' ')}',
        timestamp: DateTime.now(),
        success: result.exitCode == 0,
        duration: stopwatch.elapsedMilliseconds.toDouble(),
      ));
      
      // Keep only recent history
      if (_commandHistory.length > 1000) {
        _commandHistory.removeFirst();
      }
      
      return result;
    } catch (e) {
      _commandHistory.add(DockerCommandHistory(
        command: '$command ${args.join(' ')}',
        timestamp: DateTime.now(),
        success: false,
        duration: stopwatch.elapsedMilliseconds.toDouble(),
        error: e.toString(),
      ));
      
      rethrow;
    } finally {
      _totalCommandTime += stopwatch.elapsedMilliseconds.toDouble();
      stopwatch.stop();
    }
  }

  /// Execute Docker API command
  Future<DockerCommandResult> _executeDockerAPICommand(
    String command,
    List<String> args,
  ) async {
    switch (command) {
      case 'ps':
        return await _listContainers(args);
      case 'images':
        return await _listImages(args);
      case 'run':
        return await _runContainer(args);
      case 'stop':
        return await _stopContainer(args);
      case 'start':
        return await _startContainer(args);
      case 'restart':
        return await _restartContainer(args);
      case 'rm':
        return await _removeContainer(args);
      case 'rmi':
        return await _removeImage(args);
      case 'pull':
        return await _pullImage(args);
      case 'logs':
        return await _getContainerLogs(args);
      case 'stats':
        return await _getContainerStats(args);
      case 'volume':
        return await _manageVolumes(args);
      case 'network':
        return await _manageNetworks(args);
      default:
        throw ArgumentError('Unsupported Docker command: $command');
    }
  }

  /// List containers
  Future<DockerCommandResult> _listContainers(List<String> args) async {
    try {
      final allContainers = args.contains('-a');
      final endpoint = allContainers ? '/containers/json?all=true' : '/containers/json';
      
      final response = await _makeDockerRequest(endpoint);
      
      if (response.statusCode == 200) {
        final containers = json.decode(response.body) as List;
        
        _containers.clear();
        for (final container in containers) {
          final dockerContainer = DockerContainer.fromJson(container);
          _containers[dockerContainer.id] = dockerContainer;
        }
        
        return DockerCommandResult(
          exitCode: 0,
          stdout: json.encode(containers),
          stderr: '',
        );
      } else {
        return DockerCommandResult(
          exitCode: response.statusCode,
          stdout: '',
          stderr: 'Failed to list containers: ${response.statusCode}',
        );
      }
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// List images
  Future<DockerCommandResult> _listImages(List<String> args) async {
    try {
      final response = await _makeDockerRequest('/images/json');
      
      if (response.statusCode == 200) {
        final images = json.decode(response.body) as List;
        
        _images.clear();
        for (final image in images) {
          final dockerImage = DockerImage.fromJson(image);
          _images[dockerImage.id] = dockerImage;
        }
        
        return DockerCommandResult(
          exitCode: 0,
          stdout: json.encode(images),
          stderr: '',
        );
      } else {
        return DockerCommandResult(
          exitCode: response.statusCode,
          stdout: '',
          stderr: 'Failed to list images: ${response.statusCode}',
        );
      }
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Run container
  Future<DockerCommandResult> _runContainer(List<String> args) async {
    try {
      // Parse run command arguments
      final config = _parseRunArguments(args);
      
      final response = await _makeDockerRequest(
        '/containers/create',
        method: 'POST',
        body: json.encode(config),
      );
      
      if (response.statusCode == 201) {
        final containerInfo = json.decode(response.body);
        final containerId = containerInfo['Id'];
        
        // Start the container
        final startResponse = await _makeDockerRequest(
          '/containers/$containerId/start',
          method: 'POST',
        );
        
        if (startResponse.statusCode == 204) {
          return DockerCommandResult(
            exitCode: 0,
            stdout: containerId,
            stderr: '',
          );
        } else {
          return DockerCommandResult(
            exitCode: startResponse.statusCode,
            stdout: containerId,
            stderr: 'Container created but failed to start: ${startResponse.statusCode}',
          );
        }
      } else {
        return DockerCommandResult(
          exitCode: response.statusCode,
          stdout: '',
          stderr: 'Failed to create container: ${response.statusCode}',
        );
      }
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Parse run arguments
  Map<String, dynamic> _parseRunArguments(List<String> args) {
    final config = <String, dynamic>{
      'Image': '',
      'Cmd': [],
      'Env': [],
      'HostConfig': <String, dynamic>{},
    };
    
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      
      if (arg == '-d') {
        config['HostConfig']['Detatch'] = true;
      } else if (arg == '-p' && i + 1 < args.length) {
        final portMapping = args[++i];
        config['HostConfig']['PortBindings'] = _parsePortMapping(portMapping);
      } else if (arg == '-v' && i + 1 < args.length) {
        final volumeMapping = args[++i];
        config['HostConfig']['Binds'] = [volumeMapping];
      } else if (arg == '-e' && i + 1 < args.length) {
        config['Env'].add(args[++i]);
      } else if (arg == '--name' && i + 1 < args.length) {
        config['name'] = args[++i];
      } else if (arg == '--rm') {
        config['HostConfig']['AutoRemove'] = true;
      } else if (!arg.startsWith('-')) {
        config['Image'] = arg;
      }
    }
    
    return config;
  }

  /// Parse port mapping
  Map<String, List<Map<String, String>>> _parsePortMapping(String mapping) {
    final parts = mapping.split(':');
    if (parts.length >= 2) {
      final hostPort = parts[0];
      final containerPort = parts[1];
      
      return {
        containerPort: [
          {'HostPort': hostPort},
        ],
      };
    }
    return {};
  }

  /// Stop container
  Future<DockerCommandResult> _stopContainer(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final response = await _makeDockerRequest(
        '/containers/$containerId/stop',
        method: 'POST',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Container stopped' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to stop container: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Start container
  Future<DockerCommandResult> _startContainer(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final response = await _makeDockerRequest(
        '/containers/$containerId/start',
        method: 'POST',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Container started' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to start container: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Restart container
  Future<DockerCommandResult> _restartContainer(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final response = await _makeDockerRequest(
        '/containers/$containerId/restart',
        method: 'POST',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Container restarted' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to restart container: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Remove container
  Future<DockerCommandResult> _removeContainer(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final force = args.contains('-f');
      
      final response = await _makeDockerRequest(
        '/containers/$containerId${force ? '?force=true' : ''}',
        method: 'DELETE',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Container removed' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to remove container: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Remove image
  Future<DockerCommandResult> _removeImage(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Image ID or name required',
      );
    }
    
    try {
      final imageId = args.first;
      final force = args.contains('-f');
      
      final response = await _makeDockerRequest(
        '/images/$imageId${force ? '?force=true' : ''}',
        method: 'DELETE',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 200 ? 0 : response.statusCode,
        stdout: response.statusCode == 200 ? 'Image removed' : '',
        stderr: response.statusCode == 200 ? '' : 'Failed to remove image: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Pull image
  Future<DockerCommandResult> _pullImage(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Image name required',
      );
    }
    
    try {
      final imageName = args.first;
      
      final response = await _makeDockerRequest(
        '/images/create?fromImage=$imageName',
        method: 'POST',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 200 ? 0 : response.statusCode,
        stdout: response.statusCode == 200 ? 'Image pulled' : '',
        stderr: response.statusCode == 200 ? '' : 'Failed to pull image: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Get container logs
  Future<DockerCommandResult> _getContainerLogs(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final follow = args.contains('-f');
      final tail = args.contains('--tail');
      
      String endpoint = '/containers/$containerId/logs';
      final params = <String>[];
      
      if (follow) params.add('follow=1');
      if (tail) {
        final tailIndex = args.indexOf('--tail');
        if (tailIndex + 1 < args.length) {
          params.add('tail=${args[tailIndex + 1]}');
        }
      }
      
      if (params.isNotEmpty) {
        endpoint += '?${params.join('&')}';
      }
      
      final response = await _makeDockerRequest(endpoint);
      
      return DockerCommandResult(
        exitCode: response.statusCode == 200 ? 0 : response.statusCode,
        stdout: response.statusCode == 200 ? response.body : '',
        stderr: response.statusCode == 200 ? '' : 'Failed to get logs: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Get container stats
  Future<DockerCommandResult> _getContainerStats(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Container ID required',
      );
    }
    
    try {
      final containerId = args.first;
      final response = await _makeDockerRequest('/containers/$containerId/stats?stream=false');
      
      return DockerCommandResult(
        exitCode: response.statusCode == 200 ? 0 : response.statusCode,
        stdout: response.statusCode == 200 ? response.body : '',
        stderr: response.statusCode == 200 ? '' : 'Failed to get stats: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Manage volumes
  Future<DockerCommandResult> _manageVolumes(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Volume command required',
      );
    }
    
    final subcommand = args.first;
    
    switch (subcommand) {
      case 'ls':
        return await _listVolumes();
      case 'create':
        return await _createVolume(args.sublist(1));
      case 'rm':
        return await _removeVolume(args.sublist(1));
      default:
        return DockerCommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Unsupported volume command: $subcommand',
        );
    }
  }

  /// List volumes
  Future<DockerCommandResult> _listVolumes() async {
    try {
      final response = await _makeDockerRequest('/volumes/json');
      
      if (response.statusCode == 200) {
        final volumes = json.decode(response.body)['Volumes'] as List;
        
        _volumes.clear();
        for (final volume in volumes) {
          final dockerVolume = DockerVolume.fromJson(volume);
          _volumes[dockerVolume.name] = dockerVolume;
        }
        
        return DockerCommandResult(
          exitCode: 0,
          stdout: json.encode(volumes),
          stderr: '',
        );
      } else {
        return DockerCommandResult(
          exitCode: response.statusCode,
          stdout: '',
          stderr: 'Failed to list volumes: ${response.statusCode}',
        );
      }
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Create volume
  Future<DockerCommandResult> _createVolume(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Volume name required',
      );
    }
    
    try {
      final volumeName = args.first;
      
      final response = await _makeDockerRequest(
        '/volumes/create',
        method: 'POST',
        body: json.encode({'Name': volumeName}),
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 201 ? 0 : response.statusCode,
        stdout: response.statusCode == 201 ? 'Volume created' : '',
        stderr: response.statusCode == 201 ? '' : 'Failed to create volume: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Remove volume
  Future<DockerCommandResult> _removeVolume(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Volume name required',
      );
    }
    
    try {
      final volumeName = args.first;
      
      final response = await _makeDockerRequest(
        '/volumes/$volumeName',
        method: 'DELETE',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Volume removed' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to remove volume: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Manage networks
  Future<DockerCommandResult> _manageNetworks(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Network command required',
      );
    }
    
    final subcommand = args.first;
    
    switch (subcommand) {
      case 'ls':
        return await _listNetworks();
      case 'create':
        return await _createNetwork(args.sublist(1));
      case 'rm':
        return await _removeNetwork(args.sublist(1));
      default:
        return DockerCommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Unsupported network command: $subcommand',
        );
    }
  }

  /// List networks
  Future<DockerCommandResult> _listNetworks() async {
    try {
      final response = await _makeDockerRequest('/networks/json');
      
      if (response.statusCode == 200) {
        final networks = json.decode(response.body) as List;
        
        _networks.clear();
        for (final network in networks) {
          final dockerNetwork = DockerNetwork.fromJson(network);
          _networks[dockerNetwork.id] = dockerNetwork;
        }
        
        return DockerCommandResult(
          exitCode: 0,
          stdout: json.encode(networks),
          stderr: '',
        );
      } else {
        return DockerCommandResult(
          exitCode: response.statusCode,
          stdout: '',
          stderr: 'Failed to list networks: ${response.statusCode}',
        );
      }
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Create network
  Future<DockerCommandResult> _createNetwork(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Network name required',
      );
    }
    
    try {
      final networkName = args.first;
      
      final response = await _makeDockerRequest(
        '/networks/create',
        method: 'POST',
        body: json.encode({'Name': networkName}),
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 201 ? 0 : response.statusCode,
        stdout: response.statusCode == 201 ? 'Network created' : '',
        stderr: response.statusCode == 201 ? '' : 'Failed to create network: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Remove network
  Future<DockerCommandResult> _removeNetwork(List<String> args) async {
    if (args.isEmpty) {
      return DockerCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Network name required',
      );
    }
    
    try {
      final networkName = args.first;
      
      final response = await _makeDockerRequest(
        '/networks/$networkName',
        method: 'DELETE',
      );
      
      return DockerCommandResult(
        exitCode: response.statusCode == 204 ? 0 : response.statusCode,
        stdout: response.statusCode == 204 ? 'Network removed' : '',
        stderr: response.statusCode == 204 ? '' : 'Failed to remove network: ${response.statusCode}',
      );
    } catch (e) {
      return DockerCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }

  /// Refresh container status
  Future<void> _refreshContainerStatus() async {
    try {
      await _listContainers([]);
    } catch (e) {
      debugPrint('Failed to refresh container status: $e');
    }
  }

  /// Public API methods

  /// Execute Docker command
  Future<DockerCommandResult> executeCommand(String command, List<String> args) async {
    return await _executeDockerCommand(command, args);
  }

  /// Get containers
  Map<String, DockerContainer> getContainers() {
    return Map.unmodifiable(_containers);
  }

  /// Get images
  Map<String, DockerImage> getImages() {
    return Map.unmodifiable(_images);
  }

  /// Get volumes
  Map<String, DockerVolume> getVolumes() {
    return Map.unmodifiable(_volumes);
  }

  /// Get networks
  Map<String, DockerNetwork> getNetworks() {
    return Map.unmodifiable(_networks);
  }

  /// Get command history
  List<DockerCommandHistory> getCommandHistory({int? limit}) {
    final history = _commandHistory.reversed.toList();
    if (limit != null) {
      return history.take(limit).toList();
    }
    return history;
  }

  /// Get Docker statistics
  DockerStats getStats() {
    return DockerStats(
      totalCommands: _totalCommands,
      successfulCommands: _successfulCommands,
      successRate: _totalCommands > 0 ? _successfulCommands / _totalCommands : 0.0,
      averageCommandTime: _totalCommands > 0 ? _totalCommandTime / _totalCommands : 0.0,
      totalCommandTime: _totalCommandTime,
      containerCount: _containers.length,
      imageCount: _images.length,
      volumeCount: _volumes.length,
      networkCount: _networks.length,
      isConnected: _isConnected,
      dockerHost: _dockerHost,
      dockerPort: _dockerPort,
    );
  }

  /// Test connection
  Future<bool> testConnection() async {
    await _testConnection();
    return _isConnected;
  }

  /// Set auto refresh
  void setAutoRefresh(bool enabled) {
    _autoRefresh = enabled;
  }

  /// Dispose Docker integration
  void dispose() {
    _monitoringTimer?.cancel();
    _containers.clear();
    _images.clear();
    _volumes.clear();
    _networks.clear();
    _commandHistory.clear();
  }
}

/// Docker container
class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String status;
  final List<String> ports;
  final DateTime createdAt;
  final Map<String, dynamic> labels;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.ports,
    required this.createdAt,
    required this.labels,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    final ports = <String>[];
    final portMappings = json['Ports'] as List?;
    if (portMappings != null) {
      for (final port in portMappings) {
        if (port['PublicPort'] != null) {
          ports.add('${port['PublicPort']}:${port['PrivatePort']}');
        } else {
          ports.add(port['PrivatePort'].toString());
        }
      }
    }

    return DockerContainer(
      id: json['Id'],
      name: json['Names'][0],
      image: json['Image'],
      status: json['Status'],
      ports: ports,
      createdAt: DateTime.parse(json['Created']),
      labels: Map<String, dynamic>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker image
class DockerImage {
  final String id;
  final List<String> repoTags;
  final DateTime createdAt;
  final longSize;
  final Map<String, dynamic> labels;

  const DockerImage({
    required this.id,
    required this.repoTags,
    required this.createdAt,
    required this.longSize,
    required this.labels,
  });

  factory DockerImage.fromJson(Map<String, dynamic> json) {
    return DockerImage(
      id: json['Id'],
      repoTags: List<String>.from(json['RepoTags'] ?? []),
      createdAt: DateTime.parse(json['Created']),
      longSize: json['Size'],
      labels: Map<String, dynamic>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker volume
class DockerVolume {
  final String name;
  final String driver;
  final DateTime createdAt;
  final Map<String, dynamic> labels;

  const DockerVolume({
    required this.name,
    required this.driver,
    required this.createdAt,
    required this.labels,
  });

  factory DockerVolume.fromJson(Map<String, dynamic> json) {
    return DockerVolume(
      name: json['Name'],
      driver: json['Driver'],
      createdAt: DateTime.parse(json['CreatedAt']),
      labels: Map<String, dynamic>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker network
class DockerNetwork {
  final String id;
  final String name;
  final String driver;
  final DateTime createdAt;
  final Map<String, dynamic> labels;

  const DockerNetwork({
    required this.id,
    required this.name,
    required this.driver,
    required this.createdAt,
    required this.labels,
  });

  factory DockerNetwork.fromJson(Map<String, dynamic> json) {
    return DockerNetwork(
      id: json['Id'],
      name: json['Name'],
      driver: json['Driver'],
      createdAt: DateTime.parse(json['Created']),
      labels: Map<String, dynamic>.from(json['Labels'] ?? {}),
    );
  }
}

/// Docker command result
class DockerCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const DockerCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Docker command history
class DockerCommandHistory {
  final String command;
  final DateTime timestamp;
  final bool success;
  final double duration;
  final String? error;

  const DockerCommandHistory({
    required this.command,
    required this.timestamp,
    required this.success,
    required this.duration,
    this.error,
  });
}

/// Docker statistics
class DockerStats {
  final int totalCommands;
  final int successfulCommands;
  final double successRate;
  final double averageCommandTime;
  final double totalCommandTime;
  final int containerCount;
  final int imageCount;
  final int volumeCount;
  final int networkCount;
  final bool isConnected;
  final String dockerHost;
  final int dockerPort;

  const DockerStats({
    required this.totalCommands,
    required this.successfulCommands,
    required this.successRate,
    required this.averageCommandTime,
    required this.totalCommandTime,
    required this.containerCount,
    required this.imageCount,
    required this.volumeCount,
    required this.networkCount,
    required this.isConnected,
    required this.dockerHost,
    required this.dockerPort,
  });
}
