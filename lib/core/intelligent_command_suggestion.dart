import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class IntelligentCommandSuggestion {
  static const String _suggestionsFile = '/home/house/.termisol_suggestions.json';
  static const String _patternsFile = '/home/house/.termisol_command_patterns.json';
  static const int _maxSuggestions = 1000;
  static const int _maxPatterns = 500;
  static const int _maxHistory = 10000;
  
  final Map<String, CommandSuggestion> _suggestions = {};
  final Map<String, CommandPattern> _patterns = {};
  final List<CommandHistory> _history = [];
  final Map<String, ContextProfile> _contexts = {};
  final Map<String, double> _commandFrequencies = {};
  final Map<String, DateTime> _lastUsed = {};
  
  Timer? _cleanupTimer;
  Timer? _analysisTimer;
  int _totalSuggestions = 0;
  int _totalPatterns = 0;
  
  final StreamController<SuggestionEvent> _suggestionController = 
      StreamController<SuggestionEvent>.broadcast();

  void initialize() {
    _loadSuggestions();
    _loadPatterns();
    _loadHistory();
    _initializeDefaultPatterns();
    _startTimers();
    developer.log('🧠 intelligent Command Suggestion initialized');
  }

  void _loadSuggestions() {
    try {
      final file = File(_suggestionsFile);
      if (!file.existsSync()) {
        developer.log('🧠 Nno existing suggestions file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['suggestions']) {
        final suggestion = CommandSuggestion.fromJson(entry);
        _suggestions[suggestion.id] = suggestion;
        _totalSuggestions++;
      }
      
      developer.log('🧠 loaded ${_suggestions.length} suggestions');
      
    } catch (e) {
      developer.log('🧠 failed to load suggestions: $e');
    }
  }

  void _loadPatterns() {
    try {
      final file = File(_patternsFile);
      if (!file.existsSync()) {
        developer.log('🧠 no existing patterns file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['patterns']) {
        final pattern = CommandPattern.fromJson(entry);
        _patterns[pattern.id] = pattern;
        _totalPatterns++;
      }
      
      developer.log('🧠 loaded ${_patterns.length} patterns');
      
    } catch (e) {
      developer.log('🧠 failed to load patterns: $e');
    }
  }

  void _loadHistory() {
    try {
      final historyFile = File('${_suggestionsFile}.history');
      if (!historyFile.existsSync()) return;
      
      final content = historyFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['history']) {
        final historyEntry = CommandHistory.fromJson(entry);
        _history.add(historyEntry);
        
        // Update frequency data
        _commandFrequencies[historyEntry.command] = 
            (_commandFrequencies[historyEntry.command] ?? 0.0) + 1.0;
        _lastUsed[historyEntry.command] = historyEntry.timestamp;
      }
      
      developer.log('🧠 Lloaded ${_history.length} command history entries');
      
    } catch (e) {
      developer.log('🧠 failed to load history: $e');
    }
  }

  void _initializeDefaultPatterns() {
    if (_patterns.isEmpty) {
      final defaultPatterns = [
        // Git patterns
        CommandPattern(
          id: 'git_add',
          regex: r'^git add\s+',
          category: CommandCategory.git,
          priority: PatternPriority.high,
          description: 'Add files to git staging',
          examples: ['git add .', 'git add file.txt', 'git add *.dart'],
          context: ['git_repository'],
        ),
        
        CommandPattern(
          id: 'git_commit',
          regex: r'^git commit\s+',
          category: CommandCategory.git,
          priority: PatternPriority.high,
          description: 'Commit changes with message',
          examples: ['git commit -m "message"', 'git commit -amend'],
          context: ['git_repository'],
        ),
        
        CommandPattern(
          id: 'git_push',
          regex: r'^git push\s+',
          category: CommandCategory.git,
          priority: PatternPriority.high,
          description: 'Push changes to remote',
          examples: ['git push origin main', 'git push --force'],
          context: ['git_repository'],
        ),
        
        // File operations
        CommandPattern(
          id: 'ls_long',
          regex: r'^ls\s+',
          category: CommandCategory.file,
          priority: PatternPriority.medium,
          description: 'List files with details',
          examples: ['ls -la', 'ls -lh', 'ls -t'],
          context: ['directory'],
        ),
        
        CommandPattern(
          id: 'find_files',
          regex: r'^find\s+',
          category: CommandCategory.file,
          priority: PatternPriority.medium,
          description: 'Find files with criteria',
          examples: ['find . -name "*.dart"', 'find . -type f -size +1M'],
          context: ['directory'],
        ),
        
        // Development patterns
        CommandPattern(
          id: 'flutter_run',
          regex: r'^flutter\s+',
          category: CommandCategory.development,
          priority: PatternPriority.high,
          description: 'Flutter development commands',
          examples: ['flutter run', 'flutter build apk', 'flutter clean'],
          context: ['flutter_project'],
        ),
        
        CommandPattern(
          id: 'npm_install',
          regex: r'^npm\s+',
          category: CommandCategory.development,
          priority: PatternPriority.high,
          description: 'NPM package management',
          examples: ['npm install', 'npm run build', 'npm test'],
          context: ['node_project'],
        ),
        
        CommandPattern(
          id: 'docker_run',
          regex: r'^docker\s+',
          category: CommandCategory.development,
          priority: PatternPriority.medium,
          description: 'Docker container operations',
          examples: ['docker run -it ubuntu', 'docker ps', 'docker build -t app .'],
          context: ['docker_available'],
        ),
        
        // System patterns
        CommandPattern(
          id: 'systemctl',
          regex: r'^systemctl\s+',
          category: CommandCategory.system,
          priority: PatternPriority.medium,
          description: 'System service management',
          examples: ['systemctl start nginx', 'systemctl status docker', 'systemctl enable ssh'],
          context: ['linux'],
        ),
        
        CommandPattern(
          id: 'apt_package',
          regex: r'^apt\s+',
          category: CommandCategory.system,
          priority: PatternPriority.medium,
          description: 'APT package management',
          examples: ['apt update', 'apt install package', 'apt search term'],
          context: ['linux', 'sudo_available'],
        ),
      ];
      
      for (final pattern in defaultPatterns) {
        _patterns[pattern.id] = pattern;
        _totalPatterns++;
      }
      
      _savePatterns();
      developer.log('🧠 Initialized ${defaultPatterns.length} default patterns');
    }
  }

  void _startTimers() {
    _cleanupTimer = Timer.periodic(
      Duration(hours: 1),
      (_) => _cleanupOldData(),
    );
    
    _analysisTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _analyzeUsagePatterns(),
    );
  }

  Future<List<CommandSuggestion>> getSuggestions({
    required String input,
    String? currentDirectory,
    List<String>? context,
    int? limit,
    SuggestionType? type,
  }) async {
    final suggestions = <CommandSuggestion>[];
    final inputLower = input.toLowerCase();
    final currentContext = context ?? await _detectContext(currentDirectory);
    
    // 1. Exact matches from history
    suggestions.addAll(_getExactMatches(inputLower, currentContext));
    
    // 2. Pattern-based suggestions
    suggestions.addAll(_getPatternMatches(input, currentContext));
    
    // 3. Fuzzy matches from history
    suggestions.addAll(_getFuzzyMatches(inputLower, currentContext));
    
    // 4. Contextual suggestions
    suggestions.addAll(_getContextualSuggestions(input, currentContext));
    
    // 5. Frequency-based suggestions
    suggestions.addAll(_getFrequencyBasedSuggestions(input, currentContext));
    
    // Calculate scores and sort
    _scoreSuggestions(suggestions, input, currentContext);
    suggestions.sort((a, b) => b.score.compareTo(a.score));
    
    // Remove duplicates
    final uniqueSuggestions = <String, CommandSuggestion>{};
    for (final suggestion in suggestions) {
      uniqueSuggestions[suggestion.command] = suggestion;
    }
    
    final result = uniqueSuggestions.values.toList();
    
    // Apply limit
    if (limit != null && limit! > 0) {
      return result.take(limit!).toList();
    }
    
    developer.log('🧠 Generated ${result.length} suggestions for: "$input"');
    
    _emitEvent(SuggestionEvent(
      type: SuggestionEventType.suggestionsGenerated,
      input: input,
      suggestions: result,
      context: currentContext,
    ));
    
    return result;
  }

  List<CommandSuggestion> _getExactMatches(String input, List<String> context) {
    final matches = <CommandSuggestion>[];
    
    for (final entry in _history) {
      if (entry.command.toLowerCase().startsWith(input)) {
        final suggestion = CommandSuggestion(
          id: _generateSuggestionId(),
          command: entry.command,
          description: 'Previously used command',
          score: 0.8,
          source: SuggestionSource.history,
          category: _inferCategory(entry.command),
          context: entry.context,
          frequency: _commandFrequencies[entry.command] ?? 0.0,
          lastUsed: entry.timestamp,
          examples: [entry.command],
        );
        
        matches.add(suggestion);
      }
    }
    
    return matches;
  }

  List<CommandSuggestion> _getPatternMatches(String input, List<String> context) {
    final matches = <CommandSuggestion>[];
    
    for (final pattern in _patterns.values) {
      if (RegExp(pattern.regex).hasMatch(input)) {
        // Check if pattern context matches current context
        if (pattern.context.any((ctx) => context.contains(ctx))) {
          final suggestion = CommandSuggestion(
            id: _generateSuggestionId(),
            command: pattern.examples.first,
            description: pattern.description,
            score: 0.9,
            source: SuggestionSource.pattern,
            category: pattern.category,
            context: pattern.context,
            frequency: 0.0,
            lastUsed: null,
            examples: pattern.examples,
            patternId: pattern.id,
          );
          
          matches.add(suggestion);
        }
      }
    }
    
    return matches;
  }

  List<CommandSuggestion> _getFuzzyMatches(String input, List<String> context) {
    final matches = <CommandSuggestion>[];
    
    for (final entry in _history) {
      final similarity = _calculateSimilarity(input, entry.command.toLowerCase());
      
      if (similarity > 0.6) {
        final suggestion = CommandSuggestion(
          id: _generateSuggestionId(),
          command: entry.command,
          description: 'Similar to previous command',
          score: similarity * 0.7,
          source: SuggestionSource.history,
          category: _inferCategory(entry.command),
          context: entry.context,
          frequency: _commandFrequencies[entry.command] ?? 0.0,
          lastUsed: entry.timestamp,
          examples: [entry.command],
        );
        
        matches.add(suggestion);
      }
    }
    
    return matches;
  }

  List<CommandSuggestion> _getContextualSuggestions(String input, List<String> context) {
    final suggestions = <CommandSuggestion>[];
    
    // Directory-based suggestions
    if (context.contains('directory')) {
      final dir = Directory.current;
      final files = <String>[];
      
      try {
        await for (final entity in dir.list()) {
          if (entity is File) {
            files.add(path.basename(entity.path));
          } else if (entity is Directory) {
            files.add(path.basename(entity.path) + '/');
          }
        }
      } catch (e) {
        // Ignore permission errors
      }
      
      for (final file in files) {
        if (file.toLowerCase().startsWith(input)) {
          final suggestion = CommandSuggestion(
            id: _generateSuggestionId(),
            command: file,
            description: 'File in current directory',
            score: 0.6,
            source: SuggestionSource.context,
            category: CommandCategory.file,
            context: context,
            frequency: 0.0,
            lastUsed: null,
            examples: [file],
          );
          
          suggestions.add(suggestion);
        }
      }
    }
    
    // Git repository suggestions
    if (context.contains('git_repository')) {
      final gitSuggestions = [
        'git status',
        'git add .',
        'git commit -m "Update"',
        'git push',
        'git pull',
        'git log --oneline',
        'git diff',
      ];
      
      for (final cmd in gitSuggestions) {
        if (cmd.toLowerCase().startsWith(input)) {
          final suggestion = CommandSuggestion(
            id: _generateSuggestionId(),
            command: cmd,
            description: 'Git command',
            score: 0.7,
            source: SuggestionSource.context,
            category: CommandCategory.git,
            context: context,
            frequency: _commandFrequencies[cmd] ?? 0.0,
            lastUsed: _lastUsed[cmd],
            examples: [cmd],
          );
          
          suggestions.add(suggestion);
        }
      }
    }
    
    return suggestions;
  }

  List<CommandSuggestion> _getFrequencyBasedSuggestions(String input, List<String> context) {
    final suggestions = <CommandSuggestion>[];
    
    // Sort commands by frequency
    final sortedCommands = _commandFrequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in sortedCommands.take(20)) {
      final command = entry.key;
      final frequency = entry.value;
      
      if (command.toLowerCase().contains(input)) {
        final suggestion = CommandSuggestion(
          id: _generateSuggestionId(),
          command: command,
          description: 'Frequently used command',
          score: math.min(0.8, frequency / 100.0),
          source: SuggestionSource.frequency,
          category: _inferCategory(command),
          context: [],
          frequency: frequency,
          lastUsed: _lastUsed[command],
          examples: [command],
        );
        
        suggestions.add(suggestion);
      }
    }
    
    return suggestions;
  }

  void _scoreSuggestions(List<CommandSuggestion> suggestions, String input, List<String> context) {
    for (final suggestion in suggestions) {
      double score = suggestion.score;
      
      // Boost score for exact prefix match
      if (suggestion.command.toLowerCase().startsWith(input.toLowerCase())) {
        score += 0.2;
      }
      
      // Boost score for recent usage
      if (suggestion.lastUsed != null) {
        final daysSinceUse = DateTime.now().difference(suggestion.lastUsed!).inDays;
        score += math.max(0.0, 0.3 - (daysSinceUse * 0.05));
      }
      
      // Boost score for frequency
      if (suggestion.frequency > 0) {
        score += math.min(0.2, suggestion.frequency / 50.0);
      }
      
      // Boost score for context relevance
      final contextRelevance = _calculateContextRelevance(suggestion.context, context);
      score += contextRelevance * 0.2;
      
      suggestion.score = math.min(1.0, score);
    }
  }

  double _calculateSimilarity(String a, String b) {
    // Simple Levenshtein distance similarity
    final distance = _levenshteinDistance(a, b);
    final maxLength = math.max(a.length, b.length);
    
    if (maxLength == 0) return 1.0;
    
    return 1.0 - (distance / maxLength);
  }

  int _levenshteinDistance(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    
    return matrix[a.length][b.length];
  }

  CommandCategory _inferCategory(String command) {
    if (command.startsWith('git ')) return CommandCategory.git;
    if (command.startsWith('flutter ') || command.startsWith('npm ')) return CommandCategory.development;
    if (command.startsWith('docker ')) return CommandCategory.development;
    if (command.startsWith('systemctl ') || command.startsWith('apt ')) return CommandCategory.system;
    if (RegExp(r'^(ls|cd|cp|mv|rm|find|grep)\s*').hasMatch(command)) return CommandCategory.file;
    
    return CommandCategory.general;
  }

  double _calculateContextRelevance(List<String> suggestionContext, List<String> currentContext) {
    if (suggestionContext.isEmpty || currentContext.isEmpty) return 0.0;
    
    int matches = 0;
    for (final ctx in suggestionContext) {
      if (currentContext.contains(ctx)) {
        matches++;
      }
    }
    
    return matches / suggestionContext.length;
  }

  Future<List<String>> _detectContext(String? currentDirectory) async {
    final context = <String>[];
    
    try {
      final dir = Directory(currentDirectory ?? Directory.current.path);
      
      // Check for git repository
      if (await Directory('${dir.path}/.git').exists()) {
        context.add('git_repository');
      }
      
      // Check for Flutter project
      if (await File('${dir.path}/pubspec.yaml').exists()) {
        context.add('flutter_project');
      }
      
      // Check for Node.js project
      if (await File('${dir.path}/package.json').exists()) {
        context.add('node_project');
      }
      
      // Check for Docker
      if (await File('${dir.path}/Dockerfile').exists()) {
        context.add('docker_available');
      }
      
      // Always add directory context
      context.add('directory');
      
      // Check OS-specific context
      if (Platform.isLinux) {
        context.add('linux');
      }
      
      // Check for sudo availability
      try {
        final result = await Process.run('which', ['sudo']);
        if (result.exitCode == 0) {
          context.add('sudo_available');
        }
      } catch (e) {
        // Ignore
      }
      
    } catch (e) {
      developer.log('🧠 Context detection failed: $e');
    }
    
    return context;
  }

  Future<void> recordCommand({
    required String command,
    String? workingDirectory,
    int? exitCode,
    Duration? executionTime,
    List<String>? context,
  }) async {
    final historyEntry = CommandHistory(
      id: _generateHistoryId(),
      command: command,
      workingDirectory: workingDirectory ?? Directory.current.path,
      exitCode: exitCode ?? 0,
      executionTime: executionTime ?? Duration.zero,
      context: context ?? await _detectContext(workingDirectory),
      timestamp: DateTime.now(),
    );
    
    _history.add(historyEntry);
    
    // Update frequency data
    _commandFrequencies[command] = (_commandFrequencies[command] ?? 0.0) + 1.0;
    _lastUsed[command] = DateTime.now();
    
    // Keep history limited
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    
    developer.log('🧠 Recorded command: $command');
    
    _emitEvent(SuggestionEvent(
      type: SuggestionEventType.commandRecorded,
      command: command,
      context: historyEntry.context,
    ));
    
    await _saveHistory();
  }

  Future<String> createPattern({
    required String name,
    required String regex,
    required CommandCategory category,
    required String description,
    required List<String> examples,
    List<String>? context,
    PatternPriority? priority,
  }) async {
    if (_patterns.length >= _maxPatterns) {
      throw Exception('Maximum patterns reached: $_maxPatterns');
    }
    
    final patternId = _generatePatternId();
    
    final pattern = CommandPattern(
      id: patternId,
      name: name,
      regex: regex,
      category: category,
      priority: priority ?? PatternPriority.medium,
      description: description,
      examples: examples,
      context: context ?? [],
      createdAt: DateTime.now(),
      isDefault: false,
    );
    
    _patterns[patternId] = pattern;
    _totalPatterns++;
    
    developer.log('🧠 Created pattern: $name');
    
    _emitEvent(SuggestionEvent(
      type: SuggestionEventType.patternCreated,
      patternId: patternId,
      patternName: name,
    ));
    
    await _savePatterns();
    
    return patternId;
  }

  Future<void> updatePattern(String patternId, {
    String? name,
    String? regex,
    CommandCategory? category,
    String? description,
    List<String>? examples,
    List<String>? context,
    PatternPriority? priority,
  }) async {
    final pattern = _patterns[patternId];
    if (pattern == null) {
      throw Exception('Pattern not found: $patternId');
    }
    
    if (name != null) pattern.name = name!;
    if (regex != null) pattern.regex = regex!;
    if (category != null) pattern.category = category!;
    if (description != null) pattern.description = description!;
    if (examples != null) pattern.examples = examples!;
    if (context != null) pattern.context = context!;
    if (priority != null) pattern.priority = priority!;
    
    developer.log('🧠 Updated pattern: $patternId');
    
    _emitEvent(SuggestionEvent(
      type: SuggestionEventType.patternUpdated,
      patternId: patternId,
    ));
    
    await _savePatterns();
  }

  Future<void> deletePattern(String patternId) async {
    final pattern = _patterns.remove(patternId);
    if (pattern == null) {
      throw Exception('Pattern not found: $patternId');
    }
    
    if (pattern.isDefault) {
      throw Exception('Cannot delete default pattern');
    }
    
    _totalPatterns--;
    
    developer.log('🧠 Deleted pattern: $patternId');
    
    _emitEvent(SuggestionEvent(
      type: SuggestionEventType.patternDeleted,
      patternId: patternId,
    ));
    
    await _savePatterns();
  }

  Future<void> _cleanupOldData() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    
    // Clean old history entries
    final initialHistoryLength = _history.length;
    _history.removeWhere((entry) => entry.timestamp.isBefore(cutoffDate));
    
    if (_history.length != initialHistoryLength) {
      developer.log('🧠 Cleaned up ${initialHistoryLength - _history.length} old history entries');
      
      _emitEvent(SuggestionEvent(
        type: SuggestionEventType.historyCleaned,
        entriesRemoved: initialHistoryLength - _history.length,
      ));
      
      await _saveHistory();
    }
    
    // Update frequency data based on remaining history
    _commandFrequencies.clear();
    for (final entry in _history) {
      _commandFrequencies[entry.command] = (_commandFrequencies[entry.command] ?? 0.0) + 1.0;
    }
  }

  Future<void> _analyzeUsagePatterns() async {
    // Analyze command usage patterns and update suggestions
    final recentCommands = _history.where((entry) => 
        entry.timestamp.isAfter(DateTime.now().subtract(Duration(days: 7)))).toList();
    
    if (recentCommands.isEmpty) return;
    
    // Find most common command prefixes
    final prefixes = <String, int>{};
    for (final entry in recentCommands) {
      final parts = entry.command.split(' ');
      if (parts.isNotEmpty) {
        final prefix = parts[0];
        prefixes[prefix] = (prefixes[prefix] ?? 0) + 1;
      }
    }
    
    // Create suggestions for common prefixes
    final commonPrefixes = prefixes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(10);
    
    for (final entry in commonPrefixes) {
      final prefix = entry.key;
      final count = entry.value;
      
      if (count > 3) { // Suggest if used more than 3 times in a week
        final suggestionId = _generateSuggestionId();
        
        if (!_suggestions.containsKey(suggestionId)) {
          final suggestion = CommandSuggestion(
            id: suggestionId,
            command: prefix,
            description: 'Common command prefix (${count} uses this week)',
            score: 0.5,
            source: SuggestionSource.analysis,
            category: _inferCategory(prefix),
            context: [],
            frequency: _commandFrequencies[prefix] ?? 0.0,
            lastUsed: _lastUsed[prefix],
            examples: [prefix],
          );
          
          _suggestions[suggestionId] = suggestion;
          _totalSuggestions++;
        }
      }
    }
    
    await _saveSuggestions();
  }

  Future<void> _saveHistory() async {
    try {
      final file = File('${_suggestionsFile}.history');
      
      final historyData = _history.map((entry) => entry.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'history': historyData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🧠 Failed to save history: $e');
    }
  }

  Future<void> _saveSuggestions() async {
    try {
      final file = File(_suggestionsFile);
      
      final suggestionsData = _suggestions.values.map((suggestion) => suggestion.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'suggestions': suggestionsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🧠 Failed to save suggestions: $e');
    }
  }

  Future<void> _savePatterns() async {
    try {
      final file = File(_patternsFile);
      
      final patternsData = _patterns.values.map((pattern) => pattern.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'patterns': patternsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🧠 Failed to save patterns: $e');
    }
  }

  CommandSuggestion? getSuggestion(String suggestionId) {
    return _suggestions[suggestionId];
  }

  CommandPattern? getPattern(String patternId) {
    return _patterns[patternId];
  }

  List<CommandSuggestion> getSuggestions() {
    return _suggestions.values.toList();
  }

  List<CommandPattern> getPatterns() {
    return _patterns.values.toList();
  }

  List<CommandHistory> getHistory({int? limit, DateTime? since}) {
    var history = _history.toList();
    history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (since != null) {
      history = history.where((entry) => entry.timestamp.isAfter(since!)).toList();
    }
    
    if (limit != null && limit! > 0) {
      history = history.take(limit!).toList();
    }
    
    return history;
  }

  Map<String, double> getCommandFrequencies() {
    return Map.from(_commandFrequencies);
  }

  SuggestionStats getStats() {
    return SuggestionStats(
      totalSuggestions: _totalSuggestions,
      totalPatterns: _totalPatterns,
      totalHistoryEntries: _history.length,
      uniqueCommands: _commandFrequencies.length,
      averageCommandLength: _calculateAverageCommandLength(),
      mostUsedCommand: _getMostUsedCommand(),
      suggestionsBySource: _getSuggestionsBySource(),
      patternsByCategory: _getPatternsByCategory(),
    );
  }

  double _calculateAverageCommandLength() {
    if (_history.isEmpty) return 0.0;
    
    final totalLength = _history.fold(0, (sum, entry) => sum + entry.command.length);
    return totalLength / _history.length;
  }

  String? _getMostUsedCommand() {
    if (_commandFrequencies.isEmpty) return null;
    
    return _commandFrequencies.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  Map<SuggestionSource, int> _getSuggestionsBySource() {
    final sourceCount = <SuggestionSource, int>{};
    
    for (final suggestion in _suggestions.values) {
      sourceCount[suggestion.source] = (sourceCount[suggestion.source] ?? 0) + 1;
    }
    
    return sourceCount;
  }

  Map<CommandCategory, int> _getPatternsByCategory() {
    final categoryCount = <CommandCategory, int>{};
    
    for (final pattern in _patterns.values) {
      categoryCount[pattern.category] = (categoryCount[pattern.category] ?? 0) + 1;
    }
    
    return categoryCount;
  }

  String _generateSuggestionId() {
    return 'suggestion_${DateTime.now().millisecondsSinceEpoch}_$_totalSuggestions';
  }

  String _generateHistoryId() {
    return 'history_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generatePatternId() {
    return 'pattern_${DateTime.now().millisecondsSinceEpoch}_$_totalPatterns';
  }

  void _emitEvent(SuggestionEvent event) {
    _suggestionController.add(event);
  }

  Stream<SuggestionEvent> get suggestionEventStream => _suggestionController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    _analysisTimer?.cancel();
    
    _suggestions.clear();
    _patterns.clear();
    _history.clear();
    _contexts.clear();
    _commandFrequencies.clear();
    _lastUsed.clear();
    _suggestionController.close();
    
    developer.log('🧠 Intelligent Command Suggestion disposed');
  }
}

class CommandSuggestion {
  final String id;
  final String command;
  final String description;
  double score;
  final SuggestionSource source;
  final CommandCategory category;
  final List<String> context;
  final double frequency;
  final DateTime? lastUsed;
  final List<String> examples;
  final String? patternId;

  CommandSuggestion({
    required this.id,
    required this.command,
    required this.description,
    required this.score,
    required this.source,
    required this.category,
    required this.context,
    required this.frequency,
    this.lastUsed,
    required this.examples,
    this.patternId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'command': command,
      'description': description,
      'score': score,
      'source': source.name,
      'category': category.name,
      'context': context,
      'frequency': frequency,
      'last_used': lastUsed?.toIso8601String(),
      'examples': examples,
      'pattern_id': patternId,
    };
  }

  factory CommandSuggestion.fromJson(Map<String, dynamic> json) {
    return CommandSuggestion(
      id: json['id'],
      command: json['command'],
      description: json['description'],
      score: json['score']?.toDouble() ?? 0.0,
      source: SuggestionSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => SuggestionSource.history,
      ),
      category: CommandCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => CommandCategory.general,
      ),
      context: List<String>.from(json['context'] ?? []),
      frequency: json['frequency']?.toDouble() ?? 0.0,
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
      examples: List<String>.from(json['examples'] ?? []),
      patternId: json['pattern_id'],
    );
  }
}

