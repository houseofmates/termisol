import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await _initSystemTray();
        await _setupAutoStart();
      }

      _isInitialized = true;
      debugPrint('Background Service initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize Background Service: $e\n$stack');
    }
  }

  Future<void> _initSystemTray() async {
    try {
      final SystemTray systemTray = SystemTray();

      await systemTray.initSystemTray(
        title: 'termisol',
        iconPath: Platform.isWindows ? 'assets/icons/app_icon.ico' : 'assets/icons/app_icon.png',
      );

      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: 'New Tab',
          onClicked: (menuItem) {
            debugPrint('New Tab clicked from system tray');
            // Integration with app to open new tab
          },
        ),
        MenuItemLabel(
          label: 'Restore Session',
          onClicked: (menuItem) {
            debugPrint('Restore Session clicked from system tray');
            // Integration with app to restore session
          },
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Quit',
          onClicked: (menuItem) {
            exit(0);
          },
        ),
      ]);

      await systemTray.setContextMenu(menu);

      systemTray.registerSystemTrayEventHandler((eventName) {
        debugPrint('System tray event: $eventName');
        if (eventName == kSystemTrayEventClick) {
          Platform.isWindows ? systemTray.popUpContextMenu() : systemTray.popUpContextMenu();
        } else if (eventName == kSystemTrayEventRightClick) {
          Platform.isWindows ? systemTray.popUpContextMenu() : systemTray.popUpContextMenu();
        }
      });
    } catch (e, stack) {
      debugPrint('Failed to initialize System Tray: $e\n$stack');
    }
  }

  Future<void> _setupAutoStart() async {
    try {
      if (Platform.isLinux) {
        final autostartDir = Directory('${Platform.environment['HOME']}/.config/autostart');
        if (!await autostartDir.exists()) {
          await autostartDir.create(recursive: true);
        }

        final desktopFile = File('${autostartDir.path}/termisol.desktop');
        if (!await desktopFile.exists()) {
          const content = '''[Desktop Entry]
Type=Application
Exec=termisol
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Termisol Background Service
Comment=Starts Termisol in the background
''';
          await desktopFile.writeAsString(content);
          debugPrint('Created Linux autostart desktop file.');
        }
      } else if (Platform.isWindows) {
        // Example implementation for Windows can use a registry edit script or shortcut in Startup folder
        debugPrint('Windows auto-start logic would be implemented here.');
      } else if (Platform.isMacOS) {
         // Example implementation for MacOS can use a launchd plist
         debugPrint('MacOS auto-start logic would be implemented here.');
      }
    } catch (e, stack) {
      debugPrint('Failed to setup Auto Start: $e\n$stack');
    }
  }
}
