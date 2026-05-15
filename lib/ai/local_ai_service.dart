import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Local AI service with Ollama integration and offline capabilities.
class LocalAIService {
  static final LocalAIService _instance = LocalAIService._internal();
  factory LocalAIService() => _instance;
  LocalAIService._internal();

  bool _isInitialized = false;
  bool _ollamaAvailable = false;
  String _ollamaEndpoint = 'http://localhost:11434';
  String _currentModel = 'llama2';
  List<String> _availableModels = [];
  
  final _responseController = StreamController<AIResponse>.broadcast();
  Stream<AIResponse> get responses => _responseController.stream;

  bool get isInitialized => _isInitialized;
  bool get ollamaAvailable => _ollamaAvailable;
  String get currentModel => _currentModel;
  List<String> get availableModels => _availableModels;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadSettings();
      await _checkOllamaAvailability();
      if (_ollamaAvailable) {
        await _loadAvailableModels();
      }
      
      _isInitialized = true;
      debugPrint('Local AI service initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize local AI service: $e\n$stack');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ollamaEndpoint = prefs.getString('ai_ollama_endpoint') ?? 'http://localhost:11434';
      _currentModel = prefs.getString('ai_ollama_model') ?? 'llama2';
    } catch (e) {
      debugPrint('Failed to load AI settings: $e');
    }
  }

  Future<void> _checkOllamaAvailability() async {
    try {
      final response = await http.get(
        Uri.parse('$_ollamaEndpoint/api/version'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _ollamaAvailable = true;
        debugPrint('Ollama is available at $_ollamaEndpoint');
      }
    } catch (e) {
      _ollamaAvailable = false;
      debugPrint('Ollama not available: $e');
    }
  }

  Future<void> _loadAvailableModels() async {
    try {
      final response = await http.get(
        Uri.parse('$_ollamaEndpoint/api/tags'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>?;
        if (models != null) {
          _availableModels = models
              .map((model) => model['name'] as String)
              .where((name) => !name.endsWith(':latest'))
              .toList();
          debugPrint('Available models: $_availableModels');
        }
      }
    } catch (e) {
      debugPrint('Failed to load available models: $e');
    }
  }

  Future<AIResponse> processText({
    required String input,
    required AICapability capability,
    String? contextId,
    Map<String, dynamic>? context,
  }) async {
    if (!_ollamaAvailable) {
      return _generateOfflineResponse(input, capability);
    }

    try {
      final prompt = _buildPrompt(input, capability, context);
      
      final response = await http.post(
        Uri.parse('$_ollamaEndpoint/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _currentModel,
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': _getTemperatureForCapability(capability),
            'top_p': 0.9,
            'max_tokens': _getMaxTokensForCapability(capability),
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final output = data['response'] as String? ?? '';
        
        return AIResponse(
          success: true,
          output: output,
          model: _currentModel,
          contextId: contextId,
          timestamp: DateTime.now(),
        );
      } else {
        debugPrint('Ollama API error: ${response.statusCode}');
        return _generateOfflineResponse(input, capability);
      }
    } catch (e) {
      debugPrint('Ollama request failed: $e');
      return _generateOfflineResponse(input, capability);
    }
  }

  String _buildPrompt(String input, AICapability capability, Map<String, dynamic>? context) {
    switch (capability) {
      case AICapability.command_suggestion:
        return '''You are a terminal command expert. Based on the user's input, suggest the most appropriate command. Provide only the command, no explanation.

User input: $input

Command:''';
      
      case AICapability.error_explanation:
        return '''You are a technical support expert. Explain this terminal error in simple terms and suggest what to do.

Error: $input

Explanation:''';
      
      case AICapability.system_analysis:
        return '''You are a system administrator. Analyze this terminal situation and provide insights.

Input: $input

Analysis:''';
      
      case AICapability.text_generation:
        return '''You are a helpful assistant. Respond to the user's request.

User: $input

Response:''';
      
      default:
        return '''User: $input

Response:''';
    }
  }

  double _getTemperatureForCapability(AICapability capability) {
    switch (capability) {
      case AICapability.command_suggestion:
        return 0.1; // Low temperature for precise commands
      case AICapability.error_explanation:
        return 0.3; // Low-medium temperature for explanations
      case AICapability.system_analysis:
        return 0.4; // Medium temperature for analysis
      case AICapability.text_generation:
        return 0.7; // Higher temperature for creative responses
      default:
        return 0.5;
    }
  }

  int _getMaxTokensForCapability(AICapability capability) {
    switch (capability) {
      case AICapability.command_suggestion:
        return 100;
      case AICapability.error_explanation:
        return 300;
      case AICapability.system_analysis:
        return 500;
      case AICapability.text_generation:
        return 1000;
      default:
        return 500;
    }
  }

  AIResponse _generateOfflineResponse(String input, AICapability capability) {
    // Fallback responses when AI is not available
    switch (capability) {
      case AICapability.command_suggestion:
        return AIResponse(
          success: true,
          output: _suggestCommandOffline(input),
          model: 'offline',
          contextId: null,
          timestamp: DateTime.now(),
        );
      
      case AICapability.error_explanation:
        return AIResponse(
          success: true,
          output: _explainErrorOffline(input),
          model: 'offline',
          contextId: null,
          timestamp: DateTime.now(),
        );
      
      default:
        return AIResponse(
          success: false,
          output: 'AI service is currently unavailable. Please check your internet connection or configure a local AI model.',
          model: 'offline',
          contextId: null,
          timestamp: DateTime.now(),
        );
    }
  }

  String _suggestCommandOffline(String input) {
    final lowercase = input.toLowerCase();
    
    if (lowercase.contains('disk') || lowercase.contains('space')) {
      return 'df -h';
    } else if (lowercase.contains('memory') || lowercase.contains('ram')) {
      return 'free -h';
    } else if (lowercase.contains('process') || lowercase.contains('running')) {
      return 'ps aux';
    } else if (lowercase.contains('file') || lowercase.contains('find')) {
      return 'find . -name "*"';
    } else {
      return 'echo "Command suggestion unavailable offline"';
    }
  }

  String _explainErrorOffline(String error) {
    final lowercase = error.toLowerCase();
    
    if (lowercase.contains('permission denied')) {
      return 'Permission denied. Try using sudo or check file permissions.';
    } else if (lowercase.contains('command not found')) {
      return 'Command not found. Check if the program is installed and in your PATH.';
    } else if (lowercase.contains('no such file')) {
      return 'File or directory not found. Check the path and spelling.';
    } else {
      return 'Error occurred. Check the command syntax and file paths.';
    }
  }

  Future<void> switchModel(String model) async {
    if (_availableModels.contains(model)) {
      _currentModel = model;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_ollama_model', model);
      debugPrint('Switched to model: $model');
    }
  }

  Future<void> updateEndpoint(String endpoint) async {
    _ollamaEndpoint = endpoint;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_ollama_endpoint', endpoint);
    
    // Recheck availability with new endpoint
    await _checkOllamaAvailability();
    if (_ollamaAvailable) {
      await _loadAvailableModels();
    }
  }

  void dispose() {
    _responseController.close();
  }
}

enum AICapability {
  command_suggestion,
  error_explanation,
  system_analysis,
  text_generation,
}

class AIResponse {
  final bool success;
  final String output;
  final String model;
  final String? contextId;
  final DateTime timestamp;

  AIResponse({
    required this.success,
    required this.output,
    required this.model,
    this.contextId,
    required this.timestamp,
  });
}