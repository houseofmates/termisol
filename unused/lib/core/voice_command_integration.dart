import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Voice command integration with Whisper backend
/// 
/// Features:
/// - Real-time speech-to-text using Whisper API at 192.168.4.250
/// - Voice command recognition and execution
/// - Natural language command processing
/// - Voice feedback and confirmation
/// - Multi-language support
/// - Command customization and training
class VoiceCommandIntegration {
  static const String _whisperEndpoint = 'http://192.168.4.250:8000/transcribe';
  static const Duration _recordingTimeout = Duration(seconds: 30);
  static const Duration _processingTimeout = Duration(seconds: 10);
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _bitDepth = 16;
  
  final Map<String, VoiceCommand> _commands = {};
  final Queue<VoiceCommandHistory> _commandHistory = Queue();
  final Map<String, CommandPattern> _patterns = {};
  final List<VoiceLanguage> _supportedLanguages = [];
  
  bool _isListening = false;
  bool _isProcessing = false;
  String _currentLanguage = 'en';
  double _confidenceThreshold = 0.7;
  
  int _totalCommands = 0;
  int _successfulCommands = 0;
  int _failedCommands = 0;
  double _totalProcessingTime = 0.0;

  VoiceCommandIntegration() {
    _initializeVoiceIntegration();
  }

  /// Initialize the voice integration system
  void _initializeVoiceIntegration() {
    _setupDefaultCommands();
    _setupCommandPatterns();
    _setupSupportedLanguages();
  }

  /// Setup default voice commands
  void _setupDefaultCommands() {
    // Terminal commands
    _commands['list_files'] = VoiceCommand(
      phrase: 'list files',
      action: 'ls -la',
      description: 'List files in current directory',
      category: CommandCategory.terminal,
      confidence: 0.9,
    );
    
    _commands['change_directory'] = VoiceCommand(
      phrase: 'change directory',
      action: 'cd',
      description: 'Change directory',
      category: CommandCategory.terminal,
      confidence: 0.9,
      parameters: ['directory'],
    );
    
    _commands['git_status'] = VoiceCommand(
      phrase: 'git status',
      action: 'git status',
      description: 'Show git repository status',
      category: CommandCategory.git,
      confidence: 0.95,
    );
    
    _commands['git_add'] = VoiceCommand(
      phrase: 'git add',
      action: 'git add',
      description: 'Add files to git staging',
      category: CommandCategory.git,
      confidence: 0.9,
      parameters: ['files'],
    );
    
    _commands['git_commit'] = VoiceCommand(
      phrase: 'git commit',
      action: 'git commit -m',
      description: 'Commit changes with message',
      category: CommandCategory.git,
      confidence: 0.9,
      parameters: ['message'],
    );
    
    // Application commands
    _commands['open_editor'] = VoiceCommand(
      phrase: 'open editor',
      action: 'edit',
      description: 'Open text editor',
      category: CommandCategory.application,
      confidence: 0.85,
      parameters: ['filename'],
    );
    
    _commands['search'] = VoiceCommand(
      phrase: 'search',
      action: 'grep -r',
      description: 'Search for text in files',
      category: CommandCategory.utility,
      confidence: 0.8,
      parameters: ['pattern', 'path'],
    );
    
    _commands['help'] = VoiceCommand(
      phrase: 'help',
      action: '/voice_help',
      description: 'Show voice command help',
      category: CommandCategory.system,
      confidence: 0.95,
    );
    
    // System commands
    _commands['monitor'] = VoiceCommand(
      phrase: 'monitor',
      action: '/monitor',
      description: 'Open performance monitor',
      category: CommandCategory.system,
      confidence: 0.9,
    );
    
    _commands['clear'] = VoiceCommand(
      phrase: 'clear',
      action: 'clear',
      description: 'Clear terminal screen',
      category: CommandCategory.terminal,
      confidence: 0.95,
    );
  }