class CommandPattern {
  final String id;
  final String name;
  final String regex;
  final CommandCategory category;
  final PatternPriority priority;
  final String description;
  final List<String> examples;
  final List<String> context;
  final DateTime createdAt;
  final bool isDefault;

  CommandPattern({
    required this.id,
    required this.name,
    required this.regex,
    required this.category,
    required this.priority,
    required this.description,
    required this.examples,
    required this.context,
    required this.createdAt,
    required this.isDefault,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'regex': regex,
      'category': category.name,
      'priority': priority.name,
      'description': description,
      'examples': examples,
      'context': context,
      'created_at': createdAt.toIso8601String(),
      'is_default': isDefault,
    };
  }

  factory CommandPattern.fromJson(Map<String, dynamic> json) {
    return CommandPattern(
      id: json['id'],
      name: json['name'],
      regex: json['regex'],
      category: CommandCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => CommandCategory.general,
      ),
      priority: PatternPriority.values.firstWhere(
        (priority) => priority.name == json['priority'],
        orElse: () => PatternPriority.medium,
      ),
      description: json['description'],
      examples: List<String>.from(json['examples'] ?? []),
      context: List<String>.from(json['context'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
      isDefault: json['is_default'] ?? false,
    );
  }
}

class CommandHistory {
  final String id;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final Duration executionTime;
  final List<String> context;
  final DateTime timestamp;

