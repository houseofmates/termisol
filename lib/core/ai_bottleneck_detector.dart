import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:process_run/process_run.dart';

/// AI Bottleneck Detection and Auto-Fixing System
/// 
/// Detects performance bottlenecks using AI analysis and automatically
/// applies fixes to optimize system performance.
class AIBottleneckDetector {
  static final AIBottleneckDetector _instance = AIBottleneckDetector._internal();
  factory AIBottleneckDetector() => _instance;
  AIBottleneckDetector._internal();

  bool _isInitialized = false;
  
  // Monitoring state
  Timer? _monitoringTimer;
  final List<PerformanceSnapshot> _performanceHistory = [];
  final Map<String, BottleneckPattern> _bottleneckPatterns = {};
  
  // Auto-fix state
  final Map<String, AutoFix> _autoFixes = {};
  final List<FixHistory> _fixHistory = [];
  bool _autoFixEnabled = true;
  
  // Event system
  final _bottleneckController = StreamController<BottleneckEvent>.broadcast();
  Stream<BottleneckEvent> get events => _bottleneckController.stream;
  
  // Configuration
  static const Duration _monitoringInterval = Duration(seconds: 30);
  static const int _maxHistorySize = 1000;
  static const double _bottleneckThreshold = 0.8;
  static const int _maxFixAttempts = 3;
  
  bool get isInitialized => _isInitialized;
  bool get autoFixEnabled => _autoFixEnabled;
  int get detectedBottlenecks => _bottleneckPatterns.length;
  int get appliedFixes => _fixHistory.where((f) => f.applied).length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load bottleneck patterns
      await _loadBottleneckPatterns();
      
      // Load auto-fixes
      await _loadAutoFixes();
      
      // Load fix history
      await _loadFixHistory();
      
      // Start monitoring
      _startMonitoring();
      
