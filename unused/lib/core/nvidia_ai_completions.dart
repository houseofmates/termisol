import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// NVIDIA AI Completions - Smart completions using NVIDIA AI endpoint
/// 
/// Implements AI-powered completions:
/// - NVIDIA AI endpoint integration
/// - Context-aware command suggestions
/// - Intelligent file path completions
/// - Learning from user behavior
/// - Offline fallback with local data
class NVIDIAAICompletions {
  bool _isInitialized = false;
  
  // AI endpoint configuration
  String _nvidiaEndpoint = 'https://api.nvidia.com/v1/ai/completions';
  String? _apiKey;
  Duration _timeout = const Duration(seconds: 5);
  int _maxRetries = 3;
  
  // Completion state
  final Map<String, List<AICompletion>> _completionCache = {};
  final Map<String, CompletionContext> _contexts = {};
  final Queue<CompletionRequest> _requestQueue = Queue();
  
  // Learning and adaptation
  final Map<String, double> _completionWeights = {};
  final Map<String, int> _usageFrequency = {};
  final Map<String, DateTime> _lastUsed = {};
  
  // Performance optimization
  final Map<String, List<String>> _localCompletions = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  Timer? _cacheCleanupTimer;
  
  NVIDIAAICompletions();
  
  bool get isInitialized => _isInitialized;
  String? get apiKey => _apiKey;
  
  /// Initialize NVIDIA AI completions
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Initialize local completions
      await _initializeLocalCompletions();
      
      // Setup cache cleanup
      _setupCacheCleanup();
      
      _isInitialized = true;
      debugPrint('🤖 NVIDIA AI Completions initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize NVIDIA AI Completions: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/nvidia_ai_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _nvidiaEndpoint = data['endpoint'] as String? ?? _nvidiaEndpoint;
        _apiKey = data['apiKey'] as String?;
        _timeout = Duration(milliseconds: data['timeoutMs'] as int? ?? 5000);
        _maxRetries = data['maxRetries'] as int? ?? 3;
      }
      
      // Load API key from environment
      _apiKey ??= Platform.environment['NVIDIA_AI_API_KEY'];
      
