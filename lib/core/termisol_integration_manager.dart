import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Termisol Integration Manager
/// 
/// Central manager for all advanced features integration:
/// - Feature initialization and coordination
/// - Error handling and recovery
/// - Performance monitoring
/// - Configuration management
/// - Event coordination
/// - Resource management
class TermisolIntegrationManager {
  static final TermisolIntegrationManager _instance = TermisolIntegrationManager._internal();
  factory TermisolIntegrationManager() => _instance;
  TermisolIntegrationManager._internal();

  bool _isInitialized = false;
  bool _isInitializing = false;
  
  // Feature managers
  final Map<String, dynamic> _featureManagers = {};
  final Map<String, bool> _featureStatus = {};
  final Map<String, String> _featureErrors = {};
  
  // Event coordination
  final _integrationController = StreamController<IntegrationEvent>.broadcast();
  Stream<IntegrationEvent> get events => _integrationController.stream;
  
  // Health monitoring
  Timer? _healthCheckTimer;
  final Map<String, DateTime> _lastHealthCheck = {};
  final Map<String, bool> _featureHealth = {};
  
  // Configuration
  final Map<String, dynamic> _globalConfig = {};
  bool _autoRecoveryEnabled = true;
  int _maxRetryAttempts = 3;
  
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  int get activeFeatures => _featureStatus.values.where((s) => s).length;
  int get failedFeatures => _featureErrors.length;

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    
    _isInitializing = true;
    
    try {
      debugPrint('🚀 Initializing Termisol Integration Manager...');
      
      // Load global configuration
      await _loadGlobalConfiguration();
      
      // Initialize feature managers
      await _initializeFeatureManagers();
      
      // Setup health monitoring
      _startHealthMonitoring();
      
      // Setup error recovery
      _setupErrorRecovery();
      
      _isInitialized = true;
      _isInitializing = false;
      
      _integrationController.add(IntegrationEvent(
        type: IntegrationEventType.initializationCompleted,
        data: {
          'features_initialized': _featureStatus.length,
          'active_features': activeFeatures,
          'failed_features': failedFeatures,
        },
      ));
      
      debugPrint('✅ Termisol Integration Manager initialized successfully');
      debugPrint('📊 Active features: $activeFeatures, Failed: $failedFeatures');
      
    } catch (e) {
      _isInitializing = false;
      debugPrint('❌ Failed to initialize Integration Manager: $e');
      
      _integrationController.add(IntegrationEvent(
        type: IntegrationEventType.initializationFailed,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _loadGlobalConfiguration() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final configFile = File('$homeDir/.termisol/integration_config.json');
      
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        _globalConfig.addAll(jsonDecode(content) as Map<String, dynamic>);
      }
      
      // Set default configuration
      _globalConfig.putIfAbsent('auto_recovery', () => true);
      _globalConfig.putIfAbsent('max_retry_attempts', () => 3);
      _globalConfig.putIfAbsent('health_check_interval', () => 60000);
      _globalConfig.putIfAbsent('enable_telemetry', () => false);
      _globalConfig.putIfAbsent('performance_monitoring', () => true);
      
      debugPrint('📋 Global configuration loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load global configuration: $e');
    }
  }

  Future<void> _initializeFeatureManagers() async {
    debugPrint('🔧 Initializing feature managers...');
    
    // Initialize all feature managers with error handling
    final features = [
      ('natural_language_commands', () => _initializeNaturalLanguageCommands()),
      ('automatic_error_correction', () => _initializeAutomaticErrorCorrection()),
      ('terminal_recorder', () => _initializeTerminalRecorder()),
      ('ai_bottleneck_detector', () => _initializeAIBottleneckDetector()),
      ('resource_monitor', () => _initializeResourceMonitor()),
      ('session_persistence', () => _initializeSessionPersistence()),
      ('universal_search', () => _initializeUniversalSearch()),
      ('custom_shortcuts', () => _initializeCustomShortcuts()),
      ('clipboard_history', () => _initializeClipboardHistory()),
      ('cross_device_sync', () => _initializeCrossDeviceSync()),
      ('malware_detection', () => _initializeMalwareDetection()),
      ('vscode_integration', () => _initializeVSCodeIntegration()),
      ('context_aware_suggestions', () => _initializeContextAwareSuggestions()),
      ('git_integration', () => _initializeGitIntegration()),
      ('ssh_key_manager', () => _initializeSSHKeyManager()),
    ];
    
    // Initialize features in parallel with error isolation
    final futures = features.map((feature) => _initializeFeature(feature.$1, feature.$2)).toList();
    await Future.wait(futures);
    
    debugPrint('🔧 Feature managers initialization completed');
  }

