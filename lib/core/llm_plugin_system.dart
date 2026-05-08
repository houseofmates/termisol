import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// LLM Plugin System
///
/// Extensible plugin architecture for integrating multiple LLM providers
/// and custom AI capabilities. Supports plugin loading, lifecycle management,
/// and unified API access across providers.
class LLMPluginSystem {
  final Map<String, LLMPlugin> _plugins = {};
  final Map<String, PluginManifest> _manifests = {};
  final List<PluginHook> _hooks = [];
  final Map<String, LLMProvider> _providers = {};
  final StreamController<PluginEvent> _eventController = StreamController<PluginEvent>.broadcast();
  String? _pluginsPath;
  LLMPlugin? _defaultPlugin;

  Stream<PluginEvent> get events => _eventController.stream;
  List<LLMPlugin> get loadedPlugins => _plugins.values.toList();
  List<String> get enabledPluginNames => _plugins.values.where((p) => p.isEnabled).map((p) => p.name).toList();

  Future<void> initialize({String? pluginsDirectory}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _pluginsPath = pluginsDirectory ?? '${appDir.path}/llm_plugins';
      final dir = Directory(_pluginsPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _loadPlugins();
      debugPrint('LLMPluginSystem initialized: ${_plugins.length} plugins loaded');
    } catch (e) {
      debugPrint('Failed to initialize LLMPluginSystem: $e');
      rethrow;
    }
  }

  Future<bool> registerPlugin(LLMPlugin plugin) async {
    if (_plugins.containsKey(plugin.name)) return false;
    _plugins[plugin.name] = plugin;
    _manifests[plugin.name] = plugin.manifest;
    if (plugin.defaultProvider) {
      _defaultPlugin ??= plugin;
    }
    await _persistPluginManifest(plugin.manifest);
    await plugin.onLoad();
    _eventController.add(PluginEvent.loaded(plugin.name));
    return true;
  }

  Future<bool> unregisterPlugin(String name) async {
    final plugin = _plugins.remove(name);
    _manifests.remove(name);
    if (_defaultPlugin?.name == name) {
      _defaultPlugin = _plugins.values.where((p) => p.isEnabled).firstOrNull;
    }
    if (plugin != null) {
      await plugin.onUnload();
      _eventController.add(PluginEvent.unloaded(name));
    }
    return plugin != null;
  }

  Future<bool> enablePlugin(String name) async {
    final plugin = _plugins[name];
    if (plugin == null) return false;
    plugin.isEnabled = true;
    await plugin.onEnable();
    _eventController.add(PluginEvent.enabled(name));
    return true;
  }

  Future<bool> disablePlugin(String name) async {
    final plugin = _plugins[name];
    if (plugin == null) return false;
    plugin.isEnabled = false;
    if (_defaultPlugin?.name == name) {
      _defaultPlugin = _plugins.values.where((p) => p.isEnabled && p.name != name).firstOrNull;
    }
    await plugin.onDisable();
    _eventController.add(PluginEvent.disabled(name));
    return true;
  }

  Future<PluginCompletionResult> complete({
    required String prompt,
    String? pluginName,
    Map<String, dynamic>? options,
  }) async {
    final plugin = pluginName != null
        ? _plugins[pluginName]
        : _defaultPlugin;
    if (plugin == null || !plugin.isEnabled) {
      return PluginCompletionResult(success: false, error: 'No enabled plugin available');
    }
    try {
      final result = await plugin.complete(prompt, options: options);
      return PluginCompletionResult(success: true, text: result.text, tokens: result.tokens);
    } catch (e) {
      return PluginCompletionResult(success: false, error: e.toString());
    }
  }

  Future<PluginCompletionResult> chatCompletions({
    required List<Map<String, String>> messages,
    String? pluginName,
    Map<String, dynamic>? options,
  }) async {
    final plugin = pluginName != null
        ? _plugins[pluginName]
        : _defaultPlugin;
    if (plugin == null || !plugin.isEnabled) {
      return PluginCompletionResult(success: false, error: 'No enabled plugin available');
    }
    try {
      final result = await plugin.chatCompletion(messages, options: options);
      return PluginCompletionResult(success: true, text: result.text, tokens: result.tokens);
    } catch (e) {
      return PluginCompletionResult(success: false, error: e.toString());
    }
  }

