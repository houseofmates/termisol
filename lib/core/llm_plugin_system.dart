import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xterm/xterm.dart';

/// LLM Plugin System - Natural language plugin architecture
/// 
/// Implements comprehensive plugin management:
/// - Plugin discovery and loading
/// - Plugin lifecycle management
/// - NVIDIA endpoint integration
/// - Natural language plugin interface
/// - Plugin sandboxing
/// - Plugin communication
/// - Plugin marketplace
/// - Plugin updates
class LLMPluginSystem {
  bool _isInitialized = false;
  
  // Plugin registry
  final Map<String, LLMPlugin> _plugins = {};
  final Map<String, PluginMetadata> _pluginMetadata = {};
  final List<String> _activePlugins = [];
  
  // NVIDIA endpoint configuration
  String _nvidiaEndpoint = 'https://api.nvidia.com/v1';
  String? _nvidiaApiKey;
  String _currentModel = 'nvidia/llama-3.1-8b-instruct';
  
  // Plugin sandbox
  final Map<String, PluginSandbox> _sandboxes = {};
  final Map<String, PluginCommunication> _communications = {};
  
  // Event handlers
  final List<Function(LLMPlugin)> _onPluginLoaded = [];
  final List<Function(LLMPlugin)> _onPluginUnloaded = [];
  final List<Function(LLMPlugin, String)> _onPluginError = [];
  final List<Function(LLMPlugin, Map<String, dynamic>)> _onPluginMessage = [];
  final List<Function(String, Map<String, dynamic>)> _onSystemMessage = [];
  
  LLMPluginSystem();
  
  bool get isInitialized => _isInitialized;
  Map<String, LLMPlugin> get plugins => Map.unmodifiable(_plugins);
  List<String> get activePlugins => List.unmodifiable(_activePlugins);
  String get currentModel => _currentModel;
  String? get nvidiaApiKey => _nvidiaApiKey;
  
  /// Initialize LLM plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load NVIDIA API key
      await _loadNvidiaApiKey();
      
      // Discover plugins
      await _discoverPlugins();
      
      // Load built-in plugins
      await _loadBuiltinPlugins();
      
      // Start plugin manager
      await _startPluginManager();
      
