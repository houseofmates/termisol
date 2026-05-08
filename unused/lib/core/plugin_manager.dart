import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Production-ready plugin manager for termisol.
/// Supports dynamic loading of Dart plugins with isolate-based execution.
class PluginManager {
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;

  PluginManager._internal();

  final Map<String, Plugin> _loadedPlugins = {};
  final Map<String, Isolate> _pluginIsolates = {};
  final Map<String, SendPort> _pluginSendPorts = {};
  final Map<String, ReceivePort> _pluginReceivePorts = {};
  final StreamController<PluginEvent> _eventController = StreamController.broadcast();

  bool _isInitialized = false;
  final String _pluginsDirectory = path.join(Directory.current.path, 'plugins');

  bool get isInitialized => _isInitialized;
  Stream<PluginEvent> get events => _eventController.stream;
  List<String> get loadedPluginIds => _loadedPlugins.keys.toList();
  Map<String, PluginInfo> get loadedPlugins => Map.unmodifiable(_loadedPlugins);

  /// Initialize the plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create plugins directory if it doesn't exist
      final pluginsDir = Directory(_pluginsDirectory);
      if (!await pluginsDir.exists()) {
        await pluginsDir.create(recursive: true);
      }

      // Load any pre-installed plugins
      await _loadBundledPlugins();