      debugPrint('⚙️ NVIDIA AI configuration loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load NVIDIA AI configuration: $e');
    }
  }
  
  /// Initialize local completions
  Future<void> _initializeLocalCompletions() async {
    try {
      // Load local command completions
      _localCompletions.addAll({
        'git': ['status', 'add', 'commit', 'push', 'pull', 'branch', 'checkout', 'merge', 'rebase', 'log', 'diff', 'stash'],
        'docker': ['run', 'build', 'push', 'pull', 'ps', 'stop', 'start', 'rm', 'rmi', 'exec', 'logs'],
        'npm': ['install', 'run', 'start', 'build', 'test', 'publish', 'update', 'audit', 'ls'],
        'yarn': ['add', 'remove', 'install', 'run', 'start', 'build', 'test', 'upgrade'],
        'pip': ['install', 'uninstall', 'list', 'show', 'search', 'freeze', 'install --user'],
        'conda': ['create', 'activate', 'deactivate', 'install', 'remove', 'list', 'search', 'update'],
        'kubectl': ['get', 'apply', 'delete', 'create', 'edit', 'replace', 'logs', 'exec', 'port-forward'],
        'aws': ['s3', 'ec2', 'lambda', 'cloudformation', 'iam', 'dynamodb', 'rds'],
        'gcloud': ['compute', 'storage', 'sql', 'functions', 'run', 'deploy'],
        'az': ['vm', 'storage', 'sql', 'function', 'webapp', 'container'],
        'terraform': ['plan', 'apply', 'destroy', 'init', 'validate', 'import', 'output', 'state'],
        'ansible': ['playbook', 'inventory', 'vault', 'galaxy', 'role', 'module'],
        'kubernetes': ['cluster', 'node', 'pod', 'service', 'deployment', 'configmap', 'secret'],
        'helm': ['install', 'uninstall', 'upgrade', 'rollback', 'list', 'repo', 'search'],
        'make': ['all', 'clean', 'install', 'test', 'build', 'run', 'help'],
        'cmake': ['configure', 'build', 'install', 'test', 'package', 'clean'],
        'gradle': ['build', 'test', 'run', 'clean', 'assemble', 'dependencies', 'wrapper'],
        'mvn': ['compile', 'test', 'package', 'install', 'clean', 'dependency', 'site'],
        'cargo': ['build', 'test', 'run', 'clean', 'check', 'doc', 'publish', 'install'],
        'go': ['run', 'build', 'test', 'mod', 'get', 'install', 'clean', 'vet', 'fmt'],
        'python': ['-m', '-c', 'import', 'from', 'def', 'class', 'if', 'for', 'while', 'try', 'except'],
        'node': ['--version', '--help', 'run', 'start', 'test', 'build', 'install', 'update'],
        'rust': ['run', 'build', 'test', 'check', 'clippy', 'fmt', 'doc', 'publish'],
        'java': ['-jar', '-cp', '-classpath', 'javac', 'javadoc', 'jdb', 'jstack'],
        'scala': ['scalac', 'scala', 'sbt', 'sbt compile', 'sbt run', 'sbt test'],
        'ruby': ['gem', 'ruby', 'irb', 'rake', 'bundle', 'rails', 'rspec'],
        'php': ['php', 'composer', 'artisan', 'phpunit', 'phpstan', 'xdebug'],
        'bash': ['echo', 'printf', 'read', 'source', 'export', 'alias', 'function', 'if', 'for', 'while'],
        'zsh': ['echo', 'printf', 'read', 'source', 'export', 'alias', 'function', 'if', 'for', 'while'],
        'fish': ['echo', 'printf', 'read', 'source', 'set', 'alias', 'function', 'if', 'for', 'while'],
        'vim': ['!', ':w', ':q', ':x', ':wq', '/search', '%s', 'yank', 'put'],
        'nano': ['Ctrl+O', 'Ctrl+X', 'Ctrl+W', 'Ctrl+R', 'Ctrl+K', 'Ctrl+U'],
        'emacs': ['C-x C-s', 'C-x C-f', 'C-x C-c', 'C-x C-w', 'M-x', 'C-g'],
        'tmux': ['new-session', 'attach-session', 'list-sessions', 'kill-session', 'switch-client'],
        'screen': ['ls', 'create', 'attach', 'detach', 'kill', 'quit', 'title'],
        'ssh': ['ssh', 'scp', 'sftp', 'ssh-keygen', 'ssh-copy-id', 'ssh-agent'],
        'curl': ['-X', '-H', '-d', '--data', '--form', '-o', '-L', '-k', '--insecure'],
        'wget': ['-O', '--output', '--continue', '--limit-rate', '--timeout', '--tries'],
        'rsync': ['-avz', '--delete', '--exclude', '--include', '--progress', '--dry-run'],
        'tar': ['-xvf', '-cvf', '-tvf', '-zcvf', '-zxvf', '-jcvf', '-jxvf'],
        'gzip': ['-d', '-k', '-l', '-r', '-t', '-v', '--fast', '--best'],
        'find': ['-name', '-type', '-exec', '-mtime', '-size', '-perm', '-user', '-group'],
        'grep': ['-i', '-r', '-n', '-E', '-F', '-v', '-c', '-o', '-A', '-B', '-C'],
        'sed': ['-i', '-e', '-f', '-n', '-r', '-E', '-z'],
        'awk': ['-F', '-v', '-f', '-OFS', '-FS', '-vRS', '-vORS'],
      });
      
      debugPrint('📚 Initialized ${_localCompletions.length} local completion sets');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize local completions: $e');
    }
  }
  
  /// Setup cache cleanup
  void _setupCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupCache();
    });
    debugPrint('🧹 Cache cleanup timer started');
  }
  
  /// Get smart completions
  Future<List<AICompletion>> getCompletions(
    String input, {
    String? workingDirectory,
    String? shell,
    List<String>? environment,
    CompletionContext? context,
    int maxSuggestions = 10,
    bool useCache = true,
    bool preferLocal = true,
  }) async {
    if (!_isInitialized) return [];
    
    try {
      // Update usage tracking
      _updateUsage(input);
      
      // Check cache first
      if (useCache) {
        final cached = _getCachedCompletions(input, context);
        if (cached.isNotEmpty) {
          return cached.take(maxSuggestions).toList();
        }
      }
      
      // Try local completions first
      final localCompletions = preferLocal 
          ? _getLocalCompletions(input, context)
          : <AICompletion>[];
      
      // If we have good local completions, return them
      if (localCompletions.length >= 3) {
        return localCompletions.take(maxSuggestions).toList();
      }
      
      // Get AI completions
      final aiCompletions = await _getAICompletions(
        input,
        workingDirectory: workingDirectory,
        shell: shell,
        environment: environment,
        context: context,
        maxSuggestions: maxSuggestions - localCompletions.length,
      );
      
      // Combine local and AI completions
      final allCompletions = <AICompletion>[];
      allCompletions.addAll(localCompletions);
      allCompletions.addAll(aiCompletions);
      
      // Sort by relevance
      allCompletions.sort((a, b) => _calculateCompletionScore(b, input).compareTo(_calculateCompletionScore(a, input)));
      
      // Cache results
      _cacheCompletions(input, context, allCompletions.take(maxSuggestions).toList());
      
      return allCompletions.take(maxSuggestions).toList();
    } catch (e) {
      debugPrint('⚠️ Failed to get completions: $e');
      return [];
    }
  }
  
  /// Get local completions
  List<AICompletion> _getLocalCompletions(String input, CompletionContext? context) {
    final completions = <AICompletion>[];
    final words = input.toLowerCase().split(' ');
    final lastWord = words.isNotEmpty ? words.last : '';
    
    if (lastWord.isEmpty) return completions;
    
    // Check command completions
    for (final entry in _localCompletions.entries) {
      final command = entry.key;
      final suggestions = entry.value;
      
      if (command.startsWith(lastWord)) {
        for (final suggestion in suggestions) {
          completions.add(AICompletion(
            text: suggestion,
            type: CompletionType.command,
            source: CompletionSource.local,
            confidence: 0.9,
            metadata: {
              'command': command,
              'suggestion': suggestion,
            },
          ));
        }
      }
    }
    
    // Check file path completions
    if (context != null && context.workingDirectory != null) {
      completions.addAll(_getFilePathCompletions(lastWord, context.workingDirectory!));
    }
    
    return completions;
  }
  
  /// Get file path completions
  List<AICompletion> _getFilePathCompletions(String partial, String workingDirectory) {
    final completions = <AICompletion>[];
    
    try {
      final directory = Directory(workingDirectory);
      if (!await directory.exists()) return completions;
      
      await for (final entity in directory.list()) {
        final name = entity.path.split('/').last;
        if (name.toLowerCase().startsWith(partial.toLowerCase())) {
          final isDirectory = entity is Directory;
          
          completions.add(AICompletion(
            text: name + (isDirectory ? '/' : ''),
            type: isDirectory ? CompletionType.directory : CompletionType.file,
            source: CompletionSource.local,
            confidence: 0.8,
            metadata: {
              'path': entity.path,
              'isDirectory': isDirectory,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get file path completions: $e');
    }
    
    return completions;
  }
  
  /// Get AI completions from NVIDIA endpoint
  Future<List<AICompletion>> _getAICompletions(
    String input, {
    String? workingDirectory,
    String? shell,
    List<String>? environment,
    CompletionContext? context,
    int maxSuggestions = 10,
  }) async {
    if (_apiKey == null) {
      debugPrint('⚠️ NVIDIA AI API key not configured');
      return [];
    }
    
    try {
      final request = AICompletionRequest(
        input: input,
        workingDirectory: workingDirectory,
        shell: shell,
        environment: environment ?? [],
        context: context ?? CompletionContext(),
        maxSuggestions: maxSuggestions,
        features: [
          'command_completion',
          'file_path_completion',
          'context_awareness',
          'learning_adaptation',
        ],
      );
      
      final response = await _makeAPIRequest(request);
      
      if (response.success && response.completions != null) {
        return response.completions!.map((completion) => AICompletion(
          text: completion.text,
          type: _parseCompletionType(completion.type),
          source: CompletionSource.nvidia_ai,
          confidence: completion.confidence,
          metadata: completion.metadata,
        )).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get AI completions: $e');
    }
    
    return [];
  }
  
  /// Make API request to NVIDIA endpoint
  Future<AICompletionResponse> _makeAPIRequest(AICompletionRequest request) async {
    final url = Uri.parse('$_nvidiaEndpoint/completions');
    
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'User-Agent': 'Termisol/1.0.0',
    };
    
    final body = jsonEncode({
      'input': request.input,
      'working_directory': request.workingDirectory,
      'shell': request.shell,
      'environment': request.environment,
      'context': request.context.toJson(),
      'max_suggestions': request.maxSuggestions,
      'features': request.features,
      'user_preferences': {
        'preferred_types': ['command', 'file', 'directory'],
        'max_history_items': 5,
        'enable_learning': true,
      },
    });
    
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final httpClient = HttpClient();
        final httpRequest = await httpClient.postUrl(url, headers: headers);
        
        await httpRequest.add(utf8.encode(body));
        final httpResponse = await httpRequest.close();
        
        if (httpResponse.statusCode == 200) {
          final responseBody = await httpResponse.transform(utf8.decoder).join();
          final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
          
          return AICompletionResponse.fromJson(responseData);
        } else {
          debugPrint('⚠️ NVIDIA AI API error: ${httpResponse.statusCode}');
        }
      } catch (e) {
        debugPrint('⚠️ NVIDIA AI API request failed (attempt ${attempt + 1}): $e');
        
        if (attempt == _maxRetries - 1) {
          return AICompletionResponse(
            success: false,
            error: 'Max retries exceeded: $e',
          );
        }
      }
    }
    
    return AICompletionResponse(
      success: false,
      error: 'Unknown error',
    );
  }
  
  /// Parse completion type from API response
  CompletionType _parseCompletionType(String type) {
    switch (type.toLowerCase()) {
      case 'command':
        return CompletionType.command;
      case 'file':
        return CompletionType.file;
      case 'directory':
        return CompletionType.directory;
      case 'argument':
        return CompletionType.argument;
      case 'flag':
        return CompletionType.flag;
      case 'variable':
        return CompletionType.variable;
      case 'function':
        return CompletionType.function;
      default:
        return CompletionType.unknown;
    }
  }
  
  /// Calculate completion score
  double _calculateCompletionScore(AICompletion completion, String input) {
    double score = completion.confidence;
    
    // Boost for exact prefix matches
    if (completion.text.toLowerCase().startsWith(input.toLowerCase())) {
      score *= 1.5;
    }
    
    // Boost for frequently used completions
    final frequency = _usageFrequency[completion.text] ?? 0;
    score *= (1.0 + frequency * 0.1);
    
    // Boost for recently used completions
    final lastUsed = _lastUsed[completion.text];
    if (lastUsed != null) {
      final hoursSince = DateTime.now().difference(lastUsed!).inHours;
      score *= max(0.5, 1.0 - (hoursSince * 0.01));
    }
    
    // Boost for local completions
    if (completion.source == CompletionSource.local) {
      score *= 1.2;
    }
    
    return score;
  }
  
  /// Update usage tracking
  void _updateUsage(String completion) {
    _usageFrequency[completion] = (_usageFrequency[completion] ?? 0) + 1;
    _lastUsed[completion] = DateTime.now();
  }
  
  /// Get cached completions
  List<AICompletion> _getCachedCompletions(String input, CompletionContext? context) {
    final cacheKey = _getCacheKey(input, context);
    final cached = _completionCache[cacheKey];
    
    if (cached != null) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && DateTime.now().difference(timestamp).inMinutes < 5) {
        return cached;
      }
    }
    
    return [];
  }
  
  /// Cache completions
  void _cacheCompletions(String input, CompletionContext? context, List<AICompletion> completions) {
    final cacheKey = _getCacheKey(input, context);
    _completionCache[cacheKey] = completions;
    _cacheTimestamps[cacheKey] = DateTime.now();
  }
  
  /// Get cache key
  String _getCacheKey(String input, CompletionContext? context) {
    final parts = [input.toLowerCase()];
    if (context != null) {
      parts.add(context.workingDirectory ?? '');
      parts.add(context.shell ?? '');
    }
    return parts.join('|');
  }
  
  /// Clean up cache
  void _cleanupCache() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    
    final keysToRemove = <String>[];
    for (final entry in _cacheTimestamps.entries) {
      if (entry.value.isBefore(cutoff)) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _completionCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${keysToRemove.length} expired cache entries');
    }
  }
  
  /// Add custom completion
  void addCustomCompletion(String command, List<String> completions) {
    _localCompletions[command] = completions;
    debugPrint('➕ Added custom completions for command: $command');
  }
  
  /// Remove custom completion
  void removeCustomCompletion(String command) {
    _localCompletions.remove(command);
    debugPrint('➖ Removed custom completions for command: $command');
  }
  
  /// Get completion statistics
  CompletionStatistics getStatistics() {
    return CompletionStatistics(
      totalCompletions: _completionCache.values.fold(0, (sum, list) => sum + list.length),
      cachedKeys: _completionCache.length,
      localCommands: _localCompletions.length,
      usageFrequency: _usageFrequency.length,
      mostUsedCompletions: _usageFrequency.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value))
          .take(10)
          .map((e) => e.key)
          .toList(),
      averageCacheAge: _calculateAverageCacheAge(),
    );
  }
  
  /// Calculate average cache age
  Duration _calculateAverageCacheAge() {
    if (_cacheTimestamps.isEmpty) return Duration.zero;
    
    final now = DateTime.now();
    final totalAge = _cacheTimestamps.values
        .map((timestamp) => now.difference(timestamp))
        .fold(Duration.zero, (sum, duration) => sum + duration);
    
    return Duration(
      milliseconds: (totalAge.inMilliseconds / _cacheTimestamps.length).round(),
    );
  }
  
  /// Clear cache
  void clearCache() {
    _completionCache.clear();
    _cacheTimestamps.clear();
    debugPrint('🗑️ Completion cache cleared');
  }
  
  /// Export completion data
  String exportCompletionData() {
    final data = {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'local_completions': _localCompletions,
      'usage_frequency': _usageFrequency,
      'last_used': _lastUsed.map((k, v) => MapEntry(k, v.toIso8601String())),
      'completion_weights': _completionWeights,
    };
    
    return jsonEncode(data);
  }
  
  /// Import completion data
  bool importCompletionData(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Import local completions
      final localCompletions = data['local_completions'] as Map<String, dynamic>?;
      if (localCompletions != null) {
        for (final entry in localCompletions.entries) {
          _localCompletions[entry.key] = List<String>.from(entry.value as List);
        }
      }
      
      // Import usage frequency
      final usageFrequency = data['usage_frequency'] as Map<String, dynamic>?;
      if (usageFrequency != null) {
        for (final entry in usageFrequency.entries) {
          _usageFrequency[entry.key] = entry.value as int;
        }
      }
      
      // Import last used
      final lastUsed = data['last_used'] as Map<String, dynamic>?;
      if (lastUsed != null) {
        for (final entry in lastUsed.entries) {
          _lastUsed[entry.key] = DateTime.parse(entry.value as String);
        }
      }
      
      debugPrint('📥 Imported completion data successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import completion data: $e');
      return false;
    }
  }
  
  /// Save configuration
  Future<void> saveConfiguration() async {
    try {
      final config = {
        'endpoint': _nvidiaEndpoint,
        'apiKey': _apiKey,
        'timeoutMs': _timeout.inMilliseconds,
        'maxRetries': _maxRetries,
      };
      
      final configFile = File('${Platform.environment['HOME']}/.termisol/nvidia_ai_config.json');
      await configFile.writeAsString(jsonEncode(config));
      
      debugPrint('💾 NVIDIA AI configuration saved');
    } catch (e) {
      debugPrint('⚠️ Failed to save NVIDIA AI configuration: $e');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _cacheCleanupTimer?.cancel();
    _completionCache.clear();
    _contexts.clear();
    _requestQueue.clear();
    _completionWeights.clear();
    _usageFrequency.clear();
    _lastUsed.clear();
    _localCompletions.clear();
    _cacheTimestamps.clear();
    
    _isInitialized = false;
    debugPrint('🤖 NVIDIA AI Completions disposed');
  }
}

