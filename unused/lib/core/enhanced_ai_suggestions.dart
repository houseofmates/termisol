import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Enhanced AI Suggestions
///
/// Generates context-aware AI suggestions for terminal commands and
/// programming tasks using multi-source intelligence including local
/// history, pattern recognition, and optional remote LLM backend.
class EnhancedAISuggestions {
  final Map<String, SuggestionContext> _contexts = {};
  final List<CommandPattern> _patterns = [];
  final List<SuggestionSource> _sources = [];
  final Map<String, List<Suggestion>> _cache = {};
  Timer? _cacheCleanupTimer;
  bool _llmEnabled = false;
  String? _llmEndpoint;
  String? _apiKey;

  static const int _maxCacheSize = 500;
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _maxSuggestions = 5;

  Future<void> initialize({
    bool enableLLM = false,
    String? llmEndpoint,
    String? apiKey,
  }) async {
    _llmEnabled = enableLLM;
    _llmEndpoint = llmEndpoint;
    _apiKey = apiKey;
    _loadDefaultPatterns();
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) => _cleanupCache());
    debugPrint('EnhancedAISuggestions initialized (LLM: $_llmEnabled)');
  }

  void addSuggestionSource(SuggestionSource source) {
    _sources.add(source);
  }

  void registerContext(String key, SuggestionContext context) {
    _contexts[key] = context;
  }

  Future<List<Suggestion>> getSuggestions({
    required String input,
    String? contextKey,
    SuggestionType? type,
    int maxResults = 5,
  }) async {
    final cacheKey = '${contextKey ?? 'global'}_${input}_${type?.name ?? 'all'}';
    final cached = _cache[cacheKey];
    if (cached != null && cached.first.timestamp.isAfter(DateTime.now().subtract(_cacheTtl))) {
      return cached.take(maxResults).toList();
    }

    final results = <Suggestion>[];
    final context = contextKey != null ? _contexts[contextKey] : null;

    results.addAll(_generatePatternSuggestions(input, context));
    results.addAll(_generateHistorySuggestions(input, context));
    results.addAll(_generateSemanticSuggestions(input, context));

    for (final source in _sources) {
      try {
        final sourceResults = await source.getSuggestions(input, context);
        results.addAll(sourceResults);
      } catch (e) {
        debugPrint('Suggestion source error: $e');
      }
    }

    if (_llmEnabled && _llmEndpoint != null) {
      try {
        final llmResults = await _getLLMSuggestions(input, context);
        results.addAll(llmResults);
      } catch (e) {
        debugPrint('LLM suggestion error: $e');
      }
    }

    if (type != null) {
      results.retainWhere((s) => s.type == type);
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    final deduped = _deduplicate(results, maxResults);
    _cache[cacheKey] = deduped;
    if (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }

    return deduped.take(maxResults).toList();
  }

  Future<List<Suggestion>> getCommandSuggestions(String partialCommand, {String? contextKey}) async {
    return getSuggestions(input: partialCommand, contextKey: contextKey, type: SuggestionType.command);
  }

  Future<List<Suggestion>> getFixSuggestions(String errorMessage, {String? contextKey}) async {
    return getSuggestions(input: errorMessage, contextKey: contextKey, type: SuggestionType.fix);
  }

  Future<List<Suggestion>> getCompletionSuggestions(String code, {String? contextKey}) async {
    return getSuggestions(input: code, contextKey: contextKey, type: SuggestionType.completion);
  }

  void recordSelection(Suggestion suggestion) {
    suggestion.selectionCount++;
    suggestion.lastSelected = DateTime.now();
  }

  List<Suggestion> _generatePatternSuggestions(String input, SuggestionContext? context) {
    final results = <Suggestion>[];
    final lowerInput = input.toLowerCase();
    for (final pattern in _patterns) {
      final score = pattern.match(lowerInput, context);
      if (score > 0.3) {
        results.add(Suggestion(
          text: pattern.replacement(input),
          description: pattern.description,
          type: pattern.type,
          confidence: score,
          sourceId: pattern.id,
        ));
      }
    }
    return results;
  }

  List<Suggestion> _generateHistorySuggestions(String input, SuggestionContext? context) {
    final results = <Suggestion>[];
    if (context?.recentCommands != null) {
      for (final cmd in context!.recentCommands!) {
        if (cmd.toLowerCase().startsWith(input.toLowerCase())) {
          results.add(Suggestion(
            text: cmd,
            description: 'Previously used command',
            confidence: 0.7,
            sourceId: 'history',
          ));
        }
      }
    }
    return results;
  }

  List<Suggestion> _generateSemanticSuggestions(String input, SuggestionContext? context) {
    final results = <Suggestion>[];
    if (context?.workingDirectory != null) {
      final dir = context!.workingDirectory!;
      if (input.contains('test') || input.contains('tset')) {
        results.add(Suggestion(
          text: 'npm test',
          description: 'Run tests in $dir',
          confidence: 0.6,
          sourceId: 'semantic',
        ));
      }
      if (input.startsWith('git')) {
        results.addAll([
          Suggestion(text: 'git status', description: 'Check repository status', confidence: 0.8, sourceId: 'semantic'),
          Suggestion(text: 'git add -A && git commit -m "update"', description: 'Stage and commit all changes', confidence: 0.7, sourceId: 'semantic'),
          Suggestion(text: 'git push', description: 'Push to remote', confidence: 0.7, sourceId: 'semantic'),
        ]);
      }
    }
    return results;
  }

  Future<List<Suggestion>> _getLLMSuggestions(String input, SuggestionContext? context) async {
    if (!_llmEnabled || _llmEndpoint == null || _apiKey == null) return [];
    try {
      final prompt = _buildLLMPrompt(input, context);
      final response = await http.post(
        Uri.parse(_llmEndpoint!),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: json.encode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'system', 'content': 'You are a terminal command suggestion engine. Return ONLY a JSON array of suggestions.'},
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 200,
          'temperature': 0.3,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = (choices.first as Map<String, dynamic>)['message']?['content'] ?? '';
          return _parseLLMResponse(content.toString());
        }
      }
    } catch (e) {
      debugPrint('LLM API call failed: $e');
    }
    return [];
  }

  String _buildLLMPrompt(String input, SuggestionContext? context) {
    final buf = StringBuffer();
    buf.writeln('Suggest up to 5 terminal commands for: "$input"');
    if (context?.workingDirectory != null) {
      buf.writeln('Working directory: ${context!.workingDirectory}');
    }
    if (context?.recentCommands != null && context!.recentCommands!.isNotEmpty) {
      buf.writeln('Recent commands: ${context.recentCommands!.take(3).join(", ")}');
    }
    buf.writeln('Return as JSON array of objects with fields: text, description, type(command/fix/completion)');
    return buf.toString();
  }

  List<Suggestion> _parseLLMResponse(String response) {
    try {
      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start >= 0 && end > start) {
        final jsonStr = response.substring(start, end + 1);
        final list = (json.decode(jsonStr) as List).cast<Map<String, dynamic>>();
        return list.map((m) {
          return Suggestion(
            text: (m['text'] as String?) ?? '',
            description: (m['description'] as String?) ?? '',
            type: SuggestionType.values.byName(m['type']?.toString() ?? 'command'),
            sourceId: 'llm',
          );
        }).where((s) => s.text.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('Failed to parse LLM response: $e');
    }
    return [];
  }

  List<Suggestion> _deduplicate(List<Suggestion> suggestions, int limit) {
    final seen = <String>{};
    final result = <Suggestion>[];
    for (final s in suggestions) {
      if (!seen.contains(s.text) && result.length < limit) {
        seen.add(s.text);
        result.add(s);
      }
    }
    return result;
  }

  void _cleanupCache() {
    final now = DateTime.now();
    _cache.removeWhere((_, v) => v.isNotEmpty && v.first.timestamp.isBefore(now.subtract(_cacheTtl)));
  }

  void _loadDefaultPatterns() {
    _patterns.addAll([
      CommandPattern(id: 'git_push', description: 'Git push to remote', type: SuggestionType.command,
        matchFunc: (input, ctx) => input.toLowerCase().startsWith('git pu') ? 0.9 : 0.0,
        replaceFunc: (input) => 'git push',
      ),
      CommandPattern(id: 'npm_install', description: 'Install npm dependencies', type: SuggestionType.command,
        matchFunc: (input, ctx) => input.toLowerCase().contains('npm ins') ? 0.9 : 0.0,
        replaceFunc: (input) => 'npm install',
      ),
      CommandPattern(id: 'sudo_fix', description: 'Retry with sudo', type: SuggestionType.fix,
        matchFunc: (input, ctx) => input.toLowerCase().contains('permission denied') ? 0.8 : 0.0,
        replaceFunc: (input) => 'sudo !!',
      ),
      CommandPattern(id: 'list_files', description: 'List files in directory', type: SuggestionType.command,
        matchFunc: (input, ctx) => input.toLowerCase().startsWith('ls') ? 0.7 : 0.0,
        replaceFunc: (input) => 'ls -lah',
      ),
    ]);
  }

  Future<void> dispose() async {
    _cacheCleanupTimer?.cancel();
    _cache.clear();
    _patterns.clear();
    _sources.clear();
    _contexts.clear();
  }
}