      _isInitialized = true;
      debugPrint('🔍 AI Bottleneck Detector initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize AI Bottleneck Detector: $e');
    }
  }

  Future<void> _loadBottleneckPatterns() async {
    // Initialize common bottleneck patterns
    _bottleneckPatterns.addAll({
      'high_cpu_usage': BottleneckPattern(
        id: 'high_cpu_usage',
        type: BottleneckType.cpu,
        threshold: 80.0,
        description: 'High CPU usage detected',
        severity: BottleneckSeverity.high,
        metrics: ['cpu_percent'],
      ),
      'high_memory_usage': BottleneckPattern(
        id: 'high_memory_usage',
        type: BottleneckType.memory,
        threshold: 85.0,
        description: 'High memory usage detected',
        severity: BottleneckSeverity.high,
        metrics: ['memory_percent'],
      ),
      'disk_io_bottleneck': BottleneckPattern(
        id: 'disk_io_bottleneck',
        type: BottleneckType.disk,
        threshold: 90.0,
        description: 'Disk I/O bottleneck detected',
        severity: BottleneckSeverity.medium,
        metrics: ['disk_usage', 'iowait'],
      ),
      'network_bottleneck': BottleneckPattern(
        id: 'network_bottleneck',
        type: BottleneckType.network,
        threshold: 85.0,
        description: 'Network bottleneck detected',
        severity: BottleneckSeverity.medium,
        metrics: ['network_usage', 'latency'],
      ),
      'process_bottleneck': BottleneckPattern(
        id: 'process_bottleneck',
        type: BottleneckType.process,
        threshold: 95.0,
        description: 'Process bottleneck detected',
        severity: BottleneckSeverity.critical,
        metrics: ['process_cpu', 'process_memory'],
      ),
      'thermal_throttling': BottleneckPattern(
        id: 'thermal_throttling',
        type: BottleneckType.thermal,
        threshold: 80.0,
        description: 'Thermal throttling detected',
        severity: BottleneckSeverity.high,
        metrics: ['temperature'],
      ),
    });
    
    debugPrint('🔍 Loaded ${_bottleneckPatterns.length} bottleneck patterns');
  }

  Future<void> _loadAutoFixes() async {
    // Initialize auto-fixes
    _autoFixes.addAll({
      'cpu_cleanup': AutoFix(
        id: 'cpu_cleanup',
        bottleneckId: 'high_cpu_usage',
        name: 'CPU Cleanup',
        commands: [
          'kill -9 \$(ps aux --sort=-%cpu | head -11 | tail -1 | awk \'{print \$2}\')',
          'renice 10 \$(pgrep -d, -f)',
          'echo 1 > /proc/sys/vm/drop_caches',
        ],
        description: 'Kill high CPU processes and renice others',
        confidence: 0.8,
        risk: FixRisk.low,
      ),
      'memory_cleanup': AutoFix(
        id: 'memory_cleanup',
        bottleneckId: 'high_memory_usage',
        name: 'Memory Cleanup',
        commands: [
          'echo 3 > /proc/sys/vm/drop_caches',
          'systemctl restart systemd-journald',
          'journalctl --vacuum-size=100M',
        ],
        description: 'Clear caches and clean up logs',
        confidence: 0.9,
        risk: FixRisk.low,
      ),
      'disk_cleanup': AutoFix(
        id: 'disk_cleanup',
        bottleneckId: 'disk_io_bottleneck',
        name: 'Disk Cleanup',
        commands: [
          'sync && echo 1 > /proc/sys/vm/drop_caches',
          'fstrim -av /',
          'find /tmp -type f -atime +7 -delete',
        ],
        description: 'Sync disks, trim filesystem, and clean temp files',
        confidence: 0.7,
        risk: FixRisk.medium,
      ),
      'process_cleanup': AutoFix(
        id: 'process_cleanup',
        bottleneckId: 'process_bottleneck',
        name: 'Process Cleanup',
        commands: [
          'systemctl daemon-reload',
          'systemctl restart systemd',
          'pkill -f zombie',
        ],
        description: 'Restart system services and clean zombie processes',
        confidence: 0.6,
        risk: FixRisk.medium,
      ),
      'thermal_management': AutoFix(
        id: 'thermal_management',
        bottleneckId: 'thermal_throttling',
        name: 'Thermal Management',
        commands: [
          'cpupower frequency-set -g powersave',
          'echo 0 > /sys/devices/system/cpu/cpu*/cpuidle/state*/disable',
          'systemctl restart thermald',
        ],
        description: 'Reduce CPU frequency and manage thermal states',
        confidence: 0.8,
        risk: FixRisk.low,
      ),
    });
    
    debugPrint('🔧 Loaded ${_autoFixes.length} auto-fixes');
  }

  Future<void> _loadFixHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/fix_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['history'] as List)) {
          _fixHistory.add(FixHistory.fromJson(entry));
        }
        
        // Limit history size
        if (_fixHistory.length > _maxHistorySize) {
          _fixHistory.removeRange(0, _fixHistory.length - _maxHistorySize);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load fix history: $e');
    }
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectPerformanceMetrics();
    });
    
    debugPrint('🔍 Started performance monitoring');
  }

  Future<void> _collectPerformanceMetrics() async {
    try {
      final snapshot = await _capturePerformanceSnapshot();
      _performanceHistory.add(snapshot);
      
      // Limit history size
      if (_performanceHistory.length > _maxHistorySize) {
        _performanceHistory.removeAt(0);
      }
      
      // Analyze for bottlenecks
      await _analyzeForBottlenecks(snapshot);
      
    } catch (e) {
      debugPrint('⚠️ Failed to collect performance metrics: $e');
    }
  }

  Future<PerformanceSnapshot> _capturePerformanceSnapshot() async {
    final timestamp = DateTime.now();
    final metrics = <String, double>{};
    
    try {
      // CPU metrics
      final cpuResult = await Process.run('top', ['-bn1'], runInShell: true);
      if (cpuResult.exitCode == 0) {
        final cpuOutput = cpuResult.stdout as String;
        final cpuLines = cpuOutput.split('\n');
        
        for (final line in cpuLines) {
          if (line.contains('%Cpu(s):')) {
            final match = RegExp(r'(\d+\.\d+)\s%us').firstMatch(line);
            if (match != null) {
              metrics['cpu_percent'] = double.parse(match.group(1)!);
            }
            break;
          }
        }
      }
      
      // Memory metrics
      final memResult = await Process.run('free', ['-m'], runInShell: true);
      if (memResult.exitCode == 0) {
        final memOutput = memResult.stdout as String;
        final memLines = memOutput.split('\n');
        
        for (final line in memLines) {
          if (line.startsWith('Mem:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final total = double.parse(parts[1]);
              final used = double.parse(parts[2]);
              metrics['memory_percent'] = (used / total) * 100;
            }
            break;
          }
        }
      }
      
      // Disk usage
      final diskResult = await Process.run('df', ['-h', '/'], runInShell: true);
      if (diskResult.exitCode == 0) {
        final diskOutput = diskResult.stdout as String;
        final diskLines = diskOutput.split('\n');
        
        for (final line in diskLines) {
          if (line.startsWith('/') && !line.startsWith('Filesystem')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 5) {
              final usageStr = parts[4].replaceAll('%', '');
              metrics['disk_usage'] = double.tryParse(usageStr) ?? 0.0;
            }
            break;
          }
        }
      }
      
      // Process information
      final processResult = await Process.run('ps', ['aux'], runInShell: true);
      if (processResult.exitCode == 0) {
        final processOutput = processResult.stdout as String;
        final processLines = processOutput.split('\n');
        
        double maxProcessCpu = 0.0;
        double maxProcessMem = 0.0;
        
        for (final line in processLines.skip(1)) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 12) {
            final cpu = double.tryParse(parts[2]) ?? 0.0;
            final mem = double.tryParse(parts[3]) ?? 0.0;
            
            maxProcessCpu = math.max(maxProcessCpu, cpu);
            maxProcessMem = math.max(maxProcessMem, mem);
          }
        }
        
        metrics['process_cpu'] = maxProcessCpu;
        metrics['process_memory'] = maxProcessMem;
      }
      
      // Temperature (if available)
      try {
        final tempResult = await Process.run('sensors', [], runInShell: true);
        if (tempResult.exitCode == 0) {
          final tempOutput = tempResult.stdout as String;
          final tempLines = tempOutput.split('\n');
          
          double maxTemp = 0.0;
          for (final line in tempLines) {
            if (line.contains('°C')) {
              final match = RegExp(r'(\d+\.\d+)°C').firstMatch(line);
              if (match != null) {
                final temp = double.parse(match.group(1)!);
                maxTemp = math.max(maxTemp, temp);
              }
            }
          }
          
          if (maxTemp > 0) {
            metrics['temperature'] = maxTemp;
          }
        }
      } catch (e) {
        // Temperature monitoring not available
      }
      
    } catch (e) {
      debugPrint('⚠️ Error capturing performance metrics: $e');
    }
    
    return PerformanceSnapshot(
      timestamp: timestamp,
      metrics: metrics,
    );
  }

  Future<void> _analyzeForBottlenecks(PerformanceSnapshot snapshot) async {
    for (final pattern in _bottleneckPatterns.values) {
      if (_isBottleneckDetected(pattern, snapshot)) {
        await _handleBottleneckDetected(pattern, snapshot);
      }
    }
  }

  bool _isBottleneckDetected(BottleneckPattern pattern, PerformanceSnapshot snapshot) {
    for (final metric in pattern.metrics) {
      final value = snapshot.metrics[metric];
      if (value != null && value >= pattern.threshold) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleBottleneckDetected(BottleneckPattern pattern, PerformanceSnapshot snapshot) async {
    debugPrint('🚨 Bottleneck detected: ${pattern.description}');
    
    // Emit bottleneck event
    _bottleneckController.add(BottleneckEvent(
      type: BottleneckEventType.detected,
      pattern: pattern,
      snapshot: snapshot,
    ));
    
    // Apply auto-fix if enabled
    if (_autoFixEnabled) {
      await _applyAutoFix(pattern);
    }
  }

  Future<void> _applyAutoFix(BottleneckPattern pattern) async {
    final fix = _autoFixes[pattern.id];
    if (fix == null) {
      debugPrint('⚠️ No auto-fix available for bottleneck: ${pattern.id}');
      return;
    }
    
    // Check if fix was recently applied
    final recentFixes = _fixHistory.where((f) => 
        f.fixId == fix.id && 
        DateTime.now().difference(f.timestamp).inMinutes < 10
    ).length;
    
    if (recentFixes >= _maxFixAttempts) {
      debugPrint('⚠️ Auto-fix ${fix.id} applied too recently, skipping');
      return;
    }
    
    try {
      debugPrint('🔧 Applying auto-fix: ${fix.name}');
      
      final fixHistory = FixHistory(
        id: 'fix_${DateTime.now().millisecondsSinceEpoch}',
        fixId: fix.id,
        patternId: pattern.id,
        commands: List.from(fix.commands),
        timestamp: DateTime.now(),
        applied: false,
        success: false,
        output: '',
        error: '',
      );
      
      // Execute fix commands
      final results = <String>[];
      bool allSuccessful = true;
      
      for (final command in fix.commands) {
        try {
          final result = await Process.run('bash', ['-c', command], runInShell: true);
          
          if (result.exitCode == 0) {
            results.add('✅ $command: SUCCESS');
            debugPrint('✅ Fix command succeeded: $command');
          } else {
            results.add('❌ $command: FAILED (${result.exitCode})');
            debugPrint('❌ Fix command failed: $command - ${result.stderr}');
            allSuccessful = false;
          }
        } catch (e) {
          results.add('❌ $command: ERROR - $e');
          allSuccessful = false;
        }
      }
      
      // Update fix history
      fixHistory.applied = true;
      fixHistory.success = allSuccessful;
      fixHistory.output = results.join('\n');
      
      _fixHistory.add(fixHistory);
      await _saveFixHistory();
      
      // Emit fix event
      _bottleneckController.add(BottleneckEvent(
        type: allSuccessful ? BottleneckEventType.fixApplied : BottleneckEventType.fixFailed,
        pattern: pattern,
        fix: fix,
        fixHistory: fixHistory,
      ));
      
      if (allSuccessful) {
        debugPrint('🔧 Auto-fix applied successfully: ${fix.name}');
      } else {
        debugPrint('⚠️ Auto-fix partially failed: ${fix.name}');
      }
      
    } catch (e) {
      debugPrint('❌ Failed to apply auto-fix: $e');
      
      _bottleneckController.add(BottleneckEvent(
        type: BottleneckEventType.fixFailed,
        pattern: pattern,
        fix: fix,
        error: e.toString(),
      ));
    }
  }

  Future<BottleneckAnalysis> analyzeWithAI({
    required PerformanceSnapshot snapshot,
    required List<BottleneckPattern> detectedBottlenecks,
  }) async {
    try {
      // Check if NVIDIA API is available
      final nvidiaKeys = <String>[];
      for (int i = 1; i <= 24; i++) {
        final key = Platform.environment['NVIDIA_API_KEY_$i'];
        if (key != null && key.isNotEmpty) {
          nvidiaKeys.add(key);
        }
      }
      
      if (nvidiaKeys.isEmpty) {
        return BottleneckAnalysis(
          success: false,
          reason: 'No NVIDIA API keys available',
          recommendations: _getBasicRecommendations(detectedBottlenecks),
        );
      }
      
      final prompt = _buildAIAnalysisPrompt(snapshot, detectedBottlenecks);
      final apiKey = nvidiaKeys[math.Random().nextInt(nvidiaKeys.length)];
      
      final response = await _callNvidiaAPI(prompt, apiKey);
      final analysis = _parseAIAnalysisResponse(response);
      
      return BottleneckAnalysis(
        success: true,
        aiRecommendations: analysis,
        detectedBottlenecks: detectedBottlenecks,
        confidence: 0.8,
      );
      
    } catch (e) {
      debugPrint('⚠️ AI analysis failed: $e');
      
      return BottleneckAnalysis(
        success: false,
        reason: 'AI analysis failed: $e',
        recommendations: _getBasicRecommendations(detectedBottlenecks),
      );
    }
  }

  String _buildAIAnalysisPrompt(PerformanceSnapshot snapshot, List<BottleneckPattern> bottlenecks) {
    final metricsText = snapshot.metrics.entries
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}')
        .join(', ');
    
    final bottlenecksText = bottlenecks
        .map((b) => '- ${b.description} (${b.type}, severity: ${b.severity})')
        .join('\n');
    
    return '''
You are an expert system performance analyst. Analyze this performance data and provide actionable recommendations.

PERFORMANCE SNAPSHOT:
Timestamp: ${snapshot.timestamp.toIso8601String()}
Metrics: $metricsText

DETECTED BOTTLENECKS:
$bottlenecksText

TASK: Provide specific, actionable recommendations to fix these performance issues.

RULES:
1. Focus on the most critical bottlenecks first
2. Provide specific commands or actions
3. Consider system stability and safety
4. Include both immediate fixes and long-term optimizations
5. Format your response as a JSON array of recommendations

RESPONSE FORMAT:
[
  {
    "category": "immediate|short_term|long_term",
    "priority": "critical|high|medium|low",
    "action": "Specific action or command",
    "description": "What this action does",
    "risk": "none|low|medium|high",
    "expected_impact": "Expected performance improvement"
  }
]

RECOMMENDATIONS:
''';
  }

  Future<String> _callNvidiaAPI(String prompt, String apiKey) async {
    final url = Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions');
    
    final requestBody = {
      'model': 'deepseek-ai/deepseek-v4-pro',
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'max_tokens': 1000,
      'temperature': 0.2,
    };
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    ).timeout(Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List;
      
      if (choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>;
        return message['content'] as String;
      }
    }
    
    throw Exception('API request failed');
  }

  List<AIRecommendation> _parseAIAnalysisResponse(String response) {
    try {
      final recommendations = <AIRecommendation>[];
      final data = jsonDecode(response) as List;
      
      for (final item in data) {
        recommendations.add(AIRecommendation.fromJson(item as Map<String, dynamic>));
      }
      
      return recommendations;
    } catch (e) {
      debugPrint('⚠️ Failed to parse AI response: $e');
      return [];
    }
  }

  List<String> _getBasicRecommendations(List<BottleneckPattern> bottlenecks) {
    final recommendations = <String>[];
    
    for (final bottleneck in bottlenecks) {
      switch (bottleneck.type) {
        case BottleneckType.cpu:
          recommendations.addAll([
            'Kill high CPU processes: kill -9 $(ps aux --sort=-%cpu | head -11 | tail -1 | awk \'{print $2}\')',
            'Reduce CPU frequency: cpupower frequency-set -g powersave',
            'Enable CPU throttling: echo 1 > /proc/sys/vm/dirty_ratio',
          ]);
          break;
        case BottleneckType.memory:
          recommendations.addAll([
            'Clear system caches: echo 3 > /proc/sys/vm/drop_caches',
            'Clean up logs: journalctl --vacuum-size=100M',
            'Restart memory-intensive services',
          ]);
          break;
        case BottleneckType.disk:
          recommendations.addAll([
            'Sync filesystems: sync && echo 1 > /proc/sys/vm/drop_caches',
            'Trim SSD: fstrim -av /',
            'Clean temporary files: find /tmp -type f -atime +7 -delete',
          ]);
          break;
        case BottleneckType.network:
          recommendations.addAll([
            'Check network connections: netstat -tuln',
            'Restart network services: systemctl restart networking',
            'Flush DNS cache: systemctl restart systemd-resolved',
          ]);
          break;
        case BottleneckType.thermal:
          recommendations.addAll([
            'Reduce CPU frequency: cpupower frequency-set -g powersave',
            'Improve cooling: check fans and airflow',
            'Restart thermal daemon: systemctl restart thermald',
          ]);
          break;
      }
    }
    
    return recommendations;
  }

  Future<void> _saveFixHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/fix_history.json');
      await historyFile.parent.create(recursive: true);
      
      final data = {
        'history': _fixHistory.map((h) => h.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save fix history: $e');
    }
  }

  void setAutoFixEnabled(bool enabled) {
    _autoFixEnabled = enabled;
    debugPrint('🔧 Auto-fix ${enabled ? 'enabled' : 'disabled'}');
  }

  BottleneckStatistics getStatistics() {
    final totalFixes = _fixHistory.length;
    final successfulFixes = _fixHistory.where((f) => f.success).length;
    final appliedFixes = _fixHistory.where((f) => f.applied).length;
    
    final fixTypeDistribution = <String, int>{};
    for (final fix in _fixHistory) {
      fixTypeDistribution[fix.fixId] = (fixTypeDistribution[fix.fixId] ?? 0) + 1;
    }
    
    return BottleneckStatistics(
      monitoredMetrics: _performanceHistory.isNotEmpty ? _performanceHistory.last.metrics.length : 0,
      historySize: _performanceHistory.length,
      detectedPatterns: _bottleneckPatterns.length,
      availableFixes: _autoFixes.length,
      totalFixes: totalFixes,
      successfulFixes: successfulFixes,
      appliedFixes: appliedFixes,
      autoFixEnabled: _autoFixEnabled,
      fixTypeDistribution: fixTypeDistribution,
      averageFixTime: _calculateAverageFixTime(),
    );
  }

  double _calculateAverageFixTime() {
    // In a real implementation, this would track actual fix times
    return 2.5; // seconds
  }

  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _bottleneckController.close();
    _performanceHistory.clear();
    _bottleneckPatterns.clear();
    _autoFixes.clear();
    _fixHistory.clear();
    _isInitialized = false;
    
    debugPrint('🔍 AI Bottleneck Detector disposed');
  }
}

