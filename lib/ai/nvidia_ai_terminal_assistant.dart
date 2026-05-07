import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/nvidia_ai_client.dart';
import '../core/integrated_plugin_system.dart';

/// NVIDIA AI Terminal Assistant for Termisol.
///
/// Provides intelligent terminal assistance using NVIDIA's DeepSeek-V4-Pro model:
/// - Command prediction and completion with inline ghost text
/// - Command explanation and optimization
/// - Error analysis and suggestions
/// - Natural language command translation (/ai command)
/// - Context-aware assistance
/// - Plugin generation for custom functionality
///
/// Uses only NVIDIA NIM endpoint with DeepSeek-V4-Pro model for best-in-class performance.
class NvidiaAITerminalAssistant {
  final NvidiaAIClient _aiClient;

  // Context tracking
  final List<String> _commandHistory = [];
  final List<CommandContext> _contextHistory = [];
  String _currentDirectory = '';
  String _currentShell = '';
  String _lastCommand = '';
  String _lastError = '';

  // Command patterns and suggestions
  final Map<String, CommandSuggestion> _commandCache = {};
  final Map<String, String> _errorSolutions = {};

  // Plugin generation cache
  final Map<String, GeneratedPlugin> _pluginCache = {};

  // Performance tracking
  final Stopwatch _inferenceTimer = Stopwatch();
  final List<double> _inferenceTimes = [];
  double _avgInferenceTime = 0.0;

  final StreamController<AIAssistantEvent> _eventController =
      StreamController<AIAssistantEvent>.broadcast();

  bool _isInitialized = false;
  bool _isEnabled = true;

  Stream<AIAssistantEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  double get avgInferenceTime => _avgInferenceTime;
  bool get hasApiKeys => _aiClient.isInitialized;

  NvidiaAITerminalAssistant(this._aiClient);

  /// Initialize the assistant and its underlying AI client.
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('[AI] Initializing NVIDIA AI Terminal Assistant...');

    await _aiClient.initialize();
    await _initializeCommandPatterns();
    await _initializeErrorSolutions();

    _aiClient.events.listen(_handleAIEvent);

    _isInitialized = true;
    _eventController.add(AIAssistantEvent(
      type: AIAssistantEventType.initialized,
      message: 'NVIDIA AI Terminal Assistant initialized',
      data: {'models': _aiClient.availableModels},
    ));

