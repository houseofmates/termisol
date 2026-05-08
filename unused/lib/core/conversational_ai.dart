import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../ai/ai_terminal_assistant.dart';
import 'terminal_session.dart';
import 'smart_command_chaining.dart';
import 'semantic_search_engine.dart';
import 'enhanced_ai_suggestions.dart';

/// Conversational AI Interface
///
/// Provides natural language interaction with the terminal,
/// understanding complex requests and executing multi-step tasks.
class ConversationalAI {
  final AITerminalAssistant _aiAssistant;
  final SmartCommandChaining _commandChaining;
  final SemanticSearchEngine _searchEngine;
  final EnhancedAISuggestions _suggestions;

  final StreamController<ConversationMessage> _conversationController =
      StreamController<ConversationMessage>.broadcast();

  Stream<ConversationMessage> get conversation => _conversationController.stream;

  final List<ConversationMessage> _messageHistory = [];
  final Map<String, ConversationContext> _contexts = {};
  final Map<String, LearnedConversationIntent> _learnedIntents = {};

  bool _isActive = false;
  bool get isActive => _isActive;

  String? _currentSessionId;
  ConversationContext? _currentContext;

  ConversationalAI(
    this._aiAssistant,
    this._commandChaining,
    this._searchEngine,
    this._suggestions,
  );

  /// Initialize conversational AI
  Future<void> initialize() async {
    if (_isActive) return;

    await Future.wait([
      _aiAssistant.initialize(),
      _commandChaining.initialize(),
      _searchEngine.initialize(),
      _suggestions.initialize(),
    ]);

    _isActive = true;
    debugPrint('💬 Conversational AI initialized');
  }

  /// Start a new conversation session
  String startConversation({String? initialContext}) {
    _currentSessionId = 'conv_${DateTime.now().millisecondsSinceEpoch}';
    _currentContext = ConversationContext(
      sessionId: _currentSessionId!,
      startTime: DateTime.now(),
      initialContext: initialContext,
    );

    _contexts[_currentSessionId!] = _currentContext!;

    // Send welcome message
    final welcomeMessage = ConversationMessage(
      type: MessageType.ai,
      content: 'Hello! I\'m your AI terminal assistant. How can I help you today?',
      timestamp: DateTime.now(),
      sessionId: _currentSessionId!,
    );

    _addMessage(welcomeMessage);
    _conversationController.add(welcomeMessage);

    return _currentSessionId!;
  }

  /// Process natural language input
  Future<ConversationResponse> processInput(String input, {
    String? sessionId,
    String? currentDirectory,
    String? projectType,
  }) async {
    if (!_isActive) {
      throw Exception('Conversational AI not initialized');
    }

    final activeSessionId = sessionId ?? _currentSessionId;
    if (activeSessionId == null) {
      throw Exception('No active conversation session');
    }

    // Add user message to history
    final userMessage = ConversationMessage(
      type: MessageType.user,
      content: input,
      timestamp: DateTime.now(),
      sessionId: activeSessionId,
    );
    _addMessage(userMessage);

    try {
      // Analyze input intent
      final intent = await _analyzeIntent(input);

      // Generate response based on intent
      final response = await _generateResponse(
        input,
        intent,
        currentDirectory: currentDirectory,
        projectType: projectType,
      );

      // Add AI response to history
      final aiMessage = ConversationMessage(
        type: MessageType.ai,
        content: response.content,
        timestamp: DateTime.now(),
        sessionId: activeSessionId,
        metadata: response.metadata,
      );
      _addMessage(aiMessage);

      // Send to conversation stream
      _conversationController.add(aiMessage);

      return response;

    } catch (e) {
      debugPrint('❌ Conversational AI error: $e');

      final errorMessage = ConversationMessage(
        type: MessageType.ai,
        content: 'I\'m sorry, I encountered an error processing your request. Please try again.',
        timestamp: DateTime.now(),
        sessionId: activeSessionId,
        metadata: {'error': e.toString()},
      );

      _addMessage(errorMessage);
      _conversationController.add(errorMessage);

      return ConversationResponse(
        content: errorMessage.content,
        actions: [],
        metadata: {'error': true},
      );
    }
  }

