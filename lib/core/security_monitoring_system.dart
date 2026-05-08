import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Security monitoring system with threat detection and response
/// 
/// Features:
/// - Real-time security monitoring
/// - Anomaly detection and alerting
/// - Intrusion detection
/// - File integrity monitoring
/// - Security policy enforcement
class SecurityMonitoringSystem {
  final StreamController<SecurityEvent> _eventController = StreamController<SecurityEvent>.broadcast();
  
  final Map<String, SecurityPolicy> _policies = {};
  final List<SecurityAlert> _alerts = [];
  final Map<String, FileIntegrity> _fileIntegrity = {};
  final Map<String, SecurityMetric> _metrics = {};
  final List<SecurityIncident> _incidents = [];
  
  Timer? _monitoringTimer;
  Timer? _integrityCheckTimer;
  Timer? _policyCheckTimer;
  bool _isInitialized = false;
  bool _isMonitoring = false;
  late SharedPreferences _prefs;
  
  Stream<SecurityEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isMonitoring => _isMonitoring;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load security data
      await _loadSecurityData();
      
      // Initialize security policies
      _initializeSecurityPolicies();
      
      // Initialize file integrity monitoring
      await _initializeFileIntegrity();
      
      // Start monitoring
      _startSecurityMonitoring();
      
      // Start integrity checks
      _startIntegrityChecks();
      
      // Start policy checks
      _startPolicyChecks();
      
      _isInitialized = true;
      
      _eventController.add(SecurityEvent(
        type: SecurityEventType.initialized,
        message: 'Security monitoring system initialized',
        data: {
          'policies': _policies.length,
          'monitoredFiles': _fileIntegrity.length,
        },
      ));
      
