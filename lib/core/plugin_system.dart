import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// LLM-Friendly Plugin System - AI-powered plugin generation and management
///
/// Designed for LLMs to auto-generate plugins from natural language descriptions:
/// - Structured API specification for LLMs to understand
/// - Automatic plugin code generation from descriptions
/// - Runtime plugin validation and execution
/// - Plugin templates and patterns for common use cases
/// - Natural language plugin creation via /create-plugin command
class PluginSystem {
  bool _isInitialized = false;

  // Plugin management
  final Map<String, Plugin> _plugins = {};
  final Map<String, PluginIsolate> _pluginIsolates = {};
  final List<String> _pluginPaths = [];

  // LLM Plugin Generation
  final LLMPluginGenerator _llmGenerator = LLMPluginGenerator();

  // Plugin registry
  final PluginRegistry _registry = PluginRegistry();

  // Event system
  final Map<String, List<PluginEventHandler>> _eventHandlers = {};
  final StreamController<PluginEvent> _eventController = StreamController.broadcast();

  // API access
  final PluginAPI _api = PluginAPI();

  // Theme engine
  final ThemeEngine _themeEngine = ThemeEngine();

  // Marketplace
  final PluginMarketplace _marketplace = PluginMarketplace();
  
  PluginSystem();
  
  bool get isInitialized => _isInitialized;
  Map<String, Plugin> get plugins => Map.unmodifiable(_plugins);
  Stream<PluginEvent> get events => _eventController.stream;
  PluginAPI get api => _api;
  ThemeEngine get themeEngine => _themeEngine;
  PluginMarketplace get marketplace => _marketplace;
  
  /// Initialize plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize plugin paths
      await _initializePluginPaths();

      // Initialize LLM generator
      await _llmGenerator.initialize();

      // Load installed plugins
      await _loadInstalledPlugins();

      // Initialize API
      await _api.initialize();

      // Initialize theme engine
      await _themeEngine.initialize();

      // Initialize marketplace
      await _marketplace.initialize();

