import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Advanced network optimizer with intelligent bandwidth management
/// 
/// Features:
/// - Adaptive bandwidth allocation
/// - Network quality monitoring
/// - Connection optimization
/// - Traffic prioritization
/// - Predictive network caching
class AdvancedNetworkOptimizer {
  final StreamController<NetworkEvent> _eventController = StreamController<NetworkEvent>.broadcast();
  
  final Map<String, NetworkConnection> _connections = {};
  final Map<String, NetworkMetric> _metrics = {};
  final Map<String, NetworkPolicy> _policies = {};
  final Map<String, NetworkCache> _caches = {};
  final List<NetworkOptimization> _optimizations = [];
  
  Timer? _monitoringTimer;
  Timer? _optimizationTimer;
  Timer? _cacheCleanupTimer;
  bool _isInitialized = false;
  bool _isOptimizing = false;
  late SharedPreferences _prefs;
  
  Stream<NetworkEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isOptimizing => _isOptimizing;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load network data
      await _loadNetworkData();
      
      // Initialize network policies
      _initializeNetworkPolicies();
      
      // Start monitoring
      _startNetworkMonitoring();
      
      // Start optimization
      _startNetworkOptimization();
      
      // Start cache cleanup
      _startCacheCleanup();
      
      _isInitialized = true;
      
      _eventController.add(NetworkEvent(
        type: NetworkEventType.initialized,
        message: 'Advanced network optimizer initialized',
        data: {
          'policies': _policies.length,
          'connections': _connections.length,
        },
      ));
      