  Future<void> _initializeFeature(String featureName, Future<void> Function() initializer) async {
    try {
      debugPrint('🔧 Initializing $featureName...');
      
      await initializer();
      
      _featureStatus[featureName] = true;
      _featureErrors.remove(featureName);
      _lastHealthCheck[featureName] = DateTime.now();
      _featureHealth[featureName] = true;
      
      debugPrint('✅ $featureName initialized successfully');
      
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to initialize $featureName: $e');
      debugPrint('Stack trace: $stackTrace');
      
      _featureStatus[featureName] = false;
      _featureErrors[featureName] = '$e';
      _featureHealth[featureName] = false;
      
      // Attempt recovery if enabled
      if (_autoRecoveryEnabled) {
        await _attemptFeatureRecovery(featureName, initializer);
      }
    }
  }

  Future<void> _initializeNaturalLanguageCommands() async {
    // Import and initialize natural language commands
    final manager = NaturalLanguageCommands();
    await manager.initialize();
    _featureManagers['natural_language_commands'] = manager;
  }

  Future<void> _initializeAutomaticErrorCorrection() async {
    final manager = AutomaticErrorCorrection();
    await manager.initialize();
    _featureManagers['automatic_error_correction'] = manager;
  }

  Future<void> _initializeTerminalRecorder() async {
    final manager = TerminalRecorder();
    await manager.initialize();
    _featureManagers['terminal_recorder'] = manager;
  }

  Future<void> _initializeAIBottleneckDetector() async {
    final manager = AIBottleneckDetector();
    await manager.initialize();
    _featureManagers['ai_bottleneck_detector'] = manager;
  }

  Future<void> _initializeResourceMonitor() async {
    final manager = ResourceMonitor();
    await manager.initialize();
    _featureManagers['resource_monitor'] = manager;
  }

  Future<void> _initializeSessionPersistence() async {
    final manager = SessionPersistence();
    await manager.initialize();
    _featureManagers['session_persistence'] = manager;
  }

  Future<void> _initializeUniversalSearch() async {
    final manager = UniversalSearch();
    await manager.initialize();
    _featureManagers['universal_search'] = manager;
  }

  Future<void> _initializeCustomShortcuts() async {
    final manager = CustomShortcuts();
    await manager.initialize();
    _featureManagers['custom_shortcuts'] = manager;
  }

  Future<void> _initializeClipboardHistory() async {
    final manager = ClipboardHistory();
    await manager.initialize();
    _featureManagers['clipboard_history'] = manager;
  }

  Future<void> _initializeCrossDeviceSync() async {
    final manager = CrossDeviceSync();
    await manager.initialize();
    _featureManagers['cross_device_sync'] = manager;
  }

  Future<void> _initializeMalwareDetection() async {
    final manager = MalwareDetection();
    await manager.initialize();
    _featureManagers['malware_detection'] = manager;
  }

  Future<void> _initializeVSCodeIntegration() async {
    final manager = VSCodeIntegration();
    await manager.initialize();
    _featureManagers['vscode_integration'] = manager;
  }

  Future<void> _initializeContextAwareSuggestions() async {
    final manager = ContextAwareSuggestions();
    await manager.initialize();
    _featureManagers['context_aware_suggestions'] = manager;
  }

  Future<void> _initializeGitIntegration() async {
    final manager = GitIntegration();
    await manager.initialize();
    _featureManagers['git_integration'] = manager;
  }

