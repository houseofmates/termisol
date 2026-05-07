import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ai/nvidia_ai_terminal_assistant.dart';
import 'config/production_config_system.dart';
import 'core/performance_enforcer.dart';
import 'core/production_gpu_renderer.dart';
import 'core/sub_16ms_latency_optimizer.dart';
import 'core/adaptive_frame_pacer.dart';
import 'core/background_processor.dart';
import 'core/memory_optimizer.dart';
import 'core/network_resilience.dart';
import 'core/session_sync_manager.dart';
import 'core/llm_plugin_system.dart';
import 'ui/gnome_integration.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
// New imports for enhanced features
import 'core/smart_command_chaining.dart';
import 'core/semantic_search_engine.dart';
import 'core/enhanced_ai_suggestions.dart';
import 'core/conversational_ai.dart';
import 'core/automated_workflows.dart';
import 'vr/advanced_vr_terminal.dart';
import 'core/github_integration.dart';
import 'core/neural_processing.dart';
import 'core/terminal_pane_manager.dart';
import 'core/plugin_ecosystem.dart';
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
import 'core/database_client.dart';
import 'core/session_recovery.dart';
import 'core/command_guard.dart';
import 'core/asciicast_recorder.dart';

/// root application widget for termisol with production optimizations and advanced features.
class TermisolApp extends StatelessWidget {
  final NvidiaAITerminalAssistant aiAssistant;
  final PerformanceEnforcer performanceEnforcer;
  final ProductionGpuRenderer gpuRenderer;
  final Sub16msLatencyOptimizer latencyOptimizer;
  final AdaptiveFramePacer framePacer;
  final ProductionConfigSystem configSystem;
  final BackgroundProcessor backgroundProcessor;
  final MemoryOptimizer memoryOptimizer;
  final NetworkResilience networkResilience;
  final SessionSyncManager sessionSyncManager;
  final LLMPluginSystem llmPluginSystem;
  final GnomeIntegration gnomeIntegration;
  // Enhanced features
  final SmartCommandChaining smartCommandChaining;
  final SemanticSearchEngine semanticSearchEngine;
  final EnhancedAISuggestions enhancedAISuggestions;
  final ConversationalAI conversationalAI;
  final AutomatedWorkflowSystem automatedWorkflows;
  final AdvancedVRTerminal advancedVRTerminal;
  final GitHubIntegration githubIntegration;
  final NeuralProcessingSystem neuralProcessing;
  final TerminalPaneManager paneManager;
  final PluginManager pluginManager;
  final AudioAlertService audioAlertService;
  final KeyboardMacroReader keyboardMacroReader;
  final SyncServices syncServices;
  final DockerOperations dockerOperations;
  final IntegratedDebugger integratedDebugger;
  final TaskRunner taskRunner;
  final ConfigurableHotkeys configurableHotkeys;
  final SmoothAnimations smoothAnimations;
  final AutoBackupSystem autoBackupSystem;
  final AutoSSHKeyManagement autoSshKeyManagement;
  final MultihopSSH multihopSsh;
  final TunnelManagement tunnelManagement;
  final SSHConnectionPersistence sshConnectionPersistence;
  final CodeIntelligence codeIntelligence;
  final DatabaseClient databaseClient;
  final SessionRecovery sessionRecovery;
  final CommandGuard commandGuard;
  final AsciicastRecorder asciicastRecorder;

  const TermisolApp({
    super.key,
    required this.aiAssistant,
    required this.performanceEnforcer,
    required this.gpuRenderer,
    required this.latencyOptimizer,
    required this.framePacer,
    required this.configSystem,
    required this.backgroundProcessor,
    required this.memoryOptimizer,
    required this.networkResilience,
    required this.sessionSyncManager,
    required this.llmPluginSystem,
    required this.gnomeIntegration,
    // Enhanced features
    required this.smartCommandChaining,
    required this.semanticSearchEngine,
    required this.enhancedAISuggestions,
    required this.conversationalAI,
    required this.automatedWorkflows,
    required this.advancedVRTerminal,
    required this.githubIntegration,
    required this.neuralProcessing,
    required this.paneManager,
    required this.pluginManager,
    required this.audioAlertService,
    required this.keyboardMacroReader,
    required this.syncServices,
    required this.dockerOperations,
    required this.integratedDebugger,
    required this.taskRunner,
    required this.configurableHotkeys,
    required this.smoothAnimations,
    required this.autoBackupSystem,
    required this.autoSshKeyManagement,
    required this.multihopSsh,
    required this.tunnelManagement,
    required this.sshConnectionPersistence,
    required this.codeIntelligence,
    required this.databaseClient,
    required this.sessionRecovery,
    required this.commandGuard,
    required this.asciicastRecorder,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.varelaRoundTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: PkmTheme.primary,
          secondary: PkmTheme.secondary,
          surface: PkmTheme.popup,
          surfaceContainerHighest: PkmTheme.tabActiveBg,
        ),
        scaffoldBackgroundColor: PkmTheme.background,
        textTheme: baseTextTheme,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: PkmTheme.popup,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: PkmTheme.popup,
        ),
      ),
      home: HomeScreen(
        aiAssistant: aiAssistant,
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
          audioAlertService: audioAlertService,
          keyboardMacroReader: keyboardMacroReader,
          syncServices: syncServices,
          dockerOperations: dockerOperations,
          integratedDebugger: integratedDebugger,
          taskRunner: taskRunner,
          configurableHotkeys: configurableHotkeys,
          smoothAnimations: smoothAnimations,
          autoBackupSystem: autoBackupSystem,
          autoSshKeyManagement: autoSshKeyManagement,
          multihopSsh: multihopSsh,
          tunnelManagement: tunnelManagement,
          sshConnectionPersistence: sshConnectionPersistence,
          codeIntelligence: codeIntelligence,
          databaseClient: databaseClient,
          sessionRecovery: sessionRecovery,
          commandGuard: commandGuard,
          asciicastRecorder: asciicastRecorder,
        ),
    );
  }
}