    debugPrint('[AI] Assistant initialized');
  }

  /// Initialize command patterns for fast rule-based fallback.
  Future<void> _initializeCommandPatterns() async {
    final patterns = {
      'git': CommandSuggestion(
        command: 'git',
        description: 'Version control system',
        commonSubcommands: [
          'status',
          'log',
          'add',
          'commit',
          'push',
          'pull',
          'branch',
          'checkout',
        ],
        examples: [
          'git status',
          'git log --oneline -10',
          'git add .',
          'git commit -m "message"',
          'git push origin main',
        ],
      ),
      'docker': CommandSuggestion(
        command: 'docker',
        description: 'Container platform',
        commonSubcommands: ['run', 'build', 'push', 'ps', 'exec', 'logs', 'rm'],
        examples: [
          'docker run -it ubuntu bash',
          'docker build -t myapp .',
          'docker ps -a',
          'docker exec -it container_id bash',
        ],
      ),
      'kubectl': CommandSuggestion(
        command: 'kubectl',
        description: 'Kubernetes CLI',
        commonSubcommands: ['get', 'apply', 'delete', 'create', 'logs', 'exec'],
        examples: [
          'kubectl get pods',
          'kubectl apply -f deployment.yaml',
          'kubectl logs pod_name',
          'kubectl exec -it pod_name -- bash',
        ],
      ),
      'flutter': CommandSuggestion(
        command: 'flutter',
        description: 'Flutter development framework',
        commonSubcommands: ['run', 'build', 'test', 'pub get', 'clean'],
        examples: [
          'flutter run',
          'flutter build apk',
          'flutter test',
          'flutter pub get',
        ],
      ),
      'npm': CommandSuggestion(
        command: 'npm',
        description: 'Node.js package manager',
        commonSubcommands: ['install', 'run', 'test', 'build', 'publish'],
        examples: [
          'npm install',
          'npm run dev',
          'npm test',
          'npm run build',
        ],
      ),
    };

    _commandCache.addAll(patterns);
  }

  /// Initialize common error solutions for fast fallback.
  Future<void> _initializeErrorSolutions() async {
    final solutions = {
      'permission denied':
          'Try using sudo or check file permissions with ls -l',
      'command not found':
          'Install the command or verify it is in your PATH',
      'inaccessible or not found': 'doesn\'t exist',
      'no such file': 'Check the file path and current directory',
      'connection refused': 'Check if the service is running',
      'address already in use': 'Use a different port or stop the conflicting process',
      'disk space': 'Free up disk space or use a different location',
      'memory': 'Close other applications or increase swap',
      'network': 'Check internet connection and DNS settings',
    };

    _errorSolutions.addAll(solutions);
  }

  /// Handle events from the underlying AI client.
  void _handleAIEvent(AIEvent event) {
    switch (event.type) {
      case AIEventType.response:
        _inferenceTimer.stop();
        final responseTime = _inferenceTimer.elapsedMilliseconds.toDouble();
        _inferenceTimes.add(responseTime);

        if (_inferenceTimes.length > 100) {
          _inferenceTimes.removeAt(0);
        }

        _avgInferenceTime =
            _inferenceTimes.reduce((a, b) => a + b) / _inferenceTimes.length;

        _eventController.add(AIAssistantEvent(
          type: AIAssistantEventType.inferenceCompleted,
          message: 'AI inference completed',
          data: {
            'response_time': responseTime,
            'avg_time': _avgInferenceTime,
          },
        ));
        break;

      case AIEventType.error:
        _eventController.add(AIAssistantEvent(
          type: AIAssistantEventType.error,
          message: 'AI error: ${event.message}',
          data: event.data,
        ));
        break;

      case AIEventType.rateLimit:
        _eventController.add(AIAssistantEvent(
          type: AIAssistantEventType.rateLimit,
          message: 'AI rate limit reached',
          data: event.data,
        ));
        break;

      default:
        break;
    }
  }

  /// Predict the next command based on partial input and context.
  ///
  /// Returns a list of predictions ordered by confidence. If the AI client
  /// is available, it uses the model; otherwise falls back to rule-based
  /// pattern matching.
  Future<List<CommandPrediction>> predictCommand(String partialCommand) async {
    if (!_isInitialized || !_isEnabled) return [];
    if (partialCommand.trim().isEmpty) return [];

    // Check cache first
    final cacheKey = partialCommand.toLowerCase().trim();
    if (_commandCache.containsKey(cacheKey)) {
      final suggestion = _commandCache[cacheKey]!;
      return [
        CommandPrediction(
          command: suggestion.command,
          confidence: 0.9,
          description: suggestion.description,
          examples: suggestion.examples,
        ),
      ];
    }

    // If no API keys, use rule-based fallback
    if (!_aiClient.isInitialized) {
      return _ruleBasedPredict(partialCommand);
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a terminal command prediction expert. Based on the partial command and context, predict the most likely complete command.

Respond ONLY with a JSON object in this exact format:
{"command": "predicted_command", "confidence": 0.95, "description": "Brief description", "examples": ["example1", "example2"]}''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell
- Recent commands: ${_commandHistory.take(5).join(', ')}

Partial command: $partialCommand

Predict the complete command:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1000,
        temperature: 0.3,
        requiresMultimodal: false,
      );

      final content = response.content.trim();

      // Try to extract JSON from the response
      final prediction = _parsePredictionJson(content, partialCommand);

      // Cache the result
      _commandCache[cacheKey] = CommandSuggestion(
        command: prediction.command,
        description: prediction.description,
        commonSubcommands: [],
        examples: prediction.examples,
      );

      return [prediction];
    } catch (e) {
      debugPrint('[AI] Command prediction failed: $e');
      return _ruleBasedPredict(partialCommand);
    }
  }

  /// Parse a JSON prediction from the AI response.
  CommandPrediction _parsePredictionJson(String content, String fallback) {
    try {
      // Find JSON block if wrapped in markdown
      String jsonStr = content;
      final codeBlock = RegExp(r'```json\s*([\s\S]*?)\s*```');
      final match = codeBlock.firstMatch(content);
      if (match != null) {
        jsonStr = match.group(1)!;
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CommandPrediction(
        command: json['command']?.toString() ?? fallback,
        confidence: (json['confidence'] ?? 0.7).toDouble(),
        description: json['description']?.toString() ?? 'AI predicted command',
        examples: (json['examples'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
    } catch (e) {
      debugPrint('[AI] Failed to parse prediction JSON: $e');
      // Fallback: use first non-empty line as command
      final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final cmd = lines.isNotEmpty ? lines.first : fallback;
      return CommandPrediction(
        command: cmd,
        confidence: 0.5,
        description: 'AI predicted command',
        examples: [],
      );
    }
  }

  /// Rule-based prediction when AI is unavailable.
  List<CommandPrediction> _ruleBasedPredict(String partial) {
    final lower = partial.toLowerCase().trim();
    final results = <CommandPrediction>[];

    for (final entry in _commandCache.entries) {
      if (entry.key.startsWith(lower) || lower.startsWith(entry.key)) {
        results.add(CommandPrediction(
          command: entry.value.command,
          confidence: 0.8,
          description: entry.value.description,
          examples: entry.value.examples,
        ));
      }
    }

    if (results.isEmpty) {
      results.add(CommandPrediction(
        command: partial,
        confidence: 0.3,
        description: 'No prediction available',
        examples: [],
      ));
    }

    return results;
  }

  /// Explain what a command does.
  Future<String> explainCommand(String command) async {
    if (!_isInitialized || !_isEnabled) return 'AI assistant not available';
    if (command.trim().isEmpty) return '';

    // Check cache
    if (_commandCache.containsKey(command.toLowerCase().trim())) {
      final suggestion = _commandCache[command.toLowerCase().trim()]!;
      return '${suggestion.description}\n\nExamples:\n${suggestion.examples.map((e) => '  $e').join('\n')}';
    }

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured). Add NVIDIA_API_KEY_1 through NVIDIA_API_KEY_24 to your .env file.';
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a terminal command expert. Explain what this command does in a clear, concise way. Include:
1. What the command does
2. Common use cases
3. Important flags or options
4. Safety considerations if relevant''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell

Explain this command: $command''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1000,
        temperature: 0.5,
        requiresMultimodal: false,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Command explanation failed: $e');
      return 'Failed to explain command: $e';
    }
  }

  /// Suggest optimizations for a command.
  Future<String> optimizeCommand(String command) async {
    if (!_isInitialized || !_isEnabled) return 'AI assistant not available';
    if (command.trim().isEmpty) return '';

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured).';
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a terminal optimization expert. Analyze this command and suggest improvements for performance, safety, and best practices.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell
- Recent commands: ${_commandHistory.take(3).join(', ')}

Optimize this command: $command''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 800,
        temperature: 0.4,
        requiresMultimodal: false,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Command optimization failed: $e');
      return 'Failed to optimize command: $e';
    }
  }

  /// Analyze an error and suggest solutions.
  Future<String> analyzeError(String error) async {
    if (!_isInitialized || !_isEnabled) return 'AI assistant not available';
    if (error.trim().isEmpty) return '';

    // Check common error solutions first
    for (final pattern in _errorSolutions.keys) {
      if (error.toLowerCase().contains(pattern)) {
        return _errorSolutions[pattern]!;
      }
    }

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured).';
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a terminal troubleshooting expert. Analyze this error and provide:
1. What the error means
2. Common causes
3. Step-by-step solutions
4. Prevention tips''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell
- Recent commands: ${_commandHistory.take(3).join(', ')}
- Last command: $_lastCommand

