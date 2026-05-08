import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Natural language command translation
/// Translates natural language descriptions into executable commands
class NaturalLanguageTranslator {
  static const String _baseUrl = 'https://api.openai.com/v1';
  String? _apiKey;
  final Map<String, CommandTranslation> _translationCache = {};
  final StreamController<TranslationEvent> _eventController = StreamController<TranslationEvent>.broadcast();
  
  Stream<TranslationEvent> get events => _eventController.stream;

  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey ?? _getApiKeyFromConfig();
    
    if (_apiKey != null) {
      _eventController.add(TranslationEvent(
        type: TranslationEventType.initialized,
        message: 'Natural Language Translator initialized with AI API',
      ));
      debugPrint('🗣️ Natural Language Translator initialized');
    } else {
      _eventController.add(TranslationEvent(
        type: TranslationEventType.initialized,
        message: 'Natural Language Translator initialized without AI API',
      ));
      debugPrint('🗣️ Natural Language Translator initialized (local mode)');
    }
  }

  String? _getApiKeyFromConfig() {
    return Platform.environment['OPENAI_API_KEY'];
  }

  Future<CommandTranslation> translateCommand(
    String naturalLanguage, {
    String? context,
    String? workingDirectory,
    bool useCache = true,
  }) async {
    final cacheKey = _generateCacheKey(naturalLanguage, context, workingDirectory);
    
    if (useCache && _translationCache.containsKey(cacheKey)) {
      return _translationCache[cacheKey]!;
    }

    if (_apiKey == null) {
      return _generateLocalTranslation(naturalLanguage, context: context);
    }

    try {
      final translation = await _generateAITranslation(
        naturalLanguage,
        context: context,
        workingDirectory: workingDirectory,
      );
      
      _translationCache[cacheKey] = translation;
      
      _eventController.add(TranslationEvent(
        type: TranslationEventType.translation_generated,
        message: 'Command translation generated',
        data: {
          'input': naturalLanguage,
          'output': translation.command,
          'confidence': translation.confidence,
        },
      ));

      return translation;
    } catch (e) {
      debugPrint('Failed to generate AI translation: $e');
      return _generateLocalTranslation(naturalLanguage, context: context);
    }
  }

  String _generateCacheKey(String input, String? context, String? workingDirectory) {
    final combined = '$input|$context|$workingDirectory';
    return combined.hashCode.toString();
  }

  Future<CommandTranslation> _generateAITranslation(
    String naturalLanguage, {
    String? context,
    String? workingDirectory,
  }) async {
    final prompt = _buildTranslationPrompt(naturalLanguage, context: context, workingDirectory: workingDirectory);
    
    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an expert command-line interface translator. Convert natural language descriptions into precise, executable shell commands. Always consider safety and provide the most efficient command.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'max_tokens': 300,
        'temperature': 0.2,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final translation = data['choices'][0]['message']['content'];
      
      return _parseTranslationResponse(translation, naturalLanguage);
    } else {
      throw Exception('Failed to get AI translation: ${response.statusCode}');
    }
  }

  String _buildTranslationPrompt(String naturalLanguage, {String? context, String? workingDirectory}) {
    var prompt = 'Translate this natural language request into a shell command';
    
    if (context != null) {
      prompt += ' with context: $context';
    }
    
    if (workingDirectory != null) {
      prompt += ' in directory: $workingDirectory';
    }
    
    prompt += ':\n\n"$naturalLanguage"\n\n';
    prompt += 'Please provide:\n';
    prompt += '1. The exact command to execute\n';
    prompt += '2. A brief explanation of what the command does\n';
    prompt += '3. Confidence level (high/medium/low)\n';
    prompt += '4. Any safety warnings or considerations\n';
    prompt += '5. Alternative commands if applicable\n';
    
    return prompt;
  }

  CommandTranslation _parseTranslationResponse(String response, String originalInput) {
    final lines = response.split('\n');
    String? command;
    String? explanation;
    String? confidence;
    List<String> warnings = [];
    List<String> alternatives = [];
    
    String? currentSection;
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('1.') || trimmed.toLowerCase().contains('command')) {
        currentSection = 'command';
        continue;
      } else if (trimmed.startsWith('2.') || trimmed.toLowerCase().contains('explanation')) {
        currentSection = 'explanation';
        continue;
      } else if (trimmed.startsWith('3.') || trimmed.toLowerCase().contains('confidence')) {
        currentSection = 'confidence';
        continue;
      } else if (trimmed.startsWith('4.') || trimmed.toLowerCase().contains('warning')) {
        currentSection = 'warnings';
        continue;
      } else if (trimmed.startsWith('5.') || trimmed.toLowerCase().contains('alternative')) {
        currentSection = 'alternatives';
        continue;
      }
      
      if (trimmed.isEmpty) continue;
      
      switch (currentSection) {
        case 'command':
          command = (command ?? '') + trimmed + ' ';
          break;
        case 'explanation':
          explanation = (explanation ?? '') + trimmed + ' ';
          break;
        case 'confidence':
          if (trimmed.contains('high')) confidence = 'high';
          else if (trimmed.contains('medium')) confidence = 'medium';
          else if (trimmed.contains('low')) confidence = 'low';
          break;
        case 'warnings':
          warnings.add(trimmed);
          break;
        case 'alternatives':
          alternatives.add(trimmed);
          break;
      }
    }
    
    return CommandTranslation(
      originalInput: originalInput,
      command: command?.trim() ?? '',
      explanation: explanation?.trim() ?? 'Command generated',
      confidence: _parseConfidence(confidence ?? 'medium'),
      warnings: warnings,
      alternatives: alternatives,
      generatedAt: DateTime.now(),
      isAI: true,
    );
  }

  ConfidenceLevel _parseConfidence(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return ConfidenceLevel.high;
      case 'medium':
        return ConfidenceLevel.medium;
      case 'low':
        return ConfidenceLevel.low;
      default:
        return ConfidenceLevel.medium;
    }
  }

  CommandTranslation _generateLocalTranslation(String naturalLanguage, {String? context}) {
    final input = naturalLanguage.toLowerCase().trim();
    String command = '';
    String explanation = '';
    ConfidenceLevel confidence = ConfidenceLevel.low;
    
    // File operations
    if (input.contains('list') || input.contains('show files')) {
      if (input.contains('all') || input.contains('hidden')) {
        command = 'ls -la';
        explanation = 'List all files including hidden ones';
        confidence = ConfidenceLevel.high;
      } else {
        command = 'ls';
        explanation = 'List files in current directory';
        confidence = ConfidenceLevel.high;
      }
    } else if (input.contains('create') && input.contains('folder')) {
      command = 'mkdir new_folder';
      explanation = 'Create a new directory';
      confidence = ConfidenceLevel.medium;
    } else if (input.contains('create') && input.contains('file')) {
      command = 'touch new_file.txt';
      explanation = 'Create a new empty file';
      confidence = ConfidenceLevel.medium;
    } else if (input.contains('delete') || input.contains('remove')) {
      if (input.contains('folder') || input.contains('directory')) {
        command = 'rm -rf folder_name';
        explanation = 'Remove directory and its contents';
        confidence = ConfidenceLevel.medium;
      } else {
        command = 'rm file_name';
        explanation = 'Remove file';
        confidence = ConfidenceLevel.medium;
      }
    } else if (input.contains('copy')) {
      command = 'cp source destination';
      explanation = 'Copy file or directory';
      confidence = ConfidenceLevel.medium;
    } else if (input.contains('move') || input.contains('rename')) {
      command = 'mv source destination';
      explanation = 'Move or rename file or directory';
      confidence = ConfidenceLevel.medium;
    }
    
    // Navigation
    else if (input.contains('go') || input.contains('change') || input.contains('cd')) {
      if (input.contains('home') || input.contains('~')) {
        command = 'cd ~';
        explanation = 'Change to home directory';
        confidence = ConfidenceLevel.high;
      } else if (input.contains('parent') || input.contains('up')) {
        command = 'cd ..';
        explanation = 'Change to parent directory';
        confidence = ConfidenceLevel.high;
      } else if (input.contains('root') || input.contains('/')) {
        command = 'cd /';
        explanation = 'Change to root directory';
        confidence = ConfidenceLevel.high;
      }
    }
    
    // Search
    else if (input.contains('search') || input.contains('find')) {
      if (input.contains('file')) {
        command = 'find . -name "filename"';
        explanation = 'Find files by name';
        confidence = ConfidenceLevel.medium;
      } else if (input.contains('text') || input.contains('content')) {
        command = 'grep -r "search_term" .';
        explanation = 'Search for text in files recursively';
        confidence = ConfidenceLevel.medium;
      }
    }
    
    // Process management
    else if (input.contains('process') || input.contains('running')) {
      command = 'ps aux';
      explanation = 'Show running processes';
      confidence = ConfidenceLevel.high;
    } else if (input.contains('kill') || input.contains('stop')) {
      command = 'kill process_id';
      explanation = 'Kill a process by ID';
      confidence = ConfidenceLevel.medium;
    }
    
    // System info
    else if (input.contains('disk') || input.contains('space')) {
      command = 'df -h';
      explanation = 'Show disk usage in human readable format';
      confidence = ConfidenceLevel.high;
    } else if (input.contains('memory') || input.contains('ram')) {
      command = 'free -h';
      explanation = 'Show memory usage in human readable format';
      confidence = ConfidenceLevel.high;
    } else if (input.contains('system') || input.contains('info')) {
      command = 'uname -a';
      explanation = 'Show system information';
      confidence = ConfidenceLevel.high;
    }
    
    // Git operations
    else if (input.contains('git')) {
      if (input.contains('status')) {
        command = 'git status';
        explanation = 'Show git repository status';
        confidence = ConfidenceLevel.high;
      } else if (input.contains('add')) {
        command = 'git add .';
        explanation = 'Add all changes to git staging';
        confidence = ConfidenceLevel.high;
      } else if (input.contains('commit')) {
        command = 'git commit -m "commit message"';
        explanation = 'Commit changes with message';
        confidence = ConfidenceLevel.medium;
      } else if (input.contains('push')) {
        command = 'git push';
        explanation = 'Push changes to remote repository';
        confidence = ConfidenceLevel.high;
      } else if (input.contains('pull')) {
        command = 'git pull';
        explanation = 'Pull changes from remote repository';
        confidence = ConfidenceLevel.high;
      }
    }
    
    // Network
    else if (input.contains('ping')) {
      command = 'ping google.com';
      explanation = 'Test network connectivity';
      confidence = ConfidenceLevel.medium;
    } else if (input.contains('ip') || input.contains('address')) {
      command = 'ip addr show';
      explanation = 'Show IP addresses';
      confidence = ConfidenceLevel.high;
    }
    
    // If no specific pattern matched
    if (command.isEmpty) {
      command = '# Could not translate: "$naturalLanguage"';
      explanation = 'Unable to translate this request';
      confidence = ConfidenceLevel.low;
    }
    
    return CommandTranslation(
      originalInput: naturalLanguage,
      command: command,
      explanation: explanation,
      confidence: confidence,
      warnings: command.startsWith('#') ? ['Unable to translate request'] : [],
      alternatives: [],
      generatedAt: DateTime.now(),
      isAI: false,
    );
  }

  Future<List<String>> suggestRelatedCommands(String command) async {
    // This would integrate with a command knowledge base
    final suggestions = <String>[];
    
    if (command.contains('ls')) {
      suggestions.addAll(['ls -la', 'ls -lh', 'tree', 'find . -type f']);
    } else if (command.contains('git')) {
      suggestions.addAll(['git status', 'git log', 'git diff', 'git branch']);
    } else if (command.contains('docker')) {
      suggestions.addAll(['docker ps', 'docker images', 'docker logs', 'docker exec']);
    } else if (command.contains('npm')) {
      suggestions.addAll(['npm install', 'npm run', 'npm test', 'npm build']);
    }
    
    return suggestions;
  }

  Future<List<String>> getCommandHistory() async {
    // This would integrate with the shell history
    return [
      'ls -la',
      'git status',
      'docker ps',
      'npm install',
      'cd projects',
    ];
  }

  void clearCache() {
    _translationCache.clear();
    _eventController.add(TranslationEvent(
      type: TranslationEventType.cache_cleared,
      message: 'Translation cache cleared',
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'cacheSize': _translationCache.length,
      'hasApiKey': _apiKey != null,
      'totalTranslations': _translationCache.length,
    };
  }

  Future<void> dispose() async {
    _eventController.close();
    debugPrint('🗣️ Natural Language Translator disposed');
  }
}

