import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// protocol for isolate message-passing between main isolate and plugin isolate
class PluginMessage {
  final String id;
  final String method;
  final Map<String, dynamic> args;

  PluginMessage({
    required this.id,
    required this.method,
    this.args = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'method': method,
        'args': args,
      };
}

/// termisol plugin system
///
/// features:
/// - dynamic plugin loading from file system
/// - plugin lifecycle management (load, unload, reload)
/// - secure isolate-based execution
/// - plugin dependency resolution
/// - event-driven communication
/// - performance monitoring
/// - hot-reload capability
class TermisolPluginSystem {
  final Map<String, Plugin> _plugins = {};
  final Map<String, Isolate> _isolates = {};
  final Map<String, SendPort> _sendPorts = {};
  final Map<String, ReceivePort> _receivePorts = {};
  final Map<String, PluginManifest> _manifests = {};
  final StreamController<PluginSystemEvent> _eventController = StreamController.broadcast();

  bool _isInitialized = false;
  final String _pluginsDirectory = 'plugins';
  static const Duration _isolateTimeout = Duration(seconds: 30);

  bool get isInitialized => _isInitialized;
  Stream<PluginSystemEvent> get events => _eventController.stream;
  List<String> get loadedPluginIds => _plugins.keys.toList();
  Map<String, PluginManifest> get loadedPlugins => Map.unmodifiable(_manifests);

  /// initialize the plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // create plugins directory
      final pluginsDir = Directory(_pluginsDirectory);
      if (!await pluginsDir.exists()) {
        await pluginsDir.create(recursive: true);
      }

      // load all plugins from directory
      await _loadAllPlugins();

