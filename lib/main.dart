import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/service_registry.dart';
import 'core/service_factories.dart';
import 'core/adaptive_rendering_system.dart';

/// Setup global error handling and crash reporting
Future<void> _setupErrorHandling() async {
  // Handle Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) async {
    await _logError('Flutter Error', details.exceptionAsString(), details.stack);
    _reportErrorToUser(details.exceptionAsString());
  };

  // Handle platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('Platform Error', error.toString(), stack);
    _reportErrorToUser(error.toString());
    return true;
  };
}

import 'dart:convert';

/// Global error state
class ErrorReporter {
  static String? currentError;
  static VoidCallback? onErrorChanged;

  static void reportError(String error) {
    currentError = error;
    onErrorChanged?.call();
  }

  static void clearError() {
    currentError = null;
    onErrorChanged?.call();
  }
}

/// Show user-friendly error dialog
void _showErrorDialog(String error) {
  ErrorReporter.reportError(error);
}

/// entry point for termisol with lazy-loading service registry.
/// critical services start immediately; everything else is on-demand.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup global error handling
  await _setupErrorHandling();

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

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final registry = _registerServices();
  await registry.initializeCritical();

  // Initialize adaptive rendering system for multi-device optimization
  await AdaptiveRenderingSystem.instance.initialize();

  debugPrint('🚀 termisol started (lazy init)');
  runZonedGuarded(() {
    runApp(TermisolApp(registry: registry));
  }, (error, stackTrace) async {
    await _logError('Uncaught Error', error.toString(), stackTrace);
    _showErrorDialog(error.toString());
  });
}

/// Register all services with real implementations.
/// Services are created lazily on first use for better performance.
ServiceRegistry _registerServices() {
  final r = ServiceRegistry.instance;

  // Core terminal features
  r.register(TermisolFeatures.terminalCore, () => true);
  
  // AI and performance features
  r.register(TermisolFeatures.aiAssistant, () => ServiceFactories.createAIAssistant());
  r.register(TermisolFeatures.performanceMonitoring, () => ServiceFactories.createPerformanceEnforcer());
  r.register(TermisolFeatures.gpuRenderer, () => ServiceFactories.createGpuRenderer());
  r.register(TermisolFeatures.sub16msLatencyOptimizer, () => ServiceFactories.createLatencyOptimizer());
  r.register(TermisolFeatures.adaptiveFramePacer, () => ServiceFactories.createFramePacer());
  r.register(TermisolFeatures.productionConfigSystem, () => ServiceFactories.createConfigSystem());
  r.register(TermisolFeatures.backgroundProcessor, () => ServiceFactories.createBackgroundProcessor());
  r.register(TermisolFeatures.memoryOptimizer, () => ServiceFactories.createMemoryOptimizer());
  r.register(TermisolFeatures.networkResilience, () => ServiceFactories.createNetworkResilience());
  
  // Advanced features
  r.register(TermisolFeatures.sessionSync, () => ServiceFactories.createSessionSyncManager());
  r.register(TermisolFeatures.llmPluginSystem, () => ServiceFactories.createLLMPluginSystem());
  r.register(TermisolFeatures.gnomeIntegration, () => ServiceFactories.createGnomeIntegration());
  r.register(TermisolFeatures.smartCommandChaining, () => ServiceFactories.createSmartCommandChaining());
  r.register(TermisolFeatures.semanticSearchEngine, () => ServiceFactories.createSemanticSearchEngine());
  r.register(TermisolFeatures.enhancedAISuggestions, () => ServiceFactories.createEnhancedAISuggestions());
  r.register(TermisolFeatures.conversationalAI, () => ServiceFactories.createConversationalAI());
  r.register(TermisolFeatures.automatedWorkflows, () => ServiceFactories.createAutomatedWorkflowSystem());
  r.register(TermisolFeatures.vrSupport, () => ServiceFactories.createAdvancedVRTerminal());
  
  // Integration features
  r.register(TermisolFeatures.gitIntegration, () => ServiceFactories.createGitHubIntegration());
  r.register(TermisolFeatures.neuralProcessing, () => ServiceFactories.createNeuralProcessingSystem());
  r.register(TermisolFeatures.terminalPaneManager, () => ServiceFactories.createPaneManager());
  r.register(TermisolFeatures.plugins, () => ServiceFactories.createPluginManager());
  r.register(TermisolFeatures.audioAlertService, () => ServiceFactories.createAudioAlertService());
  r.register(TermisolFeatures.keyboardMacroReader, () => ServiceFactories.createKeyboardMacroReader());
  r.register(TermisolFeatures.syncServices, () => ServiceFactories.createSyncServices());
  
  // Development and operations features
  r.register(TermisolFeatures.dockerIntegration, () => ServiceFactories.createDockerOperations());
  r.register(TermisolFeatures.integratedDebugger, () => ServiceFactories.createIntegratedDebugger());
  r.register(TermisolFeatures.taskRunner, () => ServiceFactories.createTaskRunner());
  r.register(TermisolFeatures.configurableHotkeys, () => ServiceFactories.createConfigurableHotkeys());
  r.register(TermisolFeatures.smoothAnimations, () => ServiceFactories.createSmoothAnimations());
  r.register(TermisolFeatures.autoBackupSystem, () => ServiceFactories.createAutoBackupSystem());
   r.register(TermisolFeatures.autoSshKeyManagement, () => ServiceFactories.createAutoSSHKeyManagement());
   r.register(TermisolFeatures.multihopSsh, () => ServiceFactories.createMultihopSSH());
   r.register(TermisolFeatures.tunnelManagement, () => ServiceFactories.createTunnelManagement());
   r.register(TermisolFeatures.sshConnectionPersistence, () => ServiceFactories.createSSHConnectionPersistence());
  r.register(TermisolFeatures.codeIntelligence, () => ServiceFactories.createCodeIntelligence());
  r.register(TermisolFeatures.databaseClient, () => ServiceFactories.createDatabaseClient());
  r.register(TermisolFeatures.sessionRecovery, () => ServiceFactories.createSessionRecovery());
  r.register(TermisolFeatures.commandGuard, () => ServiceFactories.createCommandGuard());
  r.register(TermisolFeatures.asciicastRecorder, () => ServiceFactories.createAsciicastRecorder());
  
  // Content and media features
  r.register(TermisolFeatures.fileManager, () => true);
  r.register(TermisolFeatures.videoPlayback, () => true);
  r.register(TermisolFeatures.audioVisualization, () => true);
  r.register(TermisolFeatures.model3d, () => true);
  
  // Protocol and rendering features
  r.register(TermisolFeatures.advancedTerminalProtocol, () => ServiceFactories.createAdvancedTerminalProtocol());
  r.register(TermisolFeatures.adaptiveCompressionNetwork, () => ServiceFactories.createAdaptiveCompressionNetwork());

  return r;
}
