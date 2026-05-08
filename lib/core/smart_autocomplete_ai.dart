import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'nvidia_nim_command_predictor.dart';
import 'intelligent_command_suggestions.dart';

/// Smart auto-completion with AI integration
/// 
/// Features:
/// - AI-powered auto-completion using NVIDIA NIM models
/// - Context-aware suggestions based on terminal state
/// - Real-time completion with fuzzy matching
/// - Learning from user patterns and preferences
/// - Multi-source suggestion aggregation
class SmartAutocompleteAI {
  static const Duration _debounceDelay = Duration(milliseconds: 200);
  static const Duration _requestTimeout = Duration(seconds: 5);
  static const int _maxSuggestions = 8;
  static const double _minConfidence = 0.2;
  
  final NvidiaNimCommandPredictor _nimPredictor;
  final IntelligentCommandSuggestions _commandSuggestions;
  final Map<String, List<AutoCompleteSuggestion>> _completionCache = {};
  final Queue<CompletionUsage> _usageHistory = Queue();
  final Map<String, CompletionPattern> _patterns = {};
  
  Timer? _debounceTimer;
  String _currentInput = '';
  String _currentDirectory = '';
  List<String> _commandHistory = [];
  
  int _totalCompletions = 0;
  int _acceptedCompletions = 0;
  double _totalCompletionTime = 0.0;

  SmartAutocompleteAI(this._nimPredictor, this._commandSuggestions) {
    _initializeAutocomplete();
  }

  /// Initialize the auto-completion system
  void _initializeAutocomplete() {
    _currentDirectory = Directory.current.path;
  }