  CommandHistory({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.executionTime,
    required this.context,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'execution_time': executionTime.inMilliseconds,
      'context': context,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CommandHistory.fromJson(Map<String, dynamic> json) {
    return CommandHistory(
      id: json['id'],
      command: json['command'],
      workingDirectory: json['working_directory'],
      exitCode: json['exit_code'],
      executionTime: Duration(milliseconds: json['execution_time']),
      context: List<String>.from(json['context'] ?? []),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class ContextProfile {
  final String id;
  final String name;
  final List<String> indicators;
  final List<String> suggestions;
  final Map<String, dynamic> config;
  final DateTime createdAt;

  ContextProfile({
    required this.id,
    required this.name,
    required this.indicators,
    required this.suggestions,
    required this.config,
    required this.createdAt,
  });
}

enum CommandCategory {
  git,
  development,
  system,
  file,
  general,
}

enum SuggestionSource {
  history,
  pattern,
  context,
  frequency,
  analysis,
}

enum PatternPriority {
  low,
  medium,
  high,
}

enum SuggestionEventType {
  suggestionsGenerated,
  commandRecorded,
  patternCreated,
  patternUpdated,
  patternDeleted,
  historyCleaned,
}

class SuggestionEvent {
  final SuggestionEventType type;
  final String? input;
  final List<CommandSuggestion>? suggestions;
  final List<String>? context;
  final String? command;
  final String? patternId;
  final String? patternName;
  final int? entriesRemoved;

  SuggestionEvent({
    required this.type,
    this.input,
    this.suggestions,
    this.context,
    this.command,
    this.patternId,
    this.patternName,
    this.entriesRemoved,
  });
}

class SuggestionStats {
  final int totalSuggestions;
  final int totalPatterns;
  final int totalHistoryEntries;
  final int uniqueCommands;
  final double averageCommandLength;
  final String? mostUsedCommand;
  final Map<SuggestionSource, int> suggestionsBySource;
  final Map<CommandCategory, int> patternsByCategory;

  SuggestionStats({
    required this.totalSuggestions,
    required this.totalPatterns,
    required this.totalHistoryEntries,
    required this.uniqueCommands,
    required this.averageCommandLength,
    this.mostUsedCommand,
    required this.suggestionsBySource,
    required this.patternsByCategory,
  });
}