/// AI completion data structure
class AICompletion {
  final String text;
  final CompletionType type;
  final CompletionSource source;
  final double confidence;
  final Map<String, dynamic> metadata;
  
  AICompletion({
    required this.text,
    required this.type,
    required this.source,
    required this.confidence,
    required this.metadata,
  });
}

/// Completion request data structure
class AICompletionRequest {
  final String input;
  final String? workingDirectory;
  final String? shell;
  final List<String> environment;
  final CompletionContext context;
  final int maxSuggestions;
  final List<String> features;
  
  AICompletionRequest({
    required this.input,
    this.workingDirectory,
    this.shell,
    required this.environment,
    required this.context,
    required this.maxSuggestions,
    required this.features,
  });
}

/// AI completion response data structure
class AICompletionResponse {
  final bool success;
  final List<AICompletion>? completions;
  final String? error;
  final Map<String, dynamic>? metadata;
  
  AICompletionResponse({
    required this.success,
    this.completions,
    this.error,
    this.metadata,
  });
  
  factory AICompletionResponse.fromJson(Map<String, dynamic> json) {
    return AICompletionResponse(
      success: json['success'] as bool,
      completions: (json['completions'] as List<dynamic>?)
          ?.map((c) => AICompletion(
            text: c['text'] as String,
            type: CompletionType.values.firstWhere(
              (t) => t.toString() == c['type'],
              orElse: () => CompletionType.unknown,
            ),
            source: CompletionSource.nvidia_ai,
            confidence: (c['confidence'] as num).toDouble(),
            metadata: c['metadata'] as Map<String, dynamic>? ?? {},
          ))
          .toList(),
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Completion context data structure
class CompletionContext {
  final String? workingDirectory;
  final String? shell;
  final String? command;
  final List<String>? arguments;
  final Map<String, String>? environment;
  final String? gitBranch;
  final bool? inGitRepo;
  
  CompletionContext({
    this.workingDirectory,
    this.shell,
    this.command,
    this.arguments,
    this.environment,
    this.gitBranch,
    this.inGitRepo,
  });
  
  Map<String, dynamic> toJson() => {
    'working_directory': workingDirectory,
    'shell': shell,
    'command': command,
    'arguments': arguments,
    'environment': environment,
    'git_branch': gitBranch,
    'in_git_repo': inGitRepo,
  };
}

/// Completion type enumeration
enum CompletionType {
  command,
  file,
  directory,
  argument,
  flag,
  variable,
  function,
  unknown,
}

/// Completion source enumeration
enum CompletionSource {
  local,
  nvidia_ai,
  hybrid,
}

/// Completion statistics data structure
class CompletionStatistics {
  final int totalCompletions;
  final int cachedKeys;
  final int localCommands;
  final int usageFrequency;
  final List<String> mostUsedCompletions;
  final Duration averageCacheAge;
  
  CompletionStatistics({
    required this.totalCompletions,
    required this.cachedKeys,
    required this.localCommands,
    required this.usageFrequency,
    required this.mostUsedCompletions,
    required this.averageCacheAge,
  });
}