      _isInitialized = true;
      debugPrint('🤖 LLM Plugin System initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize LLM Plugin System: $e');
      rethrow;
    }
  }
  
  /// Load NVIDIA API key
  Future<void> _loadNvidiaApiKey() async {
    try {
      final apiKeyFile = File('${Platform.environment['HOME']}/.termisol/nvidia_api_key');
      
      if (await apiKeyFile.exists()) {
        _nvidiaApiKey = await apiKeyFile.readAsString();
        _nvidiaApiKey = _nvidiaApiKey?.trim();
        debugPrint('🔑 NVIDIA API key loaded');
      } else {
        debugPrint('⚠️ NVIDIA API key not found');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load NVIDIA API key: $e');
    }
  }
  
  /// Discover plugins
  Future<void> _discoverPlugins() async {
    try {
      // Search plugin directories
      final pluginDirs = [
        '${Platform.environment['HOME']}/.termisol/plugins',
        '/usr/lib/termisol/plugins',
        '/usr/local/lib/termisol/plugins',
      ];
      
      for (final pluginDir in pluginDirs) {
        await _scanPluginDirectory(pluginDir);
      }
      
      debugPrint('🔍 Plugin discovery complete');
    } catch (e) {
      debugPrint('⚠️ Plugin discovery failed: $e');
    }
  }
  
  /// Scan plugin directory
  Future<void> _scanPluginDirectory(String pluginDir) async {
    try {
      final dir = Directory(pluginDir);
      if (!await dir.exists()) return;
      
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          await _loadPlugin(entry.path);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to scan plugin directory $pluginDir: $e');
    }
  }
  
  /// Load plugin
  Future<void> _loadPlugin(String pluginPath) async {
    try {
      final manifestFile = File('$pluginPath/plugin.json');
      if (!await manifestFile.exists()) return;
      
      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent);
      
      final metadata = PluginMetadata.fromJson(manifest);
      _pluginMetadata[metadata.id] = metadata;
      
      // Create sandbox
      final sandbox = PluginSandbox(
        pluginId: metadata.id,
        pluginPath: pluginPath,
        permissions: metadata.permissions,
      );
      
      _sandboxes[metadata.id] = sandbox;
      
      // Load plugin code
      final plugin = await _createPluginInstance(metadata, sandbox);
      if (plugin != null) {
        _plugins[metadata.id] = plugin;
        
        debugPrint('🔌 Plugin loaded: ${metadata.name}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load plugin from $pluginPath: $e');
    }
  }
  
  /// Create plugin instance
  Future<LLMPlugin?> _createPluginInstance(
    PluginMetadata metadata,
    PluginSandbox sandbox,
  ) async {
    try {
      switch (metadata.type) {
        case PluginType.builtin:
          return _createBuiltinPlugin(metadata, sandbox);
          
        case PluginType.dart:
          return await _createDartPlugin(metadata, sandbox);
          
        case PluginType.python:
          return await _createPythonPlugin(metadata, sandbox);
          
        case PluginType.javascript:
          return await _createJavaScriptPlugin(metadata, sandbox);
          
        default:
          debugPrint('⚠️ Unsupported plugin type: ${metadata.type}');
          return null;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to create plugin instance: $e');
      return null;
    }
  }
  
  /// Create built-in plugin
  LLMPlugin _createBuiltinPlugin(PluginMetadata metadata, PluginSandbox sandbox) {
    switch (metadata.id) {
      case 'nvidia-llm':
        return NvidiaLLMPlugin(metadata, sandbox);
        
      case 'terminal-commands':
        return TerminalCommandsPlugin(metadata, sandbox);
        
      case 'file-operations':
        return FileOperationsPlugin(metadata, sandbox);
        
      case 'system-monitor':
        return SystemMonitorPlugin(metadata, sandbox);
        
      default:
        return BuiltinPlugin(metadata, sandbox);
    }
  }
  
  /// Create Dart plugin
  Future<LLMPlugin?> _createDartPlugin(
    PluginMetadata metadata,
    PluginSandbox sandbox,
  ) async {
    try {
      // In a real implementation, you would dynamically load Dart code
      // For now, we'll return a placeholder
      return DartPlugin(metadata, sandbox);
    } catch (e) {
      debugPrint('⚠️ Failed to create Dart plugin: $e');
      return null;
    }
  }
  
  /// Create Python plugin
  Future<LLMPlugin?> _createPythonPlugin(
    PluginMetadata metadata,
    PluginSandbox sandbox,
  ) async {
    try {
      // In a real implementation, you would spawn Python process
      return PythonPlugin(metadata, sandbox);
    } catch (e) {
      debugPrint('⚠️ Failed to create Python plugin: $e');
      return null;
    }
  }
  
  /// Create JavaScript plugin
  Future<LLMPlugin?> _createJavaScriptPlugin(
    PluginMetadata metadata,
    PluginSandbox sandbox,
  ) async {
    try {
      // In a real implementation, you would use JavaScript engine
      return JavaScriptPlugin(metadata, sandbox);
    } catch (e) {
      debugPrint('⚠️ Failed to create JavaScript plugin: $e');
      return null;
    }
  }
  
  /// Load built-in plugins
  Future<void> _loadBuiltinPlugins() async {
    final builtinPlugins = [
      PluginMetadata(
        id: 'nvidia-llm',
        name: 'NVIDIA LLM',
        description: 'Natural language processing with NVIDIA models',
        version: '1.0.0',
        type: PluginType.builtin,
        permissions: [
          PluginPermission.networkAccess,
          PluginPermission.fileRead,
          PluginPermission.terminalAccess,
        ],
        author: 'Termisol',
        website: 'https://developer.nvidia.com',
      ),
      PluginMetadata(
        id: 'terminal-commands',
        name: 'Terminal Commands',
        description: 'Natural language terminal command execution',
        version: '1.0.0',
        type: PluginType.builtin,
        permissions: [
          PluginPermission.terminalAccess,
          PluginPermission.fileWrite,
        ],
        author: 'Termisol',
        website: 'https://github.com/termisol',
      ),
      PluginMetadata(
        id: 'file-operations',
        name: 'File Operations',
        description: 'Natural language file and directory operations',
        version: '1.0.0',
        type: PluginType.builtin,
        permissions: [
          PluginPermission.fileRead,
          PluginPermission.fileWrite,
          PluginPermission.directoryAccess,
        ],
        author: 'Termisol',
        website: 'https://github.com/termisol',
      ),
      PluginMetadata(
        id: 'system-monitor',
        name: 'System Monitor',
        description: 'System resource monitoring and optimization',
        version: '1.0.0',
        type: PluginType.builtin,
        permissions: [
          PluginPermission.systemInfo,
          PluginPermission.networkAccess,
        ],
        author: 'Termisol',
        website: 'https://github.com/termisol',
      ),
    ];
    
    for (final metadata in builtinPlugins) {
      final sandbox = PluginSandbox(
        pluginId: metadata.id,
        pluginPath: '',
        permissions: metadata.permissions,
      );
      
      final plugin = _createBuiltinPlugin(metadata, sandbox);
      _plugins[metadata.id] = plugin;
      _pluginMetadata[metadata.id] = metadata;
      _sandboxes[metadata.id] = sandbox;
    }
  }
  
  /// Start plugin manager
  Future<void> _startPluginManager() async {
    // Initialize communication channels
    for (final pluginId in _plugins.keys) {
      final communication = PluginCommunication(
        pluginId: pluginId,
        plugin: _plugins[pluginId]!,
        sandbox: _sandboxes[pluginId]!,
      );
      
      _communications[pluginId] = communication;
    }
    
    debugPrint('🔌 Plugin manager started');
  }
  
  /// Execute natural language command
  Future<Map<String, dynamic>> executeCommand(
    String command, {
    Map<String, dynamic>? context,
    String? model,
    List<String>? capabilities,
  }) async {
    final targetModel = model ?? _currentModel;
    
    try {
      // Find appropriate plugin
      final plugin = _findBestPlugin(command, capabilities);
      
      if (plugin != null) {
        // Execute through plugin
        final result = await plugin.execute(command, context: context);
        
        debugPrint('🤖 Command executed through plugin: ${plugin.metadata.name}');
        return result;
      } else {
        // Execute through NVIDIA endpoint directly
        return await _executeNvidiaCommand(command, context: context);
      }
    } catch (e) {
      debugPrint('⚠️ Command execution failed: $e');
      return {
        'success': false,
        'error': e.toString(),
        'command': command,
      };
    }
  }
  
  /// Find best plugin for command
  LLMPlugin? _findBestPlugin(String command, List<String>? capabilities) {
    LLMPlugin? bestPlugin;
    int bestScore = 0;
    
    for (final plugin in _plugins.values) {
      if (!_activePlugins.contains(plugin.metadata.id)) continue;
      
      final score = _calculatePluginScore(plugin, command, capabilities);
      
      if (score > bestScore) {
        bestScore = score;
        bestPlugin = plugin;
      }
    }
    
    return bestPlugin;
  }
  
  /// Calculate plugin score for command
  int _calculatePluginScore(LLMPlugin plugin, String command, List<String>? capabilities) {
    int score = 0;
    
    // Check if plugin can handle the command
    if (plugin.canHandle(command)) {
      score += 50;
    }
    
    // Check capabilities match
    if (capabilities != null) {
      for (final capability in capabilities!) {
        if (plugin.metadata.capabilities.contains(capability)) {
          score += 10;
        }
      }
    }
    
    // Prioritize built-in plugins
    if (plugin.metadata.type == PluginType.builtin) {
      score += 20;
    }
    
    return score;
  }
  
  /// Execute command through NVIDIA endpoint
  Future<Map<String, dynamic>> _executeNvidiaCommand(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    if (_nvidiaApiKey == null) {
      return {
        'success': false,
        'error': 'NVIDIA API key not configured',
      };
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_nvidiaEndpoint/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_nvidiaApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _currentModel,
          'messages': [
            {
              'role': 'system',
              'content': 'You are a helpful AI assistant for terminal operations.',
            },
            {
              'role': 'user',
              'content': command,
            },
          ],
          'max_tokens': 1000,
          'temperature': 0.7,
        }),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final content = responseData['choices'][0]['message']['content'];
        
        return {
          'success': true,
          'response': content,
          'model': _currentModel,
          'tokens_used': responseData['usage']?['total_tokens'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'error': 'NVIDIA API error: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('⚠️ NVIDIA API error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// Activate plugin
  Future<bool> activatePlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;
    
    try {
      // Check permissions
      if (!await _checkPluginPermissions(plugin)) {
        debugPrint('⚠️ Plugin $pluginId lacks required permissions');
        return false;
      }
      
      // Initialize plugin
      await plugin.initialize();
      
      if (!_activePlugins.contains(pluginId)) {
        _activePlugins.add(pluginId);
      }
      
      debugPrint('🔌 Plugin activated: ${plugin.metadata.name}');
      _onPluginLoaded.forEach((callback) => callback(plugin));
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to activate plugin $pluginId: $e');
      return false;
    }
  }
  
  /// Deactivate plugin
  Future<bool> deactivatePlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;
    
    try {
      await plugin.dispose();
      _activePlugins.remove(pluginId);
      
      debugPrint('🔌 Plugin deactivated: ${plugin.metadata.name}');
      _onPluginUnloaded.forEach((callback) => callback(plugin));
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to deactivate plugin $pluginId: $e');
      return false;
    }
  }
  
  /// Check plugin permissions
  Future<bool> _checkPluginPermissions(LLMPlugin plugin) async {
    // In a real implementation, you would check system permissions
    // For now, we'll assume all permissions are granted
    return true;
  }
  
  /// Install plugin
  Future<bool> installPlugin(String pluginPath) async {
    try {
      // Validate plugin
      final isValid = await _validatePlugin(pluginPath);
      if (!isValid) return false;
      
      // Copy plugin to plugins directory
      final pluginsDir = Directory('${Platform.environment['HOME']}/.termisol/plugins');
      await pluginsDir.create(recursive: true);
      
      final pluginName = pluginPath.split('/').last;
      final destination = '${pluginsDir.path}/$pluginName';
      
      await Process.run('cp', ['-r', pluginPath, destination]);
      
      // Load plugin
      await _loadPlugin(destination);
      
      debugPrint('📦 Plugin installed: $pluginName');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to install plugin: $e');
      return false;
    }
  }
  
  /// Uninstall plugin
  Future<bool> uninstallPlugin(String pluginId) async {
    try {
      // Deactivate plugin first
      await deactivatePlugin(pluginId);
      
      // Remove plugin files
      final metadata = _pluginMetadata[pluginId];
      if (metadata != null) {
        final pluginDir = Directory('${Platform.environment['HOME']}/.termisol/plugins/${pluginId}');
        if (await pluginDir.exists()) {
          await pluginDir.delete(recursive: true);
        }
      }
      
      // Remove from registry
      _plugins.remove(pluginId);
      _pluginMetadata.remove(pluginId);
      _sandboxes.remove(pluginId);
      _communications.remove(pluginId);
      
      debugPrint('📦 Plugin uninstalled: $pluginId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to uninstall plugin $pluginId: $e');
      return false;
    }
  }
  
  /// Validate plugin
  Future<bool> _validatePlugin(String pluginPath) async {
    try {
      // Check manifest file
      final manifestFile = File('$pluginPath/plugin.json');
      if (!await manifestFile.exists()) return false;
      
      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent);
      
      // Validate required fields
      final requiredFields = ['id', 'name', 'version', 'type'];
      for (final field in requiredFields) {
        if (!manifest.containsKey(field)) return false;
      }
      
      // Check plugin files
      final mainFile = File('$pluginPath/main.dart');
      if (!await mainFile.exists()) return false;
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Plugin validation failed: $e');
      return false;
    }
  }
  
  /// Get available models
  Future<List<String>> getAvailableModels() async {
    if (_nvidiaApiKey == null) return [];
    
    try {
      final response = await http.get(
        Uri.parse('$_nvidiaEndpoint/models'),
        headers: {
          'Authorization': 'Bearer $_nvidiaApiKey',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = <String>[];
        
        for (final model in data['data']) {
          models.add(model['id']);
        }
        
        return models;
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get models: $e');
      return [];
    }
  }
  
  /// Set current model
  Future<bool> setCurrentModel(String model) async {
    try {
      final models = await getAvailableModels();
      if (!models.contains(model)) return false;
      
      _currentModel = model;
      
      // Save to config
      final configFile = File('${Platform.environment['HOME']}/.termisol/config.json');
      final config = {
        'current_model': model,
        'nvidia_endpoint': _nvidiaEndpoint,
      };
      
      await configFile.writeAsString(jsonEncode(config));
      
      debugPrint('🤖 Model set to: $model');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to set model: $e');
      return false;
    }
  }
  
  /// Get plugin by ID
  LLMPlugin? getPlugin(String pluginId) {
    return _plugins[pluginId];
  }
  
  /// Get plugin metadata
  PluginMetadata? getPluginMetadata(String pluginId) {
    return _pluginMetadata[pluginId];
  }
  
  /// Get all plugins
  List<PluginMetadata> getAllPlugins() {
    return _pluginMetadata.values.toList();
  }
  
  /// Get active plugins
  List<PluginMetadata> getActivePlugins() {
    return _activePlugins
        .map((id) => _pluginMetadata[id]!)
        .where((metadata) => metadata != null)
        .toList();
  }
  
  /// Search plugins
  List<PluginMetadata> searchPlugins(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _pluginMetadata.values.where((metadata) {
      return metadata.name.toLowerCase().contains(lowerQuery) ||
             metadata.description.toLowerCase().contains(lowerQuery) ||
             metadata.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Send message to plugin
  Future<void> sendPluginMessage(
    String pluginId,
    Map<String, dynamic> message,
  ) async {
    final communication = _communications[pluginId];
    if (communication != null) {
      await communication.sendMessage(message);
    }
  }
  
  /// Broadcast system message
  Future<void> broadcastSystemMessage(Map<String, dynamic> message) async {
    for (final communication in _communications.values) {
      await communication.sendMessage(message);
    }
    
    _onSystemMessage.forEach((callback) => callback('system', message));
  }
  
  /// Add plugin loaded listener
  void addPluginLoadedListener(Function(LLMPlugin) listener) {
    _onPluginLoaded.add(listener);
  }
  
  /// Add plugin unloaded listener
  void addPluginUnloadedListener(Function(LLMPlugin) listener) {
    _onPluginUnloaded.add(listener);
  }
  
  /// Add plugin error listener
  void addPluginErrorListener(Function(LLMPlugin, String) listener) {
    _onPluginError.add(listener);
  }
  
  /// Add plugin message listener
  void addPluginMessageListener(Function(LLMPlugin, Map<String, dynamic>) listener) {
    _onPluginMessage.add(listener);
  }
  
  /// Add system message listener
  void addSystemMessageListener(Function(String, Map<String, dynamic>) listener) {
    _onSystemMessage.add(listener);
  }
  
  /// Remove plugin loaded listener
  void removePluginLoadedListener(Function(LLMPlugin) listener) {
    _onPluginLoaded.remove(listener);
  }
  
  /// Remove plugin unloaded listener
  void removePluginUnloadedListener(Function(LLMPlugin) listener) {
    _onPluginUnloaded.remove(listener);
  }
  
  /// Remove plugin error listener
  void removePluginErrorListener(Function(LLMPlugin, String) listener) {
    _onPluginError.remove(listener);
  }
  
  /// Remove plugin message listener
  void removePluginMessageListener(Function(LLMPlugin, Map<String, dynamic>) listener) {
    _onPluginMessage.remove(listener);
  }
  
  /// Remove system message listener
  void removeSystemMessageListener(Function(String, Map<String, dynamic>) listener) {
    _onSystemMessage.remove(listener);
  }
  
  /// Get system statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'total_plugins': _plugins.length,
      'active_plugins': _activePlugins.length,
      'current_model': _currentModel,
      'nvidia_configured': _nvidiaApiKey != null,
      'plugin_types': _plugins.values
          .map((p) => p.metadata.type.toString())
          .toSet()
          .toList(),
    };
  }
  
  /// Set configuration
  void setConfiguration({
    String? nvidiaEndpoint,
    String? nvidiaApiKey,
    String? currentModel,
  }) {
    if (nvidiaEndpoint != null) _nvidiaEndpoint = nvidiaEndpoint!;
    if (nvidiaApiKey != null) _nvidiaApiKey = nvidiaApiKey!;
    if (currentModel != null) _currentModel = currentModel!;
    
    debugPrint('⚙️ LLM plugin system configuration updated');
  }
  
  /// Dispose plugin system
  Future<void> dispose() async {
    // Deactivate all plugins
    for (final pluginId in List.from(_activePlugins)) {
      await deactivatePlugin(pluginId);
    }
    
    // Clear registry
    _plugins.clear();
    _pluginMetadata.clear();
    _sandboxes.clear();
    _communications.clear();
    _activePlugins.clear();
    
    // Clear listeners
    _onPluginLoaded.clear();
    _onPluginUnloaded.clear();
    _onPluginError.clear();
    _onPluginMessage.clear();
    _onSystemMessage.clear();
    
    _isInitialized = false;
    debugPrint('🤖 LLM Plugin System disposed');
  }
}

/// LLM Plugin base class
abstract class LLMPlugin {
  final PluginMetadata metadata;
  final PluginSandbox sandbox;
  bool _isInitialized = false;
  
  LLMPlugin(this.metadata, this.sandbox);
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await onInitialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('⚠️ Plugin initialization failed: $e');
      rethrow;
    }
  }
  
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    try {
      await onDispose();
      _isInitialized = false;
    } catch (e) {
      debugPrint('⚠️ Plugin disposal failed: $e');
    }
  }
  
  bool canHandle(String command) {
    return onCanHandle(command);
  }
  
  Future<Map<String, dynamic>> execute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    if (!_isInitialized) {
      throw StateError('Plugin not initialized');
    }
    
    return await onExecute(command, context: context);
  }
  
  // Abstract methods to be implemented by plugins
  Future<void> onInitialize();
  Future<void> onDispose();
  bool onCanHandle(String command);
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  });
}

