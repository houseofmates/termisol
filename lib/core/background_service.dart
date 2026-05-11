import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service_registry.dart';
import 'robust_error_handler.dart';

/// Background service for system tray integration and auto-start functionality.
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;
  bool _minimizeToTray = true;
  bool _startOnBoot = false;
  bool _heartbeatEnabled = true;
  
  Timer? _heartbeatTimer;
  Timer? _statusCheckTimer;
  DateTime? _lastHeartbeat;
  
  static const String _channelName = 'com.termisol.background';
  static const MethodChannel _backgroundChannel = MethodChannel(_channelName);
  
  final _statusController = StreamController<ServiceStatus>.broadcast();
  Stream<ServiceStatus> get statusStream => _statusController.stream;
  
  final _trayController = StreamController<TrayAction>.broadcast();
  Stream<TrayAction> get trayEvents => _trayController.stream;

  bool get isInitialized => _isInitialized;
  bool get isRunning => _isRunning;
  bool get minimizeToTray => _minimizeToTray;
  bool get startOnBoot => _startOnBoot;
  DateTime? get lastHeartbeat => _lastHeartbeat;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadSettings();
      await _setupBackgroundChannel();
      
      if (_heartbeatEnabled) {
        _startHeartbeat();
      }
      
      _startStatusMonitoring();
      
      if (Platform.isLinux || Platform.isWindows) {
        await _setupSystemTray();
      }
      
      if (_startOnBoot) {
        await _configureAutoStart();
      }
      
      _isInitialized = true;
      _isRunning = true;
      _statusController.add(ServiceStatus.running);
      
      debugPrint('Background service initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize background service: $e\n$stack');
      await RobustErrorHandler().handleError(e, stack, context: 'Background Service Init');
      rethrow;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _minimizeToTray = prefs.getBool('termisol_minimize_to_tray') ?? true;
      _startOnBoot = prefs.getBool('termisol_start_on_boot') ?? false;
      _heartbeatEnabled = prefs.getBool('termisol_heartbeat_enabled') ?? true;
    } catch (e) {
      debugPrint('Failed to load background service settings: $e');
    }
  }

  Future<void> _setupBackgroundChannel() async {
    _backgroundChannel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'start_service':
            await startService();
            return true;
          case 'stop_service':
            await stopService();
            return true;
          case 'get_status':
            return _isRunning ? 'running' : 'stopped';
          case 'tray_action':
            final action = call.arguments as String?;
            if (action != null) {
              _handleTrayAction(action);
            }
            return true;
          case 'heartbeat':
            _lastHeartbeat = DateTime.now();
            return true;
          default:
            throw PlatformException(code: 'Unimplemented', message: 'Method not implemented');
        }
      } catch (e, stack) {
        await RobustErrorHandler().handleError(e, stack, context: 'Background Channel');
        rethrow;
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
    debugPrint('Heartbeat started');
  }

  void _sendHeartbeat() async {
    try {
      _lastHeartbeat = DateTime.now();
      await _backgroundChannel.invokeMethod('heartbeat', {
        'timestamp': _lastHeartbeat!.toIso8601String(),
        'status': _isRunning ? 'running' : 'stopped',
      });
    } catch (e) {
      debugPrint('Failed to send heartbeat: $e');
    }
  }

  void _startStatusMonitoring() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkServiceHealth();
    });
  }

  void _checkServiceHealth() {
    try {
      final now = DateTime.now();
      if (_lastHeartbeat != null && now.difference(_lastHeartbeat!) > const Duration(minutes: 2)) {
        debugPrint('Service heartbeat timeout detected');
        _statusController.add(ServiceStatus.unhealthy);
        _restartService();
      } else {
        _statusController.add(ServiceStatus.healthy);
      }
    } catch (e) {
      debugPrint('Health check failed: $e');
      _statusController.add(ServiceStatus.error);
    }
  }

  Future<void> _restartService() async {
    try {
      debugPrint('Restarting background service');
      await stopService();
      await Future.delayed(const Duration(seconds: 2));
      await startService();
    } catch (e, stack) {
      debugPrint('Failed to restart service: $e\n$stack');
      await RobustErrorHandler().handleError(e, stack, context: 'Service Restart');
    }
  }

  Future<void> _setupSystemTray() async {
    try {
      if (Platform.isLinux) {
        await _setupLinuxTray();
      } else if (Platform.isWindows) {
        await _setupWindowsTray();
      }
    } catch (e, stack) {
      debugPrint('Failed to setup system tray: $e\n$stack');
    }
  }

  Future<void> _setupLinuxTray() async {
    try {
      // Create tray icon file
      final appDir = await getApplicationDocumentsDirectory();
      final iconPath = '${appDir.path}/.termisol/tray_icon.png';
      
      // For Linux, we'll use a simple approach with AppIndicator
      await _backgroundChannel.invokeMethod('setup_tray', {
        'icon_path': iconPath,
        'tooltip': 'Termisol Terminal',
        'menu_items': [
          {'title': 'New Terminal', 'action': 'new_terminal'},
          {'title': 'Show Window', 'action': 'show_window'},
          {'title': 'Preferences', 'action': 'preferences'},
          {'title': '-', 'action': 'separator'},
          {'title': 'Quit', 'action': 'quit'},
        ],
      });
    } catch (e) {
      debugPrint('Linux tray setup failed: $e');
    }
  }

  Future<void> _setupWindowsTray() async {
    try {
      await windowManager.setSkipTaskbar(false);
      
      // Create system tray for Windows
      await _backgroundChannel.invokeMethod('setup_tray', {
        'tooltip': 'Termisol Terminal',
        'menu_items': [
          {'title': 'New Terminal', 'action': 'new_terminal'},
          {'title': 'Show Window', 'action': 'show_window'},
          {'title': 'Preferences', 'action': 'preferences'},
          {'title': '-', 'action': 'separator'},
          {'title': 'Quit', 'action': 'quit'},
        ],
      });
    } catch (e) {
      debugPrint('Windows tray setup failed: $e');
    }
  }

  void _handleTrayAction(String action) {
    debugPrint('Tray action: $action');
    
    switch (action) {
      case 'new_terminal':
        _trayController.add(TrayAction.newTerminal);
        break;
      case 'show_window':
        _trayController.add(TrayAction.showWindow);
        break;
      case 'preferences':
        _trayController.add(TrayAction.preferences);
        break;
      case 'quit':
        _trayController.add(TrayAction.quit);
        break;
    }
  }

  Future<void> _configureAutoStart() async {
    try {
      if (Platform.isLinux) {
        await _setupLinuxAutoStart();
      } else if (Platform.isWindows) {
        await _setupWindowsAutoStart();
      } else if (Platform.isMacOS) {
        await _setupMacOSAutoStart();
      }
    } catch (e, stack) {
      debugPrint('Failed to configure auto-start: $e\n$stack');
    }
  }

  Future<void> _setupLinuxAutoStart() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final autostartDir = Directory('${Platform.environment['HOME']}/.config/autostart');
      await autostartDir.create(recursive: true);
      
      final desktopFile = File('${autostartDir.path}/termisol.desktop');
      final executable = Platform.resolvedExecutable;
      
      final desktopContent = '''
[Desktop Entry]
Type=Application
Name=Termisol
Comment=Terminal emulator with AI integration
Exec=$executable --background
Icon=termisol
Terminal=false
Categories=System;TerminalEmulator;
X-GNOME-Autostart-enabled=true
NoDisplay=false
''';
      
      await desktopFile.writeAsString(desktopContent);
      debugPrint('Linux auto-start configured');
    } catch (e) {
      debugPrint('Linux auto-start setup failed: $e');
    }
  }

  Future<void> _setupWindowsAutoStart() async {
    try {
      await _backgroundChannel.invokeMethod('setup_autostart', {
        'app_name': 'Termisol',
        'executable': Platform.resolvedExecutable,
        'args': '--background',
      });
      debugPrint('Windows auto-start configured');
    } catch (e) {
      debugPrint('Windows auto-start setup failed: $e');
    }
  }

  Future<void> _setupMacOSAutoStart() async {
    try {
      await _backgroundChannel.invokeMethod('setup_autostart', {
        'app_name': 'Termisol',
        'bundle_id': 'com.termisol.app',
      });
      debugPrint('macOS auto-start configured');
    } catch (e) {
      debugPrint('macOS auto-start setup failed: $e');
    }
  }

  Future<void> startService() async {
    try {
      if (_isRunning) return;
      
      await _backgroundChannel.invokeMethod('start_service');
      _isRunning = true;
      _statusController.add(ServiceStatus.running);
      
      debugPrint('Background service started');
    } catch (e, stack) {
      debugPrint('Failed to start background service: $e\n$stack');
      await RobustErrorHandler().handleError(e, stack, context: 'Service Start');
      rethrow;
    }
  }

  Future<void> stopService() async {
    try {
      if (!_isRunning) return;
      
      _heartbeatTimer?.cancel();
      _statusCheckTimer?.cancel();
      
      await _backgroundChannel.invokeMethod('stop_service');
      _isRunning = false;
      _statusController.add(ServiceStatus.stopped);
      
      debugPrint('Background service stopped');
    } catch (e, stack) {
      debugPrint('Failed to stop background service: $e\n$stack');
      await RobustErrorHandler().handleError(e, stack, context: 'Service Stop');
    }
  }

  Future<void> minimizeToTrayAction() async {
    if (!_minimizeToTray) return;
    
    try {
      await windowManager.hide();
      debugPrint('Window minimized to tray');
    } catch (e, stack) {
      debugPrint('Failed to minimize to tray: $e\n$stack');
    }
  }

  Future<void> restoreFromTray() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      debugPrint('Window restored from tray');
    } catch (e, stack) {
      debugPrint('Failed to restore from tray: $e\n$stack');
    }
  }

  Future<void> updateSettings({
    bool? minimizeToTray,
    bool? startOnBoot,
    bool? heartbeatEnabled,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (minimizeToTray != null) {
        _minimizeToTray = minimizeToTray;
        await prefs.setBool('termisol_minimize_to_tray', minimizeToTray);
      }
      
      if (startOnBoot != null) {
        _startOnBoot = startOnBoot;
        await prefs.setBool('termisol_start_on_boot', startOnBoot);
        
        if (startOnBoot) {
          await _configureAutoStart();
        } else {
          await _removeAutoStart();
        }
      }
      
      if (heartbeatEnabled != null) {
        _heartbeatEnabled = heartbeatEnabled;
        await prefs.setBool('termisol_heartbeat_enabled', heartbeatEnabled);
        
        if (heartbeatEnabled && _isRunning) {
          _startHeartbeat();
        } else {
          _heartbeatTimer?.cancel();
        }
      }
      
      debugPrint('Background service settings updated');
    } catch (e, stack) {
      debugPrint('Failed to update settings: $e\n$stack');
    }
  }

  Future<void> _removeAutoStart() async {
    try {
      if (Platform.isLinux) {
        final autostartFile = File('${Platform.environment['HOME']}/.config/autostart/termisol.desktop');
        if (await autostartFile.exists()) {
          await autostartFile.delete();
        }
      } else {
        await _backgroundChannel.invokeMethod('remove_autostart');
      }
      debugPrint('Auto-start configuration removed');
    } catch (e) {
      debugPrint('Failed to remove auto-start: $e');
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
  }) async {
    try {
      await _backgroundChannel.invokeMethod('show_notification', {
        'title': title,
        'body': body,
        'icon': icon,
      });
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }

  Future<Map<String, dynamic>> getServiceInfo() async {
    return {
      'is_running': _isRunning,
      'is_initialized': _isInitialized,
      'last_heartbeat': _lastHeartbeat?.toIso8601String(),
      'minimize_to_tray': _minimizeToTray,
      'start_on_boot': _startOnBoot,
      'heartbeat_enabled': _heartbeatEnabled,
      'platform': Platform.operatingSystem,
    };
  }

  Future<void> dispose() async {
    try {
      _heartbeatTimer?.cancel();
      _statusCheckTimer?.cancel();
      await _statusController.close();
      await _trayController.close();
      
      if (_isRunning) {
        await stopService();
      }
      
      debugPrint('Background service disposed');
    } catch (e, stack) {
      debugPrint('Error disposing background service: $e\n$stack');
    }
  }
}

