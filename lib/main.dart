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

/// Setup global error handling and crash reporting
Future<void> _setupErrorHandling() async {
  // Handle Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) async {
    await _logError('Flutter Error', details.exceptionAsString(), details.stack);
    _showErrorDialog(details.exceptionAsString());
  };

  // Handle platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('Platform Error', error.toString(), stack);
    _showErrorDialog(error.toString());
    return true;
  };
}

/// Log error to local file
Future<void> _logError(String type, String error, StackTrace? stack) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final logFile = File('${directory.path}/termisol_crash_log.txt');

    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '''
[$timestamp] $type:
Error: $error
Stack Trace:
${stack ?? 'No stack trace available'}

---
''';

    await logFile.writeAsString(logEntry, mode: FileMode.append);
  } catch (e) {
    // If logging fails, at least print to console
    debugPrint('Failed to log error: $e');
  }
}

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

  debugPrint('🚀 termisol started (lazy init)');
  runZonedGuarded(() {
    runApp(TermisolApp(registry: registry));
  }, (error, stackTrace) async {
    await _logError('Uncaught Error', error.toString(), stackTrace);
    _showErrorDialog(error.toString());
  });
}

/// Register all services with lazy-loading factories.
/// None are created here — they instantiate on first use.
/// Feature flags default to true if config properties are missing.
ServiceRegistry _registerServices() {
  final r = ServiceRegistry.instance;

  r.register(TermisolFeatures.terminalCore, () => true, enabled: true);
  r.register(TermisolFeatures.aiAssistant, () => true, enabled: true);
  r.register(TermisolFeatures.performanceMonitoring, () => true, enabled: true);
  r.register(TermisolFeatures.gpuRenderer, () => true, enabled: true);
  r.register(TermisolFeatures.gitIntegration, () => true, enabled: true);
  r.register(TermisolFeatures.dockerIntegration, () => true, enabled: true);
  r.register(TermisolFeatures.databaseClient, () => true, enabled: true);
  r.register(TermisolFeatures.fileManager, () => true, enabled: true);
  r.register(TermisolFeatures.vrSupport, () => true, enabled: true);
  r.register(TermisolFeatures.videoPlayback, () => true, enabled: true);
  r.register(TermisolFeatures.audioVisualization, () => true, enabled: true);
  r.register(TermisolFeatures.model3d, () => true, enabled: true);
  r.register(TermisolFeatures.sessionSync, () => true, enabled: true);
  r.register(TermisolFeatures.sshExtras, () => true, enabled: true);
  r.register(TermisolFeatures.collaboration, () => true, enabled: true);
  r.register(TermisolFeatures.plugins, () => true, enabled: true);

  return r;
}