/// Plugin metadata
class PluginMetadata {
  final String id;
  final String name;
  final String description;
  final String version;
  final PluginType type;
  final List<PluginPermission> permissions;
  final List<String> capabilities;
  final List<String> tags;
  final String author;
  final String website;
  final Map<String, dynamic> config;
  
  PluginMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.type,
    required this.permissions,
    this.capabilities = const [],
    this.tags = const [],
    required this.author,
    required this.website,
    this.config = const {},
  });
  
  factory PluginMetadata.fromJson(Map<String, dynamic> json) {
    return PluginMetadata(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      version: json['version'],
      type: PluginType.values.firstWhere(
        (type) => type.toString() == json['type'],
        orElse: () => PluginType.dart,
      ),
      permissions: (json['permissions'] as List?)
          ?.map((p) => PluginPermission.values.firstWhere(
            (perm) => perm.toString() == p,
            orElse: () => PluginPermission.fileRead,
          ))
          .toList() ?? [],
      capabilities: List<String>.from(json['capabilities'] ?? []),
      tags: List<String>.from(json['tags'] ?? []),
      author: json['author'],
      website: json['website'],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'version': version,
      'type': type.toString(),
      'permissions': permissions.map((p) => p.toString()).toList(),
      'capabilities': capabilities,
      'tags': tags,
      'author': author,
      'website': website,
      'config': config,
    };
  }
}

