import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Custom Shortcuts and Keybind Configuration System
/// 
/// Comprehensive keyboard shortcut management with:
/// - Custom keybind configuration
/// - Action mapping and execution
/// - Context-aware shortcuts
/// - Import/export of shortcut configurations
/// - Conflict detection and resolution
class CustomShortcuts {
  static final CustomShortcuts _instance = CustomShortcuts._internal();
  factory CustomShortcuts() => _instance;
  CustomShortcuts._internal();

  bool _isInitialized = false;
  
  // Shortcut storage
  final Map<String, Shortcut> _shortcuts = {};
  final Map<KeyCombination, List<Shortcut>> _keyBindings = {};
  final List<ShortcutProfile> _profiles = [];
  ShortcutProfile? _activeProfile;
  
  // Action registry
  final Map<String, ShortcutAction> _actions = {};
  
  // Event system
  final _shortcutController = StreamController<ShortcutEvent>.broadcast();
  Stream<ShortcutEvent> get events => _shortcutController.stream;
  
  // Configuration
  Directory? _configDir;
  static const String _defaultConfigFile = 'shortcuts.json';
  static const String _profilesFile = 'shortcut_profiles.json';
  
  bool get isInitialized => _isInitialized;
  int get totalShortcuts => _shortcuts.length;
  ShortcutProfile? get activeProfile => _activeProfile;
  List<ShortcutProfile> get profiles => List.unmodifiable(_profiles);

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup directories
      await _setupDirectories();
      
      // Register built-in actions
      await _registerBuiltInActions();
      
      // Load shortcuts configuration
      await _loadShortcuts();
      
      // Load profiles
      await _loadProfiles();
      
      // Setup keyboard listener
      _setupKeyboardListener();
      