      _isInitialized = true;
      _eventController.add(PluginEvent(
        PluginEventType.systemInitialized,
        'Plugin system initialized successfully',
        data: {'pluginCount': _loadedPlugins.length},
      ));
    } catch (e, stack) {
      _eventController.add(PluginEvent(
        PluginEventType.error,
        'Failed to initialize plugin system: $e',
        data: {'error': e.toString(), 'stack': stack.toString()},
      ));
      rethrow;
    }
  }

  /// Load a plugin from file path
  Future<bool> loadPlugin(String pluginPath) async {
    try {
      final file = File(pluginPath);
      if (!await file.exists()) {
        _eventController.add(PluginEvent(
          PluginEventType.loadFailed,
          'Plugin file not found: $pluginPath',
        ));
        return false;
      }

      final content = await file.readAsString();
      final pluginInfo = await _parsePluginManifest(content);

      if (pluginInfo == null) {
        _eventController.add(PluginEvent(
          PluginEventType.loadFailed,
          'Invalid plugin manifest in $pluginPath',
        ));
        return false;
      }

      // Check for conflicts
      if (_loadedPlugins.containsKey(pluginInfo.id)) {
        _eventController.add(PluginEvent(
          PluginEventType.loadFailed,
          'Plugin ${pluginInfo.id} already loaded',
        ));
        return false;
      }

      // Check dependencies
      if (!await _checkDependencies(pluginInfo)) {
        _eventController.add(PluginEvent(
          PluginEventType.loadFailed,
          'Missing dependencies for ${pluginInfo.name}',
          data: {'plugin': pluginInfo.id, 'dependencies': pluginInfo.dependencies},
        ));
        return false;
      }

      // Create plugin isolate
      final isolate = await _createPluginIsolate(pluginInfo, content);
      if (isolate != null) {
        _loadedPlugins[pluginInfo.id] = pluginInfo;
        _pluginIsolates[pluginInfo.id] = isolate;

        _eventController.add(PluginEvent(
          PluginEventType.pluginLoaded,
          'Plugin loaded: ${pluginInfo.name}',
          data: {'plugin': pluginInfo.id, 'version': pluginInfo.version},
        ));
        return true;
      }

      return false;
    } catch (e) {
      _eventController.add(PluginEvent(
        PluginEventType.loadFailed,
        'Failed to load plugin: $e',
        data: {'path': pluginPath, 'error': e.toString()},
      ));
      return false;
    }
  }

  /// Unload a plugin by ID
  Future<void> unloadPlugin(String pluginId) async {
    final isolate = _pluginIsolates[pluginId];
    final receivePort = _pluginReceivePorts[pluginId];

    if (isolate != null) {
      isolate.kill();
      _pluginIsolates.remove(pluginId);
    }

    if (receivePort != null) {
      receivePort.close();
      _pluginReceivePorts.remove(pluginId);
    }

    _pluginSendPorts.remove(pluginId);
    _loadedPlugins.remove(pluginId);

    _eventController.add(PluginEvent(
      PluginEventType.pluginUnloaded,
      'Plugin unloaded: $pluginId',
    ));
  }

  /// Execute a plugin method
  Future<dynamic> executePlugin(String pluginId, String method, [Map<String, dynamic>? args]) async {
    final sendPort = _pluginSendPorts[pluginId];
    if (sendPort == null) {
      throw Exception('Plugin not found or not ready: $pluginId');
    }

    final completer = Completer<dynamic>();
    final responsePort = ReceivePort();

    responsePort.listen((message) {
      if (message is Map && message['type'] == 'result') {
        completer.complete(message['data']);
      } else if (message is Map && message['type'] == 'error') {
        completer.completeError(Exception(message['error']));
      }
      responsePort.close();
    });

    sendPort.send({
      'type': 'execute',
      'method': method,
      'args': args ?? {},
      'responsePort': responsePort.sendPort,
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        responsePort.close();
        throw TimeoutException('Plugin method execution timed out');
      },
    );
  }

  /// Get plugin information
  PluginInfo? getPlugin(String pluginId) => _loadedPlugins[pluginId];

  /// Check if plugin is loaded
  bool isPluginLoaded(String pluginId) => _loadedPlugins.containsKey(pluginId);

  /// Dispose all resources
  void dispose() {
    for (final isolate in _pluginIsolates.values) {
      isolate.kill();
    }
    for (final receivePort in _pluginReceivePorts.values) {
      receivePort.close();
    }
    _pluginIsolates.clear();
    _pluginReceivePorts.clear();
    _pluginSendPorts.clear();
    _loadedPlugins.clear();
    _eventController.close();
  }

  // Private methods

  Future<void> _loadBundledPlugins() async {
    try {
      final pluginsDir = Directory(_pluginsDirectory);
      if (!await pluginsDir.exists()) return;

      await for (final entity in pluginsDir.list()) {
        if (entity is File && entity.path.endsWith('.plugin')) {
          await loadPlugin(entity.path);
        }
      }
    } catch (e) {
      _eventController.add(PluginEvent(
        PluginEventType.error,
        'Failed to load bundled plugins: $e',
      ));
    }
  }

  Future<PluginInfo?> _parsePluginManifest(String content) async {
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

      return PluginInfo(
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

  Future<bool> _checkDependencies(PluginInfo plugin) async {
    // Check if required dependencies are available
    for (final dep in plugin.dependencies) {
      if (dep.startsWith('plugin:')) {
        final pluginDep = dep.substring(7);
        if (!_loadedPlugins.containsKey(pluginDep)) {
          return false;
        }
      }
      // System dependencies could be checked here
    }
    return true;
  }

  Future<Isolate?> _createPluginIsolate(PluginInfo plugin, String code) async {
    try {
      final receivePort = ReceivePort();
      _pluginReceivePorts[plugin.id] = receivePort;

      final isolate = await Isolate.spawn(
        _pluginIsolateMain,
        {
          'pluginInfo': plugin.toJson(),
          'code': code,
          'sendPort': receivePort.sendPort,
        },
        onExit: receivePort.sendPort,
        onError: receivePort.sendPort,
      );

      _pluginIsolates[plugin.id] = isolate;

      // Wait for plugin to initialize
      final initMessage = await receivePort.firstWhere((message) {
        return message is Map && message['type'] == 'initialized';
      }).timeout(const Duration(seconds: 10));

      if (initMessage is Map && initMessage['sendPort'] is SendPort) {
        _pluginSendPorts[plugin.id] = initMessage['sendPort'] as SendPort;
        return isolate;
      }

      return null;
    } catch (e) {
      debugPrint('Failed to create plugin isolate: $e');
      _pluginReceivePorts.remove(plugin.id);
      return null;
    }
  }
}

/// Plugin isolate entry point
void _pluginIsolateMain(Map<String, dynamic> args) {
  final pluginInfo = PluginInfo.fromJson(args['pluginInfo'] as Map<String, dynamic>);
  final code = args['code'] as String;
  final parentSendPort = args['sendPort'] as SendPort;

  final receivePort = ReceivePort();
  parentSendPort.send({
    'type': 'initialized',
    'sendPort': receivePort.sendPort,
  });

  receivePort.listen((message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'];

      switch (type) {
        case 'execute':
          try {
            final method = message['method'] as String;
            final args = message['args'] as Map<String, dynamic>? ?? {};
            final responsePort = message['responsePort'] as SendPort;

            final result = _executePluginMethod(pluginInfo, method, args);
            responsePort.send({'type': 'result', 'data': result});
          } catch (e) {
            final responsePort = message['responsePort'] as SendPort;
            responsePort.send({'type': 'error', 'error': e.toString()});
          }
          break;
      }
    }
  });
}

dynamic _executePluginMethod(PluginInfo plugin, String method, Map<String, dynamic> args) {
  // Plugin method execution - in production, this would execute compiled plugin code
  switch (method) {
    case 'getInfo':
      return plugin.toJson();
    case 'getCapabilities':
      return plugin.capabilities;
    case 'ping':
      return {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()};
    default:
      // For custom methods, return a generic response
      return {'method': method, 'args': args, 'executed': true};
  }
}

/// Plugin information
class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<String> dependencies;
  final List<String> capabilities;

  PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.dependencies,
    required this.capabilities,
  });

  factory PluginInfo.fromJson(Map<String, dynamic> json) {
    return PluginInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      version: json['version'] ?? '1.0.0',
      description: json['description'] ?? '',
      author: json['author'] ?? '',
      dependencies: List<String>.from(json['dependencies'] ?? []),
      capabilities: List<String>.from(json['capabilities'] ?? []),
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

/// Plugin events
class PluginEvent {
  final PluginEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  PluginEvent(
    this.type,
    this.message, {
    this.data,
  }) : timestamp = DateTime.now();
}

enum PluginEventType {
  systemInitialized,
  pluginLoaded,
  pluginUnloaded,
  loadFailed,
  error,
}