/// Data classes
class PerformanceSnapshot {
  final DateTime timestamp;
  final Map<String, double> metrics;
  
  PerformanceSnapshot({
    required this.timestamp,
    required this.metrics,
  });
}

class BottleneckPattern {
  final String id;
  final BottleneckType type;
  final double threshold;
  final String description;
  final BottleneckSeverity severity;
  final List<String> metrics;
  
  BottleneckPattern({
    required this.id,
    required this.type,
    required this.threshold,
    required this.description,
    required this.severity,
    required this.metrics,
  });
}

class AutoFix {
  final String id;
  final String bottleneckId;
  final String name;
  final List<String> commands;
  final String description;
  final double confidence;
  final FixRisk risk;
  
  AutoFix({
    required this.id,
    required this.bottleneckId,
    required this.name,
    required this.commands,
    required this.description,
    required this.confidence,
    required this.risk,
  });
}

class FixHistory {
  final String id;
  final String fixId;
  final String patternId;
  final List<String> commands;
  final DateTime timestamp;
  bool applied;
  bool success;
  final String output;
  final String error;
  
  FixHistory({
    required this.id,
    required this.fixId,
    required this.patternId,
    required this.commands,
    required this.timestamp,
    required this.applied,
    required this.success,
    required this.output,
    required this.error,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fix_id': fixId,
      'pattern_id': patternId,
      'commands': commands,
      'timestamp': timestamp.toIso8601String(),
      'applied': applied,
      'success': success,
      'output': output,
      'error': error,
    };
  }
  
