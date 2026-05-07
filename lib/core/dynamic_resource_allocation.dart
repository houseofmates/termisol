import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

class DynamicResourceAllocation {
  static const int _maxMemoryUsage = 1024 * 1024 * 1024; // 1GB
  static const int _maxCpuUsage = 80; // 80%
  static const int _maxGpuUsage = 90; // 90%
  static const int _monitoringInterval = 1000; // 1 second
  static const int _adjustmentThreshold = 10; // 10% change threshold
  
  final Map<String, ResourcePool> _resourcePools = {};
  final List<ResourceAllocation> _allocations = [];
  final Map<String, SystemMetrics> _systemMetrics = {};
  
  Timer? _monitoringTimer;
  ResourcePolicy _currentPolicy = ResourcePolicy.balanced;
  SystemLoad _currentLoad = SystemLoad();
  
  int _totalAllocated = 0;
  int _peakMemoryUsage = 0;
  double _averageCpuUsage = 0.0;
  double _averageGpuUsage = 0.0;
  
  final StreamController<ResourceEvent> _resourceController = 
      StreamController<ResourceEvent>.broadcast();

  void initialize() {
    _initializeResourcePools();
    _startMonitoring();
    developer.log('⚡ Dynamic Resource Allocation initialized');
  }

  void _initializeResourcePools() {
    _resourcePools['memory'] = ResourcePool(
      type: ResourceType.memory,
      totalCapacity: _maxMemoryUsage,
      allocatedCapacity: 0,
      peakUsage: 0,
      allocations: {},
    );
    
    _resourcePools['cpu'] = ResourcePool(
      type: ResourceType.cpu,
      totalCapacity: 100, // Percentage
      allocatedCapacity: 0,
      peakUsage: 0,
      allocations: {},
    );
    
    _resourcePools['gpu'] = ResourcePool(
      type: ResourceType.gpu,
      totalCapacity: 100, // Percentage
      allocatedCapacity: 0,
      peakUsage: 0,
      allocations: {},
    );
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(
      Duration(milliseconds: _monitoringInterval),
      (_) => _monitorSystemLoad(),
    );
  }

  Future<String> allocateResource({
    required ResourceType type,
    required int size,
    required String requesterId,
    int priority = 0,
    Map<String, dynamic>? metadata,
  }) async {
    final pool = _resourcePools[type.name];
    if (pool == null) {
      throw Exception('Unknown resource type: $type');
    }
    
    // Check if allocation is possible
    if (!_canAllocate(pool, size, priority)) {
      throw Exception('Insufficient resources for allocation: $type, size: $size');
    }
    
    final allocationId = _generateAllocationId();
    
    // Create allocation
    final allocation = ResourceAllocation(
      id: allocationId,
      type: type,
      size: size,
      requesterId: requesterId,
      priority: priority,
      metadata: metadata ?? {},
      allocatedAt: DateTime.now(),
      status: AllocationStatus.active,
    );
    
    // Update pool
    pool.allocatedCapacity += size;
    pool.peakUsage = max(pool.peakUsage, pool.allocatedCapacity);
    pool.allocations[allocationId] = allocation;
    
    _allocations.add(allocation);
    _totalAllocated += size;
    
    developer.log('⚡ Allocated resource: $type (${size} bytes) to $requesterId');
    
    _emitEvent(ResourceEvent(
      type: ResourceEventType.allocated,
      allocationId: allocationId,
      resourceType: type,
      size: size,
      requesterId: requesterId,
    ));
    
    return allocationId;
  }

  bool _canAllocate(ResourcePool pool, int size, int priority) {
    final availableCapacity = pool.totalCapacity - pool.allocatedCapacity;
    
    // High priority allocations can exceed limits temporarily
    if (priority >= 8) {
      return true;
    }
    
    // Normal allocation rules
    switch (_currentPolicy) {
      case ResourcePolicy.conservative:
        return availableCapacity >= size * 1.2; // 20% buffer
      case ResourcePolicy.balanced:
        return availableCapacity >= size;
      case ResourcePolicy.aggressive:
        return availableCapacity >= size * 0.8; // Allow 80% of available
      case ResourcePolicy.performance:
        return true; // Always allow, will adjust later
    }
  }

  Future<void> releaseResource(String allocationId) async {
    final allocation = _findAllocation(allocationId);
    if (allocation == null) {
      throw Exception('Allocation not found: $allocationId');
    }
    
    final pool = _resourcePools[allocation.type.name];
    if (pool == null) return;
    
    // Update allocation
    allocation.status = AllocationStatus.released;
    allocation.releasedAt = DateTime.now();
    
    // Update pool
    pool.allocatedCapacity -= allocation.size;
    pool.allocations.remove(allocationId);
    
    _totalAllocated -= allocation.size;
    
    developer.log('⚡ Released resource: ${allocation.type} (${allocation.size} bytes) from ${allocation.requesterId}');
    
    _emitEvent(ResourceEvent(
      type: ResourceEventType.released,
      allocationId: allocationId,
      resourceType: allocation.type,
      size: allocation.size,
      requesterId: allocation.requesterId,
    ));
    
    // Trigger rebalancing if needed
    _checkRebalancing();
  }