class CommandTranslation {
  final String originalInput;
  final String command;
  final String explanation;
  final ConfidenceLevel confidence;
  final List<String> warnings;
  final List<String> alternatives;
  final DateTime generatedAt;
  final bool isAI;

  CommandTranslation({
    required this.originalInput,
    required this.command,
    required this.explanation,
    required this.confidence,
    required this.warnings,
    required this.alternatives,
    required this.generatedAt,
    required this.isAI,
  });

  bool get isValid => !command.startsWith('#') && command.isNotEmpty;
}

enum ConfidenceLevel {
  high,
  medium,
  low,
}

enum TranslationEventType {
  initialized,
  translation_generated,
  cache_cleared,
  error,
}

class TranslationEvent {
  final TranslationEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  TranslationEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Natural language translator widget
class NaturalLanguageTranslatorWidget extends StatefulWidget {
  final Function(CommandTranslation)? onCommandSelected;
  final String? workingDirectory;

  const NaturalLanguageTranslatorWidget({
    super.key,
    this.onCommandSelected,
    this.workingDirectory,
  });

  @override
  State<NaturalLanguageTranslatorWidget> createState() => _NaturalLanguageTranslatorWidgetState();
}

class _NaturalLanguageTranslatorWidgetState extends State<NaturalLanguageTranslatorWidget> {
  final NaturalLanguageTranslator _translator = NaturalLanguageTranslator();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  
  CommandTranslation? _currentTranslation;
  bool _isTranslating = false;
  List<String> _suggestions = [];
  List<String> _history = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _translator.getCommandHistory();
      setState(() {
        _history = history;
      });
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
  }