  /// Setup command patterns
  void _setupCommandPatterns() {
    _patterns['navigate'] = CommandPattern(
      pattern: r'(go to|change to|cd|navigate to) (.+)',
      action: 'cd {2}',
      description: 'Navigate to directory',
    );
    
    _patterns['create_file'] = CommandPattern(
      pattern: r'(create|make|new) (file|document) (.+)',
      action: 'touch {3}',
      description: 'Create new file',
    );
    
    _patterns['create_directory'] = CommandPattern(
      pattern: r'(create|make|new) (directory|folder) (.+)',
      action: 'mkdir {3}',
      description: 'Create new directory',
    );
    
    _patterns['remove_file'] = CommandPattern(
      pattern: r'(remove|delete|rm) (file|) (.+)',
      action: 'rm {3}',
      description: 'Remove file',
    );
    
    _patterns['copy_file'] = CommandPattern(
      pattern: r'(copy|cp) (.+) (to|) (.+)',
      action: 'cp {2} {4}',
      description: 'Copy file',
    );
    
    _patterns['move_file'] = CommandPattern(
      pattern: r'(move|mv|rename) (.+) (to|) (.+)',
      action: 'mv {2} {4}',
      description: 'Move/rename file',
    );
  }

  /// Setup supported languages
  void _setupSupportedLanguages() {
    _supportedLanguages.add(VoiceLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      confidence: 0.9,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'es',
      name: 'Spanish',
      nativeName: 'Español',
      confidence: 0.8,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'fr',
      name: 'French',
      nativeName: 'Français',
      confidence: 0.8,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'de',
      name: 'German',
      nativeName: 'Deutsch',
      confidence: 0.8,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'it',
      name: 'Italian',
      nativeName: 'Italiano',
      confidence: 0.7,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'pt',
      name: 'Portuguese',
      nativeName: 'Português',
      confidence: 0.7,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'ru',
      name: 'Russian',
      nativeName: 'Русский',
      confidence: 0.7,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'zh',
      name: 'Chinese',
      nativeName: '中文',
      confidence: 0.6,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'ja',
      name: 'Japanese',
      nativeName: '日本語',
      confidence: 0.6,
    ));
    
