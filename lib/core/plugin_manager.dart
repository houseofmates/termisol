import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Plugin Manager
///
/// Loads and manages extensions using a registration-based architecture.
/// Supports plugin discovery, dependency resolution, lifecycle hooks,
/// and hot-reload capability.
class PluginManager {
  final Map<String, Plugin> _plugins = {};
  final Map<String, PluginDescriptor> _descriptors = {};
  final List<PluginHook> _globalHooks = [];
  final StreamController<PluginEvent> _eventController = StreamController<PluginEvent>.broadcast();
  String? _pluginsDir;
  bool _isInitialized = false;

  Stream<PluginEvent> get events => _eventController.stream;
  List<Plugin> get loadedPlugins => _plugins.values.toList();
  List<String> get enabledPluginIds => _plugins.values.where((p) => p.isEnabled).map((p) => p.descriptor.id).toList();

  Future<void> initialize({String? pluginsDirectory}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _pluginsDir = pluginsDirectory ?? '${appDir.path}/plugins';
      final dir = Directory(_pluginsDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _discoverPlugins();
      _isInitialized = true;
      debugPrint('PluginManager initialized: ${_plugins.length} plugins discovered');
    } catch (e) {
      debugPrint('Failed to initialize PluginManager: $e');
      rethrow;
    }
  }

  Future<Plugin> registerPlugin(PluginDescriptor descriptor) async {
    if (_plugins.containsKey(descriptor.id)) {
      throw PluginException('Plugin ${descriptor.id} is already registered');
    }

    final unresolved = _findUnresolvedDependencies(descriptor);
    if (unresolved.isNotEmpty) {
      throw PluginException('Unresolved dependencies: ${unresolved.join(", ")}');
    }

    final plugin = Plugin(descriptor: descriptor);
    _plugins[descriptor.id] = plugin;
    _descriptors[descriptor.id] = descriptor;

    await _callHook('beforeLoad', plugin);
    await plugin.onLoad();
    await _callHook('afterLoad', plugin);

    if (descriptor.autoEnable) {
      await enablePlugin(descriptor.id);
    }

    _eventController.add(PluginEvent.loaded(descriptor.id));
    return plugin;
  }

  Future<bool> enablePlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;

    final dependencies = plugin.descriptor.dependencies;
    for (final depId in dependencies) {
      final dep = _plugins[depId];
      if (dep != null && !dep.isEnabled) {
        await enablePlugin(depId);
      }
    }

    await _callHook('beforeEnable', plugin);
    await plugin.onEnable();
    await _callHook('afterEnable', plugin);
    _eventController.add(PluginEvent.enabled(pluginId));
    return true;
  }

  Future<bool> disablePlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;

    final dependents = _findDependents(pluginId);
    for (final depId in dependents) {
      await disablePlugin(depId);
    }

    await _callHook('beforeDisable', plugin);
    await plugin.onDisable();
    await _callHook('afterDisable', plugin);
    _eventController.add(PluginEvent.disabled(pluginId));
    return true;
  }

  Future<bool> unregisterPlugin(String pluginId) async {
    final plugin = _plugins.remove(pluginId);
    _descriptors.remove(pluginId);
    if (plugin == null) return false;

    if (plugin.isEnabled) {
      await plugin.onDisable();
    }
    await _callHook('beforeUnload', plugin);
    await plugin.onUnload();
    _eventController.add(PluginEvent.unloaded(pluginId));
    return true;
  }

  Plugin? getPlugin(String id) => _plugins[id];
  PluginDescriptor? getDescriptor(String id) => _descriptors[id];

  List<PluginDescriptor> getAvailableDescriptors() => _descriptors.values.toList();

  void addGlobalHook(PluginHook hook) {
    _globalHooks.add(hook);
  }

  Future<T> callPlugin<T>(String pluginId, String method, [List<dynamic> args = const []]) async {
    final plugin = _plugins[pluginId];
    if (plugin == null || !plugin.isEnabled) {
      throw PluginException('Plugin $pluginId is not available');
    }
    return plugin.call(method, args) as T;
  }

  List<String> _findUnresolvedDependencies(PluginDescriptor descriptor) {
    return descriptor.dependencies.where((depId) => !_plugins.containsKey(depId) && !_descriptors.containsKey(depId)).toList();
  }

  List<String> _findDependents(String pluginId) {
    return _plugins.values
        .where((p) => p.isEnabled && p.descriptor.dependencies.contains(pluginId))
        .map((p) => p.descriptor.id)
        .toList();
  }

  Future<void> _callHook(String hook, Plugin plugin) async {
    for (final h in _globalHooks) {
      if (h.event == hook) {
        try {
          await h.handler(plugin);
        } catch (e) {
          debugPrint('Hook error ($hook): $e');
        }
      }
    }
  }

  Future<void> _discoverPlugins() async {
    if (_pluginsDir == null) return;
    final dir = Directory(_pluginsDir!);
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final jsonData = json.decode(content) as Map<String, dynamic>;
            final descriptor = PluginDescriptor.fromJson(jsonData);
            _descriptors[descriptor.id] = descriptor;
            if (descriptor.autoEnable) {
              await registerPlugin(descriptor);
            }
          } catch (e) {
            debugPrint('Failed to load plugin descriptor ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to scan plugins directory: $e');
    }
  }

  Future<void> dispose() async {
    for (final pluginId in _plugins.keys.toList()) {
      await unregisterPlugin(pluginId);
    }
    _globalHooks.clear();
    await _eventController.close();
  }
}