enum SuggestionType { command, fix, completion, workflow, documentation }

class Suggestion {
  final String text;
  final String description;
  final SuggestionType type;
  final double confidence;
  final String sourceId;
  final DateTime timestamp;
  int selectionCount;
  DateTime? lastSelected;

  Suggestion({
    required this.text,
    required this.description,
    this.type = SuggestionType.command,
    this.confidence = 0.5,
    this.sourceId = 'local',
    DateTime? timestamp,
    this.selectionCount = 0,
    this.lastSelected,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SuggestionContext {
  final String? workingDirectory;
  final List<String>? recentCommands;
  final String? userRole;
  final Map<String, dynamic>? environment;

  SuggestionContext({this.workingDirectory, this.recentCommands, this.userRole, this.environment});
}

abstract class SuggestionSource {
  Future<List<Suggestion>> getSuggestions(String input, SuggestionContext? context);
}

class CommandPattern {
  final String id;
  final String description;
  final SuggestionType type;
  final double Function(String input, SuggestionContext? ctx) matchFunc;
  final String Function(String input) replaceFunc;

  CommandPattern({
    required this.id,
    required this.description,
    required this.type,
    required this.matchFunc,
    required this.replaceFunc,
  });

  double match(String input, SuggestionContext? context) => matchFunc(input, context);
  String replacement(String input) => replaceFunc(input);
}