  ResourceAllocation? _findAllocation(String allocationId) {
    for (final allocation in _allocations) {
      if (allocation.id == allocationId) {
        return allocation;
      }
    }
    return null;
  }

  Future<void> _monitorSystemLoad() async {
    final metrics = await _collectSystemMetrics();
    
    // Update system load
    _currentLoad = SystemLoad(
      memoryUsage: metrics.memoryUsage,
      cpuUsage: metrics.cpuUsage,
      gpuUsage: metrics.gpuUsage,
      timestamp: DateTime.now(),
    );
    
    // Update averages
    _averageCpuUsage = (_averageCpuUsage * 0.9) + (metrics.cpuUsage * 0.1);
    _averageGpuUsage = (_averageGpuUsage * 0.9) + (metrics.gpuUsage * 0.1);
    _peakMemoryUsage = max(_peakMemoryUsage, metrics.memoryUsage);
    
    // Update resource pools
    _updateResourcePools(metrics);
    
    // Check for policy adjustments
    _checkPolicyAdjustment();
    
    // Emit metrics event
    _emitEvent(ResourceEvent(
      type: ResourceEventType.metricsUpdated,
      systemLoad: _currentLoad,
    ));
  }

  Future<SystemMetrics> _collectSystemMetrics() async {
    // Simulate system metrics collection
    // In practice, this would use system APIs
    
    final memoryUsage = await _getMemoryUsage();
    final cpuUsage = await _getCpuUsage();
    final gpuUsage = await _getGpuUsage();
    
    return SystemMetrics(
      memoryUsage: memoryUsage,
      cpuUsage: cpuUsage,
      gpuUsage: gpuUsage,
      timestamp: DateTime.now(),
    );
  }

  Future<int> _getMemoryUsage() async {
    // Simulate memory usage
    final baseUsage = _totalAllocated;
    final variance = (Random().nextDouble() - 0.5) * 100 * 1024 * 1024; // ±50MB variance
    return (baseUsage + variance).clamp(0, _maxMemoryUsage);
  }

  Future<double> _getCpuUsage() async {
    // Simulate CPU usage
    final baseUsage = _averageCpuUsage;
    final variance = (Random().nextDouble() - 0.5) * 20; // ±10% variance
    return (baseUsage + variance).clamp(0.0, 100.0);
  }

  Future<double> _getGpuUsage() async {
    // Simulate GPU usage
    final baseUsage = _averageGpuUsage;
    final variance = (Random().nextDouble() - 0.5) * 15; // ±7.5% variance
    return (baseUsage + variance).clamp(0.0, 100.0);
  }

  void _updateResourcePools(SystemMetrics metrics) {
    // Update memory pool
    final memoryPool = _resourcePools['memory']!;
    memoryPool.allocatedCapacity = metrics.memoryUsage;
    memoryPool.peakUsage = max(memoryPool.peakUsage, metrics.memoryUsage);
    
    // Update CPU pool
    final cpuPool = _resourcePools['cpu']!;
    cpuPool.allocatedCapacity = metrics.cpuUsage.round();
    cpuPool.peakUsage = max(cpuPool.peakUsage, metrics.cpuUsage.round());
    
    // Update GPU pool
    final gpuPool = _resourcePools['gpu']!;
    gpuPool.allocatedCapacity = metrics.gpuUsage.round();
    gpuPool.peakUsage = max(gpuPool.peakUsage, metrics.gpuUsage.round());
  }

  void _checkPolicyAdjustment() {
    ResourcePolicy newPolicy = _currentPolicy;
    
    // Adjust policy based on system load
    if (_currentLoad.memoryUsage > _maxMemoryUsage * 0.9) {
      newPolicy = ResourcePolicy.conservative;
    } else if (_currentLoad.cpuUsage > 80 || _currentLoad.gpuUsage > 85) {
      newPolicy = ResourcePolicy.balanced;
    } else if (_currentLoad.memoryUsage < _maxMemoryUsage * 0.5 && 
               _currentLoad.cpuUsage < 50 && 
               _currentLoad.gpuUsage < 50) {
      newPolicy = ResourcePolicy.aggressive;
    }
    
    if (newPolicy != _currentPolicy) {
      _currentPolicy = newPolicy;
      developer.log('⚡ Adjusted resource policy: ${newPolicy.name}');
      
      _emitEvent(ResourceEvent(
        type: ResourceEventType.policyChanged,
        oldPolicy: _currentPolicy,
        newPolicy: newPolicy,
      ));
    }
  }