    _supportedLanguages.add(VoiceLanguage(
      code: 'ko',
      name: 'Korean',
      nativeName: '한국어',
      confidence: 0.6,
    ));
  }

  /// Start voice listening
  Future<void> startListening() async {
    if (_isListening) return;
    
    _isListening = true;
    debugPrint('🎤 Voice command listening started');
    
    try {
      // Start recording audio
      final audioData = await _recordAudio();
      
      if (audioData.isNotEmpty) {
        _isProcessing = true;
        
        // Transcribe audio using Whisper
        final transcription = await _transcribeAudio(audioData);
        
        if (transcription.isNotEmpty) {
          // Process the transcribed text
          await _processVoiceCommand(transcription);
        }
        
        _isProcessing = false;
      }
    } catch (e) {
      debugPrint('Voice command failed: $e');
      _failedCommands++;
    } finally {
      _isListening = false;
    }
  }

  /// Record audio from microphone
  Future<Uint8List> _recordAudio() async {
    // This is a simplified implementation
    // In a real implementation, you would use a proper audio recording library
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Simulate audio recording
      await Future.delayed(Duration(seconds: 3));
      
      // Generate mock audio data (16-bit PCM, 16kHz, mono)
      final audioData = Uint8List(_sampleRate * _channels * _bitDepth ~/ 8 * 3); // 3 seconds
      
      // Fill with some mock data
      for (int i = 0; i < audioData.length; i++) {
        audioData[i] = Random().nextInt(256);
      }
      
      debugPrint('🎤 Audio recorded: ${audioData.length} bytes in ${stopwatch.elapsedMilliseconds}ms');
      
      return audioData;
    } catch (e) {
      debugPrint('Audio recording failed: $e');
      return Uint8List(0);
    } finally {
      stopwatch.stop();
    }
  }

  /// Transcribe audio using Whisper API
  Future<String> _transcribeAudio(Uint8List audioData) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_whisperEndpoint));
      
      // Add audio file
      request.files.add(http.MultipartFile.fromBytes(
        'audio',
        audioData,
        filename: 'audio.wav',
      ));
      
      // Add language parameter
      request.fields['language'] = _currentLanguage;
      
      // Send request
      final response = await request.send().timeout(_processingTimeout);
      
      // Get response
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);
      
      final transcription = responseData['text'] as String? ?? '';
      final confidence = (responseData['confidence'] as num?)?.toDouble() ?? 0.0;
      
      debugPrint('🎤 Transcription: "$transcription" (confidence: ${(confidence * 100).toStringAsFixed(1)}%)');
      debugPrint('⏱️ Transcription time: ${stopwatch.elapsedMilliseconds}ms');
      
      if (confidence >= _confidenceThreshold) {
        _totalCommands++;
        return transcription.toLowerCase().trim();
      } else {
        debugPrint('🎤 Low confidence transcription ignored');
        return '';
      }
    } catch (e) {
      debugPrint('Transcription failed: $e');
      return '';
    } finally {
      stopwatch.stop();
    }
  }

  /// Process voice command
  Future<void> _processVoiceCommand(String transcription) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Try to match exact commands first
      final exactMatch = _findExactCommand(transcription);
      if (exactMatch != null) {
        await _executeCommand(exactMatch, transcription);
        return;
      }
      
      // Try pattern matching
      final patternMatch = _findPatternMatch(transcription);
      if (patternMatch != null) {
        await _executePatternCommand(patternMatch, transcription);
        return;
      }
      
      // Try natural language processing
      final nlpResult = await _processNaturalLanguage(transcription);
      if (nlpResult.isNotEmpty) {
        await _executeCommand(nlpResult, transcription);
        return;
      }
      
      debugPrint('🎤 Unknown command: "$transcription"');
      _failedCommands++;
      
    } catch (e) {
      debugPrint('Command processing failed: $e');
      _failedCommands++;
    } finally {
      _totalProcessingTime += stopwatch.elapsedMilliseconds.toDouble();
      stopwatch.stop();
    }
  }

  /// Find exact command match
  VoiceCommand? _findExactCommand(String transcription) {
    for (final command in _commands.values) {
      if (transcription.contains(command.phrase)) {
        return command;
      }
    }
    return null;
  }

  /// Find pattern match
  CommandPattern? _findPatternMatch(String transcription) {
    for (final pattern in _patterns.values) {
      final regex = RegExp(pattern.pattern, caseSensitive: false);
      final match = regex.firstMatch(transcription);
      
      if (match != null) {
        return pattern;
      }
    }
    return null;
  }

  /// Process natural language command
  Future<String> _processNaturalLanguage(String transcription) async {
    // Simple natural language processing
    // In a real implementation, you would use an NLP service
    
    final lowerTranscription = transcription.toLowerCase();
    
    // Common command mappings
    if (lowerTranscription.contains('show') && lowerTranscription.contains('file')) {
      return 'ls -la';
    }
    
    if (lowerTranscription.contains('open') && lowerTranscription.contains('terminal')) {
      return 'gnome-terminal';
    }
    
    if (lowerTranscription.contains('run') && lowerTranscription.contains('test')) {
      return 'npm test';
    }
    
    if (lowerTranscription.contains('build') && lowerTranscription.contains('project')) {
      return 'make';
    }
    
    if (lowerTranscription.contains('install') && lowerTranscription.contains('package')) {
      return 'npm install';
    }
    
    if (lowerTranscription.contains('push') && lowerTranscription.contains('git')) {
      return 'git push';
    }
    
    if (lowerTranscription.contains('pull') && lowerTranscription.contains('git')) {
      return 'git pull';
    }
    
    if (lowerTranscription.contains('branch') && lowerTranscription.contains('git')) {
      return 'git branch';
    }
    
    if (lowerTranscription.contains('merge') && lowerTranscription.contains('git')) {
      return 'git merge';
    }
    
    return '';
  }

  /// Execute voice command
  Future<void> _executeCommand(VoiceCommand command, String transcription) async {
    try {
      _successfulCommands++;
      
      // Extract parameters from transcription
      final parameters = _extractParameters(command, transcription);
      
      // Build command string
      String commandString = command.action;
      for (final param in parameters) {
        commandString += ' $param';
      }
      
      // Record command in history
      _commandHistory.add(VoiceCommandHistory(
        transcription: transcription,
        command: commandString,
        timestamp: DateTime.now(),
        success: true,
      ));
      
      debugPrint('🎤 Executing: $commandString');
      
      // Execute command (this would be handled by the terminal session)
      await _executeInTerminal(commandString);
      
      // Provide voice feedback
      await _provideFeedback('Command executed: ${command.description}');
      
    } catch (e) {
      debugPrint('Command execution failed: $e');
      _failedCommands++;
      
      // Record failure in history
      _commandHistory.add(VoiceCommandHistory(
        transcription: transcription,
        command: command.action,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      ));
    }
  }

  /// Execute pattern command
  Future<void> _executePatternCommand(CommandPattern pattern, String transcription) async {
    try {
      _successfulCommands++;
      
      // Extract parameters using regex
      final regex = RegExp(pattern.pattern, caseSensitive: false);
      final match = regex.firstMatch(transcription);
      
      if (match != null) {
        // Replace parameter references with actual values
        String commandString = pattern.action;
        for (int i = 1; i < match.groupCount; i++) {
          commandString = commandString.replace('{$i}', match.group(i) ?? '');
        }
        
        // Record command in history
        _commandHistory.add(VoiceCommandHistory(
          transcription: transcription,
          command: commandString,
          timestamp: DateTime.now(),
          success: true,
        ));
        
        debugPrint('🎤 Executing pattern: $commandString');
        
        // Execute command
        await _executeInTerminal(commandString);
        
        // Provide voice feedback
        await _provideFeedback('${pattern.description} executed');
      }
      
    } catch (e) {
      debugPrint('Pattern command execution failed: $e');
      _failedCommands++;
    }
  }

  /// Extract parameters from transcription
  List<String> _extractParameters(VoiceCommand command, String transcription) {
    final parameters = <String>[];
    
    // Simple parameter extraction
    if (command.parameters.contains('directory')) {
      final match = RegExp(r'(?:to|in|into)\s+(.+?)(?:\s|$)').firstMatch(transcription);
      if (match != null) {
        parameters.add(match.group(1) ?? '');
      }
    }
    
    if (command.parameters.contains('filename')) {
      final match = RegExp(r'(?:file|document)\s+(.+?)(?:\s|$)').firstMatch(transcription);
      if (match != null) {
        parameters.add(match.group(1) ?? '');
      }
    }
    
    if (command.parameters.contains('files')) {
      final match = RegExp(r'files?\s+(.+?)(?:\s|$)').firstMatch(transcription);
      if (match != null) {
        parameters.add(match.group(1) ?? '');
      }
    }
    
    if (command.parameters.contains('message')) {
      final match = RegExp(r'(?:message|commit message)\s+["\']?(.+?)["\']?(?:\s|$)').firstMatch(transcription);
      if (match != null) {
        parameters.add('"${match.group(1) ?? ''}"');
      }
    }
    
    return parameters;
  }

  /// Execute command in terminal
  Future<void> _executeInTerminal(String command) async {
    // This would integrate with the terminal session
    debugPrint('Executing in terminal: $command');
    
    // Simulate command execution
    await Future.delayed(Duration(milliseconds: 100));
  }

  /// Provide voice feedback
  Future<void> _provideFeedback(String message) async {
    // This would use text-to-speech to provide feedback
    debugPrint('🔊 Voice feedback: $message');
  }

  /// Stop voice listening
  void stopListening() {
    _isListening = false;
    debugPrint('🎤 Voice command listening stopped');
  }

  /// Set language
  void setLanguage(String languageCode) {
    final language = _supportedLanguages.where((l) => l.code == languageCode).firstOrNull;
    if (language != null) {
      _currentLanguage = languageCode;
      debugPrint('🎤 Voice language set to: ${language.name}');
    }
  }

  /// Set confidence threshold
  void setConfidenceThreshold(double threshold) {
    _confidenceThreshold = threshold.clamp(0.0, 1.0);
    debugPrint('🎤 Confidence threshold set to: ${(_confidenceThreshold * 100).toStringAsFixed(1)}%');
  }

  /// Add custom command
  void addCommand(VoiceCommand command) {
    _commands[command.phrase] = command;
    debugPrint('🎤 Added custom command: ${command.phrase}');
  }

  /// Remove command
  void removeCommand(String phrase) {
    _commands.remove(phrase);
    debugPrint('🎤 Removed command: $phrase');
  }

  /// Get command history
  List<VoiceCommandHistory> getCommandHistory({int? limit}) {
    final history = _commandHistory.reversed.toList();
    if (limit != null) {
      return history.take(limit).toList();
    }
    return history;
  }

  /// Get available commands
  Map<String, VoiceCommand> getAvailableCommands() {
    return Map.unmodifiable(_commands);
  }

  /// Get supported languages
  List<VoiceLanguage> getSupportedLanguages() {
    return List.unmodifiable(_supportedLanguages);
  }

  /// Get voice command statistics
  VoiceCommandStats getStats() {
    return VoiceCommandStats(
      totalCommands: _totalCommands,
      successfulCommands: _successfulCommands,
      failedCommands: _failedCommands,
      successRate: _totalCommands > 0 ? _successfulCommands / _totalCommands : 0.0,
      averageProcessingTime: _totalCommands > 0 ? _totalProcessingTime / _totalCommands : 0.0,
      totalProcessingTime: _totalProcessingTime,
      currentLanguage: _currentLanguage,
      confidenceThreshold: _confidenceThreshold,
      commandCount: _commands.length,
      historySize: _commandHistory.length,
      isListening: _isListening,
      isProcessing: _isProcessing,
    );
  }

  /// Clear command history
  void clearHistory() {
    _commandHistory.clear();
  }

  /// Dispose voice integration
  void dispose() {
    stopListening();
    clearHistory();
    _commands.clear();
    _patterns.clear();
    _supportedLanguages.clear();
  }
}