  Future<bool> setDefaultPlugin(String name) async {
    final plugin = _plugins[name];
    if (plugin == null || !plugin.isEnabled) return false;
    _defaultPlugin = plugin;
    return true;
  }

  LLMPlugin? getDefaultPlugin() => _defaultPlugin;

  LLMPlugin? getPlugin(String name) => _plugins[name];

  List<PluginManifest> getAvailableManifests() => _manifests.values.toList();

  void addHook(PluginHook hook) {
    _hooks.add(hook);
  }

  Future<void> _loadPlugins() async {
    try {
      if (_pluginsPath == null) return;
      final dir = Directory(_pluginsPath!);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final manifest = PluginManifest.fromJson(json.decode(content) as Map<String, dynamic>);
            if (manifest.autoLoad && manifest.type == PluginType.llm) {
              final plugin = LLMPlugin(manifest: manifest);
              _plugins[plugin.name] = plugin;
              _manifests[plugin.name] = manifest;
              await plugin.onLoad();
            }
          } catch (e) {
            debugPrint('Failed to load plugin from ${entity.path}: $e');
          }
        }
      }
      debugPrint('Loaded ${_plugins.length} LLM plugins from disk');
    } catch (e) {
      debugPrint('Failed to scan plugins directory: $e');
    }
  }

  Future<void> _persistPluginManifest(PluginManifest manifest) async {
    if (_pluginsPath == null) return;
    final file = File('$_pluginsPath/${manifest.name}.json');
    await file.writeAsString(json.encode(manifest.toJson()));
  }

  Future<void> dispose() async {
    for (final plugin in _plugins.values) {
      await plugin.onUnload();
    }
    _plugins.clear();
    _manifests.clear();
    _hooks.clear();
    _providers.clear();
    await _eventController.close();
  }
}

enum PluginType { llm, tool, provider, custom }
enum AuthType { apiKey, oauth, none }

class PluginManifest {
  final String name;
  final String version;
  final String description;
  final String? author;
  final PluginType type;
  final AuthType authType;
  final String? providerUrl;
  final String? modelName;
  final bool autoLoad;
  final Map<String, dynamic> config;

  PluginManifest({
    required this.name,
    required this.version,
    required this.description,
    this.author,
    this.type = PluginType.llm,
    this.authType = AuthType.apiKey,
    this.providerUrl,
    this.modelName,
    this.autoLoad = false,
    this.config = const {},
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    'type': type.name,
    'authType': authType.name,
    'providerUrl': providerUrl,
    'modelName': modelName,
    'autoLoad': autoLoad,
    'config': config,
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String,
      author: json['author'] as String?,
      type: PluginType.values.byName(json['type'] ?? 'llm'),
      authType: AuthType.values.byName(json['authType'] ?? 'apiKey'),
      providerUrl: json['providerUrl'] as String?,
      modelName: json['modelName'] as String?,
      autoLoad: json['autoLoad'] as bool? ?? false,
      config: Map<String, dynamic>.from(json['config'] ?? {}),
    );
  }
}

class LLMPlugin {
  final PluginManifest manifest;
  bool isEnabled;
  bool defaultProvider;
  LLMProvider? _provider;
  String? _apiKey;

  LLMPlugin({
    required this.manifest,
    this.isEnabled = false,
    this.defaultProvider = false,
  });

  String get name => manifest.name;
  String get version => manifest.version;