Analyze this error: $error''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1000,
        temperature: 0.3,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Error analysis failed: $e');
      return 'Failed to analyze error: $e';
    }
  }

  /// Translate natural language to a terminal command.
  Future<String> translateToCommand(String naturalLanguage) async {
    if (!_isInitialized || !_isEnabled) return 'AI assistant not available';
    if (naturalLanguage.trim().isEmpty) return '';

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured).';
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a natural language to terminal command translator. Convert the user's request into a valid terminal command. Respond with ONLY the command, no explanation, no markdown.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell
- Available tools: git, docker, kubectl, flutter, npm, etc.

Request: $naturalLanguage

Command:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 200,
        temperature: 0.2,
        requiresMultimodal: false,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Command translation failed: $e');
      return 'Failed to translate: $e';
    }
  }

  /// Process a raw /ai query from the terminal.
  ///
  /// This is the main entry point for the `/ai` command. The user types
  /// `/ai any query here` and this sends the query to the AI and returns
  /// the response.
  Future<String> processAiQuery(String query) async {
    if (!_isInitialized || !_isEnabled) {
      return 'AI assistant not available. Check that NVIDIA_API_KEY_1 through NVIDIA_API_KEY_24 are configured in your .env file.';
    }
    if (query.trim().isEmpty) {
      return 'Please provide a query after /ai. Example: /ai how do I find all .log files modified today?';
    }

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured). Add NVIDIA_API_KEY_1 through NVIDIA_API_KEY_24 to your .env file.';
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are an expert terminal assistant. Help the user with their query. Be concise but thorough. If they ask for a command, provide it. If they ask for explanation, explain clearly.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Context:
- Current directory: $_currentDirectory
- Shell: $_currentShell
- Recent commands: ${_commandHistory.take(10).join('\n')}

