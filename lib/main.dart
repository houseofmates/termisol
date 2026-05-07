import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/performance_enforcer.dart';
import 'core/production_gpu_renderer.dart';
import 'core/sub_16ms_latency_optimizer.dart';
import 'core/adaptive_frame_pacer.dart';
import 'ai/ai_terminal_assistant.dart';
import 'ai/nvidia_ai_terminal_assistant.dart';
import 'core/nvidia_ai_client.dart';
import 'config/production_config_system.dart';
import 'config/ssh_passcode_manager.dart';
// Existing core systems
import 'core/background_processor.dart';
import 'core/memory_optimizer.dart';
import 'core/network_resilience.dart';
import 'core/session_sync_manager.dart';
import 'core/llm_plugin_system.dart';
import 'ui/gnome_integration.dart';
// New imports for enhanced features
import 'core/smart_command_chaining.dart';
import 'core/semantic_search_engine.dart';
import 'core/enhanced_search_engine.dart';
import 'core/enhanced_ai_suggestions.dart';
import 'core/conversational_ai.dart';
import 'core/automated_workflows.dart';
import 'core/git_integration.dart';
import 'vr/advanced_vr_terminal.dart';
import 'core/github_integration.dart';
import 'core/neural_processing.dart';
import 'core/terminal_pane_manager.dart';
import 'core/plugin_ecosystem.dart';
// Newly integrated services
import 'core/audio_alert_service.dart';
import 'core/keyboard_macro_reader.dart';
import 'core/sync_services.dart';
import 'core/docker_operations.dart';
import 'core/integrated_debugger_nim.dart';
import 'core/task_runner.dart';
import 'core/configurable_hotkeys.dart';
import 'core/smooth_animations.dart';
import 'core/auto_backup_system.dart';
import 'core/auto_ssh_key_management.dart';
import 'core/multihop_ssh.dart';
import 'core/tunnel_management.dart';
import 'core/ssh_connection_persistence.dart';
import 'core/code_intelligence.dart';

