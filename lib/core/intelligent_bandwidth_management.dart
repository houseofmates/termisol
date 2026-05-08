import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Intelligent bandwidth management system
/// 
/// Features:
/// - Real-time bandwidth monitoring and allocation
/// - Adaptive bandwidth throttling based on network conditions
/// - Quality of Service (QoS) prioritization
/// - Bandwidth usage prediction and optimization
/// - Network congestion detection and avoidance
/// - Multi-connection bandwidth balancing
class IntelligentBandwidthManagement {
  static const double _defaultMaxBandwidth = 100.0; // Mbps
  static const Duration _monitoringInterval = Duration(seconds: 1);
  static const Duration _throttlingInterval = Duration(milliseconds: 100);
  static const int _maxHistorySize = 300; // 5 minutes at 1-second intervals
  static const double _congestionThreshold = 0.8; // 80% utilization
  
  final Map<String, BandwidthAllocation> _allocations = {};
  final Queue<BandwidthSnapshot> _history = Queue();
  final List<NetworkInterface> _interfaces = [];
  final Map<String, QoSPolicy> _qosPolicies = {};
  
  Timer? _monitoringTimer;
  Timer? _throttlingTimer;
  
  double _currentBandwidth = _defaultMaxBandwidth;
  double _availableBandwidth = _defaultMaxBandwidth;
  double _utilizedBandwidth = 0.0;
  bool _isCongested = false;
  
  int _totalTransfers = 0;
  double _totalBytesTransferred = 0.0;
  int _throttledTransfers = 0;
  double _totalThrottlingTime = 0.0;

  IntelligentBandwidthManagement() {
    _initializeBandwidthManagement();
  }

  /// Initialize the bandwidth management system
  Future<void> _initializeBandwidthManagement() async {
    await _detectNetworkInterfaces();
    _setupQoSPolicies();
    _startMonitoring();
    _startThrottling();
  }

  /// Detect available network interfaces
  Future<void> _detectNetworkInterfaces() async {
    try {
      // This is a simplified implementation
      // In a real implementation, you would use platform-specific APIs
      _interfaces.add(NetworkInterface(
        name: 'eth0',
        type: InterfaceType.ethernet,
        maxBandwidth: 1000.0, // 1 Gbps
        currentBandwidth: 100.0,
        isActive: true,
      ));
      
      _interfaces.add(NetworkInterface(
        name: 'wlan0',
        type: InterfaceType.wifi,
        maxBandwidth: 100.0, // 100 Mbps
        currentBandwidth: 50.0,
        isActive: false,
      ));
    } catch (e) {
      debugPrint('Failed to detect network interfaces: $e');
    }
  }

  /// Setup QoS policies
  void _setupQoSPolicies() {
    _qosPolicies['critical'] = QoSPolicy(
      name: 'critical',
      priority: 1,
      minBandwidth: 10.0, // 10 Mbps minimum
      maxBandwidth: 100.0, // 100 Mbps maximum
      burstAllowance: 50.0, // 50 Mbps burst
    );
    
    _qosPolicies['high'] = QoSPolicy(
      name: 'high',
      priority: 2,
      minBandwidth: 5.0, // 5 Mbps minimum
      maxBandwidth: 50.0, // 50 Mbps maximum
      burstAllowance: 25.0, // 25 Mbps burst
    );
    
    _qosPolicies['normal'] = QoSPolicy(
      name: 'normal',
      priority: 3,
      minBandwidth: 1.0, // 1 Mbps minimum
      maxBandwidth: 20.0, // 20 Mbps maximum
      burstAllowance: 10.0, // 10 Mbps burst
    );
    
    _qosPolicies['low'] = QoSPolicy(
      name: 'low',
      priority: 4,
      minBandwidth: 0.5, // 0.5 Mbps minimum
      maxBandwidth: 5.0, // 5 Mbps maximum
      burstAllowance: 2.0, // 2 Mbps burst
    );
  }