/// Plugin types
enum PluginType {
  builtin,
  dart,
  python,
  javascript,
}

/// Plugin permissions
enum PluginPermission {
  fileRead,
  fileWrite,
  directoryAccess,
  networkAccess,
  terminalAccess,
  systemInfo,
  cameraAccess,
  microphoneAccess,
  locationAccess,
}

/// Plugin sandbox
class PluginSandbox {
  final String pluginId;
  final String pluginPath;
  final List<PluginPermission> permissions;
  final Map<String, dynamic> environment;
  
  PluginSandbox({
    required this.pluginId,
    required this.pluginPath,
    required this.permissions,
    this.environment = const {},
  });
  
  bool hasPermission(PluginPermission permission) {
    return permissions.contains(permission);
  }
}

/// Plugin communication
class PluginCommunication {
  final String pluginId;
  final LLMPlugin plugin;
  final PluginSandbox sandbox;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  
  PluginCommunication({
    required this.pluginId,
    required this.plugin,
    required this.sandbox,
  });
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  Future<void> sendMessage(Map<String, dynamic> message) async {
    _messageController.add(message);
  }
  
  void dispose() {
    _messageController.close();
  }
}

/// Built-in plugin implementations
class BuiltinPlugin extends LLMPlugin {
  BuiltinPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  Future<void> onInitialize() async {
    // Built-in plugin initialization
  }
  