  factory FixHistory.fromJson(Map<String, dynamic> json) {
    return FixHistory(
      id: json['id'],
      fixId: json['fix_id'],
      patternId: json['pattern_id'],
      commands: List<String>.from(json['commands']),
      timestamp: DateTime.parse(json['timestamp']),
      applied: json['applied'],
      success: json['success'],
      output: json['output'] ?? '',
      error: json['error'] ?? '',
    );
  }
}

class BottleneckEvent {
  final BottleneckEventType type;
  final BottleneckPattern? pattern;
  final PerformanceSnapshot? snapshot;
  final AutoFix? fix;
  final FixHistory? fixHistory;
  final String? error;
  final Map<String, dynamic>? data;
  
  BottleneckEvent({
    required this.type,
    this.pattern,
    this.snapshot,
    this.fix,
    this.fixHistory,
    this.error,
    this.data,
  });
}

class BottleneckAnalysis {
  final bool success;
  final String? reason;
  final List<AIRecommendation>? aiRecommendations;
  final List<String>? recommendations;
  final List<BottleneckPattern>? detectedBottlenecks;
  final double confidence;
  
  BottleneckAnalysis({
    required this.success,
    this.reason,
    this.aiRecommendations,
    this.recommendations,
    this.detectedBottlenecks,
    this.confidence = 0.0,
  });
}

