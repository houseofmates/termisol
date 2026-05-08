import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'nvidia_nim_command_predictor.dart';

/// Intelligent command suggestions system
/// 
/// Features:
/// - AI-powered command suggestions using multiple sources
/// - Context-aware suggestions based on current environment
/// - Learning from user behavior and preferences
/// - Real-time suggestions with performance optimization
/// - Integration with file system and project analysis
class IntelligentCommandSuggestions {
  static const int _maxSuggestions = 10;
  static const int _maxHistorySize = 1000;
  static const Duration _debounceDelay = Duration(milliseconds: 300);
  static const double _minConfidence = 0.3;
  
  final NvidiaNimCommandPredictor _nimPredictor;
  final Map<String, List<CommandSuggestion>> _suggestionCache = {};
  final Queue<CommandUsage> _commandUsage = Queue();
  final Map<String, ProjectContext> _projectContexts = {};
  
  Timer? _debounceTimer;
  String _currentDirectory = '';
  List<String> _recentCommands = [];
  Set<String> _availableFiles = {};
  Set<String> _availableDirectories = {};
  
  int _totalSuggestions = 0;
  int _acceptedSuggestions = 0;
  double _totalSuggestionTime = 0.0;

  IntelligentCommandSuggestions(this._nimPredictor) {
    _initializeSuggestions();
  }

  /// Initialize the suggestion system
  void _initializeSuggestions() {
    _updateCurrentDirectory();
    _scanCurrentDirectory();
  }

  /// Update current working directory
  Future<void> _updateCurrentDirectory() async {
    try {
      _currentDirectory = Directory.current.path;
    } catch (e) {
      debugPrint('Failed to get current directory: $e');
    }
  }

  /// Scan current directory for files and directories
  Future<void> _scanCurrentDirectory() async {
    try {
      final currentDir = Directory(_currentDirectory);
      if (!await currentDir.exists()) return;
      
      _availableFiles.clear();
      _availableDirectories.clear();
      
      await for (final entity in currentDir.list()) {
        final name = entity.path.split('/').last;
        if (entity is File) {
          _availableFiles.add(name);
        } else if (entity is Directory) {
          _availableDirectories.add(name);
        }
      }
    } catch (e) {
      debugPrint('Failed to scan directory: $e');
    }
  }