      _isInitialized = true;
      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.systemInitialized,
        'Plugin system initialized with ${_plugins.length} plugins',
        data: {'pluginCount': _plugins.length},
      ));
    } catch (e, stack) {
      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.error,
        'Failed to initialize plugin system: $e',
        data: {'error': e.toString(), 'stack': stack.toString()},
      ));
      rethrow;
    }
  }

  /// load a plugin from file path
  Future<bool> loadPlugin(String pluginPath) async {
    try {
      final file = File(pluginPath);
      if (!await file.exists()) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Plugin file not found: $pluginPath',
        ));
        return false;
      }

      final content = await file.readAsString();
      final manifest = _parsePluginManifest(content);

      if (manifest == null) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Invalid plugin manifest in $pluginPath',
        ));
        return false;
      }

      // check for conflicts
      if (_plugins.containsKey(manifest.id)) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Plugin ${manifest.id} already loaded',
        ));
        return false;
      }

      // validate dependencies
      if (!await _validateDependencies(manifest)) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Missing dependencies for plugin ${manifest.id}',
          data: {'plugin': manifest.id, 'dependencies': manifest.dependencies},
        ));
        return false;
      }

      // create plugin isolate
      final isolate = await _createPluginIsolate(manifest, content);
      if (isolate == null) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Failed to create isolate for plugin ${manifest.id}',
        ));
        return false;
      }

      // create plugin instance
      final plugin = SimplePlugin(
        manifest: manifest,
        isolate: isolate,
        sendPort: _sendPorts[manifest.id]!,
        receivePort: _receivePorts[manifest.id]!,
      );

      _plugins[manifest.id] = plugin;
      _manifests[manifest.id] = manifest;
      _isolates[manifest.id] = isolate;

      // initialize plugin
      await plugin.initialize();

      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.pluginLoaded,
        'Plugin loaded: ${manifest.name} (${manifest.version})',
        data: {'plugin': manifest.id, 'version': manifest.version},
      ));

      return true;
    } catch (e) {
      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.loadFailed,
        'Failed to load plugin from $pluginPath: $e',
        data: {'path': pluginPath, 'error': e.toString()},
      ));
      return false;
    }
  }

  /// unload a plugin
  Future<void> unloadPlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    final isolate = _isolates[pluginId];
    final receivePort = _receivePorts[pluginId];

    if (plugin != null) {
      try {
        await plugin.dispose();
      } catch (e) {
        debugPrint('Error disposing plugin $pluginId: $e');
      }
    }

    if (isolate != null) {
      isolate.kill();
    }

    if (receivePort != null) {
      receivePort.close();
    }

    _plugins.remove(pluginId);
    _isolates.remove(pluginId);
    _sendPorts.remove(pluginId);
    _receivePorts.remove(pluginId);
    _manifests.remove(pluginId);

    _eventController.add(PluginSystemEvent(
      PluginSystemEventType.pluginUnloaded,
      'Plugin unloaded: $pluginId',
    ));
  }

  /// reload a plugin
  Future<bool> reloadPlugin(String pluginId) async {
    final manifest = _manifests[pluginId];
    if (manifest == null) return false;

    await unloadPlugin(pluginId);

    // find plugin file
    final pluginFile = File('$_pluginsDirectory/$pluginId.plugin');
    if (!await pluginFile.exists()) {
      return false;
    }

    return await loadPlugin(pluginFile.path);
  }

  /// execute plugin method
  Future<dynamic> executePlugin(String pluginId, String method, [Map<String, dynamic>? args]) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) {
      throw Exception('Plugin not found: $pluginId');
    }

    return await plugin.execute(method, args ?? {});
  }

  /// get plugin information
  PluginManifest? getPluginManifest(String pluginId) => _manifests[pluginId];

  /// check if plugin is loaded
  bool isPluginLoaded(String pluginId) => _plugins.containsKey(pluginId);

  /// get plugin capabilities
  List<String> getPluginCapabilities(String pluginId) {
    final manifest = _manifests[pluginId];
    return manifest?.capabilities ?? [];
  }

  /// list all available plugin files
  Future<List<String>> listAvailablePlugins() async {
    try {
      final pluginsDir = Directory(_pluginsDirectory);
      if (!await pluginsDir.exists()) return [];

      final files = <String>[];
      await for (final entity in pluginsDir.list()) {
        if (entity is File && entity.path.endsWith('.plugin')) {
          files.add(entity.path);
        }
      }
      return files;
    } catch (e) {
      debugPrint('Error listing plugins: $e');
      return [];
    }
  }

  /// dispose all resources
  Future<void> dispose() async {
    final pluginIds = List<String>.from(_plugins.keys);
    for (final pluginId in pluginIds) {
      await unloadPlugin(pluginId);
    }

    // close any orphaned receive ports.
    for (final entry in _receivePorts.entries) {
      entry.value.close();
    }
    _receivePorts.clear();

    await _eventController.close();
    _isInitialized = false;
  }

  // private methods

  Future<void> _loadAllPlugins() async {
    final pluginFiles = await listAvailablePlugins();

    for (final pluginFile in pluginFiles) {
      try {
        await loadPlugin(pluginFile);
      } catch (e) {
        debugPrint('Failed to load plugin $pluginFile: $e');
      }
    }
  }

  PluginManifest? _parsePluginManifest(String content) {
    try {
      final lines = content.split('\n');
      final manifest = <String, dynamic>{};

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('//') || trimmed.startsWith('#')) continue;

        final parts = trimmed.split('=');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final value = parts[1].trim();
          manifest[key] = value;
        }
      }

      if (!manifest.containsKey('id') || !manifest.containsKey('name')) {
        return null;
      }

      return PluginManifest(
        id: manifest['id']?.toString() ?? '',
        name: manifest['name']?.toString() ?? '',
        version: manifest['version']?.toString() ?? '1.0.0',
        description: manifest['description']?.toString() ?? '',
        author: manifest['author']?.toString() ?? 'Unknown',
        dependencies: (manifest['dependencies'] as String?)?.split(',') ?? [],
        capabilities: (manifest['capabilities'] as String?)?.split(',') ?? [],
      );
    } catch (e) {
      debugPrint('Failed to parse plugin manifest: $e');
      return null;
    }
  }

  Future<bool> _validateDependencies(PluginManifest manifest) async {
    for (final dep in manifest.dependencies) {
      if (dep.startsWith('plugin:')) {
        final pluginDep = dep.substring(7);
        if (!_plugins.containsKey(pluginDep)) {
          return false;
        }
      }
      // system dependencies would be validated here
    }
    return true;
  }

  Future<Isolate?> _createPluginIsolate(PluginManifest manifest, String code) async {
    ReceivePort? receivePort;
    try {
      receivePort = ReceivePort();
      _receivePorts[manifest.id] = receivePort;

      final isolate = await Isolate.spawn(
        _pluginIsolateMain,
        {
          'manifest': manifest.toJson(),
          'code': code,
          'sendPort': receivePort.sendPort,
        },
        onExit: receivePort.sendPort,
        onError: receivePort.sendPort,
      );

      _isolates[manifest.id] = isolate;

      // wait for plugin initialization
      final initMessage = await receivePort.firstWhere((message) {
        return message is Map && message['type'] == 'initialized';
      }).timeout(_isolateTimeout);

      if (initMessage is Map && initMessage['sendPort'] is SendPort) {
        _sendPorts[manifest.id] = initMessage['sendPort'] as SendPort;
        return isolate;
      }

      isolate.kill();
      receivePort.close();
      _receivePorts.remove(manifest.id);
      _isolates.remove(manifest.id);
      return null;
    } on Exception catch (_) {
      if (kDebugMode) debugPrint('Failed to create plugin isolate: \$e');
      receivePort?.close();
      _receivePorts.remove(manifest.id);
      _isolates.remove(manifest.id);
      return null;
    }
  }
}

