import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Intelligent Command Prediction and Auto-Completion
/// 
/// Implements smart command completion:
/// - Context-aware suggestions
/// - Machine learning predictions
/// - Command history analysis
/// - Fuzzy matching algorithms
/// - Workspace-specific completions
/// - Real-time learning from usage
/// - Multi-language support
class IntelligentCommandCompletion {
  bool _isInitialized = false;
  
  // Command history and analytics
  final List<CommandEntry> _commandHistory = [];
  final Map<String, int> _commandFrequency = {};
  final Map<String, List<String>> _commandContexts = {};
  final Map<String, CommandPattern> _patterns = {};
  
  // Machine learning models
  final Map<String, double> _commandWeights = {};
  final Map<String, List<String>> _commandAssociations = {};
  final Map<String, CommandContext> _contexts = {};
  
  // Current completion state
  String _currentInput = '';
  List<CommandSuggestion> _suggestions = [];
  String _currentWorkspace = '';
  String _currentLanguage = '';
  Timer? _debounceTimer;
  
  // Event handlers
  final List<Function(List<CommandSuggestion>)> _onSuggestionsUpdated = [];
  final List<Function(CommandSuggestion)> _onSuggestionSelected = [];
  final List<Function(String)> _onContextChanged = [];
  
  IntelligentCommandCompletion();
  
  bool get isInitialized => _isInitialized;
  List<CommandSuggestion> get suggestions => List.unmodifiable(_suggestions);
  String get currentInput => _currentInput;
  Map<String, int> get commandFrequency => Map.unmodifiable(_commandFrequency);
  
  /// Initialize command completion system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load existing data
      await _loadCommandHistory();
      await _loadCommandPatterns();
      await _loadMachineLearningModels();
      