  /// Start bandwidth monitoring
  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _performMonitoring();
    });
  }

  /// Start bandwidth throttling
  void _startThrottling() {
    _throttlingTimer = Timer.periodic(_throttlingInterval, (_) {
      _performThrottling();
    });
  }

  /// Perform bandwidth monitoring
  void _performMonitoring() {
    final snapshot = _collectBandwidthSnapshot();
    _history.add(snapshot);
    
    // Keep only recent history
    if (_history.length > _maxHistorySize) {
      _history.removeFirst();
    }
    
    // Update current metrics
    _updateMetrics(snapshot);
    
    // Check for congestion
    _checkCongestion(snapshot);
  }

  /// Collect bandwidth snapshot
  BandwidthSnapshot _collectBandwidthSnapshot() {
    final totalAllocated = _allocations.values
        .fold(0.0, (sum, allocation) => sum + allocation.allocatedBandwidth);
    
    final totalUsed = _allocations.values
        .fold(0.0, (sum, allocation) => sum + allocation.currentUsage);
    
    return BandwidthSnapshot(
      timestamp: DateTime.now(),
      totalBandwidth: _currentBandwidth,
      allocatedBandwidth: totalAllocated,
      usedBandwidth: totalUsed,
      availableBandwidth: _currentBandwidth - totalUsed,
      activeConnections: _allocations.length,
      isCongested: _isCongested,
    );
  }

  /// Update current metrics
  void _updateMetrics(BandwidthSnapshot snapshot) {
    _utilizedBandwidth = snapshot.usedBandwidth;
    _availableBandwidth = snapshot.availableBandwidth;
    
    // Adjust current bandwidth based on network conditions
    _adjustCurrentBandwidth(snapshot);
  }

  /// Adjust current bandwidth based on conditions
  void _adjustCurrentBandwidth(BandwidthSnapshot snapshot) {
    // Simple bandwidth adjustment logic
    final utilization = snapshot.usedBandwidth / snapshot.totalBandwidth;
    
    if (utilization > 0.9) {
      // High utilization, reduce available bandwidth
      _currentBandwidth = _defaultMaxBandwidth * 0.8;
    } else if (utilization < 0.5) {
      // Low utilization, increase available bandwidth
      _currentBandwidth = min(_defaultMaxBandwidth, _currentBandwidth * 1.1);
    }
  }

  /// Check for network congestion
  void _checkCongestion(BandwidthSnapshot snapshot) {
    final utilization = snapshot.usedBandwidth / snapshot.totalBandwidth;
    final wasCongested = _isCongested;
    _isCongested = utilization > _congestionThreshold;
    
    if (_isCongested && !wasCongested) {
      _handleCongestionStart();
    } else if (!_isCongested && wasCongested) {
      _handleCongestionEnd();
    }
  }

  /// Handle congestion start
  void _handleCongestionStart() {
    debugPrint('🚦 Network congestion detected');
    
    // Prioritize critical traffic
    _prioritizeCriticalTraffic();
    
    // Throttle low-priority traffic
    _throttleLowPriorityTraffic();
  }

  /// Handle congestion end
  void _handleCongestionEnd() {
    debugPrint('🚦 Network congestion cleared');
    
    // Restore normal bandwidth allocation
    _restoreNormalAllocation();
  }

  /// Prioritize critical traffic
  void _prioritizeCriticalTraffic() {
    for (final allocation in _allocations.values) {
      if (allocation.priority == 1) {
        allocation.allocatedBandwidth = allocation.policy.maxBandwidth;
      }
    }
  }

  /// Throttle low-priority traffic
  void _throttleLowPriorityTraffic() {
    for (final allocation in _allocations.values) {
      if (allocation.priority >= 3) {
        allocation.allocatedBandwidth = allocation.policy.minBandwidth;
      }
    }
  }

  /// Restore normal allocation
  void _restoreNormalAllocation() {
    for (final allocation in _allocations.values) {
      allocation.allocatedBandwidth = allocation.policy.maxBandwidth;
    }
  }

  /// Perform bandwidth throttling
  void _performThrottling() {
    final stopwatch = Stopwatch()..start();
    
    for (final allocation in _allocations.values) {
      if (allocation.currentUsage > allocation.allocatedBandwidth) {
        _throttleTransfer(allocation);
        _throttledTransfers++;
      }
    }
    
    _totalThrottlingTime += stopwatch.elapsedMilliseconds.toDouble();
    stopwatch.stop();
  }

  /// Throttle individual transfer
  void _throttleTransfer(BandwidthAllocation allocation) {
    // Calculate required delay
    final excessUsage = allocation.currentUsage - allocation.allocatedBandwidth;
    final delay = (excessUsage / allocation.allocatedBandwidth) * 1000; // milliseconds
    
    // Apply throttling delay
    allocation.throttlingDelay = delay.toInt();
  }

  /// Allocate bandwidth for a transfer
  String allocateBandwidth({
    required String transferId,
    required String priority,
    double? requestedBandwidth,
    Map<String, dynamic>? metadata,
  }) {
    final policy = _qosPolicies[priority];
    if (policy == null) {
      throw ArgumentError('Invalid priority: $priority');
    }
    
    final allocatedBandwidth = min(
      requestedBandwidth ?? policy.maxBandwidth,
      policy.maxBandwidth,
    );
    
    final allocation = BandwidthAllocation(
      id: transferId,
      priority: policy.priority,
      policy: policy,
      allocatedBandwidth: allocatedBandwidth,
      currentUsage: 0.0,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
      metadata: metadata ?? {},
    );
    
    _allocations[transferId] = allocation;
    _totalTransfers++;
    
    return transferId;
  }

  /// Update bandwidth usage for a transfer
  void updateUsage(String transferId, double currentUsage) {
    final allocation = _allocations[transferId];
    if (allocation != null) {
      allocation.currentUsage = currentUsage;
      allocation.lastUsed = DateTime.now();
      _totalBytesTransferred += currentUsage;
    }
  }

  /// Release bandwidth allocation
  void releaseBandwidth(String transferId) {
    _allocations.remove(transferId);
  }

  /// Get bandwidth allocation
  BandwidthAllocation? getAllocation(String transferId) {
    return _allocations[transferId];
  }

  /// Get current bandwidth statistics
  BandwidthStats getStats() {
    return BandwidthStats(
      totalBandwidth: _currentBandwidth,
      availableBandwidth: _availableBandwidth,
      utilizedBandwidth: _utilizedBandwidth,
      utilizationRate: _currentBandwidth > 0 ? _utilizedBandwidth / _currentBandwidth : 0.0,
      totalTransfers: _totalTransfers,
      activeTransfers: _allocations.length,
      throttledTransfers: _throttledTransfers,
      totalBytesTransferred: _totalBytesTransferred,
      averageThrottlingTime: _throttledTransfers > 0 ? _totalThrottlingTime / _throttledTransfers : 0.0,
      isCongested: _isCongested,
      interfaceCount: _interfaces.length,
      activeInterfaces: _interfaces.where((i) => i.isActive).length,
    );
  }

  /// Get bandwidth history
  List<BandwidthSnapshot> getHistory({Duration? duration}) {
    if (duration == null) return _history.toList();
    
    final cutoff = DateTime.now().subtract(duration);
    return _history.where((snapshot) => snapshot.timestamp.isAfter(cutoff)).toList();
  }

  /// Predict future bandwidth usage
  BandwidthPrediction predictUsage(Duration futureDuration) {
    if (_history.length < 10) {
      return BandwidthPrediction(
        predictedUsage: _utilizedBandwidth,
        confidence: 0.1,
        trend: UsageTrend.stable,
      );
    }
    
    // Simple linear regression for prediction
    final recentSnapshots = _history.take(30).toList(); // Last 30 seconds
    final usageValues = recentSnapshots.map((s) => s.usedBandwidth).toList();
    
    // Calculate trend
    final trend = _calculateTrend(usageValues);
    
    // Predict future usage
    final averageUsage = usageValues.reduce((a, b) => a + b) / usageValues.length;
    final predictedChange = trend * (futureDuration.inSeconds / 30.0);
    final predictedUsage = max(0.0, averageUsage + predictedChange);
    
    return BandwidthPrediction(
      predictedUsage: predictedUsage,
      confidence: _calculateConfidence(usageValues),
      trend: trend > 0.1 ? UsageTrend.increasing : trend < -0.1 ? UsageTrend.decreasing : UsageTrend.stable,
    );
  }

  /// Calculate usage trend
  double _calculateTrend(List<double> values) {
    if (values.length < 2) return 0.0;
    
    final firstHalf = values.take(values.length ~/ 2).toList();
    final secondHalf = values.skip(values.length ~/ 2).toList();
    
    final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    
    return secondAvg - firstAvg;
  }

  /// Calculate prediction confidence
  double _calculateConfidence(List<double> values) {
    if (values.length < 5) return 0.1;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    final standardDeviation = sqrt(variance);
    
    // Lower variance = higher confidence
    return max(0.1, 1.0 - (standardDeviation / mean));
  }

  /// Optimize bandwidth allocation
  Future<void> optimizeAllocation() async {
    // Reallocate bandwidth based on current usage and priorities
    final sortedAllocations = _allocations.values.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    
    double remainingBandwidth = _availableBandwidth;
    
    for (final allocation in sortedAllocations) {
      final optimalBandwidth = min(
        allocation.policy.maxBandwidth,
        remainingBandwidth,
      );
      
      allocation.allocatedBandwidth = max(
        allocation.policy.minBandwidth,
        optimalBandwidth,
      );
      
      remainingBandwidth -= allocation.allocatedBandwidth;
    }
  }

  /// Dispose bandwidth management system
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _throttlingTimer?.cancel();
    _allocations.clear();
    _history.clear();
    _interfaces.clear();
    _qosPolicies.clear();
  }
}

