import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/headerbar_actions.dart';
import 'core/service_registry.dart';
import 'core/service_factories.dart';
import 'core/robust_error_handler.dart';
import 'core/termisol_core_integration.dart';

/// Setup global error handling and crash reporting
Future<void> _setupErrorHandling() async {
  await RobustErrorHandler().initialize();

  FlutterError.onError = (FlutterErrorDetails details) async {
    await RobustErrorHandler().handleError(
      details.exception,
      details.stack,
      context: 'Flutter Error',
    );
    _showErrorDialog(details.exceptionAsString());
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    RobustErrorHandler().handleError(
      error,
      stack,
      context: 'Platform Error',
    );
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
  } catch (e, stack) {
    debugPrint('failed to log error: $e\n$stack');
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

/// Entry point for termisol.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _setupErrorHandling();
  await TermisolCoreIntegration.instance.initialize();

  const headerBarChannel = MethodChannel('com.termisol/headerbar');
  headerBarChannel.setMethodCallHandler((call) async {
    if (call.method == 'headerbar_action') {
      final action = call.arguments as String?;
      if (action != null) HeaderbarActions.dispatch(action);
    }
  });

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();
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

  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  final registry = _registerServices();
  await registry.initializeCritical();

  if (kDebugMode) debugPrint('termisol started');
  runZonedGuarded(() {
    runApp(TermisolApp(registry: registry));
  }, (error, stackTrace) async {
    await _logError('Uncaught Error', error.toString(), stackTrace);
    _showErrorDialog(error.toString());
  });
}

/// Register services that are actually used in the working ui path.
ServiceRegistry _registerServices() {
  final r = ServiceRegistry.instance;

  r.register(TermisolFeatures.terminalCore, () => true);
  r.register(TermisolFeatures.aiAssistant, () => ServiceFactories.createAIAssistant());
  r.register(TermisolFeatures.productionConfigSystem, () => ServiceFactories.createConfigSystem());
  r.register(TermisolFeatures.fileManager, () => true);

  return r;
}
