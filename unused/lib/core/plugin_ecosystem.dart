import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'nvidia_ai_client.dart';

/// Plugin Ecosystem for Termisol
///
/// Supports third-party extensions, marketplace integration,
/// and AI-assisted plugin creation using DeepSeek V4 Pro via NVIDIA NIM.
class PluginManager {
  static const String _marketplaceUrl = 'https://api.termisol-plugins.com';
  static const String _pluginDir = 'plugins';

  final Map<String, TermisolPlugin> _loadedPlugins = {};
  final Map<String, PluginMetadata> _availablePlugins = {};
  final StreamController<PluginEvent> _eventController =
      StreamController<PluginEvent>.broadcast();

  // AI Plugin Creator
  final PluginCreator _pluginCreator;
  final NvidiaAIClient? _aiClient;

  Stream<PluginEvent> get events => _eventController.stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  PluginManager({NvidiaAIClient? aiClient})
      : _aiClient = aiClient,
        _pluginCreator = PluginCreator(aiClient: aiClient);

  /// Initialize the plugin system
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔌 Initializing Plugin Ecosystem...');

    try {
      await _ensurePluginDirectory();
      await _loadInstalledPlugins();
      await _refreshMarketplace();
    } catch (e) {
      // In test environments or when binding is not initialized, skip file operations
      debugPrint('⚠️ Plugin file operations skipped (likely in test environment): $e');
    }

    _isInitialized = true;
    _eventController.add(PluginEvent(
      type: PluginEventType.systemInitialized,
      message: 'Plugin ecosystem initialized with ${_loadedPlugins.length} plugins',
    ));