  Future<void> _initializeSSHKeyManager() async {
    final manager = SSHKeyManager();
    await manager.initialize();
    _featureManagers['ssh_key_manager'] = manager;
  }

  Future<void> _attemptFeatureRecovery(String featureName, Future<void> Function() initializer) async {
    debugPrint('🔄 Attempting recovery for $featureName...');
    
    for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        debugPrint('🔄 Recovery attempt $attempt for $featureName');
        
        // Wait before retry
        await Future.delayed(Duration(seconds: attempt * 2));
        
        await initializer();
        
        _featureStatus[featureName] = true;
        _featureErrors.remove(featureName);
        _featureHealth[featureName] = true;
        
        debugPrint('✅ Recovery successful for $featureName (attempt $attempt)');
        
        _integrationController.add(IntegrationEvent(
          type: IntegrationEventType.featureRecovered,
          data: {
            'feature': featureName,
            'attempt': attempt,
          },
        ));
        
        return;
      } catch (e) {
        debugPrint('⚠️ Recovery attempt $attempt failed for $featureName: $e');
        
        if (attempt == _maxRetryAttempts) {
          debugPrint('❌ All recovery attempts failed for $featureName');
          
          _integrationController.add(IntegrationEvent(
            type: IntegrationEventType.featureRecoveryFailed,
            data: {
              'feature': featureName,
              'attempts': _maxRetryAttempts,
              'error': e.toString(),
            },
          ));
        }
      }
    }
  }

  void _startHealthMonitoring() {
    final interval = Duration(milliseconds: _globalConfig['health_check_interval'] ?? 60000);
    
    _healthCheckTimer = Timer.periodic(interval, (_) {
      _performHealthCheck();
    });
    
    debugPrint('💗 Health monitoring started (${interval.inSeconds} seconds)');
  }

  Future<void> _performHealthCheck() async {
    debugPrint('💗 Performing health check...');
    
    for (final entry in _featureManagers.entries) {
      final featureName = entry.key;
      final manager = entry.value;
      
      try {
        // Check if feature is still responsive
        final isHealthy = await _checkFeatureHealth(featureName, manager);
        
        _featureHealth[featureName] = isHealthy;
        _lastHealthCheck[featureName] = DateTime.now();
        
        if (!isHealthy && _featureStatus[featureName] == true) {
          debugPrint('⚠️ Feature $featureName became unhealthy');
          
          _integrationController.add(IntegrationEvent(
            type: IntegrationEventType.featureUnhealthy,
            data: {'feature': featureName},
          ));
          
          // Attempt recovery
          if (_autoRecoveryEnabled) {
            await _attemptFeatureRecovery(featureName, () => _reinitializeFeature(featureName));
          }
        }
        
      } catch (e) {
        debugPrint('⚠️ Health check failed for $featureName: $e');
        _featureHealth[featureName] = false;
      }
    }
    
    debugPrint('💗 Health check completed');
  }

  Future<bool> _checkFeatureHealth(String featureName, dynamic manager) async {
    try {
      // Basic health check - try to get statistics or status
      if (manager is NaturalLanguageCommands) {
        return manager.isInitialized;
      } else if (manager is AutomaticErrorCorrection) {
        return manager.isInitialized;
      } else if (manager is TerminalRecorder) {
        return manager.isInitialized;
      } else if (manager is AIBottleneckDetector) {
        return manager.isInitialized;
      } else if (manager is ResourceMonitor) {
        return manager.isInitialized;
      } else if (manager is SessionPersistence) {
        return manager.isInitialized;
      } else if (manager is UniversalSearch) {
        return manager.isInitialized;
      } else if (manager is CustomShortcuts) {
        return manager.isInitialized;
      } else if (manager is ClipboardHistory) {
        return manager.isInitialized;
      } else if (manager is CrossDeviceSync) {
        return manager.isInitialized;
      } else if (manager is MalwareDetection) {
        return manager.isInitialized;
      } else if (manager is VSCodeIntegration) {
        return manager.isInitialized;
      } else if (manager is ContextAwareSuggestions) {
        return manager.isInitialized;
      } else if (manager is GitIntegration) {
        return manager.isInitialized;
      } else if (manager is SSHKeyManager) {
        return manager.isInitialized;
      }
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Health check error for $featureName: $e');
      return false;
    }
  }

  Future<void> _reinitializeFeature(String featureName) async {
    debugPrint('🔄 Reinitializing feature: $featureName');
    
    switch (featureName) {
      case 'natural_language_commands':
        await _initializeNaturalLanguageCommands();
        break;
      case 'automatic_error_correction':
        await _initializeAutomaticErrorCorrection();
        break;
      case 'terminal_recorder':
        await _initializeTerminalRecorder();
        break;
      case 'ai_bottleneck_detector':
        await _initializeAIBottleneckDetector();
        break;
      case 'resource_monitor':
        await _initializeResourceMonitor();
        break;
      case 'session_persistence':
        await _initializeSessionPersistence();
        break;
      case 'universal_search':
        await _initializeUniversalSearch();
        break;
      case 'custom_shortcuts':
        await _initializeCustomShortcuts();
        break;
      case 'clipboard_history':
        await _initializeClipboardHistory();
        break;
      case 'cross_device_sync':
        await _initializeCrossDeviceSync();
        break;
      case 'malware_detection':
        await _initializeMalwareDetection();
        break;
      case 'vscode_integration':
        await _initializeVSCodeIntegration();
        break;
      case 'context_aware_suggestions':
        await _initializeContextAwareSuggestions();
        break;
      case 'git_integration':
        await _initializeGitIntegration();
        break;
      case 'ssh_key_manager':
        await _initializeSSHKeyManager();
        break;
    }
  }

  void _setupErrorRecovery() {
    // Setup global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('🔥 Flutter error: ${details.exception}');
      debugPrint('Stack trace: ${details.stack}');
      
      _integrationController.add(IntegrationEvent(
        type: IntegrationEventType.errorOccurred,
        error: details.exception.toString(),
        data: {
          'stack_trace': details.stack?.toString(),
          'library': details.library,
        },
      ));
    };
    
    // Setup platform error handlers
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔥 Platform error: $error');
      debugPrint('Stack trace: $stack');
      
      _integrationController.add(IntegrationEvent(
        type: IntegrationEventType.errorOccurred,
        error: error.toString(),
        data: {
          'stack_trace': stack.toString(),
          'type': 'platform',
        },
      ));
      
      return true;
    };
  }

  // Public API methods
  
  T? getFeatureManager<T>(String featureName) {
    return _featureManagers[featureName] as T?;
  }

  bool isFeatureActive(String featureName) {
    return _featureStatus[featureName] ?? false;
  }

  bool isFeatureHealthy(String featureName) {
    return _featureHealth[featureName] ?? false;
  }

  String? getFeatureError(String featureName) {
    return _featureErrors[featureName];
  }

  Map<String, bool> getAllFeatureStatus() {
    return Map.unmodifiable(_featureStatus);
  }

  Map<String, bool> getAllFeatureHealth() {
    return Map.unmodifiable(_featureHealth);
  }

  Future<bool> restartFeature(String featureName) async {
    try {
      debugPrint('🔄 Restarting feature: $featureName');
      
      // Dispose existing manager
      final manager = _featureManagers[featureName];
      if (manager != null && manager is dynamic) {
        if (manager.dispose is Function) {
          await manager.dispose();
        }
      }
      
      // Remove from managers
      _featureManagers.remove(featureName);
      _featureStatus.remove(featureName);
      _featureErrors.remove(featureName);
      
      // Reinitialize
      await _reinitializeFeature(featureName);
      
      _integrationController.add(IntegrationEvent(
        type: IntegrationEventType.featureRestarted,
        data: {'feature': featureName},
      ));
      
      debugPrint('✅ Feature restarted: $featureName');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to restart feature $featureName: $e');
      return false;
    }
  }

  Future<void> performDiagnostics() async {
    debugPrint('🔍 Performing comprehensive diagnostics...');
    
    final diagnostics = <String, dynamic>{};
    
    // Check each feature
    for (final featureName in _featureManagers.keys) {
      final manager = _featureManagers[featureName];
      final isHealthy = await _checkFeatureHealth(featureName, manager);
      final status = _featureStatus[featureName] ?? false;
      final lastCheck = _lastHealthCheck[featureName];
      
      diagnostics[featureName] = {
        'healthy': isHealthy,
        'active': status,
        'last_health_check': lastCheck?.toIso8601String(),
        'error': _featureErrors[featureName],
      };
    }
    
    // Global diagnostics
    diagnostics['global'] = {
      'total_features': _featureManagers.length,
      'active_features': activeFeatures,
      'failed_features': failedFeatures,
      'healthy_features': _featureHealth.values.where((h) => h).length,
      'auto_recovery_enabled': _autoRecoveryEnabled,
      'max_retry_attempts': _maxRetryAttempts,
      'integration_manager_initialized': _isInitialized,
    };
    
    _integrationController.add(IntegrationEvent(
      type: IntegrationEventType.diagnosticsCompleted,
      data: diagnostics,
    ));
    
    debugPrint('🔍 Diagnostics completed');
    debugPrint('📊 Summary: ${diagnostics['global']}');
  }

  Future<Map<String, dynamic>> getSystemStatus() async {
    final status = <String, dynamic>{
      'integration_manager': {
        'initialized': _isInitialized,
        'initializing': _isInitializing,
        'active_features': activeFeatures,
        'failed_features': failedFeatures,
      },
      'features': <String, dynamic>{},
    };
    
    // Get status from each feature manager
    for (final entry in _featureManagers.entries) {
      final featureName = entry.key;
      final manager = entry.value;
      
      try {
        if (manager is NaturalLanguageCommands) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is AutomaticErrorCorrection) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is TerminalRecorder) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is AIBottleneckDetector) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is ResourceMonitor) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is SessionPersistence) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is UniversalSearch) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is CustomShortcuts) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is ClipboardHistory) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is CrossDeviceSync) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is MalwareDetection) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is VSCodeIntegration) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is ContextAwareSuggestions) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is GitIntegration) {
          status['features'][featureName] = manager.getStatistics();
        } else if (manager is SSHKeyManager) {
          status['features'][featureName] = manager.getStatistics();
        } else {
          status['features'][featureName] = {
            'initialized': true,
            'type': manager.runtimeType.toString(),
          };
        }
      } catch (e) {
        status['features'][featureName] = {
          'error': e.toString(),
          'type': manager.runtimeType.toString(),
        };
      }
    }
    
    return status;
  }

  Future<void> dispose() async {
    debugPrint('🔄 Disposing Termisol Integration Manager...');
    
    // Cancel timers
    _healthCheckTimer?.cancel();
    
    // Dispose all feature managers
    for (final entry in _featureManagers.entries) {
      try {
        final manager = entry.value;
        if (manager is dynamic && manager.dispose is Function) {
          await manager.dispose();
        }
      } catch (e) {
        debugPrint('⚠️ Failed to dispose ${entry.key}: $e');
      }
    }
    
    // Clear data
    _featureManagers.clear();
    _featureStatus.clear();
    _featureErrors.clear();
    _lastHealthCheck.clear();
    _featureHealth.clear();
    
    // Close event controller
    _integrationController.close();
    
    _isInitialized = false;
    debugPrint('✅ Termisol Integration Manager disposed');
  }
}

/// Integration event
class IntegrationEvent {
  final IntegrationEventType type;
  final String? error;
  final Map<String, dynamic>? data;
  
  IntegrationEvent({
    required this.type,
    this.error,
    this.data,
  });
}

enum IntegrationEventType {
  initializationStarted,
  initializationCompleted,
  initializationFailed,
  featureInitialized,
  featureFailed,
  featureRecovered,
  featureRecoveryFailed,
  featureRestarted,
  featureUnhealthy,
  errorOccurred,
  diagnosticsCompleted,
  healthCheckCompleted,
}