  /// Analyze user input intent
  Future<ConversationIntent> _analyzeIntent(String input) async {
    final lowerInput = input.toLowerCase();

    // Check for learned intents first
    for (final learnedIntent in _learnedIntents.values) {
      if (learnedIntent.matches(input)) {
        return learnedIntent.intent;
      }
    }

    // Pattern-based intent detection
    if (_isQuestion(input)) {
      return ConversationIntent.question;
    }
    if (_isCommand(input)) {
      return ConversationIntent.command;
    }
    if (_isExplanationRequest(input)) {
      return ConversationIntent.explanation;
    }
    if (_isWorkflowRequest(input)) {
      return ConversationIntent.workflow;
    }
    if (_isSearchRequest(input)) {
      return ConversationIntent.search;
    }
    if (_isSetupRequest(input)) {
      return ConversationIntent.setup;
    }

    // Use AI for complex intent analysis
    try {
      final aiIntent = await _aiAssistant.processAiQuery(
        'Analyze this user input and determine the primary intent. '
        'Possible intents: question, command, explanation, workflow, search, setup, general. '
        'Input: "$input". Return only the intent type.'
      );

      switch (aiIntent.toLowerCase().trim()) {
        case 'question':
          return ConversationIntent.question;
        case 'command':
          return ConversationIntent.command;
        case 'explanation':
          return ConversationIntent.explanation;
        case 'workflow':
          return ConversationIntent.workflow;
        case 'search':
          return ConversationIntent.search;
        case 'setup':
          return ConversationIntent.setup;
        default:
          return ConversationIntent.general;
      }
    } catch (e) {
      return ConversationIntent.general;
    }
  }

  /// Check if input is a question
  bool _isQuestion(String input) {
    return input.contains('?') ||
           input.toLowerCase().startsWith('what') ||
           input.toLowerCase().startsWith('how') ||
           input.toLowerCase().startsWith('why') ||
           input.toLowerCase().startsWith('when') ||
           input.toLowerCase().startsWith('where') ||
           input.toLowerCase().startsWith('can you') ||
           input.toLowerCase().startsWith('do you');
  }

  /// Check if input is a direct command
  bool _isCommand(String input) {
    return input.contains('run') ||
           input.contains('execute') ||
           input.startsWith('git ') ||
           input.startsWith('npm ') ||
           input.startsWith('docker ') ||
           input.startsWith('cd ') ||
           input.startsWith('ls ') ||
           input.startsWith('mkdir ') ||
           input.startsWith('rm ');
  }

  /// Check if input is requesting explanation
  bool _isExplanationRequest(String input) {
    return input.toLowerCase().contains('explain') ||
           input.toLowerCase().contains('what does') ||
           input.toLowerCase().contains('what is') ||
           input.toLowerCase().contains('how does');
  }

  /// Check if input is requesting a workflow
  bool _isWorkflowRequest(String input) {
    return input.toLowerCase().contains('workflow') ||
           input.toLowerCase().contains('automate') ||
           input.toLowerCase().contains('sequence') ||
           input.toLowerCase().contains('chain') ||
           input.toLowerCase().contains('pipeline');
  }

  /// Check if input is a search request
  bool _isSearchRequest(String input) {
    return input.toLowerCase().contains('find') ||
           input.toLowerCase().contains('search') ||
           input.toLowerCase().contains('locate') ||
           input.toLowerCase().contains('grep');
  }

  /// Check if input is a setup request
  bool _isSetupRequest(String input) {
    return input.toLowerCase().contains('setup') ||
           input.toLowerCase().contains('install') ||
           input.toLowerCase().contains('configure') ||
           input.toLowerCase().contains('initialize');
  }

  /// Generate response based on intent
  Future<ConversationResponse> _generateResponse(
    String input,
    ConversationIntent intent, {
    String? currentDirectory,
    String? projectType,
  }) async {
    switch (intent) {
      case ConversationIntent.question:
        return await _handleQuestion(input, currentDirectory, projectType);

      case ConversationIntent.command:
        return await _handleCommand(input, currentDirectory, projectType);

      case ConversationIntent.explanation:
        return await _handleExplanation(input);

      case ConversationIntent.workflow:
        return await _handleWorkflow(input, currentDirectory, projectType);

      case ConversationIntent.search:
        return await _handleSearch(input, currentDirectory);

      case ConversationIntent.setup:
        return await _handleSetup(input, currentDirectory, projectType);

      case ConversationIntent.general:
      default:
        return await _handleGeneral(input, currentDirectory, projectType);
    }
  }