/// Bandwidth allocation
class BandwidthAllocation {
  final String id;
  final int priority;
  final QoSPolicy policy;
  double allocatedBandwidth;
  double currentUsage;
  final DateTime createdAt;
  DateTime lastUsed;
  final Map<String, dynamic> metadata;
  int throttlingDelay = 0;

  BandwidthAllocation({
    required this.id,
    required this.priority,
    required this.policy,
    required this.allocatedBandwidth,
    required this.currentUsage,
    required this.createdAt,
    required this.lastUsed,
    required this.metadata,
  });
}

/// Bandwidth snapshot
class BandwidthSnapshot {
  final DateTime timestamp;
  final double totalBandwidth;
  final double allocatedBandwidth;
  final double usedBandwidth;
  final double availableBandwidth;
  final int activeConnections;
  final bool isCongested;

  const BandwidthSnapshot({
    required this.timestamp,
    required this.totalBandwidth,
    required this.allocatedBandwidth,
    required this.usedBandwidth,
    required this.availableBandwidth,
    required this.activeConnections,
    required this.isCongested,
  });
}

/// QoS policy
class QoSPolicy {
  final String name;
  final int priority;
  final double minBandwidth;
  final double maxBandwidth;
  final double burstAllowance;

  const QoSPolicy({
    required this.name,
    required this.priority,
    required this.minBandwidth,
    required this.maxBandwidth,
    required this.burstAllowance,
  });
}

