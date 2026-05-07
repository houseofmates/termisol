import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:xterm/xterm.dart';

/// Custom Command Aliases and Snippets System
/// 
/// Implements intelligent command management:
/// - Custom aliases with parameters
/// - Code snippets and templates
/// - Dynamic alias expansion
/// - Context-aware suggestions
/// - Command history integration
/// - Workspace-specific aliases
/// - Smart snippet insertion
class CommandAliasSystem {
  bool _isInitialized = false;
  
  // Storage
  String _aliasesPath = '';
  String _snippetsPath = '';
  final Map<String, CommandAlias> _aliases = {};
  final Map<String, CodeSnippet> _snippets = {};
  final List<String> _commandHistory = [];
  
  // Context
  String _currentWorkspace = '';
  String _currentLanguage = '';
  final Map<String, String> _environmentVariables = {};
  
  // Event handlers
  final List<Function(CommandAlias)> _onAliasAdded = [];
  final List<Function(CommandAlias)> _onAliasRemoved = [];
  final List<Function(CodeSnippet)> _onSnippetAdded = [];
  final List<Function(CodeSnippet)> _onSnippetRemoved = [];
  final List<Function(String, String)> _onAliasExecuted = [];
  final List<Function(String, String)> _onSnippetInserted = [];
  
  CommandAliasSystem();
  
  bool get isInitialized => _isInitialized;
  Map<String, CommandAlias> get aliases => Map.unmodifiable(_aliases);
  Map<String, CodeSnippet> get snippets => Map.unmodifiable(_snippets);
  List<String> get commandHistory => List.unmodifiable(_commandHistory);
  String get currentWorkspace => _currentWorkspace;
  String get currentLanguage => _currentLanguage;
  
  /// Initialize alias system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup paths
      _setupPaths();
      
      // Load aliases and snippets
      await _loadAliases();
      await _loadSnippets();
      
      // Load environment
      await _loadEnvironment();
      
      // Setup file watchers
      _setupFileWatchers();
      