  /// Handle question intents
  Future<ConversationResponse> _handleQuestion(
    String input,
    String? currentDirectory,
    String? projectType,
  ) async {
    try {
      final answer = await _aiAssistant.processAiQuery(
        'Answer this question in the context of terminal/developer workflows: $input'
      );

      return ConversationResponse(
        content: answer,
        actions: [],
        metadata: {'intent': 'question'},
      );
    } catch (e) {
      return ConversationResponse(
        content: 'I\'m not sure about that. Let me help you find the information you need.',
        actions: [],
        metadata: {'error': true},
      );
    }
  }

  /// Handle command intents
  Future<ConversationResponse> _handleCommand(
    String input,
    String? currentDirectory,
    String? projectType,
  ) async {
    // Extract command from natural language
    final command = await _aiAssistant.translateToCommand(input);

    if (command.startsWith('#')) {
      return ConversationResponse(
        content: 'I couldn\'t translate that to a specific command. Could you be more specific?',
        actions: [],
        metadata: {'intent': 'command', 'translation_failed': true},
      );
    }

    final actions = [
      ConversationAction(
        type: ActionType.execute_command,
        data: command,
        description: 'Execute: $command',
      ),
    ];

    return ConversationResponse(
      content: 'I can run this command for you: `$command`. Would you like me to execute it?',
      actions: actions,
      metadata: {'intent': 'command', 'suggested_command': command},
    );
  }

  /// Handle explanation intents
  Future<ConversationResponse> _handleExplanation(String input) async {
    // Extract what to explain
    final toExplain = input.replaceAll(RegExp(r'explain\s+', caseSensitive: false), '')
                         .replaceAll(RegExp(r'what does\s+', caseSensitive: false), '')
                         .replaceAll(RegExp(r'what is\s+', caseSensitive: false), '')
                         .trim();

    final explanation = await _aiAssistant.explainCommand(toExplain);

    return ConversationResponse(
      content: explanation,
      actions: [],
      metadata: {'intent': 'explanation', 'explained': toExplain},
    );
  }

  /// Handle workflow intents
  Future<ConversationResponse> _handleWorkflow(
    String input,
    String? currentDirectory,
    String? projectType,
  ) async {
    // Parse workflow request
    final workflowDescription = input.toLowerCase();

    String workflowType = 'general';

    if (workflowDescription.contains('git') || workflowDescription.contains('commit')) {
      workflowType = 'git';
    } else if (workflowDescription.contains('deploy') || workflowDescription.contains('build')) {
      workflowType = 'deployment';
    } else if (workflowDescription.contains('test')) {
      workflowType = 'testing';
    }

    // Get available workflows
    final workflows = _commandChaining.getWorkflows();
    final matchingWorkflows = workflows.where((w) =>
      w.name.toLowerCase().contains(workflowType) ||
      workflowType == 'general'
    ).toList();

    if (matchingWorkflows.isNotEmpty) {
      final actions = matchingWorkflows.map((workflow) =>
        ConversationAction(
          type: ActionType.execute_workflow,
          data: workflow.name,
          description: 'Run workflow: ${workflow.name}',
        )
      ).toList();

      return ConversationResponse(
        content: 'I found these workflows that might help: ${matchingWorkflows.map((w) => w.name).join(', ')}',
        actions: actions,
        metadata: {'intent': 'workflow', 'workflow_type': workflowType},
      );
    }

    return ConversationResponse(
      content: 'I can help you create a workflow. What specific tasks would you like to automate?',
      actions: [
        ConversationAction(
          type: ActionType.create_workflow,
          data: input,
          description: 'Create custom workflow',
        ),
      ],
      metadata: {'intent': 'workflow', 'needs_creation': true},
    );
  }

  /// Handle search intents
  Future<ConversationResponse> _handleSearch(String input, String? currentDirectory) async {
    // Extract search query
    final query = input.replaceAll(RegExp(r'(find|search|locate|grep)\s+', caseSensitive: false), '').trim();

    try {
      final context = currentDirectory != null ? SearchContext(directory: currentDirectory) : null;
      final results = await _searchEngine.semanticSearch(query, context: context);

      if (results.results.isEmpty) {
        return ConversationResponse(
          content: 'I couldn\'t find any matches for "$query". Try a different search term.',
          actions: [],
          metadata: {'intent': 'search', 'results_count': 0},
        );
      }

      final topResults = results.results.take(3);
      final resultSummary = topResults.map((r) => '${r.path}:${r.lineNumber ?? 0}').join(', ');

      return ConversationResponse(
        content: 'I found ${results.totalResults} matches. Top results: $resultSummary',
        actions: [
          ConversationAction(
            type: ActionType.view_search_results,
            data: query,
            description: 'View all search results',
          ),
        ],
        metadata: {
          'intent': 'search',
          'results_count': results.totalResults,
          'top_results': topResults.map((r) => r.displayPath).toList(),
        },
      );
    } catch (e) {
      return ConversationResponse(
        content: 'Search failed. Please try a different query.',
        actions: [],
        metadata: {'intent': 'search', 'error': e.toString()},
      );
    }
  }