/// Network interface
class NetworkInterface {
  final String name;
  final InterfaceType type;
  final double maxBandwidth;
  double currentBandwidth;
  final bool isActive;

  NetworkInterface({
    required this.name,
    required this.type,
    required this.maxBandwidth,
    required this.currentBandwidth,
    required this.isActive,
  });
}

/// Bandwidth statistics
class BandwidthStats {
  final double totalBandwidth;
  final double availableBandwidth;
  final double utilizedBandwidth;
  final double utilizationRate;
  final int totalTransfers;
  final int activeTransfers;
  final int throttledTransfers;
  final double totalBytesTransferred;
  final double averageThrottlingTime;
  final bool isCongested;
  final int interfaceCount;
  final int activeInterfaces;

  const BandwidthStats({
    required this.totalBandwidth,
    required this.availableBandwidth,
    required this.utilizedBandwidth,
    required this.utilizationRate,
    required this.totalTransfers,
    required this.activeTransfers,
    required this.throttledTransfers,
    required this.totalBytesTransferred,
    required this.averageThrottlingTime,
    required this.isCongested,
    required this.interfaceCount,
    required this.activeInterfaces,
  });
}

/// Bandwidth prediction
class BandwidthPrediction {
  final double predictedUsage;
  final double confidence;
  final UsageTrend trend;

  const BandwidthPrediction({
    required this.predictedUsage,
    required this.confidence,
    required this.trend,
  });
}

/// Interface types
enum InterfaceType {
  ethernet,
  wifi,
  cellular,
  vpn,
}

/// Usage trends
enum UsageTrend {
  increasing,
  decreasing,
  stable,
}
