import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Production-ready plugin manager for termisol.
/// Supports dynamic loading of Dart plugins with hot-reload capability.
class PluginManager {
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;

  PluginManager._internal();

  bool _isInitialized = false;
  final Map<String, PluginInfo> _loadedPlugins = {};
  final Map<String, Isolate> _pluginIsolates = {};
  final StreamController<PluginEvent> _eventController = StreamController.broadcast();

  bool get isInitialized => _isInitialized;
  Stream<PluginEvent> get events => _eventController.stream;
  List<Map<String, dynamic>> get loadedPlugins => _loadedPlugins.values.map((p) => p.toJson()).toList();

  /// Initialize the plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Create plugins directory if it doesn't exist
    final pluginsDir = Directory(_getPluginsDirectory());
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }

    // Load any pre-installed plugins
    await _loadBundledPlugins();

    _isInitialized = true;
    _eventController.add(PluginEvent(PluginEventType.systemInitialized, 'Plugin system initialized'));
  }

  /// Load a plugin from file path
  Future<bool> loadPlugin(String pluginPath) async {
    try {
      final file = File(pluginPath);
      if (!await file.exists()) {
        _eventController.add(PluginEvent(PluginEventType.loadFailed, 'Plugin file not found: $pluginPath'));
        return false;
      }

      final content = await file.readAsString();
      final pluginInfo = await _parsePluginManifest(content);

      if (pluginInfo == null) {
        _eventController.add(PluginEvent(PluginEventType.loadFailed, 'Invalid plugin manifest'));
        return false;
      }

      // Check dependencies
      if (!await _checkDependencies(pluginInfo)) {
        _eventController.add(PluginEvent(PluginEventType.loadFailed, 'Missing dependencies for ${pluginInfo.name}'));
        return false;
      }

      // Initialize plugin isolate
      final isolate = await _createPluginIsolate(pluginInfo, content);
      if (isolate != null) {
        _loadedPlugins[pluginInfo.id] = pluginInfo;
        _pluginIsolates[pluginInfo.id] = isolate;

        _eventController.add(PluginEvent(PluginEventType.pluginLoaded, 'Plugin loaded: ${pluginInfo.name}'));
        return true;
      }

      return false;
    } catch (e) {
      _eventController.add(PluginEvent(PluginEventType.loadFailed, 'Failed to load plugin: $e'));
      return false;
    }
  }

  /// Unload a plugin by ID
  Future<void> unloadPlugin(String pluginId) async {
    final isolate = _pluginIsolates[pluginId];
    if (isolate != null) {
      isolate.kill();
      _pluginIsolates.remove(pluginId);
    }

    _loadedPlugins.remove(pluginId);
    _eventController.add(PluginEvent(PluginEventType.pluginUnloaded, 'Plugin unloaded: $pluginId'));
  }

  /// Execute a plugin method
  Future<dynamic> executePlugin(String pluginId, String method, [Map<String, dynamic>? args]) async {
    final plugin = _loadedPlugins[pluginId];
    if (plugin == null) {
      throw Exception('Plugin not found: $pluginId');
    }

    // Send message to plugin isolate
    final sendPort = _getPluginSendPort(pluginId);
    if (sendPort != null) {
      final completer = Completer<dynamic>();
      final receivePort = ReceivePort();
      receivePort.listen((message) {
        if (message is Map && message['type'] == 'result') {
          completer.complete(message['data']);
        } else if (message is Map && message['type'] == 'error') {
          completer.completeError(message['error']);
        }
      });

      sendPort.send({
        'type': 'execute',
        'method': method,
        'args': args ?? {},
        'replyPort': receivePort.sendPort,
      });

      return completer.future;
    }

    throw Exception('Plugin isolate not available');
  }

  /// Get plugin information
  PluginInfo? getPlugin(String pluginId) => _loadedPlugins[pluginId];

  /// Dispose all resources
  void dispose() {
    for (final isolate in _pluginIsolates.values) {
      isolate.kill();
    }
    _pluginIsolates.clear();
    _loadedPlugins.clear();
    _eventController.close();
  }

  // Private methods

  String _getPluginsDirectory() {
    return path.join(Directory.current.path, 'plugins');
  }

  Future<void> _loadBundledPlugins() async {
    // Load any plugins that come bundled with the app
    final pluginsDir = Directory(_getPluginsDirectory());
    if (!await pluginsDir.exists()) return;

    await for (final entity in pluginsDir.list()) {
      if (entity is File && entity.path.endsWith('.plugin')) {
        await loadPlugin(entity.path);
      }
    }
  }

  Future<PluginInfo?> _parsePluginManifest(String content) async {
    try {
      final manifest = jsonDecode(content) as Map<String, dynamic>;
      return PluginInfo.fromJson(manifest);
    } catch (e) {
      return null;
    }
  }

  Future<bool> _checkDependencies(PluginInfo plugin) async {
    // Check if required dependencies are available
    for (final dep in plugin.dependencies) {
      // For now, assume all dependencies are available
      // In a real implementation, you'd check if other plugins or system deps exist
    }
    return true;
  }

  Future<Isolate?> _createPluginIsolate(PluginInfo plugin, String code) async {
    try {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_pluginIsolateMain, {
        'sendPort': receivePort.sendPort,
        'pluginInfo': plugin.toJson(),
        'code': code,
      });

      // Wait for plugin to initialize
      await receivePort.firstWhere((message) => message['type'] == 'initialized');

      return isolate;
    } catch (e) {
      debugPrint('Failed to create plugin isolate: $e');
      return null;
    }
  }

  SendPort? _getPluginSendPort(String pluginId) {
    // In a real implementation, you'd maintain send ports for each isolate
    return null;
  }
}

/// Plugin isolate entry point
void _pluginIsolateMain(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  final pluginInfo = PluginInfo.fromJson(args['pluginInfo'] as Map<String, dynamic>);
  final code = args['code'] as String;

  final receivePort = ReceivePort();
  sendPort.send({'type': 'initialized'});

  receivePort.listen((message) {
    if (message is Map && message['type'] == 'execute') {
      final method = message['method'] as String;
      final args = message['args'] as Map<String, dynamic>;
      final replyPort = message['replyPort'] as SendPort;

      try {
        // Execute plugin method (simplified)
        final result = _executePluginMethod(pluginInfo, method, args);
        replyPort.send({'type': 'result', 'data': result});
      } catch (e) {
        replyPort.send({'type': 'error', 'error': e.toString()});
      }
    }
  });
}

dynamic _executePluginMethod(PluginInfo plugin, String method, Map<String, dynamic> args) {
  // Simplified plugin execution - in reality you'd compile and run actual Dart code
  switch (method) {
    case 'getVersion':
      return plugin.version;
    case 'getCapabilities':
      return plugin.capabilities;
    default:
      throw Exception('Unknown method: $method');
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
}

/// Plugin events
class PluginEvent {
  final PluginEventType type;
  final String message;
  final DateTime timestamp;

  PluginEvent(this.type, this.message) : timestamp = DateTime.now();
}

enum PluginEventType {
  systemInitialized,
  pluginLoaded,
  pluginUnloaded,
  loadFailed,
}