Query: $query''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 2048,
        temperature: 0.7,
        requiresMultimodal: false,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Query processing failed: $e');
      return 'AI query failed: $e';
    }
  }

  /// Provide real-time code suggestions as user types.
  Future<List<CodeSuggestion>> getCodeSuggestions(String codeSnippet, String language, {String? context}) async {
    if (!_isInitialized || !_isEnabled) return [];
    if (codeSnippet.trim().isEmpty) return [];

    if (!_aiClient.isInitialized) {
      return [];
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a code completion expert. Provide intelligent code suggestions based on the partial code snippet. Return ONLY a JSON array of suggestions in this exact format:

[{"text": "completion_text", "description": "Brief description", "confidence": 0.95, "type": "function|variable|keyword|class"}]

Keep suggestions concise and relevant. Focus on the most likely completions.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Language: $language
Context: ${context ?? 'General coding'}
Partial code: $codeSnippet

Provide 3-5 most likely completions:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1000,
        temperature: 0.4,
        requiresMultimodal: false,
      );

      final content = response.content.trim();
      return _parseCodeSuggestions(content);
    } catch (e) {
      debugPrint('[AI] Code suggestions failed: $e');
      return [];
    }
  }

  /// Analyze code for potential bugs and issues.
  Future<List<CodeIssue>> analyzeCodeForBugs(String code, String language, {String? context}) async {
    if (!_isInitialized || !_isEnabled) return [];
    if (code.trim().isEmpty) return [];

    if (!_aiClient.isInitialized) {
      return [];
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a code analysis expert. Analyze the provided code for bugs, potential issues, and improvements. Return ONLY a JSON array of issues in this exact format:

[{"type": "error|warning|info", "line": 1, "column": 0, "message": "Issue description", "suggestion": "How to fix", "severity": "high|medium|low"}]

Be thorough but focus on real issues, not style preferences.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Language: $language
Context: ${context ?? 'General coding'}
Code to analyze:
$code

Identify bugs and issues:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1500,
        temperature: 0.3,
        requiresMultimodal: false,
      );

      final content = response.content.trim();
      return _parseCodeIssues(content);
    } catch (e) {
      debugPrint('[AI] Code analysis failed: $e');
      return [];
    }
  }

  /// Generate automatic fixes for code issues.
  Future<List<CodeFix>> generateCodeFixes(String code, List<CodeIssue> issues, String language) async {
    if (!_isInitialized || !_isEnabled) return [];
    if (issues.isEmpty) return [];

    if (!_aiClient.isInitialized) {
      return [];
    }

    try {
      _inferenceTimer.start();

      final issuesJson = jsonEncode(issues.map((i) => {
        'type': i.type,
        'line': i.line,
        'message': i.message,
        'severity': i.severity,
      }).toList());

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a code fix expert. Generate specific fixes for the identified code issues. Return ONLY a JSON array of fixes in this exact format:

[{"issueIndex": 0, "description": "Fix description", "originalCode": "original_code", "fixedCode": "fixed_code", "confidence": 0.9}]

Each fix should include the exact original code to replace and the corrected code.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Language: $language
Original code:
$code

Issues to fix:
$issuesJson

Generate fixes:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 2000,
        temperature: 0.2,
        requiresMultimodal: false,
      );

      final content = response.content.trim();
      return _parseCodeFixes(content);
    } catch (e) {
      debugPrint('[AI] Code fixes failed: $e');
      return [];
    }
  }

  /// Provide intelligent command autofill suggestions.
  Future<List<CommandAutofill>> getCommandAutofill(String partialCommand, String shell) async {
    if (!_isInitialized || !_isEnabled) return [];
    if (partialCommand.trim().isEmpty) return [];

    if (!_aiClient.isInitialized) {
      return _ruleBasedAutofill(partialCommand, shell);
    }

    try {
      _inferenceTimer.start();

      final messages = [
        ChatMessage(
          role: 'system',
          content: '''You are a shell command expert. Provide intelligent command completion suggestions. Return ONLY a JSON array in this exact format:

[{"command": "completed_command", "description": "What it does", "confidence": 0.95, "category": "file|process|network|system"}]

Focus on common and useful completions.''',
        ),
        ChatMessage(
          role: 'user',
          content: '''Shell: $shell
Current directory: $_currentDirectory
Recent commands: ${_commandHistory.take(5).join(', ')}
Partial command: $partialCommand

Provide completions:''',
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 1000,
        temperature: 0.3,
      );

      final content = response.content.trim();
      return _parseCommandAutofill(content);
    } catch (e) {
      debugPrint('[AI] Command autofill failed: $e');
      return _ruleBasedAutofill(partialCommand, shell);
    }
  }

  /// Parse code suggestions from AI response.
  List<CodeSuggestion> _parseCodeSuggestions(String content) {
    try {
      String jsonStr = content;
      final codeBlock = RegExp(r'```json\s*([\s\S]*?)\s*```');
      final match = codeBlock.firstMatch(content);
      if (match != null) {
        jsonStr = match.group(1)!;
      }

      final list = jsonDecode(jsonStr) as List;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return CodeSuggestion(
          text: map['text']?.toString() ?? '',
          description: map['description']?.toString() ?? '',
          confidence: (map['confidence'] ?? 0.5).toDouble(),
          type: map['type']?.toString() ?? 'unknown',
        );
      }).toList();
    } catch (e) {
      debugPrint('[AI] Failed to parse code suggestions: $e');
      return [];
    }
  }

  /// Parse code issues from AI response.
  List<CodeIssue> _parseCodeIssues(String content) {
    try {
      String jsonStr = content;
      final codeBlock = RegExp(r'```json\s*([\s\S]*?)\s*```');
      final match = codeBlock.firstMatch(content);
      if (match != null) {
        jsonStr = match.group(1)!;
      }

      final list = jsonDecode(jsonStr) as List;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return CodeIssue(
          type: map['type']?.toString() ?? 'info',
          line: map['line'] ?? 1,
          column: map['column'] ?? 0,
          message: map['message']?.toString() ?? '',
          suggestion: map['suggestion']?.toString() ?? '',
          severity: map['severity']?.toString() ?? 'medium',
        );
      }).toList();
    } catch (e) {
      debugPrint('[AI] Failed to parse code issues: $e');
      return [];
    }
  }

  /// Parse code fixes from AI response.
  List<CodeFix> _parseCodeFixes(String content) {
    try {
      String jsonStr = content;
      final codeBlock = RegExp(r'```json\s*([\s\S]*?)\s*```');
      final match = codeBlock.firstMatch(content);
      if (match != null) {
        jsonStr = match.group(1)!;
      }

      final list = jsonDecode(jsonStr) as List;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return CodeFix(
          issueIndex: map['issueIndex'] ?? 0,
          description: map['description']?.toString() ?? '',
          originalCode: map['originalCode']?.toString() ?? '',
          fixedCode: map['fixedCode']?.toString() ?? '',
          confidence: (map['confidence'] ?? 0.5).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[AI] Failed to parse code fixes: $e');
      return [];
    }
  }

  /// Parse command autofill from AI response.
  List<CommandAutofill> _parseCommandAutofill(String content) {
    try {
      String jsonStr = content;
      final codeBlock = RegExp(r'```json\s*([\s\S]*?)\s*```');
      final match = codeBlock.firstMatch(content);
      if (match != null) {
        jsonStr = match.group(1)!;
      }

      final list = jsonDecode(jsonStr) as List;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return CommandAutofill(
          command: map['command']?.toString() ?? '',
          description: map['description']?.toString() ?? '',
          confidence: (map['confidence'] ?? 0.5).toDouble(),
          category: map['category']?.toString() ?? 'general',
        );
      }).toList();
    } catch (e) {
      debugPrint('[AI] Failed to parse command autofill: $e');
      return [];
    }
  }

  /// Rule-based command autofill fallback.
  List<CommandAutofill> _ruleBasedAutofill(String partial, String shell) {
    final lower = partial.toLowerCase().trim();
    final results = <CommandAutofill>[];

    // Common command completions
    final completions = {
      'ls': ['ls -la', 'ls -lh', 'ls -ltr'],
      'cd': ['cd ..', 'cd ~', 'cd /'],
      'git': ['git status', 'git log', 'git add', 'git commit', 'git push'],
      'docker': ['docker ps', 'docker run', 'docker build', 'docker logs'],
      'npm': ['npm install', 'npm run', 'npm test', 'npm build'],
      'ps': ['ps aux', 'ps -ef'],
      'grep': ['grep -r', 'grep -i'],
      'find': ['find . -name', 'find . -type f'],
    };

    for (final entry in completions.entries) {
      if (entry.key.startsWith(lower) || lower.startsWith(entry.key)) {
        for (final cmd in entry.value) {
          results.add(CommandAutofill(
            command: cmd,
            description: 'Common ${entry.key} command',
            confidence: 0.8,
            category: 'system',
          ));
        }
      }
    }

    return results.take(5).toList();
  }

  /// Summarize terminal output using AI (auto-selects multimodal model if needed).
  Future<String> summarizeText(String text) async {
    if (!_isInitialized || !_isEnabled) return 'AI assistant not available';
    if (text.trim().isEmpty) return '';

    if (!_aiClient.isInitialized) {
      return 'AI assistant unavailable (no API keys configured). Add NVIDIA_API_KEY_1 through NVIDIA_API_KEY_24 to your .env file.';
    }

    try {
      _inferenceTimer.start();

      // Check if content might benefit from multimodal model (contains image/video references)
      final requiresMultimodal = _containsImageReferences(text);

      final messages = [
        ChatMessage(
          role: 'system',
          content: 'Summarize the following terminal output concisely. Focus on key information, errors, and outcomes.',
        ),
        ChatMessage(
          role: 'user',
          content: text,
        ),
      ];

      final response = await _aiClient.chatCompletion(
        messages: messages,
        maxTokens: 500,
        temperature: 0.3,
        requiresMultimodal: requiresMultimodal,
      );

      return response.content.trim();
    } catch (e) {
      debugPrint('[AI] Summary failed: $e');
      return 'Failed to summarize: $e';
    }
  }

  /// Check if text contains references to images/videos that would benefit from multimodal AI.
  bool _containsImageReferences(String text) {
    final lowerText = text.toLowerCase();
    final imageKeywords = [
      'image', 'photo', 'picture', 'img', 'jpg', 'png', 'gif', 'webp',
      'video', 'movie', 'mp4', 'avi', 'mov', 'webm', 'display', 'show',
      'render', 'view', 'preview', 'screenshot', 'capture'
    ];

    return imageKeywords.any((keyword) => lowerText.contains(keyword));
  }

  /// Check if the given output looks like an error and auto-suggest a fix.
  bool looksLikeError(String output) {
    final lower = output.toLowerCase();
    final errorPatterns = [
      'error',
      'failed',
      'fatal',
      'exception',
      'permission denied',
      'command not found',
      'inaccessible or not found',
      'no such file',
      'connection refused',
      'address already in use',
      'syntax error',
      'segmentation fault',
      'core dumped',
    ];
    return errorPatterns.any((pattern) => lower.contains(pattern));
  }

  /// Update the assistant's context based on terminal activity.
  void updateContext({
    String? currentDirectory,
    String? currentShell,
    String? lastCommand,
    String? lastOutput,
  }) {
    if (currentDirectory != null) _currentDirectory = currentDirectory;
    if (currentShell != null) _currentShell = currentShell;
    if (lastCommand != null) {
      _lastCommand = lastCommand;
      _commandHistory.insert(0, lastCommand);
      if (_commandHistory.length > 100) {
        _commandHistory.removeLast();
      }
    }
    if (lastOutput != null && looksLikeError(lastOutput)) {
      _lastError = lastOutput;
      _eventController.add(AIAssistantEvent(
        type: AIAssistantEventType.errorDetected,
        message: 'Error detected in terminal output',
        data: {'error': lastOutput},
      ));
    }
  }

  /// Enable or disable the AI assistant.
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _eventController.add(AIAssistantEvent(
      type: AIAssistantEventType.statusChanged,
      message: enabled ? 'AI assistant enabled' : 'AI assistant disabled',
      data: {'enabled': enabled},
    ));
  }

  /// Get performance metrics.
  Map<String, dynamic> getMetrics() {
    return {
      'is_initialized': _isInitialized,
      'is_enabled': _isEnabled,
      'avg_inference_time': _avgInferenceTime,
      'command_history_count': _commandHistory.length,
      'cached_patterns': _commandCache.length,
      'error_solutions': _errorSolutions.length,
      'inference_count': _inferenceTimes.length,
    };
  }

  /// Dispose the assistant and release resources.
  Future<void> dispose() async {
    await _eventController.close();
    _isInitialized = false;
    debugPrint('[AI] Assistant disposed');
  }

  /// Generate custom plugin using DeepSeek-V4-Pro
  Future<GeneratedPlugin> generatePlugin(String pluginDescription) async {
    if (!_aiClient.isInitialized) {
      throw Exception('AI client not initialized');
    }

    _inferenceTimer.start();

    try {
      final prompt = '''
You are an expert Flutter/Dart plugin developer for the Termisol terminal emulator.

Generate a flawless plugin for this request: "$pluginDescription"

Requirements:
1. Create a complete, working plugin that extends TerminalPlugin
2. Follow Flutter/Dart best practices
3. Include proper error handling
4. Add comprehensive documentation
5. Make it production-ready with no bugs
6. Ensure it integrates seamlessly with Termisol's architecture
7. Use the existing patterns and conventions found in the codebase

Plugin structure should include:
- Plugin class extending TerminalPlugin
- Proper initialization and disposal
- Event handling
- Configuration options
- Integration with terminal backend

Respond with only the complete Dart code for the plugin, no explanations.
''';

      final response = await _aiClient.generateResponse(
        prompt: prompt,
        model: 'deepseek-v4-pro',
        temperature: 0.1, // Low temperature for consistent code
        maxTokens: 4000,
      );

      _inferenceTimer.stop();
      _updateInferenceTimeStats();

      final plugin = GeneratedPlugin(
        name: _extractPluginName(pluginDescription),
        description: pluginDescription,
        code: response,
        timestamp: DateTime.now(),
        model: 'deepseek-v4-pro',
      );

      _pluginCache[pluginDescription] = plugin;

      _eventController.add(AIAssistantEvent(
        type: AIAssistantEventType.pluginGenerated,
        message: 'Plugin generated: ${plugin.name}',
        data: {'plugin': plugin.toJson()},
      ));

      debugPrint('[AI] Generated plugin: ${plugin.name}');
      return plugin;

    } catch (e) {
      _inferenceTimer.stop();
      debugPrint('[AI] Plugin generation failed: $e');
      rethrow;
    }
  }

  /// Extract plugin name from description
  String _extractPluginName(String description) {
    final words = description.toLowerCase().split(' ');
    final relevantWords = words.where((word) => 
        word.length > 3 && !['that', 'with', 'for', 'from', 'have'].contains(word)
    ).take(3);
    
    return relevantWords.map((word) => 
        word[0].toUpperCase() + word.substring(1)
    ).join() + 'Plugin';
  }

  /// Get cached plugin or generate new one
  Future<GeneratedPlugin> getOrGeneratePlugin(String description) async {
    if (_pluginCache.containsKey(description)) {
      return _pluginCache[description]!;
    }
    return await generatePlugin(description);
  }

  /// List all generated plugins
  List<GeneratedPlugin> getGeneratedPlugins() {
    return _pluginCache.values.toList();
  }

  /// Clear plugin cache
  void clearPluginCache() {
    _pluginCache.clear();
  }
}

