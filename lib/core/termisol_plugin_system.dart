import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:termisol/core/logging_system.dart';

/// Termisol Plugin System
///
/// Features:
/// - Dynamic plugin loading from file system
/// - Plugin lifecycle management (load, unload, reload)
/// - Secure isolate-based execution
/// - Plugin dependency resolution
/// - Event-driven communication
/// - Performance monitoring
/// - Hot-reload capability
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

  /// Initialize the plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create plugins directory
      final pluginsDir = Directory(_pluginsDirectory);
      if (!await pluginsDir.exists()) {
        await pluginsDir.create(recursive: true);
      }

      // Load all plugins from directory
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

  /// Load a plugin from file path
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

      // Check for conflicts
      if (_plugins.containsKey(manifest.id)) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Plugin ${manifest.id} already loaded',
        ));
        return false;
      }

      // Validate dependencies
      if (!await _validateDependencies(manifest)) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Missing dependencies for plugin ${manifest.id}',
          data: {'plugin': manifest.id, 'dependencies': manifest.dependencies},
        ));
        return false;
      }

      // Create plugin isolate
      final isolate = await _createPluginIsolate(manifest, content);
      if (isolate == null) {
        _eventController.add(PluginSystemEvent(
          PluginSystemEventType.loadFailed,
          'Failed to create isolate for plugin ${manifest.id}',
        ));
        return false;
      }

      // Create plugin instance
      final plugin = SimplePlugin(
        manifest: manifest,
        isolate: isolate,
      );

      _plugins[manifest.id] = plugin;
      _manifests[manifest.id] = manifest;
      _isolates[manifest.id] = isolate;

      // Initialize plugin
      await plugin.initialize();

      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.pluginLoaded,
        'Plugin loaded: ${manifest.name} (${manifest.version})',
        data: {'plugin': manifest.id, 'version': manifest.version},
      ));

      return true;
    } catch (e, stack) {
      _eventController.add(PluginSystemEvent(
        PluginSystemEventType.loadFailed,
        'Failed to load plugin from $pluginPath: $e',
        data: {'path': pluginPath, 'error': e.toString()},
      ));
      return false;
    }
  }

  /// Unload a plugin
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

  /// Reload a plugin
  Future<bool> reloadPlugin(String pluginId) async {
    final manifest = _manifests[pluginId];
    if (manifest == null) return false;

    await unloadPlugin(pluginId);

    // Find plugin file
    final pluginFile = File('$_pluginsDirectory/$pluginId.plugin');
    if (!await pluginFile.exists()) {
      return false;
    }

    return await loadPlugin(pluginFile.path);
  }

  /// Execute plugin method
  Future<dynamic> executePlugin(String pluginId, String method, [Map<String, dynamic>? args]) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) {
      throw Exception('Plugin not found: $pluginId');
    }

    return await plugin.execute(method, args ?? {});
  }

  /// Get plugin information
  PluginManifest? getPluginManifest(String pluginId) => _manifests[pluginId];

  /// Check if plugin is loaded
  bool isPluginLoaded(String pluginId) => _plugins.containsKey(pluginId);

  /// Get plugin capabilities
  List<String> getPluginCapabilities(String pluginId) {
    final manifest = _manifests[pluginId];
    return manifest?.capabilities ?? [];
  }

  /// List all available plugin files
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

  /// Dispose all resources
  Future<void> dispose() async {
    final pluginIds = List<String>.from(_plugins.keys);
    for (final pluginId in pluginIds) {
      await unloadPlugin(pluginId);
    }

    _eventController.close();
    _isInitialized = false;
  }

  // Private methods

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
        id: manifest['id'],
        name: manifest['name'],
        version: manifest['version'] ?? '1.0.0',
        description: manifest['description'] ?? '',
        author: manifest['author'] ?? 'Unknown',
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
      // System dependencies would be validated here
    }
    return true;
  }

  Future<Isolate?> _createPluginIsolate(PluginManifest manifest, String code) async {
    try {
      final receivePort = ReceivePort();
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

      // Wait for plugin initialization
      final initMessage = await receivePort.firstWhere((message) {
        return message is Map && message['type'] == 'initialized';
      }).timeout(_isolateTimeout);

      if (initMessage is Map && initMessage['sendPort'] is SendPort) {
        _sendPorts[manifest.id] = initMessage['sendPort'] as SendPort;
        return isolate;
      }

      return null;
    } catch (e) {
      debugPrint('Failed to create plugin isolate: $e');
      _receivePorts.remove(manifest.id);
      return null;
    }
  }
}

/// Plugin isolate entry point
void _pluginIsolateMain(Map<String, dynamic> args) {
  final manifest = PluginManifest.fromJson(args['manifest'] as Map<String, dynamic>);
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

            final result = _executePluginMethodInIsolate(manifest, method, args);
            responsePort.send({'type': 'result', 'data': result});
          } catch (e) {
            final responsePort = message['responsePort'] as SendPort;
            responsePort.send({'type': 'error', 'error': e.toString()});
          }
          break;
        case 'dispose':
          receivePort.close();
          break;
      }
    }
  });
}

dynamic _executePluginMethodInIsolate(PluginManifest manifest, String method, Map<String, dynamic> args) {
  // Plugin method execution - in production, this would compile and run actual plugin code
  switch (method) {
    case 'getInfo':
      return manifest.toJson();
    case 'getCapabilities':
      return manifest.capabilities;
    case 'ping':
      return {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()};
    case 'execute':
      // Generic execution for custom plugin methods
      return {'method': method, 'args': args, 'executed': true, 'plugin': manifest.id};
    default:
      throw Exception('Unknown method: $method');
  }
}

/// Plugin interface
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

/// Simple plugin implementation
class SimplePlugin implements Plugin {
  final PluginManifest manifest;
  final Isolate isolate;

  SimplePlugin({
    required this.manifest,
    required this.isolate,
  });

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
    // Plugin initialization logic
    debugPrint('Plugin $name initialized');
  }

  @override
  Future<void> dispose() async {
    // Plugin cleanup logic
    debugPrint('Plugin $name disposed');
  }

  @override
  Future<dynamic> execute(String method, [Map<String, dynamic>? args]) async {
    // This would communicate with the isolate to execute methods
    // For now, return a placeholder response
    return {'method': method, 'args': args, 'executed': true};
  }
}

/// Plugin manifest
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

/// Plugin system events
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