  void _checkRebalancing() {
    // Check if any pool needs rebalancing
    for (final pool in _resourcePools.values) {
      if (_shouldRebalancePool(pool)) {
        _rebalancePool(pool);
      }
    }
  }

  bool _shouldRebalancePool(ResourcePool pool) {
    final usagePercentage = (pool.allocatedCapacity / pool.totalCapacity) * 100;
    
    // Rebalance if usage is consistently high
    return usagePercentage > 85;
  }

  Future<void> _rebalancePool(ResourcePool pool) async {
    developer.log('⚡ Rebalancing resource pool: ${pool.type.name}');
    
    // Find low-priority allocations to release
    final lowPriorityAllocations = pool.allocations.values
        .where((allocation) => allocation.priority < 5)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    
    // Release some allocations to free up space
    final toRelease = lowPriorityAllocations.take(5);
    for (final allocation in toRelease) {
      await releaseResource(allocation.id);
    }
    
    _emitEvent(ResourceEvent(
      type: ResourceEventType.rebalanced,
      resourceType: pool.type,
      releasedCount: toRelease.length,
    ));
  }

  void setPolicy(ResourcePolicy policy) {
    _currentPolicy = policy;
    developer.log('⚡ Set resource policy: ${policy.name}');
    
    _emitEvent(ResourceEvent(
      type: ResourceEventType.policyChanged,
      newPolicy: policy,
    ));
  }

  Future<String> reallocateResource({
    required String allocationId,
    required int newSize,
  }) async {
    final allocation = _findAllocation(allocationId);
    if (allocation == null) {
      throw Exception('Allocation not found: $allocationId');
    }
    
    // Release current allocation
    await releaseResource(allocationId);
    
    // Allocate new size
    return await allocateResource(
      type: allocation.type,
      size: newSize,
      requesterId: allocation.requesterId,
      priority: allocation.priority,
      metadata: allocation.metadata,
    );
  }

  ResourceAllocation? getAllocation(String allocationId) {
    return _findAllocation(allocationId);
  }

  List<ResourceAllocation> getAllocations({ResourceType? type, String? requesterId}) {
    var allocations = _allocations;
    
    if (type != null) {
      allocations = allocations.where((a) => a.type == type).toList();
    }
    
    if (requesterId != null) {
      allocations = allocations.where((a) => a.requesterId == requesterId).toList();
    }
    
    return allocations;
  }

  SystemLoad getCurrentLoad() {
    return _currentLoad;
  }

  ResourcePolicy getCurrentPolicy() {
    return _currentPolicy;
  }

  ResourcePool? getResourcePool(ResourceType type) {
    return _resourcePools[type.name];
  }

  Future<void> optimizeAllocations() async {
    // Analyze allocation patterns and optimize
    final allocationsByType = <ResourceType, List<ResourceAllocation>>{};
    
    for (final allocation in _allocations) {
      allocationsByType.putIfAbsent(
        allocation.type,
        () => <ResourceAllocation>[],
      ).add(allocation);
    }
    
    for (final entry in allocationsByType.entries) {
      final type = entry.key;
      final typeAllocations = entry.value;
      
      // Sort by priority (ascending)
      typeAllocations.sort((a, b) => a.priority.compareTo(b.priority));
      
      // Check for fragmentation
      final fragmentation = _calculateFragmentation(typeAllocations);
      
      if (fragmentation > 0.3) { // 30% fragmentation threshold
        await _defragmentAllocations(type, typeAllocations);
      }
    }
  }

  double _calculateFragmentation(List<ResourceAllocation> allocations) {
    if (allocations.isEmpty) return 0.0;
    
    // Simple fragmentation calculation based on allocation sizes
    final sizes = allocations.map((a) => a.size).toList();
    sizes.sort();
    
    final totalSize = sizes.reduce((a, b) => a + b);
    final averageSize = totalSize / sizes.length;
    
    // Calculate variance as fragmentation metric
    final variance = sizes
        .map((size) => pow(size - averageSize, 2))
        .reduce((a, b) => a + b) / sizes.length;
    
    return sqrt(variance) / averageSize;
  }

  Future<void> _defragmentAllocations(
    ResourceType type,
    List<ResourceAllocation> allocations,
  ) async {
    developer.log('⚡ Defragmenting allocations for: $type');
    
    // Release and reallocate in optimal order
    final sortedAllocations = List.from(allocations)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    
    for (final allocation in sortedAllocations) {
      await releaseResource(allocation.id);
      await allocateResource(
        type: allocation.type,
        size: allocation.size,
        requesterId: allocation.requesterId,
        priority: allocation.priority,
        metadata: allocation.metadata,
      );
    }
    
    _emitEvent(ResourceEvent(
      type: ResourceEventType.defragmented,
      resourceType: type,
      allocationCount: allocations.length,
    ));
  }