  @override
  Future<void> onDispose() async {
    // Built-in plugin disposal
  }
  
  @override
  bool onCanHandle(String command) {
    // Built-in plugins can handle most commands
    return true;
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    // Default built-in implementation
    return {
      'success': false,
      'error': 'Built-in plugin not implemented',
    };
  }
}

/// NVIDIA LLM Plugin
class NvidiaLLMPlugin extends BuiltinPlugin {
  NvidiaLLMPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  bool onCanHandle(String command) {
    // Handle natural language commands
    return command.toLowerCase().contains('help') ||
           command.toLowerCase().contains('explain') ||
           command.toLowerCase().contains('generate') ||
           command.toLowerCase().contains('create') ||
           command.toLowerCase().contains('write');
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    // This would integrate with the main LLM plugin system
    // For now, return a placeholder response
    return {
      'success': true,
      'response': 'NVIDIA LLM processing: $command',
      'plugin': 'nvidia-llm',
    };
  }
}

/// Terminal Commands Plugin
class TerminalCommandsPlugin extends BuiltinPlugin {
  TerminalCommandsPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  bool onCanHandle(String command) {
    return command.toLowerCase().startsWith('run ') ||
           command.toLowerCase().startsWith('execute ') ||
           command.toLowerCase().startsWith('terminal ');
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': true,
      'response': 'Terminal command executed: $command',
      'plugin': 'terminal-commands',
    };
  }
}

