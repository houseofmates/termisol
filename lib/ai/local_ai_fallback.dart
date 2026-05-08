import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tensor_flow_lite/tensor_flow_lite.dart' as tfl;

/// Local AI Fallback System
/// 
/// Provides offline AI capabilities using ONNX and TensorFlow Lite models
/// when cloud-based AI services are unavailable or for privacy-sensitive operations.
class LocalAiFallback {
  static const String _modelName = 'termisol_ai_model.tflite';
  static const String _modelVersion = '1.0.0';
  static const int _maxInputLength = 512;
  static const int _maxOutputLength = 256;
  
  // Model instances
  tfl.Interpreter? _textModel;
  tfl.Interpreter? _codeModel;
  tfl.Interpreter? _commandModel;
  
  // Model state
  bool _isInitialized = false;
  bool _modelsLoaded = false;
  String? _modelPath;
  
  // Performance optimization
  final Map<String, String> _responseCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  Timer? _cacheCleanupTimer;
  
  // Capabilities
  final Set<LocalAiCapability> _supportedCapabilities = {};
  
  LocalAiFallback();
  
  /// Initialize local AI system
  Future<bool> initialize() async {
    try {
      debugPrint('[local_ai] Initializing local AI fallback...');
      
      // Check if models are available
      if (!await _checkModelAvailability()) {
        debugPrint('[local_ai] No local models found, downloading...');
        await _downloadModels();
      }
      
      // Load models
      await _loadModels();
      
      // Setup cache cleanup
      _startCacheCleanup();
      
      _isInitialized = true;
      debugPrint('[local_ai] Local AI fallback initialized successfully');
      
      return true;
    } catch (e) {
      debugPrint('[local_ai] Initialization failed: $e');
      return false;
    }
  }
  
  /// Check if models are available locally
  Future<bool> _checkModelAvailability() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/$_modelName');
      
