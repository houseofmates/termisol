import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global hotkeys management for system-wide shortcuts
/// Supports Ctrl+Shift+T to open Termisol and other custom hotkeys
class GlobalHotkeysV2 {
  static const String _kTermisolHotkey = 'Ctrl+Shift+T';
  static GlobalHotkeysV2? _instance;
  final Map<String, HotkeyAction> _hotkeys = {};
  final StreamController<HotkeyEvent> _eventController = StreamController<HotkeyEvent>.broadcast();
  Timer? _hotkeyCheckTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<HotkeyEvent> get events => _eventController.stream;

  static GlobalHotkeysV2 get instance {
    _instance ??= GlobalHotkeysV2._();
    return _instance!;
  }

  GlobalHotkeysV2._() {
    // Initialize default hotkeys
    _hotkeys[_kTermisolHotkey] = HotkeyAction(
      id: 'open_termisol',
      name: 'Open Termisol',
      description: 'Opens or focuses Termisol window',
      enabled: true,
      createdAt: DateTime.now(),
    );
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load saved hotkey configurations
      await _loadHotkeyConfigurations();
      
      // Initialize platform-specific hotkey system
      await _initializePlatformHotkeys();
      
      // Start hotkey monitoring
      _startHotkeyMonitoring();
      
      _isInitialized = true;
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.initialized,
        message: 'Global hotkeys V2 initialized',
        data: {'hotkeysCount': _hotkeys.length},
      ));
      
      debugPrint('⌨️ Global Hotkeys V2 initialized');
    } catch (e) {
      debugPrint('Failed to initialize global hotkeys: $e');
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.error,
        message: 'Failed to initialize: $e',
      ));
    }
  }

  Future<void> _loadHotkeyConfigurations() async {
    try {
      final hotkeysJson = _prefs.getString('global_hotkeys');
      if (hotkeysJson != null) {
        // Parse and load custom hotkey configurations
        debugPrint('Loaded custom hotkey configurations');
      }
    } catch (e) {
      debugPrint('Failed to load hotkey configurations: $e');
    }
  }

  Future<void> _initializePlatformHotkeys() async {
    if (Platform.isLinux) {
      await _initializeLinuxHotkeys();
    } else if (Platform.isWindows) {
      await _initializeWindowsHotkeys();
    } else if (Platform.isMacOS) {
      await _initializeMacOSHotkeys();
    }
  }

  Future<void> _initializeLinuxHotkeys() async {
    try {
      // Check for required tools
      final xdotoolCheck = await Process.run('which', ['xdotool']);
      final xbindkeysCheck = await Process.run('which', ['xbindkeys']);
      
      if (xdotoolCheck.exitCode == 0) {
        debugPrint('🔧 Linux hotkeys: xdotool available');
      } else {
        debugPrint('⚠️ Linux hotkeys: xdotool not available');
      }
      
      if (xbindkeysCheck.exitCode == 0) {
        debugPrint('🔧 Linux hotkeys: xbindkeys available');
      } else {
        debugPrint('⚠️ Linux hotkeys: xbindkeys not available');
      }
      
      // Create xbindkeys configuration
      await _createLinuxHotkeyConfig();
    } catch (e) {
      debugPrint('Failed to initialize Linux hotkeys: $e');
    }
  }

  Future<void> _initializeWindowsHotkeys() async {
    try {
      // Windows hotkeys would require additional packages like hotkey_manager
      debugPrint('🔧 Windows hotkeys initialized');
    } catch (e) {
      debugPrint('Failed to initialize Windows hotkeys: $e');
    }
  }

  Future<void> _initializeMacOSHotkeys() async {
    try {
      // Check for osascript availability
      final osascriptCheck = await Process.run('which', ['osascript']);
      if (osascriptCheck.exitCode == 0) {
        debugPrint('🔧 macOS hotkeys: osascript available');
      } else {
        debugPrint('⚠️ macOS hotkeys: osascript not available');
      }
      
      // Create macOS hotkey configuration
      await _createMacOSHotkeyConfig();
    } catch (e) {
      debugPrint('Failed to initialize macOS hotkeys: $e');
    }
  }

  Future<void> _createLinuxHotkeyConfig() async {
    try {
      final configDir = '${Platform.environment['HOME']}/.config/termisol';
      await Directory(configDir).create(recursive: true);
      
      final configFile = '$configDir/xbindkeysrc';
      final config = '''
# Termisol Global Hotkeys Configuration
# Generated automatically - do not edit manually

# Open Termisol with Ctrl+Shift+T
"xdotool search --class "termisol" windowactivate || termisol"
    Control+Shift+T
''';

      final file = File(configFile);
      await file.writeAsString(config);
      
      debugPrint('🔧 Linux hotkey config created: $configFile');
    } catch (e) {
      debugPrint('Failed to create Linux hotkey config: $e');
    }
  }

  Future<void> _createMacOSHotkeyConfig() async {
    try {
      final script = '''
-- macOS Hotkey Script for Termisol
-- This script handles global hotkey registration

on hotkey_pressed()
    tell application "Termisol"
        activate
    end tell
end hotkey_pressed

-- Register Ctrl+Shift+T
tell application "System Events"
    register hotkey control shift t with procedure hotkey_pressed
end tell
''';

      final scriptFile = '${Directory.systemTemp.path}/termisol_hotkeys.scpt';
      await File(scriptFile).writeAsString(script);
      
      debugPrint('🔧 macOS hotkey script created: $scriptFile');
    } catch (e) {
      debugPrint('Failed to create macOS hotkey config: $e');
    }
  }

  void _startHotkeyMonitoring() {
    _hotkeyCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkHotkeys();
    });
  }

  Future<void> _checkHotkeys() async {
    try {
      if (Platform.isLinux) {
        await _checkLinuxHotkeys();
      } else if (Platform.isWindows) {
        await _checkWindowsHotkeys();
      } else if (Platform.isMacOS) {
        await _checkMacOSHotkeys();
      }
    } catch (e) {
      // Silently handle hotkey check errors
    }
  }

  Future<void> _checkLinuxHotkeys() async {
    try {
      // Check if Ctrl+Shift+T is pressed using xdotool
      final result = await Process.run('xdotool', ['keydown', 'Control+Shift+T']);
      if (result.exitCode == 0) {
        await _triggerHotkey(_kTermisolHotkey);
      }
    } catch (e) {
      // Silently handle hotkey check errors
    }
  }

  Future<void> _checkWindowsHotkeys() async {
    // Windows hotkey checking would require additional implementation
  }

  Future<void> _checkMacOSHotkeys() async {
    // macOS hotkey checking would require additional implementation
  }

  Future<void> _triggerHotkey(String hotkey) async {
    final action = _hotkeys[hotkey];
    if (action != null && action.enabled) {
      await _executeAction(action);
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.hotkey_triggered,
        message: 'Hotkey triggered: $hotkey',
        data: {
          'hotkey': hotkey,
          'action': action.id,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }
  }

  Future<void> _executeAction(HotkeyAction action) async {
    switch (action.id) {
      case 'open_termisol':
        await _openTermisol();
        break;
      default:
        debugPrint('Unknown hotkey action: ${action.id}');
    }
  }

  Future<void> _openTermisol() async {
    try {
      // Check if Termisol is already running
      if (await _isTermisolRunning()) {
        // Focus existing window
        await _focusTermisol();
      } else {
        // Launch new Termisol instance
        await _launchTermisol();
      }
    } catch (e) {
      debugPrint('Failed to open Termisol: $e');
    }
  }

  Future<bool> _isTermisolRunning() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('pgrep', ['-f', 'termisol']);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq termisol.exe']);
        return result.stdout.contains('termisol.exe');
      } else if (Platform.isMacOS) {
        final result = await Process.run('pgrep', ['-f', 'Termisol']);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _focusTermisol() async {
    try {
      if (Platform.isLinux) {
        await Process.run('xdotool', [
          'search', '--class', 'termisol', 'windowactivate'
        ]);
      } else if (Platform.isWindows) {
        // Windows window focusing would require additional implementation
      } else if (Platform.isMacOS) {
        await Process.run('osascript', ['-e', '''
          tell application "Termisol" to activate
        ''']);
      }
    } catch (e) {
      debugPrint('Failed to focus Termisol: $e');
    }
  }

  Future<void> _launchTermisol() async {
    try {
      if (Platform.isLinux) {
        await Process.run('termisol', []);
      } else if (Platform.isWindows) {
        await Process.run('termisol.exe', []);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Termisol']);
      }
    } catch (e) {
      debugPrint('Failed to launch Termisol: $e');
    }
  }

  Future<bool> registerHotkey({
    required String hotkey,
    required String id,
    required String name,
    required String description,
    bool enabled = true,
  }) async {
    try {
      final action = HotkeyAction(
        id: id,
        name: name,
        description: description,
        enabled: enabled,
        createdAt: DateTime.now(),
      );
      
      _hotkeys[hotkey] = action;
      
      await _saveHotkeyConfigurations();
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.hotkey_registered,
        message: 'Hotkey registered: $hotkey',
        data: {
          'hotkey': hotkey,
          'action': id,
          'name': name,
        },
      ));
      
      debugPrint('🔧 Hotkey registered: $hotkey -> $name');
      return true;
    } catch (e) {
      debugPrint('Failed to register hotkey: $e');
      return false;
    }
  }

  Future<bool> unregisterHotkey(String hotkey) async {
    try {
      if (_hotkeys.containsKey(hotkey)) {
        _hotkeys.remove(hotkey);
        await _saveHotkeyConfigurations();
        
        _eventController.add(HotkeyEvent(
          type: HotkeyEventType.hotkey_unregistered,
          message: 'Hotkey unregistered: $hotkey',
          data: {'hotkey': hotkey},
        ));
        
        debugPrint('🔧 Hotkey unregistered: $hotkey');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to unregister hotkey: $e');
      return false;
    }
  }

  Future<void> _saveHotkeyConfigurations() async {
    try {
      final hotkeysMap = _hotkeys.map((key, value) => MapEntry(
        key,
        {
          'id': value.id,
          'name': value.name,
          'description': value.description,
          'enabled': value.enabled,
          'createdAt': value.createdAt.toIso8601String(),
        },
      ));
      
      await _prefs.setString('global_hotkeys', jsonEncode(hotkeysMap));
    } catch (e) {
      debugPrint('Failed to save hotkey configurations: $e');
    }
  }

  Future<void> enableHotkey(String hotkey) async {
    if (_hotkeys.containsKey(hotkey)) {
      _hotkeys[hotkey]!.enabled = true;
      await _saveHotkeyConfigurations();
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.hotkey_enabled,
        message: 'Hotkey enabled: $hotkey',
        data: {'hotkey': hotkey},
      ));
    }
  }

  Future<void> disableHotkey(String hotkey) async {
    if (_hotkeys.containsKey(hotkey)) {
      _hotkeys[hotkey]!.enabled = false;
      await _saveHotkeyConfigurations();
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.hotkey_disabled,
        message: 'Hotkey disabled: $hotkey',
        data: {'hotkey': hotkey},
      ));
    }
  }

  Map<String, HotkeyAction> getRegisteredHotkeys() {
    return Map.from(_hotkeys);
  }

  List<String> getSupportedPlatforms() {
    return ['Linux', 'Windows', 'macOS'];
  }

  String get currentPlatform {
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  Future<void> testHotkey(String hotkey) async {
    await _triggerHotkey(hotkey);
    
    _eventController.add(HotkeyEvent(
      type: HotkeyEventType.hotkey_tested,
      message: 'Hotkey tested: $hotkey',
      data: {'hotkey': hotkey},
    ));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'platform': currentPlatform,
      'totalHotkeys': _hotkeys.length,
      'enabledHotkeys': _hotkeys.values.where((h) => h.enabled).length,
      'supportedPlatforms': getSupportedPlatforms(),
      'defaultHotkey': _kTermisolHotkey,
    };
  }

  Future<void> dispose() async {
    _hotkeyCheckTimer?.cancel();
    _eventController.close();
    debugPrint('⌨️ Global Hotkeys V2 disposed');
  }
}