  Future<void> _translate() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isTranslating = true;
      _currentTranslation = null;
    });

    try {
      final translation = await _translator.translateCommand(
        input,
        context: 'Terminal command execution',
        workingDirectory: widget.workingDirectory,
      );

      setState(() {
        _currentTranslation = translation;
        _isTranslating = false;
      });

      if (translation.isValid) {
        _loadSuggestions(translation.command);
      }
    } catch (e) {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  Future<void> _loadSuggestions(String command) async {
    try {
      final suggestions = await _translator.suggestRelatedCommands(command);
      setState(() {
        _suggestions = suggestions;
      });
    } catch (e) {
      debugPrint('Failed to load suggestions: $e');
    }
  }

  void _selectCommand(CommandTranslation translation) {
    if (widget.onCommandSelected != null) {
      widget.onCommandSelected!(translation);
    }
    
    // Add to history
    if (!_history.contains(translation.command)) {
      setState(() {
        _history.insert(0, translation.command);
        if (_history.length > 20) {
          _history.removeLast();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 500),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.translate, color: Colors.blue[400]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Natural Language Translator',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.workingDirectory != null)
                        Text(
                          'Directory: ${widget.workingDirectory}',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                  icon: Icon(
                    _showHistory ? Icons.close : Icons.history,
                    color: Colors.grey[400],
                  ),
                  tooltip: 'Command History',
                ),
              ],
            ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Describe what you want to do...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[600]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.blue),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onSubmitted: (_) => _translate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isTranslating ? null : _translate,
                      icon: _isTranslating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send, size: 16),
                      label: Text(_isTranslating ? 'Translating...' : 'Translate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Quick examples
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildExampleChip('List all files'),
                    _buildExampleChip('Create new folder'),
                    _buildExampleChip('Git status'),
                    _buildExampleChip('Show running processes'),
                  ],
                ),
              ],
            ),
          ),
          
          // Results area
          Expanded(
            child: _showHistory
                ? _buildHistoryView()
                : _buildTranslationView(),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _inputController.text = text;
        _translate();
      },
      backgroundColor: Colors.grey[700],
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
    );
  }

  Widget _buildTranslationView() {
    if (_currentTranslation == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.translate, color: Colors.grey[400], size: 48),
              const SizedBox(height: 16),
              Text(
                'Type a natural language description',
                style: TextStyle(color: Colors.grey[400]),
              ),
              const SizedBox(height: 8),
              Text(
                'Examples: "list all files", "create new folder", "git status"',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Translation result
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _currentTranslation!.isValid
                    ? Colors.green[700]!
                    : Colors.red[700]!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _currentTranslation!.isValid ? Icons.check_circle : Icons.error,
                      color: _currentTranslation!.isValid ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Generated Command',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getConfidenceColor(_currentTranslation!.confidence),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _currentTranslation!.confidence.name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    _currentTranslation!.command,
                    style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_currentTranslation!.isValid)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _selectCommand(_currentTranslation!),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Execute Command'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Explanation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[400]),
                    const SizedBox(width: 8),
                    const Text(
                      'Explanation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currentTranslation!.explanation,
                  style: const TextStyle(color: Colors.grey[300]),
                ),
              ],
            ),
          ),
          
          // Warnings
          if (_currentTranslation!.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[400]),
                      const SizedBox(width: 8),
                      const Text(
                        'Warnings',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._currentTranslation!.warnings.map((warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Colors.orange)),
                        Expanded(
                          child: Text(
                            warning,
                            style: const TextStyle(color: Colors.orange[300]),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
          
          // Alternatives
          if (_currentTranslation!.alternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.alt_route, color: Colors.purple[400]),
                      const SizedBox(width: 8),
                      const Text(
                        'Alternative Commands',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._currentTranslation!.alternatives.map((alternative) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Colors.purple)),
                        Expanded(
                          child: Text(
                            alternative,
                            style: const TextStyle(color: Colors.purple[300]),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
          
          // Related suggestions
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.yellow[400]),
                      const SizedBox(width: 8),
                      const Text(
                        'Related Commands',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions.map((suggestion) => ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _inputController.text = suggestion;
                        _translate();
                      },
                      backgroundColor: Colors.grey[700],
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.blue[400]),
              const SizedBox(width: 8),
              const Text(
                'Command History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showHistory = false),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Close'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[400],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_history.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.history, color: Colors.grey[400], size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'No command history yet',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          else
            ..._history.asMap().entries.map((entry) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text(
                    '${entry.key + 1}.',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _inputController.text = entry.value;
                      setState(() => _showHistory = false);
                      _translate();
                    },
                    icon: const Icon(Icons.play_arrow, size: 16),
                    color: Colors.green[400],
                    tooltip: 'Use this command',
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Color _getConfidenceColor(ConfidenceLevel confidence) {
    switch (confidence) {
      case ConfidenceLevel.high:
        return Colors.green[700]!;
      case ConfidenceLevel.medium:
        return Colors.orange[700]!;
      case ConfidenceLevel.low:
        return Colors.red[700]!;
    }
  }
}
