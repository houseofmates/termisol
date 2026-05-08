import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// NVIDIA NIM command prediction system
/// 
/// Features:
/// - AI-powered command prediction using NVIDIA NIM models
/// - Context-aware suggestions based on terminal history
/// - Multiple model support with fallback
/// - Real-time prediction with caching
/// - Performance optimization and monitoring
class NvidiaNimCommandPredictor {
  static const String _nimEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxTokens = 2048;
  static const double _temperature = 0.7;

  String? _apiKey;

  final Map<String, List<CommandPrediction>> _predictionCache = {};
  final List<CommandHistory> _commandHistory = [];
  final Map<String, ModelInfo> _availableModels = {};

  String _selectedModel = 'nvidia/nemotron-4-340b-instruct';
  bool _isInitialized = false;
  int _totalPredictions = 0;
  int _cacheHits = 0;
  double _totalResponseTime = 0.0;

  NvidiaNimCommandPredictor() {
    _loadApiKey();
    _initializePredictor();
  }

  /// Load API key from environment variables.
  /// Hardcoded placeholders are a security risk and have been removed.
  void _loadApiKey() {
    _apiKey = Platform.environment['NVIDIA_NIM_API_KEY'] ??
              Platform.environment['NVIDIA_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('⚠️ NVIDIA NIM API key not configured. Set NVIDIA_NIM_API_KEY or NVIDIA_API_KEY environment variable.');
    }
  }

  bool get _apiKeyConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// Initialize the predictor
  Future<void> _initializePredictor() async {
    try {
      await _loadAvailableModels();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize NIM predictor: $e');
    }
  }