class PluginDescriptor {
  final String id;
  final String name;
  final String version;
  final String description;
  final String? author;
  final List<String> dependencies;
  final Map<String, String> exports;
  final bool autoEnable;
  final Map<String, dynamic> config;

  PluginDescriptor({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.author,
    this.dependencies = const [],
    this.exports = const {},
    this.autoEnable = false,
    this.config = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'version': version, 'description': description,
    'author': author, 'dependencies': dependencies, 'exports': exports,
    'autoEnable': autoEnable, 'config': config,
  };

  factory PluginDescriptor.fromJson(Map<String, dynamic> json) {
    return PluginDescriptor(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String?,
      dependencies: List<String>.from(json['dependencies'] ?? []),
      exports: Map<String, String>.from(json['exports'] ?? {}),
      autoEnable: json['autoEnable'] as bool? ?? false,
      config: Map<String, dynamic>.from(json['config'] ?? {}),
    );
  }
}

class Plugin {
  final PluginDescriptor descriptor;
  bool isEnabled;
  final DateTime createdAt;
  final Map<String, dynamic> _state;

  Plugin({
    required this.descriptor,
    this.isEnabled = false,
    DateTime? createdAt,
    Map<String, dynamic>? state,
  }) : createdAt = createdAt ?? DateTime.now(),
      _state = state ?? {};

  String get id => descriptor.id;
  String get name => descriptor.name;

  Future<void> onLoad() async {
    debugPrint('Plugin [${descriptor.id}] loaded');
  }

  Future<void> onUnload() async {
    debugPrint('Plugin [${descriptor.id}] unloaded');
  }

  Future<void> onEnable() async {
    isEnabled = true;
    debugPrint('Plugin [${descriptor.id}] enabled');
  }

  Future<void> onDisable() async {
    isEnabled = false;
    debugPrint('Plugin [${descriptor.id}] disabled');
  }

  dynamic call(String method, [List<dynamic> args = const []]) {
    throw UnimplementedError('Plugin ${descriptor.id} does not implement $method');
  }

  void setState(String key, dynamic value) => _state[key] = value;
  dynamic getState(String key) => _state[key];
}

class PluginHook {
  final String event;
  final Future<void> Function(Plugin plugin) handler;

  PluginHook({required this.event, required this.handler});
}

class PluginEvent {
  final String pluginId;
  final PluginEventType type;

  PluginEvent._({required this.pluginId, required this.type});

  factory PluginEvent.loaded(String id) => PluginEvent._(pluginId: id, type: PluginEventType.loaded);
  factory PluginEvent.unloaded(String id) => PluginEvent._(pluginId: id, type: PluginEventType.unloaded);
  factory PluginEvent.enabled(String id) => PluginEvent._(pluginId: id, type: PluginEventType.enabled);
  factory PluginEvent.disabled(String id) => PluginEvent._(pluginId: id, type: PluginEventType.disabled);
}

enum PluginEventType { loaded, unloaded, enabled, disabled }

class PluginException implements Exception {
  final String message;
  PluginException(this.message);
  @override
  String toString() => 'PluginException: $message';
}