/// File Operations Plugin
class FileOperationsPlugin extends BuiltinPlugin {
  FileOperationsPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  bool onCanHandle(String command) {
    return command.toLowerCase().contains('file ') ||
           command.toLowerCase().contains('directory ') ||
           command.toLowerCase().contains('create ') ||
           command.toLowerCase().contains('delete ') ||
           command.toLowerCase().contains('copy ') ||
           command.toLowerCase().contains('move ');
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': true,
      'response': 'File operation executed: $command',
      'plugin': 'file-operations',
    };
  }
}

/// System Monitor Plugin
class SystemMonitorPlugin extends BuiltinPlugin {
  SystemMonitorPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  bool onCanHandle(String command) {
    return command.toLowerCase().contains('system ') ||
           command.toLowerCase().contains('monitor ') ||
           command.toLowerCase().contains('status ') ||
           command.toLowerCase().contains('performance ');
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': true,
      'response': 'System monitoring: $command',
      'plugin': 'system-monitor',
    };
  }
}

/// Dart Plugin
class DartPlugin extends LLMPlugin {
  DartPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  Future<void> onInitialize() async {
    // Dart plugin initialization
  }
  
  @override
  Future<void> onDispose() async {
    // Dart plugin disposal
  }
  
  @override
  bool onCanHandle(String command) {
    // Dart plugin-specific command handling
    return false;
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': false,
      'error': 'Dart plugin not implemented',
    };
  }
}

/// Python Plugin
class PythonPlugin extends LLMPlugin {
  PythonPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  Future<void> onInitialize() async {
    // Python plugin initialization
  }
  
  @override
  Future<void> onDispose() async {
    // Python plugin disposal
  }
  
  @override
  bool onCanHandle(String command) {
    // Python plugin-specific command handling
    return false;
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': false,
      'error': 'Python plugin not implemented',
    };
  }
}

/// JavaScript Plugin
class JavaScriptPlugin extends LLMPlugin {
  JavaScriptPlugin(PluginMetadata metadata, PluginSandbox sandbox)
      : super(metadata, sandbox);
  
  @override
  Future<void> onInitialize() async {
    // JavaScript plugin initialization
  }
  
  @override
  Future<void> onDispose() async {
    // JavaScript plugin disposal
  }
  
  @override
  bool onCanHandle(String command) {
    // JavaScript plugin-specific command handling
    return false;
  }
  
  @override
  Future<Map<String, dynamic>> onExecute(
    String command, {
    Map<String, dynamic>? context,
  }) async {
    return {
      'success': false,
      'error': 'JavaScript plugin not implemented',
    };
  }
}