/// Command suggestion with metadata.
class CommandSuggestion {
  final String command;
  final String description;
  final List<String> commonSubcommands;
  final List<String> examples;

  CommandSuggestion({
    required this.command,
    required this.description,
    required this.commonSubcommands,
    required this.examples,
  });
}

/// A single command prediction result.
class CommandPrediction {
  final String command;
  final double confidence;
  final String description;
  final List<String> examples;

  CommandPrediction({
    required this.command,
    required this.confidence,
    required this.description,
    required this.examples,
  });
}

/// Context of a previously executed command.
class CommandContext {
  final String command;
  final String directory;
  final DateTime timestamp;
  final bool success;

  CommandContext({
    required this.command,
    required this.directory,
    required this.timestamp,
    required this.success,
  });
}

/// Event types for the AI assistant.
enum AIAssistantEventType {
  initialized,
  inferenceCompleted,
  error,
  rateLimit,
  statusChanged,
  errorDetected,
}

/// Event emitted by the AI assistant.
class AIAssistantEvent {
  final AIAssistantEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  AIAssistantEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}

/// Code suggestion for real-time completion.
class CodeSuggestion {
  final String text;
  final String description;
  final double confidence;
  final String type; // function, variable, keyword, class, etc.

  CodeSuggestion({
    required this.text,
    required this.description,
    required this.confidence,
    required this.type,
  });
}

/// Code issue identified during analysis.
class CodeIssue {
  final String type; // error, warning, info
  final int line;
  final int column;
  final String message;
  final String suggestion;
  final String severity; // high, medium, low

  CodeIssue({
    required this.type,
    required this.line,
    required this.column,
    required this.message,
    required this.suggestion,
    required this.severity,
  });
}

/// Automatic code fix suggestion.
class CodeFix {
  final int issueIndex;
  final String description;
  final String originalCode;
  final String fixedCode;
  final double confidence;

  CodeFix({
    required this.issueIndex,
    required this.description,
    required this.originalCode,
    required this.fixedCode,
    required this.confidence,
  });
}

/// Command autofill suggestion.
class CommandAutofill {
  final String command;
  final String description;
  final double confidence;
  final String category; // file, process, network, system, etc.

  CommandAutofill({
    required this.command,
    required this.description,
    required this.confidence,
    required this.category,
  });
}