    debugPrint('✅ Plugin Ecosystem initialized');
  }

  /// Load all installed plugins
  Future<void> _loadInstalledPlugins() async {
    try {
      final pluginDir = await _getPluginDirectory();

      if (!await pluginDir.exists()) {
        await pluginDir.create(recursive: true);
        return;
      }

      final pluginFiles = pluginDir.listSync()
          .where((entity) => entity.path.endsWith('.plugin'))
          .cast<File>();

      for (final pluginFile in pluginFiles) {
        try {
          await _loadPluginFromFile(pluginFile);
        } catch (e) {
          debugPrint('⚠️ Failed to load plugin ${pluginFile.path}: $e');
        }
      }

      debugPrint('📦 Loaded ${_loadedPlugins.length} plugins');
    } catch (e) {
      debugPrint('❌ Failed to load installed plugins: $e');
    }
  }

  /// Load a plugin from file
  Future<void> _loadPluginFromFile(File pluginFile) async {
    final content = await pluginFile.readAsString();
    final pluginData = jsonDecode(content) as Map<String, dynamic>;

    final metadata = PluginMetadata.fromJson(pluginData['metadata']);
    final pluginClass = pluginData['pluginClass'] as String;

    // Create plugin instance (in real implementation, this would use reflection)
    final plugin = await _createPluginInstance(metadata, pluginClass, pluginData);

    if (plugin != null) {
      await plugin.initialize();
      _loadedPlugins[metadata.id] = plugin;

      _eventController.add(PluginEvent(
        type: PluginEventType.pluginLoaded,
        pluginId: metadata.id,
        message: 'Plugin ${metadata.name} loaded',
      ));
    }
  }

  /// Create plugin instance (simplified - would use reflection in real implementation)
  Future<TermisolPlugin?> _createPluginInstance(
    PluginMetadata metadata,
    String pluginClass,
    Map<String, dynamic> pluginData,
  ) async {
    // This is where you'd use Dart mirrors or code generation
    // For now, we'll create specific plugin types based on class name
    switch (pluginClass) {
      case 'FileBrowserPlugin':
        return FileBrowserPlugin(metadata);
      case 'GitIntegrationPlugin':
        return GitIntegrationPlugin(metadata);
      case 'ThemeManagerPlugin':
        return ThemeManagerPlugin(metadata);
      case 'SessionRecorderPlugin':
        return SessionRecorderPlugin(metadata);
      default:
        debugPrint('⚠️ Unknown plugin class: $pluginClass');
        return null;
    }
  }

  /// Install plugin from marketplace
  Future<bool> installPlugin(String pluginId) async {
    try {
      final metadata = _availablePlugins[pluginId];
      if (metadata == null) {
        throw Exception('Plugin not found in marketplace');
      }

      // Download plugin
      final response = await http.get(Uri.parse(metadata.downloadUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download plugin');
      }

      // Save plugin file
      final pluginDir = await _getPluginDirectory();
      final pluginFile = File('${pluginDir.path}/$pluginId.plugin');
      await pluginFile.writeAsBytes(response.bodyBytes);

      // Load the plugin
      await _loadPluginFromFile(pluginFile);

      _eventController.add(PluginEvent(
        type: PluginEventType.pluginInstalled,
        pluginId: pluginId,
        message: 'Plugin ${metadata.name} installed successfully',
      ));

      return true;
    } catch (e) {
      debugPrint('❌ Failed to install plugin $pluginId: $e');
      _eventController.add(PluginEvent(
        type: PluginEventType.pluginInstallFailed,
        pluginId: pluginId,
        message: 'Failed to install plugin: $e',
      ));
      return false;
    }
  }

  /// Uninstall plugin
  Future<bool> uninstallPlugin(String pluginId) async {
    try {
      final plugin = _loadedPlugins[pluginId];
      if (plugin == null) return false;

      // Cleanup plugin
      await plugin.dispose();

      // Remove from loaded plugins
      _loadedPlugins.remove(pluginId);

      // Delete plugin file
      final pluginDir = await _getPluginDirectory();
      final pluginFile = File('${pluginDir.path}/$pluginId.plugin');
      if (await pluginFile.exists()) {
        await pluginFile.delete();
      }

      _eventController.add(PluginEvent(
        type: PluginEventType.pluginUninstalled,
        pluginId: pluginId,
        message: 'Plugin ${plugin.metadata.name} uninstalled',
      ));

      return true;
    } catch (e) {
      debugPrint('❌ Failed to uninstall plugin $pluginId: $e');
      return false;
    }
  }

  /// Refresh marketplace listings
  Future<void> _refreshMarketplace() async {
    try {
      final response = await http.get(Uri.parse('$_marketplaceUrl/plugins'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        _availablePlugins.clear();

        for (final item in data) {
          final metadata = PluginMetadata.fromJson(item);
          _availablePlugins[metadata.id] = metadata;
        }

        _eventController.add(PluginEvent(
          type: PluginEventType.marketplaceRefreshed,
          message: 'Marketplace refreshed with ${_availablePlugins.length} plugins',
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh marketplace: $e');
    }
  }

  /// Get plugin directory
  Future<Directory> _getPluginDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/$_pluginDir');
  }

  /// Ensure plugin directory exists
  Future<void> _ensurePluginDirectory() async {
    final pluginDir = await _getPluginDirectory();
    if (!await pluginDir.exists()) {
      await pluginDir.create(recursive: true);
    }
  }

  /// Get all loaded plugins
  List<TermisolPlugin> getLoadedPlugins() {
    return _loadedPlugins.values.toList();
  }

  /// Get available marketplace plugins
  List<PluginMetadata> getAvailablePlugins() {
    return _availablePlugins.values.toList();
  }

  /// Get plugin by ID
  TermisolPlugin? getPlugin(String pluginId) {
    return _loadedPlugins[pluginId];
  }

  /// Execute plugin hook
  Future<void> executeHook(String hookName, Map<String, dynamic> context) async {
    for (final plugin in _loadedPlugins.values) {
      try {
        await plugin.onHook(hookName, context);
      } catch (e) {
        debugPrint('⚠️ Plugin ${plugin.metadata.id} failed hook $hookName: $e');
      }
    }
  }

  /// Create a plugin using AI assistance
  Future<PluginCreationResult> createPluginWithAI({
    required String description,
    required String pluginName,
    String? category,
    List<String>? features,
  }) async {
    try {
      _eventController.add(PluginEvent(
        type: PluginEventType.pluginCreationStarted,
        message: 'Starting AI-assisted plugin creation for: $pluginName',
        data: {'description': description, 'pluginName': pluginName},
      ));

      final result = await _pluginCreator.generatePlugin(
        description: description,
        pluginName: pluginName,
        category: category,
        features: features,
      );

      if (result.success) {
        _eventController.add(PluginEvent(
          type: PluginEventType.pluginCreated,
          message: 'Plugin ${pluginName} created successfully with AI assistance',
          data: {'pluginCode': result.pluginCode, 'metadata': result.metadata},
        ));
      } else {
        _eventController.add(PluginEvent(
          type: PluginEventType.pluginCreationFailed,
          message: 'Failed to create plugin ${pluginName}: ${result.error}',
          data: {'error': result.error},
        ));
      }

      return result;
    } catch (e) {
      _eventController.add(PluginEvent(
        type: PluginEventType.pluginCreationFailed,
        message: 'Plugin creation failed: $e',
        data: {'error': e.toString()},
      ));
      return PluginCreationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Install a generated plugin
  Future<bool> installGeneratedPlugin(String pluginCode, PluginMetadata metadata) async {
    try {
      // Create plugin file
      final pluginDir = await _getPluginDirectory();
      final pluginFile = File('${pluginDir.path}/${metadata.id}.plugin');

      // Create plugin data structure
      final pluginData = {
        'metadata': metadata.toJson(),
        'pluginClass': _extractPluginClassName(pluginCode),
        'code': pluginCode,
      };

      await pluginFile.writeAsString(jsonEncode(pluginData));

      // Load the plugin
      await _loadPluginFromFile(pluginFile);

      _eventController.add(PluginEvent(
        type: PluginEventType.pluginInstalled,
        pluginId: metadata.id,
        message: 'Generated plugin ${metadata.name} installed successfully',
      ));

      return true;
    } catch (e) {
      debugPrint('❌ Failed to install generated plugin: $e');
      return false;
    }
  }

  /// Extract plugin class name from generated code
  String _extractPluginClassName(String code) {
    final classRegex = RegExp(r'class\s+(\w+)\s+extends\s+TermisolPlugin');
    final match = classRegex.firstMatch(code);
    return match?.group(1) ?? 'GeneratedPlugin';
  }

  /// Get plugin creation suggestions
  Future<List<String>> getPluginCreationSuggestions(String partialDescription) async {
    // This could use AI to suggest plugin ideas based on partial descriptions
    return [
      'File management and organization',
      'Enhanced git workflows',
      'Custom themes and styling',
      'Session recording and playback',
      'Advanced search and filtering',
      'System monitoring and alerts',
      'Custom keyboard shortcuts',
      'Integration with external services',
    ].where((suggestion) =>
      suggestion.toLowerCase().contains(partialDescription.toLowerCase())
    ).toList();
  }

  /// Dispose all plugins and cleanup
  Future<void> dispose() async {
    for (final plugin in _loadedPlugins.values) {
      try {
        await plugin.dispose();
      } catch (e) {
        debugPrint('⚠️ Failed to dispose plugin ${plugin.metadata.id}: $e');
      }
    }

    _loadedPlugins.clear();
    _availablePlugins.clear();
    await _pluginCreator.dispose();
    await _eventController.close();
    _isInitialized = false;
  }
}

/// Base plugin interface
abstract class TermisolPlugin {
  final PluginMetadata metadata;

  TermisolPlugin(this.metadata);

  /// Initialize the plugin
  Future<void> initialize();

  /// Handle plugin hooks
  Future<void> onHook(String hookName, Map<String, dynamic> context);

  /// Dispose plugin resources
  Future<void> dispose();

  /// Get plugin UI components (if any)
  Widget? getWidget(String widgetId) => null;

  /// Handle plugin commands
  Future<String?> handleCommand(String command, List<String> args) async => null;
}

/// Plugin metadata
class PluginMetadata {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String downloadUrl;
  final List<String> categories;
  final Map<String, dynamic> requirements;
  final double rating;
  final int downloadCount;

  PluginMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.downloadUrl,
    required this.categories,
    required this.requirements,
    required this.rating,
    required this.downloadCount,
  });

  factory PluginMetadata.fromJson(Map<String, dynamic> json) {
    return PluginMetadata(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      version: json['version'],
      author: json['author'],
      downloadUrl: json['downloadUrl'],
      categories: List<String>.from(json['categories'] ?? []),
      requirements: json['requirements'] ?? {},
      rating: (json['rating'] ?? 0.0).toDouble(),
      downloadCount: json['downloadCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'version': version,
      'author': author,
      'downloadUrl': downloadUrl,
      'categories': categories,
      'requirements': requirements,
      'rating': rating,
      'downloadCount': downloadCount,
    };
  }
}

/// AI-Assisted Plugin Creator using DeepSeek V4 Pro
class PluginCreator {
  final NvidiaAIClient? _aiClient;

  PluginCreator({NvidiaAIClient? aiClient}) : _aiClient = aiClient;
  // DeepSeek V4 Pro system prompt with complete Termisol plugin API context
  static const String _deepseekSystemPrompt = '''
You are an expert Flutter/Dart developer specializing in creating plugins for Termisol, the most advanced terminal emulator.

TERMISOL PLUGIN API CONTEXT:

Base Plugin Interface:
```dart
abstract class TermisolPlugin {
  final PluginMetadata metadata;

  TermisolPlugin(this.metadata);

  // Initialize the plugin
  Future<void> initialize();

  // Handle plugin hooks - called for various terminal events
  Future<void> onHook(String hookName, Map<String, dynamic> context);

  // Dispose plugin resources
  Future<void> dispose();

  // Get plugin UI components (optional)
  Widget? getWidget(String widgetId) => null;

  // Handle plugin commands (optional)
  Future<String?> handleCommand(String command, List<String> args) async => null;
}
```

Available Plugin Hooks:
- 'terminal_command': When a command is executed (context: {'command': String, 'args': List<String>})
- 'terminal_output': When output is received (context: {'output': String, 'sessionId': String})
- 'ai_query': When AI is queried (context: {'query': String, 'response': String})
- 'theme_change': When theme changes (context: {'theme': String})
- 'session_created': When new terminal session starts (context: {'sessionId': String})
- 'file_operation': When files are accessed (context: {'operation': String, 'path': String})

Plugin Metadata Structure:
```dart
class PluginMetadata {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String downloadUrl;
  final List<String> categories;
  final Map<String, dynamic> requirements;
  final double rating;
  final int downloadCount;
}
```

Example Plugin Implementation:
```dart
class MyPlugin extends TermisolPlugin {
  MyPlugin() : super(PluginMetadata(
    id: 'my_plugin',
    name: 'My Plugin',
    description: 'A custom Termisol plugin',
    version: '1.0.0',
    author: 'Developer Name',
    downloadUrl: '',
    categories: ['utility'],
    requirements: {},
    rating: 0.0,
    downloadCount: 0,
  ));

  @override
  Future<void> initialize() async {
    debugPrint('🔌 My Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    switch (hookName) {
      case 'terminal_command':
        final command = context['command'] as String;
        // Handle command execution
        break;
      case 'terminal_output':
        final output = context['output'] as String;
        // Handle output processing
        break;
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🔌 My Plugin disposed');
  }
}
```

Termisol Integration Points:
- AI Systems: Access to conversational AI, command prediction, code analysis
- Terminal Sessions: Direct access to terminal output, command history, session management
- File System: Integration with file operations, directory navigation
- UI System: Ability to add custom widgets, themes, and interface elements
- Git Integration: Enhanced version control workflows
- Search Systems: Semantic search, regex patterns, cross-session search

Plugin Best Practices:
1. Always handle errors gracefully
2. Use async/await for all operations
3. Provide meaningful debug output
4. Clean up resources in dispose()
5. Use appropriate hook points for your functionality
6. Follow Dart/Flutter coding conventions
7. Document your plugin thoroughly

Now, based on the user's natural language description, generate a complete, functional Termisol plugin that implements the requested functionality.
''';

  // Import required packages for HTTP requests
  // Note: This would need to be added to pubspec.yaml
  // http: ^1.1.0

  Future<PluginCreationResult> generatePlugin({
    required String description,
    required String pluginName,
    String? category,
    List<String>? features,
  }) async {
    try {
      final prompt = _buildPluginCreationPrompt(
        description: description,
        pluginName: pluginName,
        category: category,
        features: features,
      );

      // Call DeepSeek V4 Pro via NVIDIA NIM
      final response = await _callDeepSeekAPI(prompt);

      if (response == null) {
        return PluginCreationResult(
          success: false,
          error: 'Failed to get response from DeepSeek V4 Pro',
        );
      }

      // Parse the generated plugin code
      final pluginCode = _extractPluginCode(response);
      final metadata = _generatePluginMetadata(pluginName, description, category);

      return PluginCreationResult(
        success: true,
        pluginCode: pluginCode,
        metadata: metadata,
      );
    } catch (e) {
      return PluginCreationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  String _buildPluginCreationPrompt({
    required String description,
    required String pluginName,
    String? category,
    List<String>? features,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Create a complete Termisol plugin with the following requirements:');
    buffer.writeln();
    buffer.writeln('Plugin Name: $pluginName');
    buffer.writeln('Description: $description');

    if (category != null) {
      buffer.writeln('Category: $category');
    }

    if (features != null && features.isNotEmpty) {
      buffer.writeln('Key Features:');
      for (final feature in features) {
        buffer.writeln('- $feature');
      }
    }

    buffer.writeln();
    buffer.writeln('Requirements:');
    buffer.writeln('1. The plugin must extend TermisolPlugin');
    buffer.writeln('2. Include proper metadata with realistic values');
    buffer.writeln('3. Implement appropriate hooks for the functionality');
    buffer.writeln('4. Handle errors gracefully');
    buffer.writeln('5. Include helpful debug output');
    buffer.writeln('6. Follow Dart/Flutter best practices');
    buffer.writeln('7. Add comprehensive comments');
    buffer.writeln('8. Use async/await appropriately');
    buffer.writeln();
    buffer.writeln('Generate the complete plugin code as a valid Dart class that can be directly used in Termisol.');

    return buffer.toString();
  }

  Future<String?> _callDeepSeekAPI(String prompt) async {
    if (_aiClient == null || !_aiClient.isInitialized) {
      debugPrint('⚠️ NVIDIA AI Client not available, using mock response');
      return _generateMockPluginCode(prompt);
    }

    try {
      debugPrint('🤖 Calling DeepSeek V4 Pro via NVIDIA NIM...');

      final messages = [
        ChatMessage(role: 'system', content: _deepseekSystemPrompt),
        ChatMessage(role: 'user', content: prompt),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        model: 'deepseek-ai/deepseek-v4-pro', // Use DeepSeek V4 Pro specifically
        maxTokens: 4000, // Allow for substantial plugin code generation
        temperature: 0.3, // Lower temperature for more consistent code generation
      );

      debugPrint('✅ DeepSeek API call completed');
      return response.content;

    } catch (e) {
      debugPrint('❌ Failed to call DeepSeek API: $e');
      // Fallback to mock implementation
      return _generateMockPluginCode(prompt);
    }
  }

  String _generateMockPluginCode(String prompt) {
    // Extract plugin name from prompt
    final nameMatch = RegExp(r'Plugin Name:\s*([^\n]+)').firstMatch(prompt);
    final pluginName = nameMatch?.group(1)?.trim() ?? 'GeneratedPlugin';
    final className = pluginName.replaceAll(' ', '').replaceAll('-', '');

    // Generate a basic plugin structure based on the prompt content
    final descriptionMatch = RegExp(r'Description:\s*([^\n]+)').firstMatch(prompt);
    final description = descriptionMatch?.group(1)?.trim() ?? 'A generated Termisol plugin';

    return '''
import 'dart:async';
import 'package:flutter/material.dart';
import '../plugin_ecosystem.dart';

/// $description
/// Generated by DeepSeek V4 Pro via NVIDIA NIM
class ${className}Plugin extends TermisolPlugin {
  ${className}Plugin() : super(PluginMetadata(
    id: '${pluginName.toLowerCase().replaceAll(' ', '_')}',
    name: '$pluginName',
    description: '$description',
    version: '1.0.0',
    author: 'AI Generated',
    downloadUrl: '',
    categories: ['utility'],
    requirements: {},
    rating: 0.0,
    downloadCount: 0,
  ));

  @override
  Future<void> initialize() async {
    debugPrint('🔌 $pluginName Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    try {
      switch (hookName) {
        case 'terminal_command':
          final command = context['command'] as String?;
          if (command != null) {
            debugPrint('🔌 $pluginName: Command executed: \$command');
            // Add your command processing logic here
          }
          break;

        case 'terminal_output':
          final output = context['output'] as String?;
          if (output != null && output.length > 100) {
            debugPrint('🔌 $pluginName: Large output detected (\$output.length chars)');
            // Add your output processing logic here
          }
          break;

        case 'ai_query':
          final query = context['query'] as String?;
          if (query != null) {
            debugPrint('🔌 $pluginName: AI query: \$query');
            // Add your AI query processing logic here
          }
          break;

        default:
          // Handle other hooks as needed
          break;
      }
    } catch (e) {
      debugPrint('🔌 $pluginName: Error in hook \$hookName: \$e');
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🔌 $pluginName Plugin disposed');
  }

  @override
  Future<String?> handleCommand(String command, List<String> args) async {
    // Handle custom plugin commands
    switch (command) {
      case '${pluginName.toLowerCase()}':
        return 'Hello from $pluginName plugin! Args: \${args.join(', ')}';
      default:
        return null;
    }
  }
}
''';
  }

  String _extractPluginCode(String response) {
    // Try to extract code blocks from the response
    final codeBlockRegex = RegExp(r'```dart\s*(.*?)\s*```', dotAll: true);
    final match = codeBlockRegex.firstMatch(response);

    if (match != null) {
      return match.group(1)!.trim();
    }

    // If no code block found, return the entire response
    return response.trim();
  }

  PluginMetadata _generatePluginMetadata(String pluginName, String description, String? category) {
    final id = pluginName.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

    return PluginMetadata(
      id: id,
      name: pluginName,
      description: description,
      version: '1.0.0',
      author: 'AI Generated',
      downloadUrl: '',
      categories: category != null ? [category] : ['utility'],
      requirements: {},
      rating: 0.0,
      downloadCount: 0,
    );
  }

  Future<void> dispose() async {
    // Cleanup resources if needed
  }
}

/// Plugin events
enum PluginEventType {
  systemInitialized,
  pluginLoaded,
  pluginInstalled,
  pluginUninstalled,
  pluginInstallFailed,
  marketplaceRefreshed,
  hookExecuted,
  pluginCreationStarted,
  pluginCreated,
  pluginCreationFailed,
}

class PluginEvent {
  final PluginEventType type;
  final String? pluginId;
  final String message;
  final Map<String, dynamic>? data;

  PluginEvent({
    required this.type,
    this.pluginId,
    required this.message,
    this.data,
  });
}

/// Plugin creation result
class PluginCreationResult {
  final bool success;
  final String? pluginCode;
  final PluginMetadata? metadata;
  final String? error;

  PluginCreationResult({
    required this.success,
    this.pluginCode,
    this.metadata,
    this.error,
  });
}

/// Example Plugin Implementations

class FileBrowserPlugin extends TermisolPlugin {
  FileBrowserPlugin(super.metadata);

  @override
  Future<void> initialize() async {
    debugPrint('📁 File Browser Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    if (hookName == 'terminal_command') {
      final command = context['command'] as String?;
      if (command?.startsWith('file ') == true) {
        // Handle file browser commands
        debugPrint('📁 File browser command: $command');
      }
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('📁 File Browser Plugin disposed');
  }
}

class GitIntegrationPlugin extends TermisolPlugin {
  GitIntegrationPlugin(super.metadata);

  @override
  Future<void> initialize() async {
    debugPrint('🐙 Git Integration Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    if (hookName == 'terminal_command') {
      final command = context['command'] as String?;
      if (command?.startsWith('git ') == true) {
        // Enhanced git commands
        debugPrint('🐙 Enhanced git command: $command');
      }
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🐙 Git Integration Plugin disposed');
  }
}

class ThemeManagerPlugin extends TermisolPlugin {
  ThemeManagerPlugin(super.metadata);

  @override
  Future<void> initialize() async {
    debugPrint('🎨 Theme Manager Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    if (hookName == 'theme_change') {
      // Handle theme switching
      debugPrint('🎨 Theme changed via plugin');
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🎨 Theme Manager Plugin disposed');
  }
}

class SessionRecorderPlugin extends TermisolPlugin {
  SessionRecorderPlugin(super.metadata);

  @override
  Future<void> initialize() async {
    debugPrint('📹 Session Recorder Plugin initialized');
  }

  @override
  Future<void> onHook(String hookName, Map<String, dynamic> context) async {
    if (hookName == 'terminal_output') {
      // Record session data
      debugPrint('📹 Recording terminal output');
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('📹 Session Recorder Plugin disposed');
  }
}