  /// Get auto-completion suggestions
  Future<List<AutoCompleteSuggestion>> getCompletions(
    String input, {
    int cursorPosition = -1,
    bool includeAI = true,
    bool includeHistory = true,
    bool includeFiles = true,
    bool includeCommands = true,
  }) async {
    if (input.isEmpty) return [];
    
    _currentInput = input;
    _totalCompletions++;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Cancel previous debounce timer
      _debounceTimer?.cancel();
      
      // Debounce completion requests
      final completer = Completer<List<AutoCompleteSuggestion>>();
      
      _debounceTimer = Timer(_debounceDelay, () async {
        final completions = await _generateCompletions(
          input,
          cursorPosition: cursorPosition,
          includeAI: includeAI,
          includeHistory: includeHistory,
          includeFiles: includeFiles,
          includeCommands: includeCommands,
        );
        
        completer.complete(completions);
      });
      
      final suggestions = await completer.future;
      
      _totalCompletionTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return suggestions.take(_maxSuggestions).toList();
    } catch (e) {
      debugPrint('Failed to get completions: $e');
      return [];
    } finally {
      stopwatch.stop();
    }
  }

  /// Generate completions from multiple sources
  Future<List<AutoCompleteSuggestion>> _generateCompletions(
    String input, {
    required int cursorPosition,
    required bool includeAI,
    required bool includeHistory,
    required bool includeFiles,
    required bool includeCommands,
  }) async {
    final allSuggestions = <AutoCompleteSuggestion>[];
    
    // Extract current word and context
    final context = _extractCompletionContext(input, cursorPosition);
    
    // AI-powered completions
    if (includeAI && context.currentWord.isNotEmpty) {
      final aiCompletions = await _getAICompletions(context);
      allSuggestions.addAll(aiCompletions);
    }
    
    // Command suggestions
    if (includeCommands) {
      final commandCompletions = await _getCommandCompletions(context);
      allSuggestions.addAll(commandCompletions);
    }
    
    // File and directory completions
    if (includeFiles) {
      final fileCompletions = await _getFileCompletions(context);
      allSuggestions.addAll(fileCompletions);
    }
    
    // History-based completions
    if (includeHistory) {
      final historyCompletions = _getHistoryCompletions(context);
      allSuggestions.addAll(historyCompletions);
    }
    
    // Pattern-based completions
    final patternCompletions = _getPatternCompletions(context);
    allSuggestions.addAll(patternCompletions);
    
    // Remove duplicates and sort by confidence
    final uniqueSuggestions = _removeDuplicates(allSuggestions);
    uniqueSuggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return uniqueSuggestions;
  }

  /// Extract completion context
  CompletionContext _extractCompletionContext(String input, int cursorPosition) {
    final actualCursorPosition = cursorPosition == -1 ? input.length : cursorPosition;
    final beforeCursor = input.substring(0, actualCursorPosition);
    final afterCursor = input.substring(actualCursorPosition);
    
    // Extract current word
    final currentWordMatch = RegExp(r'\w+$').firstMatch(beforeCursor);
    final currentWord = currentWordMatch?.group(0) ?? '';
    
    // Extract command context
    final words = beforeCursor.split(' ');
    final command = words.isNotEmpty ? words.first : '';
    final args = words.length > 1 ? words.sublist(1) : [];
    
    return CompletionContext(
      fullInput: input,
      beforeCursor: beforeCursor,
      afterCursor: afterCursor,
      currentWord: currentWord,
      command: command,
      arguments: args,
      cursorPosition: actualCursorPosition,
    );
  }

  /// Get AI-powered completions
  Future<List<AutoCompleteSuggestion>> _getAICompletions(CompletionContext context) async {
    try {
      // Use NIM predictor for AI completions
      final predictions = await _nimPredictor.predictNextCommand(
        currentInput: context.beforeCursor,
        workingDirectory: _currentDirectory,
        recentCommands: _commandHistory,
      );
      
      return predictions.map((prediction) => AutoCompleteSuggestion(
        text: prediction.command,
        displayText: prediction.command,
        type: CompletionType.ai,
        description: prediction.description,
        confidence: prediction.confidence,
        priority: _calculatePriority(prediction.confidence),
        metadata: {
          'source': 'nim',
          'category': prediction.category,
        },
      )).where((s) => s.text.startsWith(context.currentWord)).toList();
    } catch (e) {
      debugPrint('Failed to get AI completions: $e');
      return [];
    }
  }

  /// Get command completions
  Future<List<AutoCompleteSuggestion>> _getCommandCompletions(CompletionContext context) async {
    try {
      final suggestions = await _commandSuggestions.getSuggestions(
        context.beforeCursor,
        includeFiles: false,
        includeDirectories: false,
        includeCommands: true,
        includeHistory: false,
      );
      
      return suggestions.map((suggestion) => AutoCompleteSuggestion(
        text: suggestion.text,
        displayText: suggestion.text,
        type: CompletionType.command,
        description: suggestion.description,
        confidence: suggestion.confidence,
        priority: _calculatePriority(suggestion.confidence),
        metadata: suggestion.metadata,
      )).where((s) => s.text.startsWith(context.currentWord)).toList();
    } catch (e) {
      debugPrint('Failed to get command completions: $e');
      return [];
    }
  }

  /// Get file and directory completions
  Future<List<AutoCompleteSuggestion>> _getFileCompletions(CompletionContext context) async {
    final completions = <AutoCompleteSuggestion>[];
    
    try {
      // Extract path from context
      final pathPart = _extractPathFromContext(context);
      if (pathPart.isEmpty) return completions;
      
      final isAbsolute = pathPart.startsWith('/');
      final searchDir = isAbsolute ? pathPart : '$_currentDirectory/$pathPart';
      final searchName = pathPart.split('/').last.toLowerCase();
      
      final dir = Directory(searchDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          final name = entity.path.split('/').last;
          if (name.toLowerCase().startsWith(searchName)) {
            final type = entity is File ? 'file' : 'directory';
            final icon = _getFileIcon(name, type);
            
            completions.add(AutoCompleteSuggestion(
              text: name,
              displayText: '$icon $name',
              type: type == 'file' ? CompletionType.file : CompletionType.directory,
              description: '$type: $name',
              confidence: 0.8,
              priority: Priority.high,
              metadata: {
                'path': entity.path,
                'full_path': entity.path,
                'type': type,
              },
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get file completions: $e');
    }
    
    return completions;
  }

  /// Extract path from completion context
  String _extractPathFromContext(CompletionContext context) {
    final words = context.beforeCursor.split(' ');
    if (words.isEmpty) return '';
    
    // Find the last word that looks like a path
    for (int i = words.length - 1; i >= 0; i--) {
      final word = words[i];
      if (word.contains('/') || word.startsWith('./') || word.startsWith('~')) {
        return word;
      }
    }
    
    return '';
  }

  /// Get file icon
  String _getFileIcon(String name, String type) {
    if (type == 'directory') return '📁';
    
    final extension = name.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart': return '🎯';
      case 'py': return '🐍';
      case 'js': return '📜';
      case 'ts': return '📘';
      case 'json': return '📋';
      case 'yaml': return '📄';
      case 'md': return '📝';
      case 'txt': return '📃';
      case 'png': case 'jpg': case 'jpeg': case 'gif': return '🖼️';
      case 'pdf': return '📕';
      case 'zip': case 'tar': case 'gz': return '📦';
      default: return '📄';
    }
  }

  /// Get history-based completions
  List<AutoCompleteSuggestion> _getHistoryCompletions(CompletionContext context) {
    final completions = <AutoCompleteSuggestion>[];
    final searchLower = context.currentWord.toLowerCase();
    
    for (final usage in _usageHistory.reversed.take(50)) {
      if (usage.completion.toLowerCase().startsWith(searchLower)) {
        completions.add(AutoCompleteSuggestion(
          text: usage.completion,
          displayText: usage.completion,
          type: CompletionType.history,
          description: 'Recent completion (${usage.formattedAge})',
          confidence: _calculateHistoryConfidence(usage),
          priority: _calculatePriority(usage.confidence),
          metadata: {
            'usage_count': usage.count,
            'last_used': usage.lastUsed.toIso8601String(),
          },
        ));
      }
    }
    
    return completions;
  }

  /// Calculate history confidence
  double _calculateHistoryConfidence(CompletionUsage usage) {
    final ageInHours = DateTime.now().difference(usage.lastUsed).inHours;
    final ageScore = max(0.0, 1.0 - (ageInHours / 24.0)); // Decay over 24 hours
    final frequencyScore = min(1.0, usage.count / 10.0); // Normalize to 0-1
    
    return (ageScore * 0.6) + (frequencyScore * 0.4);
  }

  /// Get pattern-based completions
  List<AutoCompleteSuggestion> _getPatternCompletions(CompletionContext context) {
    final completions = <AutoCompleteSuggestion>[];
    final pattern = _detectPattern(context);
    
    if (pattern != null) {
      final patternCompletions = _getPatternSuggestions(pattern, context);
      completions.addAll(patternCompletions);
    }
    
    return completions;
  }

  /// Detect completion pattern
  CompletionPattern? _detectPattern(CompletionContext context) {
    final command = context.command.toLowerCase();
    final args = context.arguments;
    
    // Git command patterns
    if (command == 'git') {
      if (args.isEmpty) {
        return CompletionPattern.gitCommand();
      } else if (args.length == 1) {
        return CompletionPattern.gitArgument(args.first);
      }
    }
    
    // Docker command patterns
    if (command == 'docker') {
      if (args.isEmpty) {
        return CompletionPattern.dockerCommand();
      } else if (args.length == 1) {
        return CompletionPattern.dockerArgument(args.first);
      }
    }
    
    // NPM command patterns
    if (command == 'npm') {
      if (args.isEmpty) {
        return CompletionPattern.npmCommand();
      }
    }
    
    return null;
  }

  /// Get pattern suggestions
  List<AutoCompleteSuggestion> _getPatternSuggestions(
    CompletionPattern pattern,
    CompletionContext context,
  ) {
    return pattern.suggestions.map((suggestion) => AutoCompleteSuggestion(
      text: suggestion.text,
      displayText: suggestion.displayText,
      type: CompletionType.pattern,
      description: suggestion.description,
      confidence: suggestion.confidence,
      priority: suggestion.priority,
      metadata: {
        'pattern': pattern.type,
        'category': suggestion.category,
      },
    )).where((s) => s.text.startsWith(context.currentWord)).toList();
  }

  /// Remove duplicate suggestions
  List<AutoCompleteSuggestion> _removeDuplicates(List<AutoCompleteSuggestion> suggestions) {
    final seen = <String>{};
    final unique = <AutoCompleteSuggestion>[];
    
    for (final suggestion in suggestions) {
      if (!seen.contains(suggestion.text)) {
        seen.add(suggestion.text);
        unique.add(suggestion);
      }
    }
    
    return unique;
  }

  /// Calculate priority based on confidence
  Priority _calculatePriority(double confidence) {
    if (confidence >= 0.8) return Priority.high;
    if (confidence >= 0.5) return Priority.medium;
    return Priority.low;
  }

  /// Accept completion (user selected it)
  void acceptCompletion(AutoCompleteSuggestion suggestion) {
    _acceptedCompletions++;
    
    // Record usage
    final existing = _usageHistory.where((u) => u.completion == suggestion.text).firstOrNull;
    if (existing != null) {
      existing.count++;
      existing.lastUsed = DateTime.now();
      existing.confidence = suggestion.confidence;
    } else {
      _usageHistory.add(CompletionUsage(
        completion: suggestion.text,
        count: 1,
        lastUsed: DateTime.now(),
        confidence: suggestion.confidence,
      ));
    }
    
    // Keep only recent usage
    if (_usageHistory.length > 1000) {
      _usageHistory.removeFirst();
    }
    
    // Update command history
    _commandHistory.insert(0, suggestion.text);
    if (_commandHistory.length > 100) {
      _commandHistory.removeRange(100, _commandHistory.length);
    }
  }

  /// Update current directory
  void updateCurrentDirectory(String directory) {
    _currentDirectory = directory;
  }

  /// Get completion statistics
  CompletionStats getStats() {
    return CompletionStats(
      totalCompletions: _totalCompletions,
      acceptedCompletions: _acceptedCompletions,
      acceptanceRate: _totalCompletions > 0 ? _acceptedCompletions / _totalCompletions : 0.0,
      averageCompletionTime: _totalCompletions > 0 ? _totalCompletionTime / _totalCompletions : 0.0,
      totalCompletionTime: _totalCompletionTime,
      cacheSize: _completionCache.length,
      historySize: _usageHistory.length,
      currentDirectory: _currentDirectory,
      commandHistorySize: _commandHistory.length,
    );
  }

  /// Clear all data
  void clear() {
    _completionCache.clear();
    _usageHistory.clear();
    _commandHistory.clear();
    _patterns.clear();
  }

  /// Dispose auto-completion system
  void dispose() {
    _debounceTimer?.cancel();
    clear();
  }
}

/// Completion context
class CompletionContext {
  final String fullInput;
  final String beforeCursor;
  final String afterCursor;
  final String currentWord;
  final String command;
  final List<String> arguments;
  final int cursorPosition;

  const CompletionContext({
    required this.fullInput,
    required this.beforeCursor,
    required this.afterCursor,
    required this.currentWord,
    required this.command,
    required this.arguments,
    required this.cursorPosition,
  });
}

/// Auto-complete suggestion
class AutoCompleteSuggestion {
  final String text;
  final String displayText;
  final CompletionType type;
  final String description;
  final double confidence;
  final Priority priority;
  final Map<String, dynamic> metadata;

  const AutoCompleteSuggestion({
    required this.text,
    required this.displayText,
    required this.type,
    required this.description,
    required this.confidence,
    required this.priority,
    required this.metadata,
  });
}

/// Completion types
enum CompletionType {
  ai,
  command,
  file,
  directory,
  history,
  pattern,
}

/// Priority levels
enum Priority {
  high,
  medium,
  low,
}

/// Completion usage tracking
class CompletionUsage {
  final String completion;
  int count;
  DateTime lastUsed;
  double confidence;

  CompletionUsage({
    required this.completion,
    required this.count,
    required this.lastUsed,
    required this.confidence,
  });

  String get formattedAge {
    final age = DateTime.now().difference(lastUsed);
    if (age.inMinutes < 60) {
      return '${age.inMinutes}m ago';
    } else if (age.inHours < 24) {
      return '${age.inHours}h ago';
    } else {
      return '${age.inDays}d ago';
    }
  }
}

/// Completion pattern
class CompletionPattern {
  final String type;
  final List<PatternSuggestion> suggestions;

  const CompletionPattern({
    required this.type,
    required this.suggestions,
  });

  factory CompletionPattern.gitCommand() {
    return CompletionPattern(
      type: 'git_command',
      suggestions: [
        PatternSuggestion(
          text: 'status',
          displayText: 'status',
          description: 'Show working tree status',
          confidence: 0.9,
          priority: Priority.high,
          category: 'git',
        ),
        PatternSuggestion(
          text: 'add',
          displayText: 'add',
          description: 'Add files to staging area',
          confidence: 0.9,
          priority: Priority.high,
          category: 'git',
        ),
        PatternSuggestion(
          text: 'commit',
          displayText: 'commit',
          description: 'Commit changes',
          confidence: 0.9,
          priority: Priority.high,
          category: 'git',
        ),
        PatternSuggestion(
          text: 'push',
          displayText: 'push',
          description: 'Push to remote',
          confidence: 0.8,
          priority: Priority.medium,
          category: 'git',
        ),
        PatternSuggestion(
          text: 'pull',
          displayText: 'pull',
          description: 'Pull from remote',
          confidence: 0.8,
          priority: Priority.medium,
          category: 'git',
        ),
      ],
    );
  }

  factory CompletionPattern.gitArgument(String command) {
    switch (command) {
      case 'add':
        return CompletionPattern(
          type: 'git_add_argument',
          suggestions: [
            PatternSuggestion(
              text: '.',
              displayText: '.',
              description: 'Add all files',
              confidence: 0.9,
              priority: Priority.high,
              category: 'git',
            ),
            PatternSuggestion(
              text: '-A',
              displayText: '-A',
              description: 'Add all files (including deleted)',
              confidence: 0.8,
              priority: Priority.medium,
              category: 'git',
            ),
          ],
        );
      case 'commit':
        return CompletionPattern(
          type: 'git_commit_argument',
          suggestions: [
            PatternSuggestion(
              text: '-m',
              displayText: '-m',
              description: 'Commit message',
              confidence: 0.9,
              priority: Priority.high,
              category: 'git',
            ),
            PatternSuggestion(
              text: '--amend',
              displayText: '--amend',
              description: 'Amend last commit',
              confidence: 0.7,
              priority: Priority.medium,
              category: 'git',
            ),
          ],
        );
      default:
        return CompletionPattern(type: 'git_unknown', suggestions: []);
    }
  }

  factory CompletionPattern.dockerCommand() {
    return CompletionPattern(
      type: 'docker_command',
      suggestions: [
        PatternSuggestion(
          text: 'run',
          displayText: 'run',
          description: 'Run a container',
          confidence: 0.9,
          priority: Priority.high,
          category: 'docker',
        ),
        PatternSuggestion(
          text: 'build',
          displayText: 'build',
          description: 'Build an image',
          confidence: 0.9,
          priority: Priority.high,
          category: 'docker',
        ),
        PatternSuggestion(
          text: 'ps',
          displayText: 'ps',
          description: 'List containers',
          confidence: 0.8,
          priority: Priority.medium,
          category: 'docker',
        ),
      ],
    );
  }

  factory CompletionPattern.dockerArgument(String command) {
    switch (command) {
      case 'run':
        return CompletionPattern(
          type: 'docker_run_argument',
          suggestions: [
            PatternSuggestion(
              text: '-d',
              displayText: '-d',
              description: 'Run in detached mode',
              confidence: 0.8,
              priority: Priority.medium,
              category: 'docker',
            ),
            PatternSuggestion(
              text: '-p',
              displayText: '-p',
              description: 'Port mapping',
              confidence: 0.8,
              priority: Priority.medium,
              category: 'docker',
            ),
            PatternSuggestion(
              text: '-v',
              displayText: '-v',
              description: 'Volume mapping',
              confidence: 0.8,
              priority: Priority.medium,
              category: 'docker',
            ),
          ],
        );
      default:
        return CompletionPattern(type: 'docker_unknown', suggestions: []);
    }
  }

  factory CompletionPattern.npmCommand() {
    return CompletionPattern(
      type: 'npm_command',
      suggestions: [
        PatternSuggestion(
          text: 'install',
          displayText: 'install',
          description: 'Install packages',
          confidence: 0.9,
          priority: Priority.high,
          category: 'npm',
        ),
        PatternSuggestion(
          text: 'run',
          displayText: 'run',
          description: 'Run scripts',
          confidence: 0.9,
          priority: Priority.high,
          category: 'npm',
        ),
        PatternSuggestion(
          text: 'test',
          displayText: 'test',
          description: 'Run tests',
          confidence: 0.8,
          priority: Priority.medium,
          category: 'npm',
        ),
      ],
    );
  }
}

/// Pattern suggestion
class PatternSuggestion {
  final String text;
  final String displayText;
  final String description;
  final double confidence;
  final Priority priority;
  final String category;

  const PatternSuggestion({
    required this.text,
    required this.displayText,
    required this.description,
    required this.confidence,
    required this.priority,
    required this.category,
  });
}

/// Completion statistics
class CompletionStats {
  final int totalCompletions;
  final int acceptedCompletions;
  final double acceptanceRate;
  final double averageCompletionTime;
  final double totalCompletionTime;
  final int cacheSize;
  final int historySize;
  final String currentDirectory;
  final int commandHistorySize;

  const CompletionStats({
    required this.totalCompletions,
    required this.acceptedCompletions,
    required this.acceptanceRate,
    required this.averageCompletionTime,
    required this.totalCompletionTime,
    required this.cacheSize,
    required this.historySize,
    required this.currentDirectory,
    required this.commandHistorySize,
  });
}
