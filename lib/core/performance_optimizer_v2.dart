import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:process_run/process_run.dart';

/// Performance optimization suggestions for terminal and system
/// Provides intelligent recommendations for improving performance
class PerformanceOptimizerV2 {
  static const String _baseUrl = 'https://api.openai.com/v1';
  String? _apiKey;
  final Map<String, OptimizationSuggestion> _suggestionCache = {};
  final StreamController<OptimizationEvent> _eventController = StreamController<OptimizationEvent>.broadcast();
  
  Stream<OptimizationEvent> get events => _eventController.stream;
  Timer? _monitoringTimer;
  SystemMetrics? _currentMetrics;

  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey ?? _getApiKeyFromConfig();
    
    if (_apiKey != null) {
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.initialized,
        message: 'Performance Optimizer initialized with AI API',
      ));
      debugPrint('⚡ Performance Optimizer V2 initialized');
    } else {
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.initialized,
        message: 'Performance Optimizer V2 initialized without AI API',
      ));
      debugPrint('⚡ Performance Optimizer V2 initialized (local mode)');
    }
    
    // Start system monitoring
    _startMonitoring();
  }

  String? _getApiKeyFromConfig() {
    return Platform.environment['OPENAI_API_KEY'];
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _collectSystemMetrics();
    });
  }

  Future<void> _collectSystemMetrics() async {
    try {
      final metrics = await _getSystemMetrics();
      _currentMetrics = metrics;
      
      // Check for performance issues
      await _analyzePerformance(metrics);
    } catch (e) {
      debugPrint('Failed to collect system metrics: $e');
    }
  }

  Future<SystemMetrics> _getSystemMetrics() async {
    final metrics = SystemMetrics(timestamp: DateTime.now());
    
    try {
      // CPU usage
      final cpuResult = await run('top', ['-bn1', '-p', '1']);
      if (cpuResult.exitCode == 0) {
        final lines = cpuResult.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('%Cpu(s):')) {
            final cpuMatch = RegExp(r'(\d+\.?\d*)\s*%us').firstMatch(line);
            if (cpuMatch != null) {
              metrics.cpuUsage = double.tryParse(cpuMatch.group(1)!) ?? 0.0;
            }
          }
        }
      }
      
      // Memory usage
      final memResult = await run('free', ['-m']);
      if (memResult.exitCode == 0) {
        final lines = memResult.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('Mem:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final total = double.tryParse(parts[1]) ?? 0.0;
              final used = double.tryParse(parts[2]) ?? 0.0;
              metrics.memoryUsage = (used / total) * 100;
              metrics.memoryTotal = total;
              metrics.memoryUsed = used;
            }
          }
        }
      }
      
      // Disk usage
      final diskResult = await run('df', ['-h', '/']);
      if (diskResult.exitCode == 0) {
        final lines = diskResult.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('/dev/')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 5) {
              final total = parts[1];
              final used = parts[2];
              final avail = parts[3];
              final usePercent = parts[4];
              
              metrics.diskTotal = total;
              metrics.diskUsed = used;
              metrics.diskAvailable = avail;
              
              final percentMatch = RegExp(r'(\d+)%').firstMatch(usePercent);
              if (percentMatch != null) {
                metrics.diskUsage = double.tryParse(percentMatch.group(1)!) ?? 0.0;
              }
            }
          }
        }
      }
      
      // Network stats (simplified)
      try {
        final netResult = await run('cat', ['/proc/net/dev']);
        if (netResult.exitCode == 0) {
          final lines = netResult.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.startsWith('eth') || line.startsWith('en') || line.startsWith('wlan')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 10) {
                final received = int.tryParse(parts[1]) ?? 0;
                final transmitted = int.tryParse(parts[9]) ?? 0;
                metrics.networkReceived += received;
                metrics.networkTransmitted += transmitted;
              }
            }
          }
        }
      } catch (e) {
        // Network stats not available on all systems
      }
      
    } catch (e) {
      debugPrint('Error collecting metrics: $e');
    }
    
    return metrics;
  }

  Future<void> _analyzePerformance(SystemMetrics metrics) async {
    final issues = <String>[];
    
    // CPU analysis
    if (metrics.cpuUsage > 80) {
      issues.add('High CPU usage: ${metrics.cpuUsage.toStringAsFixed(1)}%');
    }
    
    // Memory analysis
    if (metrics.memoryUsage > 85) {
      issues.add('High memory usage: ${metrics.memoryUsage.toStringAsFixed(1)}%');
    }
    
    // Disk analysis
    if (metrics.diskUsage > 90) {
      issues.add('High disk usage: ${metrics.diskUsage.toStringAsFixed(1)}%');
    }
    
    if (issues.isNotEmpty) {
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.performance_issue_detected,
        message: 'Performance issues detected',
        data: {'issues': issues},
      ));
    }
  }

  Future<List<OptimizationSuggestion>> getSuggestions({
    String? category,
    SystemMetrics? metrics,
    bool useCache = true,
  }) async {
    final cacheKey = _generateCacheKey(category, metrics);
    
    if (useCache && _suggestionCache.containsKey(cacheKey)) {
      return [_suggestionCache[cacheKey]!];
    }

    if (_apiKey == null) {
      return _generateLocalSuggestions(category, metrics);
    }

    try {
      final suggestions = await _generateAISuggestions(category, metrics);
      
      for (final suggestion in suggestions) {
        _suggestionCache[_generateCacheKey(suggestion.category, null)] = suggestion;
      }
      
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.suggestions_generated,
        message: 'Performance optimization suggestions generated',
        data: {'category': category, 'count': suggestions.length},
      ));

      return suggestions;
    } catch (e) {
      debugPrint('Failed to generate AI suggestions: $e');
      return _generateLocalSuggestions(category, metrics);
    }
  }

  String _generateCacheKey(String? category, SystemMetrics? metrics) {
    return '${category ?? "all"}|${metrics?.cpuUsage ?? 0}|${metrics?.memoryUsage ?? 0}|${metrics?.diskUsage ?? 0}';
  }

  Future<List<OptimizationSuggestion>> _generateAISuggestions(
    String? category,
    SystemMetrics? metrics,
  ) async {
    final prompt = _buildOptimizationPrompt(category, metrics);
    
    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an expert system performance optimizer. Provide specific, actionable suggestions to improve terminal and system performance.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'max_tokens': 600,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final suggestions = data['choices'][0]['message']['content'];
      
      return _parseOptimizationResponse(suggestions, category);
    } else {
      throw Exception('Failed to get AI suggestions: ${response.statusCode}');
    }
  }

  String _buildOptimizationPrompt(String? category, SystemMetrics? metrics) {
    var prompt = 'Analyze system performance and provide optimization suggestions';
    
    if (category != null) {
      prompt += ' specifically for $category';
    }
    
    if (metrics != null) {
      prompt += ':\n\n';
      prompt += 'Current Metrics:\n';
      prompt += '- CPU Usage: ${metrics!.cpuUsage.toStringAsFixed(1)}%\n';
      prompt += '- Memory Usage: ${metrics.memoryUsage.toStringAsFixed(1)}% (${metrics.memoryUsed}/${metrics.memoryTotal} MB)\n';
      prompt += '- Disk Usage: ${metrics.diskUsage.toStringAsFixed(1)}% (${metrics.diskUsed} used, ${metrics.diskAvailable} available)\n';
    }
    
    prompt += '\nPlease provide:\n';
    prompt += '1. 3-5 specific optimization suggestions\n';
    prompt += '2. Priority level (low/medium/high)\n';
    prompt += '3. Expected impact (minimal/moderate/significant)\n';
    prompt += '4. Implementation complexity (easy/medium/hard)\n';
    prompt += '5. Specific commands or steps to implement\n';
    
    return prompt;
  }

  List<OptimizationSuggestion> _parseOptimizationResponse(String response, String? category) {
    final suggestions = <OptimizationSuggestion>[];
    final lines = response.split('\n');
    
    String? currentSuggestion;
    String? priority;
    String? impact;
    String? complexity;
    List<String> commands = [];
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('1.') || trimmed.toLowerCase().contains('suggestion')) {
        if (currentSuggestion != null) {
          suggestions.add(_createSuggestion(
            currentSuggestion!,
            priority ?? 'medium',
            impact ?? 'moderate',
            complexity ?? 'medium',
            commands,
            category ?? 'general',
            true,
          ));
        }
        currentSuggestion = '';
        commands = [];
      } else if (trimmed.startsWith('2.') || trimmed.toLowerCase().contains('priority')) {
        priority = _extractValue(trimmed);
      } else if (trimmed.startsWith('3.') || trimmed.toLowerCase().contains('impact')) {
        impact = _extractValue(trimmed);
      } else if (trimmed.startsWith('4.') || trimmed.toLowerCase().contains('complexity')) {
        complexity = _extractValue(trimmed);
      } else if (trimmed.startsWith('5.') || trimmed.toLowerCase().contains('command')) {
        if (trimmed.contains('```')) {
          // Extract code block
          final codeMatch = RegExp(r'```(?:\w+)?\n?(.*?)\n?```', dotAll: true).firstMatch(trimmed);
          if (codeMatch != null) {
            commands.add(codeMatch.group(1)!);
          }
        } else {
          commands.add(trimmed);
        }
      } else if (trimmed.isNotEmpty && !trimmed.startsWith(RegExp(r'\d+\.'))) {
        currentSuggestion = (currentSuggestion ?? '') + trimmed + ' ';
      }
    }
    
    // Add the last suggestion
    if (currentSuggestion != null) {
      suggestions.add(_createSuggestion(
        currentSuggestion!,
        priority ?? 'medium',
        impact ?? 'moderate',
        complexity ?? 'medium',
        commands,
        category ?? 'general',
        true,
      ));
    }
    
    return suggestions;
  }

  String _extractValue(String line) {
    final match = RegExp(r':\s*(.+)').firstMatch(line);
    return match?.group(1)?.trim() ?? '';
  }

  OptimizationSuggestion _createSuggestion(
    String title,
    String priority,
    String impact,
    String complexity,
    List<String> commands,
    String category,
    bool isAI,
  ) {
    return OptimizationSuggestion(
      title: title.trim(),
      priority: _parsePriority(priority),
      impact: _parseImpact(impact),
      complexity: _parseComplexity(complexity),
      commands: commands,
      category: category,
      generatedAt: DateTime.now(),
      isAI: isAI,
    );
  }

  SuggestionPriority _parsePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return SuggestionPriority.high;
      case 'medium':
        return SuggestionPriority.medium;
      case 'low':
        return SuggestionPriority.low;
      default:
        return SuggestionPriority.medium;
    }
  }

  SuggestionImpact _parseImpact(String impact) {
    switch (impact.toLowerCase()) {
      case 'significant':
        return SuggestionImpact.significant;
      case 'moderate':
        return SuggestionImpact.moderate;
      case 'minimal':
        return SuggestionImpact.minimal;
      default:
        return SuggestionImpact.moderate;
    }
  }

  SuggestionComplexity _parseComplexity(String complexity) {
    switch (complexity.toLowerCase()) {
      case 'hard':
        return SuggestionComplexity.hard;
      case 'medium':
        return SuggestionComplexity.medium;
      case 'easy':
        return SuggestionComplexity.easy;
      default:
        return SuggestionComplexity.medium;
    }
  }

  List<OptimizationSuggestion> _generateLocalSuggestions(
    String? category,
    SystemMetrics? metrics,
  ) {
    final suggestions = <OptimizationSuggestion>[];
    
    // CPU optimizations
    if (category == null || category == 'cpu') {
      if (metrics != null && metrics!.cpuUsage > 70) {
        suggestions.add(OptimizationSuggestion(
          title: 'Reduce CPU usage by managing processes',
          priority: SuggestionPriority.high,
          impact: SuggestionImpact.significant,
          complexity: SuggestionComplexity.easy,
          commands: [
            'top -o %CPU | head -10',
            'kill -9 <process_id>',
            'nice -n 10 <command>',
          ],
          category: 'cpu',
          generatedAt: DateTime.now(),
          isAI: false,
        ));
      }
      
      suggestions.add(OptimizationSuggestion(
        title: 'Optimize CPU frequency scaling',
        priority: SuggestionPriority.medium,
        impact: SuggestionImpact.moderate,
        complexity: SuggestionComplexity.medium,
        commands: [
          'cpupower frequency-set -g performance',
          'echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor',
        ],
        category: 'cpu',
        generatedAt: DateTime.now(),
        isAI: false,
      ));
    }
    
    // Memory optimizations
    if (category == null || category == 'memory') {
      if (metrics != null && metrics!.memoryUsage > 80) {
        suggestions.add(OptimizationSuggestion(
          title: 'Free up memory by clearing caches',
          priority: SuggestionPriority.high,
          impact: SuggestionImpact.moderate,
          complexity: SuggestionComplexity.easy,
          commands: [
            'sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches',
            'echo 2 | sudo tee /proc/sys/vm/drop_caches',
            'free -h',
          ],
          category: 'memory',
          generatedAt: DateTime.now(),
          isAI: false,
        ));
      }
      
      suggestions.add(OptimizationSuggestion(
        title: 'Configure swap space for better memory management',
        priority: SuggestionPriority.medium,
        impact: SuggestionImpact.moderate,
        complexity: SuggestionComplexity.medium,
        commands: [
          'swapon --show',
          'sudo fallocate -l 2G /swapfile',
          'sudo chmod 600 /swapfile',
          'sudo mkswap /swapfile',
          'sudo swapon /swapfile',
        ],
        category: 'memory',
        generatedAt: DateTime.now(),
        isAI: false,
      ));
    }
    
    // Disk optimizations
    if (category == null || category == 'disk') {
      if (metrics != null && metrics!.diskUsage > 85) {
        suggestions.add(OptimizationSuggestion(
          title: 'Clean up disk space',
          priority: SuggestionPriority.high,
          impact: SuggestionImpact.moderate,
          complexity: SuggestionComplexity.easy,
          commands: [
            'df -h',
            'du -sh * | sort -hr | head -10',
            'sudo apt autoremove',
            'sudo apt autoclean',
            'journalctl --vacuum-time=7d',
          ],
          category: 'disk',
          generatedAt: DateTime.now(),
          isAI: false,
        ));
      }
      
      suggestions.add(OptimizationSuggestion(
        title: 'Optimize disk I/O with better file system settings',
        priority: SuggestionPriority.medium,
        impact: SuggestionImpact.moderate,
        complexity: SuggestionComplexity.hard,
        commands: [
          'echo "deadline" | sudo tee /sys/block/sda/queue/scheduler',
          'echo "1" | sudo tee /sys/block/sda/queue/iosched/fifo_batch',
          'tune2fs -o journal_data_writeback /dev/sda1',
        ],
        category: 'disk',
        generatedAt: DateTime.now(),
        isAI: false,
      ));
    }
    
    // Network optimizations
    if (category == null || category == 'network') {
      suggestions.add(OptimizationSuggestion(
        title: 'Optimize network settings',
        priority: SuggestionPriority.medium,
        impact: SuggestionImpact.moderate,
        complexity: SuggestionComplexity.medium,
        commands: [
          'echo "net.core.rmem_max = 16777216" | sudo tee -a /etc/sysctl.conf',
          'echo "net.core.wmem_max = 16777216" | sudo tee -a /etc/sysctl.conf',
          'sudo sysctl -p',
          'ethtool -K eth0 on',
        ],
        category: 'network',
        generatedAt: DateTime.now(),
        isAI: false,
      ));
    }
    
    // Terminal optimizations
    if (category == null || category == 'terminal') {
      suggestions.add(OptimizationSuggestion(
        title: 'Optimize terminal performance',
        priority: SuggestionPriority.low,
        impact: SuggestionImpact.minimal,
        complexity: SuggestionComplexity.easy,
        commands: [
          'export TERM=xterm-256color',
          'export COLORTERM=truecolor',
          'echo "set -g history-limit 10000" >> ~/.tmux.conf',
          'echo "set -g mouse on" >> ~/.tmux.conf',
        ],
        category: 'terminal',
        generatedAt: DateTime.now(),
        isAI: false,
      ));
    }
    
    return suggestions;
  }

  Future<bool> applySuggestion(OptimizationSuggestion suggestion) async {
    try {
      for (final command in suggestion.commands) {
        final result = await run('bash', ['-c', command]);
        if (result.exitCode != 0) {
          _eventController.add(OptimizationEvent(
            type: OptimizationEventType.error,
            message: 'Failed to apply suggestion: ${result.stderr}',
            data: {'command': command, 'suggestion': suggestion.title},
          ));
          return false;
        }
      }
      
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.suggestion_applied,
        message: 'Optimization suggestion applied successfully',
        data: {'suggestion': suggestion.title},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.error,
        message: 'Error applying suggestion: $e',
        data: {'suggestion': suggestion.title},
      ));
      return false;
    }
  }

  Future<SystemBenchmark> runBenchmark() async {
    final benchmark = SystemBenchmark(startedAt: DateTime.now());
    
    try {
      // CPU benchmark
      final cpuStart = DateTime.now();
      await run('dd', ['if=/dev/zero', 'of=/dev/null', 'bs=1M', 'count=1000']);
      benchmark.cpuTime = DateTime.now().difference(cpuStart);
      
      // Memory benchmark
      final memStart = DateTime.now();
      await run('dd', ['if=/dev/zero', 'of=/dev/null', 'bs=1M', 'count=1000']);
      benchmark.memoryTime = DateTime.now().difference(memStart);
      
      // Disk benchmark
      final diskStart = DateTime.now();
      await run('dd', ['if=/dev/zero', 'of=/tmp/testfile', 'bs=1M', 'count=100']);
      benchmark.diskTime = DateTime.now().difference(diskStart);
      await run('rm', ['-f', '/tmp/testfile']);
      
      benchmark.completedAt = DateTime.now();
      
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.benchmark_completed,
        message: 'System benchmark completed',
        data: {
          'cpuTime': benchmark.cpuTime.inMilliseconds,
          'memoryTime': benchmark.memoryTime.inMilliseconds,
          'diskTime': benchmark.diskTime.inMilliseconds,
        },
      ));
      
    } catch (e) {
      benchmark.error = e.toString();
      _eventController.add(OptimizationEvent(
        type: OptimizationEventType.error,
        message: 'Benchmark failed: $e',
      ));
    }
    
    return benchmark;
  }

  void clearCache() {
    _suggestionCache.clear();
    _eventController.add(OptimizationEvent(
      type: OptimizationEventType.cache_cleared,
      message: 'Optimization cache cleared',
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'cacheSize': _suggestionCache.length,
      'hasApiKey': _apiKey != null,
      'currentMetrics': _currentMetrics?.toJson(),
      'totalSuggestions': _suggestionCache.length,
    };
  }

  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _eventController.close();
    debugPrint('⚡ Performance Optimizer V2 disposed');
  }
}

