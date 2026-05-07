import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Dependency Injection System - Best-in-class service management
/// 
/// Provides comprehensive dependency injection with:
/// - Singleton and transient service lifecycles
/// - Circular dependency detection
/// - Lazy initialization
/// - Service factory methods
/// - Interface-based registration
/// - Automatic disposal management
class DependencyInjection {
  static final DependencyInjection _instance = DependencyInjection._internal();
  factory DependencyInjection() => _instance;
  DependencyInjection._internal();

  final Map<Type, ServiceDefinition> _services = {};
  final Map<Type, dynamic> _singletons = {};
  final Map<Type, dynamic> _transients = {};
  final Set<Type> _resolving = <Type>{};
  
  bool _isInitialized = false;
  bool _isDisposed = false;
  
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  /// Initialize the dependency injection container
  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) return;
    
    try {
      // Register core services
      await _registerCoreServices();
      
      _isInitialized = true;
      debugPrint('💉 Dependency Injection initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Dependency Injection: $e');
      rethrow;
    }
  }

  /// Register a singleton service
  void registerSingleton<T extends Object>(
    T Function() factory, {
    String? name,
    bool lazy = true,
    Future<void> Function(T)? onDispose,
  }) {
    final type = T;
    _services[type] = ServiceDefinition(
      type: type,
      factory: factory,
      lifecycle: ServiceLifecycle.singleton,
      lazy: lazy,
      name: name,
      onDispose: onDispose,
    );
    
    debugPrint('💉 Registered singleton: $type');
  }

  /// Register a transient service
  void registerTransient<T extends Object>(
    T Function() factory, {
    String? name,
    Future<void> Function(T)? onDispose,
  }) {
    final type = T;
    _services[type] = ServiceDefinition(
      type: type,
      factory: factory,
      lifecycle: ServiceLifecycle.transient,
      lazy: false,
      name: name,
      onDispose: onDispose,
    );
    
    debugPrint('💉 Registered transient: $type');
  }

  /// Register an interface implementation
  void registerInterface<TInterface, TImplementation extends TInterface>(
    TImplementation Function() factory, {
    ServiceLifecycle lifecycle = ServiceLifecycle.singleton,
    String? name,
    bool lazy = true,
    Future<void> Function(TImplementation)? onDispose,
  }) {
    final interfaceType = TInterface;
    final implType = TImplementation;
    
    _services[interfaceType] = ServiceDefinition(
      type: interfaceType,
      implementationType: implType,
      factory: factory,
      lifecycle: lifecycle,
      lazy: lazy,
      name: name,
      onDispose: onDispose,
    );
    
    debugPrint('💉 Registered interface $interfaceType -> $implType');
  }

  /// Get a service instance
  T get<T extends Object>() {
    if (_isDisposed) {
      throw StateError('Dependency injection container has been disposed');
    }
    
    final type = T;
    final definition = _services[type];
    
    if (definition == null) {
      throw ArgumentError('Service not registered: $type');
    }
    
    return _createInstance<T>(definition);
  }

  /// Get a service asynchronously
  Future<T> getAsync<T extends Object>() async {
    // For now, just call the synchronous version
    // In a real implementation, this could handle async factory methods
    return get<T>();
  }

  /// Try to get a service instance
  T? tryGet<T extends Object>() {
    try {
      return get<T>();
    } catch (e) {
      return null;
    }
  }

  /// Check if a service is registered
  bool isRegistered<T extends Object>() {
    return _services.containsKey(T);
  }

  /// Create a service instance
  T _createInstance<T extends Object>(ServiceDefinition definition) {
    final type = definition.type;
    
    // Check for circular dependencies
    if (_resolving.contains(type)) {
      throw StateError('Circular dependency detected: $type');
    }
    
    // Return existing singleton if already created
    if (definition.lifecycle == ServiceLifecycle.singleton) {
      if (_singletons.containsKey(type)) {
        return _singletons[type] as T;
      }
    }
    
    // Mark as resolving
    _resolving.add(type);
    
    try {
      // Create instance
      final instance = definition.factory() as T;
      
      // Store based on lifecycle
      if (definition.lifecycle == ServiceLifecycle.singleton) {
        _singletons[type] = instance;
      } else {
        _transients[type] = instance;
      }
      
      return instance;
      
    } finally {
      _resolving.remove(type);
    }
  }

  /// Register core services
  Future<void> _registerCoreServices() async {
    // Performance monitor
    registerSingleton<UnifiedPerformanceMonitor>(
      () => UnifiedPerformanceMonitor(),
      lazy: true,
    );

    // Lazy loading manager
    registerSingleton<LazyLoadingManager>(
      () => LazyLoadingManager(),
      lazy: true,
    );

    // Object pool manager
    registerSingleton<ObjectPoolManager>(
      () => ObjectPoolManager(),
      lazy: true,
    );

    // Circular buffer manager
    registerSingleton<CircularBufferManager>(
      () => CircularBufferManager(),
      lazy: true,
    );

    // Smart throttling manager
    registerSingleton<SmartThrottlingManager>(
      () => SmartThrottlingManager(),
      lazy: true,
    );

    // Texture compression manager
    registerSingleton<TextureCompressionManager>(
      () => TextureCompressionManager(),
      lazy: true,
    );

    debugPrint('💉 Registered ${_services.length} core services');
  }

  /// Initialize all non-lazy singletons
  Future<void> initializeSingletons() async {
    final nonLazyServices = _services.values
        .where((s) => s.lifecycle == ServiceLifecycle.singleton && !s.lazy)
        .toList();
    
    for (final service in nonLazyServices) {
      get<dynamic>(service.type);
    }
    
    debugPrint('💉 Initialized ${nonLazyServices.length} non-lazy singletons');
  }

  /// Get service statistics
  ServiceStatistics getStatistics() {
    return ServiceStatistics(
      registeredServices: _services.length,
      activeSingletons: _singletons.length,
      activeTransients: _transients.length,
      circularDependencies: _resolving.length,
      services: _services.values.map((s) => ServiceInfo(
        type: s.type.toString(),
        lifecycle: s.lifecycle,
        lazy: s.lazy,
        name: s.name,
      )).toList(),
    );
  }

  /// Dispose the dependency injection container
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    
    // Dispose all singletons with disposal methods
    for (final entry in _singletons.entries) {
      final definition = _services[entry.key];
      final instance = entry.value;
      
      if (definition?.onDispose != null) {
        try {
          await definition!.onDispose!(instance);
        } catch (e) {
          debugPrint('❌ Error disposing service ${entry.key}: $e');
        }
      }
    }
    
    // Dispose all transients with disposal methods
    for (final entry in _transients.entries) {
      final definition = _services[entry.key];
      final instance = entry.value;
      
      if (definition?.onDispose != null) {
        try {
          await definition!.onDispose!(instance);
        } catch (e) {
          debugPrint('❌ Error disposing transient service ${entry.key}: $e');
        }
      }
    }
    
    _services.clear();
    _singletons.clear();
    _transients.clear();
    _resolving.clear();
    
    debugPrint('💉 Dependency Injection disposed');
  }
}