  String _generateAllocationId() {
    return 'alloc_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(ResourceEvent event) {
    _resourceController.add(event);
  }

  Stream<ResourceEvent> get resourceEventStream => _resourceController.stream;

  ResourceAllocationStats getStats() {
    return ResourceAllocationStats(
      totalAllocations: _totalAllocated,
      activeAllocations: _allocations.where((a) => a.status == AllocationStatus.active).length,
      peakMemoryUsage: _peakMemoryUsage,
      averageCpuUsage: _averageCpuUsage,
      averageGpuUsage: _averageGpuUsage,
      currentPolicy: _currentPolicy,
      resourcePools: _resourcePools.values.map((pool) => ResourcePoolInfo(
        type: pool.type,
        totalCapacity: pool.totalCapacity,
        allocatedCapacity: pool.allocatedCapacity,
        peakUsage: pool.peakUsage,
        allocationCount: pool.allocations.length,
      )).toList(),
    );
  }

  void dispose() {
    _monitoringTimer?.cancel();
    
    // Release all active allocations
    for (final allocation in _allocations.where((a) => a.status == AllocationStatus.active)) {
      releaseResource(allocation.id);
    }
    
    _resourcePools.clear();
    _allocations.clear();
    _systemMetrics.clear();
    _resourceController.close();
    
    developer.log('⚡ Dynamic Resource Allocation disposed');
  }
}

enum ResourceType {
  memory,
  cpu,
  gpu,
}

enum ResourcePolicy {
  conservative,
  balanced,
  aggressive,
  performance,
}

enum AllocationStatus {
  active,
  released,
  failed,
}

enum ResourceEventType {
  allocated,
  released,
  metricsUpdated,
  policyChanged,
  rebalanced,
  defragmented,
}

class ResourcePool {
  final ResourceType type;
  final int totalCapacity;
  int allocatedCapacity;
  int peakUsage;
  final Map<String, ResourceAllocation> allocations;

  ResourcePool({
    required this.type,
    required this.totalCapacity,
    required this.allocatedCapacity,
    required this.peakUsage,
    required this.allocations,
  });
}

class ResourceAllocation {
  final String id;
  final ResourceType type;
  final int size;
  final String requesterId;
  final int priority;
  final Map<String, dynamic> metadata;
  final DateTime allocatedAt;
  AllocationStatus status;
  DateTime? releasedAt;

  ResourceAllocation({
    required this.id,
    required this.type,
    required this.size,
    required this.requesterId,
    required this.priority,
    required this.metadata,
    required this.allocatedAt,
    required this.status,
    this.releasedAt,
  });
}

class SystemMetrics {
  final int memoryUsage;
  final double cpuUsage;
  final double gpuUsage;
  final DateTime timestamp;

  SystemMetrics({
    required this.memoryUsage,
    required this.cpuUsage,
    required this.gpuUsage,
    required this.timestamp,
  });
}

class SystemLoad {
  final int memoryUsage;
  final double cpuUsage;
  final double gpuUsage;
  final DateTime timestamp;

  SystemLoad({
    required this.memoryUsage,
    required this.cpuUsage,
    required this.gpuUsage,
    required this.timestamp,
  });
}

class ResourceEvent {
  final ResourceEventType type;
  final String? allocationId;
  final ResourceType? resourceType;
  final int? size;
  final String? requesterId;
  final SystemLoad? systemLoad;
  final ResourcePolicy? oldPolicy;
  final ResourcePolicy? newPolicy;
  final int? releasedCount;
  final int? allocationCount;

  ResourceEvent({
    required this.type,
    this.allocationId,
    this.resourceType,
    this.size,
    this.requesterId,
    this.systemLoad,
    this.oldPolicy,
    this.newPolicy,
    this.releasedCount,
    this.allocationCount,
  });
}

class ResourceAllocationStats {
  final int totalAllocations;
  final int activeAllocations;
  final int peakMemoryUsage;
  final double averageCpuUsage;
  final double averageGpuUsage;
  final ResourcePolicy currentPolicy;
  final List<ResourcePoolInfo> resourcePools;

  ResourceAllocationStats({
    required this.totalAllocations,
    required this.activeAllocations,
    required this.peakMemoryUsage,
    required this.averageCpuUsage,
    required this.averageGpuUsage,
    required this.currentPolicy,
    required this.resourcePools,
  });
}

class ResourcePoolInfo {
  final ResourceType type;
  final int totalCapacity;
  final int allocatedCapacity;
  final int peakUsage;
  final int allocationCount;

  ResourcePoolInfo({
    required this.type,
    required this.totalCapacity,
    required this.allocatedCapacity,
    required this.peakUsage,
    required this.allocationCount,
  });
}