      _isInitialized = true;
      debugPrint('🧠 Intelligent Command Completion initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Command Completion: $e');
      rethrow;
    }
  }
  
  /// Load command history
  Future<void> _loadCommandHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/command_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content);
        
        final historyData = data['history'] as List? ?? [];
        for (final entryData in historyData) {
          final entry = CommandEntry.fromJson(entryData);
          _commandHistory.add(entry);
          
          // Update frequency
          _commandFrequency[entry.command] = 
              (_commandFrequency[entry.command] ?? 0) + 1;
          
          // Update contexts
          _updateCommandContext(entry);
        }
        
        debugPrint('🧠 Loaded ${_commandHistory.length} command history entries');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load command history: $e');
    }
  }
  
  /// Load command patterns
  Future<void> _loadCommandPatterns() async {
    try {
      final patternsFile = File('${Platform.environment['HOME']}/.termisol/command_patterns.json');
      if (await patternsFile.exists()) {
        final content = await patternsFile.readAsString();
        final data = jsonDecode(content);
        
        final patternsData = data['patterns'] as Map? ?? {};
        for (final entry in patternsData.entries) {
          final pattern = CommandPattern.fromJson(entry.value);
          _patterns[entry.key] = pattern;
        }
        
        debugPrint('🧠 Loaded ${_patterns.length} command patterns');
      } else {
        await _createDefaultPatterns();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load command patterns: $e');
      await _createDefaultPatterns();
    }
  }
  
  /// Create default command patterns
  Future<void> _createDefaultPatterns() async {
    final defaultPatterns = {
      'git_commands': CommandPattern(
        pattern: r'^git\s+(.*)',
        type: PatternType.git,
        suggestions: ['status', 'add', 'commit', 'push', 'pull', 'branch', 'merge', 'checkout'],
        context: 'version_control',
        weight: 1.0,
      ),
      'flutter_commands': CommandPattern(
        pattern: r'^flutter\s+(.*)',
        type: PatternType.flutter,
        suggestions: ['run', 'build', 'test', 'clean', 'pub', 'doctor', 'upgrade', 'analyze', 'format'],
        context: 'development',
        weight: 1.0,
      ),
      'npm_commands': CommandPattern(
        pattern: r'^npm\s+(.*)',
        type: PatternType.nodejs,
        suggestions: ['install', 'run', 'start', 'build', 'test', 'clean', 'publish'],
        context: 'package_manager',
        weight: 1.0,
      ),
      'python_commands': CommandPattern(
        pattern: r'^(python|pip)\s+(.*)',
        type: PatternType.python,
        suggestions: ['run', 'install', 'list', 'show', 'freeze', 'uninstall', 'check'],
        context: 'development',
        weight: 1.0,
      ),
      'docker_commands': CommandPattern(
        pattern: r'^docker\s+(.*)',
        type: PatternType.docker,
        suggestions: ['run', 'build', 'push', 'pull', 'exec', 'logs', 'ps', 'stop', 'rm'],
        context: 'container_management',
        weight: 1.0,
      ),
      'file_operations': CommandPattern(
        pattern: r'^(ls|cd|mkdir|rm|cp|mv|find|grep|cat|less|vim|nano)\s*(.*)',
        type: PatternType.file,
        suggestions: ['*.txt', '*.md', '*.json', '*.yaml', '*.yml', '*.dart', '*.py', '*.js'],
        context: 'file_operations',
        weight: 0.8,
      ),
    };
    
    _patterns.addAll(defaultPatterns);
    await _saveCommandPatterns();
  }
  
  /// Load machine learning models
  Future<void> _loadMachineLearningModels() async {
    try {
      final modelsFile = File('${Platform.environment['HOME']}/.termisol/ml_models.json');
      if (await modelsFile.exists()) {
        final content = await modelsFile.readAsString();
        final data = jsonDecode(content);
        
        // Load command weights
        final weightsData = data['command_weights'] as Map? ?? {};
        for (final entry in weightsData.entries) {
          _commandWeights[entry.key] = entry.value.toDouble();
        }
        
        // Load command associations
        final associationsData = data['command_associations'] as Map? ?? {};
        for (final entry in associationsData.entries) {
          _commandAssociations[entry.key] = List<String>.from(entry.value);
        }
        
        // Load contexts
        final contextsData = data['contexts'] as Map? ?? {};
        for (final entry in contextsData.entries) {
          final context = CommandContext.fromJson(entry.value);
          _contexts[entry.key] = context;
        }
        
        debugPrint('🧠 Loaded ML models with ${_commandWeights.length} weights, ${_commandAssociations.length} associations');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load ML models: $e');
    }
  }
  
  /// Update command context
  void _updateCommandContext(CommandEntry entry) {
    final words = entry.command.split(' ');
    
    for (int i = 0; i < words.length - 1; i++) {
      final key = '${words[i]} ${words[i + 1]}';
      
      if (!_commandContexts.containsKey(key)) {
        _commandContexts[key] = <String>[];
      }
      
      _commandContexts[key]!.add(entry.command);
    }
  }
  
  /// Get command suggestions
  Future<List<CommandSuggestion>> getSuggestions(String input) async {
    _currentInput = input;
    
    // Clear previous suggestions
    _suggestions.clear();
    
    // Cancel previous debounce timer
    _debounceTimer?.cancel();
    
    // Debounce suggestions
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _generateSuggestions(input);
    });
    
    return _suggestions;
  }
  
  /// Generate suggestions
  void _generateSuggestions(String input) {
    final words = input.split(' ');
    final lastWord = words.isNotEmpty ? words.last : '';
    
    // Get suggestions from multiple sources
    final historySuggestions = _getHistorySuggestions(input);
    final patternSuggestions = _getPatternSuggestions(lastWord);
    final mlSuggestions = _getMachineLearningSuggestions(input);
    final fuzzySuggestions = _getFuzzySuggestions(lastWord);
    final workspaceSuggestions = _getWorkspaceSuggestions(lastWord);
    
    // Combine and rank suggestions
    final allSuggestions = <CommandSuggestion>[];
    allSuggestions.addAll(historySuggestions);
    allSuggestions.addAll(patternSuggestions);
    allSuggestions.addAll(mlSuggestions);
    allSuggestions.addAll(fuzzySuggestions);
    allSuggestions.addAll(workspaceSuggestions);
    
    // Remove duplicates and sort by score
    final uniqueSuggestions = <String, CommandSuggestion>{};
    for (final suggestion in allSuggestions) {
      final key = '${suggestion.command}_${suggestion.type}';
      if (!uniqueSuggestions.containsKey(key)) {
        uniqueSuggestions[key] = suggestion;
      }
    }
    
    _suggestions = uniqueSuggestions.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    
    // Limit to top 10 suggestions
    if (_suggestions.length > 10) {
      _suggestions = _suggestions.take(10).toList();
    }
    
    _onSuggestionsUpdated.forEach((callback) => callback(_suggestions));
    
    debugPrint('🧠 Generated ${_suggestions.length} suggestions for: "$input"');
  }
  
  /// Get history-based suggestions
  List<CommandSuggestion> _getHistorySuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    final words = input.split(' ');
    final lastWord = words.isNotEmpty ? words.last : '';
    
    // Find similar commands in history
    for (final entry in _commandHistory.reversed.take(50))) {
      if (entry.command.startsWith(input) || 
          entry.command.contains(lastWord)) {
        final score = _calculateHistoryScore(entry, input, lastWord);
        suggestions.add(CommandSuggestion(
          command: entry.command,
          type: SuggestionType.history,
          score: score,
          description: 'Previously used command',
          context: entry.context ?? '',
          frequency: _commandFrequency[entry.command] ?? 0,
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Get pattern-based suggestions
  List<CommandSuggestion> _getPatternSuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    
    for (final pattern in _patterns.values) {
      final match = RegExp(pattern.pattern).firstMatch(input);
      if (match != null) {
        for (final suggestion in pattern.suggestions) {
          final score = _calculatePatternScore(pattern, input, suggestion);
          suggestions.add(CommandSuggestion(
            command: '${pattern.pattern.split(r'\s+')[0]} $suggestion',
            type: SuggestionType.pattern,
            score: score,
            description: 'Pattern-based suggestion',
            context: pattern.context,
            frequency: 0,
          ));
        }
      }
    }
    
    return suggestions;
  }
  
  /// Get machine learning suggestions
  List<CommandSuggestion> _getMachineLearningSuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    final words = input.split(' ');
    final lastWord = words.isNotEmpty ? words.last : '';
    
    // Find similar commands using ML models
    for (final entry in _commandWeights.entries) {
      final similarity = _calculateSimilarity(input, entry.key);
      if (similarity > 0.3) {
        final score = similarity * entry.value;
        suggestions.add(CommandSuggestion(
          command: entry.key,
          type: SuggestionType.machine_learning,
          score: score,
          description: 'ML-based suggestion',
          context: 'learned',
          frequency: _commandFrequency[entry.key] ?? 0,
        ));
      }
    }
    
    // Use command associations
    for (final entry in _commandAssociations.entries) {
      if (entry.key.contains(lastWord)) {
        for (final associatedCommand in entry.value) {
          final score = _calculateAssociationScore(input, associatedCommand);
          suggestions.add(CommandSuggestion(
            command: associatedCommand,
            type: SuggestionType.association,
            score: score,
            description: 'Associated command',
            context: 'association',
            frequency: _commandFrequency[associatedCommand] ?? 0,
          ));
        }
      }
    }
    
    return suggestions;
  }
  
  /// Get fuzzy suggestions
  List<CommandSuggestion> _getFuzzySuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    
    // Simple fuzzy matching against command history
    for (final entry in _commandHistory) {
      final distance = _levenshteinDistance(input.toLowerCase(), entry.command.toLowerCase());
      if (distance <= 2 && entry.command.length <= input.length + 3) {
        final score = 1.0 - (distance / 10.0);
        suggestions.add(CommandSuggestion(
          command: entry.command,
          type: SuggestionType.fuzzy,
          score: score,
          description: 'Fuzzy match',
          context: entry.context ?? '',
          frequency: _commandFrequency[entry.command] ?? 0,
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Get workspace-specific suggestions
  List<CommandSuggestion> _getWorkspaceSuggestions(String input) {
    final suggestions = <CommandSuggestion>[];
    
    // Check current workspace context
    final context = _contexts[_currentWorkspace];
    if (context != null) {
      for (final command in context.commonCommands) {
        if (command.startsWith(input) || command.contains(input)) {
          suggestions.add(CommandSuggestion(
            command: command,
            type: SuggestionType.workspace,
            score: 0.9,
            description: 'Workspace-specific command',
            context: _currentWorkspace,
            frequency: _commandFrequency[command] ?? 0,
          ));
        }
      }
    }
    
    return suggestions;
  }
  
  /// Calculate history score
  double _calculateHistoryScore(CommandEntry entry, String input, String lastWord) {
    double score = 0.0;
    
    // Exact match gets highest score
    if (entry.command == input) {
      score += 1.0;
    }
    
    // Boost score for recent usage
    final hoursSince = DateTime.now().difference(entry.timestamp).inHours;
    if (hoursSince < 1) {
      score += 0.5;
    } else if (hoursSince < 24) {
      score += 0.3;
    } else if (hoursSince < 168) {
      score += 0.1;
    }
    
    // Boost score for frequency
    final frequency = _commandFrequency[entry.command] ?? 0;
    score += (frequency / 100.0);
    
    return score;
  }
  
  /// Calculate pattern score
  double _calculatePatternScore(CommandPattern pattern, String input, String suggestion) {
    double score = pattern.weight;
    
    // Boost score for exact pattern match
    if (RegExp(pattern.pattern).hasMatch(input)) {
      score += 0.5;
    }
    
    // Boost score for common suggestions
    if (pattern.suggestions.contains(suggestion)) {
      score += 0.2;
    }
    
    return score;
  }
  
  /// Calculate similarity score
  double _calculateSimilarity(String str1, String str2) {
    // Simple similarity calculation (can be enhanced with proper ML)
    final longer = str1.length > str2.length ? str1 : str2;
    final shorter = str1.length > str2.length ? str2 : str1;
    
    int matches = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (longer.contains(shorter[i])) {
        matches++;
      }
    }
    
    return matches / shorter.length;
  }
  
  /// Calculate association score
  double _calculateAssociationScore(String input, String command) {
    double score = 0.5;
    
    // Boost score if input contains association trigger
    if (input.contains(command)) {
      score += 0.5;
    }
    
    return score;
  }
  
  /// Calculate Levenshtein distance
  int _levenshteinDistance(String str1, String str2) {
    final matrix = List.generate(
      str2.length + 1,
      (i) => List.generate(str1.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= str1.length; i++) {
      matrix[0][i] = i;
    }
    
    for (int j = 0; j <= str2.length; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= str1.length; i++) {
      for (int j = 1; j <= str2.length; j++) {
        final cost = str1[i - 1] == str2[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + cost,
        );
      }
    }
    
    return matrix[str1.length][str2.length];
  }
  
  /// Select suggestion
  Future<void> selectSuggestion(CommandSuggestion suggestion) async {
    // Update machine learning models
    await _updateMachineLearningModels(suggestion);
    
    // Add to command history
    final entry = CommandEntry(
      command: suggestion.command,
      timestamp: DateTime.now(),
      context: suggestion.context,
      workspace: _currentWorkspace,
      language: _currentLanguage,
    );
    
    _commandHistory.insert(0, entry);
    
    // Update frequency
    _commandFrequency[suggestion.command] = 
        (_commandFrequency[suggestion.command] ?? 0) + 1;
    
    // Save updated models
    await _saveCommandHistory();
    await _saveMachineLearningModels();
    
    _onSuggestionSelected.forEach((callback) => callback(suggestion));
    
    debugPrint('🧠 Selected suggestion: ${suggestion.command}');
  }
  
  /// Update machine learning models
  Future<void> _updateMachineLearningModels(CommandSuggestion suggestion) async {
    // Update command weights based on usage
    final currentWeight = _commandWeights[suggestion.command] ?? 0.5;
    final newWeight = math.min(1.0, currentWeight + 0.1);
    _commandWeights[suggestion.command] = newWeight;
    
    // Update command associations
    if (!_commandAssociations.containsKey(suggestion.command)) {
      _commandAssociations[suggestion.command] = [];
    }
    
    // Add context associations
    final words = suggestion.command.split(' ');
    for (int i = 0; i < words.length - 1; i++) {
      final key = '${words[i]} ${words[i + 1]}';
      
      if (!_commandAssociations.containsKey(key)) {
        _commandAssociations[key] = [];
      }
      
      if (!_commandAssociations[key]!.contains(suggestion.command)) {
        _commandAssociations[key]!.add(suggestion.command);
      }
    }
  }
  
  /// Update workspace context
  void updateWorkspace(String workspace) {
    _currentWorkspace = workspace;
    _onContextChanged.forEach((callback) => callback(workspace));
    debugPrint('🧠 Updated workspace context: $workspace');
  }
  
  /// Update language context
  void updateLanguage(String language) {
    _currentLanguage = language;
    debugPrint('🧠 Updated language context: $language');
  }
  
  /// Get command statistics
  Map<String, dynamic> getStatistics() {
    final totalCommands = _commandHistory.length;
    final uniqueCommands = _commandFrequency.keys.length;
    final avgFrequency = totalCommands > 0 
        ? totalCommands / uniqueCommands 
        : 0.0;
    
    final mostUsed = _commandFrequency.entries.isNotEmpty
        ? _commandFrequency.entries.reduce((a, b) => a.value > b.value ? a : b)
        : null;
    
    return {
      'total_commands': totalCommands,
      'unique_commands': uniqueCommands,
      'average_frequency': avgFrequency,
      'most_used_command': mostUsed?.key,
      'most_used_count': mostUsed?.value,
      'patterns_loaded': _patterns.length,
      'ml_weights_count': _commandWeights.length,
      'associations_count': _commandAssociations.length,
      'contexts_count': _contexts.length,
      'current_workspace': _currentWorkspace,
      'current_language': _currentLanguage,
    };
  }
  
  /// Save command history
  Future<void> _saveCommandHistory() async {
    try {
      final historyData = _commandHistory
          .take(1000)
          .map((entry) => entry.toJson())
          .toList();
      
      final data = {
        'version': '1.0',
        'history': historyData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final historyFile = File('${Platform.environment['HOME']}/.termisol/command_history.json');
      await historyFile.parent.create(recursive: true);
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save command history: $e');
    }
  }
  
  /// Save command patterns
  Future<void> _saveCommandPatterns() async {
    try {
      final patternsData = _patterns.map((k, v) => MapEntry(k, v.toJson())).toList();
      final data = {
        'version': '1.0',
        'patterns': patternsData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final patternsFile = File('${Platform.environment['HOME']}/.termisol/command_patterns.json');
      await patternsFile.parent.create(recursive: true);
      await patternsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save command patterns: $e');
    }
  }
  
  /// Save machine learning models
  Future<void> _saveMachineLearningModels() async {
    try {
      final weightsData = _commandWeights.map((k, v) => MapEntry(k, v));
      final associationsData = _commandAssociations.map((k, v) => MapEntry(k, v));
      final contextsData = _contexts.map((k, v) => MapEntry(k, v.toJson()));
      
      final data = {
        'version': '1.0',
        'command_weights': weightsData,
        'command_associations': associationsData,
        'contexts': contextsData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final modelsFile = File('${Platform.environment['HOME']}/.termisol/ml_models.json');
      await modelsFile.parent.create(recursive: true);
      await modelsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save ML models: $e');
    }
  }
  
  /// Clear command history
  Future<void> clearHistory() async {
    _commandHistory.clear();
    _commandFrequency.clear();
    _commandContexts.clear();
    await _saveCommandHistory();
    debugPrint('🗑️ Cleared command history');
  }
  
  /// Export training data
  Future<String> exportTrainingData() async {
    final exportData = {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'command_history': _commandHistory.map((e) => e.toJson()).toList(),
      'command_frequency': _commandFrequency,
      'command_patterns': _patterns.map((k, v) => MapEntry(k, v.toJson())).toList(),
      'machine_learning_weights': _commandWeights,
      'command_associations': _commandAssociations,
      'contexts': _contexts.map((k, v) => MapEntry(k, v.toJson())).toList(),
    };
    
    return jsonEncode(exportData);
  }
  
  /// Import training data
  Future<bool> importTrainingData(String trainingData) async {
    try {
      final data = jsonDecode(trainingData);
      
      // Import command history
      if (data.containsKey('command_history')) {
        final historyData = data['command_history'] as List? ?? [];
        for (final entryData in historyData) {
          final entry = CommandEntry.fromJson(entryData);
          _commandHistory.add(entry);
          
          // Update frequency
          _commandFrequency[entry.command] = 
              (_commandFrequency[entry.command] ?? 0) + 1;
          
          // Update contexts
          _updateCommandContext(entry);
        }
      }
      
      // Import ML models
      if (data.containsKey('machine_learning_weights')) {
        final weightsData = data['machine_learning_weights'] as Map? ?? {};
        for (final entry in weightsData.entries) {
          _commandWeights[entry.key] = entry.value.toDouble();
        }
      }
      
      await _saveCommandHistory();
      await _saveMachineLearningModels();
      
      debugPrint('📥 Imported training data');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import training data: $e');
      return false;
    }
  }
  
  /// Add suggestions updated listener
  void addSuggestionsUpdatedListener(Function(List<CommandSuggestion>) listener) {
    _onSuggestionsUpdated.add(listener);
  }
  
  /// Add suggestion selected listener
  void addSuggestionSelectedListener(Function(CommandSuggestion) listener) {
    _onSuggestionSelected.add(listener);
  }
  
  /// Add context changed listener
  void addContextChangedListener(Function(String) listener) {
    _onContextChanged.add(listener);
  }
  
  /// Remove suggestions updated listener
  void removeSuggestionsUpdatedListener(Function(List<CommandSuggestion>) listener) {
    _onSuggestionsUpdated.remove(listener);
  }
  
  /// Remove suggestion selected listener
  void removeSuggestionSelectedListener(Function(CommandSuggestion) listener) {
    _onSuggestionSelected.remove(listener);
  }
  
  /// Remove context changed listener
  void removeContextChangedListener(Function(String) listener) {
    _onContextChanged.remove(listener);
  }
  
  /// Dispose command completion system
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    
    // Save final state
    await _saveCommandHistory();
    await _saveMachineLearningModels();
    
    // Clear listeners
    _onSuggestionsUpdated.clear();
    _onSuggestionSelected.clear();
    _onContextChanged.clear();
    
    _isInitialized = false;
    debugPrint('🧠 Intelligent Command Completion disposed');
  }
}

/// Command entry model
class CommandEntry {
  final String command;
  final DateTime timestamp;
  final String? context;
  final String? workspace;
  final String? language;
  final Map<String, dynamic>? metadata;
  
  CommandEntry({
    required this.command,
    required this.timestamp,
    this.context,
    this.workspace,
    this.language,
    this.metadata,
  });
  
  factory CommandEntry.fromJson(Map<String, dynamic> json) {
    return CommandEntry(
      command: json['command'],
      timestamp: DateTime.parse(json['timestamp']),
      context: json['context'],
      workspace: json['workspace'],
      language: json['language'],
      metadata: json['metadata'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'command': command,
      'timestamp': timestamp.toIso8601String(),
      'context': context,
      'workspace': workspace,
      'language': language,
      'metadata': metadata,
    };
  }
}

/// Command pattern model
class CommandPattern {
  final String pattern;
  final PatternType type;
  final List<String> suggestions;
  final String context;
  final double weight;
  
  CommandPattern({
    required this.pattern,
    required this.type,
    required this.suggestions,
    required this.context,
    required this.weight,
  });
  
  factory CommandPattern.fromJson(Map<String, dynamic> json) {
    return CommandPattern(
      pattern: json['pattern'],
      type: PatternType.values.firstWhere(
        (p) => p.toString() == json['type'],
        orElse: () => PatternType.general,
      ),
      suggestions: List<String>.from(json['suggestions'] ?? []),
      context: json['context'],
      weight: (json['weight'] ?? 1.0).toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'pattern': pattern,
      'type': type.toString(),
      'suggestions': suggestions,
      'context': context,
      'weight': weight,
    };
  }
}

/// Pattern types
enum PatternType {
  git,
  flutter,
  nodejs,
  python,
  docker,
  file,
  general,
}

/// Command context model
class CommandContext {
  final String name;
  final String description;
  final List<String> commonCommands;
  final List<String> fileTypes;
  final List<String> tools;
  final Map<String, dynamic> settings;
  
  CommandContext({
    required this.name,
    required this.description,
    required this.commonCommands,
    required this.fileTypes,
    required this.tools,
    required this.settings,
  });
  
  factory CommandContext.fromJson(Map<String, dynamic> json) {
    return CommandContext(
      name: json['name'],
      description: json['description'],
      commonCommands: List<String>.from(json['common_commands'] ?? []),
      fileTypes: List<String>.from(json['file_types'] ?? []),
      tools: List<String>.from(json['tools'] ?? []),
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'common_commands': commonCommands,
      'file_types': fileTypes,
      'tools': tools,
      'settings': settings,
    };
  }
}

/// Command suggestion model
class CommandSuggestion {
  final String command;
  final SuggestionType type;
  final double score;
  final String description;
  final String context;
  final int frequency;
  
  CommandSuggestion({
    required this.command,
    required this.type,
    required this.score,
    required this.description,
    required this.context,
    required this.frequency,
  });
}

/// Suggestion types
enum SuggestionType {
  history,
  pattern,
  machine_learning,
  fuzzy,
  workspace,
  association,
}