      debugPrint('🔒 Security Monitoring System initialized');
    } catch (e) {
      debugPrint('Failed to initialize security monitoring system: $e');
    }
  }
  
  Future<void> _loadSecurityData() async {
    try {
      final policiesJson = _prefs.getString('security_policies');
      if (policiesJson != null) {
        final policiesMap = jsonDecode(policiesJson);
        _policies = policiesMap.map((key, value) => 
          MapEntry(key, SecurityPolicy.fromJson(value)));
      }
      
      final alertsJson = _prefs.getString('security_alerts');
      if (alertsJson != null) {
        final alertsList = jsonDecode(alertsJson);
        _alerts = alertsList.map((item) => 
          SecurityAlert.fromJson(item)).toList();
      }
      
      final integrityJson = _prefs.getString('file_integrity');
      if (integrityJson != null) {
        final integrityMap = jsonDecode(integrityJson);
        _fileIntegrity = integrityMap.map((key, value) => 
          MapEntry(key, FileIntegrity.fromJson(value)));
      }
      
      final incidentsJson = _prefs.getString('security_incidents');
      if (incidentsJson != null) {
        final incidentsList = jsonDecode(incidentsJson);
        _incidents = incidentsList.map((item) => 
          SecurityIncident.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load security data: $e');
    }
  }
  
  void _initializeSecurityPolicies() {
    // File access policy
    _policies['file_access'] = SecurityPolicy(
      id: 'file_access',
      name: 'File Access Control',
      description: 'Monitor and control file access patterns',
      type: PolicyType.file_access,
      enabled: true,
      severity: SecuritySeverity.medium,
      rules: [
        SecurityRule(
          id: 'sensitive_file_access',
          description: 'Alert on access to sensitive files',
          condition: 'file_path CONTAINS ["private", "secret", "key"]',
          action: 'alert',
          enabled: true,
        ),
        SecurityRule(
          id: 'unusual_access_time',
          description: 'Alert on unusual access times',
          condition: 'access_time BETWEEN 23:00 AND 05:00',
          action: 'log',
          enabled: true,
        ),
      ],
    );
    
    // Network security policy
    _policies['network_security'] = SecurityPolicy(
      id: 'network_security',
      name: 'Network Security',
      description: 'Monitor network connections and traffic',
      type: PolicyType.network,
      enabled: true,
      severity: SecuritySeverity.high,
      rules: [
        SecurityRule(
          id: 'suspicious_connections',
          description: 'Alert on suspicious network connections',
          condition: 'remote_port IN [22, 3389, 5900] AND NOT trusted_ip',
          action: 'alert',
          enabled: true,
        ),
        SecurityRule(
          id: 'unusual_bandwidth',
          description: 'Alert on unusual bandwidth usage',
          condition: 'bandwidth_usage > baseline * 3',
          action: 'throttle',
          enabled: true,
        ),
      ],
    );
    
    // Process security policy
    _policies['process_security'] = SecurityPolicy(
      id: 'process_security',
      name: 'Process Security',
      description: 'Monitor running processes for threats',
      type: PolicyType.process,
      enabled: true,
      severity: SecuritySeverity.high,
      rules: [
        SecurityRule(
          id: 'suspicious_processes',
          description: 'Alert on suspicious process execution',
          condition: 'process_name IN ["nc", "netcat", "nmap", "wireshark"]',
          action: 'alert',
          enabled: true,
        ),
        SecurityRule(
          id: 'privilege_escalation',
          description: 'Alert on privilege escalation attempts',
          condition: 'process_uid = 0 AND NOT trusted_process',
          action: 'alert',
          enabled: true,
        ),
      ],
    );
    
    // System integrity policy
    _policies['system_integrity'] = SecurityPolicy(
      id: 'system_integrity',
      name: 'System Integrity',
      description: 'Monitor system file integrity',
      type: PolicyType.integrity,
      enabled: true,
      severity: SecuritySeverity.critical,
      rules: [
        SecurityRule(
          id: 'system_file_modification',
          description: 'Alert on system file modifications',
          condition: 'file_path STARTS WITH ["/etc", "/bin", "/sbin", "/usr/bin"] AND modification_detected',
          action: 'alert',
          enabled: true,
        ),
        SecurityRule(
          id: 'startup_modification',
          description: 'Alert on startup script modifications',
          condition: 'file_path IN ["/etc/rc.local", "/etc/init.d", "~/.bashrc"] AND modification_detected',
          action: 'alert',
          enabled: true,
        ),
      ],
    );
  }
  
  Future<void> _initializeFileIntegrity() async {
    try {
      final criticalFiles = [
        '/etc/passwd',
        '/etc/shadow',
        '/etc/sudoers',
        '/etc/hosts',
        '/etc/ssh/sshd_config',
        '~/.ssh/authorized_keys',
        '~/.bashrc',
        '~/.profile',
      ];
      
      for (final filePath in criticalFiles) {
        final expandedPath = filePath.startsWith('~') 
            ? filePath.replaceFirst('~', Platform.environment['HOME'] ?? '')
            : filePath;
        
        final file = File(expandedPath);
        if (await file.exists()) {
          final hash = await _calculateFileHash(file);
          final stat = await file.stat();
          
          _fileIntegrity[filePath] = FileIntegrity(
            path: filePath,
            hash: hash,
            lastModified: stat.modified,
            size: stat.size,
            permissions: stat.mode,
            monitored: true,
            lastCheck: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize file integrity: $e');
    }
  }
  
  void _startSecurityMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _performSecurityMonitoring();
    });
  }
  
  void _startIntegrityChecks() {
    _integrityCheckTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _performIntegrityChecks();
    });
  }
  
  void _startPolicyChecks() {
    _policyCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _performPolicyChecks();
    });
  }
  
  Future<void> _performSecurityMonitoring() async {
    if (_isMonitoring) return;
    
    try {
      _isMonitoring = true;
      
      // Monitor network connections
      await _monitorNetworkConnections();
      
      // Monitor running processes
      await _monitorProcesses();
      
      // Monitor system calls
      await _monitorSystemCalls();
      
      // Update security metrics
      await _updateSecurityMetrics();
      
    } catch (e) {
      debugPrint('Failed to perform security monitoring: $e');
    } finally {
      _isMonitoring = false;
    }
  }
  
  Future<void> _monitorNetworkConnections() async {
    try {
      final result = await run('netstat', ['-tuln']);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.contains('LISTEN') || line.contains('ESTABLISHED')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final protocol = parts[0];
            final localAddress = parts[3];
            final foreignAddress = parts[4];
            final state = parts[5];
            
            // Check against security policies
            await _checkNetworkSecurity(protocol, localAddress, foreignAddress, state);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to monitor network connections: $e');
    }
  }
  
  Future<void> _monitorProcesses() async {
    try {
      final result = await run('ps', ['-eo', 'pid,comm,user,uid,cmd']);
      final lines = result.stdout.split('\n');
      
      for (final line in lines.skip(1)) { // Skip header
        if (line.trim().isEmpty) continue;
        
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final pid = parts[0];
          final command = parts[1];
          final user = parts[2];
          final uid = parts[3];
          
          // Check against security policies
          await _checkProcessSecurity(pid, command, user, uid);
        }
      }
    } catch (e) {
      debugPrint('Failed to monitor processes: $e');
    }
  }
  
  Future<void> _monitorSystemCalls() async {
    try {
      // Monitor audit logs if available
      final result = await run('journalctl', ['-k', 'AUDIT', '--since', '5 minutes ago']);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.contains('syscall')) {
          // Parse system call information
          await _analyzeSystemCall(line);
        }
      }
    } catch (e) {
      debugPrint('Failed to monitor system calls: $e');
    }
  }
  
  Future<void> _updateSecurityMetrics() async {
    try {
      final timestamp = DateTime.now();
      
      // Network metrics
      final connectionCount = await _getNetworkConnectionCount();
      _metrics['network_connections_${timestamp.millisecondsSinceEpoch}'] = SecurityMetric(
        name: 'network_connections',
        value: connectionCount.toDouble(),
        timestamp: timestamp,
        unit: 'count',
        category: SecurityCategory.network,
      );
      
      // Process metrics
      final processCount = await _getProcessCount();
      _metrics['process_count_${timestamp.millisecondsSinceEpoch}'] = SecurityMetric(
        name: 'process_count',
        value: processCount.toDouble(),
        timestamp: timestamp,
        unit: 'count',
        category: SecurityCategory.process,
      );
      
      // Authentication metrics
      final authFailures = await _getAuthenticationFailures();
      _metrics['auth_failures_${timestamp.millisecondsSinceEpoch}'] = SecurityMetric(
        name: 'auth_failures',
        value: authFailures.toDouble(),
        timestamp: timestamp,
        unit: 'count',
        category: SecurityCategory.authentication,
      );
      
      // Keep only last 500 metrics
      if (_metrics.length > 500) {
        final keys = _metrics.keys.toList()..sort();
        final toRemove = keys.take(_metrics.length - 500);
        for (final key in toRemove) {
          _metrics.remove(key);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to update security metrics: $e');
    }
  }
  
  Future<void> _checkNetworkSecurity(
    String protocol, 
    String localAddress, 
    String foreignAddress, 
    String state
  ) async {
    try {
      final networkPolicy = _policies['network_security'];
      if (networkPolicy == null || !networkPolicy.enabled) return;
      
      for (final rule in networkPolicy.rules) {
        if (!rule.enabled) continue;
        
        if (await _evaluateSecurityRule(rule, {
          'protocol': protocol,
          'local_address': localAddress,
          'foreign_address': foreignAddress,
          'state': state,
        })) {
          await _triggerSecurityRule(rule, 'network', {
            'protocol': protocol,
            'local_address': localAddress,
            'foreign_address': foreignAddress,
            'state': state,
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to check network security: $e');
    }
  }
  
  Future<void> _checkProcessSecurity(
    String pid, 
    String command, 
    String user, 
    String uid
  ) async {
    try {
      final processPolicy = _policies['process_security'];
      if (processPolicy == null || !processPolicy.enabled) return;
      
      for (final rule in processPolicy.rules) {
        if (!rule.enabled) continue;
        
        if (await _evaluateSecurityRule(rule, {
          'pid': pid,
          'command': command,
          'user': user,
          'uid': uid,
        })) {
          await _triggerSecurityRule(rule, 'process', {
            'pid': pid,
            'command': command,
            'user': user,
            'uid': uid,
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to check process security: $e');
    }
  }
  
  Future<void> _analyzeSystemCall(String logLine) async {
    try {
      // Parse system call from audit log
      final syscallMatch = RegExp(r'syscall=(\w+)').firstMatch(logLine);
      if (syscallMatch != null) {
        final syscall = syscallMatch.group(1)!;
        
        // Check for dangerous system calls
        final dangerousSyscalls = ['execve', 'ptrace', 'mount', 'umount', 'chmod', 'chown'];
        if (dangerousSyscalls.contains(syscall)) {
          await _createSecurityAlert(
            type: SecurityAlertType.suspicious_activity,
            severity: SecuritySeverity.high,
            message: 'Suspicious system call detected: $syscall',
            details: {'syscall': syscall, 'log': logLine},
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to analyze system call: $e');
    }
  }
  
  Future<bool> _evaluateSecurityRule(
    SecurityRule rule, 
    Map<String, dynamic> context
  ) async {
    try {
      // Simple rule evaluation
      final condition = rule.condition;
      
      if (condition.contains('CONTAINS')) {
        final values = condition.split('CONTAINS')[1].trim();
        final valueList = values.replaceAll(RegExp(r'[\[\]]'), '').split(',').map((v) => v.trim()).toList();
        final fieldValue = context['file_path'] ?? '';
        
        return valueList.any((value) => fieldValue.toLowerCase().contains(value.toLowerCase()));
      }
      
      if (condition.contains('IN')) {
        final values = condition.split('IN')[1].trim();
        final valueList = values.replaceAll(RegExp(r'[\[\]]'), '').split(',').map((v) => v.trim()).toList();
        final fieldValue = context['process_name'] ?? '';
        
        return valueList.contains(fieldValue);
      }
      
      if (condition.contains('BETWEEN')) {
        final timeRange = condition.split('BETWEEN')[1].trim();
        final times = timeRange.split('AND').map((t) => t.trim()).toList();
        
        if (times.length >= 2) {
          final currentTime = DateTime.now();
          final currentHour = currentTime.hour;
          
          final startHour = int.tryParse(times[0].split(':')[0]) ?? 0;
          final endHour = int.tryParse(times[1].split(':')[0]) ?? 23;
          
          if (startHour > endHour) {
            return currentHour >= startHour || currentHour <= endHour;
          } else {
            return currentHour >= startHour && currentHour <= endHour;
          }
        }
      }
      
      if (condition.contains('STARTS WITH')) {
        final values = condition.split('STARTS WITH')[1].trim();
        final valueList = values.replaceAll(RegExp(r'[\[\]]'), '').split(',').map((v) => v.trim()).toList();
        final fieldValue = context['file_path'] ?? '';
        
        return valueList.any((value) => fieldValue.startsWith(value));
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate security rule: $e');
      return false;
    }
  }
  
  Future<void> _triggerSecurityRule(
    SecurityRule rule, 
    String category, 
    Map<String, dynamic> details
  ) async {
    try {
      switch (rule.action) {
        case 'alert':
          await _createSecurityAlert(
            type: SecurityAlertType.policy_violation,
            severity: _policies.values
                .where((p) => p.rules.contains(rule))
                .first.severity,
            message: 'Security policy violation: ${rule.description}',
            details: details,
          );
          break;
          
        case 'log':
          await _logSecurityEvent(category, details);
          break;
          
        case 'throttle':
          await _throttleResource(category, details);
          break;
          
        default:
          debugPrint('Unknown security rule action: ${rule.action}');
      }
    } catch (e) {
      debugPrint('Failed to trigger security rule: $e');
    }
  }
  
  Future<void> _createSecurityAlert({
    required SecurityAlertType type,
    required SecuritySeverity severity,
    required String message,
    required Map<String, dynamic> details,
  }) async {
    try {
      final alert = SecurityAlert(
        id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        severity: severity,
        message: message,
        details: details,
        timestamp: DateTime.now(),
        acknowledged: false,
      );
      
      _alerts.add(alert);
      
      _eventController.add(SecurityEvent(
        type: SecurityEventType.alert_created,
        message: 'Security alert created: $message',
        data: {
          'alertId': alert.id,
          'type': type.name,
          'severity': severity.name,
        },
      ));
      
      // Save alerts
      await _saveSecurityData();
      
    } catch (e) {
      debugPrint('Failed to create security alert: $e');
    }
  }
  
  Future<void> _logSecurityEvent(String category, Map<String, dynamic> details) async {
    try {
      final incident = SecurityIncident(
        id: 'incident_${DateTime.now().millisecondsSinceEpoch}',
        category: category,
        severity: SecuritySeverity.medium,
        description: 'Security event logged: $category',
        details: details,
        timestamp: DateTime.now(),
        resolved: false,
      );
      
      _incidents.add(incident);
      
      _eventController.add(SecurityEvent(
        type: SecurityEventType.incident_logged,
        message: 'Security incident logged: $category',
        data: {
          'incidentId': incident.id,
          'category': category,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to log security event: $e');
    }
  }
  
  Future<void> _throttleResource(String category, Map<String, dynamic> details) async {
    try {
      if (category == 'network') {
        // Implement network throttling
        await run('tc', ['qdisc', 'add', 'dev', 'eth0', 'root', 'netem', 'rate', '1mbit']);
      }
      
      _eventController.add(SecurityEvent(
        type: SecurityEventType.resource_throttled,
        message: 'Security resource throttled: $category',
        data: details,
      ));
      
    } catch (e) {
      debugPrint('Failed to throttle resource: $e');
    }
  }
  
  Future<void> _performIntegrityChecks() async {
    try {
      for (final entry in _fileIntegrity.entries) {
        final filePath = entry.key;
        final integrity = entry.value;
        
        if (!integrity.monitored) continue;
        
        final expandedPath = filePath.startsWith('~') 
            ? filePath.replaceFirst('~', Platform.environment['HOME'] ?? '')
            : filePath;
        
        final file = File(expandedPath);
        if (!await file.exists()) continue;
        
        final currentHash = await _calculateFileHash(file);
        final stat = await file.stat();
        
        if (currentHash != integrity.hash) {
          await _createSecurityAlert(
            type: SecurityAlertType.integrity_violation,
            severity: SecuritySeverity.critical,
            message: 'File integrity violation: $filePath',
            details: {
              'filePath': filePath,
              'originalHash': integrity.hash,
              'currentHash': currentHash,
              'lastModified': stat.modified,
            },
          );
          
          // Update integrity record
          _fileIntegrity[filePath] = FileIntegrity(
            path: filePath,
            hash: currentHash,
            lastModified: stat.modified,
            size: stat.size,
            permissions: stat.mode,
            monitored: true,
            lastCheck: DateTime.now(),
          );
        }
      }
      
      // Save integrity data
      await _saveSecurityData();
      
    } catch (e) {
      debugPrint('Failed to perform integrity checks: $e');
    }
  }
  
  Future<void> _performPolicyChecks() async {
    try {
      for (final policy in _policies.values) {
        if (!policy.enabled) continue;
        
        // Check policy-specific conditions
        await _checkPolicyCompliance(policy);
      }
    } catch (e) {
      debugPrint('Failed to perform policy checks: $e');
    }
  }
  
  Future<void> _checkPolicyCompliance(SecurityPolicy policy) async {
    try {
      switch (policy.type) {
        case PolicyType.file_access:
          await _checkFileAccessPolicy(policy);
          break;
        case PolicyType.network:
          await _checkNetworkPolicy(policy);
          break;
        case PolicyType.process:
          await _checkProcessPolicy(policy);
          break;
        case PolicyType.integrity:
          // Integrity checks are performed separately
          break;
      }
    } catch (e) {
      debugPrint('Failed to check policy compliance: $e');
    }
  }
  
  Future<void> _checkFileAccessPolicy(SecurityPolicy policy) async {
    try {
      // Monitor recent file access patterns
      final result = await run('find', [
        Platform.environment['HOME'] ?? '',
        '-type', 'f',
        '-amin', '-5', // Accessed in last 5 minutes
        '-exec', 'ls', '-la', '{}', ';'
      ]);
      
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        // Check against file access rules
        for (final rule in policy.rules) {
          if (!rule.enabled) continue;
          
          if (await _evaluateSecurityRule(rule, {'file_path': line})) {
            await _triggerSecurityRule(rule, 'file_access', {'access_log': line});
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to check file access policy: $e');
    }
  }
  
  Future<void> _checkNetworkPolicy(SecurityPolicy policy) async {
    try {
      // Network policy checks are performed during monitoring
      // This is a placeholder for additional network-specific checks
    } catch (e) {
      debugPrint('Failed to check network policy: $e');
    }
  }
  
  Future<void> _checkProcessPolicy(SecurityPolicy policy) async {
    try {
      // Process policy checks are performed during monitoring
      // This is a placeholder for additional process-specific checks
    } catch (e) {
      debugPrint('Failed to check process policy: $e');
    }
  }
  
  Future<String> _calculateFileHash(File file) async {
    try {
      final result = await run('sha256sum', [file.path]);
      return result.stdout.split(' ').first;
    } catch (e) {
      debugPrint('Failed to calculate file hash: $e');
      return '';
    }
  }
  
  Future<int> _getNetworkConnectionCount() async {
    try {
      final result = await run('netstat', ['-an']);
      return result.stdout.split('\n').where((line) => 
          line.contains('ESTABLISHED') || line.contains('LISTEN')).length;
    } catch (e) {
      return 0;
    }
  }
  
  Future<int> _getProcessCount() async {
    try {
      final result = await run('ps', ['-e']);
      return result.stdout.split('\n').length - 1; // Subtract header
    } catch (e) {
      return 0;
    }
  }
  
  Future<int> _getAuthenticationFailures() async {
    try {
      final result = await run('journalctl', ['-k', 'AUTH', '--since', '1 hour ago']);
      return result.stdout.split('\n').where((line) => 
          line.contains('failure') || line.contains('failed')).length;
    } catch (e) {
      return 0;
    }
  }
  
  Future<void> _saveSecurityData() async {
    try {
      final policiesMap = _policies.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('security_policies', jsonEncode(policiesMap));
      
      final alertsList = _alerts.take(100).map((alert) => alert.toJson()).toList();
      await _prefs.setString('security_alerts', jsonEncode(alertsList));
      
      final integrityMap = _fileIntegrity.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('file_integrity', jsonEncode(integrityMap));
      
      final incidentsList = _incidents.take(100).map((incident) => incident.toJson()).toList();
      await _prefs.setString('security_incidents', jsonEncode(incidentsList));
      
    } catch (e) {
      debugPrint('Failed to save security data: $e');
    }
  }
  
  Future<void> acknowledgeAlert(String alertId) async {
    try {
      final alert = _alerts.firstWhere((a) => a.id == alertId, orElse: () => 
        SecurityAlert(
          id: '',
          type: SecurityAlertType.info,
          severity: SecuritySeverity.low,
          message: '',
          details: {},
          timestamp: DateTime.now(),
          acknowledged: false,
        ));
      
      alert.acknowledged = true;
      await _saveSecurityData();
      
      _eventController.add(SecurityEvent(
        type: SecurityEventType.alert_acknowledged,
        message: 'Security alert acknowledged: $alertId',
        data: {'alertId': alertId},
      ));
      
    } catch (e) {
      debugPrint('Failed to acknowledge alert: $e');
    }
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isMonitoring': _isMonitoring,
      'totalPolicies': _policies.length,
      'enabledPolicies': _policies.values.where((p) => p.enabled).length,
      'totalAlerts': _alerts.length,
      'unacknowledgedAlerts': _alerts.where((a) => !a.acknowledged).length,
      'monitoredFiles': _fileIntegrity.length,
      'totalIncidents': _incidents.length,
      'unresolvedIncidents': _incidents.where((i) => !i.resolved).length,
    };
  }
  
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _integrityCheckTimer?.cancel();
    _policyCheckTimer?.cancel();
    
    await _saveSecurityData();
    
    _eventController.close();
    debugPrint('🔒 Security Monitoring System disposed');
  }
}

// Data models
class SecurityPolicy {
  final String id;
  final String name;
  final String description;
  final PolicyType type;
  final bool enabled;
  final SecuritySeverity severity;
  final List<SecurityRule> rules;
  
  SecurityPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.enabled,
    required this.severity,
    required this.rules,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'enabled': enabled,
    'severity': severity.name,
    'rules': rules.map((r) => r.toJson()).toList(),
  };
  
  factory SecurityPolicy.fromJson(Map<String, dynamic> json) => SecurityPolicy(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    type: PolicyType.values.firstWhere((t) => t.name == json['type'], orElse: () => PolicyType.file_access),
    enabled: json['enabled'] ?? true,
    severity: SecuritySeverity.values.firstWhere((s) => s.name == json['severity'], orElse: () => SecuritySeverity.medium),
    rules: (json['rules'] as List<dynamic>?)
        ?.map((r) => SecurityRule.fromJson(r))
        .toList() ?? [],
  );
}

class SecurityRule {
  final String id;
  final String description;
  final String condition;
  final String action;
  final bool enabled;
  
  SecurityRule({
    required this.id,
    required this.description,
    required this.condition,
    required this.action,
    required this.enabled,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'condition': condition,
    'action': action,
    'enabled': enabled,
  };
  
  factory SecurityRule.fromJson(Map<String, dynamic> json) => SecurityRule(
    id: json['id'],
    description: json['description'],
    condition: json['condition'],
    action: json['action'],
    enabled: json['enabled'] ?? true,
  );
}

class SecurityAlert {
  final String id;
  final SecurityAlertType type;
  final SecuritySeverity severity;
  final String message;
  final Map<String, dynamic> details;
  final DateTime timestamp;
  final bool acknowledged;
  
  SecurityAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.details,
    required this.timestamp,
    required this.acknowledged,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'severity': severity.name,
    'message': message,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
    'acknowledged': acknowledged,
  };
  
  factory SecurityAlert.fromJson(Map<String, dynamic> json) => SecurityAlert(
    id: json['id'],
    type: SecurityAlertType.values.firstWhere((t) => t.name == json['type'], orElse: () => SecurityAlertType.info),
    severity: SecuritySeverity.values.firstWhere((s) => s.name == json['severity'], orElse: () => SecuritySeverity.low),
    message: json['message'],
    details: json['details'] ?? {},
    timestamp: DateTime.parse(json['timestamp']),
    acknowledged: json['acknowledged'] ?? false,
  );
}

class FileIntegrity {
  final String path;
  final String hash;
  final DateTime lastModified;
  final int size;
  final int permissions;
  final bool monitored;
  final DateTime lastCheck;
  
  FileIntegrity({
    required this.path,
    required this.hash,
    required this.lastModified,
    required this.size,
    required this.permissions,
    required this.monitored,
    required this.lastCheck,
  });
  
  Map<String, dynamic> toJson() => {
    'path': path,
    'hash': hash,
    'lastModified': lastModified.toIso8601String(),
    'size': size,
    'permissions': permissions,
    'monitored': monitored,
    'lastCheck': lastCheck.toIso8601String(),
  };
  
  factory FileIntegrity.fromJson(Map<String, dynamic> json) => FileIntegrity(
    path: json['path'],
    hash: json['hash'],
    lastModified: DateTime.parse(json['lastModified']),
    size: json['size'] ?? 0,
    permissions: json['permissions'] ?? 0,
    monitored: json['monitored'] ?? true,
    lastCheck: DateTime.parse(json['lastCheck']),
  );
}

class SecurityMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final SecurityCategory category;
  
  SecurityMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
    required this.category,
  });
}

class SecurityIncident {
  final String id;
  final String category;
  final SecuritySeverity severity;
  final String description;
  final Map<String, dynamic> details;
  final DateTime timestamp;
  final bool resolved;
  
  SecurityIncident({
    required this.id,
    required this.category,
    required this.severity,
    required this.description,
    required this.details,
    required this.timestamp,
    required this.resolved,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'severity': severity.name,
    'description': description,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
    'resolved': resolved,
  };
  
  factory SecurityIncident.fromJson(Map<String, dynamic> json) => SecurityIncident(
    id: json['id'],
    category: json['category'],
    severity: SecuritySeverity.values.firstWhere((s) => s.name == json['severity'], orElse: () => SecuritySeverity.medium),
    description: json['description'],
    details: json['details'] ?? {},
    timestamp: DateTime.parse(json['timestamp']),
    resolved: json['resolved'] ?? false,
  );
}

enum PolicyType {
  file_access,
  network,
  process,
  integrity,
}

enum SecuritySeverity {
  low,
  medium,
  high,
  critical,
}

enum SecurityAlertType {
  info,
  warning,
  suspicious_activity,
  policy_violation,
  integrity_violation,
  intrusion_detected,
}

enum SecurityCategory {
  network,
  process,
  authentication,
  file_access,
}

enum SecurityEventType {
  initialized,
  alert_created,
  alert_acknowledged,
  incident_logged,
  resource_throttled,
  error,
}

class SecurityEvent {
  final SecurityEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  SecurityEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