  /// Handle setup intents
  Future<ConversationResponse> _handleSetup(
    String input,
    String? currentDirectory,
    String? projectType,
  ) async {
    // Determine setup type
    final setupType = _determineSetupType(input, projectType);

    final setupSteps = await _generateSetupSteps(setupType, currentDirectory);

    if (setupSteps.isEmpty) {
      return ConversationResponse(
        content: 'I\'m not sure what kind of setup you need. Could you be more specific?',
        actions: [],
        metadata: {'intent': 'setup', 'setup_type': 'unknown'},
      );
    }

    final actions = setupSteps.map((step) =>
      ConversationAction(
        type: ActionType.execute_command,
        data: step.command,
        description: step.description,
      )
    ).toList();

    return ConversationResponse(
      content: 'Here\'s the setup process for $setupType:\n\n${setupSteps.map((s) => '• ${s.description}').join('\n')}',
      actions: actions,
      metadata: {
        'intent': 'setup',
        'setup_type': setupType,
        'steps_count': setupSteps.length,
      },
    );
  }

  /// Handle general intents
  Future<ConversationResponse> _handleGeneral(
    String input,
    String? currentDirectory,
    String? projectType,
  ) async {
    // Get suggestions for the input
    final suggestions = await _suggestions.getProactiveSuggestions(
      currentInput: input,
      currentDirectory: currentDirectory,
      projectType: projectType,
    );

    if (suggestions.isNotEmpty) {
      final topSuggestion = suggestions.first;
      final actions = [
        ConversationAction(
          type: ActionType.execute_command,
          data: topSuggestion.content,
          description: 'Try: ${topSuggestion.content}',
        ),
      ];

      return ConversationResponse(
        content: 'Based on your input, I suggest: `${topSuggestion.content}`\n\nReason: ${topSuggestion.reason}',
        actions: actions,
        metadata: {
          'intent': 'general',
          'suggestions_count': suggestions.length,
          'top_suggestion': topSuggestion.content,
        },
      );
    }

    // Fallback to AI response
    try {
      final response = await _aiAssistant.processAiQuery(
        'Respond helpfully to this user input in a terminal/developer context: $input'
      );

      return ConversationResponse(
        content: response,
        actions: [],
        metadata: {'intent': 'general', 'ai_response': true},
      );
    } catch (e) {
      return ConversationResponse(
        content: 'I\'m here to help! What would you like to do in the terminal?',
        actions: [],
        metadata: {'intent': 'general'},
      );
    }
  }

  /// Determine setup type from input
  String _determineSetupType(String input, String? projectType) {
    final lowerInput = input.toLowerCase();

    if (lowerInput.contains('react') || lowerInput.contains('next') || lowerInput.contains('vue')) {
      return 'frontend';
    }
    if (lowerInput.contains('node') || lowerInput.contains('npm') || lowerInput.contains('express')) {
      return 'nodejs';
    }
    if (lowerInput.contains('python') || lowerInput.contains('django') || lowerInput.contains('flask')) {
      return 'python';
    }
    if (lowerInput.contains('flutter') || lowerInput.contains('dart')) {
      return 'flutter';
    }
    if (lowerInput.contains('docker')) {
      return 'docker';
    }

    // Use project type if available
    return projectType ?? 'general';
  }