  Future<void> onLoad() async { debugPrint('LLM plugin [${manifest.name}] loaded'); }
  Future<void> onUnload() async { debugPrint('LLM plugin [${manifest.name}] unloaded'); }
  Future<void> onEnable() async { await _initProvider(); }
  Future<void> onDisable() async { _provider = null; }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _initProvider();
  }

  Future<void> _initProvider() async {
    if (manifest.providerUrl != null && _apiKey != null) {
      _provider = LLMProvider(
        name: manifest.name,
        endpoint: manifest.providerUrl!,
        apiKey: _apiKey!,
        modelName: manifest.modelName ?? 'default',
      );
    }
  }

  Future<CompletionResult> complete(String prompt, {Map<String, dynamic>? options}) async {
    if (_provider != null) {
      return _provider!.complete(prompt, options: options);
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return CompletionResult(text: 'Plugin [${manifest.name}] response to: "$prompt"', tokens: prompt.length ~/ 4);
  }

  Future<CompletionResult> chatCompletion(List<Map<String, String>> messages, {Map<String, dynamic>? options}) async {
    if (_provider != null) {
      return _provider!.chatCompletions(messages, options: options);
    }
    await Future.delayed(const Duration(milliseconds: 300));
    final lastContent = messages.isNotEmpty ? messages.last['content'] ?? '' : '';
    return CompletionResult(text: 'Plugin [${manifest.name}] chat response based on ${messages.length} messages', tokens: lastContent.length ~/ 4);
  }
}

class LLMProvider {
  final String name;
  final String endpoint;
  final String apiKey;
  final String modelName;

  LLMProvider({
    required this.name,
    required this.endpoint,
    required this.apiKey,
    required this.modelName,
  });

  Future<CompletionResult> complete(String prompt, {Map<String, dynamic>? options}) async {
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': modelName,
          'prompt': prompt,
          'max_tokens': options?['max_tokens'] ?? 1024,
          'temperature': options?['temperature'] ?? 0.7,
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final text = data['choices']?[0]?['text'] ?? data['response'] ?? '';
        final tokens = data['usage']?['total_tokens'] ?? text.length ~/ 4;
        return CompletionResult(text: text as String, tokens: tokens as int);
      }
      return CompletionResult(text: '', tokens: 0);
    } catch (e) {
      debugPrint('LLMProvider completion error: $e');
      return CompletionResult(text: '', tokens: 0);
    }
  }

  Future<CompletionResult> chatCompletions(List<Map<String, String>> messages, {Map<String, dynamic>? options}) async {
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': modelName,
          'messages': messages,
          'max_tokens': options?['max_tokens'] ?? 1024,
          'temperature': options?['temperature'] ?? 0.7,
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        final text = choices?.isNotEmpty == true
            ? (choices!.first as Map<String, dynamic>)['message']?['content'] ?? ''
            : '';
        final tokens = data['usage']?['total_tokens'] ?? text.toString().length ~/ 4;
        return CompletionResult(text: text.toString(), tokens: tokens as int);
      }
      return CompletionResult(text: '', tokens: 0);
    } catch (e) {
      debugPrint('LLMProvider chat error: $e');
      return CompletionResult(text: '', tokens: 0);
    }
  }
}

class CompletionResult {
  final String text;
  final int tokens;

  CompletionResult({required this.text, this.tokens = 0});
}

class PluginCompletionResult {
  final bool success;
  final String? text;
  final int? tokens;
  final String? error;

  PluginCompletionResult({required this.success, this.text, this.tokens, this.error});
}

class PluginHook {
  final String event;
  final Future<void> Function(Map<String, dynamic>) handler;

  PluginHook({required this.event, required this.handler});
}

class PluginEvent {
  final String pluginName;
  final PluginEventType type;
  final String? message;

  PluginEvent._({required this.pluginName, required this.type, this.message});

  factory PluginEvent.loaded(String name) => PluginEvent._(pluginName: name, type: PluginEventType.loaded);
  factory PluginEvent.unloaded(String name) => PluginEvent._(pluginName: name, type: PluginEventType.unloaded);
  factory PluginEvent.enabled(String name) => PluginEvent._(pluginName: name, type: PluginEventType.enabled);
  factory PluginEvent.disabled(String name) => PluginEvent._(pluginName: name, type: PluginEventType.disabled);
}

enum PluginEventType { loaded, unloaded, enabled, disabled }