      debugPrint('🌐 Advanced Network Optimizer initialized');
    } catch (e) {
      debugPrint('Failed to initialize advanced network optimizer: $e');
    }
  }
  
  Future<void> _loadNetworkData() async {
    try {
      final policiesJson = _prefs.getString('network_policies');
      if (policiesJson != null) {
        final policiesMap = jsonDecode(policiesJson);
        _policies = policiesMap.map((key, value) => 
          MapEntry(key, NetworkPolicy.fromJson(value)));
      }
      
      final cachesJson = _prefs.getString('network_caches');
      if (cachesJson != null) {
        final cachesMap = jsonDecode(cachesJson);
        _caches = cachesMap.map((key, value) => 
          MapEntry(key, NetworkCache.fromJson(value)));
      }
      
      final optimizationsJson = _prefs.getString('network_optimizations');
      if (optimizationsJson != null) {
        final optimizationsList = jsonDecode(optimizationsJson);
        _optimizations = optimizationsList.map((item) => 
          NetworkOptimization.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load network data: $e');
    }
  }
  
  void _initializeNetworkPolicies() {
    // Priority traffic policy
    _policies['priority_traffic'] = NetworkPolicy(
      id: 'priority_traffic',
      name: 'Priority Traffic',
      description: 'Prioritize critical network traffic',
      type: PolicyType.traffic_shaping,
      enabled: true,
      rules: [
        NetworkRule(
          id: 'ssh_priority',
          description: 'Prioritize SSH traffic',
          condition: 'port IN [22, 2222]',
          action: 'priority_high',
          enabled: true,
        ),
        NetworkRule(
          id: 'http_priority',
          description: 'Prioritize HTTP traffic',
          condition: 'port IN [80, 443]',
          action: 'priority_medium',
          enabled: true,
        ),
      ],
    );
    
    // Bandwidth allocation policy
    _policies['bandwidth_allocation'] = NetworkPolicy(
      id: 'bandwidth_allocation',
      name: 'Bandwidth Allocation',
      description: 'Optimize bandwidth allocation',
      type: PolicyType.bandwidth_management,
      enabled: true,
      rules: [
        NetworkRule(
          id: 'limit_downloads',
          description: 'Limit download bandwidth',
          condition: 'protocol IN [ftp, torrent]',
          action: 'limit_bandwidth_50',
          enabled: true,
        ),
        NetworkRule(
          id: 'boost_uploads',
          description: 'Boost upload bandwidth',
          condition: 'direction = upload AND protocol IN [ssh, scp]',
          action: 'boost_bandwidth_20',
          enabled: true,
        ),
      ],
    );
    
    // Quality of service policy
    _policies['quality_of_service'] = NetworkPolicy(
      id: 'quality_of_service',
      name: 'Quality of Service',
      description: 'Ensure quality of service for critical applications',
      type: PolicyType.quality_of_service,
      enabled: true,
      rules: [
        NetworkRule(
          id: 'low_latency_apps',
          description: 'Ensure low latency for real-time apps',
          condition: 'application IN [voip, gaming, remote_desktop]',
          action: 'low_latency',
          enabled: true,
        ),
      ],
    );
  }
  
  void _startNetworkMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _collectNetworkMetrics();
    });
  }
  
  void _startNetworkOptimization() {
    _optimizationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _performNetworkOptimization();
    });
  }
  
  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _cleanupNetworkCache();
    });
  }
  
  Future<void> _collectNetworkMetrics() async {
    try {
      final timestamp = DateTime.now();
      
      // Network interface metrics
      final interfaces = await _getNetworkInterfaces();
      for (final interface in interfaces) {
        final metrics = await _getInterfaceMetrics(interface);
        
        _metrics['interface_${interface}_rx_${timestamp.millisecondsSinceEpoch}'] = NetworkMetric(
          name: 'interface_rx',
          value: metrics.rxBytes,
          timestamp: timestamp,
          unit: 'bytes',
          category: NetworkCategory.traffic,
          interface: interface,
        );
        
        _metrics['interface_${interface}_tx_${timestamp.millisecondsSinceEpoch}'] = NetworkMetric(
          name: 'interface_tx',
          value: metrics.txBytes,
          timestamp: timestamp,
          unit: 'bytes',
          category: NetworkCategory.traffic,
          interface: interface,
        );
        
        _metrics['interface_${interface}_latency_${timestamp.millisecondsSinceEpoch}'] = NetworkMetric(
          name: 'interface_latency',
          value: metrics.latency,
          timestamp: timestamp,
          unit: 'ms',
          category: NetworkCategory.quality,
          interface: interface,
        );
      }
      
      // Connection metrics
      final connections = await _getActiveConnections();
      for (final connection in connections) {
        _connections[connection.id] = connection;
      }
      
      // Keep only last 500 metrics
      if (_metrics.length > 500) {
        final keys = _metrics.keys.toList()..sort();
        final toRemove = keys.take(_metrics.length - 500);
        for (final key in toRemove) {
          _metrics.remove(key);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to collect network metrics: $e');
    }
  }
  
  Future<void> _performNetworkOptimization() async {
    if (_isOptimizing) return;
    
    try {
      _isOptimizing = true;
      
      // Analyze network quality
      final quality = await _analyzeNetworkQuality();
      
      // Apply policies based on quality
      await _applyNetworkPolicies(quality);
      
      // Optimize connections
      await _optimizeConnections();
      
      // Update routing tables if needed
      await _optimizeRouting();
      
      _eventController.add(NetworkEvent(
        type: NetworkEventType.optimization_completed,
        message: 'Network optimization completed',
        data: {
          'quality': quality.toJson(),
          'connections': _connections.length,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to perform network optimization: $e');
    } finally {
      _isOptimizing = false;
    }
  }
  
  Future<NetworkQuality> _analyzeNetworkQuality() async {
    try {
      final interfaces = await _getNetworkInterfaces();
      double totalLatency = 0.0;
      double totalPacketLoss = 0.0;
      double totalBandwidth = 0.0;
      int interfaceCount = 0;
      
      for (final interface in interfaces) {
        final metrics = await _getInterfaceMetrics(interface);
        totalLatency += metrics.latency;
        totalPacketLoss += metrics.packetLoss;
        totalBandwidth += metrics.bandwidth;
        interfaceCount++;
      }
      
      final avgLatency = interfaceCount > 0 ? totalLatency / interfaceCount : 0.0;
      final avgPacketLoss = interfaceCount > 0 ? totalPacketLoss / interfaceCount : 0.0;
      final avgBandwidth = interfaceCount > 0 ? totalBandwidth / interfaceCount : 0.0;
      
      // Determine quality level
      NetworkQualityLevel level;
      if (avgLatency < 50 && avgPacketLoss < 1.0) {
        level = NetworkQualityLevel.excellent;
      } else if (avgLatency < 100 && avgPacketLoss < 3.0) {
        level = NetworkQualityLevel.good;
      } else if (avgLatency < 200 && avgPacketLoss < 5.0) {
        level = NetworkQualityLevel.fair;
      } else {
        level = NetworkQualityLevel.poor;
      }
      
      return NetworkQuality(
        level: level,
        latency: avgLatency,
        packetLoss: avgPacketLoss,
        bandwidth: avgBandwidth,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Failed to analyze network quality: $e');
      return NetworkQuality(
        level: NetworkQualityLevel.unknown,
        latency: 0.0,
        packetLoss: 0.0,
        bandwidth: 0.0,
        timestamp: DateTime.now(),
      );
    }
  }
  
  Future<void> _applyNetworkPolicies(NetworkQuality quality) async {
    try {
      for (final policy in _policies.values) {
        if (!policy.enabled) continue;
        
        for (final rule in policy.rules) {
          if (!rule.enabled) continue;
          
          await _applyNetworkRule(rule, quality);
        }
      }
    } catch (e) {
      debugPrint('Failed to apply network policies: $e');
    }
  }
  
  Future<void> _applyNetworkRule(NetworkRule rule, NetworkQuality quality) async {
    try {
      switch (rule.action) {
        case 'priority_high':
          await _setTrafficPriority('high', rule);
          break;
        case 'priority_medium':
          await _setTrafficPriority('medium', rule);
          break;
        case 'limit_bandwidth_50':
          await _limitBandwidth(50, rule);
          break;
        case 'boost_bandwidth_20':
          await _boostBandwidth(20, rule);
          break;
        case 'low_latency':
          await _setLowLatency(rule);
          break;
      }
      
      _eventController.add(NetworkEvent(
        type: NetworkEventType.policy_applied,
        message: 'Network policy applied: ${rule.description}',
        data: {
          'ruleId': rule.id,
          'action': rule.action,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to apply network rule: $e');
    }
  }
  
  Future<void> _optimizeConnections() async {
    try {
      for (final connection in _connections.values) {
        if (connection.state == ConnectionState.active) {
          await _optimizeConnection(connection);
        }
      }
    } catch (e) {
      debugPrint('Failed to optimize connections: $e');
    }
  }
  
  Future<void> _optimizeRouting() async {
    try {
      // Optimize routing based on current network conditions
      final result = await run('ip', ['route', 'show']);
      final routes = result.stdout.split('\n');
      
      for (final route in routes) {
        if (route.contains('default')) {
          // Analyze default route and suggest optimizations
          await _analyzeRoute(route);
        }
      }
    } catch (e) {
      debugPrint('Failed to optimize routing: $e');
    }
  }
  
  Future<void> _cleanupNetworkCache() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      
      _caches.removeWhere((key, cache) => 
          cache.lastAccessed.isBefore(cutoff));
      
      await _saveNetworkData();
    } catch (e) {
      debugPrint('Failed to cleanup network cache: $e');
    }
  }
  
  Future<List<String>> _getNetworkInterfaces() async {
    try {
      final result = await run('ip', ['link', 'show']);
      final lines = result.stdout.split('\n');
      
      final interfaces = <String>[];
      for (final line in lines) {
        if (line.contains('state UP')) {
          final match = RegExp(r'\d+: (\w+):').firstMatch(line);
          if (match != null) {
            interfaces.add(match.group(1)!);
          }
        }
      }
      
      return interfaces;
    } catch (e) {
      return ['eth0', 'wlan0']; // Fallback
    }
  }
  
  Future<InterfaceMetrics> _getInterfaceMetrics(String interface) async {
    try {
      // Get interface statistics
      final result = await run('cat', ['/proc/net/dev']);
      final lines = result.stdout.split('\n');
      
      double rxBytes = 0.0;
      double txBytes = 0.0;
      
      for (final line in lines) {
        if (line.contains(':$interface')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 9) {
            rxBytes = double.tryParse(parts[1]) ?? 0.0;
            txBytes = double.tryParse(parts[9]) ?? 0.0;
            break;
          }
        }
      }
      
      // Measure latency
      final latency = await _measureLatency(interface);
      
      // Calculate packet loss
      final packetLoss = await _measurePacketLoss(interface);
      
      // Calculate bandwidth
      final bandwidth = await _measureBandwidth(interface);
      
      return InterfaceMetrics(
        interface: interface,
        rxBytes: rxBytes,
        txBytes: txBytes,
        latency: latency,
        packetLoss: packetLoss,
        bandwidth: bandwidth,
      );
    } catch (e) {
      return InterfaceMetrics(
        interface: interface,
        rxBytes: 0.0,
        txBytes: 0.0,
        latency: 0.0,
        packetLoss: 0.0,
        bandwidth: 0.0,
      );
    }
  }
  
  Future<double> _measureLatency(String interface) async {
    try {
      final result = await run('ping', ['-c', '1', '-I', interface, '8.8.8.8']);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.contains('time=')) {
          final match = RegExp(r'time=(\d+\.\d+)').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      return 100.0; // Fallback high latency
    }
  }
  
  Future<double> _measurePacketLoss(String interface) async {
    try {
      final result = await run('ping', ['-c', '10', '-I', interface, '8.8.8.8']);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.contains('packet loss')) {
          final match = RegExp(r'(\d+)% packet loss').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      return 5.0; // Fallback packet loss
    }
  }
  
  Future<double> _measureBandwidth(String interface) async {
    try {
      // Simple bandwidth measurement
      final startMetrics = await _getInterfaceMetrics(interface);
      await Future.delayed(const Duration(seconds: 1));
      final endMetrics = await _getInterfaceMetrics(interface);
      
      final bandwidth = (endMetrics.rxBytes - startMetrics.rxBytes) * 8; // Convert to bits
      
      return bandwidth / 1024 / 1024; // Convert to Mbps
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<List<NetworkConnection>> _getActiveConnections() async {
    try {
      final result = await run('netstat', ['-tuln']);
      final lines = result.stdout.split('\n');
      
      final connections = <NetworkConnection>[];
      for (final line in lines) {
        if (line.contains('LISTEN') || line.contains('ESTABLISHED')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final protocol = parts[0];
            final localAddress = parts[3];
            final foreignAddress = parts[4];
            final state = parts.length > 4 ? parts[5] : '';
            
            connections.add(NetworkConnection(
              id: 'conn_${DateTime.now().millisecondsSinceEpoch}',
              protocol: protocol,
              localAddress: localAddress,
              foreignAddress: foreignAddress,
              state: state.contains('LISTEN') ? ConnectionState.listening : ConnectionState.active,
              timestamp: DateTime.now(),
            ));
          }
        }
      }
      
      return connections;
    } catch (e) {
      return [];
    }
  }
  
  Future<void> _setTrafficPriority(String priority, NetworkRule rule) async {
    try {
      // Use tc (traffic control) to set priority
      await run('tc', ['qdisc', 'add', 'dev', 'eth0', 'root', 'handle', '1:', 'prio']);
      await run('tc', ['filter', 'add', 'dev', 'eth0', 'protocol', 'ip', 'parent', '1:0', 'prio', '1', 'u32', 'match', 'ip', 'dport', '22', '0xffff', 'flowid', '1:1']);
    } catch (e) {
      debugPrint('Failed to set traffic priority: $e');
    }
  }
  
  Future<void> _limitBandwidth(int percentage, NetworkRule rule) async {
    try {
      // Use tc to limit bandwidth
      await run('tc', ['qdisc', 'add', 'dev', 'eth0', 'root', 'handle', '1:', 'htb']);
      await run('tc', ['class', 'add', 'dev', 'eth0', 'parent', '1:', 'classid', '1:1', 'htb', 'rate', '${percentage}mbit']);
    } catch (e) {
      debugPrint('Failed to limit bandwidth: $e');
    }
  }
  
  Future<void> _boostBandwidth(int percentage, NetworkRule rule) async {
    try {
      // Use tc to boost bandwidth
      await run('tc', ['qdisc', 'add', 'dev', 'eth0', 'root', 'handle', '1:', 'htb']);
      await run('tc', ['class', 'add', 'dev', 'eth0', 'parent', '1:', 'classid', '1:1', 'htb', 'rate', '${100 + percentage}mbit']);
    } catch (e) {
      debugPrint('Failed to boost bandwidth: $e');
    }
  }
  
  Future<void> _setLowLatency(NetworkRule rule) async {
    try {
      // Use tc to set low latency
      await run('tc', ['qdisc', 'add', 'dev', 'eth0', 'root', 'handle', '1:', 'fq_codel']);
    } catch (e) {
      debugPrint('Failed to set low latency: $e');
    }
  }
  
  Future<void> _optimizeConnection(NetworkConnection connection) async {
    try {
      // Optimize TCP settings for the connection
      await run('sysctl', ['-w', 'net.ipv4.tcp_window_scaling=1']);
      await run('sysctl', ['-w', 'net.ipv4.tcp_timestamps=1']);
      await run('sysctl', ['-w', 'net.ipv4.tcp_sack=1']);
    } catch (e) {
      debugPrint('Failed to optimize connection: $e');
    }
  }
  
  Future<void> _analyzeRoute(String route) async {
    try {
      // Analyze route and suggest optimizations
      final parts = route.split(' ');
      if (parts.length >= 3) {
        final gateway = parts[2];
        
        // Check gateway latency
        final latency = await _measureGatewayLatency(gateway);
        
        if (latency > 100) {
          _eventController.add(NetworkEvent(
            type: NetworkEventType.route_optimization_suggested,
            message: 'High latency detected on gateway: $gateway',
            data: {
              'gateway': gateway,
              'latency': latency,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('Failed to analyze route: $e');
    }
  }
  
  Future<double> _measureGatewayLatency(String gateway) async {
    try {
      final result = await run('ping', ['-c', '1', gateway]);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.contains('time=')) {
          final match = RegExp(r'time=(\d+\.\d+)').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      return 200.0; // Fallback high latency
    }
  }
  
  Future<void> _saveNetworkData() async {
    try {
      final policiesMap = _policies.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('network_policies', jsonEncode(policiesMap));
      
      final cachesMap = _caches.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('network_caches', jsonEncode(cachesMap));
      
      final optimizationsList = _optimizations.take(50).map((item) => item.toJson()).toList();
      await _prefs.setString('network_optimizations', jsonEncode(optimizationsList));
    } catch (e) {
      debugPrint('Failed to save network data: $e');
    }
  }
  
  Future<void> addNetworkPolicy({
    required String name,
    required String description,
    required PolicyType type,
    required List<NetworkRule> rules,
    bool enabled = true,
  }) async {
    final policyId = 'policy_${DateTime.now().millisecondsSinceEpoch}';
    
    final policy = NetworkPolicy(
      id: policyId,
      name: name,
      description: description,
      type: type,
      enabled: enabled,
      rules: rules,
    );
    
    _policies[policyId] = policy;
    await _saveNetworkData();
    
    _eventController.add(NetworkEvent(
      type: NetworkEventType.policy_added,
      message: 'Network policy added: $name',
      data: {'policyId': policyId},
    ));
  }
  
  Future<void> addNetworkCache({
    required String key,
    required String data,
    Duration? ttl,
  }) async {
    _caches[key] = NetworkCache(
      key: key,
      data: data,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      ttl: ttl ?? const Duration(hours: 1),
    );
    
    await _saveNetworkData();
  }
  
  String? getNetworkCache(String key) {
    final cache = _caches[key];
    if (cache != null) {
      if (DateTime.now().difference(cache.createdAt) < cache.ttl) {
        cache.lastAccessed = DateTime.now();
        return cache.data;
      } else {
        _caches.remove(key);
      }
    }
    return null;
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isOptimizing': _isOptimizing,
      'totalPolicies': _policies.length,
      'enabledPolicies': _policies.values.where((p) => p.enabled).length,
      'totalConnections': _connections.length,
      'activeConnections': _connections.values.where((c) => c.state == ConnectionState.active).length,
      'totalCaches': _caches.length,
      'totalOptimizations': _optimizations.length,
    };
  }
  
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _optimizationTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    
    await _saveNetworkData();
    
    _eventController.close();
    debugPrint('🌐 Advanced Network Optimizer disposed');
  }
}

// Data models
class NetworkPolicy {
  final String id;
  final String name;
  final String description;
  final PolicyType type;
  final bool enabled;
  final List<NetworkRule> rules;
  
  NetworkPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.enabled,
    required this.rules,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'enabled': enabled,
    'rules': rules.map((r) => r.toJson()).toList(),
  };
  
  factory NetworkPolicy.fromJson(Map<String, dynamic> json) => NetworkPolicy(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    type: PolicyType.values.firstWhere((t) => t.name == json['type'], orElse: () => PolicyType.traffic_shaping),
    enabled: json['enabled'] ?? true,
    rules: (json['rules'] as List<dynamic>?)
        ?.map((r) => NetworkRule.fromJson(r))
        .toList() ?? [],
  );
}

class NetworkRule {
  final String id;
  final String description;
  final String condition;
  final String action;
  final bool enabled;
  
  NetworkRule({
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
  
  factory NetworkRule.fromJson(Map<String, dynamic> json) => NetworkRule(
    id: json['id'],
    description: json['description'],
    condition: json['condition'],
    action: json['action'],
    enabled: json['enabled'] ?? true,
  );
}

class NetworkConnection {
  final String id;
  final String protocol;
  final String localAddress;
  final String foreignAddress;
  final ConnectionState state;
  final DateTime timestamp;
  
  NetworkConnection({
    required this.id,
    required this.protocol,
    required this.localAddress,
    required this.foreignAddress,
    required this.state,
    required this.timestamp,
  });
}

class NetworkMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final NetworkCategory category;
  final String? interface;
  
  NetworkMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
    required this.category,
    this.interface,
  });
}

class NetworkCache {
  final String key;
  final String data;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final Duration ttl;
  
  NetworkCache({
    required this.key,
    required this.data,
    required this.createdAt,
    required this.lastAccessed,
    required this.ttl,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'lastAccessed': lastAccessed.toIso8601String(),
    'ttl': ttl.inSeconds,
  };
  
  factory NetworkCache.fromJson(Map<String, dynamic> json) => NetworkCache(
    key: json['key'],
    data: json['data'],
    createdAt: DateTime.parse(json['createdAt']),
    lastAccessed: DateTime.parse(json['lastAccessed']),
    ttl: Duration(seconds: json['ttl'] ?? 3600),
  );
}

class NetworkOptimization {
  final String id;
  final String type;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> details;
  
  NetworkOptimization({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.details,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };
  
  factory NetworkOptimization.fromJson(Map<String, dynamic> json) => NetworkOptimization(
    id: json['id'],
    type: json['type'],
    description: json['description'],
    timestamp: DateTime.parse(json['timestamp']),
    details: json['details'] ?? {},
  );
}

class NetworkQuality {
  final NetworkQualityLevel level;
  final double latency;
  final double packetLoss;
  final double bandwidth;
  final DateTime timestamp;
  
  NetworkQuality({
    required this.level,
    required this.latency,
    required this.packetLoss,
    required this.bandwidth,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'level': level.name,
    'latency': latency,
    'packetLoss': packetLoss,
    'bandwidth': bandwidth,
    'timestamp': timestamp.toIso8601String(),
  };
}

class InterfaceMetrics {
  final String interface;
  final double rxBytes;
  final double txBytes;
  final double latency;
  final double packetLoss;
  final double bandwidth;
  
  InterfaceMetrics({
    required this.interface,
    required this.rxBytes,
    required this.txBytes,
    required this.latency,
    required this.packetLoss,
    required this.bandwidth,
  });
}

enum PolicyType {
  traffic_shaping,
  bandwidth_management,
  quality_of_service,
  security,
}

enum ConnectionState {
  active,
  listening,
  established,
  closed,
}

enum NetworkCategory {
  traffic,
  quality,
  security,
  performance,
}

enum NetworkQualityLevel {
  excellent,
  good,
  fair,
  poor,
  unknown,
}

enum NetworkEventType {
  initialized,
  policy_added,
  policy_applied,
  optimization_completed,
  route_optimization_suggested,
  error,
}

class NetworkEvent {
  final NetworkEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  NetworkEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
