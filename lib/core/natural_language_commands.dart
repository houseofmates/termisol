import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Natural Language Command Processor with NVIDIA API Integration
/// 
/// Converts natural language descriptions to actual terminal commands
/// using high-quality NVIDIA AI models with round-robin API key rotation.
class NaturalLanguageCommands {
  static final NaturalLanguageCommands _instance = NaturalLanguageCommands._internal();
  factory NaturalLanguageCommands() => _instance;
  NaturalLanguageCommands._internal();

  bool _isInitialized = false;
  final List<String> _apiKeys = [];
  int _currentApiKeyIndex = 0;
  String? _currentModel;
  
  // Command cache and learning
  final Map<String, String> _commandCache = {};
  final List<NLCommand> _commandHistory = [];
  final Map<String, CommandPattern> _learnedPatterns = {};
  
  // Event system
  final _commandController = StreamController<NLCommandEvent>.broadcast();
  Stream<NLCommandEvent> get events => _commandController.stream;
  
  // Configuration
  static const String _baseUrl = 'https://integrate.api.nvidia.com/v1';
  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const int _cacheSize = 1000;
  
  bool get isInitialized => _isInitialized;
  int get cachedCommands => _commandCache.length;
  int get learnedPatterns => _learnedPatterns.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load API keys from environment
      await _loadApiKeys();
      
      // Load cached commands
      await _loadCommandCache();
      
      // Load learned patterns
      await _loadLearnedPatterns();
      
