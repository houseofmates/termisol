import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';
import 'personal_command_fingerprint.dart';
import 'personal_performance_profiles.dart';
import 'adaptive_resource_manager.dart';
import 'personal_error_correction.dart';
import 'project_templates.dart';
import 'intelligent_background_processor.dart';
import 'personal_storage_optimizer.dart';

/// Personal integration manager for all personalized features
/// 
/// Features:
/// - Integrates all personal systems
/// - Amnesia-proof persistence
/// - Tool integration (Hermes, N8N, Nextcloud)
/// - Unified personal data management
class PersonalIntegrationManager {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<IntegrationEvent> _eventController = StreamController<IntegrationEvent>.broadcast();
  
  PersonalCommandFingerprint? _commandFingerprint;
  PersonalPerformanceProfiles? _performanceProfiles;
  AdaptiveResourceManager? _resourceManager;
  PersonalErrorCorrection? _errorCorrection;
  ProjectTemplates? _projectTemplates;
  IntelligentBackgroundProcessor? _backgroundProcessor;
  PersonalStorageOptimizer? _storageOptimizer;
  
  final Map<String, ToolIntegration> _toolIntegrations = {};
  final Map<String, dynamic> _personalData = {};
  
  Timer? _syncTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<IntegrationEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  PersonalIntegrationManager({this.aiAssistant});
  
  /// Initialize personal integration manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Initialize all personal systems
      await _initializePersonalSystems();
      
      // Initialize tool integrations
      await _initializeToolIntegrations();
      