      _isInitialized = true;
      debugPrint('🔌 LLM-Friendly Plugin System initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Plugin System: $e');
    }
  }
  
  /// Initialize plugin paths
  Future<void> _initializePluginPaths() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    _pluginPaths.addAll([
      '$homeDir/.termisol/plugins',
      '/usr/local/share/termisol/plugins',
      '/opt/termisol/plugins',
    ]);
    
    // Create user plugin directory
    final userPluginDir = Directory('$homeDir/.termisol/plugins');
    if (!await userPluginDir.exists()) {
      await userPluginDir.create(recursive: true);
    }
  }
  
  /// Load installed plugins
  Future<void> _loadInstalledPlugins() async {
    for (final path in _pluginPaths) {
      await _scanPluginDirectory(path);
    }
  }
  
  /// Scan plugin directory for plugins
  Future<void> _scanPluginDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) return;
      
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          await _loadPluginFromDirectory(entity);
        } else if (entity is File && entity.path.endsWith('.termisol-plugin')) {
          await _loadPluginFromFile(entity);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to scan plugin directory: $e');
    }
  }
  
  /// Load plugin from directory
  Future<void> _loadPluginFromDirectory(Directory directory) async {
    try {
      final manifestFile = File('${directory.path}/plugin.json');
      if (!await manifestFile.exists()) return;
      
      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
      
      final plugin = Plugin.fromJson(manifest, directory.path);
      await _loadPlugin(plugin);
    } catch (e) {
      debugPrint('⚠️ Failed to load plugin from ${directory.path}: $e');
    }
  }
  
  /// Load plugin from file
  Future<void> _loadPluginFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      final plugin = Plugin.fromJson(data, file.path);
      await _loadPlugin(plugin);
    } catch (e) {
      debugPrint('⚠️ Failed to load plugin from ${file.path}: $e');
    }
  }
  
  /// Load plugin
  Future<void> _loadPlugin(Plugin plugin) async {
    try {
      // Validate plugin
      if (!_validatePlugin(plugin)) {
        debugPrint('❌ Plugin validation failed: ${plugin.name}');
        return;
      }
      
      // Check dependencies
      if (!await _checkDependencies(plugin)) {
        debugPrint('❌ Plugin dependencies not satisfied: ${plugin.name}');
        return;
      }
      
      // Load plugin in isolate
      final isolate = await _loadPluginIsolate(plugin);
      if (isolate == null) return;
      
      _plugins[plugin.id] = plugin;
      _pluginIsolates[plugin.id] = isolate;
      
      // Register event handlers
      for (final event in plugin.events) {
        _registerEventHandler(event, plugin.id);
      }
      
      // Emit plugin loaded event
      _emitEvent(PluginEvent(
        type: PluginEventType.pluginLoaded,
        pluginId: plugin.id,
        data: {'plugin': plugin.toJson()},
      ));
      
      debugPrint('🔌 Loaded plugin: ${plugin.name} v${plugin.version}');
    } catch (e) {
      debugPrint('❌ Failed to load plugin ${plugin.name}: $e');
    }
  }
  
  /// Validate plugin
  bool _validatePlugin(Plugin plugin) {
    // Check required fields
    if (plugin.name.isEmpty || plugin.version.isEmpty || plugin.id.isEmpty) {
      return false;
    }
    
    // Check API version compatibility
    if (!plugin.apiVersion.startsWith('1.')) {
      return false;
    }
    
    // Check entry point
    if (plugin.entryPoint.isEmpty) {
      return false;
    }
    
    return true;
  }
  
  /// Check plugin dependencies
  Future<bool> _checkDependencies(Plugin plugin) async {
    for (final dependency in plugin.dependencies) {
      if (dependency.type == DependencyType.plugin) {
        final requiredPlugin = _plugins[dependency.name];
        if (requiredPlugin == null) {
          return false;
        }
        
        if (!_isVersionCompatible(requiredPlugin.version, dependency.version)) {
          return false;
        }
      } else if (dependency.type == DependencyType.system) {
        if (!await _checkSystemDependency(dependency)) {
          return false;
        }
      }
    }
    
    return true;
  }
  
  /// Check version compatibility
  bool _isVersionCompatible(String installed, String required) {
    // Simple version comparison (could be enhanced with semver)
    final installedParts = installed.split('.').map(int.parse).toList();
    final requiredParts = required.split('.').map(int.parse).toList();
    
    for (int i = 0; i < requiredParts.length; i++) {
      if (i >= installedParts.length) return false;
      if (installedParts[i] < requiredParts[i]) return false;
      if (installedParts[i] > requiredParts[i]) return true;
    }
    
    return true;
  }
  
  /// Check system dependency
  Future<bool> _checkSystemDependency(Dependency dependency) async {
    try {
      final result = await Process.run('which', [dependency.name]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
  
  /// Load plugin in isolate
  Future<PluginIsolate?> _loadPluginIsolate(Plugin plugin) async {
    try {
      final entryPoint = '${plugin.path}/${plugin.entryPoint}';
      final receivePort = ReceivePort();
      
      final isolate = await Isolate.spawn(
        _pluginIsolateEntry,
        receivePort.sendPort,
        debugName: plugin.name,
      );
      
      final sendPort = await receivePort.first as SendPort;
      
      // Initialize plugin
      final initResponse = await _sendPluginMessage(
        sendPort,
        PluginMessage(
          type: 'init',
          data: {
            'plugin': plugin.toJson(),
            'api': _api.getApiSpec(),
          },
        ),
      );
      
      if (initResponse['success'] == true) {
        return PluginIsolate(
          isolate: isolate,
          sendPort: sendPort,
          receivePort: receivePort,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load plugin isolate: $e');
    }
    
    return null;
  }
  
  /// Plugin isolate entry point
  static void _pluginIsolateEntry(SendPort sendPort) {
    // This would be the actual plugin execution environment
    // For now, just echo back messages
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) {
      try {
        final pluginMessage = PluginMessage.fromJson(message as Map<String, dynamic>);
        
        switch (pluginMessage.type) {
          case 'init':
            sendPort.send({'success': true, 'message': 'Plugin initialized'});
            break;
          case 'execute':
            sendPort.send({'success': true, 'result': 'Command executed'});
            break;
          case 'event':
            // Handle plugin events
            break;
          default:
            sendPort.send({'success': false, 'error': 'Unknown message type'});
        }
      } catch (e) {
        sendPort.send({'success': false, 'error': e.toString()});
      }
    });
  }
  
  /// Send message to plugin
  Future<Map<String, dynamic>> _sendPluginMessage(
    SendPort sendPort,
    PluginMessage message,
  ) async {
    final responsePort = ReceivePort();
    sendPort.send({
      ...message.toJson(),
      'responsePort': responsePort.sendPort,
    });
    
    return await responsePort.first as Map<String, dynamic>;
  }
  
  /// Unload plugin
  Future<void> unloadPlugin(String pluginId) async {
    try {
      final plugin = _plugins[pluginId];
      if (plugin == null) return;
      
      final isolate = _pluginIsolates[pluginId];
      if (isolate != null) {
        await _sendPluginMessage(
          isolate.sendPort,
          PluginMessage(type: 'cleanup'),
        );
        
        isolate.isolate.kill(priority: Isolate.immediate);
        isolate.receivePort.close();
        _pluginIsolates.remove(pluginId);
      }
      
      // Unregister event handlers
      for (final event in plugin.events) {
        _unregisterEventHandler(event, pluginId);
      }
      
      _plugins.remove(pluginId);
      
      // Emit plugin unloaded event
      _emitEvent(PluginEvent(
        type: PluginEventType.pluginUnloaded,
        pluginId: pluginId,
        data: {'plugin': plugin.toJson()},
      ));
      
      debugPrint('🔌 Unloaded plugin: ${plugin.name}');
    } catch (e) {
      debugPrint('❌ Failed to unload plugin $pluginId: $e');
    }
  }
  
  /// Execute plugin command
  Future<PluginResult> executePluginCommand(
    String pluginId,
    String command,
    Map<String, dynamic> args,
  ) async {
    try {
      final isolate = _pluginIsolates[pluginId];
      if (isolate == null) {
        return PluginResult(
          success: false,
          error: 'Plugin not loaded: $pluginId',
        );
      }
      
      final response = await _sendPluginMessage(
        isolate.sendPort,
        PluginMessage(
          type: 'execute',
          data: {
            'command': command,
            'args': args,
          },
        ),
      );
      
      return PluginResult.fromJson(response);
    } catch (e) {
      return PluginResult(
        success: false,
        error: 'Failed to execute command: $e',
      );
    }
  }
  
  /// Register event handler
  void _registerEventHandler(String eventType, String pluginId) {
    if (!_eventHandlers.containsKey(eventType)) {
      _eventHandlers[eventType] = [];
    }
    
    _eventHandlers[eventType]!.add(PluginEventHandler(
      pluginId: pluginId,
      eventType: eventType,
    ));
  }
  
  /// Unregister event handler
  void _unregisterEventHandler(String eventType, String pluginId) {
    final handlers = _eventHandlers[eventType];
    if (handlers != null) {
      handlers.removeWhere((handler) => handler.pluginId == pluginId);
    }
  }
  
  /// Emit event to plugins
  void _emitEvent(PluginEvent event) {
    _eventController.add(event);
    
    final handlers = _eventHandlers[event.type.toString()];
    if (handlers != null) {
      for (final handler in handlers) {
        final isolate = _pluginIsolates[handler.pluginId];
        if (isolate != null) {
          _sendPluginMessage(
            isolate.sendPort,
            PluginMessage(
              type: 'event',
              data: event.toJson(),
            ),
          );
        }
      }
    }
  }
  
  /// Install plugin from marketplace
  Future<bool> installPlugin(String pluginId) async {
    try {
      final pluginInfo = await _marketplace.getPluginInfo(pluginId);
      if (pluginInfo == null) return false;
      
      // Download plugin
      final success = await _marketplace.downloadPlugin(pluginId);
      if (!success) return false;
      
      // Load plugin
      await _loadInstalledPlugins();
      
      // Emit plugin installed event
      _emitEvent(PluginEvent(
        type: PluginEventType.pluginInstalled,
        pluginId: pluginId,
        data: {'plugin': pluginInfo.toJson()},
      ));
      
      return true;
    } catch (e) {
      debugPrint('❌ Failed to install plugin $pluginId: $e');
      return false;
    }
  }
  
  /// Uninstall plugin
  Future<bool> uninstallPlugin(String pluginId) async {
    try {
      final plugin = _plugins[pluginId];
      if (plugin == null) return false;
      
      // Unload plugin first
      await unloadPlugin(pluginId);
      
      // Remove plugin files
      final pluginDir = Directory(plugin.path);
      if (await pluginDir.exists()) {
        await pluginDir.delete(recursive: true);
      }
      
      // Emit plugin uninstalled event
      _emitEvent(PluginEvent(
        type: PluginEventType.pluginUninstalled,
        pluginId: pluginId,
        data: {'plugin': plugin.toJson()},
      ));
      
      return true;
    } catch (e) {
      debugPrint('❌ Failed to uninstall plugin $pluginId: $e');
      return false;
    }
  }
  
  /// Get plugin by ID
  Plugin? getPlugin(String pluginId) {
    return _plugins[pluginId];
  }
  
  /// Get all plugins
  List<Plugin> getAllPlugins() {
    return _plugins.values.toList();
  }
  
  /// Get enabled plugins
  List<Plugin> getEnabledPlugins() {
    return _plugins.values.where((plugin) => plugin.enabled).toList();
  }
  
  /// Enable/disable plugin
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return;
    
    if (enabled && !plugin.enabled) {
      await _loadPlugin(plugin);
    } else if (!enabled && plugin.enabled) {
      await unloadPlugin(pluginId);
    }
    
    plugin.enabled = enabled;
  }
  
  /// Create plugin from natural language description using LLM
  Future<PluginCreationResult> createPluginFromDescription(String description) async {
    try {
      debugPrint('🤖 Generating plugin from description: $description');

      final pluginSpec = await _llmGenerator.generatePluginSpec(description);
      if (pluginSpec == null) {
        return PluginCreationResult(
          success: false,
          error: 'Failed to generate plugin specification',
        );
      }

      final pluginCode = await _llmGenerator.generatePluginCode(pluginSpec);
      if (pluginCode == null) {
        return PluginCreationResult(
          success: false,
          error: 'Failed to generate plugin code',
        );
      }

      final plugin = await _createPluginFromGeneratedCode(pluginSpec, pluginCode);

      return PluginCreationResult(
        success: true,
        plugin: plugin,
      );
    } catch (e) {
      debugPrint('❌ Failed to create plugin from description: $e');
      return PluginCreationResult(
        success: false,
        error: 'Plugin creation failed: $e',
      );
    }
  }

  /// Generate plugin from user query (for /create-plugin command)
  Future<String> generatePluginFromQuery(String query) async {
    try {
      final result = await createPluginFromDescription(query);

      if (result.success && result.plugin != null) {
        await _loadPlugin(result.plugin!);
        return '✅ Plugin "${result.plugin!.name}" created and loaded successfully!\n\n' +
               'Description: ${result.plugin!.description}\n' +
               'Commands: ${result.plugin!.events.join(", ")}\n\n' +
               'You can now use the plugin functionality.';
      } else {
        return '❌ Failed to create plugin: ${result.error}';
      }
    } catch (e) {
      return '❌ Plugin generation failed: $e';
    }
  }

  /// Create plugin from generated code
  Future<Plugin> _createPluginFromGeneratedCode(PluginSpec spec, String code) async {
    // Create plugin directory
    final pluginDir = Directory('$_pluginPaths[0]/${spec.id}');
    await pluginDir.create(recursive: true);

    // Write plugin code
    final codeFile = File('${pluginDir.path}/plugin.dart');
    await codeFile.writeAsString(code);

    // Create manifest
    final manifest = {
      'id': spec.id,
      'name': spec.name,
      'version': '1.0.0',
      'description': spec.description,
      'author': 'AI Generated',
      'apiVersion': '1.0',
      'events': spec.events,
      'dependencies': spec.dependencies.map((d) => d.toJson()).toList(),
      'entryPoint': 'plugin.dart',
    };

    final manifestFile = File('${pluginDir.path}/plugin.json');
    await manifestFile.writeAsString(jsonEncode(manifest));

    return Plugin.fromJson(manifest, pluginDir.path);
  }

  /// Get LLM API specification for plugin generation
  Map<String, dynamic> getLLMPluginAPISpec() {
    return _llmGenerator.getAPISpecification();
  }

  /// Dispose plugin system
  Future<void> dispose() async {
    // Unload all plugins
    for (final pluginId in _plugins.keys.toList()) {
      await unloadPlugin(pluginId);
    }

    // Close event stream
    await _eventController.close();

    // Dispose components
    await _llmGenerator.dispose();
    await _api.dispose();
    await _themeEngine.dispose();
    await _marketplace.dispose();

    _plugins.clear();
    _pluginIsolates.clear();
    _eventHandlers.clear();
    _isInitialized = false;

    debugPrint('🔌 Plugin System disposed');
  }
}

/// Plugin data structure
class Plugin {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String apiVersion;
  final List<String> events;
  final List<Dependency> dependencies;
  final String entryPoint;
  final String path;
  bool enabled = true;
  
  Plugin({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.apiVersion,
    required this.events,
    required this.dependencies,
    required this.entryPoint,
    required this.path,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    'apiVersion': apiVersion,
    'events': events,
    'dependencies': dependencies.map((d) => d.toJson()).toList(),
    'entryPoint': entryPoint,
    'path': path,
    'enabled': enabled,
  };
  
  factory Plugin.fromJson(Map<String, dynamic> json, String path) => Plugin(
    id: json['id'] as String,
    name: json['name'] as String,
    version: json['version'] as String,
    description: json['description'] as String,
    author: json['author'] as String,
    apiVersion: json['apiVersion'] as String,
    events: List<String>.from(json['events'] as List? ?? []),
    dependencies: (json['dependencies'] as List<dynamic>?)
        ?.map((d) => Dependency.fromJson(d as Map<String, dynamic>))
        .toList() ?? [],
    entryPoint: json['entryPoint'] as String,
    path: path,
  )..enabled = json['enabled'] as bool? ?? true;
}

/// Plugin isolate data structure
class PluginIsolate {
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;
  
  PluginIsolate({
    required this.isolate,
    required this.sendPort,
    required this.receivePort,
  });
}

/// Plugin message data structure
class PluginMessage {
  final String type;
  final Map<String, dynamic> data;
  
  PluginMessage({
    required this.type,
    required this.data,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
  };
  
  factory PluginMessage.fromJson(Map<String, dynamic> json) => PluginMessage(
    type: json['type'] as String,
    data: json['data'] as Map<String, dynamic>,
  );
}

/// Plugin result data structure
class PluginResult {
  final bool success;
  final dynamic result;
  final String? error;
  
  PluginResult({
    required this.success,
    this.result,
    this.error,
  });
  
  Map<String, dynamic> toJson() => {
    'success': success,
    'result': result,
    'error': error,
  };
  
  factory PluginResult.fromJson(Map<String, dynamic> json) => PluginResult(
    success: json['success'] as bool,
    result: json['result'],
    error: json['error'] as String?,
  );
}

/// Plugin event data structure
class PluginEvent {
  final PluginEventType type;
  final String? pluginId;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  PluginEvent({
    required this.type,
    this.pluginId,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'pluginId': pluginId,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Plugin event handler data structure
class PluginEventHandler {
  final String pluginId;
  final String eventType;
  
  PluginEventHandler({
    required this.pluginId,
    required this.eventType,
  });
}

/// Dependency data structure
class Dependency {
  final String name;
  final String version;
  final DependencyType type;
  
  Dependency({
    required this.name,
    required this.version,
    required this.type,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'type': type.toString(),
  };
  
  factory Dependency.fromJson(Map<String, dynamic> json) => Dependency(
    name: json['name'] as String,
    version: json['version'] as String,
    type: DependencyType.values.firstWhere(
      (t) => t.toString() == json['type'],
      orElse: () => DependencyType.plugin,
    ),
  );
}

/// Plugin event type enumeration
enum PluginEventType {
  pluginLoaded,
  pluginUnloaded,
  pluginInstalled,
  pluginUninstalled,
  terminalReady,
  commandExecuted,
  themeChanged,
  sessionCreated,
  sessionClosed,
}

/// Dependency type enumeration
enum DependencyType {
  plugin,
  system,
  library,
}

/// Plugin registry for managing plugin metadata
class PluginRegistry {
  final Map<String, PluginMetadata> _registry = {};
  
  PluginRegistry();
  
  Future<void> initialize() async {
    // Load registry from file or remote
    await _loadRegistry();
  }
  
  Future<void> _loadRegistry() async {
    // Implementation for loading plugin registry
  // This could be from a local cache or remote server
  debugPrint('📚 Plugin registry initialized');
  }
  
  PluginMetadata? getPluginMetadata(String pluginId) {
    return _registry[pluginId];
  }
  
  List<PluginMetadata> searchPlugins(String query) {
    return _registry.values
        .where((plugin) => 
            plugin.name.toLowerCase().contains(query.toLowerCase()) ||
            plugin.description.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}

/// Plugin metadata data structure
class PluginMetadata {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<String> tags;
  final int downloads;
  final double rating;
  final DateTime lastUpdated;
  
  PluginMetadata({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.tags,
    required this.downloads,
    required this.rating,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    'tags': tags,
    'downloads': downloads,
    'rating': rating,
    'lastUpdated': lastUpdated.toIso8601String(),
  };
}

/// Plugin API for plugins to interact with terminal
class PluginAPI {
  bool _isInitialized = false;
  
  PluginAPI();
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isInitialized = true;
    debugPrint('🔌 Plugin API initialized');
  }
  
  Map<String, dynamic> getApiSpec() {
    return {
      'version': '1.0.0',
      'methods': [
        'writeToTerminal',
        'readFromTerminal',
        'executeCommand',
        'showNotification',
        'setTheme',
        'registerCommand',
        'unregisterCommand',
      ],
    };
  }
  
  Future<void> dispose() async {
    _isInitialized = false;
    debugPrint('🔌 Plugin API disposed');
  }
}

/// Theme engine for dynamic theming
class ThemeEngine {
  bool _isInitialized = false;
  final Map<String, ThemeData> _themes = {};
  String _currentTheme = 'default';
  
  ThemeEngine();
  
  bool get isInitialized => _isInitialized;
  String get currentTheme => _currentTheme;
  Map<String, ThemeData> get themes => Map.unmodifiable(_themes);
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Load default themes
    await _loadDefaultThemes();
    
    _isInitialized = true;
    debugPrint('🎨 Theme Engine initialized');
  }
  
  Future<void> _loadDefaultThemes() async {
    // Implementation for loading default themes
    _themes['default'] = ThemeData(
      name: 'Default',
      backgroundColor: const Color(0xFF1e1e1e),
      foregroundColor: const Color(0xFFffffff),
      cursorColor: const Color(0xFF00ff00),
    );
    
    _themes['dark'] = ThemeData(
      name: 'Dark',
      backgroundColor: const Color(0xFF000000),
      foregroundColor: const Color(0xFFffffff),
      cursorColor: const Color(0xFF00ff00),
    );
  }
  
  void setTheme(String themeName) {
    if (_themes.containsKey(themeName)) {
      _currentTheme = themeName;
      debugPrint('🎨 Theme changed to: $themeName');
    }
  }
  
  ThemeData? getCurrentThemeData() {
    return _themes[_currentTheme];
  }
  
  Future<void> dispose() async {
    _themes.clear();
    _isInitialized = false;
    debugPrint('🎨 Theme Engine disposed');
  }
}

/// Plugin marketplace for downloading plugins
class PluginMarketplace {
  bool _isInitialized = false;
  final String _baseUrl = 'https://plugins.termisol.dev/api';
  
  PluginMarketplace();
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isInitialized = true;
    debugPrint('🛒 Plugin Marketplace initialized');
  }
  
  Future<PluginMetadata?> getPluginInfo(String pluginId) async {
    try {
      // Implementation for getting plugin info from marketplace
      // This would make HTTP requests to the marketplace API
      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to get plugin info: $e');
      return null;
    }
  }
  
  Future<bool> downloadPlugin(String pluginId) async {
    try {
      // Implementation for downloading plugin
      // This would download and extract plugin files
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to download plugin: $e');
      return false;
    }
  }
  
  Future<List<PluginMetadata>> searchPlugins(String query) async {
    try {
      // Implementation for searching plugins
      return [];
    } catch (e) {
      debugPrint('⚠️ Failed to search plugins: $e');
      return [];
    }
  }
  
  Future<void> dispose() async {
    _isInitialized = false;
    debugPrint('🛒 Plugin Marketplace disposed');
  }
}

/// Theme data structure
class ThemeData {
  final String name;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color cursorColor;
  final Map<String, Color> ansiColors;

  ThemeData({
    required this.name,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.cursorColor,
    Map<String, Color>? ansiColors,
  }) : ansiColors = ansiColors ?? {};
}

/// LLM Plugin Generator - AI-powered plugin creation
class LLMPluginGenerator {
  bool _isInitialized = false;
  final Map<String, PluginTemplate> _templates = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadPluginTemplates();
    _isInitialized = true;
    debugPrint('🤖 LLM Plugin Generator initialized');
  }

  Future<void> _loadPluginTemplates() async {
    // Load common plugin templates that LLMs can use as reference
    _templates['command'] = PluginTemplate(
      name: 'Command Plugin',
      description: 'Adds custom terminal commands',
      example: 'Create a plugin that adds a "weather" command to show current weather',
      structure: {
        'commands': ['weather'],
        'events': ['command.weather'],
        'dependencies': [],
      },
    );

    _templates['theme'] = PluginTemplate(
      name: 'Theme Plugin',
      description: 'Custom terminal themes and color schemes',
      example: 'Create a solarized dark theme plugin',
      structure: {
        'themes': ['solarized_dark'],
        'events': ['theme.changed'],
        'dependencies': [],
      },
    );

    _templates['integration'] = PluginTemplate(
      name: 'Integration Plugin',
      description: 'Integrates with external services',
      example: 'Create a GitHub integration plugin for issue management',
      structure: {
        'services': ['github'],
        'events': ['integration.github'],
        'dependencies': ['http'],
      },
    );

    debugPrint('📋 Loaded ${_templates.length} plugin templates');
  }

  /// Generate plugin specification from natural language description
  Future<PluginSpec?> generatePluginSpec(String description) async {
    try {
      // This would use the NVIDIA AI client to generate plugin spec
      // For now, return a mock spec based on the description

      final spec = PluginSpec(
        id: 'plugin_${DateTime.now().millisecondsSinceEpoch}',
        name: _extractPluginName(description),
        description: description,
        events: _inferEvents(description),
        dependencies: _inferDependencies(description),
        template: _matchTemplate(description),
      );

      return spec;
    } catch (e) {
      debugPrint('❌ Failed to generate plugin spec: $e');
      return null;
    }
  }

  /// Generate plugin code from specification
  Future<String?> generatePluginCode(PluginSpec spec) async {
    try {
      // This would use the NVIDIA AI client to generate actual Dart code
      // For now, return a template-based implementation

      final template = _templates[spec.template];
      if (template == null) return null;

      final code = _generateCodeFromTemplate(spec, template);
      return code;
    } catch (e) {
      debugPrint('❌ Failed to generate plugin code: $e');
      return null;
    }
  }

  /// Get API specification for LLMs
  Map<String, dynamic> getAPISpecification() {
    return {
      'version': '1.0',
      'templates': _templates.map((key, template) => MapEntry(key, template.toJson())),
      'api_methods': [
        'registerCommand',
        'addTheme',
        'createIntegration',
        'showNotification',
        'executeTerminalCommand',
        'readTerminalOutput',
      ],
      'events': [
        'command.executed',
        'theme.changed',
        'integration.called',
        'notification.shown',
      ],
      'dependencies': [
        'http',
        'path',
        'dart:io',
        'flutter',
      ],
    };
  }

  String _extractPluginName(String description) {
    // Simple name extraction - could be enhanced with AI
    final words = description.split(' ');
    if (words.isNotEmpty) {
      return words.first.toLowerCase();
    }
    return 'custom_plugin';
  }

  List<String> _inferEvents(String description) {
    final events = <String>[];
    final lower = description.toLowerCase();

    if (lower.contains('command')) {
      events.add('command.executed');
    }
    if (lower.contains('theme')) {
      events.add('theme.changed');
    }
    if (lower.contains('integration') || lower.contains('github') || lower.contains('api')) {
      events.add('integration.called');
    }

    return events.isNotEmpty ? events : ['plugin.activated'];
  }

  List<Dependency> _inferDependencies(String description) {
    final dependencies = <Dependency>[];
    final lower = description.toLowerCase();

    if (lower.contains('http') || lower.contains('api') || lower.contains('web')) {
      dependencies.add(Dependency(
        name: 'http',
        version: '1.0.0',
        type: DependencyType.library,
      ));
    }

    return dependencies;
  }

  String _matchTemplate(String description) {
    final lower = description.toLowerCase();

    if (lower.contains('command')) return 'command';
    if (lower.contains('theme') || lower.contains('color')) return 'theme';
    if (lower.contains('integration') || lower.contains('github') || lower.contains('api')) return 'integration';

    return 'command'; // default
  }

  String _generateCodeFromTemplate(PluginSpec spec, PluginTemplate template) {
    // Generate basic Dart plugin code based on template
    final buffer = StringBuffer();

    buffer.writeln('''
// Auto-generated plugin: ${spec.name}
// Generated from: ${spec.description}
// Template: ${template.name}

import 'dart:async';
import 'package:flutter/material.dart';

class ${spec.id.replaceAll('_', '').toUpperCase()}Plugin {
  static const String PLUGIN_ID = '${spec.id}';
  static const String PLUGIN_NAME = '${spec.name}';
  static const String PLUGIN_VERSION = '1.0.0';

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔌 Initializing ${spec.name} plugin');
    _isInitialized = true;
  }

  Future<void> dispose() async {
    _isInitialized = false;
    debugPrint('🔌 Disposed ${spec.name} plugin');
  }

  // Plugin-specific functionality would be implemented here
  Future<String> execute(String command, Map<String, dynamic> args) async {
    switch (command) {
''');

    for (final event in spec.events) {
      final eventName = event.split('.').last;
      buffer.writeln('      case \'$eventName\':');
      buffer.writeln('        return await _handle${eventName.toUpperCase()}(args);');
    }

    buffer.writeln('      default:');
    buffer.writeln('        return \'Unknown command: \$command\';');
    buffer.writeln('    }');
    buffer.writeln('  }');

    // Add handler methods
    for (final event in spec.events) {
      final eventName = event.split('.').last;
      buffer.writeln('');
      buffer.writeln('  Future<String> _handle${eventName.toUpperCase()}(Map<String, dynamic> args) async {');
      buffer.writeln('    // Add your ${eventName} functionality here');
      buffer.writeln('    debugPrint(\'📋 Handling ${eventName} with args: \$args\');');
      buffer.writeln('    return \'${eventName} executed successfully\';');
      buffer.writeln('  }');
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  Future<void> dispose() async {
    _templates.clear();
    _isInitialized = false;
    debugPrint('🤖 LLM Plugin Generator disposed');
  }
}

/// Plugin specification for generation
class PluginSpec {
  final String id;
  final String name;
  final String description;
  final List<String> events;
  final List<Dependency> dependencies;
  final String template;

  PluginSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.events,
    required this.dependencies,
    required this.template,
  });
}

/// Plugin creation result
class PluginCreationResult {
  final bool success;
  final Plugin? plugin;
  final String? error;

  PluginCreationResult({
    required this.success,
    this.plugin,
    this.error,
  });
}

/// Plugin template for code generation
class PluginTemplate {
  final String name;
  final String description;
  final String example;
  final Map<String, dynamic> structure;

  PluginTemplate({
    required this.name,
    required this.description,
    required this.example,
    required this.structure,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'example': example,
    'structure': structure,
  };
}