      return await modelFile.exists();
    } catch (e) {
      debugPrint('[local_ai] Error checking model availability: $e');
      return false;
    }
  }
  
  /// Download AI models if not available
  Future<void> _downloadModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/$_modelName');
      
      // In a real implementation, this would download from a CDN
      // For now, we'll create a placeholder model
      debugPrint('[local_ai] Creating placeholder model...');
      
      // Create a simple placeholder model file
      await modelFile.writeAsBytes(_createPlaceholderModel());
      
      debugPrint('[local_ai] Model downloaded/created');
    } catch (e) {
      debugPrint('[local_ai] Failed to download models: $e');
      rethrow;
    }
  }
  
  /// Create placeholder model (for demo purposes)
  Uint8List _createPlaceholderModel() {
    // This would be a real TFLite model in production
    // For now, return empty data as placeholder
    return Uint8List.fromList([]);
  }
  
  /// Load AI models into memory
  Future<void> _loadModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _modelPath = '${appDir.path}/$_modelName';
      
      // Load text generation model
      _textModel = await tfl.Interpreter.fromAsset(_modelName);
      _supportedCapabilities.add(LocalAiCapability.textGeneration);
      
      // Load code generation model
      _codeModel = await tfl.Interpreter.fromAsset('code_model.tflite');
      _supportedCapabilities.add(LocalAiCapability.codeGeneration);
      
      // Load command suggestion model
      _commandModel = await tfl.Interpreter.fromAsset('command_model.tflite');
      _supportedCapabilities.add(LocalAiCapability.commandSuggestion);
      
      _modelsLoaded = true;
      debugPrint('[local_ai] Models loaded: $_supportedCapabilities');
      
    } catch (e) {
      debugPrint('[local_ai] Failed to load models: $e');
      // Continue with limited capabilities
      _modelsLoaded = false;
    }
  }
  
  /// Process text input using local AI
  Future<LocalAiResponse> processText({
    required String input,
    required LocalAiCapability capability,
    String? context,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) {
      return LocalAiResponse.error('Local AI not initialized');
    }
    
    // Check cache first
    final cacheKey = _getCacheKey(input, capability, context);
    if (_responseCache.containsKey(cacheKey)) {
      final cachedResponse = _responseCache[cacheKey]!;
      return LocalAiResponse.success(cachedResponse, cached: true);
    }
    
    try {
      switch (capability) {
        case LocalAiCapability.textGeneration:
          return await _generateTextResponse(input, context);
        case LocalAiCapability.codeGeneration:
          return await _generateCodeResponse(input, context);
        case LocalAiCapability.commandSuggestion:
          return await _generateCommandSuggestions(input, context);
        case LocalAiCapability.errorAnalysis:
          return await _analyzeError(input, context);
        case LocalAiCapability.textSummarization:
          return await _summarizeText(input, context);
      }
    } catch (e) {
      debugPrint('[local_ai] Processing failed: $e');
      return LocalAiResponse.error('Local processing failed: $e');
    }
  }
  
  /// Generate text response
  Future<LocalAiResponse> _generateTextResponse(String input, String? context) async {
    if (_textModel == null) {
      return LocalAiResponse.error('Text model not available');
    }
    
    try {
      // Tokenize input (simplified)
      final tokens = _tokenizeInput(input);
      final inputTensor = _createInputTensor(tokens);
      
      // Run inference
      final output = List.filled(1 * _maxOutputLength * 1000, 0.0).reshape([1, _maxOutputLength, 1000]);
      _textModel!.run(inputTensor, output);
      
      // Decode output
      final response = _decodeOutput(output);
      
      // Cache response
      final cacheKey = _getCacheKey(input, LocalAiCapability.textGeneration, context);
      _cacheResponse(cacheKey, response);
      
      return LocalAiResponse.success(response);
    } catch (e) {
      debugPrint('[local_ai] Text generation failed: $e');
      return _generateFallbackResponse(input, 'text');
    }
  }
  
  /// Generate code response
  Future<LocalAiResponse> _generateCodeResponse(String input, String? context) async {
    if (_codeModel == null) {
      return _generateFallbackCodeResponse(input);
    }
    
    try {
      // Similar to text generation but with code-specific model
      final tokens = _tokenizeInput(input);
      final inputTensor = _createInputTensor(tokens);
      
      final output = List.filled(1 * _maxOutputLength * 5000, 0.0).reshape([1, _maxOutputLength, 5000]);
      _codeModel!.run(inputTensor, output);
      
      final response = _decodeOutput(output);
      
      final cacheKey = _getCacheKey(input, LocalAiCapability.codeGeneration, context);
      _cacheResponse(cacheKey, response);
      
      return LocalAiResponse.success(response);
    } catch (e) {
      debugPrint('[local_ai] Code generation failed: $e');
      return _generateFallbackCodeResponse(input);
    }
  }
  
  /// Generate command suggestions
  Future<LocalAiResponse> _generateCommandSuggestions(String input, String? context) async {
    if (_commandModel == null) {
      return _generateFallbackCommandSuggestions(input);
    }
    
    try {
      final tokens = _tokenizeInput(input);
      final inputTensor = _createInputTensor(tokens);
      
      final output = List.filled(1 * 10 * 1000, 0.0).reshape([1, 10, 1000]); // 10 suggestions
      _commandModel!.run(inputTensor, output);
      
      final suggestions = _decodeSuggestions(output);
      
      final cacheKey = _getCacheKey(input, LocalAiCapability.commandSuggestion, context);
      _cacheResponse(cacheKey, suggestions.join('\n'));
      
      return LocalAiResponse.success(suggestions.join('\n'));
    } catch (e) {
      debugPrint('[local_ai] Command suggestion failed: $e');
      return _generateFallbackCommandSuggestions(input);
    }
  }
  
  /// Analyze error messages
  Future<LocalAiResponse> _analyzeError(String errorText, String? context) async {
    // Simple error analysis using pattern matching
    final analysis = _analyzeErrorPatterns(errorText);
    
    final cacheKey = _getCacheKey(errorText, LocalAiCapability.errorAnalysis, context);
    _cacheResponse(cacheKey, analysis);
    
    return LocalAiResponse.success(analysis);
  }
  
  /// Summarize text
  Future<LocalAiResponse> _summarizeText(String text, String? context) async {
    // Simple extractive summarization
    final sentences = text.split(RegExp(r'[.!?]+'));
    if (sentences.length <= 3) {
      return LocalAiResponse.success(text.trim());
    }
    
    // Select first, middle, and last sentences for summary
    final summary = [
      sentences[0].trim(),
      sentences[sentences.length ~/ 2].trim(),
      sentences.last.trim(),
    ].join('. ');
    
    final cacheKey = _getCacheKey(text, LocalAiCapability.textSummarization, context);
    _cacheResponse(cacheKey, summary);
    
    return LocalAiResponse.success(summary);
  }
  
  /// Tokenize input text (simplified)
  List<int> _tokenizeInput(String text) {
    // Simple word-based tokenization
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final tokens = <int>[];
    
    for (final word in words.take(_maxInputLength)) {
      // Simple hash-based tokenization
      tokens.add(word.hashCode % 1000);
    }
    
    // Pad or truncate to fixed length
    while (tokens.length < _maxInputLength) {
      tokens.add(0); // Padding token
    }
    
    return tokens.take(_maxInputLength).toList();
  }
  
  /// Create input tensor for model
  List<List<List<double>>> _createInputTensor(List<int> tokens) {
    return [[tokens.map((t) => t.toDouble()).toList()]];
  }
  
  /// Decode model output (simplified)
  String _decodeOutput(List<List<List<double>>> output) {
    // Simple decoding - in real implementation would use proper tokenizer
    final flatOutput = output.expand((e) => e).expand((e) => e).toList();
    final tokens = flatOutput.map((v) => v.round().toInt()).where((t) => t > 0 && t < 1000).take(50);
    
    // Convert tokens back to words (simplified)
    return tokens.map((t) => 'word$t').join(' ');
  }
  
  /// Decode command suggestions
  List<String> _decodeSuggestions(List<List<List<double>>> output) {
    final suggestions = <String>[];
    
    for (int i = 0; i < output[0].length; i++) {
      final suggestion = _decodeOutput([output[0][i]]);
      if (suggestion.isNotEmpty) {
        suggestions.add(suggestion);
      }
    }
    
    return suggestions.take(5).toList(); // Return top 5 suggestions
  }
  
  /// Analyze error patterns
  String _analyzeErrorPatterns(String errorText) {
    final patterns = {
      'permission denied': 'Permission denied. Try running with sudo or check file permissions.',
      'command not found': 'Command not found. Check if the command is installed and in your PATH.',
      'no such file': 'File or directory not found. Check the file path and spelling.',
      'connection refused': 'Connection refused. Check if the service is running and accessible.',
      'network unreachable': 'Network unreachable. Check your network connection.',
    };
    
    for (final pattern in patterns.entries) {
      if (errorText.toLowerCase().contains(pattern.key)) {
        return pattern.value;
      }
    }
    
    return 'Unknown error. Check the error message and try troubleshooting steps.';
  }
  
  /// Generate fallback response
  LocalAiResponse _generateFallbackResponse(String input, String type) {
    final responses = {
      'text': 'I understand you said: "$input". This is a fallback response as the local AI model is not available.',
      'code': '// Fallback code generation\n// You asked for: $input\n// Please install the AI models for better responses.',
      'command': 'echo "Fallback command suggestion for: $input"',
    };
    
    return LocalAiResponse.success(responses[type] ?? 'Fallback response');
  }
  
  /// Generate fallback code response
  LocalAiResponse _generateFallbackCodeResponse(String input) {
    final code = '''
// Fallback code generation
// Request: $input
// Note: Install local AI models for better code generation

function handleRequest() {
  console.log("Handling: $input");
  // Add your implementation here
}
''';
    
    return LocalAiResponse.success(code);
  }
  
  /// Generate fallback command suggestions
  LocalAiResponse _generateFallbackCommandSuggestions(String input) {
    final suggestions = [
      'echo "$input"',
      'ls -la',
      'pwd',
      'help',
      'man $input',
    ];
    
    return LocalAiResponse.success(suggestions.join('\n'));
  }
  
  /// Get cache key
  String _getCacheKey(String input, LocalAiCapability capability, String? context) {
    return '${capability.name}_${input.hashCode}_${context?.hashCode ?? 0}';
  }
  
  /// Cache response
  void _cacheResponse(String key, String response) {
    _responseCache[key] = response;
    _cacheTimestamps[key] = DateTime.now();
    
    // Limit cache size
    if (_responseCache.length > 100) {
      final oldestKey = _cacheTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _responseCache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
    }
  }
  
  /// Start cache cleanup timer
  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _cleanupCache();
    });
  }
  
  /// Clean up old cache entries
  void _cleanupCache() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));
    
    final keysToRemove = <String>[];
    for (final entry in _cacheTimestamps.entries) {
      if (entry.value.isBefore(cutoff)) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _responseCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      debugPrint('[local_ai] Cleaned up ${keysToRemove.length} cache entries');
    }
  }
  
  /// Check if capability is supported
  bool supportsCapability(LocalAiCapability capability) {
    return _supportedCapabilities.contains(capability);
  }
  
  /// Get system status
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _isInitialized,
      'modelsLoaded': _modelsLoaded,
      'modelPath': _modelPath,
      'supportedCapabilities': _supportedCapabilities.map((c) => c.name).toList(),
      'cacheSize': _responseCache.length,
    };
  }
  
  /// Dispose resources
  void dispose() {
    _cacheCleanupTimer?.cancel();
    _textModel?.close();
    _codeModel?.close();
    _commandModel?.close();
    _responseCache.clear();
    _cacheTimestamps.clear();
    _supportedCapabilities.clear();
    
    debugPrint('[local_ai] Local AI fallback disposed');
  }
}

/// Local AI capabilities
enum LocalAiCapability {
  textGeneration('text_generation'),
  codeGeneration('code_generation'),
  commandSuggestion('command_suggestion'),
  errorAnalysis('error_analysis'),
  textSummarization('text_summarization');
  
  const LocalAiCapability(this.name);
  final String name;
}

/// Local AI response
class LocalAiResponse {
  final bool success;
  final String? output;
  final String? error;
  final bool cached;
  final DateTime timestamp;
  
  const LocalAiResponse._({
    required this.success,
    this.output,
    this.error,
    this.cached = false,
    required this.timestamp,
  });
  
  factory LocalAiResponse.success(String output, {bool cached = false}) {
    return LocalAiResponse._(
      success: true,
      output: output,
      cached: cached,
      timestamp: DateTime.now(),
    );
  }
  
  factory LocalAiResponse.error(String error) {
    return LocalAiResponse._(
      success: false,
      error: error,
      timestamp: DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'success': success,
    'output': output,
    'error': error,
    'cached': cached,
    'timestamp': timestamp.toIso8601String(),
  };
}