      // Start sync timer
      _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _syncPersonalData();
      });
      
      _isInitialized = true;
      
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.initialized,
        message: 'Personal integration manager initialized',
        data: {'systems_count': 7, 'tools_count': _toolIntegrations.length},
      ));
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to initialize integration manager: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<void> _initializePersonalSystems() async {
    // Initialize all personal systems
    _commandFingerprint = PersonalCommandFingerprint(aiAssistant: aiAssistant);
    _performanceProfiles = PersonalPerformanceProfiles(aiAssistant: aiAssistant);
    _resourceManager = AdaptiveResourceManager(aiAssistant: aiAssistant);
    _errorCorrection = PersonalErrorCorrection(aiAssistant: aiAssistant);
    _projectTemplates = ProjectTemplates(aiAssistant: aiAssistant);
    _backgroundProcessor = IntelligentBackgroundProcessor(aiAssistant: aiAssistant);
    _storageOptimizer = PersonalStorageOptimizer(aiAssistant: aiAssistant);
    
    // Initialize all systems
    await Future.wait([
      _commandFingerprint!.initialize(),
      _performanceProfiles!.initialize(),
      _resourceManager!.initialize(),
      _errorCorrection!.initialize(),
      _projectTemplates!.initialize(),
      _backgroundProcessor!.initialize(),
      _storageOptimizer!.initialize(),
    ]);
    
    // Set up event listeners for cross-system communication
    _setupSystemEventListeners();
  }
  
  void _setupSystemEventListeners() {
    // Command fingerprint events
    _commandFingerprint!.events.listen((event) {
      _handleCommandFingerprintEvent(event);
    });
    
    // Performance profile events
    _performanceProfiles!.events.listen((event) {
      _handlePerformanceEvent(event);
    });
    
    // Resource manager events
    _resourceManager!.events.listen((event) {
      _handleResourceEvent(event);
    });
    
    // Error correction events
    _errorCorrection!.events.listen((event) {
      _handleErrorCorrectionEvent(event);
    });
    
    // Project template events
    _projectTemplates!.events.listen((event) {
      _handleTemplateEvent(event);
    });
    
    // Background processor events
    _backgroundProcessor!.events.listen((event) {
      _handleBackgroundEvent(event);
    });
    
    // Storage optimizer events
    _storageOptimizer!.events.listen((event) {
      _handleStorageEvent(event);
    });
  }
  
  void _handleCommandFingerprintEvent(FingerprintEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.command_fingerprint_event,
      message: 'Command fingerprint event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handlePerformanceEvent(PerformanceEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.performance_event,
      message: 'Performance event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handleResourceEvent(ResourceEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.resource_event,
      message: 'Resource event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handleErrorCorrectionEvent(ErrorCorrectionEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.error_correction_event,
      message: 'Error correction event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handleTemplateEvent(TemplateEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.template_event,
      message: 'Template event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handleBackgroundEvent(BackgroundEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.background_event,
      message: 'Background event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  void _handleStorageEvent(StorageEvent event) {
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.storage_event,
      message: 'Storage event: ${event.message}',
      data: {
        'event_type': event.type.toString(),
        'event_data': event.data,
      },
    ));
  }
  
  Future<void> _initializeToolIntegrations() async {
    // Initialize Hermes Agent integration
    _toolIntegrations['hermes'] = ToolIntegration(
      name: 'Hermes Agent',
      description: 'AI-powered agent integration',
      type: ToolType.ai_agent,
      enabled: true,
      config: {
        'api_endpoint': 'http://localhost:3000/api',
        'timeout': Duration(seconds: 30),
        'retry_count': 3,
      },
    );
    
    // Initialize N8N integration
    _toolIntegrations['n8n'] = ToolIntegration(
      name: 'N8N Workflow Automation',
      description: 'Self-hosted N8N integration',
      type: ToolType.workflow_automation,
      enabled: false, // Requires API key
      config: {
        'base_url': 'https://n8n.houseofmates.space',
        'api_version': 'v1',
        'timeout': Duration(seconds: 45),
        'webhook_timeout': Duration(seconds: 10),
      },
    );
    
    // Initialize Nextcloud integration
    _toolIntegrations['nextcloud'] = ToolIntegration(
      name: 'Nextcloud',
      description: 'Self-hosted Nextcloud integration',
      type: ToolType.cloud_storage,
      enabled: true,
      config: {
        'base_url': 'https://cloud.houseofmates.space',
        'username': 'house',
        'sync_interval': Duration(minutes: 15),
        'max_file_size': 100 * 1024 * 1024, // 100MB
      },
    );
    
    // Initialize Docker integration (from stack)
    _toolIntegrations['docker_stack'] = ToolIntegration(
      name: 'Docker Stack',
      description: 'Docker compose stack management',
      type: ToolType.container_management,
      enabled: true,
      config: {
        'stack_path': '/home/house/Documents/docker/main-stack',
        'auto_restart': true,
        'health_check_interval': Duration(minutes: 5),
      },
    );
    
    // Load tool configurations from environment
    await _loadToolConfigurations();
  }
  
  Future<void> _loadToolConfigurations() async {
    // Load N8N API key from environment
    final n8nApiKey = Platform.environment['N8N_API_KEY'] ?? 
                   _prefs.getString('n8n_api_key');
    
    if (n8nApiKey != null && n8nApiKey!.isNotEmpty) {
      final n8nIntegration = _toolIntegrations['n8n']!;
      n8nIntegration.enabled = true;
      n8nIntegration.config['api_key'] = n8nApiKey;
      _toolIntegrations['n8n'] = n8nIntegration;
    }
    
    // Load Nextcloud API key from environment
    final nextcloudApiKey = Platform.environment['NEXTCLOUD_API_KEY'] ??
                           _prefs.getString('nextcloud_api_key');
    
    if (nextcloudApiKey != null && nextcloudApiKey!.isNotEmpty) {
      final nextcloudIntegration = _toolIntegrations['nextcloud']!;
      nextcloudIntegration.enabled = true;
      nextcloudIntegration.config['api_key'] = nextcloudApiKey;
      _toolIntegrations['nextcloud'] = nextcloudIntegration;
    }
  }
  
  /// Record command with full personal context
  void recordCommand(String command, {String? project, String? workingDirectory}) {
    _commandFingerprint?.recordCommand(command, workingDirectory, project: project);
    
    // Update personal data
    _personalData['last_command'] = command;
    _personalData['last_project'] = project;
    _personalData['last_working_directory'] = workingDirectory;
    _personalData['last_command_time'] = DateTime.now().toIso8601String();
    
    // Sync with integrated tools
    _syncWithTools(command, project, workingDirectory);
  }
  
  void _syncWithTools(String command, String? project, String? workingDirectory) {
    // Sync with Hermes Agent
    if (_toolIntegrations['hermes']!.enabled) {
      _syncWithHermes(command, project, workingDirectory);
    }
    
    // Sync with N8N
    if (_toolIntegrations['n8n']!.enabled) {
      _syncWithN8N(command, project, workingDirectory);
    }
    
    // Sync with Nextcloud
    if (_toolIntegrations['nextcloud']!.enabled) {
      _syncWithNextcloud(command, project, workingDirectory);
    }
  }
  
  Future<void> _syncWithHermes(String command, String? project, String? workingDirectory) async {
    try {
      final hermesConfig = _toolIntegrations['hermes']!.config;
      final endpoint = Uri.parse('${hermesConfig['api_endpoint']}/command');
      
      // Send command to Hermes
      final response = await HttpClient().postUrl(endpoint, headers: {
        'Content-Type': 'application/json',
      }, body: jsonEncode({
        'command': command,
        'project': project,
        'working_directory': workingDirectory,
        'timestamp': DateTime.now().toIso8601String(),
        'user_context': _personalData,
      }));
      
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.hermes_sync,
        message: 'Synced with Hermes Agent',
        data: {
          'command': command,
          'response': response.statusCode,
        },
      ));
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to sync with Hermes: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<void> _syncWithN8N(String command, String? project, String? workingDirectory) async {
    try {
      final n8nConfig = _toolIntegrations['n8n']!.config;
      final endpoint = Uri.parse('${n8nConfig['base_url']}/api/v1/workflows');
      
      // Trigger N8N workflow based on command
      final workflowId = _getN8NWorkflowId(command);
      if (workflowId != null) {
        final response = await HttpClient().postUrl(
          Uri.parse('${n8nConfig['base_url']}/api/v1/workflows/$workflowId/execute'),
          headers: {
            'Content-Type': 'application/json',
            'X-N8N-API-KEY': n8nConfig['api_key'],
          },
          body: jsonEncode({
            'command': command,
            'project': project,
            'working_directory': workingDirectory,
            'user_context': _personalData,
          }),
        );
        
        _eventController.add(IntegrationEvent(
          type: IntegrationEventType.n8n_sync,
          message: 'Triggered N8N workflow',
          data: {
            'workflow_id': workflowId,
            'command': command,
            'response': response.statusCode,
          },
        ));
      }
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to sync with N8N: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  String? _getN8NWorkflowId(String command) {
    // Map commands to N8N workflows
    final commandWorkflows = {
      'git': 'git-operations',
      'docker': 'docker-management',
      'deploy': 'deployment-workflow',
      'backup': 'backup-workflow',
      'monitor': 'monitoring-workflow',
      'cleanup': 'cleanup-workflow',
    };
    
    for (final entry in commandWorkflows.entries) {
      if (command.startsWith(entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  Future<void> _syncWithNextcloud(String command, String? project, String? workingDirectory) async {
    try {
      final nextcloudConfig = _toolIntegrations['nextcloud']!.config;
      
      // Sync command history to Nextcloud
      final commandHistory = _personalData['command_history'] as List? ?? [];
      commandHistory.insert(0, {
        'command': command,
        'project': project,
        'working_directory': workingDirectory,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Keep only last 1000 commands
      if (commandHistory.length > 1000) {
        commandHistory.removeRange(1000, commandHistory.length);
      }
      
      _personalData['command_history'] = commandHistory;
      
      // Upload to Nextcloud using API key authentication
      final response = await HttpClient().putUrl(
        Uri.parse('${nextcloudConfig['base_url']}/remote.php/dav/files/termisol/command_history.json'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${nextcloudConfig['api_key']}',
        },
        body: jsonEncode(commandHistory),
      );
      
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.nextcloud_sync,
        message: 'Synced with Nextcloud',
        data: {
          'commands_synced': commandHistory.length,
          'response': response.statusCode,
        },
      ));
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to sync with Nextcloud: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Get unified personal statistics
  Map<String, dynamic> getPersonalStatistics() {
    return {
      'is_initialized': _isInitialized,
      'personal_data': _personalData,
      'command_fingerprint': _commandFingerprint?.getPersonalStatistics(),
      'performance_profiles': _performanceProfiles?.getPerformanceStatistics(),
      'resource_manager': _resourceManager?.getResourceStatistics(),
      'error_correction': _errorCorrection?.getErrorStatistics(),
      'project_templates': _projectTemplates?.getTemplateStatistics(),
      'background_processor': _backgroundProcessor?.getTaskStatus(),
      'storage_optimizer': _storageOptimizer?.getStorageStatistics(),
      'tool_integrations': _toolIntegrations.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
  
  /// Enable/disable tool integration
  Future<bool> toggleToolIntegration(String toolId, bool enabled) async {
    if (!_toolIntegrations.containsKey(toolId)) return false;
    
    final integration = _toolIntegrations[toolId]!;
    integration.enabled = enabled;
    _toolIntegrations[toolId] = integration;
    
    await _persistToolIntegrations();
    
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.tool_toggled,
      message: 'Tool integration toggled: $toolId',
      data: {
        'tool_id': toolId,
        'enabled': enabled,
      },
    ));
    
    return true;
  }
  
  /// Configure tool integration
  Future<bool> configureToolIntegration(String toolId, Map<String, dynamic> config) async {
    if (!_toolIntegrations.containsKey(toolId)) return false;
    
    final integration = _toolIntegrations[toolId]!;
    integration.config.addAll(config);
    _toolIntegrations[toolId] = integration;
    
    await _persistToolIntegrations();
    
    _eventController.add(IntegrationEvent(
      type: IntegrationEventType.tool_configured,
      message: 'Tool integration configured: $toolId',
      data: {
        'tool_id': toolId,
        'config': config,
      },
    ));
    
    return true;
  }
  
  /// Sync personal data across all systems
  Future<void> _syncPersonalData() async {
    try {
      // Sync data between all personal systems
      final syncData = {
        'timestamp': DateTime.now().toIso8601String(),
        'personal_data': _personalData,
        'system_stats': {
          'command_fingerprint': _commandFingerprint?.getPersonalStatistics(),
          'performance_profiles': _performanceProfiles?.getPerformanceStatistics(),
          'resource_manager': _resourceManager?.getResourceStatistics(),
          'error_correction': _errorCorrection?.getErrorStatistics(),
          'project_templates': _projectTemplates?.getTemplateStatistics(),
          'background_processor': _backgroundProcessor?.getTaskStatus(),
          'storage_optimizer': _storageOptimizer?.getStorageStatistics(),
        },
        'tool_integrations': _toolIntegrations.map((k, v) => MapEntry(k, v.toJson())),
      };
      
      // Persist immediately for amnesia protection
      await _persistPersonalDataImmediately(syncData);
      
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.data_synced,
        message: 'Personal data synchronized',
        data: {'sync_data': syncData},
      ));
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to sync personal data: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Get AI-powered personal insights
  Future<Map<String, dynamic>> getPersonalInsights() async {
    if (aiAssistant == null) return {};
    
    try {
      final prompt = '''Analyze my complete personal Termisol usage and provide comprehensive insights:

Personal Data:
${jsonEncode(_personalData)}

System Statistics:
${jsonEncode(getPersonalStatistics())}

Tool Integrations:
${jsonEncode(_toolIntegrations.map((k, v) => MapEntry(k, v.toJson())))}

Provide insights on:
1. My usage patterns and productivity trends
2. Optimization opportunities based on my NVIDIA hardware (RTX 3080/2070)
3. Tool integration improvements
4. Personal efficiency recommendations
5. Predictive suggestions for my workflow

Use these NVIDIA AI models for best analysis:
- deepseek-ai/deepseek-v4-pro for comprehensive insights
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for technical analysis
- minimaxai/minimax-m2.7 for efficiency recommendations''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      return {
        'insights': response,
        'generated_at': DateTime.now().toIso8601String(),
        'data_sources': ['personal_data', 'system_stats', 'tool_integrations'],
      };
    } catch (e) {
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.error,
        message: 'Failed to generate personal insights: $e',
        data: {'error': e.toString()},
      ));
      return {};
    }
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load personal data
      final personalDataJson = _prefs.getString('personal_data') ?? '{}';
      _personalData.clear();
      final personalDataMap = jsonDecode(personalDataJson) as Map;
      for (final entry in personalDataMap.entries) {
        _personalData[entry.key] = entry.value;
      }
      
      // Load tool integrations
      final toolsJson = _prefs.getString('tool_integrations') ?? '{}';
      final toolsMap = jsonDecode(toolsJson) as Map;
      _toolIntegrations.clear();
      for (final entry in toolsMap.entries) {
        _toolIntegrations[entry.key] = ToolIntegration.fromJson(entry.value);
      }
      
      _eventController.add(IntegrationEvent(
        type: IntegrationEventType.data_loaded,
        message: 'Persisted integration data loaded',
        data: {
          'personal_data_count': _personalData.length,
          'tool_integrations_count': _toolIntegrations.length,
        },
      ));
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist data immediately for amnesia protection
  Future<void> _persistPersonalDataImmediately(Map<String, dynamic> data) async {
    try {
      final dataJson = jsonEncode(data);
      await _prefs.setString('personal_data_sync', dataJson);
      
      // Also save to multiple locations for redundancy
      await _prefs.setString('personal_data_backup_1', dataJson);
      await _prefs.setString('personal_data_backup_2', dataJson);
      
    } catch (e) {
      debugPrint('❌ Failed to persist personal data immediately: $e');
    }
  }
  
  /// Persist tool integrations
  Future<void> _persistToolIntegrations() async {
    try {
      final toolsJson = jsonEncode(_toolIntegrations.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('tool_integrations', toolsJson);
    } catch (e) {
      debugPrint('❌ Failed to persist tool integrations: $e');
    }
  }
  
  /// Load backup data for amnesia recovery
  Future<void> loadBackupData() async {
    try {
      // Try to load from backup locations
      final backup1 = _prefs.getString('personal_data_backup_1');
      final backup2 = _prefs.getString('personal_data_backup_2');
      
      if (backup1 != null && backup1!.isNotEmpty) {
        final data = jsonDecode(backup1) as Map;
        for (final entry in data.entries) {
          _personalData[entry.key] = entry.value;
        }
        
        _eventController.add(IntegrationEvent(
          type: IntegrationEventType.data_loaded,
          message: 'Backup data loaded from backup 1',
          data: {'backup_source': 'backup_1'},
        ));
      } else if (backup2 != null && backup2!.isNotEmpty) {
        final data = jsonDecode(backup2) as Map;
        for (final entry in data.entries) {
          _personalData[entry.key] = entry.value;
        }
        
        _eventController.add(IntegrationEvent(
          type: IntegrationEventType.data_loaded,
          message: 'Backup data loaded from backup 2',
          data: {'backup_source': 'backup_2'},
        ));
      }
    } catch (e) {
      debugPrint('❌ Failed to load backup data: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _syncTimer?.cancel();
    _commandFingerprint?.dispose();
    _performanceProfiles?.dispose();
    _resourceManager?.dispose();
    _errorCorrection?.dispose();
    _projectTemplates?.dispose();
    _backgroundProcessor?.dispose();
    _storageOptimizer?.dispose();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Tool integration
class ToolIntegration {
  final String name;
  final String description;
  final ToolType type;
  bool enabled;
  Map<String, dynamic> config;
  
  ToolIntegration({
    required this.name,
    required this.description,
    required this.type,
    required this.enabled,
    required this.config,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'type': type.toString(),
    'enabled': enabled,
    'config': config,
  };
  
  factory ToolIntegration.fromJson(Map<String, dynamic> json) {
    return ToolIntegration(
      name: json['name'],
      description: json['description'],
      type: ToolType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => ToolType.ai_agent,
      ),
      enabled: json['enabled'],
      config: Map<String, dynamic>.from(json['config']),
    );
  }
}

/// Tool types
enum ToolType {
  ai_agent,
  workflow_automation,
  cloud_storage,
  container_management,
}

/// Integration event types
enum IntegrationEventType {
  initialized,
  command_fingerprint_event,
  performance_event,
  resource_event,
  error_correction_event,
  template_event,
  background_event,
  storage_event,
  hermes_sync,
  n8n_sync,
  nextcloud_sync,
  tool_toggled,
  tool_configured,
  data_synced,
  data_loaded,
  error,
}

/// Integration event
class IntegrationEvent {
  final IntegrationEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  IntegrationEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