class SystemMetrics {
  final DateTime timestamp;
  double cpuUsage = 0.0;
  double memoryUsage = 0.0;
  double memoryTotal = 0.0;
  double memoryUsed = 0.0;
  double diskUsage = 0.0;
  String diskTotal = '0';
  String diskUsed = '0';
  String diskAvailable = '0';
  int networkReceived = 0;
  int networkTransmitted = 0;

  SystemMetrics({required this.timestamp});

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'cpuUsage': cpuUsage,
      'memoryUsage': memoryUsage,
      'memoryTotal': memoryTotal,
      'memoryUsed': memoryUsed,
      'diskUsage': diskUsage,
      'diskTotal': diskTotal,
      'diskUsed': diskUsed,
      'diskAvailable': diskAvailable,
      'networkReceived': networkReceived,
      'networkTransmitted': networkTransmitted,
    };
  }
}

class OptimizationSuggestion {
  final String title;
  final SuggestionPriority priority;
  final SuggestionImpact impact;
  final SuggestionComplexity complexity;
  final List<String> commands;
  final String category;
  final DateTime generatedAt;
  final bool isAI;

  OptimizationSuggestion({
    required this.title,
    required this.priority,
    required this.impact,
    required this.complexity,
    required this.commands,
    required this.category,
    required this.generatedAt,
    required this.isAI,
  });
}

class SystemBenchmark {
  final DateTime startedAt;
  DateTime? completedAt;
  Duration cpuTime = Duration.zero;
  Duration memoryTime = Duration.zero;
  Duration diskTime = Duration.zero;
  String? error;

  SystemBenchmark({required this.startedAt});
}

enum SuggestionPriority {
  low,
  medium,
  high,
}

enum SuggestionImpact {
  minimal,
  moderate,
  significant,
}

enum SuggestionComplexity {
  easy,
  medium,
  hard,
}

enum OptimizationEventType {
  initialized,
  performance_issue_detected,
  suggestions_generated,
  suggestion_applied,
  benchmark_completed,
  cache_cleared,
  error,
}

class OptimizationEvent {
  final OptimizationEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  OptimizationEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