  /// Get intelligent suggestions for current input
  Future<List<CommandSuggestion>> getSuggestions(
    String currentInput, {
    bool includeFiles = true,
    bool includeDirectories = true,
    bool includeCommands = true,
    bool includeHistory = true,
  }) async {
    if (currentInput.isEmpty) return [];
    
    _totalSuggestions++;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Cancel previous debounce timer
      _debounceTimer?.cancel();
      
      // Debounce suggestions
      final completer = Completer<List<CommandSuggestion>>();
      
      _debounceTimer = Timer(_debounceDelay, () async {
        final suggestions = await _generateSuggestions(
          currentInput,
          includeFiles: includeFiles,
          includeDirectories: includeDirectories,
          includeCommands: includeCommands,
          includeHistory: includeHistory,
        );
        
        completer.complete(suggestions);
      });
      
      final suggestions = await completer.future;
      
      _totalSuggestionTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return suggestions.take(_maxSuggestions).toList();
    } catch (e) {
      debugPrint('Failed to get suggestions: $e');
      return [];
    } finally {
      stopwatch.stop();
    }
  }

  /// Generate suggestions from multiple sources
  Future<List<CommandSuggestion>> _generateSuggestions(
    String currentInput, {
    required bool includeFiles,
    required bool includeDirectories,
    required bool includeCommands,
    required bool includeHistory,
  }) async {
    final allSuggestions = <CommandSuggestion>[];
    
    // File and directory suggestions
    if (includeFiles || includeDirectories) {
      final pathSuggestions = await _getPathSuggestions(currentInput, includeFiles, includeDirectories);
      allSuggestions.addAll(pathSuggestions);
    }
    
    // Command suggestions from NIM
    if (includeCommands) {
      final commandSuggestions = await _getCommandSuggestions(currentInput);
      allSuggestions.addAll(commandSuggestions);
    }
    
    // History-based suggestions
    if (includeHistory) {
      final historySuggestions = _getHistorySuggestions(currentInput);
      allSuggestions.addAll(historySuggestions);
    }
    
    // Project-specific suggestions
    final projectSuggestions = await _getProjectSuggestions(currentInput);
    allSuggestions.addAll(projectSuggestions);
    
    // Sort by confidence and relevance
    allSuggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return allSuggestions;
  }

  /// Get file and directory path suggestions
  Future<List<CommandSuggestion>> _getPathSuggestions(
    String currentInput,
    bool includeFiles,
    bool includeDirectories,
  ) async {
    final suggestions = <CommandSuggestion>[];
    
    // Extract path from current input
    final pathPart = _extractPathFromInput(currentInput);
    if (pathPart.isEmpty) return suggestions;
    
    final isAbsolute = pathPart.startsWith('/');
    final searchDir = isAbsolute ? pathPart : '$_currentDirectory/$pathPart';
    final searchName = pathPart.split('/').last.toLowerCase();
    
    try {
      final dir = Directory(searchDir);
      if (!await dir.exists()) {
        // Try parent directory
        final parentDir = dir.parent;
        if (await parentDir.exists()) {
          await for (final entity in parentDir.list()) {
            final name = entity.path.split('/').last;
            if (name.toLowerCase().contains(searchName)) {
              final type = entity is File ? 'file' : 'directory';
              if ((type == 'file' && includeFiles) || (type == 'directory' && includeDirectories)) {
                suggestions.add(CommandSuggestion(
                  text: _buildPathSuggestion(currentInput, name),
                  type: SuggestionType.path,
                  description: '$type: $name',
                  confidence: _calculatePathConfidence(name, searchName),
                  metadata: {
                    'path': entity.path,
                    'type': type,
                  },
                ));
              }
            }
          }
        }
      } else {
        // Directory exists, list its contents
        await for (final entity in dir.list()) {
          final name = entity.path.split('/').last;
          final type = entity is File ? 'file' : 'directory';
          if ((type == 'file' && includeFiles) || (type == 'directory' && includeDirectories)) {
            suggestions.add(CommandSuggestion(
              text: _buildPathSuggestion(currentInput, name),
              type: SuggestionType.path,
              description: '$type: $name',
              confidence: _calculatePathConfidence(name, searchName),
              metadata: {
                'path': entity.path,
                'type': type,
              },
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get path suggestions: $e');
    }
    
    return suggestions;
  }

  /// Extract path part from input
  String _extractPathFromInput(String input) {
    final words = input.split(' ');
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

  /// Build path suggestion
  String _buildPathSuggestion(String currentInput, String suggestion) {
    final words = currentInput.split(' ');
    if (words.isEmpty) return suggestion;
    
    // Replace the last word with the suggestion
    words[words.length - 1] = suggestion;
    return words.join(' ');
  }

  /// Calculate path confidence
  double _calculatePathConfidence(String name, String searchName) {
    if (name.toLowerCase().startsWith(searchName)) {
      return 0.9;
    } else if (name.toLowerCase().contains(searchName)) {
      return 0.7;
    } else {
      return 0.5;
    }
  }

  /// Get command suggestions from NIM predictor
  Future<List<CommandSuggestion>> _getCommandSuggestions(String currentInput) async {
    try {
      final predictions = await _nimPredictor.predictNextCommand(
        currentInput: currentInput,
        workingDirectory: _currentDirectory,
        recentCommands: _recentCommands,
      );
      
      return predictions.map((prediction) => CommandSuggestion(
        text: prediction.command,
        type: SuggestionType.command,
        description: prediction.description,
        confidence: prediction.confidence,
        metadata: {
          'category': prediction.category,
          'source': 'nim',
        },
      )).toList();
    } catch (e) {
      debugPrint('Failed to get NIM suggestions: $e');
      return [];
    }
  }

  /// Get history-based suggestions
  List<CommandSuggestion> _getHistorySuggestions(String currentInput) {
    final suggestions = <CommandSuggestion>[];
    final searchLower = currentInput.toLowerCase();
    
    for (final usage in _commandUsage.reversed.take(50)) {
      if (usage.command.toLowerCase().contains(searchLower)) {
        suggestions.add(CommandSuggestion(
          text: usage.command,
          type: SuggestionType.history,
          description: 'Recent command (${usage.formattedAge})',
          confidence: _calculateHistoryConfidence(usage),
          metadata: {
            'usage_count': usage.count,
            'last_used': usage.lastUsed.toIso8601String(),
          },
        ));
      }
    }
    
    return suggestions;
  }

  /// Calculate history confidence
  double _calculateHistoryConfidence(CommandUsage usage) {
    final ageInHours = DateTime.now().difference(usage.lastUsed).inHours;
    final ageScore = max(0.0, 1.0 - (ageInHours / 24.0)); // Decay over 24 hours
    final frequencyScore = min(1.0, usage.count / 10.0); // Normalize to 0-1
    
    return (ageScore * 0.6) + (frequencyScore * 0.4);
  }

  /// Get project-specific suggestions
  Future<List<CommandSuggestion>> _getProjectSuggestions(String currentInput) async {
    final suggestions = <CommandSuggestion>[];
    
    // Detect project type and provide relevant suggestions
    final projectType = await _detectProjectType();
    
    switch (projectType) {
      case ProjectType.nodejs:
        suggestions.addAll(_getNodeJSSuggestions(currentInput));
        break;
      case ProjectType.python:
        suggestions.addAll(_getPythonSuggestions(currentInput));
        break;
      case ProjectType.dart:
        suggestions.addAll(_getDartSuggestions(currentInput));
        break;
      case ProjectType.rust:
        suggestions.addAll(_getRustSuggestions(currentInput));
        break;
      case ProjectType.docker:
        suggestions.addAll(_getDockerSuggestions(currentInput));
        break;
      case ProjectType.git:
        suggestions.addAll(_getGitSuggestions(currentInput));
        break;
    }
    
    return suggestions;
  }

  /// Detect project type
  Future<ProjectType> _detectProjectType() async {
    try {
      final currentDir = Directory(_currentDirectory);
      
      // Check for package.json (Node.js)
      if (await File('$_currentDirectory/package.json').exists()) {
        return ProjectType.nodejs;
      }
      
      // Check for requirements.txt or pyproject.toml (Python)
      if (await File('$_currentDirectory/requirements.txt').exists() ||
          await File('$_currentDirectory/pyproject.toml').exists()) {
        return ProjectType.python;
      }
      
      // Check for pubspec.yaml (Dart/Flutter)
      if (await File('$_currentDirectory/pubspec.yaml').exists()) {
        return ProjectType.dart;
      }
      
      // Check for Cargo.toml (Rust)
      if (await File('$_currentDirectory/Cargo.toml').exists()) {
        return ProjectType.rust;
      }
      
      // Check for Dockerfile
      if (await File('$_currentDirectory/Dockerfile').exists()) {
        return ProjectType.docker;
      }
      
      // Check for .git directory
      if (await Directory('$_currentDirectory/.git').exists()) {
        return ProjectType.git;
      }
      
    } catch (e) {
      debugPrint('Failed to detect project type: $e');
    }
    
    return ProjectType.unknown;
  }

  /// Get Node.js specific suggestions
  List<CommandSuggestion> _getNodeJSSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'npm install',
        type: SuggestionType.project,
        description: 'Install npm dependencies',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'npm run',
        type: SuggestionType.project,
        description: 'Run npm script',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'npm test',
        type: SuggestionType.project,
        description: 'Run tests',
        confidence: 0.7,
      ),
      CommandSuggestion(
        text: 'node index.js',
        type: SuggestionType.project,
        description: 'Run Node.js application',
        confidence: 0.7,
      ),
    ];
  }

  /// Get Python specific suggestions
  List<CommandSuggestion> _getPythonSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'python -m venv venv',
        type: SuggestionType.project,
        description: 'Create virtual environment',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'pip install -r requirements.txt',
        type: SuggestionType.project,
        description: 'Install Python dependencies',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'python main.py',
        type: SuggestionType.project,
        description: 'Run Python application',
        confidence: 0.7,
      ),
      CommandSuggestion(
        text: 'pytest',
        type: SuggestionType.project,
        description: 'Run tests',
        confidence: 0.7,
      ),
    ];
  }

  /// Get Dart specific suggestions
  List<CommandSuggestion> _getDartSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'flutter pub get',
        type: SuggestionType.project,
        description: 'Get Flutter dependencies',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'dart run',
        type: SuggestionType.project,
        description: 'Run Dart application',
        confidence: 0.7,
      ),
      CommandSuggestion(
        text: 'flutter test',
        type: SuggestionType.project,
        description: 'Run Flutter tests',
        confidence: 0.7,
      ),
      CommandSuggestion(
        text: 'dart analyze',
        type: SuggestionType.project,
        description: 'Analyze Dart code',
        confidence: 0.6,
      ),
    ];
  }

  /// Get Rust specific suggestions
  List<CommandSuggestion> _getRustSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'cargo build',
        type: SuggestionType.project,
        description: 'Build Rust project',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'cargo run',
        type: SuggestionType.project,
        description: 'Run Rust application',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'cargo test',
        type: SuggestionType.project,
        description: 'Run Rust tests',
        confidence: 0.7,
      ),
      CommandSuggestion(
        text: 'cargo check',
        type: SuggestionType.project,
        description: 'Check Rust code',
        confidence: 0.6,
      ),
    ];
  }

  /// Get Docker specific suggestions
  List<CommandSuggestion> _getDockerSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'docker build -t app .',
        type: SuggestionType.project,
        description: 'Build Docker image',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'docker run -p 8080:8080 app',
        type: SuggestionType.project,
        description: 'Run Docker container',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'docker-compose up',
        type: SuggestionType.project,
        description: 'Start Docker Compose',
        confidence: 0.7,
      ),
    ];
  }

  /// Get Git specific suggestions
  List<CommandSuggestion> _getGitSuggestions(String currentInput) {
    return [
      CommandSuggestion(
        text: 'git status',
        type: SuggestionType.project,
        description: 'Check Git status',
        confidence: 0.9,
      ),
      CommandSuggestion(
        text: 'git add .',
        type: SuggestionType.project,
        description: 'Stage all changes',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'git commit -m ""',
        type: SuggestionType.project,
        description: 'Commit changes',
        confidence: 0.8,
      ),
      CommandSuggestion(
        text: 'git push',
        type: SuggestionType.project,
        description: 'Push to remote',
        confidence: 0.7,
      ),
    ];
  }

  /// Record command usage
  void recordCommandUsage(String command) {
    // Update recent commands
    _recentCommands.insert(0, command);
    if (_recentCommands.length > 50) {
      _recentCommands.removeRange(50, _recentCommands.length);
    }
    
    // Update command usage statistics
    final existing = _commandUsage.where((u) => u.command == command).firstOrNull;
    if (existing != null) {
      existing.count++;
      existing.lastUsed = DateTime.now();
    } else {
      _commandUsage.add(CommandUsage(
        command: command,
        count: 1,
        lastUsed: DateTime.now(),
      ));
    }
    
    // Keep only recent usage
    if (_commandUsage.length > _maxHistorySize) {
      _commandUsage.removeFirst();
    }
    
    // Update NIM predictor history
    _nimPredictor.addToHistory(command);
  }

  /// Accept suggestion (user selected it)
  void acceptSuggestion(CommandSuggestion suggestion) {
    _acceptedSuggestions++;
    recordCommandUsage(suggestion.text);
  }

  /// Update current directory
  void updateCurrentDirectory(String directory) {
    _currentDirectory = directory;
    _scanCurrentDirectory();
  }

  /// Get suggestion statistics
  SuggestionStats getStats() {
    return SuggestionStats(
      totalSuggestions: _totalSuggestions,
      acceptedSuggestions: _acceptedSuggestions,
      acceptanceRate: _totalSuggestions > 0 ? _acceptedSuggestions / _totalSuggestions : 0.0,
      averageSuggestionTime: _totalSuggestions > 0 ? _totalSuggestionTime / _totalSuggestions : 0.0,
      totalSuggestionTime: _totalSuggestionTime,
      cacheSize: _suggestionCache.length,
      historySize: _commandUsage.length,
      currentDirectory: _currentDirectory,
      recentCommandsCount: _recentCommands.length,
    );
  }

  /// Clear all data
  void clear() {
    _suggestionCache.clear();
    _commandUsage.clear();
    _recentCommands.clear();
    _projectContexts.clear();
  }

  /// Dispose suggestion system
  void dispose() {
    _debounceTimer?.cancel();
    clear();
  }
}