/// Voice command
class VoiceCommand {
  final String phrase;
  final String action;
  final String description;
  final CommandCategory category;
  final double confidence;
  final List<String> parameters;

  const VoiceCommand({
    required this.phrase,
    required this.action,
    required this.description,
    required this.category,
    required this.confidence,
    this.parameters = const [],
  });
}

/// Command pattern
class CommandPattern {
  final String pattern;
  final String action;
  final String description;

  const CommandPattern({
    required this.pattern,
    required this.action,
    required this.description,
  });
}

/// Voice command history
class VoiceCommandHistory {
  final String transcription;
  final String command;
  final DateTime timestamp;
  final bool success;
  final String? error;

  const VoiceCommandHistory({
    required this.transcription,
    required this.command,
    required this.timestamp,
    required this.success,
    this.error,
  });
}

/// Voice language
class VoiceLanguage {
  final String code;
  final String name;
  final String nativeName;
  final double confidence;

  const VoiceLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.confidence,
  });
}

/// Voice command statistics
class VoiceCommandStats {
  final int totalCommands;
  final int successfulCommands;
  final int failedCommands;
  final double successRate;
  final double averageProcessingTime;
  final double totalProcessingTime;
  final String currentLanguage;
  final double confidenceThreshold;
  final int commandCount;
  final int historySize;
  final bool isListening;
  final bool isProcessing;

  const VoiceCommandStats({
    required this.totalCommands,
    required this.successfulCommands,
    required this.failedCommands,
    required this.successRate,
    required this.averageProcessingTime,
    required this.totalProcessingTime,
    required this.currentLanguage,
    required this.confidenceThreshold,
    required this.commandCount,
    required this.historySize,
    required this.isListening,
    required this.isProcessing,
  });
}

/// Command categories
enum CommandCategory {
  terminal,
  git,
  application,
  utility,
  system,
  file,
  network,
  development,
}