enum ServiceStatus {
  stopped,
  running,
  healthy,
  unhealthy,
  error,
}

enum TrayAction {
  newTerminal,
  showWindow,
  preferences,
  quit,
}

// Background isolate entry point
void _backgroundIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    try {
      if (message is Map<String, dynamic>) {
        final command = message['command'] as String;
        final response = await _handleBackgroundCommand(command, message['args']);
        sendPort.send({'success': true, 'data': response});
      }
    } catch (e) {
      sendPort.send({'success': false, 'error': e.toString()});
    }
  });
}

Future<dynamic> _handleBackgroundCommand(String command, dynamic args) async {
  switch (command) {
    case 'heartbeat':
      return {'timestamp': DateTime.now().toIso8601String()};
    case 'status':
      return {'status': 'running'};
    case 'ping':
      return 'pong';
    default:
      throw UnimplementedError('Unknown command: $command');
  }
}

// Utility class for managing background isolates
class BackgroundIsolateManager {
  static SendPort? _backgroundSendPort;
  static Isolate? _backgroundIsolate;

  static Future<void> startBackgroundIsolate() async {
    if (_backgroundIsolate != null) return;

    try {
      final receivePort = ReceivePort();
      _backgroundIsolate = await Isolate.spawn(_backgroundIsolateEntry, receivePort.sendPort);

      final completer = Completer<SendPort>();
      receivePort.listen((message) {
        if (message is SendPort) {
          completer.complete(message);
        }
      });

      _backgroundSendPort = await completer.future;
      debugPrint('Background isolate started');
    } catch (e, stack) {
      debugPrint('Failed to start background isolate: $e\n$stack');
    }
  }

  static Future<void> stopBackgroundIsolate() async {
    try {
      _backgroundIsolate?.kill(priority: Isolate.immediate);
      _backgroundIsolate = null;
      _backgroundSendPort = null;
      debugPrint('Background isolate stopped');
    } catch (e) {
      debugPrint('Failed to stop background isolate: $e');
    }
  }

  static Future<T?> sendBackgroundCommand<T>(String command, [dynamic args]) async {
    if (_backgroundSendPort == null) return null;

    try {
      final completer = Completer<Map<String, dynamic>>();
      final receivePort = ReceivePort();

      receivePort.listen((message) {
        if (message is Map<String, dynamic>) {
          completer.complete(message);
        }
      });

      _backgroundSendPort!.send({
        'command': command,
        'args': args,
        'response_port': receivePort.sendPort,
      });

      final response = await completer.future.timeout(const Duration(seconds: 5));
      return response['success'] == true ? response['data'] as T? : null;
    } catch (e) {
      debugPrint('Background command failed: $e');
      return null;
    }
  }
}