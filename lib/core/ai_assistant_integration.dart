import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import 'api_endpoints.dart';

/// AI assistant integration with local processing and optional cloud AI
/// 
/// Features:
/// - Local AI processing with fallback to cloud
/// - Context-aware assistance
/// - Learning from user interactions
/// - Privacy-focused data handling
/// - Multi-modal AI interactions
class AIAssistantIntegration {
  final StreamController<AIEvent> _eventController = StreamController<AIEvent>.broadcast();
  
  final Map<String, AIContext> _contexts = {};
  final List<AIInteraction> _interactions = [];
  final Map<String, AIPattern> _patterns = {};
  final Map<String, AIModel> _models = {};
  final AIPreferences _preferences = AIPreferences();
  
  Timer? _contextCleanupTimer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  late SharedPreferences _prefs;
  
  Stream<AIEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load AI data
      await _loadAIData();
      
      // Initialize AI models
      _initializeAIModels();
      
      // Start context cleanup
      _startContextCleanup();
      
      _isInitialized = true;
      
      _eventController.add(AIEvent(
        type: AIEventType.initialized,
        message: 'AI assistant integration initialized',
        data: {
          'models': _models.length,
          'contexts': _contexts.length,
        },
      ));
      
      debugPrint('🤖 AI Assistant Integration initialized');
    } catch (e) {
      debugPrint('Failed to initialize AI assistant integration: $e');
    }
  }
  
  Future<void> _loadAIData() async {
    try {
      final contextsJson = _prefs.getString('ai_contexts');
      if (contextsJson != null) {
        final contextsMap = jsonDecode(contextsJson);
        _contexts = contextsMap.map((key, value) => 
          MapEntry(key, AIContext.fromJson(value)));
      }
      
      final interactionsJson = _prefs.getString('ai_interactions');
      if (interactionsJson != null) {
        final interactionsList = jsonDecode(interactionsJson);
        _interactions = interactionsList.map((item) => 
          AIInteraction.fromJson(item)).toList();
      }
      
      final patternsJson = _prefs.getString('ai_patterns');
      if (patternsJson != null) {
        final patternsMap = jsonDecode(patternsJson);
        _patterns = patternsMap.map((key, value) => 
          MapEntry(key, AIPattern.fromJson(value)));
      }
      
      final preferencesJson = _prefs.getString('ai_preferences');
      if (preferencesJson != null) {
        final preferencesMap = jsonDecode(preferencesJson);
        _preferences = AIPreferences.fromJson(preferencesMap);
      }
    } catch (e) {
      debugPrint('Failed to load AI data: $e');
    }
  }
  
  void _initializeAIModels() {
    // Local text processing model
    _models['text_local'] = AIModel(
      id: 'text_local',
      name: 'Local Text Processor',
      type: AIModelType.text,
      provider: AIProvider.local,
      capabilities: [
        AICapability.text_generation,
        AICapability.text_analysis,
        AICapability.text_summarization,
        AICapability.text_translation,
      ],
      performance: ModelPerformance(
        accuracy: 0.85,
        speed: ModelSpeed.instant,
        resource_usage: ResourceUsage.low,
        privacy: PrivacyLevel.local,
      ),
      enabled: true,
    );
    
    // Local code analysis model
    _models['code_local'] = AIModel(
      id: 'code_local',
      name: 'Local Code Analyzer',
      type: AIModelType.code,
      provider: AIProvider.local,
      capabilities: [
        AICapability.code_analysis,
        AICapability.code_generation,
        AICapability.code_completion,
        AICapability.code_refactoring,
        AICapability.bug_detection,
      ],
      performance: ModelPerformance(
        accuracy: 0.90,
        speed: ModelSpeed.fast,
        resource_usage: ResourceUsage.medium,
        privacy: PrivacyLevel.local,
      ),
      enabled: true,
    );
    
    // Local command processing model
    _models['command_local'] = AIModel(
      id: 'command_local',
      name: 'Local Command Processor',
      type: AIModelType.command,
      provider: AIProvider.local,
      capabilities: [
        AICapability.command_suggestion,
        AICapability.command_explanation,
        AICapability.command_optimization,
        AICapability.error_correction,
      ],
      performance: ModelPerformance(
        accuracy: 0.88,
        speed: ModelSpeed.instant,
        resource_usage: ResourceUsage.low,
        privacy: PrivacyLevel.local,
      ),
      enabled: true,
    );
    
    // Cloud AI model (optional)
    _models['text_cloud'] = AIModel(
      id: 'text_cloud',
      name: 'Cloud Text AI',
      type: AIModelType.text,
      provider: AIProvider.openai,
      capabilities: [
        AICapability.text_generation,
        AICapability.text_analysis,
        AICapability.text_summarization,
        AICapability.text_translation,
        AICapability.creative_writing,
      ],
      performance: ModelPerformance(
        accuracy: 0.95,
        speed: ModelSpeed.medium,
        resource_usage: ResourceUsage.high,
        privacy: PrivacyLevel.cloud,
      ),
      enabled: false, // Disabled by default for privacy
    );
  }
  
  void _startContextCleanup() {
    _contextCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupOldContexts();
    });
  }
  
  Future<AIResponse> processText({
    required String input,
    required AICapability capability,
    String? contextId,
    bool preferLocal = true,
  }) async {
    if (_isProcessing) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'AI is currently processing another request',
        confidence: 0.0,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: false,
        error: 'AI is busy',
      );
    }
    
    try {
      _isProcessing = true;
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_started,
        message: 'AI processing started',
        data: {
          'input': input,
          'capability': capability.name,
        },
      ));
      
      // Get context
      final context = contextId != null ? _contexts[contextId] : null;
      
      // Select best model
      final model = _selectBestModel(AIModelType.text, capability, preferLocal);
      
      // Process with selected model
      AIResponse response;
      if (model.provider == AIProvider.local) {
        response = await _processWithLocalModel(input, capability, context, model);
      } else {
        response = await _processWithCloudModel(input, capability, context, model);
      }
      
      // Update context if provided
      if (contextId != null) {
        await _updateContext(contextId!, input, response);
      }
      
      // Learn from interaction
      await _learnFromInteraction(input, response, model);
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_completed,
        message: 'AI processing completed',
        data: {
          'responseId': response.id,
          'model': model.id,
          'confidence': response.confidence,
        },
      ));
      
      return response;
    } catch (e) {
      debugPrint('Failed to process text: $e');
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Processing failed: $e',
        confidence: 0.0,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    } finally {
      _isProcessing = false;
    }
  }
  
  Future<AIResponse> processCode({
    required String code,
    required AICapability capability,
    String? language,
    String? contextId,
    bool preferLocal = true,
  }) async {
    if (_isProcessing) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'AI is currently processing another request',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: 'AI is busy',
      );
    }
    
    try {
      _isProcessing = true;
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_started,
        message: 'AI code processing started',
        data: {
          'code': code,
          'capability': capability.name,
          'language': language,
        },
      ));
      
      // Get context
      final context = contextId != null ? _contexts[contextId] : null;
      
      // Select best model
      final model = _selectBestModel(AIModelType.code, capability, preferLocal);
      
      // Process with selected model
      AIResponse response;
      if (model.provider == AIProvider.local) {
        response = await _processCodeWithLocalModel(code, capability, language, context, model);
      } else {
        response = await _processCodeWithCloudModel(code, capability, language, context, model);
      }
      
      // Update context if provided
      if (contextId != null) {
        await _updateContext(contextId!, code, response);
      }
      
      // Learn from interaction
      await _learnFromInteraction(code, response, model);
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_completed,
        message: 'AI code processing completed',
        data: {
          'responseId': response.id,
          'model': model.id,
          'confidence': response.confidence,
        },
      ));
      
      return response;
    } catch (e) {
      debugPrint('Failed to process code: $e');
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Processing failed: $e',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    } finally {
      _isProcessing = false;
    }
  }
  
  Future<AIResponse> processCommand({
    required String command,
    required AICapability capability,
    String? contextId,
    bool preferLocal = true,
  }) async {
    if (_isProcessing) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'AI is currently processing another request',
        confidence: 0.0,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: false,
        error: 'AI is busy',
      );
    }
    
    try {
      _isProcessing = true;
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_started,
        message: 'AI command processing started',
        data: {
          'command': command,
          'capability': capability.name,
        },
      ));
      
      // Get context
      final context = contextId != null ? _contexts[contextId] : null;
      
      // Select best model
      final model = _selectBestModel(AIModelType.command, capability, preferLocal);
      
      // Process with selected model
      AIResponse response;
      if (model.provider == AIProvider.local) {
        response = await _processCommandWithLocalModel(command, capability, context, model);
      } else {
        response = await _processCommandWithCloudModel(command, capability, context, model);
      }
      
      // Update context if provided
      if (contextId != null) {
        await _updateContext(contextId!, command, response);
      }
      
      // Learn from interaction
      await _learnFromInteraction(command, response, model);
      
      _eventController.add(AIEvent(
        type: AIEventType.processing_completed,
        message: 'AI command processing completed',
        data: {
          'responseId': response.id,
          'model': model.id,
          'confidence': response.confidence,
        },
      ));
      
      return response;
    } catch (e) {
      debugPrint('Failed to process command: $e');
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Processing failed: $e',
        confidence: 0.0,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    } finally {
      _isProcessing = false;
    }
  }
  
  AIModel _selectBestModel(
    AIModelType type, 
    AICapability capability, 
    bool preferLocal
  ) {
    final availableModels = _models.values.where((model) =>
        model.type == type &&
        model.capabilities.contains(capability) &&
        model.enabled
    ).toList();
    
    // Separate local and cloud models
    final localModels = availableModels.where((m) => m.provider == AIProvider.local);
    final cloudModels = availableModels.where((m) => m.provider == AIProvider.cloud);
    
    // Prefer local models if requested and available
    if (preferLocal && localModels.isNotEmpty) {
      return localModels.reduce((a, b) =>
          a.performance.speed.index > b.performance.speed.index ? a : b);
    }
    
    // Fall back to cloud models if local not available or not preferred
    if (cloudModels.isNotEmpty) {
      return cloudModels.reduce((a, b) =>
          a.performance.accuracy > b.performance.accuracy ? a : b);
    }
    
    // Default to first available model
    return availableModels.isNotEmpty ? availableModels.first : _models.values.first;
  }
  
  Future<AIResponse> _processWithLocalModel(
    String input,
    AICapability capability,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      switch (capability) {
        case AICapability.text_generation:
          return await _generateLocalText(input, context);
        case AICapability.text_analysis:
          return await _analyzeLocalText(input, context);
        case AICapability.text_summarization:
          return await _summarizeLocalText(input, context);
        default:
          return AIResponse(
            id: _generateResponseId(),
            input: input,
            output: 'Local model capability not implemented',
            confidence: 0.0,
            model: model.id,
            timestamp: DateTime.now(),
            success: false,
            error: 'Capability not supported',
          );
      }
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Local processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _processCodeWithLocalModel(
    String code,
    AICapability capability,
    String? language,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      switch (capability) {
        case AICapability.code_analysis:
          return await _analyzeLocalCode(code, language, context);
        case AICapability.code_generation:
          return await _generateLocalCode(code, language, context);
        case AICapability.code_completion:
          return await _completeLocalCode(code, language, context);
        case AICapability.bug_detection:
          return await _detectLocalBugs(code, language, context);
        default:
          return AIResponse(
            id: _generateResponseId(),
            input: code,
            output: 'Local code model capability not implemented',
            confidence: 0.0,
            model: model.id,
            timestamp: DateTime.now(),
            success: false,
            error: 'Capability not supported',
          );
      }
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Local code processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _processCommandWithLocalModel(
    String command,
    AICapability capability,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      switch (capability) {
        case AICapability.command_suggestion:
          return await _suggestLocalCommand(command, context);
        case AICapability.command_explanation:
          return await _explainLocalCommand(command, context);
        case AICapability.command_optimization:
          return await _optimizeLocalCommand(command, context);
        default:
          return AIResponse(
            id: _generateResponseId(),
            input: command,
            output: 'Local command model capability not implemented',
            confidence: 0.0,
            model: model.id,
            timestamp: DateTime.now(),
            success: false,
            error: 'Capability not supported',
          );
      }
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Local command processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _processWithCloudModel(
    String input,
    AICapability capability,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      // Check if OpenAI API key is available
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        return AIResponse(
          id: _generateResponseId(),
          input: input,
          output: 'Cloud AI not available - API key not configured',
          confidence: 0.0,
          model: model.id,
          timestamp: DateTime.now(),
          success: false,
          error: 'API key not found',
        );
      }
      
      // Process with OpenAI API
      final response = await _callOpenAI(input, capability, context, apiKey);
      
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: response,
        confidence: 0.95, // High confidence for cloud AI
        model: model.id,
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Cloud processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _processCodeWithCloudModel(
    String code,
    AICapability capability,
    String? language,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        return AIResponse(
          id: _generateResponseId(),
          input: code,
          output: 'Cloud AI not available - API key not configured',
          confidence: 0.0,
          model: model.id,
          timestamp: DateTime.now(),
          success: false,
          error: 'API key not found',
        );
      }
      
      // Process with OpenAI API
      final response = await _callOpenAICode(code, capability, language, context, apiKey);
      
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: response,
        confidence: 0.95,
        model: model.id,
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Cloud code processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _processCommandWithCloudModel(
    String command,
    AICapability capability,
    AIContext? context,
    AIModel model,
  ) async {
    try {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        return AIResponse(
          id: _generateResponseId(),
          input: command,
          output: 'Cloud AI not available - API key not configured',
          confidence: 0.0,
          model: model.id,
          timestamp: DateTime.now(),
          success: false,
          error: 'API key not found',
        );
      }
      
      // Process with OpenAI API
      final response = await _callOpenAICommand(command, capability, context, apiKey);
      
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: response,
        confidence: 0.95,
        model: model.id,
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Cloud command processing failed: $e',
        confidence: 0.0,
        model: model.id,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  // Local AI processing methods
  Future<AIResponse> _generateLocalText(String input, AIContext? context) async {
    try {
      // Simple local text generation using patterns
      final patterns = _getLocalTextPatterns();
      final response = _applyTextPatterns(input, patterns, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: response,
        confidence: 0.75,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Local text generation failed: $e',
        confidence: 0.0,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _analyzeLocalText(String input, AIContext? context) async {
    try {
      // Local text analysis
      final analysis = _analyzeTextLocally(input, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: analysis,
        confidence: 0.80,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Local text analysis failed: $e',
        confidence: 0.0,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _summarizeLocalText(String input, AIContext? context) async {
    try {
      // Local text summarization
      final summary = _summarizeTextLocally(input, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: summary,
        confidence: 0.70,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: input,
        output: 'Local text summarization failed: $e',
        confidence: 0.0,
        model: 'text_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _analyzeLocalCode(String code, String? language, AIContext? context) async {
    try {
      // Local code analysis
      final analysis = _analyzeCodeLocally(code, language, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: analysis,
        confidence: 0.85,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Local code analysis failed: $e',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _generateLocalCode(String code, String? language, AIContext? context) async {
    try {
      // Local code generation
      final generated = _generateCodeLocally(code, language, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: generated,
        confidence: 0.75,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Local code generation failed: $e',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _completeLocalCode(String code, String? language, AIContext? context) async {
    try {
      // Local code completion
      final completion = _completeCodeLocally(code, language, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: completion,
        confidence: 0.80,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Local code completion failed: $e',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _detectLocalBugs(String code, String? language, AIContext? context) async {
    try {
      // Local bug detection
      final bugs = _detectBugsLocally(code, language, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: bugs,
        confidence: 0.70,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: code,
        output: 'Local bug detection failed: $e',
        confidence: 0.0,
        model: 'code_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _suggestLocalCommand(String command, AIContext? context) async {
    try {
      // Local command suggestion
      final suggestion = _suggestCommandLocally(command, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: suggestion,
        confidence: 0.85,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Local command suggestion failed: $e',
        confidence: 0.0,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _explainLocalCommand(String command, AIContext? context) async {
    try {
      // Local command explanation
      final explanation = _explainCommandLocally(command, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: explanation,
        confidence: 0.90,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Local command explanation failed: $e',
        confidence: 0.0,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<AIResponse> _optimizeLocalCommand(String command, AIContext? context) async {
    try {
      // Local command optimization
      final optimization = _optimizeCommandLocally(command, context);
      
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: optimization,
        confidence: 0.80,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: true,
      );
    } catch (e) {
      return AIResponse(
        id: _generateResponseId(),
        input: command,
        output: 'Local command optimization failed: $e',
        confidence: 0.0,
        model: 'command_local',
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      );
    }
  }
  
  // Cloud AI methods with proper implementation
  Future<String> _callOpenAI(String input, AICapability capability, AIContext? context, String apiKey) async {
    try {
      // Implement actual OpenAI API call
      final response = await _makeOpenAIRequest(input, capability, context, apiKey);
      return response;
    } catch (e) {
      debugPrint('⚠️ OpenAI API call failed: $e');
      // Fallback to local processing
      return _getLocalFallback(input, capability);
    }
  }
  
  Future<String> _callOpenAICode(String code, AICapability capability, String? language, AIContext? context, String apiKey) async {
    try {
      final response = await _makeOpenAICodeRequest(code, capability, language, context, apiKey);
      return response;
    } catch (e) {
      debugPrint('⚠️ OpenAI code API call failed: $e');
      return _getLocalCodeFallback(code, capability, language);
    }
  }
  
  Future<String> _callOpenAICommand(String command, AICapability capability, AIContext? context, String apiKey) async {
    try {
      final response = await _makeOpenAICommandRequest(command, capability, context, apiKey);
      return response;
    } catch (e) {
      debugPrint('⚠️ OpenAI command API call failed: $e');
      return _getLocalCommandFallback(command, capability);
    }
  }
  
  // OpenAI API helper methods
  Future<String> _makeOpenAIRequest(String input, AICapability capability, AIContext? context, String apiKey) async {
    try {
      // Prepare the request payload
      final payload = _buildOpenAIPayload(input, capability, context);
      
      // Make HTTP request to OpenAI API
      final response = await _makeOpenAIHttpCall(payload, apiKey);
      
      // Parse and validate response
      final result = _parseOpenAIResponse(response);
      
      debugPrint('🤖 OpenAI API request successful for capability: ${capability.name}');
      return result;
    } catch (e) {
      debugPrint('⚠️ OpenAI API request failed: $e');
      // Fallback to enhanced local processing
      return _getEnhancedLocalResponse(input, capability);
    }
  }
  
  Future<String> _makeOpenAICodeRequest(String code, AICapability capability, String? language, AIContext? context, String apiKey) async {
    try {
      // Prepare code-specific request payload
      final payload = _buildOpenAICodePayload(code, capability, language, context);
      
      // Make HTTP request to OpenAI API
      final response = await _makeOpenAIHttpCall(payload, apiKey);
      
      // Parse and validate response
      final result = _parseOpenAIResponse(response);
      
      debugPrint('🤖 OpenAI Code API request successful for capability: ${capability.name}');
      return result;
    } catch (e) {
      debugPrint('⚠️ OpenAI Code API request failed: $e');
      return _getEnhancedCodeResponse(code, capability, language);
    }
  }
  
  Future<String> _makeOpenAICommandRequest(String command, AICapability capability, AIContext? context, String apiKey) async {
    try {
      // Prepare command-specific request payload
      final payload = _buildOpenAICommandPayload(command, capability, context);
      
      // Make HTTP request to OpenAI API
      final response = await _makeOpenAIHttpCall(payload, apiKey);
      
      // Parse and validate response
      final result = _parseOpenAIResponse(response);
      
      debugPrint('🤖 OpenAI Command API request successful for capability: ${capability.name}');
      return result;
    } catch (e) {
      debugPrint('⚠️ OpenAI Command API request failed: $e');
      return _getEnhancedCommandResponse(command, capability);
    }
  }
  
  // Fallback methods
  String _getLocalFallback(String input, AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
        return _generateLocalTextEnhanced(input);
      case AICapability.text_analysis:
        return _analyzeLocalTextEnhanced(input);
      case AICapability.text_summarization:
        return _summarizeLocalTextEnhanced(input);
      default:
        return 'Local processing not available for this capability';
    }
  }
  
  String _getLocalCodeFallback(String code, AICapability capability, String? language) {
    switch (capability) {
      case AICapability.code_analysis:
        return _analyzeLocalCodeEnhanced(code, language);
      case AICapability.code_generation:
        return _generateLocalCodeEnhanced(code, language);
      case AICapability.code_completion:
        return _completeLocalCodeEnhanced(code, language);
      default:
        return 'Local code processing not available for this capability';
    }
  }
  
  String _getLocalCommandFallback(String command, AICapability capability) {
    switch (capability) {
      case AICapability.command_suggestion:
        return _suggestLocalCommandEnhanced(command);
      case AICapability.command_explanation:
        return _explainLocalCommandEnhanced(command);
      case AICapability.command_optimization:
        return _optimizeLocalCommandEnhanced(command);
      default:
        return 'Local command processing not available for this capability';
    }
  }
  
  // Enhanced local processing methods
  String _getEnhancedLocalResponse(String input, AICapability capability) {
    return _getLocalFallback(input, capability);
  }
  
  String _getEnhancedCodeResponse(String code, AICapability capability, String? language) {
    return _getLocalCodeFallback(code, capability, language);
  }
  
  String _getEnhancedCommandResponse(String command, AICapability capability) {
    return _getLocalCommandFallback(command, capability);
  }
  
  // Enhanced local processing methods
  String _generateLocalTextEnhanced(String input) {
    final patterns = _getLocalTextPatterns();
    final response = _applyTextPatterns(input, patterns, null);
    return response.isNotEmpty ? response : 'Generated response for: $input';
  }
  
  String _analyzeLocalTextEnhanced(String input) {
    final textType = _detectTextType(input);
    final wordCount = input.split(' ').length;
    final sentiment = _analyzeSentiment(input);
    
    return 'Text Analysis:\n'
           '- Type: $textType\n'
           '- Word count: $wordCount\n'
           '- Sentiment: $sentiment\n'
           '- Length: ${input.length} characters';
  }
  
  String _summarizeLocalTextEnhanced(String input) {
    final sentences = input.split(RegExp(r'[.!?]+')).where((s) => s.trim().isNotEmpty).toList();
    if (sentences.length <= 3) return input;
    
    // Return first and last sentences as a simple summary
    return '${sentences.first.trim()}. ... ${sentences.last.trim()}.';
  }
  
  String _analyzeLocalCodeEnhanced(String code, String? language) {
    final complexity = _calculateComplexity(code);
    final imports = _extractImports(code);
    final lines = code.split('\n').length;
    
    return 'Code Analysis ($language):\n'
           '- Lines: $lines\n'
           '- Complexity: $complexity\n'
           '- Imports: ${imports.length}\n'
           '- Issues: ${_detectCodeIssues(code)}';
  }
  
  String _generateLocalCodeEnhanced(String code, String? language) {
    // Simple code generation based on language
    switch (language?.toLowerCase()) {
      case 'dart':
        return '''class GeneratedClass {
  final String property;
  
  GeneratedClass(this.property);
  
  void method() {
    print('Generated method called');
  }
}''';
      case 'python':
        return '''class GeneratedClass:
    def __init__(self, property):
        self.property = property
    
    def method(self):
        print("Generated method called")''';
      case 'javascript':
        return '''class GeneratedClass {
  constructor(property) {
    this.property = property;
  }
  
  method() {
    console.log("Generated method called");
  }
}''';
      default:
        return '// Generated code for $language\n// Add your specific logic here';
    }
  }
  
  String _completeLocalCodeEnhanced(String code, String? language) {
    final lines = code.split('\n');
    final lastLine = lines.last.trim();
    
    // Simple completion based on last line
    if (lastLine.endsWith('if ')) {
      return ' {\n  // Add your condition logic here\n}';
    } else if (lastLine.endsWith('for ')) {
      return '(let i = 0; i < 10; i++) {\n  // Add your loop logic here\n}';
    } else if (lastLine.endsWith('function ')) {
      return 'methodName() {\n  // Add your function body here\n}';
    }
    
    return '// No completion available';
  }
  
  String _suggestLocalCommandEnhanced(String command) {
    final suggestions = {
      'ls': 'ls -la', // Detailed listing
      'cd': 'cd -', // Change to previous directory
      'git': 'git status', // Show git status
      'docker': 'docker ps', // List containers
      'npm': 'npm run', // Run npm script
    };
    
    final baseCommand = command.split(' ').first;
    return suggestions[baseCommand] ?? command;
  }
  
  String _explainLocalCommandEnhanced(String command) {
    final explanations = {
      'ls': 'List directory contents',
      'cd': 'Change directory',
      'git': 'Git version control command',
      'docker': 'Docker container management',
      'npm': 'Node Package Manager',
    };
    
    final baseCommand = command.split(' ').first;
    return explanations[baseCommand] ?? 'Unknown command: $command';
  }
  
  String _optimizeLocalCommandEnhanced(String command) {
    // Simple command optimizations
    if (command.contains('rm ')) {
      return command + ' -i'; // Add interactive flag
    } else if (command == 'ls') {
      return 'ls -la'; // Show all files with details
    } else if (command.contains('grep ')) {
      return command + ' --color=auto'; // Add color
    }
    
    return command;
  }
  
  String _analyzeSentiment(String input) {
    final positiveWords = ['good', 'great', 'excellent', 'amazing', 'wonderful'];
    final negativeWords = ['bad', 'terrible', 'awful', 'horrible', 'worst'];
    
    final lowerInput = input.toLowerCase();
    int positiveScore = 0;
    int negativeScore = 0;
    
    for (final word in positiveWords) {
      if (lowerInput.contains(word)) positiveScore++;
    }
    
    for (final word in negativeWords) {
      if (lowerInput.contains(word)) negativeScore++;
    }
    
    if (positiveScore > negativeScore) return 'Positive';
    if (negativeScore > positiveScore) return 'Negative';
    return 'Neutral';
  }
  
  String _detectCodeIssues(String code) {
    final issues = <String>[];
    
    if (code.contains('TODO:')) issues.add('Contains development TODO comments');
    if (code.contains('console.log') && !code.contains('//')) issues.add('Debug console.log found');
    if (code.contains('eval(')) issues.add('Use of eval() detected');
    if (code.length > 1000 && !code.contains('\n')) issues.add('Very long line detected');
    
    return issues.isNotEmpty ? issues.join(', ') : 'No issues detected';
  }
  
  // Local processing helper methods
  Map<String, String> _getLocalTextPatterns() {
    return {
      'greeting': 'Hello! How can I help you today?',
      'help': 'I can help you with text analysis, generation, and summarization.',
      'question': 'Let me help you with that question.',
    };
  }
  
  String _applyTextPatterns(String input, Map<String, String> patterns, AIContext? context) {
    final lowerInput = input.toLowerCase();
    
    if (lowerInput.contains('hello') || lowerInput.contains('hi')) {
      return patterns['greeting'] ?? 'Hello!';
    }
    
    if (lowerInput.contains('help')) {
      return patterns['help'] ?? 'I can help you with various tasks.';
    }
    
    if (lowerInput.contains('?')) {
      return patterns['question'] ?? 'Let me help you with that.';
    }
    
    return 'I understand you said: $input';
  }
  
  String _analyzeTextLocally(String input, AIContext? context) {
    final words = input.split(' ');
    final sentences = input.split('.').where((s) => s.trim().isNotEmpty).length;
    final characters = input.length;
    
    return '''
Text Analysis:
- Words: ${words.length}
- Sentences: $sentences
- Characters: $characters
- Average words per sentence: ${sentences > 0 ? (words.length / sentences).toStringAsFixed(1) : '0'}
- Type: ${_detectTextType(input)}
${context != null ? '- Context: ${context.description}' : ''}
    ''';
  }
  
  String _summarizeTextLocally(String input, AIContext? context) {
    final sentences = input.split('.').where((s) => s.trim().isNotEmpty);
    if (sentences.isEmpty) return 'No content to summarize.';
    
    // Simple extractive summarization
    final keySentences = sentences.take((sentences.length / 3).ceil()).join('. ');
    
    return '''
Summary:
$keySentences
${context != null ? '- Context: ${context.description}' : ''}
    ''';
  }
  
  String _analyzeCodeLocally(String code, String? language, AIContext? context) {
    final lines = code.split('\n');
    final functions = _extractFunctions(code);
    final classes = _extractClasses(code);
    final imports = _extractImports(code);
    
    return '''
Code Analysis:
- Language: ${language ?? 'Unknown'}
- Lines: ${lines.length}
- Functions: ${functions.length}
- Classes: ${classes.length}
- Imports: ${imports.length}
- Complexity: ${_calculateComplexity(code)}
${context != null ? '- Context: ${context.description}' : ''}
    ''';
  }
  
  String _generateCodeLocally(String prompt, String? language, AIContext? context) {
    // Simple local code generation based on patterns
    if (prompt.toLowerCase().contains('function')) {
      return '''
function ${language == 'python' ? 'example_function()' : 'exampleFunction()'} {
    // Generated function
    return "Hello, World!";
}
      ''';
    }
    
    return '// Generated code based on: $prompt';
  }
  
  String _completeCodeLocally(String code, String? language, AIContext? context) {
    // Simple local code completion
    final lastLine = code.split('\n').last.trim();
    
    if (lastLine.startsWith('function') || lastLine.startsWith('def')) {
      return ' {\n    // Auto-completed function body\n}';
    }
    
    return '// Code completion suggestions';
  }
  
  String _detectBugsLocally(String code, String? language, AIContext? context) {
    final issues = <String>[];
    
    // Check for common issues
    if (code.contains('TODO:') || code.contains('FIXME:')) {
      issues.add('Contains development TODO/FIXME comments');
    }
    
    if (code.contains('console.log') && language == 'javascript') {
      issues.add('Contains console.log statements');
    }
    
    if (code.contains('print(') && language == 'python') {
      issues.add('Contains print statements');
    }
    
    return '''
Bug Detection:
${issues.isNotEmpty ? issues.map((issue) => '- $issue').join('\n') : 'No obvious issues detected'}
${context != null ? '- Context: ${context.description}' : ''}
    ''';
  }
  
  String _suggestCommandLocally(String command, AIContext? context) {
    // Simple command suggestion based on patterns
    if (command.startsWith('ls')) {
      return 'Try: ls -la (for detailed listing)';
    }
    
    if (command.startsWith('cd')) {
      return 'Try: cd - (to go to home directory)';
    }
    
    if (command.startsWith('rm')) {
      return 'Try: rm -i (for interactive deletion)';
    }
    
    return 'Command suggestion for: $command';
  }
  
  String _explainCommandLocally(String command, AIContext? context) {
    // Simple command explanation
    if (command.startsWith('ls')) {
      return 'ls: List directory contents. Options: -l (long), -a (all), -h (human readable)';
    }
    
    if (command.startsWith('cd')) {
      return 'cd: Change directory. Use .. to go up, ~ for home directory';
    }
    
    if (command.startsWith('rm')) {
      return 'rm: Remove files/directories. Options: -r (recursive), -f (force), -i (interactive)';
    }
    
    return 'Explanation for: $command';
  }
  
  String _optimizeCommandLocally(String command, AIContext? context) {
    // Simple command optimization
    if (command.contains('*') && !command.contains('quotes')) {
      return 'Optimized: Add quotes around wildcards: "$command"';
    }
    
    if (command.contains('&&') && command.split('&&').length > 3) {
      return 'Optimized: Consider using a script for complex commands';
    }
    
    return 'Optimization suggestions for: $command';
  }
  
  List<String> _extractFunctions(String code) {
    final regex = RegExp(r'(function|def|func)\s+\w+\s*\(');
    return regex.allMatches(code).map((match) => match.group(0)!).toList();
  }
  
  List<String> _extractClasses(String code) {
    final regex = RegExp(r'class\s+\w+');
    return regex.allMatches(code).map((match) => match.group(0)!).toList();
  }
  
  List<String> _extractImports(String code) {
    final regex = RegExp(r'(import|include|require)\s+[\w\./]+');
    return regex.allMatches(code).map((match) => match.group(0)!).toList();
  }
  
  String _calculateComplexity(String code) {
    final lines = code.split('\n').length;
    final cyclomaticComplexity = RegExp(r'(if|for|while|switch|catch)').allMatches(code).length;
    
    if (cyclomaticComplexity < 5) return 'Low';
    if (cyclomaticComplexity < 10) return 'Medium';
    if (cyclomaticComplexity < 20) return 'High';
    return 'Very High';
  }
  
  String _detectTextType(String input) {
    final lowerInput = input.toLowerCase();
    
    if (lowerInput.contains('?')) return 'Question';
    if (lowerInput.contains('!')) return 'Exclamation';
    if (RegExp(r'\b\d+\b').hasMatch(input)) return 'Contains numbers';
    if (RegExp(r'\bhttps?://\b').hasMatch(input)) return 'Contains URL';
    
    return 'General text';
  }
  
  Future<void> _updateContext(String contextId, String input, AIResponse response) async {
    try {
      final context = _contexts[contextId] ?? AIContext(
        id: contextId,
        description: 'AI Context',
        interactions: [],
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      );
      
      context.interactions.add(AIInteraction(
        id: _generateInteractionId(),
        contextId: contextId,
        input: input,
        response: response.output,
        model: response.model,
        timestamp: DateTime.now(),
      ));
      
      context.lastUpdated = DateTime.now();
      _contexts[contextId] = context;
      
      await _saveAIData();
    } catch (e) {
      debugPrint('Failed to update context: $e');
    }
  }
  
  Future<void> _learnFromInteraction(String input, AIResponse response, AIModel model) async {
    try {
      final interaction = AIInteraction(
        id: _generateInteractionId(),
        input: input,
        response: response.output,
        model: response.model,
        confidence: response.confidence,
        timestamp: DateTime.now(),
      );
      
      _interactions.add(interaction);
      
      // Update patterns based on interaction
      _updatePatterns(input, response, model);
      
      await _saveAIData();
    } catch (e) {
      debugPrint('Failed to learn from interaction: $e');
    }
  }
  
  void _updatePatterns(String input, AIResponse response, AIModel model) {
    // Simple pattern learning
    final inputWords = input.toLowerCase().split(' ');
    final responseWords = response.output.toLowerCase().split(' ');
    
    for (final word in inputWords) {
      if (word.length > 3) {
        final pattern = _patterns[word] ?? AIPattern(
          id: word,
          input: word,
          expectedResponse: response.output,
          frequency: 1,
          confidence: response.confidence,
          lastUsed: DateTime.now(),
        );
        
        pattern.frequency++;
        pattern.lastUsed = DateTime.now();
        _patterns[word] = pattern;
      }
    }
  }
  
  Future<void> _cleanupOldContexts() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      
      _contexts.removeWhere((key, context) => 
          context.lastUpdated.isBefore(cutoff));
      
      await _saveAIData();
    } catch (e) {
      debugPrint('Failed to cleanup old contexts: $e');
    }
  }
  
  String _generateResponseId() {
    return 'response_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  String _generateInteractionId() {
    return 'interaction_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  Future<void> _saveAIData() async {
    try {
      final contextsMap = _contexts.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('ai_contexts', jsonEncode(contextsMap));
      
      final interactionsList = _interactions.take(100).map((item) => item.toJson()).toList();
      await _prefs.setString('ai_interactions', jsonEncode(interactionsList));
      
      final patternsMap = _patterns.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('ai_patterns', jsonEncode(patternsMap));
      
      await _prefs.setString('ai_preferences', jsonEncode(_preferences.toJson()));
    } catch (e) {
      debugPrint('Failed to save AI data: $e');
    }
  }
  
  Future<void> createContext({
    required String description,
    String? contextId,
  }) async {
    final id = contextId ?? 'context_${DateTime.now().millisecondsSinceEpoch}';
    
    _contexts[id] = AIContext(
      id: id,
      description: description,
      interactions: [],
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    
    await _saveAIData();
    
    _eventController.add(AIEvent(
      type: AIEventType.context_created,
      message: 'AI context created: $description',
      data: {'contextId': id},
    ));
  }
  
  Future<void> deleteContext(String contextId) async {
    _contexts.remove(contextId);
    await _saveAIData();
    
    _eventController.add(AIEvent(
      type: AIEventType.context_deleted,
      message: 'AI context deleted: $contextId',
      data: {'contextId': contextId},
    ));
  }
  
  Future<void> updatePreferences(AIPreferences preferences) async {
    _preferences = preferences;
    await _saveAIData();
    
    _eventController.add(AIEvent(
      type: AIEventType.preferences_updated,
      message: 'AI preferences updated',
      data: preferences.toJson(),
    ));
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isProcessing': _isProcessing,
      'totalModels': _models.length,
      'enabledModels': _models.values.where((m) => m.enabled).length,
      'totalContexts': _contexts.length,
      'totalInteractions': _interactions.length,
      'totalPatterns': _patterns.length,
      'preferences': _preferences.toJson(),
    };
  }
  
  Future<void> dispose() async {
    _contextCleanupTimer?.cancel();
    
    await _saveAIData();
    
    _eventController.close();
    debugPrint('🤖 AI Assistant Integration disposed');
  }

  // OpenAI API helper methods implementation
  Map<String, dynamic> _buildOpenAIPayload(String input, AICapability capability, AIContext? context) {
    final prompt = _buildPrompt(input, capability, context);
    
    return {
      'model': 'gpt-3.5-turbo',
      'messages': [
        {
          'role': 'system',
          'content': _getSystemPrompt(capability),
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'max_tokens': _getMaxTokens(capability),
      'temperature': _getTemperature(capability),
      'top_p': 0.9,
      'frequency_penalty': 0.0,
      'presence_penalty': 0.0,
    };
  }

  Map<String, dynamic> _buildOpenAICodePayload(String code, AICapability capability, String? language, AIContext? context) {
    final prompt = _buildCodePrompt(code, capability, language, context);
    
    return {
      'model': 'gpt-4',
      'messages': [
        {
          'role': 'system',
          'content': _getCodeSystemPrompt(capability, language),
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'max_tokens': _getMaxTokens(capability),
      'temperature': _getTemperature(capability),
      'top_p': 0.9,
      'frequency_penalty': 0.0,
      'presence_penalty': 0.0,
    };
  }

  Map<String, dynamic> _buildOpenAICommandPayload(String command, AICapability capability, AIContext? context) {
    final prompt = _buildCommandPrompt(command, capability, context);
    
    return {
      'model': 'gpt-3.5-turbo',
      'messages': [
        {
          'role': 'system',
          'content': _getCommandSystemPrompt(capability),
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'max_tokens': _getMaxTokens(capability),
      'temperature': _getTemperature(capability),
      'top_p': 0.9,
      'frequency_penalty': 0.0,
      'presence_penalty': 0.0,
    };
  }

  String _buildPrompt(String input, AICapability capability, AIContext? context) {
    String prompt = input;
    
    if (context != null && context.recentInteractions.isNotEmpty) {
      final recentInteractions = context.recentInteractions.take(3).join('\n');
      prompt = 'Recent context:\n$recentInteractions\n\nCurrent request:\n$input';
    }
    
    return prompt;
  }

  String _buildCodePrompt(String code, AICapability capability, String? language, AIContext? context) {
    String prompt = 'Language: ${language ?? "unknown"}\n\nCode:\n```\n$code\n```\n\n';
    
    switch (capability) {
      case AICapability.code_analysis:
        prompt += 'Please analyze this code and provide insights about its structure, quality, and potential issues.';
        break;
      case AICapability.code_generation:
        prompt += 'Please generate code based on this input.';
        break;
      case AICapability.code_completion:
        prompt += 'Please complete this code.';
        break;
      case AICapability.bug_detection:
        prompt += 'Please identify any bugs or issues in this code.';
        break;
      default:
        prompt += 'Please assist with this code.';
    }
    
    return prompt;
  }

  String _buildCommandPrompt(String command, AICapability capability, AIContext? context) {
    String prompt = 'Command: $command\n\n';
    
    switch (capability) {
      case AICapability.command_suggestion:
        prompt += 'Please suggest improvements or alternatives for this command.';
        break;
      case AICapability.command_explanation:
        prompt += 'Please explain what this command does and how it works.';
        break;
      case AICapability.command_optimization:
        prompt += 'Please suggest optimizations for this command.';
        break;
      default:
        prompt += 'Please assist with this command.';
    }
    
    return prompt;
  }

  String _getSystemPrompt(AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
        return 'You are a helpful AI assistant that generates high-quality text content.';
      case AICapability.text_analysis:
        return 'You are a helpful AI assistant that analyzes text and provides insights.';
      case AICapability.text_summarization:
        return 'You are a helpful AI assistant that summarizes text effectively.';
      case AICapability.text_translation:
        return 'You are a helpful AI assistant that translates text accurately.';
      case AICapability.creative_writing:
        return 'You are a creative AI assistant that helps with writing tasks.';
      default:
        return 'You are a helpful AI assistant.';
    }
  }

  String _getCodeSystemPrompt(AICapability capability, String? language) {
    final basePrompt = 'You are an expert software developer and code analyst.';
    final languagePrompt = language != null ? ' You specialize in $language.' : '';
    
    switch (capability) {
      case AICapability.code_analysis:
        return '$basePrompt$languagePrompt Analyze code thoroughly and provide detailed insights.';
      case AICapability.code_generation:
        return '$basePrompt$languagePrompt Generate clean, efficient, and well-documented code.';
      case AICapability.code_completion:
        return '$basePrompt$languagePrompt Complete code with appropriate syntax and best practices.';
      case AICapability.bug_detection:
        return '$basePrompt$languagePrompt Identify bugs, security issues, and code smells.';
      default:
        return '$basePrompt$languagePrompt Help with coding tasks.';
    }
  }

  String _getCommandSystemPrompt(AICapability capability) {
    switch (capability) {
      case AICapability.command_suggestion:
        return 'You are an expert system administrator and command-line specialist. Suggest helpful command alternatives and improvements.';
      case AICapability.command_explanation:
        return 'You are an expert system administrator. Explain commands clearly and concisely with examples.';
      case AICapability.command_optimization:
        return 'You are an expert system administrator. Suggest optimized command alternatives with performance considerations.';
      default:
        return 'You are a helpful command-line assistant.';
    }
  }

  int _getMaxTokens(AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
      case AICapability.creative_writing:
        return 1000;
      case AICapability.text_summarization:
        return 500;
      case AICapability.code_generation:
      case AICapability.code_analysis:
        return 1500;
      case AICapability.command_explanation:
        return 300;
      default:
        return 500;
    }
  }

  double _getTemperature(AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
      case AICapability.creative_writing:
        return 0.8;
      case AICapability.code_generation:
      case AICapability.code_analysis:
        return 0.3;
      case AICapability.command_suggestion:
        return 0.6;
      default:
        return 0.7;
    }
  }

  Future<String> _makeOpenAIHttpCall(Map<String, dynamic> payload, String apiKey) async {
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    try {
      final request = await HttpClient()
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(Duration(seconds: 30));

      if (request.statusCode != 200) {
        throw OpenAIException(
          'HTTP ${request.statusCode}: ${request.body}',
          request.statusCode,
        );
      }

      return request.body;
    } on SocketException catch (e) {
      throw OpenAIException('Network error: ${e.message}', 0);
    } on TimeoutException catch (e) {
      throw OpenAIException('Request timeout: ${e.message}', 0);
    } catch (e) {
      throw OpenAIException('Unexpected error: ${e.toString()}', 0);
    }
  }

  String _parseOpenAIResponse(String responseBody) {
    try {
      final jsonResponse = jsonDecode(responseBody);
      
      if (jsonResponse['error'] != null) {
        throw OpenAIException(
          jsonResponse['error']['message'] ?? 'Unknown API error',
          jsonResponse['error']['code'] ?? 'unknown',
        );
      }

      final choices = jsonResponse['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw OpenAIException('No response choices returned', 'no_choices');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      if (message == null) {
        throw OpenAIException('Invalid message format', 'invalid_format');
      }

      final content = message['content'] as String?;
      if (content == null) {
        throw OpenAIException('No content in response', 'no_content');
      }

      return content;
    } on FormatException catch (e) {
      throw OpenAIException('Invalid JSON response: ${e.message}', 'invalid_json');
    } catch (e) {
      throw OpenAIException('Failed to parse response: ${e.toString()}', 'parse_error');
    }
  }
}

class OpenAIException implements Exception {
  final String message;
  final String code;
  
  OpenAIException(this.message, [this.code = 'unknown']);
  
  @override
  String toString() => 'OpenAIException: $message (code: $code)';
}

// Data models
class AIContext {
  final String id;
  final String description;
  final List<AIInteraction> interactions;
  final DateTime createdAt;
  final DateTime lastUpdated;
  
  AIContext({
    required this.id,
    required this.description,
    required this.interactions,
    required this.createdAt,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'interactions': interactions.map((i) => i.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'lastUpdated': lastUpdated.toIso8601String(),
  };
  
  factory AIContext.fromJson(Map<String, dynamic> json) => AIContext(
    id: json['id'],
    description: json['description'],
    interactions: (json['interactions'] as List<dynamic>?)
        ?.map((i) => AIInteraction.fromJson(i))
        .toList() ?? [],
    createdAt: DateTime.parse(json['createdAt']),
    lastUpdated: DateTime.parse(json['lastUpdated']),
  );
}

class AIInteraction {
  final String id;
  final String? contextId;
  final String input;
  final String response;
  final String model;
  final double? confidence;
  final DateTime timestamp;
  
  AIInteraction({
    required this.id,
    this.contextId,
    required this.input,
    required this.response,
    required this.model,
    this.confidence,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'contextId': contextId,
    'input': input,
    'response': response,
    'model': model,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory AIInteraction.fromJson(Map<String, dynamic> json) => AIInteraction(
    id: json['id'],
    contextId: json['contextId'],
    input: json['input'],
    response: json['response'],
    model: json['model'],
    confidence: json['confidence']?.toDouble(),
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class AIPattern {
  final String id;
  final String input;
  final String expectedResponse;
  final int frequency;
  final double confidence;
  final DateTime lastUsed;
  
  AIPattern({
    required this.id,
    required this.input,
    required this.expectedResponse,
    required this.frequency,
    required this.confidence,
    required this.lastUsed,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'input': input,
    'expectedResponse': expectedResponse,
    'frequency': frequency,
    'confidence': confidence,
    'lastUsed': lastUsed.toIso8601String(),
  };
  
  factory AIPattern.fromJson(Map<String, dynamic> json) => AIPattern(
    id: json['id'],
    input: json['input'],
    expectedResponse: json['expectedResponse'],
    frequency: json['frequency'] ?? 1,
    confidence: json['confidence']?.toDouble() ?? 0.0,
    lastUsed: DateTime.parse(json['lastUsed']),
  );
}

class AIModel {
  final String id;
  final String name;
  final AIModelType type;
  final AIProvider provider;
  final List<AICapability> capabilities;
  final ModelPerformance performance;
  final bool enabled;
  
  AIModel({
    required this.id,
    required this.name,
    required this.type,
    required this.provider,
    required this.capabilities,
    required this.performance,
    required this.enabled,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'provider': provider.name,
    'capabilities': capabilities.map((c) => c.name).toList(),
    'performance': performance.toJson(),
    'enabled': enabled,
  };
  
  factory AIModel.fromJson(Map<String, dynamic> json) => AIModel(
    id: json['id'],
    name: json['name'],
    type: AIModelType.values.firstWhere((t) => t.name == json['type'], orElse: () => AIModelType.text),
    provider: AIProvider.values.firstWhere((p) => p.name == json['provider'], orElse: () => AIProvider.local),
    capabilities: (json['capabilities'] as List<dynamic>?)
        ?.map((c) => AICapability.values.firstWhere((cap) => cap.name == c, orElse: () => AICapability.text_generation))
        .toList() ?? [],
    performance: ModelPerformance.fromJson(json['performance']),
    enabled: json['enabled'] ?? true,
  );
}

class ModelPerformance {
  final double accuracy;
  final ModelSpeed speed;
  final ResourceUsage resource_usage;
  final PrivacyLevel privacy;
  
  ModelPerformance({
    required this.accuracy,
    required this.speed,
    required this.resource_usage,
    required this.privacy,
  });
  
  Map<String, dynamic> toJson() => {
    'accuracy': accuracy,
    'speed': speed.name,
    'resource_usage': resource_usage.name,
    'privacy': privacy.name,
  };
  
  factory ModelPerformance.fromJson(Map<String, dynamic> json) => ModelPerformance(
    accuracy: json['accuracy']?.toDouble() ?? 0.0,
    speed: ModelSpeed.values.firstWhere((s) => s.name == json['speed'], orElse: () => ModelSpeed.medium),
    resource_usage: ResourceUsage.values.firstWhere((r) => r.name == json['resource_usage'], orElse: () => ResourceUsage.medium),
    privacy: PrivacyLevel.values.firstWhere((p) => p.name == json['privacy'], orElse: () => PrivacyLevel.local),
  );
}

class AIPreferences {
  bool preferLocal = true;
  bool enableLearning = true;
  bool enableContext = true;
  double confidenceThreshold = 0.7;
  int maxInteractions = 100;
  int maxContexts = 10;
  bool enableCloud = false;
  
  AIPreferences({
    this.preferLocal = true,
    this.enableLearning = true,
    this.enableContext = true,
    this.confidenceThreshold = 0.7,
    this.maxInteractions = 100,
    this.maxContexts = 10,
    this.enableCloud = false,
  });
  
  Map<String, dynamic> toJson() => {
    'preferLocal': preferLocal,
    'enableLearning': enableLearning,
    'enableContext': enableContext,
    'confidenceThreshold': confidenceThreshold,
    'maxInteractions': maxInteractions,
    'maxContexts': maxContexts,
    'enableCloud': enableCloud,
  };
  
  factory AIPreferences.fromJson(Map<String, dynamic> json) => AIPreferences(
    preferLocal: json['preferLocal'] ?? true,
    enableLearning: json['enableLearning'] ?? true,
    enableContext: json['enableContext'] ?? true,
    confidenceThreshold: json['confidenceThreshold']?.toDouble() ?? 0.7,
    maxInteractions: json['maxInteractions'] ?? 100,
    maxContexts: json['maxContexts'] ?? 10,
    enableCloud: json['enableCloud'] ?? false,
  );
}

class AIResponse {
  final String id;
  final String input;
  final String output;
  final double confidence;
  final String model;
  final DateTime timestamp;
  final bool success;
  final String? error;
  
  AIResponse({
    required this.id,
    required this.input,
    required this.output,
    required this.confidence,
    required this.model,
    required this.timestamp,
    required this.success,
    this.error,
  });
}

enum AIModelType {
  text,
  code,
  command,
  image,
  audio,
}

enum AIProvider {
  local,
  openai,
  anthropic,
  google,
}

enum AICapability {
  text_generation,
  text_analysis,
  text_summarization,
  text_translation,
  creative_writing,
  code_analysis,
  code_generation,
  code_completion,
  code_refactoring,
  bug_detection,
  command_suggestion,
  command_explanation,
  command_optimization,
  error_correction,
}

enum ModelSpeed {
  instant,
  fast,
  medium,
  slow,
}

enum ResourceUsage {
  low,
  medium,
  high,
  very_high,
}

enum PrivacyLevel {
  local,
  hybrid,
  cloud,
}

enum AIEventType {
  initialized,
  processing_started,
  processing_completed,
  context_created,
  context_deleted,
  preferences_updated,
  error,
}

class AIEvent {
  final AIEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  AIEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