  /// Generate setup steps for a given type
  Future<List<SetupStep>> _generateSetupSteps(String setupType, String? currentDirectory) async {
    switch (setupType) {
      case 'nodejs':
        return [
          SetupStep('mkdir my-node-app && cd my-node-app', 'Create project directory'),
          SetupStep('npm init -y', 'Initialize npm project'),
          SetupStep('npm install express', 'Install Express framework'),
          SetupStep('echo \'const express = require("express"); const app = express(); app.listen(3000, () => console.log("Server running"));\' > server.js', 'Create basic server'),
          SetupStep('node server.js', 'Start the server'),
        ];

      case 'react':
        return [
          SetupStep('npx create-react-app my-react-app', 'Create React application'),
          SetupStep('cd my-react-app', 'Navigate to project directory'),
          SetupStep('npm start', 'Start development server'),
        ];

      case 'flutter':
        return [
          SetupStep('flutter create my_flutter_app', 'Create Flutter project'),
          SetupStep('cd my_flutter_app', 'Navigate to project directory'),
          SetupStep('flutter run', 'Run the app'),
        ];

      case 'python':
        return [
          SetupStep('python -m venv venv', 'Create virtual environment'),
          SetupStep('source venv/bin/activate', 'Activate virtual environment'),
          SetupStep('pip install flask', 'Install Flask framework'),
          SetupStep('echo \'from flask import Flask\napp = Flask(__name__)\n@app.route("/")\ndef hello():\n    return "Hello World!"\nif __name__ == "__main__":\n    app.run()\' > app.py', 'Create Flask app'),
          SetupStep('python app.py', 'Run the Flask app'),
        ];

      default:
        return [];
    }
  }

  /// Add message to history
  void _addMessage(ConversationMessage message) {
    _messageHistory.add(message);
    if (_messageHistory.length > 1000) {
      _messageHistory.removeAt(0);
    }
  }

  /// Get conversation history
  List<ConversationMessage> getConversationHistory({String? sessionId}) {
    final targetSessionId = sessionId ?? _currentSessionId;
    if (targetSessionId == null) return [];

    return _messageHistory.where((msg) => msg.sessionId == targetSessionId).toList();
  }

  /// Learn from conversation patterns
  void learnFromConversation() {
    // Analyze conversation patterns to improve future responses
    // This would be implemented with ML model training
  }

  /// End conversation session
  void endConversation({String? sessionId}) {
    final targetSessionId = sessionId ?? _currentSessionId;
    if (targetSessionId != null) {
      _contexts.remove(targetSessionId);
      if (_currentSessionId == targetSessionId) {
        _currentSessionId = null;
        _currentContext = null;
      }
    }
  }

  /// Get conversation statistics
  Map<String, dynamic> getConversationStats() {
    return {
      'total_messages': _messageHistory.length,
      'active_sessions': _contexts.length,
      'learned_intents': _learnedIntents.length,
    };
  }

  /// Dispose resources
  void dispose() {
    _conversationController.close();
    _isActive = false;
  }
}

/// Message types
enum MessageType {
  user,
  ai,
  system,
}

/// Conversation intents
enum ConversationIntent {
  question,
  command,
  explanation,
  workflow,
  search,
  setup,
  general,
}

/// Action types
enum ActionType {
  execute_command,
  execute_workflow,
  view_search_results,
  create_workflow,
  show_suggestions,
}

/// Conversation message
class ConversationMessage {
  final MessageType type;
  final String content;
  final DateTime timestamp;
  final String sessionId;
  final Map<String, dynamic>? metadata;

  ConversationMessage({
    required this.type,
    required this.content,
    required this.timestamp,
    required this.sessionId,
    this.metadata,
  });

  @override
  String toString() => '[${type.name.toUpperCase()}] $content';
}

/// Conversation response
class ConversationResponse {
  final String content;
  final List<ConversationAction> actions;
  final Map<String, dynamic> metadata;

  ConversationResponse({
    required this.content,
    required this.actions,
    required this.metadata,
  });
}

/// Conversation action
class ConversationAction {
  final ActionType type;
  final String data;
  final String description;

  ConversationAction({
    required this.type,
    required this.data,
    required this.description,
  });
}

/// Conversation context
class ConversationContext {
  final String sessionId;
  final DateTime startTime;
  final String? initialContext;
  final Map<String, dynamic> metadata = {};

  ConversationContext({
    required this.sessionId,
    required this.startTime,
    this.initialContext,
  });

  Duration get duration => DateTime.now().difference(startTime);
}

/// Learned conversation intent
class LearnedConversationIntent {
  final String pattern;
  final ConversationIntent intent;
  final int frequency;

  LearnedConversationIntent({
    required this.pattern,
    required this.intent,
    required this.frequency,
  });

  bool matches(String input) {
    // Simple pattern matching - could be enhanced with regex
    return input.toLowerCase().contains(pattern.toLowerCase());
  }
}

/// Setup step
class SetupStep {
  final String command;
  final String description;

  SetupStep(this.command, this.description);
}