      _isInitialized = true;
      debugPrint('⌨️ Custom Shortcuts initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Custom Shortcuts: $e');
    }
  }

  Future<void> _setupDirectories() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      _configDir = Directory('$homeDir/.termisol/shortcuts');
      await _configDir!.create(recursive: true);
      
      debugPrint('📁 Shortcuts directory created');
    } catch (e) {
      debugPrint('❌ Failed to setup directories: $e');
      rethrow;
    }
  }

  Future<void> _registerBuiltInActions() async {
    // Register built-in actions
    _actions.addAll({
      'new_terminal': ShortcutAction(
        id: 'new_terminal',
        name: 'New Terminal',
        description: 'Create a new terminal session',
        category: ActionCategory.terminal,
        icon: 'add',
      ),
      'close_terminal': ShortcutAction(
        id: 'close_terminal',
        name: 'Close Terminal',
        description: 'Close current terminal session',
        category: ActionCategory.terminal,
        icon: 'close',
      ),
      'copy': ShortcutAction(
        id: 'copy',
        name: 'Copy',
        description: 'Copy selected text',
        category: ActionCategory.editing,
        icon: 'copy',
      ),
      'paste': ShortcutAction(
        id: 'paste',
        name: 'Paste',
        description: 'Paste clipboard content',
        category: ActionCategory.editing,
        icon: 'paste',
      ),
      'search': ShortcutAction(
        id: 'search',
        name: 'Search',
        description: 'Open universal search',
        category: ActionCategory.navigation,
        icon: 'search',
      ),
      'command_palette': ShortcutAction(
        id: 'command_palette',
        name: 'Command Palette',
        description: 'Open command palette',
        category: ActionCategory.navigation,
        icon: 'terminal',
      ),
      'toggle_fullscreen': ShortcutAction(
        id: 'toggle_fullscreen',
        name: 'Toggle Fullscreen',
        description: 'Toggle fullscreen mode',
        category: ActionCategory.view,
        icon: 'fullscreen',
      ),
      'zoom_in': ShortcutAction(
        id: 'zoom_in',
        name: 'Zoom In',
        description: 'Increase terminal font size',
        category: ActionCategory.view,
        icon: 'zoom_in',
      ),
      'zoom_out': ShortcutAction(
        id: 'zoom_out',
        name: 'Zoom Out',
        description: 'Decrease terminal font size',
        category: ActionCategory.view,
        icon: 'zoom_out',
      ),
      'reset_zoom': ShortcutAction(
        id: 'reset_zoom',
        name: 'Reset Zoom',
        description: 'Reset terminal font size to default',
        category: ActionCategory.view,
        icon: 'zoom_reset',
      ),
      'next_tab': ShortcutAction(
        id: 'next_tab',
        name: 'Next Tab',
        description: 'Switch to next tab',
        category: ActionCategory.navigation,
        icon: 'next_tab',
      ),
      'previous_tab': ShortcutAction(
        id: 'previous_tab',
        name: 'Previous Tab',
        description: 'Switch to previous tab',
        category: ActionCategory.navigation,
        icon: 'previous_tab',
      ),
      'new_tab': ShortcutAction(
        id: 'new_tab',
        name: 'New Tab',
        description: 'Create a new tab',
        category: ActionCategory.terminal,
        icon: 'new_tab',
      ),
      'split_horizontal': ShortcutAction(
        id: 'split_horizontal',
        name: 'Split Horizontal',
        description: 'Split terminal horizontally',
        category: ActionCategory.layout,
        icon: 'split_h',
      ),
      'split_vertical': ShortcutAction(
        id: 'split_vertical',
        name: 'Split Vertical',
        description: 'Split terminal vertically',
        category: ActionCategory.layout,
        icon: 'split_v',
      ),
      'toggle_recording': ShortcutAction(
        id: 'toggle_recording',
        name: 'Toggle Recording',
        description: 'Start/stop terminal recording (Ctrl+P)',
        category: ActionCategory.recording,
        icon: 'record',
      ),
      'clear_terminal': ShortcutAction(
        id: 'clear_terminal',
        name: 'Clear Terminal',
        description: 'Clear terminal screen',
        category: ActionCategory.terminal,
        icon: 'clear',
      ),
      'find_in_terminal': ShortcutAction(
        id: 'find_in_terminal',
        name: 'Find in Terminal',
        description: 'Search within terminal output',
        category: ActionCategory.search,
        icon: 'find',
      ),
      'open_settings': ShortcutAction(
        id: 'open_settings',
        name: 'Open Settings',
        description: 'Open Termisol settings',
        category: ActionCategory.application,
        icon: 'settings',
      ),
      'quit': ShortcutAction(
        id: 'quit',
        name: 'Quit',
        description: 'Quit Termisol',
        category: ActionCategory.application,
        icon: 'exit',
      ),
    });
    
    debugPrint('⌨️ Registered ${_actions.length} built-in actions');
  }

  Future<void> _loadShortcuts() async {
    try {
      final configFile = File('${_configDir!.path}/$_defaultConfigFile');
      if (!await configFile.exists()) {
        await _createDefaultShortcuts();
        return;
      }
      
      final content = await configFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      for (final entry in (data['shortcuts'] as List)) {
        final shortcut = Shortcut.fromJson(entry);
        _shortcuts[shortcut.id] = shortcut;
        
        // Update key bindings
        for (final keyCombo in shortcut.keyCombinations) {
          _keyBindings.putIfAbsent(keyCombo, () => []).add(shortcut);
        }
      }
      
      debugPrint('⌨️ Loaded ${_shortcuts.length} shortcuts');
    } catch (e) {
      debugPrint('⚠️ Failed to load shortcuts: $e');
      await _createDefaultShortcuts();
    }
  }

  Future<void> _createDefaultShortcuts() async {
    final defaultShortcuts = [
      Shortcut(
        id: 'default_new_terminal',
        actionId: 'new_terminal',
        name: 'New Terminal',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.t]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_close_terminal',
        actionId: 'close_terminal',
        name: 'Close Terminal',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.w]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_copy',
        actionId: 'copy',
        name: 'Copy',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyC]),
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.insert]),
        ],
        enabled: true,
        context: ShortcutContext.terminal,
      ),
      Shortcut(
        id: 'default_paste',
        actionId: 'paste',
        name: 'Paste',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyV]),
          KeyCombination([LogicalKeyboardKey.shift, LogicalKeyboardKey.insert]),
        ],
        enabled: true,
        context: ShortcutContext.terminal,
      ),
      Shortcut(
        id: 'default_search',
        actionId: 'search',
        name: 'Search',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyF]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_command_palette',
        actionId: 'command_palette',
        name: 'Command Palette',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyP]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_toggle_fullscreen',
        actionId: 'toggle_fullscreen',
        name: 'Toggle Fullscreen',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.f11]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_zoom_in',
        actionId: 'zoom_in',
        name: 'Zoom In',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.equal]),
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.plus]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_zoom_out',
        actionId: 'zoom_out',
        name: 'Zoom Out',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.minus]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_reset_zoom',
        actionId: 'reset_zoom',
        name: 'Reset Zoom',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.digit0]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_next_tab',
        actionId: 'next_tab',
        name: 'Next Tab',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.tab]),
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.pageDown]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_previous_tab',
        actionId: 'previous_tab',
        name: 'Previous Tab',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.tab]),
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.pageUp]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_new_tab',
        actionId: 'new_tab',
        name: 'New Tab',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.t]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_toggle_recording',
        actionId: 'toggle_recording',
        name: 'Toggle Recording',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyP]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_clear_terminal',
        actionId: 'clear_terminal',
        name: 'Clear Terminal',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyL]),
        ],
        enabled: true,
        context: ShortcutContext.terminal,
      ),
      Shortcut(
        id: 'default_find_in_terminal',
        actionId: 'find_in_terminal',
        name: 'Find in Terminal',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyF]),
        ],
        enabled: true,
        context: ShortcutContext.terminal,
      ),
      Shortcut(
        id: 'default_open_settings',
        actionId: 'open_settings',
        name: 'Open Settings',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.comma]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
      Shortcut(
        id: 'default_quit',
        actionId: 'quit',
        name: 'Quit',
        keyCombinations: [
          KeyCombination([LogicalKeyboardKey.control, LogicalKeyboardKey.keyQ]),
        ],
        enabled: true,
        context: ShortcutContext.global,
      ),
    ];
    
    for (final shortcut in defaultShortcuts) {
      _shortcuts[shortcut.id] = shortcut;
      
      for (final keyCombo in shortcut.keyCombinations) {
        _keyBindings.putIfAbsent(keyCombo, () => []).add(shortcut);
      }
    }
    
    await _saveShortcuts();
    debugPrint('⌨️ Created ${defaultShortcuts.length} default shortcuts');
  }

  Future<void> _loadProfiles() async {
    try {
      final profilesFile = File('${_configDir!.path}/$_profilesFile');
      if (!await profilesFile.exists()) {
        await _createDefaultProfiles();
        return;
      }
      
      final content = await profilesFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      for (final entry in (data['profiles'] as List)) {
        final profile = ShortcutProfile.fromJson(entry);
        _profiles.add(profile);
      }
      
      // Set active profile
      final activeProfileId = data['active_profile'] as String?;
      if (activeProfileId != null) {
        _activeProfile = _profiles.firstWhere((p) => p.id == activeProfileId);
      }
      
      if (_activeProfile == null && _profiles.isNotEmpty) {
        _activeProfile = _profiles.first;
      }
      
      debugPrint('⌨️ Loaded ${_profiles.length} shortcut profiles');
    } catch (e) {
      debugPrint('⚠️ Failed to load profiles: $e');
      await _createDefaultProfiles();
    }
  }

  Future<void> _createDefaultProfiles() async {
    final defaultProfiles = [
      ShortcutProfile(
        id: 'default',
        name: 'Default',
        description: 'Default shortcut configuration',
        shortcuts: _shortcuts.keys.toList(),
        isDefault: true,
        createdAt: DateTime.now(),
      ),
      ShortcutProfile(
        id: 'vim_mode',
        name: 'Vim Mode',
        description: 'Vim-style shortcuts',
        shortcuts: [],
        isDefault: false,
        createdAt: DateTime.now(),
      ),
      ShortcutProfile(
        id: 'emacs_mode',
        name: 'Emacs Mode',
        description: 'Emacs-style shortcuts',
        shortcuts: [],
        isDefault: false,
        createdAt: DateTime.now(),
      ),
    ];
    
    _profiles.addAll(defaultProfiles);
    _activeProfile = defaultProfiles.first;
    
    await _saveProfiles();
    debugPrint('⌨️ Created ${defaultProfiles.length} default profiles');
  }

  void _setupKeyboardListener() {
    // This would integrate with the main application's keyboard event system
    // For now, we'll simulate the listener
    debugPrint('⌨️ Keyboard listener setup');
  }

  // Public API methods
  
  Future<bool> addShortcut({
    required String actionId,
    required String name,
    required List<KeyCombination> keyCombinations,
    ShortcutContext context = ShortcutContext.global,
    String? description,
  }) async {
    try {
      // Check if action exists
      if (!_actions.containsKey(actionId)) {
        throw ArgumentError('Action not found: $actionId');
      }
      
      // Check for conflicts
      final conflicts = _detectConflicts(keyCombinations);
      if (conflicts.isNotEmpty) {
        debugPrint('⚠️ Shortcut conflicts detected: $conflicts');
        _shortcutController.add(ShortcutEvent(
          type: ShortcutEventType.conflictDetected,
          data: {
            'conflicts': conflicts,
            'key_combinations': keyCombinations.map((kc) => kc.toString()).toList(),
          },
        ));
        return false;
      }
      
      // Create shortcut
      final shortcut = Shortcut(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        actionId: actionId,
        name: name,
        keyCombinations: keyCombinations,
        enabled: true,
        context: context,
        description: description,
      );
      
      // Add to storage
      _shortcuts[shortcut.id] = shortcut;
      
      // Update key bindings
      for (final keyCombo in keyCombinations) {
        _keyBindings.putIfAbsent(keyCombo, () => []).add(shortcut);
      }
      
      // Add to active profile
      if (_activeProfile != null) {
        _activeProfile!.shortcuts.add(shortcut.id);
      }
      
      await _saveShortcuts();
      await _saveProfiles();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.shortcutAdded,
        shortcutId: shortcut.id,
        data: shortcut.toJson(),
      ));
      
      debugPrint('⌨️ Added shortcut: $name');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to add shortcut: $e');
      return false;
    }
  }

  Future<bool> removeShortcut(String shortcutId) async {
    try {
      final shortcut = _shortcuts.remove(shortcutId);
      if (shortcut == null) {
        throw ArgumentError('Shortcut not found: $shortcutId');
      }
      
      // Remove from key bindings
      for (final keyCombo in shortcut.keyCombinations) {
        _keyBindings[keyCombo]?.remove(shortcut);
        if (_keyBindings[keyCombo]?.isEmpty == true) {
          _keyBindings.remove(keyCombo);
        }
      }
      
      // Remove from profiles
      for (final profile in _profiles) {
        profile.shortcuts.remove(shortcutId);
      }
      
      await _saveShortcuts();
      await _saveProfiles();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.shortcutRemoved,
        shortcutId: shortcutId,
      ));
      
      debugPrint('⌨️ Removed shortcut: $shortcutId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to remove shortcut: $e');
      return false;
    }
  }

  Future<bool> updateShortcut(String shortcutId, {
    String? name,
    List<KeyCombination>? keyCombinations,
    bool? enabled,
    ShortcutContext? context,
    String? description,
  }) async {
    try {
      final shortcut = _shortcuts[shortcutId];
      if (shortcut == null) {
        throw ArgumentError('Shortcut not found: $shortcutId');
      }
      
      // Check for conflicts if key combinations changed
      if (keyCombinations != null) {
        final conflicts = _detectConflicts(keyCombinations);
        if (conflicts.isNotEmpty) {
          debugPrint('⚠️ Shortcut conflicts detected: $conflicts');
          return false;
        }
      }
      
      // Remove old key bindings
      for (final keyCombo in shortcut.keyCombinations) {
        _keyBindings[keyCombo]?.remove(shortcut);
        if (_keyBindings[keyCombo]?.isEmpty == true) {
          _keyBindings.remove(keyCombo);
        }
      }
      
      // Update shortcut
      if (name != null) shortcut.name = name;
      if (keyCombinations != null) shortcut.keyCombinations = keyCombinations;
      if (enabled != null) shortcut.enabled = enabled;
      if (context != null) shortcut.context = context;
      if (description != null) shortcut.description = description;
      
      // Add new key bindings
      for (final keyCombo in shortcut.keyCombinations) {
        _keyBindings.putIfAbsent(keyCombo, () => []).add(shortcut);
      }
      
      await _saveShortcuts();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.shortcutUpdated,
        shortcutId: shortcutId,
        data: shortcut.toJson(),
      ));
      
      debugPrint('⌨️ Updated shortcut: $shortcutId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to update shortcut: $e');
      return false;
    }
  }

  Future<bool> executeShortcut(KeyCombination keyCombo, {ShortcutContext? context}) async {
    try {
      final shortcuts = _keyBindings[keyCombo];
      if (shortcuts == null || shortcuts.isEmpty) {
        return false;
      }
      
      // Find matching shortcut for current context
      Shortcut? matchingShortcut;
      for (final shortcut in shortcuts) {
        if (!shortcut.enabled) continue;
        
        if (context != null) {
          if (shortcut.context == ShortcutContext.global || 
              shortcut.context == context) {
            matchingShortcut = shortcut;
            break;
          }
        } else {
          matchingShortcut = shortcut;
          break;
        }
      }
      
      if (matchingShortcut == null) {
        return false;
      }
      
      final action = _actions[matchingShortcut.actionId];
      if (action == null) {
        debugPrint('⚠️ Action not found: ${matchingShortcut.actionId}');
        return false;
      }
      
      // Execute action
      await _executeAction(action);
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.shortcutExecuted,
        shortcutId: matchingShortcut.id,
        actionId: action.id,
        data: {
          'key_combination': keyCombo.toString(),
          'context': context?.toString(),
        },
      ));
      
      debugPrint('⌨️ Executed shortcut: ${matchingShortcut.name}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to execute shortcut: $e');
      return false;
    }
  }

  Future<void> _executeAction(ShortcutAction action) async {
    // This would integrate with the main application to execute the actual action
    debugPrint('⌨️ Executing action: ${action.name} (${action.id})');
    
    // Emit action execution event for the main app to handle
    _shortcutController.add(ShortcutEvent(
      type: ShortcutEventType.actionExecuted,
      actionId: action.id,
      data: action.toJson(),
    ));
  }

  List<String> _detectConflicts(List<KeyCombination> keyCombinations) {
    final conflicts = <String>[];
    
    for (final keyCombo in keyCombinations) {
      final existingShortcuts = _keyBindings[keyCombo];
      if (existingShortcuts != null && existingShortcuts.isNotEmpty) {
        for (final shortcut in existingShortcuts) {
          conflicts.add('${shortcut.name} (${keyCombo.toString()})');
        }
      }
    }
    
    return conflicts;
  }

  Future<bool> createProfile({
    required String name,
    required String description,
    List<String>? shortcuts,
  }) async {
    try {
      final profile = ShortcutProfile(
        id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: description,
        shortcuts: shortcuts ?? [],
        isDefault: false,
        createdAt: DateTime.now(),
      );
      
      _profiles.add(profile);
      await _saveProfiles();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.profileCreated,
        data: profile.toJson(),
      ));
      
      debugPrint('⌨️ Created profile: $name');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to create profile: $e');
      return false;
    }
  }

  Future<bool> setActiveProfile(String profileId) async {
    try {
      final profile = _profiles.firstWhere((p) => p.id == profileId);
      _activeProfile = profile;
      
      await _saveProfiles();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.profileChanged,
        data: profile.toJson(),
      ));
      
      debugPrint('⌨️ Switched to profile: ${profile.name}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to set active profile: $e');
      return false;
    }
  }

  Future<bool> deleteProfile(String profileId) async {
    try {
      final profile = _profiles.firstWhere((p) => p.id == profileId);
      
      if (profile.isDefault) {
        debugPrint('⚠️ Cannot delete default profile');
        return false;
      }
      
      if (_activeProfile?.id == profileId) {
        // Switch to default profile
        final defaultProfile = _profiles.firstWhere((p) => p.isDefault);
        _activeProfile = defaultProfile;
      }
      
      _profiles.remove(profile);
      await _saveProfiles();
      
      _shortcutController.add(ShortcutEvent(
        type: ShortcutEventType.profileDeleted,
        data: {'profile_id': profileId},
      ));
      
      debugPrint('⌨️ Deleted profile: ${profile.name}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to delete profile: $e');
      return false;
    }
  }

  Future<void> _saveShortcuts() async {
    try {
      final configFile = File('${_configDir!.path}/$_defaultConfigFile');
      
      final data = {
        'shortcuts': _shortcuts.values.map((s) => s.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await configFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save shortcuts: $e');
    }
  }

  Future<void> _saveProfiles() async {
    try {
      final profilesFile = File('${_configDir!.path}/$_profilesFile');
      
      final data = {
        'profiles': _profiles.map((p) => p.toJson()).toList(),
        'active_profile': _activeProfile?.id,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await profilesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Failed to save profiles: $e');
    }
  }

  Future<Map<String, dynamic>> exportShortcuts() async {
    return {
      'shortcuts': _shortcuts.values.map((s) => s.toJson()).toList(),
      'profiles': _profiles.map((p) => p.toJson()).toList(),
      'active_profile': _activeProfile?.id,
      'actions': _actions.values.map((a) => a.toJson()).toList(),
      'exported_at': DateTime.now().toIso8601String(),
      'version': '1.0.0',
    };
  }

  Future<bool> importShortcuts(Map<String, dynamic> data) async {
    try {
      // Validate data structure
      if (!data.containsKey('shortcuts') || !data.containsKey('profiles')) {
        throw ArgumentError('Invalid shortcut data format');
      }
      
      // Backup current configuration
      final backup = await exportShortcuts();
      
      try {
        // Import shortcuts
        _shortcuts.clear();
        _keyBindings.clear();
        
        for (final entry in (data['shortcuts'] as List)) {
          final shortcut = Shortcut.fromJson(entry);
          _shortcuts[shortcut.id] = shortcut;
          
          for (final keyCombo in shortcut.keyCombinations) {
            _keyBindings.putIfAbsent(keyCombo, () => []).add(shortcut);
          }
        }
        
        // Import profiles
        _profiles.clear();
        for (final entry in (data['profiles'] as List)) {
          final profile = ShortcutProfile.fromJson(entry);
          _profiles.add(profile);
        }
        
        // Set active profile
        final activeProfileId = data['active_profile'] as String?;
        if (activeProfileId != null) {
          _activeProfile = _profiles.firstWhere((p) => p.id == activeProfileId);
        }
        
        await _saveShortcuts();
        await _saveProfiles();
        
        _shortcutController.add(ShortcutEvent(
          type: ShortcutEventType.shortcutsImported,
          data: {'imported_shortcuts': _shortcuts.length},
        ));
        
        debugPrint('⌨️ Imported ${_shortcuts.length} shortcuts');
        return true;
      } catch (e) {
        // Restore backup on failure
        await importShortcuts(backup);
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ Failed to import shortcuts: $e');
      return false;
    }
  }

  ShortcutStatistics getStatistics() {
    return ShortcutStatistics(
      totalShortcuts: _shortcuts.length,
      enabledShortcuts: _shortcuts.values.where((s) => s.enabled).length,
      totalProfiles: _profiles.length,
      activeProfile: _activeProfile?.name,
      totalActions: _actions.length,
      keyBindings: _keyBindings.length,
      conflicts: _detectAllConflicts(),
    );
  }

  List<String> _detectAllConflicts() {
    final conflicts = <String>[];
    final processedKeys = <KeyCombination>{};
    
    for (final entry in _keyBindings.entries) {
      if (processedKeys.contains(entry.key)) continue;
      
      final shortcuts = entry.value;
      if (shortcuts.length > 1) {
        for (final shortcut in shortcuts) {
          conflicts.add('${shortcut.name} (${entry.key.toString()})');
        }
      }
      
      processedKeys.add(entry.key);
    }
    
    return conflicts;
  }

  Future<void> dispose() async {
    // Save current state
    await _saveShortcuts();
    await _saveProfiles();
    
    // Clear data
    _shortcuts.clear();
    _keyBindings.clear();
    _profiles.clear();
    _actions.clear();
    _activeProfile = null;
    
    // Close event controller
    _shortcutController.close();
    
    _isInitialized = false;
    debugPrint('⌨️ Custom Shortcuts disposed');
  }
}

/// Data classes
class Shortcut {
  final String id;
  final String actionId;
  String name;
  final List<KeyCombination> keyCombinations;
  bool enabled;
  final ShortcutContext context;
  final String? description;
  final DateTime createdAt = DateTime.now();
  
  Shortcut({
    required this.id,
    required this.actionId,
    required this.name,
    required this.keyCombinations,
    required this.enabled,
    required this.context,
    this.description,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action_id': actionId,
      'name': name,
      'key_combinations': keyCombinations.map((kc) => kc.toJson()).toList(),
      'enabled': enabled,
      'context': context.toString(),
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
  
  factory Shortcut.fromJson(Map<String, dynamic> json) {
    return Shortcut(
      id: json['id'],
      actionId: json['action_id'],
      name: json['name'],
      keyCombinations: (json['key_combinations'] as List)
          .map((kc) => KeyCombination.fromJson(kc))
          .toList(),
      enabled: json['enabled'],
      context: ShortcutContext.values.firstWhere((c) => c.toString() == json['context']),
      description: json['description'],
    );
  }
}

class KeyCombination {
  final List<LogicalKeyboardKey> keys;
  
  KeyCombination(this.keys);
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyCombination &&
          runtimeType == other.runtimeType &&
          _listEquals(keys, other.keys);
  
  @override
  int get hashCode => keys.fold(0, (hash, key) => hash * 31 + key.keyId);
  
  @override
  String toString() {
    return keys.map((key) => _keyToString(key)).join('+');
  }
  
  String _keyToString(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.control) return 'Ctrl';
    if (key == LogicalKeyboardKey.shift) return 'Shift';
    if (key == LogicalKeyboardKey.alt) return 'Alt';
    if (key == LogicalKeyboardKey.meta) return 'Meta';
    return key.keyLabel ?? key.debugName ?? 'Unknown';
  }
  
  Map<String, dynamic> toJson() {
    return {
      'keys': keys.map((k) => k.keyId).toList(),
    };
  }
  
  factory KeyCombination.fromJson(Map<String, dynamic> json) {
    final keyIds = (json['keys'] as List).cast<int>();
    final keys = keyIds.map((id) => LogicalKeyboardKey.findKeyByKeyId(id)).where((k) => k != null).cast<LogicalKeyboardKey>().toList();
    return KeyCombination(keys);
  }
  
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class ShortcutAction {
  final String id;
  final String name;
  final String description;
  final ActionCategory category;
  final String icon;
  
  ShortcutAction({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category.toString(),
      'icon': icon,
    };
  }
}

class ShortcutProfile {
  final String id;
  String name;
  String description;
  List<String> shortcuts;
  bool isDefault;
  final DateTime createdAt;
  
  ShortcutProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.shortcuts,
    required this.isDefault,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'shortcuts': shortcuts,
      'is_default': isDefault,
      'created_at': createdAt.toIso8601String(),
    };
  }
  
  factory ShortcutProfile.fromJson(Map<String, dynamic> json) {
    return ShortcutProfile(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      shortcuts: List<String>.from(json['shortcuts'] ?? []),
      isDefault: json['is_default'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class ShortcutEvent {
  final ShortcutEventType type;
  final String? shortcutId;
  final String? actionId;
  final Map<String, dynamic>? data;
  
  ShortcutEvent({
    required this.type,
    this.shortcutId,
    this.actionId,
    this.data,
  });
}

class ShortcutStatistics {
  final int totalShortcuts;
  final int enabledShortcuts;
  final int totalProfiles;
  final String? activeProfile;
  final int totalActions;
  final int keyBindings;
  final List<String> conflicts;
  
  ShortcutStatistics({
    required this.totalShortcuts,
    required this.enabledShortcuts,
    required this.totalProfiles,
    this.activeProfile,
    required this.totalActions,
    required this.keyBindings,
    required this.conflicts,
  });
}

enum ShortcutContext {
  global,
  terminal,
  editor,
  fileManager,
  search,
}

enum ActionCategory {
  terminal,
  editing,
  navigation,
  view,
  layout,
  recording,
  search,
  application,
}

enum ShortcutEventType {
  shortcutAdded,
  shortcutRemoved,
  shortcutUpdated,
  shortcutExecuted,
  actionExecuted,
  conflictDetected,
  profileCreated,
  profileDeleted,
  profileChanged,
  shortcutsImported,
  shortcutsExported,
}