/// Service definition
class ServiceDefinition {
  final Type type;
  final Type? implementationType;
  final dynamic Function() factory;
  final ServiceLifecycle lifecycle;
  final bool lazy;
  final String? name;
  final Future<void> Function(dynamic)? onDispose;
  
  ServiceDefinition({
    required this.type,
    this.implementationType,
    required this.factory,
    required this.lifecycle,
    required this.lazy,
    this.name,
    this.onDispose,
  });
}

/// Service lifecycle
enum ServiceLifecycle {
  singleton,
  transient,
}

/// Service statistics
class ServiceStatistics {
  final int registeredServices;
  final int activeSingletons;
  final int activeTransients;
  final int circularDependencies;
  final List<ServiceInfo> services;
  
  ServiceStatistics({
    required this.registeredServices,
    required this.activeSingletons,
    required this.activeTransients,
    required this.circularDependencies,
    required this.services,
  });
}

/// Service information
class ServiceInfo {
  final String type;
  final ServiceLifecycle lifecycle;
  final bool lazy;
  final String? name;
  
  ServiceInfo({
    required this.type,
    required this.lifecycle,
    required this.lazy,
    this.name,
  });
}

/// Service locator for easy access
class ServiceLocator {
  static final DependencyInjection _di = DependencyInjection();
  
  static T get<T extends Object>() => _di.get<T>();
  static Future<T> getAsync<T extends Object>() => _di.getAsync<T>();
  static T? tryGet<T extends Object>() => _di.tryGet<T>();
  static bool isRegistered<T extends Object>() => _di.isRegistered<T>();
}

/// Injectable annotation for automatic registration
class Injectable {
  final ServiceLifecycle lifecycle;
  final bool lazy;
  final String? name;
  
  const Injectable({
    this.lifecycle = ServiceLifecycle.singleton,
    this.lazy = true,
    this.name,
  });
}

/// Inject annotation for constructor injection
class Inject {
  final String? name;
  
  const Inject({this.name});
}

/// Service container extension for easier registration
extension ServiceContainer on DependencyInjection {
  void registerFactory<T extends Object>(T Function() factory) {
    registerTransient(factory);
  }
  
  void registerLazySingleton<T extends Object>(
    T Function() factory, {
    String? name,
    Future<void> Function(T)? onDispose,
  }) {
    registerSingleton(factory, name: name, lazy: true, onDispose: onDispose);
  }
  
  void registerEagerSingleton<T extends Object>(
    T Function() factory, {
    String? name,
    Future<void> Function(T)? onDispose,
  }) {
    registerSingleton(factory, name: name, lazy: false, onDispose: onDispose);
  }
}