class AIRecommendation {
  final String category;
  final String priority;
  final String action;
  final String description;
  final String risk;
  final String expectedImpact;
  
  AIRecommendation({
    required this.category,
    required this.priority,
    required this.action,
    required this.description,
    required this.risk,
    required this.expectedImpact,
  });
  
  factory AIRecommendation.fromJson(Map<String, dynamic> json) {
    return AIRecommendation(
      category: json['category'],
      priority: json['priority'],
      action: json['action'],
      description: json['description'],
      risk: json['risk'],
      expectedImpact: json['expected_impact'],
    );
  }
}

class BottleneckStatistics {
  final int monitoredMetrics;
  final int historySize;
  final int detectedPatterns;
  final int availableFixes;
  final int totalFixes;
  final int successfulFixes;
  final int appliedFixes;
  final bool autoFixEnabled;
  final Map<String, int> fixTypeDistribution;
  final double averageFixTime;
  
  BottleneckStatistics({
    required this.monitoredMetrics,
    required this.historySize,
    required this.detectedPatterns,
    required this.availableFixes,
    required this.totalFixes,
    required this.successfulFixes,
    required this.appliedFixes,
    required this.autoFixEnabled,
    required this.fixTypeDistribution,
    required this.averageFixTime,
  });
}

enum BottleneckType {
  cpu,
  memory,
  disk,
  network,
  process,
  thermal,
}

enum BottleneckSeverity {
  low,
  medium,
  high,
  critical,
}

enum FixRisk {
  none,
  low,
  medium,
  high,
}

enum BottleneckEventType {
  detected,
  fixApplied,
  fixFailed,
  analysisCompleted,
}