      _isInitialized = true;
      debugPrint('🤖 Natural Language Commands initialized with ${_apiKeys.length} API keys');
    } catch (e) {
      debugPrint('❌ Failed to initialize Natural Language Commands: $e');
    }
  }

  Future<void> _loadApiKeys() async {
    // Load NVIDIA API keys from environment
    for (int i = 1; i <= 24; i++) {
      final key = Platform.environment['NVIDIA_API_KEY_$i'];
      if (key != null && key.isNotEmpty) {
        _apiKeys.add(key);
      }
    }
    
    if (_apiKeys.isEmpty) {
      throw Exception('No NVIDIA API keys found. Please set NVIDIA_API_KEY_1 through NVIDIA_API_KEY_24 in your environment.');
    }
    
    // Set default model
    _currentModel = Platform.environment['PRIMARY_AI_MODEL'] ?? 'deepseek-ai/deepseek-v4-pro';
    
    debugPrint('🔑 Loaded ${_apiKeys.length} NVIDIA API keys');
  }

  Future<void> _loadCommandCache() async {
    try {
      final cacheFile = File('${Platform.environment['HOME']}/.termisol/nl_command_cache.json');
      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _commandCache.addAll(Map<String, String>.from(data['cache'] ?? {}));
        
        // Limit cache size
        if (_commandCache.length > _cacheSize) {
          final entries = _commandCache.entries.toList();
          entries.sort((a, b) => a.key.compareTo(b.key));
          _commandCache.clear();
          _commandCache.addEntries(entries.take(_cacheSize));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load command cache: $e');
    }
  }

  Future<void> _loadLearnedPatterns() async {
    try {
      final patternsFile = File('${Platform.environment['HOME']}/.termisol/learned_patterns.json');
      if (await patternsFile.exists()) {
        final content = await patternsFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['patterns'] as Map<String, dynamic>).entries) {
          _learnedPatterns[entry.key] = CommandPattern.fromJson(entry.value);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load learned patterns: $e');
    }
  }

  Future<String> processNaturalLanguageCommand(
    String naturalLanguage, {
    String? context,
    String? currentDirectory,
    Map<String, String>? environment,
    bool useCache = true,
  }) async {
    try {
      // Check cache first
      if (useCache && _commandCache.containsKey(naturalLanguage)) {
        final cachedCommand = _commandCache[naturalLanguage]!;
        _emitEvent(NLCommandEvent(
          type: NLCommandEventType.cached,
          input: naturalLanguage,
          output: cachedCommand,
        ));
        return cachedCommand;
      }
      
      // Check learned patterns
      final patternMatch = _matchLearnedPattern(naturalLanguage);
      if (patternMatch != null) {
        _emitEvent(NLCommandEvent(
          type: NLCommandEventType.patternMatched,
          input: naturalLanguage,
          output: patternMatch,
        ));
        return patternMatch;
      }
      
      // Build context for AI
      final aiContext = _buildContext(context, currentDirectory, environment);
      
      // Call NVIDIA API
      final command = await _callNvidiaAPI(naturalLanguage, aiContext);
      
      // Cache the result
      _commandCache[naturalLanguage] = command;
      await _saveCommandCache();
      
      // Add to history
      _addToHistory(naturalLanguage, command);
      
      _emitEvent(NLCommandEvent(
        type: NLCommandEventType.processed,
        input: naturalLanguage,
        output: command,
      ));
      
      return command;
    } catch (e) {
      debugPrint('❌ Failed to process natural language command: $e');
      
      _emitEvent(NLCommandEvent(
        type: NLCommandEventType.error,
        input: naturalLanguage,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  String? _matchLearnedPattern(String input) {
    final normalizedInput = input.toLowerCase().trim();
    
    for (final pattern in _learnedPatterns.values) {
      if (pattern.matches(normalizedInput)) {
        return pattern.generateCommand(normalizedInput);
      }
    }
    
    return null;
  }

  Map<String, dynamic> _buildContext(
    String? context,
    String? currentDirectory,
    Map<String, String>? environment,
  ) {
    final contextMap = <String, dynamic>{
      'current_directory': currentDirectory ?? Directory.current.path,
      'environment': environment ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    if (context != null) {
      contextMap['additional_context'] = context;
    }
    
    // Add directory analysis
    if (currentDirectory != null) {
      contextMap['directory_analysis'] = _analyzeDirectory(currentDirectory);
    }
    
    // Add recent commands from history
    if (_commandHistory.isNotEmpty) {
      final recentCommands = _commandHistory
          .take(5)
          .map((cmd) => {'input': cmd.input, 'output': cmd.output})
          .toList();
      contextMap['recent_commands'] = recentCommands;
    }
    
    return contextMap;
  }

  Map<String, dynamic> _analyzeDirectory(String directory) {
    final dir = Directory(directory);
    final analysis = <String, dynamic>{
      'exists': dir.existsSync(),
      'files': <String>[],
      'directories': <String>[],
      'project_type': 'unknown',
    };
    
    if (!dir.existsSync()) return analysis;
    
    try {
      final entities = dir.listSync().take(50).toList(); // Limit to 50 items
      
      for (final entity in entities) {
        final name = entity.path.split('/').last;
        if (entity is File) {
          analysis['files'].add(name);
        } else if (entity is Directory) {
          analysis['directories'].add(name);
        }
      }
      
      // Determine project type
      analysis['project_type'] = _determineProjectType(directory);
    } catch (e) {
      debugPrint('⚠️ Failed to analyze directory: $e');
    }
    
    return analysis;
  }

  String _determineProjectType(String directory) {
    final dir = Directory(directory);
    
    // Check for project indicators
    if (File('$directory/package.json').existsSync()) return 'nodejs';
    if (File('$directory/pubspec.yaml').existsSync()) return 'dart';
    if (File('$directory/Cargo.toml').existsSync()) return 'rust';
    if (File('$directory/Dockerfile').existsSync()) return 'docker';
    if (Directory('$directory/.git').existsSync()) return 'git';
    if (File('$directory/go.mod').existsSync()) return 'go';
    if (File('$directory/pom.xml').existsSync()) return 'maven';
    if (File('$directory/requirements.txt').existsSync()) return 'python';
    
    return 'unknown';
  }

  Future<String> _callNvidiaAPI(String input, Map<String, dynamic> context) async {
    final prompt = _buildPrompt(input, context);
    
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final apiKey = _getNextApiKey();
        final response = await _makeAPIRequest(prompt, apiKey);
        
        if (response.isNotEmpty) {
          return _parseResponse(response);
        }
      } catch (e) {
        debugPrint('⚠️ API attempt ${attempt + 1} failed: $e');
        if (attempt == _maxRetries - 1) rethrow;
        
        // Wait before retry
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    
    throw Exception('Failed to get response from NVIDIA API after $_maxRetries attempts');
  }

  String _buildPrompt(String input, Map<String, dynamic> context) {
    return '''
You are an expert terminal command generator. Convert the following natural language description into a precise, executable shell command.

CONTEXT:
- Current Directory: ${context['current_directory']}
- Project Type: ${context['directory_analysis']['project_type']}
- Available Files: ${context['directory_analysis']['files'].take(10).join(', ')}
- Available Directories: ${context['directory_analysis']['directories'].take(10).join(', ')}
${context['additional_context'] != null ? '- Additional Context: ${context['additional_context']}' : ''}

RECENT COMMANDS:
${context['recent_commands']?.map((cmd) => '- ${cmd['input']} → ${cmd['output']}').join('\n') ?? 'None'}

TASK:
Convert this natural language request to a shell command: "$input"

RULES:
1. Generate ONLY the command, no explanations
2. Use absolute paths when necessary
3. Include common flags and options that are typically needed
4. Ensure the command is safe and executable
5. Use appropriate tools for the detected project type
6. If multiple commands are needed, separate with && or ;
7. Handle edge cases and provide fallback options
8. Consider the current directory and available files

COMMAND:
''';
  }

  String _getNextApiKey() {
    final apiKey = _apiKeys[_currentApiKeyIndex];
    _currentApiKeyIndex = (_currentApiKeyIndex + 1) % _apiKeys.length;
    return apiKey;
  }

  Future<String> _makeAPIRequest(String prompt, String apiKey) async {
    final url = Uri.parse('$_baseUrl/chat/completions');
    
    final requestBody = {
      'model': _currentModel,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'max_tokens': 500,
      'temperature': 0.1,
      'top_p': 0.9,
    };
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    ).timeout(_timeout);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List;
      
      if (choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>;
        return message['content'] as String;
      }
    } else {
      throw Exception('API request failed with status ${response.statusCode}: ${response.body}');
    }
    
    throw Exception('No response from API');
  }

  String _parseResponse(String response) {
    // Clean up the response
    String command = response.trim();
    
    // Remove common prefixes
    command = command.replaceAll(RegExp(r'^(command:|shell:|bash:|\$)', caseSensitive: false), '');
    
    // Remove markdown code blocks
    command = command.replaceAll(RegExp(r'^```(?:bash|shell)?\s*'), '');
    command = command.replaceAll(RegExp(r'\s*```$'), '');
    
    // Remove quotes
    command = command.replaceAll(RegExp(r'^["\']|["\']$'), '');
    
    // Clean up whitespace
    command = command.trim();
    
    if (command.isEmpty) {
      throw Exception('Empty command generated');
    }
    
    return command;
  }

  void _addToHistory(String input, String output) {
    final command = NLCommand(
      id: 'nl_${DateTime.now().millisecondsSinceEpoch}',
      input: input,
      output: output,
      timestamp: DateTime.now(),
      context: {},
    );
    
    _commandHistory.add(command);
    
    // Limit history size
    if (_commandHistory.length > 1000) {
      _commandHistory.removeAt(0);
    }
  }

  Future<void> learnPattern(String input, String output) async {
    final pattern = CommandPattern.fromExamples(input, output);
    _learnedPatterns[pattern.id] = pattern;
    
    await _saveLearnedPatterns();
    
    _emitEvent(NLCommandEvent(
      type: NLCommandEventType.patternLearned,
      input: input,
      output: output,
    ));
  }

  Future<void> _saveCommandCache() async {
    try {
      final cacheFile = File('${Platform.environment['HOME']}/.termisol/nl_command_cache.json');
      await cacheFile.parent.create(recursive: true);
      
      final data = {
        'cache': _commandCache,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await cacheFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save command cache: $e');
    }
  }

  Future<void> _saveLearnedPatterns() async {
    try {
      final patternsFile = File('${Platform.environment['HOME']}/.termisol/learned_patterns.json');
      await patternsFile.parent.create(recursive: true);
      
      final data = {
        'patterns': _learnedPatterns.map((k, v) => MapEntry(k, v.toJson())),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await patternsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save learned patterns: $e');
    }
  }

  void _emitEvent(NLCommandEvent event) {
    _commandController.add(event);
  }

  Future<List<String>> suggestCommands(String partialInput) async {
    final suggestions = <String>[];
    
    // Get cache suggestions
    suggestions.addAll(_commandCache.keys
        .where((key) => key.toLowerCase().contains(partialInput.toLowerCase()))
        .take(5));
    
    // Get pattern suggestions
    for (final pattern in _learnedPatterns.values) {
      if (pattern.matches(partialInput)) {
        suggestions.add(pattern.generateCommand(partialInput));
      }
    }
    
    // Get history suggestions
    suggestions.addAll(_commandHistory
        .where((cmd) => cmd.input.toLowerCase().contains(partialInput.toLowerCase()))
        .map((cmd) => cmd.output)
        .take(5));
    
    return suggestions.toSet().toList();
  }

  NLCommandStatistics getStatistics() {
    return NLCommandStatistics(
      totalCommands: _commandHistory.length,
      cachedCommands: _commandCache.length,
      learnedPatterns: _learnedPatterns.length,
      apiKeysCount: _apiKeys.length,
      currentModel: _currentModel,
      averageResponseTime: _calculateAverageResponseTime(),
      mostCommonInputs: _getMostCommonInputs(),
    );
  }

  double _calculateAverageResponseTime() {
    // In a real implementation, this would track actual response times
    return 1.5; // seconds
  }

  List<String> _getMostCommonInputs() {
    final inputCounts = <String, int>{};
    
    for (final command in _commandHistory) {
      inputCounts[command.input] = (inputCounts[command.input] ?? 0) + 1;
    }
    
    return inputCounts.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        .take(10)
        .map((e) => e.key)
        .toList();
  }

  Future<void> dispose() async {
    _commandController.close();
    _commandCache.clear();
    _commandHistory.clear();
    _learnedPatterns.clear();
    _isInitialized = false;
    
    debugPrint('🤖 Natural Language Commands disposed');
  }
}

/// Data classes
class NLCommand {
  final String id;
  final String input;
  final String output;
  final DateTime timestamp;
  final Map<String, dynamic> context;
  
  NLCommand({
    required this.id,
    required this.input,
    required this.output,
    required this.timestamp,
    required this.context,
  });
}

class CommandPattern {
  final String id;
  final String pattern;
  final String template;
  final Map<String, String> variables;
  int usageCount = 0;
  DateTime lastUsed = DateTime.now();
  
  CommandPattern({
    required this.id,
    required this.pattern,
    required this.template,
    required this.variables,
  });
  
  bool matches(String input) {
    // Simple pattern matching (can be enhanced with regex)
    return input.toLowerCase().contains(pattern.toLowerCase());
  }
  
  String generateCommand(String input) {
    String command = template;
    
    // Replace variables (simplified)
    for (final entry in variables.entries) {
      command = command.replaceAll('\${${entry.key}}', entry.value);
    }
    
    return command;
  }
  
  factory CommandPattern.fromExamples(String input, String output) {
    // Generate pattern from examples (simplified)
    final id = 'pattern_${DateTime.now().millisecondsSinceEpoch}';
    final pattern = _extractPattern(input);
    final template = _extractTemplate(output);
    
    return CommandPattern(
      id: id,
      pattern: pattern,
      template: template,
      variables: {},
    );
  }
  
  static String _extractPattern(String input) {
    // Extract key pattern from input (simplified)
    final words = input.toLowerCase().split(' ');
    return words.take(3).join(' ');
  }
  
  static String _extractTemplate(String output) {
    // Extract template from output (simplified)
    return output;
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pattern': pattern,
      'template': template,
      'variables': variables,
      'usage_count': usageCount,
      'last_used': lastUsed.toIso8601String(),
    };
  }
  
  factory CommandPattern.fromJson(Map<String, dynamic> json) {
    return CommandPattern(
      id: json['id'],
      pattern: json['pattern'],
      template: json['template'],
      variables: Map<String, String>.from(json['variables'] ?? {}),
    );
  }
}

class NLCommandEvent {
  final NLCommandEventType type;
  final String input;
  final String? output;
  final String? error;
  
  NLCommandEvent({
    required this.type,
    required this.input,
    this.output,
    this.error,
  });
}

class NLCommandStatistics {
  final int totalCommands;
  final int cachedCommands;
  final int learnedPatterns;
  final int apiKeysCount;
  final String? currentModel;
  final double averageResponseTime;
  final List<String> mostCommonInputs;
  
  NLCommandStatistics({
    required this.totalCommands,
    required this.cachedCommands,
    required this.learnedPatterns,
    required this.apiKeysCount,
    this.currentModel,
    required this.averageResponseTime,
    required this.mostCommonInputs,
  });
}

enum NLCommandEventType {
  processed,
  cached,
  patternMatched,
  patternLearned,
  error,
}