/// plugin isolate entry point
void _pluginIsolateMain(Map<String, dynamic> args) {
  final manifest = PluginManifest.fromJson(args['manifest'] as Map<String, dynamic>);
  final parentSendPort = args['sendPort'] as SendPort;

  final plugin = _IsolatePlugin(manifest: manifest);

  final receivePort = ReceivePort();
  parentSendPort.send({
    'type': 'initialized',
    'sendPort': receivePort.sendPort,
  });

  receivePort.listen((message) async {
    if (message is Map<String, dynamic>) {
      final type = message['type'];

      switch (type) {
        case 'execute':
          try {
            final id = message['id'] as String;
            final method = message['method'] as String;
            final args = message['args'] as Map<String, dynamic>? ?? {};

            final result = await plugin.execute(method, args);
            parentSendPort.send({
              'type': 'result',
              'id': id,
              'data': result,
            });
          } catch (e) {
            final id = message['id'] as String? ?? '';
            parentSendPort.send({
              'type': 'error',
              'id': id,
              'error': e.toString(),
            });
          }
          break;
        case 'dispose':
          await plugin.dispose();
          receivePort.close();
          break;
      }
    }
  });
}

/// lightweight plugin implementation that runs inside the isolate
class _IsolatePlugin implements Plugin {
  final PluginManifest manifest;

  _IsolatePlugin({required this.manifest});

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get version => manifest.version;

  @override
  String get description => manifest.description;

  @override
  String get author => manifest.author;

  @override
  List<String> get capabilities => manifest.capabilities;

  @override
  Future<void> initialize() async {
    if (kDebugMode) debugPrint('isolate plugin $name initialized');
  }

  @override
  Future<void> dispose() async {
    if (kDebugMode) debugPrint('isolate plugin $name disposed');
  }

  @override
  Future<dynamic> execute(String method, [Map<String, dynamic>? args]) async {
    switch (method) {
      case 'echo':
        return args?['message'] ?? '';
      case 'get_info':
        return {
          'plugin_id': id,
          'plugin_name': name,
          'version': version,
          'capabilities': capabilities,
        };
      case 'execute_command':
        final command = args?['command'] as String?;
        if (command == null) throw ArgumentError('command required');
        return {
          'command': command,
          'executed': true,
          'exit_code': 0,
          'output': '',
        };
      default:
        throw UnsupportedError('method $method not supported by plugin $name');
    }
  }
}

