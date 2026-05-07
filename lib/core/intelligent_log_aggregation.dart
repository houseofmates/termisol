import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class IntelligentLogAggregation {
  static const String _configFile = '/home/house/.termisol_log_config.json';
  static const String _patternsFile = '/home/house/.termisol_log_patterns.json';
  static const String _aggregatedFile = '/home/house/.termisol_aggregated_logs.json';
  static const int _maxLogSources = 50;
  static const int _maxPatterns = 200;
  static const int _maxAggregatedEntries = 100000;
  static const Duration _aggregationInterval = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(hours: 1);
  
  final Map<String, LogSource> _sources = {};
  final Map<String, LogPattern> _patterns = {};
  final Map<String, List<LogEntry>> _aggregatedLogs = {};
  final Map<String, LogAnalysis> _analyses = {};
  final Map<String, AnomalyDetection> _anomalyDetectors = {};
  
  Timer? _aggregationTimer;
  Timer? _cleanupTimer;
  Timer? _analysisTimer;
  int _totalSources = 0;
  int _totalPatterns = 0;
  int _totalAggregatedEntries = 0;
  int _totalAnalyses = 0;
  
  final StreamController<LogEvent> _logController = 
      StreamController<LogEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _loadPatterns();
    _loadAggregatedLogs();
    _initializeDefaultPatterns();
    _startTimers();
    developer.log('📊 Intelligent Log Aggregation initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('📊 No existing log configuration found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load log sources
      for (final entry in data['sources']) {
        final source = LogSource.fromJson(entry);
        _sources[source.id] = source;
        _totalSources++;
      }
      
      // Load anomaly detectors
      for (final entry in data['anomaly_detectors']) {
        final detector = AnomalyDetection.fromJson(entry);
        _anomalyDetectors[detector.id] = detector;
      }
      
      developer.log('📊 Loaded ${_sources.length} log sources');
      
    } catch (e) {
      developer.log('📊 Failed to load log configuration: $e');
    }
  }

  void _loadPatterns() {
    try {
      final file = File(_patternsFile);
      if (!file.existsSync()) {
        developer.log('📊 No existing log patterns found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['patterns']) {
        final pattern = LogPattern.fromJson(entry);
        _patterns[pattern.id] = pattern;
        _totalPatterns++;
      }
      
      developer.log('📊 Loaded ${_patterns.length} log patterns');
      
    } catch (e) {
      developer.log('📊 Failed to load log patterns: $e');
    }
  }

  void _loadAggregatedLogs() {
    try {
      final file = File(_aggregatedFile);
      if (!file.existsSync()) {
        developer.log('📊 No existing aggregated logs found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['aggregated_logs']) {
        final logs = (entry['logs'] as List)
            .map((log) => LogEntry.fromJson(log))
            .toList();
        
        _aggregatedLogs[entry['source_id']] = logs;
        _totalAggregatedEntries += logs.length;
      }
      
      // Load analyses
      for (final entry in data['analyses']) {
        final analysis = LogAnalysis.fromJson(entry);
        _analyses[analysis.id] = analysis;
        _totalAnalyses++;
      }
      
      developer.log('📊 Loaded ${_aggregatedLogs.length} aggregated log sets, ${_analyses.length} analyses');
      
    } catch (e) {
      developer.log('📊 Failed to load aggregated logs: $e');
    }
  }

  void _initializeDefaultPatterns() {
    if (_patterns.isEmpty) {
      final defaultPatterns = [
        // Error patterns
        LogPattern(
          id: 'error_critical',
          name: 'Critical Error',
          description: 'Critical error messages',
          regex: r'(?i)critical|fatal|panic|emergency',
          severity: LogSeverity.critical,
          category: LogCategory.error,
          priority: 10,
          action: LogAction.alert,
          tags: ['error', 'critical'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'error_exception',
          name: 'Exception Error',
          description: 'Exception stack traces',
          regex: r'(?i)exception|stack trace|traceback',
          severity: LogSeverity.error,
          category: LogCategory.error,
          priority: 8,
          action: LogAction.alert,
          tags: ['error', 'exception'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'error_timeout',
          name: 'Timeout Error',
          description: 'Connection or operation timeouts',
          regex: r'(?i)timeout|timed out|connection.*failed',
          severity: LogSeverity.warning,
          category: LogCategory.error,
          priority: 6,
          action: LogAction.warn,
          tags: ['error', 'timeout'],
          createdAt: DateTime.now(),
        ),
        
        // Performance patterns
        LogPattern(
          id: 'slow_query',
          name: 'Slow Query',
          description: 'Slow database or API queries',
          regex: r'(?i)slow.*query|query.*slow|executed.*slow',
          severity: LogSeverity.warning,
          category: LogCategory.performance,
          priority: 7,
          action: LogAction.monitor,
          tags: ['performance', 'slow'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'high_memory',
          name: 'High Memory Usage',
          description: 'High memory consumption',
          regex: r'(?i)memory.*high|out of memory|oom|memory.*exhausted',
          severity: LogSeverity.warning,
          category: LogCategory.performance,
          priority: 6,
          action: LogAction.monitor,
          tags: ['performance', 'memory'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'high_cpu',
          name: 'High CPU Usage',
          description: 'High CPU utilization',
          regex: r'(?i)cpu.*high|high.*cpu|cpu.*max',
          severity: LogSeverity.warning,
          category: LogCategory.performance,
          priority: 6,
          action: LogAction.monitor,
          tags: ['performance', 'cpu'],
          createdAt: DateTime.now(),
        ),
        
        // Security patterns
        LogPattern(
          id: 'security_breach',
          name: 'Security Breach',
          description: 'Security-related events',
          regex: r'(?i)security|breach|unauthorized|forbidden|attack|intrusion',
          severity: LogSeverity.critical,
          category: LogCategory.security,
          priority: 9,
          action: LogAction.alert,
          tags: ['security', 'breach'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'authentication_failure',
          name: 'Authentication Failure',
          description: 'Failed login attempts',
          regex: r'(?i)auth.*failed|login.*failed|authentication.*error',
          severity: LogSeverity.warning,
          category: LogCategory.security,
          priority: 7,
          action: LogAction.monitor,
          tags: ['security', 'auth'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'permission_denied',
          name: 'Permission Denied',
          description: 'Permission access issues',
          regex: r'(?i)permission.*denied|access.*denied|unauthorized.*access',
          severity: LogSeverity.warning,
          category: LogCategory.security,
          priority: 5,
          action: LogAction.warn,
          tags: ['security', 'permission'],
          createdAt: DateTime.now(),
        ),
        
        // Application patterns
        LogPattern(
          id: 'application_crash',
          name: 'Application Crash',
          description: 'Application crashes or exits',
          regex: r'(?i)crash|segfault|core.*dump|aborted|killed',
          severity: LogSeverity.error,
          category: LogCategory.application,
          priority: 9,
          action: LogAction.alert,
          tags: ['application', 'crash'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'startup_failure',
          name: 'Startup Failure',
          description: 'Service or application startup failures',
          regex: r'(?i)startup.*failed|failed.*startup|service.*not.*running',
          severity: LogSeverity.error,
          category: LogCategory.application,
          priority: 8,
          action: LogAction.alert,
          tags: ['application', 'startup'],
          createdAt: DateTime.now(),
        ),
        
        // Network patterns
        LogPattern(
          id: 'network_error',
          name: 'Network Error',
          description: 'Network connectivity issues',
          regex: r'(?i)network.*error|connection.*failed|dns.*error|timeout.*network',
          severity: LogSeverity.warning,
          category: LogCategory.network,
          priority: 7,
          action: LogAction.monitor,
          tags: ['network', 'connectivity'],
          createdAt: DateTime.now(),
        ),
        
        LogPattern(
          id: 'high_latency',
          name: 'High Latency',
          description: 'High network or service latency',
          regex: r'(?i)latency.*high|high.*latency|slow.*response|response.*slow',
          severity: LogSeverity.warning,
          category: LogCategory.network,
          priority: 6,
          action: LogAction.monitor,
          tags: ['network', 'latency'],
          createdAt: DateTime.now(),
        ),
      ];
      
      for (final pattern in defaultPatterns) {
        _patterns[pattern.id] = pattern;
        _totalPatterns++;
      }
      
      _savePatterns();
      developer.log('📊 Initialized ${defaultPatterns.length} default log patterns');
    }
  }

  void _startTimers() {
    _aggregationTimer = Timer.periodic(_aggregationInterval, (_) => _performAggregation());
    
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
    
    _analysisTimer = Timer.periodic(Duration(minutes: 15), (_) => _performAnalysis());
  }

  Future<String> addLogSource({
    required String name,
    required String path,
    LogSourceType type,
    String? format,
    Map<String, dynamic>? config,
  }) async {
    if (_sources.length >= _maxLogSources) {
      throw Exception('Maximum log sources reached: $_maxLogSources');
    }
    
    final sourceId = _generateSourceId();
    
    final source = LogSource(
      id: sourceId,
      name: name,
      path: path,
      type: type,
      format: format ?? 'auto',
      config: config ?? {},
      enabled: true,
      lastPosition: 0,
      totalLines: 0,
      lastModified: DateTime.now(),
      createdAt: DateTime.now(),
    );
    
    _sources[sourceId] = source;
    _totalSources++;
    
    developer.log('📊 Added log source: $name ($path)');
    
    _emitEvent(LogEvent(
      type: LogEventType.sourceAdded,
      sourceId: sourceId,
      sourceName: name,
    ));
    
    await _saveConfiguration();
    
    return sourceId;
  }

  Future<void> addLogEntry({
    required String sourceId,
    required String message,
    LogSeverity? severity,
    LogCategory? category,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw Exception('Log source not found: $sourceId');
    }
    
    final entry = LogEntry(
      id: _generateEntryId(),
      sourceId: sourceId,
      message: message,
      severity: severity ?? LogSeverity.info,
      category: category ?? LogCategory.general,
      metadata: metadata ?? {},
      timestamp: timestamp ?? DateTime.now(),
      processed: false,
      patterns: [],
      anomalies: [],
    );
    
    // Add to aggregated logs
    final aggregated = _aggregatedLogs[sourceId] ?? [];
    aggregated.add(entry);
    _aggregatedLogs[sourceId] = aggregated;
    _totalAggregatedEntries++;
    
    // Update source info
    source.totalLines++;
    source.lastModified = DateTime.now();
    
    // Process the entry
    await _processLogEntry(entry);
    
    developer.log('📊 Added log entry: ${message.substring(0, 50)}...');
    
    _emitEvent(LogEvent(
      type: LogEventType.entryAdded,
      sourceId: sourceId,
      entryId: entry.id,
      message: message,
    ));
    
    await _saveAggregatedLogs();
  }

  Future<void> _processLogEntry(LogEntry entry) async {
    // Match against patterns
    final matchedPatterns = <PatternMatch>[];
    
    for (final pattern in _patterns.values) {
      if (!pattern.enabled) continue;
      
      final match = _matchPattern(pattern, entry);
      if (match != null) {
        matchedPatterns.add(match);
        entry.patterns.add(match.patternId);
        
        // Trigger pattern action
        await _triggerPatternAction(pattern, entry, match);
      }
    }
    
    // Check for anomalies
    final anomalies = await _detectAnomalies(entry);
    for (final anomaly in anomalies) {
      entry.anomalies.add(anomaly.id);
      await _triggerAnomalyAction(anomaly, entry);
    }
  }

  PatternMatch? _matchPattern(LogPattern pattern, LogEntry entry) {
    try {
      final regex = RegExp(pattern.regex, caseSensitive: false);
      final match = regex.firstMatch(entry.message);
      
      if (match != null) {
        return PatternMatch(
          patternId: pattern.id,
          patternName: pattern.name,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          severity: pattern.severity,
          category: pattern.category,
          confidence: _calculateMatchConfidence(pattern, entry, match),
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      developer.log('📊 Pattern matching failed: $e');
    }
    
    return null;
  }

  double _calculateMatchConfidence(LogPattern pattern, LogEntry entry, RegExpMatch match) {
    double confidence = 0.5; // Base confidence
    
    // Boost confidence for exact matches
    if (match.group(0)!.toLowerCase() == pattern.regex.toLowerCase()) {
      confidence += 0.3;
    }
    
    // Boost confidence for category consistency
    if (entry.category == pattern.category) {
      confidence += 0.2;
    }
    
    // Boost confidence for severity consistency
    if (entry.severity == pattern.severity) {
      confidence += 0.1;
    }
    
    return math.min(1.0, confidence);
  }

  Future<List<AnomalyDetection>> _detectAnomalies(LogEntry entry) async {
    final anomalies = <AnomalyDetection>[];
    
    for (final detector in _anomalyDetectors.values) {
      if (!detector.enabled) continue;
      
      final isAnomaly = await _checkAnomaly(detector, entry);
      if (isAnomaly) {
        anomalies.add(detector);
      }
    }
    
    return anomalies;
  }

  Future<bool> _checkAnomaly(AnomalyDetection detector, LogEntry entry) async {
    switch (detector.type) {
      case AnomalyType.frequency:
        return await _checkFrequencyAnomaly(detector, entry);
      case AnomalyType.burst:
        return await _checkBurstAnomaly(detector, entry);
      case AnomalyType.outlier:
        return await _checkOutlierAnomaly(detector, entry);
      case AnomalyType.sequence:
        return await _checkSequenceAnomaly(detector, entry);
      case AnomalyType.semantic:
        return await _checkSemanticAnomaly(detector, entry);
    }
    
    return false;
  }

  Future<bool> _checkFrequencyAnomaly(AnomalyDetection detector, LogEntry entry) async {
    // Check if error frequency exceeds threshold
    if (entry.category != LogCategory.error) return false;
    
    final recentEntries = _getRecentEntries(entry.sourceId, Duration(minutes: 5));
    final errorCount = recentEntries
        .where((e) => e.category == LogCategory.error)
        .length;
    
    return errorCount > (detector.config['threshold'] as int? ?? 10);
  }

  Future<bool> _checkBurstAnomaly(AnomalyDetection detector, LogEntry entry) async {
    // Check for burst of messages in short time
    final recentEntries = _getRecentEntries(entry.sourceId, Duration(seconds: 10));
    
    final threshold = detector.config['threshold'] as int? ?? 50;
    return recentEntries.length > threshold;
  }

  Future<bool> _checkOutlierAnomaly(AnomalyDetection detector, LogEntry entry) async {
    // Check for unusual message patterns
    final recentEntries = _getRecentEntries(entry.sourceId, Duration(hours: 1));
    
    // Calculate message length statistics
    final lengths = recentEntries.map((e) => e.message.length).toList();
    if (lengths.isEmpty) return false;
    
    final meanLength = lengths.reduce((a, b) => a + b) / lengths.length;
    final stdDev = _calculateStandardDeviation(lengths, meanLength);
    
    // Check if current entry is an outlier
    final zScore = (entry.message.length - meanLength) / stdDev;
    return zScore.abs() > (detector.config['threshold'] as double? ?? 3.0);
  }

  double _calculateStandardDeviation(List<int> values, double mean) {
    if (values.isEmpty) return 0.0;
    
    final variance = values
        .map((value) => math.pow(value - mean, 2))
        .reduce((a, b) => a + b) / values.length;
    
    return math.sqrt(variance);
  }

  Future<bool> _checkSequenceAnomaly(AnomalyDetection detector, LogEntry entry) async {
    // Check for unusual sequence of messages
    final recentEntries = _getRecentEntries(entry.sourceId, Duration(minutes: 5));
    
    if (recentEntries.length < 3) return false;
    
    // Check for repeated error patterns
    final lastThree = recentEntries.takeLast(3).map((e) => e.category).toList();
    final errorSequence = lastThree.where((category) => category == LogCategory.error);
    
    return errorSequence.length >= (detector.config['threshold'] as int? ?? 3);
  }

  Future<bool> _checkSemanticAnomaly(AnomalyDetection detector, LogEntry entry) async {
    // Check for semantic anomalies using keyword analysis
    final keywords = detector.config['keywords'] as List<String>? ?? [];
    if (keywords.isEmpty) return false;
    
    final messageLower = entry.message.toLowerCase();
    final matchedKeywords = keywords.where((keyword) => 
        messageLower.contains(keyword.toLowerCase())).toList();
    
    return matchedKeywords.length >= (detector.config['threshold'] as int? ?? 2);
  }

  Future<void> _triggerPatternAction(LogPattern pattern, LogEntry entry, PatternMatch match) async {
    switch (pattern.action) {
      case LogAction.alert:
        await _createAlert(
          title: 'Pattern Match: ${pattern.name}',
          message: 'Detected: ${match.matchedText}',
          severity: pattern.severity,
          category: pattern.category,
          sourceId: entry.sourceId,
        );
        break;
        
      case LogAction.warn:
        await _createWarning(
          title: 'Pattern Match: ${pattern.name}',
          message: 'Detected: ${match.matchedText}',
          severity: pattern.severity,
          category: pattern.category,
          sourceId: entry.sourceId,
        );
        break;
        
      case LogAction.monitor:
        await _createMonitoringEvent(
          title: 'Pattern Match: ${pattern.name}',
          message: 'Detected: ${match.matchedText}',
          severity: pattern.severity,
          category: pattern.category,
          sourceId: entry.sourceId,
        );
        break;
        
      case LogAction.ignore:
        // Do nothing
        break;
    }
  }

  Future<void> _triggerAnomalyAction(AnomalyDetection detector, LogEntry entry) async {
    await _createAlert(
      title: 'Anomaly Detected: ${detector.name}',
      message: 'Anomaly detected in log entry: ${entry.message.substring(0, 100)}',
      severity: LogSeverity.warning,
      category: LogCategory.anomaly,
      sourceId: entry.sourceId,
      anomalyId: detector.id,
    );
  }

  Future<void> _createAlert({
    required String title,
    required String message,
    required LogSeverity severity,
    required LogCategory category,
    required String sourceId,
    String? patternId,
    String? anomalyId,
  }) async {
    developer.log('📊 ALERT: $title - $message');
    
    _emitEvent(LogEvent(
      type: LogEventType.alertCreated,
      sourceId: sourceId,
      title: title,
      message: message,
      severity: severity,
      category: category,
      patternId: patternId,
      anomalyId: anomalyId,
    ));
  }

  Future<void> _createWarning({
    required String title,
    required String message,
    required LogSeverity severity,
    required LogCategory category,
    required String sourceId,
    String? patternId,
  }) async {
    developer.log('📊 WARNING: $title - $message');
    
    _emitEvent(LogEvent(
      type: LogEventType.warningCreated,
      sourceId: sourceId,
      title: title,
      message: message,
      severity: severity,
      category: category,
      patternId: patternId,
    ));
  }

  Future<void> _createMonitoringEvent({
    required String title,
    required String message,
    required LogSeverity severity,
    required LogCategory category,
    required String sourceId,
    String? patternId,
  }) async {
    developer.log('📊 MONITOR: $title - $message');
    
    _emitEvent(LogEvent(
      type: LogEventType.monitoringEventCreated,
      sourceId: sourceId,
      title: title,
      message: message,
      severity: severity,
      category: category,
      patternId: patternId,
    ));
  }

  Future<void> _performAggregation() async {
    for (final source in _sources.values) {
      if (!source.enabled) continue;
      
      try {
        await _aggregateSourceLogs(source);
      } catch (e) {
        developer.log('📊 Failed to aggregate logs for source ${source.name}: $e');
      }
    }
    
    // Perform periodic analysis
    await _performPeriodicAnalysis();
    
    await _saveAggregatedLogs();
    
    developer.log('📊 Performed log aggregation');
  }

  Future<void> _aggregateSourceLogs(LogSource source) async {
    // Read new log entries from source
    final newEntries = await _readNewLogEntries(source);
    
    if (newEntries.isEmpty) return;
    
    // Process each new entry
    for (final entry in newEntries) {
      await _processLogEntry(entry);
      
      // Add to aggregated logs
      final aggregated = _aggregatedLogs[source.id] ?? [];
      aggregated.add(entry);
      _aggregatedLogs[source.id] = aggregated;
      _totalAggregatedEntries++;
    }
    
    // Update source position
    source.lastPosition += newEntries.length;
    source.lastModified = DateTime.now();
  }

  Future<List<LogEntry>> _readNewLogEntries(LogSource source) async {
    final entries = <LogEntry>[];
    
    try {
      final file = File(source.path);
      if (!file.existsSync()) return entries;
      
      // Read from last position
      final randomAccessFile = file.openSync(mode: FileMode.read);
      randomAccessFile.setPositionSync(source.lastPosition);
      
      final content = utf8.decode(randomAccessFile.readSync(source.totalLines - source.lastPosition));
      final lines = content.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        
        final entry = LogEntry(
          id: _generateEntryId(),
          sourceId: source.id,
          message: line,
          severity: _parseSeverity(line),
          category: _parseCategory(line),
          metadata: _parseMetadata(line, source.format),
          timestamp: _parseTimestamp(line, source.format),
          processed: false,
          patterns: [],
          anomalies: [],
        );
        
        entries.add(entry);
      }
      
      randomAccessFile.closeSync();
      
    } catch (e) {
      developer.log('📊 Failed to read log entries from ${source.path}: $e');
    }
    
    return entries;
  }

  LogSeverity _parseSeverity(String line) {
    final lowerLine = line.toLowerCase();
    
    if (lowerLine.contains('critical') || lowerLine.contains('fatal') || lowerLine.contains('panic')) {
      return LogSeverity.critical;
    } else if (lowerLine.contains('error') || lowerLine.contains('exception')) {
      return LogSeverity.error;
    } else if (lowerLine.contains('warn') || lowerLine.contains('warning')) {
      return LogSeverity.warning;
    } else if (lowerLine.contains('info')) {
      return LogSeverity.info;
    } else if (lowerLine.contains('debug')) {
      return LogSeverity.debug;
    }
    
    return LogSeverity.info;
  }

  LogCategory _parseCategory(String line) {
    final lowerLine = line.toLowerCase();
    
    if (lowerLine.contains('error') || lowerLine.contains('exception') || lowerLine.contains('fail')) {
      return LogCategory.error;
    } else if (lowerLine.contains('security') || lowerLine.contains('auth') || lowerLine.contains('unauthorized')) {
      return LogCategory.security;
    } else if (lowerLine.contains('performance') || lowerLine.contains('slow') || lowerLine.contains('timeout')) {
      return LogCategory.performance;
    } else if (lowerLine.contains('network') || lowerLine.contains('connection') || lowerLine.contains('latency')) {
      return LogCategory.network;
    } else if (lowerLine.contains('app') || lowerLine.contains('service') || lowerLine.contains('startup')) {
      return LogCategory.application;
    }
    
    return LogCategory.general;
  }

  Map<String, dynamic> _parseMetadata(String line, String format) {
    final metadata = <String, dynamic>{};
    
    if (format == 'json') {
      try {
        final jsonData = jsonDecode(line);
        metadata['parsed'] = jsonData;
      } catch (e) {
        metadata['parse_error'] = e.toString();
      }
    } else if (format == 'syslog') {
      // Parse syslog format
      final parts = line.split(' ');
      if (parts.length >= 6) {
        metadata['hostname'] = parts[3];
        metadata['process'] = parts[4];
        metadata['pid'] = parts[5];
      }
    }
    
    return metadata;
  }

  DateTime _parseTimestamp(String line, String format) {
    if (format == 'iso8601') {
      try {
        final timestampMatch = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').firstMatch(line);
        if (timestampMatch != null) {
          return DateTime.parse(timestampMatch.group(0)!);
        }
      } catch (e) {
        // Ignore parse errors
      }
    } else if (format == 'syslog') {
      try {
        final timestampMatch = RegExp(r'\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}').firstMatch(line);
        if (timestampMatch != null) {
          final now = DateTime.now();
          final timestampStr = '${now.year} ${timestampMatch!.group(0)}';
          return DateTime.parse(timestampStr);
        }
      } catch (e) {
        // Ignore parse errors
      }
    }
    
    return DateTime.now();
  }

  Future<void> _performPeriodicAnalysis() async {
    for (final entry in _aggregatedLogs.entries) {
      final sourceId = entry.key;
      final logs = entry.value;
      
      if (logs.isEmpty) continue;
      
      // Perform various analyses
      await _analyzeLogTrends(sourceId, logs);
      await _analyzeErrorPatterns(sourceId, logs);
      await _analyzePerformanceMetrics(sourceId, logs);
      await _analyzeSecurityEvents(sourceId, logs);
    }
  }

  Future<void> _analyzeLogTrends(String sourceId, List<LogEntry> logs) async {
    final analysisId = _generateAnalysisId();
    
    // Analyze log volume trends
    final now = DateTime.now();
    final hourlyCounts = <int, int>{};
    final severityCounts = <LogSeverity, int>{};
    
    for (final log in logs) {
      final hour = log.timestamp.hour;
      hourlyCounts[hour] = (hourlyCounts[hour] ?? 0) + 1;
      severityCounts[log.severity] = (severityCounts[log.severity] ?? 0) + 1;
    }
    
    // Calculate trends
    final totalLogs = logs.length;
    final errorRate = (severityCounts[LogSeverity.error] ?? 0) + (severityCounts[LogSeverity.critical] ?? 0);
    final errorPercentage = totalLogs > 0 ? (errorRate / totalLogs) * 100 : 0.0;
    
    final analysis = LogAnalysis(
      id: analysisId,
      sourceId: sourceId,
      type: AnalysisType.trends,
      title: 'Log Volume Trends',
      description: 'Analysis of log volume and error rates',
      data: {
        'total_logs': totalLogs,
        'hourly_counts': hourlyCounts,
        'severity_counts': severityCounts.map((k, v) => MapEntry(k.name, v)).toList(),
        'error_rate': errorRate,
        'error_percentage': errorPercentage,
        'analysis_period': '1 hour',
      },
      confidence: 0.8,
      createdAt: DateTime.now(),
    );
    
    _analyses[analysisId] = analysis;
    _totalAnalyses++;
    
    developer.log('📊 Analyzed log trends for source $sourceId');
  }

  Future<void> _analyzeErrorPatterns(String sourceId, List<LogEntry> logs) async {
    final analysisId = _generateAnalysisId();
    
    // Analyze error patterns
    final errorLogs = logs.where((log) => 
        log.category == LogCategory.error || log.severity == LogSeverity.error).toList();
    
    if (errorLogs.isEmpty) return;
    
    // Group errors by message patterns
    final errorPatterns = <String, int>{};
    for (final log in errorLogs) {
      final normalizedMessage = _normalizeErrorMessage(log.message);
      errorPatterns[normalizedMessage] = (errorPatterns[normalizedMessage] ?? 0) + 1;
    }
    
    // Find most common errors
    final sortedErrors = errorPatterns.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final analysis = LogAnalysis(
      id: analysisId,
      sourceId: sourceId,
      type: AnalysisType.errorPatterns,
      title: 'Error Pattern Analysis',
      description: 'Analysis of recurring error patterns',
      data: {
        'total_errors': errorLogs.length,
        'error_patterns': sortedErrors.take(10).map((e) => MapEntry(e.key, e.value)).toList(),
        'most_common_error': sortedErrors.isNotEmpty ? sortedErrors.first.key : null,
        'error_rate': errorLogs.length / logs.length,
      },
      confidence: 0.9,
      createdAt: DateTime.now(),
    );
    
    _analyses[analysisId] = analysis;
    _totalAnalyses++;
    
    developer.log('📊 Analyzed error patterns for source $sourceId');
  }

  Future<void> _analyzePerformanceMetrics(String sourceId, List<LogEntry> logs) async {
    final analysisId = _generateAnalysisId();
    
    // Analyze performance-related logs
    final perfLogs = logs.where((log) => 
        log.category == LogCategory.performance).toList();
    
    if (perfLogs.isEmpty) return;
    
    // Calculate performance metrics
    final slowOperations = perfLogs.where((log) => 
        log.message.toLowerCase().contains('slow')).length;
    final timeoutOperations = perfLogs.where((log) => 
        log.message.toLowerCase().contains('timeout')).length;
    final memoryIssues = perfLogs.where((log) => 
        log.message.toLowerCase().contains('memory')).length;
    
    final analysis = LogAnalysis(
      id: analysisId,
      sourceId: sourceId,
      type: AnalysisType.performance,
      title: 'Performance Metrics Analysis',
      description: 'Analysis of performance-related log entries',
      data: {
        'total_performance_logs': perfLogs.length,
        'slow_operations': slowOperations,
        'timeout_operations': timeoutOperations,
        'memory_issues': memoryIssues,
        'performance_score': _calculatePerformanceScore(perfLogs.length, logs.length),
      },
      confidence: 0.7,
      createdAt: DateTime.now(),
    );
    
    _analyses[analysisId] = analysis;
    _totalAnalyses++;
    
    developer.log('📊 Analyzed performance metrics for source $sourceId');
  }

  Future<void> _analyzeSecurityEvents(String sourceId, List<LogEntry> logs) async {
    final analysisId = _generateAnalysisId();
    
    // Analyze security-related logs
    final securityLogs = logs.where((log) => 
        log.category == LogCategory.security).toList();
    
    if (securityLogs.isEmpty) return;
    
    // Calculate security metrics
    final authenticationFailures = securityLogs.where((log) => 
        log.message.toLowerCase().contains('auth') && 
        log.message.toLowerCase().contains('fail')).length;
    final unauthorizedAttempts = securityLogs.where((log) => 
        log.message.toLowerCase().contains('unauthorized')).length;
    final breachEvents = securityLogs.where((log) => 
        log.message.toLowerCase().contains('breach') || 
        log.message.toLowerCase().contains('attack')).length;
    
    final analysis = LogAnalysis(
      id: analysisId,
      sourceId: sourceId,
      type: AnalysisType.security,
      title: 'Security Events Analysis',
      description: 'Analysis of security-related log entries',
      data: {
        'total_security_logs': securityLogs.length,
        'authentication_failures': authenticationFailures,
        'unauthorized_attempts': unauthorizedAttempts,
        'breach_events': breachEvents,
        'security_score': _calculateSecurityScore(securityLogs.length, logs.length),
      },
      confidence: 0.95,
      createdAt: DateTime.now(),
    );
    
    _analyses[analysisId] = analysis;
    _totalAnalyses++;
    
    developer.log('📊 Analyzed security events for source $sourceId');
  }

  double _calculatePerformanceScore(int perfLogs, int totalLogs) {
    if (totalLogs == 0) return 1.0;
    
    final perfRatio = perfLogs / totalLogs;
    // Lower score is better (fewer performance issues)
    return math.max(0.0, 1.0 - (perfRatio * 2));
  }

  double _calculateSecurityScore(int securityLogs, int totalLogs) {
    if (totalLogs == 0) return 1.0;
    
    final securityRatio = securityLogs / totalLogs;
    // Lower score is better (fewer security issues)
    return math.max(0.0, 1.0 - (securityRatio * 3));
  }

  String _normalizeErrorMessage(String message) {
    // Normalize error message by removing specific values and timestamps
    return message
        .toLowerCase()
        .replaceAll(RegExp(r'\d+'), 'N') // Replace numbers
        .replaceAll(RegExp(r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\b'), 'TIMESTAMP') // Replace timestamps
        .replaceAll(RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'), 'UUID') // Replace UUIDs
        .replaceAll(RegExp(r'\b\w+@\w+\.\w+\b'), 'EMAIL') // Replace emails
        .replaceAll(RegExp(r'\b/\w+/\b'), 'PATH') // Replace file paths
        .trim();
  }

  List<LogEntry> _getRecentEntries(String sourceId, Duration duration) {
    final logs = _aggregatedLogs[sourceId] ?? [];
    final cutoffTime = DateTime.now().subtract(duration);
    
    return logs
        .where((entry) => entry.timestamp.isAfter(cutoffTime))
        .toList();
  }

  Future<void> _performCleanup() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 7));
    
    // Clean old aggregated logs
    for (final entry in _aggregatedLogs.entries) {
      final sourceId = entry.key;
      final logs = entry.value;
      
      final initialCount = logs.length;
      logs.removeWhere((log) => log.timestamp.isBefore(cutoffDate));
      final removedCount = initialCount - logs.length;
      
      if (removedCount > 0) {
        _totalAggregatedEntries -= removedCount;
        developer.log('📊 Cleaned $removedCount old log entries for source $sourceId');
      }
    }
    
    // Clean old analyses
    final initialAnalysisCount = _analyses.length;
    _analyses.removeWhere((analysis) => analysis.createdAt.isBefore(cutoffDate));
    final removedAnalysisCount = initialAnalysisCount - _analyses.length;
    
    if (removedAnalysisCount > 0) {
      _totalAnalyses -= removedAnalysisCount;
      developer.log('📊 Cleaned $removedAnalysisCount old analyses');
    }
    
    await _saveAggregatedLogs();
    await _saveAnalyses();
  }

  Future<void> _saveConfiguration() async {
    try {
      final file = File(_configFile);
      
      final sourcesData = _sources.values.map((source) => source.toJson()).toList();
      final detectorsData = _anomalyDetectors.values.map((detector) => detector.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'sources': sourcesData,
        'anomaly_detectors': detectorsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save configuration: $e');
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
      developer.log('📊 Failed to save patterns: $e');
    }
  }

  Future<void> _saveAggregatedLogs() async {
    try {
      final file = File(_aggregatedFile);
      
      final aggregatedData = _aggregatedLogs.entries.map((entry) => {
        'source_id': entry.key,
        'logs': entry.value.map((log) => log.toJson()).toList(),
      }).toList();
      
      final analysesData = _analyses.values.map((analysis) => analysis.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'aggregated_logs': aggregatedData,
        'analyses': analysesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save aggregated logs: $e');
    }
  }

  Future<void> _saveAnalyses() async {
    // Analyses are saved with aggregated logs
    await _saveAggregatedLogs();
  }

  Future<String> createPattern({
    required String name,
    required String description,
    required String regex,
    required LogSeverity severity,
    required LogCategory category,
    LogAction? action,
    int? priority,
    List<String>? tags,
    Map<String, dynamic>? config,
  }) async {
    if (_patterns.length >= _maxPatterns) {
      throw Exception('Maximum patterns reached: $_maxPatterns');
    }
    
    final patternId = _generatePatternId();
    
    final pattern = LogPattern(
      id: patternId,
      name: name,
      description: description,
      regex: regex,
      severity: severity,
      category: category,
      priority: priority ?? 5,
      action: action ?? LogAction.monitor,
      tags: tags ?? [],
      enabled: true,
      config: config ?? {},
      matchCount: 0,
      lastMatched: null,
      createdAt: DateTime.now(),
    );
    
    _patterns[patternId] = pattern;
    _totalPatterns++;
    
    developer.log('📊 Created log pattern: $name');
    
    _emitEvent(LogEvent(
      type: LogEventType.patternCreated,
      patternId: patternId,
      patternName: name,
    ));
    
    await _savePatterns();
    
    return patternId;
  }

  Future<String> createAnomalyDetector({
    required String name,
    required String description,
    required AnomalyType type,
    required Map<String, dynamic> config,
  }) async {
    final detectorId = _generateDetectorId();
    
    final detector = AnomalyDetection(
      id: detectorId,
      name: name,
      description: description,
      type: type,
      config: config,
      enabled: true,
      detectionCount: 0,
      lastDetected: null,
      createdAt: DateTime.now(),
    );
    
    _anomalyDetectors[detectorId] = detector;
    
    developer.log('📊 Created anomaly detector: $name');
    
    _emitEvent(LogEvent(
      type: LogEventType.anomalyDetectorCreated,
      detectorId: detectorId,
      detectorName: name,
    ));
    
    await _saveConfiguration();
    
    return detectorId;
  }

  Future<LogQueryResult> queryLogs({
    String? sourceId,
    String? query,
    LogSeverity? severity,
    LogCategory? category,
    DateTime? startTime,
    DateTime? endTime,
    int? limit,
    bool? includeMetadata,
  }) async {
    var results = <LogEntry>[];
    
    // Filter by source
    var logsToSearch = <LogEntry>[];
    if (sourceId != null) {
      logsToSearch = _aggregatedLogs[sourceId] ?? [];
    } else {
      for (final sourceLogs in _aggregatedLogs.values) {
        logsToSearch.addAll(sourceLogs);
      }
    }
    
    // Apply filters
    for (final log in logsToSearch) {
      bool matches = true;
      
      if (query != null && !log.message.toLowerCase().contains(query!.toLowerCase())) {
        matches = false;
      }
      
      if (severity != null && log.severity != severity) {
        matches = false;
      }
      
      if (category != null && log.category != category) {
        matches = false;
      }
      
      if (startTime != null && log.timestamp.isBefore(startTime!)) {
        matches = false;
      }
      
      if (endTime != null && log.timestamp.isAfter(endTime!)) {
        matches = false;
      }
      
      if (matches) {
        results.add(log);
      }
    }
    
    // Sort by timestamp (newest first)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    // Apply limit
    if (limit != null && limit! > 0) {
      results = results.take(limit!).toList();
    }
    
    // Remove metadata if not requested
    if (includeMetadata != true) {
      results = results.map((log) => LogEntry(
        id: log.id,
        sourceId: log.sourceId,
        message: log.message,
        severity: log.severity,
        category: log.category,
        metadata: {},
        timestamp: log.timestamp,
        processed: log.processed,
        patterns: log.patterns,
        anomalies: log.anomalies,
      )).toList();
    }
    
    return LogQueryResult(
      results: results,
      totalCount: results.length,
      hasMore: false, // Simplified - in practice would check if more results exist
      queryTime: DateTime.now(),
    );
  }

  Future<LogAnalysis> getAnalysis(String analysisId) async {
    return _analyses[analysisId];
  }

  List<LogAnalysis> getAnalyses({String? sourceId}) {
    final analyses = _analyses.values.toList();
    
    if (sourceId != null) {
      return analyses.where((analysis) => analysis.sourceId == sourceId).toList();
    }
    
    return analyses;
  }

  LogAggregationStats getStats() {
    return LogAggregationStats(
      totalSources: _totalSources,
      totalPatterns: _totalPatterns,
      totalAggregatedEntries: _totalAggregatedEntries,
      totalAnalyses: _totalAnalyses,
      enabledSources: _sources.values.where((source) => source.enabled).length,
      enabledPatterns: _patterns.values.where((pattern) => pattern.enabled).length,
      entriesBySource: _aggregatedLogs.entries.map((entry) => 
          MapEntry(entry.key, entry.value.length)).toList(),
      analysesByType: _analyses.values.fold(<AnalysisType, int>{}, (map, analysis) {
        map[analysis.type] = (map[analysis.type] ?? 0) + 1;
        return map;
      }),
    );
  }

  String _generateSourceId() {
    return 'source_${DateTime.now().millisecondsSinceEpoch}_$_totalSources';
  }

  String _generateEntryId() {
    return 'entry_${DateTime.now().millisecondsSinceEpoch}_$_totalAggregatedEntries';
  }

  String _generatePatternId() {
    return 'pattern_${DateTime.now().millisecondsSinceEpoch}_$_totalPatterns';
  }

  String _generateDetectorId() {
    return 'detector_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateAnalysisId() {
    return 'analysis_${DateTime.now().millisecondsSinceEpoch}_$_totalAnalyses';
  }

  void _emitEvent(LogEvent event) {
    _logController.add(event);
  }

  Stream<LogEvent> get logEventStream => _logController.stream;

  void dispose() {
    _aggregationTimer?.cancel();
    _cleanupTimer?.cancel();
    _analysisTimer?.cancel();
    
    _sources.clear();
    _patterns.clear();
    _aggregatedLogs.clear();
    _analyses.clear();
    _anomalyDetectors.clear();
    _logController.close();
    
    developer.log('📊 Intelligent Log Aggregation disposed');
  }
}

class LogSource {
  final String id;
  final String name;
  final String path;
  final LogSourceType type;
  final String format;
  final Map<String, dynamic> config;
  final bool enabled;
  final int lastPosition;
  final int totalLines;
  final DateTime lastModified;
  final DateTime createdAt;

  LogSource({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.format,
    required this.config,
    required this.enabled,
    required this.lastPosition,
    required this.totalLines,
    required this.lastModified,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'type': type.name,
      'format': format,
      'config': config,
      'enabled': enabled,
      'last_position': lastPosition,
      'total_lines': totalLines,
      'last_modified': lastModified.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory LogSource.fromJson(Map<String, dynamic> json) {
    return LogSource(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      type: LogSourceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => LogSourceType.file,
      ),
      format: json['format'],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      enabled: json['enabled'] ?? true,
      lastPosition: json['last_position'] ?? 0,
      totalLines: json['total_lines'] ?? 0,
      lastModified: DateTime.parse(json['last_modified']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class LogPattern {
  final String id;
  final String name;
  final String description;
  final String regex;
  final LogSeverity severity;
  final LogCategory category;
  final int priority;
  final LogAction action;
  final List<String> tags;
  final bool enabled;
  final Map<String, dynamic> config;
  final int matchCount;
  final DateTime? lastMatched;
  final DateTime createdAt;

  LogPattern({
    required this.id,
    required this.name,
    required this.description,
    required this.regex,
    required this.severity,
    required this.category,
    required this.priority,
    required this.action,
    required this.tags,
    required this.enabled,
    required this.config,
    required this.matchCount,
    this.lastMatched,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'regex': regex,
      'severity': severity.name,
      'category': category.name,
      'priority': priority,
      'action': action.name,
      'tags': tags,
      'enabled': enabled,
      'config': config,
      'match_count': matchCount,
      'last_matched': lastMatched?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory LogPattern.fromJson(Map<String, dynamic> json) {
    return LogPattern(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      regex: json['regex'],
      severity: LogSeverity.values.firstWhere(
        (severity) => severity.name == json['severity'],
        orElse: () => LogSeverity.info,
      ),
      category: LogCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => LogCategory.general,
      ),
      priority: json['priority'] ?? 5,
      action: LogAction.values.firstWhere(
        (action) => action.name == json['action'],
        orElse: () => LogAction.monitor,
      ),
      tags: List<String>.from(json['tags'] ?? []),
      enabled: json['enabled'] ?? true,
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      matchCount: json['match_count'] ?? 0,
      lastMatched: json['last_matched'] != null ? DateTime.parse(json['last_matched']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class AnomalyDetection {
  final String id;
  final String name;
  final String description;
  final AnomalyType type;
  final Map<String, dynamic> config;
  final bool enabled;
  final int detectionCount;
  final DateTime? lastDetected;
  final DateTime createdAt;

  AnomalyDetection({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.config,
    required this.enabled,
    required this.detectionCount,
    this.lastDetected,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'config': config,
      'enabled': enabled,
      'detection_count': detectionCount,
      'last_detected': lastDetected?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AnomalyDetection.fromJson(Map<String, dynamic> json) {
    return AnomalyDetection(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: AnomalyType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => AnomalyType.frequency,
      ),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      enabled: json['enabled'] ?? true,
      detectionCount: json['detection_count'] ?? 0,
      lastDetected: json['last_detected'] != null ? DateTime.parse(json['last_detected']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class LogEntry {
  final String id;
  final String sourceId;
  final String message;
  final LogSeverity severity;
  final LogCategory category;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  final bool processed;
  final List<String> patterns;
  final List<String> anomalies;

  LogEntry({
    required this.id,
    required this.sourceId,
    required this.message,
    required this.severity,
    required this.category,
    required this.metadata,
    required this.timestamp,
    required this.processed,
    required this.patterns,
    required this.anomalies,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_id': sourceId,
      'message': message,
      'severity': severity.name,
      'category': category.name,
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
      'processed': processed,
      'patterns': patterns,
      'anomalies': anomalies,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'],
      sourceId: json['source_id'],
      message: json['message'],
      severity: LogSeverity.values.firstWhere(
        (severity) => severity.name == json['severity'],
        orElse: () => LogSeverity.info,
      ),
      category: LogCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => LogCategory.general,
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      timestamp: DateTime.parse(json['timestamp']),
      processed: json['processed'] ?? false,
      patterns: List<String>.from(json['patterns'] ?? []),
      anomalies: List<String>.from(json['anomalies'] ?? []),
    );
  }
}

class LogAnalysis {
  final String id;
  final String sourceId;
  final AnalysisType type;
  final String title;
  final String description;
  final Map<String, dynamic> data;
  final double confidence;
  final DateTime createdAt;

  LogAnalysis({
    required this.id,
    required this.sourceId,
    required this.type,
    required this.title,
    required this.description,
    required this.data,
    required this.confidence,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_id': sourceId,
      'type': type.name,
      'title': title,
      'description': description,
      'data': data,
      'confidence': confidence,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory LogAnalysis.fromJson(Map<String, dynamic> json) {
    return LogAnalysis(
      id: json['id'],
      sourceId: json['source_id'],
      type: AnalysisType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => AnalysisType.trends,
      ),
      title: json['title'],
      description: json['description'],
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class PatternMatch {
  final String patternId;
  final String patternName;
  final String matchedText;
  final int startIndex;
  final int endIndex;
  final LogSeverity severity;
  final LogCategory category;
  final double confidence;
  final DateTime timestamp;

  PatternMatch({
    required this.patternId,
    required this.patternName,
    required this.matchedText,
    required this.startIndex,
    required this.endIndex,
    required this.severity,
    required this.category,
    required this.confidence,
    required this.timestamp,
  });
}

class LogQueryResult {
  final List<LogEntry> results;
  final int totalCount;
  final bool hasMore;
  final DateTime queryTime;

  LogQueryResult({
    required this.results,
    required this.totalCount,
    required this.hasMore,
    required this.queryTime,
  });
}

class LogAggregationStats {
  final int totalSources;
  final int totalPatterns;
  final int totalAggregatedEntries;
  final int totalAnalyses;
  final int enabledSources;
  final int enabledPatterns;
  final List<MapEntry<String, int>> entriesBySource;
  final Map<AnalysisType, int> analysesByType;

  LogAggregationStats({
    required this.totalSources,
    required this.totalPatterns,
    required this.totalAggregatedEntries,
    required this.totalAnalyses,
    required this.enabledSources,
    required this.enabledPatterns,
    required this.entriesBySource,
    required this.analysesByType,
  });
}

enum LogSourceType {
  file,
  syslog,
  json,
  database,
  api,
}

enum LogSeverity {
  debug,
  info,
  warning,
  error,
  critical,
}

enum LogCategory {
  general,
  error,
  performance,
  security,
  network,
  application,
  anomaly,
}

enum LogAction {
  ignore,
  monitor,
  warn,
  alert,
}

enum AnomalyType {
  frequency,
  burst,
  outlier,
  sequence,
  semantic,
}

enum AnalysisType {
  trends,
  errorPatterns,
  performance,
  security,
}

enum LogEventType {
  sourceAdded,
  entryAdded,
  patternCreated,
  anomalyDetectorCreated,
  alertCreated,
  warningCreated,
  monitoringEventCreated,
  analysisGenerated,
}