      _isInitialized = true;
      debugPrint('🔧 Command Alias System initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Command Alias System: $e');
      rethrow;
    }
  }
  
  /// Setup file paths
  void _setupPaths() {
    final homeDir = Platform.environment['HOME'] ?? '';
    _aliasesPath = path.join(homeDir, '.termisol', 'aliases.json');
    _snippetsPath = path.join(homeDir, '.termisol', 'snippets.json');
  }
  
  /// Load aliases
  Future<void> _loadAliases() async {
    try {
      final aliasesFile = File(_aliasesPath);
      if (await aliasesFile.exists()) {
        final content = await aliasesFile.readAsString();
        final data = jsonDecode(content);
        
        final aliasesData = data['aliases'] as List? ?? [];
        for (final aliasData in aliasesData) {
          final alias = CommandAlias.fromJson(aliasData);
          _aliases[alias.name] = alias;
        }
        
        debugPrint('🔧 Loaded ${_aliases.length} command aliases');
      } else {
        // Create default aliases
        await _createDefaultAliases();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load aliases: $e');
      await _createDefaultAliases();
    }
  }
  
  /// Create default aliases
  Future<void> _createDefaultAliases() async {
    final defaultAliases = [
      // Development aliases
      CommandAlias(
        name: 'run',
        command: 'flutter run',
        description: 'Run Flutter application',
        category: AliasCategory.development,
        workspace: 'flutter',
        language: 'dart',
        parameters: ['--release', '--profile', '--debug'],
      ),
      CommandAlias(
        name: 'build',
        command: 'flutter build apk',
        description: 'Build Flutter APK',
        category: AliasCategory.development,
        workspace: 'flutter',
        language: 'dart',
        parameters: ['--release', '--split-debug-info'],
      ),
      CommandAlias(
        name: 'test',
        command: 'flutter test',
        description: 'Run Flutter tests',
        category: AliasCategory.development,
        workspace: 'flutter',
        language: 'dart',
        parameters: ['--coverage', '--machine'],
      ),
      CommandAlias(
        name: 'serve',
        command: 'python -m http.server 8000',
        description: 'Start local HTTP server',
        category: AliasCategory.development,
        workspace: 'python',
        language: 'python',
        parameters: ['--bind', '--directory'],
      ),
      CommandAlias(
        name: 'clean',
        command: 'git clean -fd',
        description: 'Clean git repository',
        category: AliasCategory.git,
        workspace: 'any',
        language: 'any',
        parameters: ['--dry-run', '--force'],
      ),
      CommandAlias(
        name: 'pull',
        command: 'git pull origin main',
        description: 'Pull latest changes',
        category: AliasCategory.git,
        workspace: 'any',
        language: 'any',
        parameters: ['--rebase', '--force'],
      ),
      CommandAlias(
        name: 'push',
        command: 'git push origin main',
        description: 'Push changes to remote',
        category: AliasCategory.git,
        workspace: 'any',
        language: 'any',
        parameters: ['--force', '--set-upstream'],
      ),
      CommandAlias(
        name: 'status',
        command: 'git status',
        description: 'Check git status',
        category: AliasCategory.git,
        workspace: 'any',
        language: 'any',
        parameters: ['--porcelain', '--branch'],
      ),
      CommandAlias(
        name: 'commit',
        command: 'git add . && git commit -m',
        description: 'Stage and commit changes',
        category: AliasCategory.git,
        workspace: 'any',
        language: 'any',
        parameters: ['--amend', '--no-verify'],
      ),
      
      // System aliases
      CommandAlias(
        name: 'll',
        command: 'ls -la',
        description: 'List files in long format',
        category: AliasCategory.system,
        workspace: 'any',
        language: 'any',
        parameters: ['--human-readable', '--time-style'],
      ),
      CommandAlias(
        name: 'la',
        command: 'ls -la',
        description: 'List all files including hidden',
        category: AliasCategory.system,
        workspace: 'any',
        language: 'any',
        parameters: ['--color', '--indicator-style'],
      ),
      CommandAlias(
        name: 'grep',
        command: 'grep --color=auto --exclude-dir=.git',
        description: 'Search with colored output',
        category: AliasCategory.system,
        workspace: 'any',
        language: 'any',
        parameters: ['--recursive', '--ignore-case'],
      ),
      CommandAlias(
        name: 'find',
        command: 'find . -name',
        description: 'Find files by name',
        category: AliasCategory.system,
        workspace: 'any',
        language: 'any',
        parameters: ['--type', '--maxdepth'],
      ),
      
      // House-specific aliases
      CommandAlias(
        name: 'vibecode',
        command: 'cd /home/house/vibecode',
        description: 'Navigate to vibecode directory',
        category: AliasCategory.navigation,
        workspace: 'any',
        language: 'any',
        parameters: ['--new-terminal'],
      ),
      CommandAlias(
        name: 'termisol',
        command: 'cd /home/house/termisol',
        description: 'Navigate to termisol directory',
        category: AliasCategory.navigation,
        workspace: 'any',
        language: 'any',
        parameters: ['--new-terminal'],
      ),
      CommandAlias(
        name: 'workspace',
        command: 'cd /home/house/workspace',
        description: 'Navigate to workspace directory',
        category: AliasCategory.navigation,
        workspace: 'any',
        language: 'any',
        parameters: ['--new-terminal'],
      ),
      CommandAlias(
        name: 'home',
        command: 'cd ~',
        description: 'Navigate to home directory',
        category: AliasCategory.navigation,
        workspace: 'any',
        language: 'any',
        parameters: ['--new-terminal'],
      ),
    ];
    
    for (final alias in defaultAliases) {
      _aliases[alias.name] = alias;
    }
    
    await _saveAliases();
  }
  
  /// Load snippets
  Future<void> _loadSnippets() async {
    try {
      final snippetsFile = File(_snippetsPath);
      if (await snippetsFile.exists()) {
        final content = await snippetsFile.readAsString();
        final data = jsonDecode(content);
        
        final snippetsData = data['snippets'] as List? ?? [];
        for (final snippetData in snippetsData) {
          final snippet = CodeSnippet.fromJson(snippetData);
          _snippets[snippet.id] = snippet;
        }
        
        debugPrint('📝 Loaded ${_snippets.length} code snippets');
      } else {
        // Create default snippets
        await _createDefaultSnippets();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load snippets: $e');
      await _createDefaultSnippets();
    }
  }
  
  /// Create default snippets
  Future<void> _createDefaultSnippets() async {
    final defaultSnippets = [
      // Flutter/Dart snippets
      CodeSnippet(
        id: 'flutter_stateful_widget',
        name: 'Stateful Widget',
        description: 'Flutter stateful widget template',
        code: '''class MyWidget extends StatefulWidget {
  const MyWidget({Key? key}) : super(key: key);

  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('Hello World'),
    );
  }
}''',
        category: SnippetCategory.flutter,
        language: 'dart',
        tags: ['flutter', 'widget', 'stateful'],
        parameters: ['WidgetName'],
      ),
      CodeSnippet(
        id: 'flutter_stateless_widget',
        name: 'Stateless Widget',
        description: 'Flutter stateless widget template',
        code: '''class MyWidget extends StatelessWidget {
  const MyWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('Hello World'),
    );
  }
}''',
        category: SnippetCategory.flutter,
        language: 'dart',
        tags: ['flutter', 'widget', 'stateless'],
        parameters: ['WidgetName'],
      ),
      CodeSnippet(
        id: 'dart_async_function',
        name: 'Async Function',
        description: 'Dart async function template',
        code: '''Future<void> myFunction() async {
  try {
    // Async operation here
    await Future.delayed(Duration(seconds: 1));
    print('Operation completed');
  } catch (e) {
    print('Error: \${e}');
  }
}''',
        category: SnippetCategory.dart,
        language: 'dart',
        tags: ['dart', 'async', 'function'],
        parameters: ['functionName'],
      ),
      
      // Git snippets
      CodeSnippet(
        id: 'git_commit_message',
        name: 'Git Commit Message',
        description: 'Standard git commit message',
        code: 'feat: add new feature\n\n- Description of the feature\n\nCloses #123',
        category: SnippetCategory.git,
        language: 'git',
        tags: ['git', 'commit', 'message'],
        parameters: ['feature', 'issue'],
      ),
      CodeSnippet(
        id: 'git_branch_feature',
        name: 'Git Feature Branch',
        description: 'Create and switch to feature branch',
        code: 'git checkout -b feature/\${FEATURE_NAME}',
        category: SnippetCategory.git,
        language: 'git',
        tags: ['git', 'branch', 'feature'],
        parameters: ['FEATURE_NAME'],
      ),
      
      // Python snippets
      CodeSnippet(
        id: 'python_function',
        name: 'Python Function',
        description: 'Python function template',
        code: '''def function_name(param1, param2):
    """\"""
    Function description here.
    
    Args:
        param1: Description of param1
        param2: Description of param2
    """
    # Function implementation
    result = param1 + param2
    return result

if __name__ == "__main__":
    # Example usage
    result = function_name("value1", "value2")
    print(result)''',
        category: SnippetCategory.python,
        language: 'python',
        tags: ['python', 'function', 'template'],
        parameters: ['function_name'],
      ),
      
      // Shell snippets
      CodeSnippet(
        id: 'bash_function',
        name: 'Bash Function',
        description: 'Bash function template',
        code: '''function_name() {
    # Function description
    local param1="\$1"
    local param2="\$2"
    
    # Function implementation
    echo "Processing: \$param1 and \$param2"
    
    # Return result
    echo "Result: \$((\$param1 + \$param2))"
}

# Usage: function_name arg1 arg2''',
        category: SnippetCategory.shell,
        language: 'bash',
        tags: ['bash', 'function', 'shell'],
        parameters: ['function_name'],
      ),
    ];
    
    for (final snippet in defaultSnippets) {
      _snippets[snippet.id] = snippet;
    }
    
    await _saveSnippets();
  }
  
  /// Load environment variables
  Future<void> _loadEnvironment() async {
    try {
      // Load from .env file
      final envFile = File('${Platform.environment['HOME']}/.termisol/.env');
      if (await envFile.exists()) {
        final content = await envFile.readAsString();
        final lines = content.split('\n');
        
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('#')) {
            final parts = trimmedLine.split('=');
            if (parts.length == 2) {
              _environmentVariables[parts[0].trim()] = parts[1].trim();
            }
          }
        }
      }
      
      // Add system environment variables
      _environmentVariables.addAll(Platform.environment);
      
      debugPrint('🌍 Loaded ${_environmentVariables.length} environment variables');
    } catch (e) {
      debugPrint('⚠️ Failed to load environment: $e');
    }
  }
  
  /// Setup file watchers
  void _setupFileWatchers() {
    // Watch for changes to alias and snippet files
    // In a real implementation, you would use file system watchers
  }
  
  /// Expand command with aliases
  Future<String> expandCommand(String input) async {
    final parts = input.trim().split(' ');
    if (parts.isEmpty) return input;
    
    final command = parts[0];
    final arguments = parts.skip(1).toList();
    
    // Check if it's an alias
    final alias = _aliases[command];
    if (alias != null) {
      // Expand alias with parameters
      final expandedCommand = _expandAlias(alias, arguments);
      
      // Notify about alias execution
      _onAliasExecuted.forEach((callback) => callback(alias.name, expandedCommand));
      
      debugPrint('🔧 Expanded alias: $command → $expandedCommand');
      return expandedCommand;
    }
    
    // Check if it's a snippet insertion
    if (command.startsWith('snippet:')) {
      final snippetId = command.substring(8);
      final snippet = _snippets[snippetId];
      if (snippet != null) {
        final expandedSnippet = _expandSnippet(snippet, arguments);
        
        // Notify about snippet insertion
        _onSnippetInserted.forEach((callback) => callback(snippetId, expandedSnippet));
        
        debugPrint('📝 Inserted snippet: $snippetId');
        return expandedSnippet;
      }
    }
    
    // Return original command if no expansion
    return input;
  }
  
  /// Expand alias with parameters
  String _expandAlias(CommandAlias alias, List<String> arguments) {
    String command = alias.command;
    
    // Replace parameter placeholders
    for (int i = 0; i < arguments.length && i < alias.parameters.length; i++) {
      final param = alias.parameters[i];
      command = command.replaceAll('\${$param.toUpperCase()}', arguments[i]);
    }
    
    // Add remaining arguments
    if (arguments.length > alias.parameters.length) {
      final remainingArgs = arguments.skip(alias.parameters.length).join(' ');
      command = '$command $remainingArgs';
    }
    
    return command;
  }
  
  /// Expand snippet with parameters
  String _expandSnippet(CodeSnippet snippet, List<String> arguments) {
    String code = snippet.code;
    
    // Replace parameter placeholders
    for (int i = 0; i < arguments.length && i < snippet.parameters.length; i++) {
      final param = snippet.parameters[i];
      code = code.replaceAll('\${$param}', arguments[i]);
    }
    
    return code;
  }
  
  /// Add custom alias
  Future<void> addAlias(CommandAlias alias) async {
    _aliases[alias.name] = alias;
    await _saveAliases();
    
    _onAliasAdded.forEach((callback) => callback(alias));
    debugPrint('🔧 Added alias: ${alias.name}');
  }
  
  /// Remove alias
  Future<void> removeAlias(String name) async {
    final alias = _aliases.remove(name);
    if (alias != null) {
      await _saveAliases();
      _onAliasRemoved.forEach((callback) => callback(alias));
      debugPrint('🗑️ Removed alias: $name');
    }
  }
  
  /// Update alias
  Future<void> updateAlias(CommandAlias alias) async {
    _aliases[alias.name] = alias;
    await _saveAliases();
    debugPrint('🔧 Updated alias: ${alias.name}');
  }
  
  /// Add code snippet
  Future<void> addSnippet(CodeSnippet snippet) async {
    _snippets[snippet.id] = snippet;
    await _saveSnippets();
    
    _onSnippetAdded.forEach((callback) => callback(snippet));
    debugPrint('📝 Added snippet: ${snippet.name}');
  }
  
  /// Remove snippet
  Future<void> removeSnippet(String id) async {
    final snippet = _snippets.remove(id);
    if (snippet != null) {
      await _saveSnippets();
      _onSnippetRemoved.forEach((callback) => callback(snippet));
      debugPrint('🗑️ Removed snippet: $id');
    }
  }
  
  /// Update snippet
  Future<void> updateSnippet(CodeSnippet snippet) async {
    _snippets[snippet.id] = snippet;
    await _saveSnippets();
    debugPrint('📝 Updated snippet: ${snippet.name}');
  }
  
  /// Execute command with alias expansion
  Future<String> executeCommand(String input) async {
    // Add to command history
    _addToHistory(input);
    
    // Expand aliases and snippets
    final expanded = await expandCommand(input);
    
    return expanded;
  }
  
  /// Add to command history
  void _addToHistory(String command) {
    _commandHistory.insert(0, command);
    
    // Keep only last 1000 commands
    if (_commandHistory.length > 1000) {
      _commandHistory.removeRange(1000, _commandHistory.length);
    }
  }
  
  /// Search aliases
  List<CommandAlias> searchAliases(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _aliases.values.where((alias) {
      return alias.name.toLowerCase().contains(lowerQuery) ||
             alias.description.toLowerCase().contains(lowerQuery) ||
             alias.command.toLowerCase().contains(lowerQuery) ||
             alias.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Search snippets
  List<CodeSnippet> searchSnippets(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _snippets.values.where((snippet) {
      return snippet.name.toLowerCase().contains(lowerQuery) ||
             snippet.description.toLowerCase().contains(lowerQuery) ||
             snippet.code.toLowerCase().contains(lowerQuery) ||
             snippet.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Get aliases by category
  List<CommandAlias> getAliasesByCategory(AliasCategory category) {
    return _aliases.values
        .where((alias) => alias.category == category)
        .toList();
  }
  
  /// Get snippets by category
  List<CodeSnippet> getSnippetsByCategory(SnippetCategory category) {
    return _snippets.values
        .where((snippet) => snippet.category == category)
        .toList();
  }
  
  /// Get aliases by workspace
  List<CommandAlias> getAliasesByWorkspace(String workspace) {
    return _aliases.values
        .where((alias) => alias.workspace == workspace || alias.workspace == 'any')
        .toList();
  }
  
  /// Get snippets by language
  List<CodeSnippet> getSnippetsByLanguage(String language) {
    return _snippets.values
        .where((snippet) => snippet.language == language)
        .toList();
  }
  
  /// Get command suggestions
  List<String> getCommandSuggestions(String partial) {
    final suggestions = <String>[];
    final lowerPartial = partial.toLowerCase();
    
    // Check alias names
    for (final alias in _aliases.values) {
      if (alias.name.toLowerCase().startsWith(lowerPartial)) {
        suggestions.add(alias.name);
      }
    }
    
    // Check snippet IDs
    for (final snippet in _snippets.values) {
      if (snippet.id.toLowerCase().startsWith(lowerPartial)) {
        suggestions.add('snippet:${snippet.id}');
      }
    }
    
    // Check command history
    for (final command in _commandHistory) {
      if (command.toLowerCase().startsWith(lowerPartial)) {
        suggestions.add(command);
      }
    }
    
    return suggestions.toSet().toList();
  }
  
  /// Save aliases
  Future<void> _saveAliases() async {
    try {
      final aliasesData = _aliases.values.map((alias) => alias.toJson()).toList();
      final data = {
        'version': '1.0',
        'aliases': aliasesData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final aliasesFile = File(_aliasesPath);
      await aliasesFile.parent.create(recursive: true);
      await aliasesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save aliases: $e');
    }
  }
  
  /// Save snippets
  Future<void> _saveSnippets() async {
    try {
      final snippetsData = _snippets.values.map((snippet) => snippet.toJson()).toList();
      final data = {
        'version': '1.0',
        'snippets': snippetsData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final snippetsFile = File(_snippetsPath);
      await snippetsFile.parent.create(recursive: true);
      await snippetsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save snippets: $e');
    }
  }
  
  /// Update workspace context
  void updateWorkspace(String workspace) {
    _currentWorkspace = workspace;
    debugPrint('🔧 Updated workspace context: $workspace');
  }
  
  /// Update language context
  void updateLanguage(String language) {
    _currentLanguage = language;
    debugPrint('🔧 Updated language context: $language');
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    final aliasesByCategory = <String, int>{};
    final snippetsByCategory = <String, int>{};
    
    for (final alias in _aliases.values) {
      aliasesByCategory[alias.category.toString()] = 
          (aliasesByCategory[alias.category.toString()] ?? 0) + 1;
    }
    
    for (final snippet in _snippets.values) {
      snippetsByCategory[snippet.category.toString()] = 
          (snippetsByCategory[snippet.category.toString()] ?? 0) + 1;
    }
    
    return {
      'total_aliases': _aliases.length,
      'total_snippets': _snippets.length,
      'command_history_size': _commandHistory.length,
      'current_workspace': _currentWorkspace,
      'current_language': _currentLanguage,
      'environment_variables': _environmentVariables.length,
      'aliases_by_category': aliasesByCategory,
      'snippets_by_category': snippetsByCategory,
    };
  }
  
  /// Import aliases
  Future<bool> importAliases(String jsonData) async {
    try {
      final data = jsonDecode(jsonData);
      final aliasesData = data['aliases'] as List? ?? [];
      
      int importedCount = 0;
      for (final aliasData in aliasesData) {
        final alias = CommandAlias.fromJson(aliasData);
        
        // Generate new ID to avoid conflicts
        alias.name = '${alias.name}_imported_${DateTime.now().millisecondsSinceEpoch}';
        
        _aliases[alias.name] = alias;
        importedCount++;
      }
      
      await _saveAliases();
      debugPrint('🔧 Imported $importedCount aliases');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import aliases: $e');
      return false;
    }
  }
  
  /// Export aliases
  Future<String> exportAliases() async {
    final exportData = {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'workspace': _currentWorkspace,
      'language': _currentLanguage,
      'aliases': _aliases.values.map((a) => a.toJson()).toList(),
    };
    
    return jsonEncode(exportData);
  }
  
  /// Add alias added listener
  void addAliasAddedListener(Function(CommandAlias) listener) {
    _onAliasAdded.add(listener);
  }
  
  /// Add alias removed listener
  void addAliasRemovedListener(Function(CommandAlias) listener) {
    _onAliasRemoved.add(listener);
  }
  
  /// Add snippet added listener
  void addSnippetAddedListener(Function(CodeSnippet) listener) {
    _onSnippetAdded.add(listener);
  }
  
  /// Add snippet removed listener
  void addSnippetRemovedListener(Function(CodeSnippet) listener) {
    _onSnippetRemoved.add(listener);
  }
  
  /// Add alias executed listener
  void addAliasExecutedListener(Function(String, String) listener) {
    _onAliasExecuted.add(listener);
  }
  
  /// Add snippet inserted listener
  void addSnippetInsertedListener(Function(String, String) listener) {
    _onSnippetInserted.add(listener);
  }
  
  /// Remove alias added listener
  void removeAliasAddedListener(Function(CommandAlias) listener) {
    _onAliasAdded.remove(listener);
  }
  
  /// Remove alias removed listener
  void removeAliasRemovedListener(Function(CommandAlias) listener) {
    _onAliasRemoved.remove(listener);
  }
  
  /// Remove snippet added listener
  void removeSnippetAddedListener(Function(CodeSnippet) listener) {
    _onSnippetAdded.remove(listener);
  }
  
  /// Remove snippet removed listener
  void removeSnippetRemovedListener(Function(CodeSnippet) listener {
    _onSnippetRemoved.remove(listener);
  }
  
  /// Remove alias executed listener
  void removeAliasExecutedListener(Function(String, String) listener {
    _onAliasExecuted.remove(listener);
  }
  
  /// Remove snippet inserted listener
  void removeSnippetInsertedListener(Function(String, String) listener {
    _onSnippetInserted.remove(listener);
  }
  
  /// Dispose alias system
  Future<void> dispose() async {
    // Save final state
    await _saveAliases();
    await _saveSnippets();
    
    // Clear listeners
    _onAliasAdded.clear();
    _onAliasRemoved.clear();
    _onSnippetAdded.clear();
    _onSnippetRemoved.clear();
    _onAliasExecuted.clear();
    _onSnippetInserted.clear();
    
    _isInitialized = false;
    debugPrint('🔧 Command Alias System disposed');
  }
}

/// Command alias model
class CommandAlias {
  final String name;
  final String command;
  final String description;
  final AliasCategory category;
  final String workspace;
  final String language;
  final List<String> parameters;
  final DateTime createdAt;
  final int usageCount;
  final DateTime? lastUsed;
  final Map<String, dynamic>? metadata;
  
  CommandAlias({
    required this.name,
    required this.command,
    required this.description,
    required this.category,
    required this.workspace,
    required this.language,
    required this.parameters,
    this.createdAt,
    this.usageCount = 0,
    this.lastUsed,
    this.metadata,
  }) : createdAt = DateTime.now();
  
  factory CommandAlias.fromJson(Map<String, dynamic> json) {
    return CommandAlias(
      name: json['name'],
      command: json['command'],
      description: json['description'],
      category: AliasCategory.values.firstWhere(
        (c) => c.toString() == json['category'],
        orElse: () => AliasCategory.custom,
      ),
      workspace: json['workspace'] ?? 'any',
      language: json['language'] ?? 'any',
      parameters: List<String>.from(json['parameters'] ?? []),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      usageCount: json['usage_count'] ?? 0,
      lastUsed: json['last_used'] != null 
          ? DateTime.parse(json['last_used'])
          : null,
      metadata: json['metadata'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'command': command,
      'description': description,
      'category': category.toString(),
      'workspace': workspace,
      'language': language,
      'parameters': parameters,
      'created_at': createdAt.toIso8601String(),
      'usage_count': usageCount,
      'last_used': lastUsed?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Code snippet model
class CodeSnippet {
  final String id;
  final String name;
  final String description;
  final String code;
  final SnippetCategory category;
  final String language;
  final List<String> tags;
  final List<String> parameters;
  final DateTime createdAt;
  final int usageCount;
  final DateTime? lastUsed;
  final Map<String, dynamic>? metadata;
  
  CodeSnippet({
    required this.id,
    required this.name,
    required this.description,
    required this.code,
    required this.category,
    required this.language,
    required this.tags,
    required this.parameters,
    this.createdAt,
    this.usageCount = 0,
    this.lastUsed,
    this.metadata,
  }) : createdAt = DateTime.now();
  
  factory CodeSnippet.fromJson(Map<String, dynamic> json) {
    return CodeSnippet(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      code: json['code'],
      category: SnippetCategory.values.firstWhere(
        (c) => c.toString() == json['category'],
        orElse: () => SnippetCategory.custom,
      ),
      language: json['language'] ?? 'any',
      tags: List<String>.from(json['tags'] ?? []),
      parameters: List<String>.from(json['parameters'] ?? []),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      usageCount: json['usage_count'] ?? 0,
      lastUsed: json['last_used'] != null 
          ? DateTime.parse(json['last_used'])
          : null,
      metadata: json['metadata'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'code': code,
      'category': category.toString(),
      'language': language,
      'tags': tags,
      'parameters': parameters,
      'created_at': createdAt.toIso8601String(),
      'usage_count': usageCount,
      'last_used': lastUsed?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Alias categories
enum AliasCategory {
  development,
  git,
  system,
  navigation,
  custom,
}

/// Snippet categories
enum SnippetCategory {
  flutter,
  dart,
  python,
  javascript,
  git,
  shell,
  custom,
}
