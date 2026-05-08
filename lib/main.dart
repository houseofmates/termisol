import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/service_registry.dart';
import 'config/production_config_system.dart';
import 'config/ssh_passcode_manager.dart';

/// entry point for termisol with lazy-loading service registry.
/// critical services start immediately; everything else is on-demand.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configSystem = await ProductionConfigSystem.initialize();
  await SshPasscodeManager().load();

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

  final registry = _registerServices(configSystem);
  await registry.initializeCritical();

  debugPrint('🚀 termisol started (lazy init)');
  runApp(TermisolApp(registry: registry));
}

/// Register all services with lazy-loading factories.
/// None are created here — they instantiate on first use.
ServiceRegistry _registerServices(ProductionConfigSystem config) {
  final r = ServiceRegistry.instance;

  r.register(TermisolFeatures.terminalCore, () => true, enabled: true);

  r.register(TermisolFeatures.aiAssistant, () async {
    final ai = NvidiaAITerminalAssistant(NvidiaAIClient());
    await ai.initialize();
    return ai;
  }, enabled: config.ai.enabled, timeout: const Duration(seconds: 15));

  r.register(TermisolFeatures.performanceMonitoring, () {
    final enforcer = PerformanceEnforcer();
    enforcer.start();
    return enforcer;
  }, enabled: config.performance.hardwareAcceleration);

  r.register(TermisolFeatures.gpuRenderer, () async {
    final renderer = ProductionGpuRenderer();
    await renderer.initialize();
    return renderer;
  }, enabled: config.performance.gpuAcceleration, timeout: const Duration(seconds: 8));

  r.register(TermisolFeatures.gitIntegration, () => GitIntegration()..initialize(),
      enabled: config.gitIntegration);

  r.register(TermisolFeatures.dockerIntegration, () => DockerOperations()..initialize(),
      enabled: config.dockerIntegration);

  r.register(TermisolFeatures.databaseClient, () {
    final client = DatabaseClient();
    client.initialize();
    return client;
  }, enabled: config.databaseClient);

  r.register(TermisolFeatures.fileManager, () => true, enabled: true);

  r.register(TermisolFeatures.vrSupport, () => true, enabled: config.vrSupport);

  r.register(TermisolFeatures.videoPlayback, () => true,
      enabled: config.multimedia.videoPlayer);
  r.register(TermisolFeatures.audioVisualization, () => true,
      enabled: config.multimedia.audioVisualizer);
  r.register(TermisolFeatures.model3d, () => true,
      enabled: config.multimedia.model3dViewer);

  r.register(TermisolFeatures.sessionSync, () => SessionSyncManager()..initialize(),
      enabled: config.sessionSync);

  r.register(TermisolFeatures.sshExtras, () => SSHConnectionPersistence()..initialize(),
      enabled: config.ssh.enabled);

  r.register(TermisolFeatures.collaboration, () => true, enabled: config.collaboration);

  r.register(TermisolFeatures.plugins, () {
    return PluginManager(aiClient: NvidiaAIClient())..initialize();
  }, enabled: config.plugins);

  return r;
}