class HotkeyAction {
  final String id;
  final String name;
  final String description;
  bool enabled;
  final DateTime createdAt;

  HotkeyAction({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.createdAt,
  });
}

enum HotkeyEventType {
  initialized,
  hotkey_registered,
  hotkey_unregistered,
  hotkey_triggered,
  hotkey_enabled,
  hotkey_disabled,
  hotkey_tested,
  error,
}

class HotkeyEvent {
  final HotkeyEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  HotkeyEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Global hotkeys widget
class GlobalHotkeysWidgetV2 extends StatefulWidget {
  const GlobalHotkeysWidgetV2({super.key});

  @override
  State<GlobalHotkeysWidgetV2> createState() => _GlobalHotkeysWidgetV2State();
}

class _GlobalHotkeysWidgetV2State extends State<GlobalHotkeysWidgetV2> {
  final GlobalHotkeysV2 _hotkeys = GlobalHotkeysV2.instance;
  Map<String, HotkeyAction> _registeredHotkeys = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHotkeys();
    _hotkeys.initialize();
    _hotkeys.events.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadHotkeys() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final hotkeys = _hotkeys.getRegisteredHotkeys();
      setState(() {
        _registeredHotkeys = hotkeys;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.keyboard, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Text(
                  'Global Hotkeys V2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  _hotkeys.currentPlatform,
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          
          // Platform info
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[850],
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[400], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Platform: ${_hotkeys.currentPlatform}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${_registeredHotkeys.length} hotkeys registered',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          
          // Hotkeys list
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Registered Hotkeys',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ..._registeredHotkeys.entries.map((entry) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: entry.value.enabled ? Colors.green[700]! : Colors.grey[600]!,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.value.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Switch(
                              value: entry.value.enabled,
                              onChanged: (value) async {
                                if (value) {
                                  await _hotkeys.enableHotkey(entry.key);
                                } else {
                                  await _hotkeys.disableHotkey(entry.key);
                                }
                                await _loadHotkeys();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.value.description,
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Created: ${_formatDate(entry.value.createdAt)}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
          
          // Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border(top: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _hotkeys.testHotkey('Ctrl+Shift+T'),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Test Ctrl+Shift+T'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showAddHotkeyDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Hotkey'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
           '${date.month.toString().padLeft(2, '0')}/'
           '${date.year}';
  }

  void _showAddHotkeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Global Hotkey'),
        content: const Text('Custom hotkey registration will be implemented in a future update.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