  /// Load available models from NVIDIA NIM
  Future<void> _loadAvailableModels() async {
    if (!_apiKeyConfigured) {
      debugPrint('⚠️ Skipping model loading: NVIDIA NIM API key not configured');
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('https://integrate.api.nvidia.com/v1/models'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final models = data['data'] as List?;
        
        if (models != null) {
          for (final model in models) {
            final modelInfo = ModelInfo.fromJson(model);
            _availableModels[modelInfo.id] = modelInfo;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load available models: $e');
    }
  }

  /// Predict next command based on context
  Future<List<CommandPrediction>> predictNextCommand({
    required String currentInput,
    required String workingDirectory,
    required List<String> recentCommands,
    int maxSuggestions = 5,
  }) async {
    if (!_isInitialized) {
      await _initializePredictor();
    }

    _totalPredictions++;
    final stopwatch = Stopwatch()..start();

    try {
      // Check cache first
      final cacheKey = _generateCacheKey(currentInput, workingDirectory, recentCommands);
      if (_predictionCache.containsKey(cacheKey)) {
        _cacheHits++;
        return _predictionCache[cacheKey]!;
      }

      // Build context for prediction
      final context = _buildPredictionContext(
        currentInput,
        workingDirectory,
        recentCommands,
      );

      // Call NVIDIA NIM API
      if (!_apiKeyConfigured) {
        return _getFallbackPredictions(currentInput, recentCommands);
      }
      final predictions = await _callNimAPI(context, maxSuggestions);
      
      // Cache results
      if (_predictionCache.length < 1000) {
        _predictionCache[cacheKey] = predictions;
      }

      _totalResponseTime += stopwatch.elapsedMilliseconds.toDouble();

      return predictions;
    } catch (e) {
      debugPrint('Failed to predict command: $e');
      return _getFallbackPredictions(currentInput, recentCommands);
    } finally {
      stopwatch.stop();
    }
  }

  /// Build prediction context
  Map<String, dynamic> _buildPredictionContext(
    String currentInput,
    String workingDirectory,
    List<String> recentCommands,
  ) {
    return {
      'current_input': currentInput,
      'working_directory': workingDirectory,
      'recent_commands': recentCommands.take(10).toList(),
      'system_prompt': _getSystemPrompt(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Get system prompt for command prediction
  String _getSystemPrompt() {
    return '''You are an expert terminal command predictor. Based on the current input and recent command history, predict the most likely next commands the user wants to execute.

Context:
- Current input: The partial command the user is typing
- Working directory: The current directory context
- Recent commands: The last 10 commands executed

Provide predictions in JSON format:
{
  "predictions": [
    {
      "command": "predicted_command",
      "description": "brief description of what the command does",
      "confidence": 0.95,
      "category": "file_operations|system_info|development|network|other"
    }
  ]
}

Guidelines:
1. Predict realistic, useful commands
2. Consider the current working directory
3. Learn from recent command patterns
4. Provide confidence scores (0.0-1.0)
5. Categorize commands appropriately
6. Include both simple and complex predictions
7. Consider common aliases and shortcuts''';
  }

  /// Call NVIDIA NIM API
  Future<List<CommandPrediction>> _callNimAPI(
    Map<String, dynamic> context,
    int maxSuggestions,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(_nimEndpoint),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': _selectedModel,
          'messages': [
            {
              'role': 'system',
              'content': context['system_prompt'],
            },
            {
              'role': 'user',
              'content': _buildUserPrompt(context),
            },
          ],
          'max_tokens': _maxTokens,
          'temperature': _temperature,
          'stream': false,
        }),
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        // Parse predictions from response
        return _parsePredictions(content, maxSuggestions);
      } else {
        throw Exception('NIM API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('NIM API call failed: $e');
      rethrow;
    }
  }

  /// Build user prompt for API
  String _buildUserPrompt(Map<String, dynamic> context) {
    final buffer = StringBuffer();
    
    buffer.writeln('Current input: ${context['current_input']}');
    buffer.writeln('Working directory: ${context['working_directory']}');
    buffer.writeln('Recent commands:');
    
    final recentCommands = context['recent_commands'] as List<String>;
    for (int i = 0; i < recentCommands.length; i++) {
      buffer.writeln('${i + 1}. ${recentCommands[i]}');
    }
    
    buffer.writeln('\nPredict the next 5 most likely commands based on this context.');
    
    return buffer.toString();
  }

  /// Parse predictions from API response
  List<CommandPrediction> _parsePredictions(String content, int maxSuggestions) {
    try {
      // Try to parse as JSON
      final data = json.decode(content);
      final predictions = data['predictions'] as List?;
      
      if (predictions != null) {
        return predictions
            .take(maxSuggestions)
            .map((p) => CommandPrediction.fromJson(p))
            .toList();
      }
    } catch (e) {
      debugPrint('Failed to parse predictions: $e');
    }
    
    // Fallback: parse text response
    return _parseTextPredictions(content, maxSuggestions);
  }

  /// Parse predictions from text response
  List<CommandPrediction> _parseTextPredictions(String content, int maxSuggestions) {
    final lines = content.split('\n');
    final predictions = <CommandPrediction>[];
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      // Simple parsing: assume each line is a command
      final command = line.trim();
      if (command.isNotEmpty) {
        predictions.add(CommandPrediction(
          command: command,
          description: 'Suggested command',
          confidence: 0.8,
          category: _categorizeCommand(command),
        ));
        
        if (predictions.length >= maxSuggestions) break;
      }
    }
    
    return predictions;
  }

  /// Get fallback predictions when API fails
  List<CommandPrediction> _getFallbackPredictions(String currentInput, List<String> recentCommands) {
    final predictions = <CommandPrediction>[];
    
    // Common command patterns
    final commonCommands = [
      'ls -la',
      'cd ..',
      'git status',
      'git pull',
      'git add .',
      'git commit -m ""',
      'npm install',
      'pip install',
      'docker ps',
      'docker run',
      'make',
      'cmake',
      'grep -r',
      'find . -name',
      'cat',
      'nano',
      'vim',
      'chmod +x',
      'sudo apt update',
      'sudo systemctl restart',
    ];
    
    // Filter based on current input
    final filtered = commonCommands.where((cmd) => 
      cmd.startsWith(currentInput.toLowerCase()) || 
      currentInput.isEmpty
    ).take(5);
    
    for (final command in filtered) {
      predictions.add(CommandPrediction(
        command: command,
        description: 'Common command suggestion',
        confidence: 0.7,
        category: _categorizeCommand(command),
      ));
    }
    
    return predictions;
  }

  /// Categorize command
  String _categorizeCommand(String command) {
    final lowerCommand = command.toLowerCase();
    
    if (lowerCommand.contains('git')) return 'development';
    if (lowerCommand.contains('docker')) return 'development';
    if (lowerCommand.contains('npm') || lowerCommand.contains('pip')) return 'development';
    if (lowerCommand.contains('make') || lowerCommand.contains('cmake')) return 'development';
    
    if (lowerCommand.contains('ls') || lowerCommand.contains('cd') || 
        lowerCommand.contains('cat') || lowerCommand.contains('find')) return 'file_operations';
    
    if (lowerCommand.contains('ps') || lowerCommand.contains('kill') || 
        lowerCommand.contains('systemctl')) return 'system_info';
    
    if (lowerCommand.contains('curl') || lowerCommand.contains('wget') || 
        lowerCommand.contains('ping')) return 'network';
    
    return 'other';
  }

  /// Generate cache key
  String _generateCacheKey(String currentInput, String workingDirectory, List<String> recentCommands) {
    final recentHash = recentCommands.take(5).join('|').hashCode;
    return '${currentInput.hashCode}_${workingDirectory.hashCode}_$recentHash';
  }

  /// Add command to history
  void addToHistory(String command) {
    _commandHistory.add(CommandHistory(
      command: command,
      timestamp: DateTime.now(),
    ));
    
    // Keep only recent 100 commands
    if (_commandHistory.length > 100) {
      _commandHistory.removeRange(0, _commandHistory.length - 100);
    }
  }

  /// Get command history
  List<CommandHistory> getHistory() {
    return List.unmodifiable(_commandHistory);
  }

  /// Set selected model
  void setModel(String modelId) {
    if (_availableModels.containsKey(modelId)) {
      _selectedModel = modelId;
      _predictionCache.clear(); // Clear cache when model changes
    }
  }

  /// Get available models
  List<ModelInfo> getAvailableModels() {
    return _availableModels.values.toList();
  }

  /// Get current model
  ModelInfo? getCurrentModel() {
    return _availableModels[_selectedModel];
  }

  /// Get prediction statistics
  PredictionStats getStats() {
    return PredictionStats(
      totalPredictions: _totalPredictions,
      cacheHits: _cacheHits,
      cacheHitRate: _totalPredictions > 0 ? _cacheHits / _totalPredictions : 0.0,
      averageResponseTime: _totalPredictions > 0 ? _totalResponseTime / _totalPredictions : 0.0,
      totalResponseTime: _totalResponseTime,
      cacheSize: _predictionCache.length,
      historySize: _commandHistory.length,
      currentModel: _selectedModel,
    );
  }

  /// Clear cache and history
  void clearCache() {
    _predictionCache.clear();
    _commandHistory.clear();
  }

  /// Dispose predictor
  void dispose() {
    clearCache();
  }
}

/// Command prediction model
class CommandPrediction {
  final String command;
  final String description;
  final double confidence;
  final String category;
  final DateTime timestamp;

  const CommandPrediction({
    required this.command,
    required this.description,
    required this.confidence,
    required this.category,
  }) : timestamp = DateTime.now();

  factory CommandPrediction.fromJson(Map<String, dynamic> json) {
    return CommandPrediction(
      command: json['command'] as String,
      description: json['description'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      category: json['category'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'description': description,
      'confidence': confidence,
      'category': category,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Command history entry
class CommandHistory {
  final String command;
  final DateTime timestamp;

  const CommandHistory({
    required this.command,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Model information
class ModelInfo {
  final String id;
  final String name;
  final String description;
  final int maxTokens;
  final List<String> capabilities;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.maxTokens,
    required this.capabilities,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['id'] as String, // Use ID as name for now
      description: json['description'] as String? ?? '',
      maxTokens: json['max_tokens'] as int? ?? 4096,
      capabilities: (json['capabilities'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// Prediction statistics
class PredictionStats {
  final int totalPredictions;
  final int cacheHits;
  final double cacheHitRate;
  final double averageResponseTime;
  final double totalResponseTime;
  final int cacheSize;
  final int historySize;
  final String currentModel;

  const PredictionStats({
    required this.totalPredictions,
    required this.cacheHits,
    required this.cacheHitRate,
    required this.averageResponseTime,
    required this.totalResponseTime,
    required this.cacheSize,
    required this.historySize,
    required this.currentModel,
  });
}