/// Command suggestion model
class CommandSuggestion {
  final String text;
  final SuggestionType type;
  final String description;
  final double confidence;
  final Map<String, dynamic> metadata;

  const CommandSuggestion({
    required this.text,
    required this.type,
    required this.description,
    required this.confidence,
    required this.metadata,
  });
}

/// Suggestion types
enum SuggestionType {
  command,
  path,
  history,
  project,
  ai,
}

/// Command usage tracking
class CommandUsage {
  final String command;
  int count;
  DateTime lastUsed;

  CommandUsage({
    required this.command,
    required this.count,
    required this.lastUsed,
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

/// Project types
enum ProjectType {
  nodejs,
  python,
  dart,
  rust,
  docker,
  git,
  unknown,
}

/// Project context
class ProjectContext {
  final ProjectType type;
  final String rootPath;
  final Map<String, dynamic> metadata;

  const ProjectContext({
    required this.type,
    required this.rootPath,
    required this.metadata,
  });
}

/// Suggestion statistics
class SuggestionStats {
  final int totalSuggestions;
  final int acceptedSuggestions;
  final double acceptanceRate;
  final double averageSuggestionTime;
  final double totalSuggestionTime;
  final int cacheSize;
  final int historySize;
  final String currentDirectory;
  final int recentCommandsCount;

  const SuggestionStats({
    required this.totalSuggestions,
    required this.acceptedSuggestions,
    required this.acceptanceRate,
    required this.averageSuggestionTime,
    required this.totalSuggestionTime,
    required this.cacheSize,
    required this.historySize,
    required this.currentDirectory,
    required this.recentCommandsCount,
  });
}