/// entry point for termisol with production optimizations.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize production configuration system
  final configSystem = await ProductionConfigSystem.initialize();

  // load ssh passcode (asked once via home_screen if missing)
  await SshPasscodeManager().load();
  
  // Apply performance optimizations
  final perfConfig = configSystem.performance;
  if (perfConfig.hardwareAcceleration) {
    debugPrint('🚀 Hardware acceleration enabled');
  }

  // initialize window manager on desktop before runapp
  // on linux we only ensure initialization; the native gtk runner handles
  // window creation and showing to avoid conflicts with window_manager.
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();
    if (!Platform.isLinux) {
      const windowOptions = WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.black,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'termisol',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  // force hardware acceleration and optimal settings
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // enable high performance mode for optimal gpu utilization
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  debugPrint('🚀 starting termisol with production GPU acceleration');

  // Initialize core systems
  final backgroundProcessor = BackgroundProcessor();
  final memoryOptimizer = MemoryOptimizer();
  final networkResilience = NetworkResilience();
  final sessionSyncManager = SessionSyncManager();
  final llmPluginSystem = LLMPluginSystem();
  final gnomeIntegration = GnomeIntegration();

  await backgroundProcessor.initialize();
  await memoryOptimizer.initialize();
  await networkResilience.initialize();
  await sessionSyncManager.initialize();
  await llmPluginSystem.initialize();
  await gnomeIntegration.initialize();

  // start the sub-16ms performance enforcer
  final performanceEnforcer = PerformanceEnforcer();
  final gpuRenderer = ProductionGpuRenderer();
  final latencyOptimizer = Sub16msLatencyOptimizer();
  final framePacer = AdaptiveFramePacer();

  await gpuRenderer.initialize();
  await latencyOptimizer.initialize();
  framePacer.initialize();

  performanceEnforcer.start();

  // initialize ai systems
  final aiAssistant = AITerminalAssistant();
  final nvidiaAIClient = NvidiaAIClient();
  final nvidiaAIAssistant = NvidiaAITerminalAssistant(nvidiaAIClient);

  await aiAssistant.initialize();
  await nvidiaAIClient.initialize();
   await nvidiaAIAssistant.initialize();

   // Initialize enhanced features
  final smartCommandChaining = SmartCommandChaining();
  final enhancedSearchEngine = EnhancedSearchEngine();
  final semanticSearchEngine = SemanticSearchEngine(enhancedSearchEngine, aiAssistant);
  final enhancedAISuggestions = EnhancedAISuggestions(aiAssistant);
  final conversationalAI = ConversationalAI(aiAssistant, smartCommandChaining, semanticSearchEngine, enhancedAISuggestions);
  final automatedWorkflows = AutomatedWorkflowSystem(smartCommandChaining, conversationalAI);
  final advancedVRTerminal = AdvancedVRTerminal(
    conversationalAI: conversationalAI,
    workflowSystem: automatedWorkflows,
    aiSuggestions: enhancedAISuggestions,
    terminalWidget: const SizedBox(), // Placeholder, will be set in HomeScreen
  );
  final gitIntegration = GitIntegration();
  final githubIntegration = GitHubIntegration(gitIntegration, conversationalAI, semanticSearchEngine);
  final neuralProcessing = NeuralProcessingSystem(aiAssistant);
  final paneManager = TerminalPaneManager();
  final pluginManager = PluginManager(aiClient: nvidiaAIClient);

  // Initialize all new systems
  await Future.wait([
    backgroundProcessor.initialize(),
    memoryOptimizer.initialize(),
    networkResilience.initialize(),
    sessionSyncManager.initialize(),
    llmPluginSystem.initialize(),
    gnomeIntegration.initialize(),
    smartCommandChaining.initialize(),
    semanticSearchEngine.initialize(),
    enhancedAISuggestions.initialize(),
    conversationalAI.initialize(),
    automatedWorkflows.initialize(),
    githubIntegration.initialize(),
    neuralProcessing.initialize(),
    paneManager.initialize(),
    pluginManager.initialize(),
  ]);

  // Initialize newly integrated services
  final audioAlertService = AudioAlertService();
  final keyboardMacroReader = KeyboardMacroReader();
  final syncServices = SyncServices();
  final dockerOperations = DockerOperations();
  final integratedDebugger = IntegratedDebugger();
  final taskRunner = TaskRunner();
  final configurableHotkeys = ConfigurableHotkeys();
  final smoothAnimations = SmoothAnimations();
  final autoBackupSystem = AutoBackupSystem();
  final autoSshKeyManagement = AutoSSHKeyManagement();
  final multihopSsh = MultihopSSH();
  final tunnelManagement = TunnelManagement();
  final sshConnectionPersistence = SSHConnectionPersistence();
  final codeIntelligence = CodeIntelligence();

  await Future.wait([
    audioAlertService.initialize(),
    keyboardMacroReader.initialize(),
    integratedDebugger.initialize(),
    taskRunner.initialize(),
    configurableHotkeys.initialize(),
    smoothAnimations.initialize(),
    autoBackupSystem.initialize(),
    autoSshKeyManagement.initialize(),
    multihopSsh.initialize(),
    tunnelManagement.initialize(),
    sshConnectionPersistence.initialize(),
    codeIntelligence.initialize(),
  ]);
  syncServices.initialize();

  runApp(TermisolApp(
    aiAssistant: nvidiaAIAssistant,
    performanceEnforcer: performanceEnforcer,
    gpuRenderer: gpuRenderer,
    latencyOptimizer: latencyOptimizer,
    framePacer: framePacer,
    configSystem: configSystem,
    backgroundProcessor: backgroundProcessor,
    memoryOptimizer: memoryOptimizer,
    networkResilience: networkResilience,
    sessionSyncManager: sessionSyncManager,
    llmPluginSystem: llmPluginSystem,
    gnomeIntegration: gnomeIntegration,
    // Enhanced features
    smartCommandChaining: smartCommandChaining,
    semanticSearchEngine: semanticSearchEngine,
    enhancedAISuggestions: enhancedAISuggestions,
    conversationalAI: conversationalAI,
    automatedWorkflows: automatedWorkflows,
    advancedVRTerminal: advancedVRTerminal,
    githubIntegration: githubIntegration,
    neuralProcessing: neuralProcessing,
    paneManager: paneManager,
    pluginManager: pluginManager,
  ));
}