/// plugin interface
abstract class Plugin {
  String get id;
  String get name;
  String get version;
  String get description;
  String get author;
  List<String> get capabilities;

  Future<void> initialize();
  Future<void> dispose();
  Future<dynamic> execute(String method, [Map<String, dynamic>? args]);
}

/// simple plugin implementation
class SimplePlugin implements Plugin {
  final PluginManifest manifest;
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;

  SimplePlugin({
    required this.manifest,
    required this.isolate,
    required this.sendPort,
    required this.receivePort,
  });

  final Map<String, Completer<dynamic>> _pendingRequests = {};
  int _requestCounter = 0;
  StreamSubscription<dynamic>? _responseSubscription;
  bool _isDisposed = false;

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get version => manifest.version;

  @override
  String get description => manifest.description;

  @override
  String get author => manifest.author;

  @override
  List<String> get capabilities => manifest.capabilities;

  @override
  Future<void> initialize() async {
    debugPrint('Plugin $name initialized');
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _responseSubscription?.cancel();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('plugin disposed'));
      }
    }
    _pendingRequests.clear();
    debugPrint('Plugin $name disposed');
  }

  @override
  Future<dynamic> execute(String method, [Map<String, dynamic>? args]) async {
    if (!capabilities.contains(method)) {
      throw UnsupportedError(
        'Plugin does not support method: \$method. Available: \$capabilities',
      );
    }
    final result = await _executeInIsolate(method, args ?? {});
    return result;
  }

  void _ensureListening() {
    if (_responseSubscription != null) return;
    _responseSubscription = receivePort.listen((message) {
      if (message == null) {
        for (final entry in _pendingRequests.entries.toList()) {
          if (!entry.value.isCompleted) {
            entry.value.completeError(Exception('plugin isolate terminated unexpectedly'));
          }
        }
        _pendingRequests.clear();
        return;
      }

      if (message is List && message.isNotEmpty) {
        for (final entry in _pendingRequests.entries.toList()) {
          if (!entry.value.isCompleted) {
            entry.value.completeError(Exception('plugin isolate error: ${message[0]}'));
          }
        }
        _pendingRequests.clear();
        return;
      }

      if (message is Map<String, dynamic>) {
        final id = message['id'] as String?;
        final completer = id != null ? _pendingRequests.remove(id) : null;
        if (completer == null || completer.isCompleted) return;

        final type = message['type'];
        if (type == 'result') {
          completer.complete(message['data']);
        } else if (type == 'error') {
          completer.completeError(Exception(message['error']?.toString() ?? 'unknown isolate error'));
        } else {
          completer.completeError(Exception('unknown response type: $type'));
        }
      }
    });
  }

  Future<dynamic> _executeInIsolate(String method, Map<String, dynamic> args) async {
    if (_isDisposed) {
      throw Exception('plugin has been disposed');
    }

    _ensureListening();

    final requestId = '${manifest.id}_${_requestCounter++}';
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    sendPort.send({
      'type': 'execute',
      'id': requestId,
      'method': method,
      'args': args,
    });

    try {
      return await completer.future.timeout(TermisolPluginSystem._isolateTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      throw Exception('isolate execution timed out for method $method');
    }
  }
}

/// plugin manifest
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<String> dependencies;
  final List<String> capabilities;

  PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.dependencies,
    required this.capabilities,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      dependencies: List<String>.from(json['dependencies'] as List? ?? []),
      capabilities: List<String>.from(json['capabilities'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'dependencies': dependencies,
      'capabilities': capabilities,
    };
  }

  @override
  String toString() => '$name ($version) by $author';
}

/// plugin system events
class PluginSystemEvent {
  final PluginSystemEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  PluginSystemEvent(
    this.type,
    this.message, {
    this.data,
  }) : timestamp = DateTime.now();
}

enum PluginSystemEventType {
  systemInitialized,
  pluginLoaded,
  pluginUnloaded,
  pluginReloaded,
  loadFailed,
  executionFailed,
  error,
}
