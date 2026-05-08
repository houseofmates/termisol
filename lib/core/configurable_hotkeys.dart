import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production-grade configurable hotkey system for Termisol
/// 
/// Features:
/// - Cross-platform hotkey registration and detection
/// - Configurable key combinations with modifiers
/// - Persistent storage of hotkey configurations
/// - Conflict detection and resolution
/// - Context-aware hotkey handling
/// - Import/export hotkey profiles
class ConfigurableHotkeys {
  static final ConfigurableHotkeys _instance = ConfigurableHotkeys._internal();
  factory ConfigurableHotkeys() => _instance;
  ConfigurableHotkeys._internal();

  final Map<String, HotkeyBinding> _bindings = {};
  final Map<String, List<HotkeyAction>> _contextActions = {};
  final StreamController<HotkeyEvent> _eventController = StreamController.broadcast();
  final Map<String, int> _keyStates = {};
  
  bool _initialized = false;
  String? _currentContext;
  Timer? _debounceTimer;

  Stream<HotkeyEvent> get events => _eventController.stream;
  bool get isInitialized => _initialized;
  Map<String, HotkeyBinding> get bindings => Map.unmodifiable(_bindings);

  /// Initialize the hotkey system
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadDefaultBindings();
      await _loadUserBindings();
      _setupKeyboardListener();
      _initialized = true;
      debugPrint('✅ ConfigurableHotkeys initialized');
    } catch (e) {
      debugPrint('❌ ConfigurableHotkeys initialization failed: $e');
    }
  }

  /// Load default hotkey bindings
  Future<void> _loadDefaultBindings() async {
    final defaultBindings = {
      'new_tab': HotkeyBinding(
        id: 'new_tab',
        key: LogicalKeyboardKey.keyT,
        modifiers: {HotkeyModifier.ctrl},
        action: 'new_terminal_tab',
        description: 'Open new terminal tab',
      ),
      'close_tab': HotkeyBinding(
        id: 'close_tab',
        key: LogicalKeyboardKey.keyW,
        modifiers: {HotkeyModifier.ctrl},
        action: 'close_terminal_tab',
        description: 'Close current terminal tab',
      ),
      'copy': HotkeyBinding(
        id: 'copy',
        key: LogicalKeyboardKey.keyC,
        modifiers: {HotkeyModifier.ctrl, HotkeyModifier.shift},
        action: 'copy_selection',
        description: 'Copy selected text',
      ),
      'paste': HotkeyBinding(
        id: 'paste',
        key: LogicalKeyboardKey.keyV,
        modifiers: {HotkeyModifier.ctrl, HotkeyModifier.shift},
        action: 'paste_clipboard',
        description: 'Paste from clipboard',
      ),
      'find': HotkeyBinding(
        id: 'find',
        key: LogicalKeyboardKey.keyF,
        modifiers: {HotkeyModifier.ctrl},
        action: 'find_in_terminal',
        description: 'Find text in terminal',
      ),
      'split_horizontal': HotkeyBinding(
        id: 'split_horizontal',
        key: LogicalKeyboardKey.keyD,
        modifiers: {HotkeyModifier.ctrl},
        action: 'split_horizontal',
        description: 'Split terminal horizontally',
      ),
      'split_vertical': HotkeyBinding(
        id: 'split_vertical',
        key: LogicalKeyboardKey.keyD,
        modifiers: {HotkeyModifier.ctrl, HotkeyModifier.shift},
        action: 'split_vertical',
        description: 'Split terminal vertically',
      ),
      'zoom_in': HotkeyBinding(
        id: 'zoom_in',
        key: LogicalKeyboardKey.equal,
        modifiers: {HotkeyModifier.ctrl},
        action: 'increase_font_size',
        description: 'Increase font size',
      ),
      'zoom_out': HotkeyBinding(
        id: 'zoom_out',
        key: LogicalKeyboardKey.minus,
        modifiers: {HotkeyModifier.ctrl},
        action: 'decrease_font_size',
        description: 'Decrease font size',
      ),
      'reset_zoom': HotkeyBinding(
        id: 'reset_zoom',
        key: LogicalKeyboardKey.digit0,
        modifiers: {HotkeyModifier.ctrl},
        action: 'reset_font_size',
        description: 'Reset font size to default',
      ),
    };

    _bindings.addAll(defaultBindings);
  }

  /// Load user-defined hotkey bindings
  Future<void> _loadUserBindings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bindingsJson = prefs.getString('hotkey_bindings');
      
      if (bindingsJson != null) {
        final List<dynamic> userBindings = jsonDecode(bindingsJson);
        for (final bindingJson in userBindings) {
          final binding = HotkeyBinding.fromJson(bindingJson);
          _bindings[binding.id] = binding;
        }
      }
    } catch (e) {
      debugPrint('Failed to load user hotkey bindings: $e');
    }
  }

  /// Save user-defined hotkey bindings
  Future<void> _saveUserBindings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userBindings = _bindings.values
          .where((b) => !b.isDefault)
          .map((b) => b.toJson())
          .toList();
      
      await prefs.setString('hotkey_bindings', jsonEncode(userBindings));
    } catch (e) {
      debugPrint('Failed to save user hotkey bindings: $e');
    }
  }

  /// Setup keyboard event listener
  void _setupKeyboardListener() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// Handle keyboard events
  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _handleKeyDown(event);
    } else if (event is KeyUpEvent) {
      _handleKeyUp(event);
    }
    return false; // Don't consume the event
  }

  /// Handle key down events
  void _handleKeyDown(KeyDownEvent event) {
    final key = event.logicalKey;
    _keyStates[key.keyId] = DateTime.now().millisecondsSinceEpoch;

    // Debounce rapid key presses
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _checkHotkeyMatch();
    });
  }

  /// Handle key up events
  void _handleKeyUp(KeyUpEvent event) {
    final key = event.logicalKey;
    _keyStates.remove(key.keyId);
  }

  /// Check if current key state matches any hotkey
  void _checkHotkeyMatch() {
    final currentKeys = _keyStates.keys.toList();
    final currentModifiers = _getCurrentModifiers();

    for (final binding in _bindings.values) {
      if (_matchesHotkey(binding, currentKeys, currentModifiers)) {
        _executeHotkey(binding);
        break;
      }
    }
  }

  /// Get current modifier keys state
  Set<HotkeyModifier> _getCurrentModifiers() {
    final modifiers = <HotkeyModifier>{};
    
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers.add(HotkeyModifier.ctrl);
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers.add(HotkeyModifier.shift);
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers.add(HotkeyModifier.alt);
    }
    if (HardwareKeyboard.instance.isMetaPressed) {
      modifiers.add(HotkeyModifier.meta);
    }
    
    return modifiers;
  }

  /// Check if current key state matches a hotkey binding
  bool _matchesHotkey(HotkeyBinding binding, List<int> currentKeys, Set<HotkeyModifier> currentModifiers) {
    // Check if the main key is pressed
    if (!currentKeys.contains(binding.key.keyId)) {
      return false;
    }

    // Check if all required modifiers are pressed
    if (!binding.modifiers.every((modifier) => currentModifiers.contains(modifier))) {
      return false;
    }

    // Check if no extra modifiers are pressed (unless allowed)
    final extraModifiers = currentModifiers.difference(binding.modifiers);
    if (extraModifiers.isNotEmpty) {
      return false;
    }

    return true;
  }

  /// Execute a hotkey action
  void _executeHotkey(HotkeyBinding binding) {
    // Check context-specific actions
    if (_currentContext != null) {
      final contextActions = _contextActions[_currentContext!];
      if (contextActions != null) {
        final matchingAction = contextActions.firstWhere(
          (action) => action.id == binding.action,
          orElse: () => HotkeyAction(id: binding.action, handler: () {}),
        );
        
        if (matchingAction.handler != null) {
          matchingAction.handler!();
          _eventController.add(HotkeyEvent(
            type: HotkeyEventType.executed,
            binding: binding,
            context: _currentContext,
          ));
          return;
        }
      }
    }

    // Execute global action
    _eventController.add(HotkeyEvent(
      type: HotkeyEventType.executed,
      binding: binding,
      context: _currentContext,
    ));
  }

  /// Register a new hotkey binding
  Future<bool> registerBinding(HotkeyBinding binding) async {
    try {
      // Check for conflicts
      final conflict = _findConflict(binding);
      if (conflict != null) {
        debugPrint('Hotkey conflict: ${binding.id} conflicts with ${conflict.id}');
        return false;
      }

      _bindings[binding.id] = binding;
      await _saveUserBindings();
      
      debugPrint('✅ Registered hotkey: ${binding.id}');
      return true;
    } catch (e) {
      debugPrint('Failed to register hotkey ${binding.id}: $e');
      return false;
    }
  }

  /// Find conflicting hotkey binding
  HotkeyBinding? _findConflict(HotkeyBinding newBinding) {
    for (final binding in _bindings.values) {
      if (binding.id == newBinding.id) continue;
      
      if (binding.key == newBinding.key && 
          binding.modifiers.equals(newBinding.modifiers)) {
        return binding;
      }
    }
    return null;
  }

  /// Unregister a hotkey binding
  Future<bool> unregisterBinding(String bindingId) async {
    try {
      if (_bindings.remove(bindingId) != null) {
        await _saveUserBindings();
        debugPrint('✅ Unregistered hotkey: $bindingId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to unregister hotkey $bindingId: $e');
      return false;
    }
  }

  /// Update an existing hotkey binding
  Future<bool> updateBinding(HotkeyBinding binding) async {
    try {
      // Check for conflicts (excluding self)
      final conflict = _findConflict(binding);
      if (conflict != null && conflict.id != binding.id) {
        debugPrint('Hotkey conflict: ${binding.id} conflicts with ${conflict.id}');
        return false;
      }

      _bindings[binding.id] = binding;
      await _saveUserBindings();
      
      debugPrint('✅ Updated hotkey: ${binding.id}');
      return true;
    } catch (e) {
      debugPrint('Failed to update hotkey ${binding.id}: $e');
      return false;
    }
  }

  /// Register context-specific actions
  void registerContextActions(String context, List<HotkeyAction> actions) {
    _contextActions[context] = actions;
  }

  /// Set current context
  void setContext(String? context) {
    _currentContext = context;
  }

  /// Get binding by ID
  HotkeyBinding? getBinding(String id) {
    return _bindings[id];
  }

  /// Get all bindings for a specific action
  List<HotkeyBinding> getBindingsForAction(String action) {
    return _bindings.values.where((b) => b.action == action).toList();
  }

  /// Export hotkey configuration
  Future<String> exportConfiguration() async {
    try {
      final config = {
        'version': '1.0.0',
        'bindings': _bindings.values.map((b) => b.toJson()).toList(),
        'contexts': _contextActions.map((k, v) => MapEntry(k, v.map((a) => a.toJson()).toList())),
      };
      
      return jsonEncode(config);
    } catch (e) {
      debugPrint('Failed to export configuration: $e');
      return '';
    }
  }

  /// Import hotkey configuration
  Future<bool> importConfiguration(String configJson) async {
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;
      final bindingsJson = config['bindings'] as List<dynamic>;
      
      for (final bindingJson in bindingsJson) {
        final binding = HotkeyBinding.fromJson(bindingJson);
        await registerBinding(binding);
      }
      
      debugPrint('✅ Imported hotkey configuration');
      return true;
    } catch (e) {
      debugPrint('Failed to import configuration: $e');
      return false;
    }
  }

  /// Reset to default bindings
  Future<void> resetToDefaults() async {
    try {
      _bindings.clear();
      await _loadDefaultBindings();
      await _saveUserBindings();
      debugPrint('✅ Reset hotkey bindings to defaults');
    } catch (e) {
      debugPrint('Failed to reset to defaults: $e');
    }
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalBindings': _bindings.length,
      'userBindings': _bindings.values.where((b) => !b.isDefault).length,
      'defaultBindings': _bindings.values.where((b) => b.isDefault).length,
      'contexts': _contextActions.keys.toList(),
      'currentContext': _currentContext,
    };
  }

  /// Dispose resources
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _debounceTimer?.cancel();
    _eventController.close();
    _bindings.clear();
    _contextActions.clear();
    _keyStates.clear();
    _initialized = false;
  }
}

/// Hotkey binding definition
class HotkeyBinding {
  final String id;
  final LogicalKeyboardKey key;
  final Set<HotkeyModifier> modifiers;
  final String action;
  final String description;
  final bool isDefault;

  HotkeyBinding({
    required this.id,
    required this.key,
    required this.modifiers,
    required this.action,
    required this.description,
    this.isDefault = false,
  });

  factory HotkeyBinding.fromJson(Map<String, dynamic> json) {
    return HotkeyBinding(
      id: json['id'] as String,
      key: LogicalKeyboardKey.findKeyByKeyId(json['key'] as int) ?? LogicalKeyboardKey.space,
      modifiers: (json['modifiers'] as List<dynamic>)
          .map((m) => HotkeyModifier.values[m as int])
          .toSet(),
      action: json['action'] as String,
      description: json['description'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key.keyId,
      'modifiers': modifiers.map((m) => m.index).toList(),
      'action': action,
      'description': description,
      'isDefault': isDefault,
    };
  }

  String get displayName {
    final parts = <String>[];
    
    if (modifiers.contains(HotkeyModifier.ctrl)) parts.add('Ctrl');
    if (modifiers.contains(HotkeyModifier.shift)) parts.add('Shift');
    if (modifiers.contains(HotkeyModifier.alt)) parts.add('Alt');
    if (modifiers.contains(HotkeyModifier.meta)) parts.add('Meta');
    
    parts.add(key.keyLabel);
    
    return parts.join(' + ');
  }
}

/// Hotkey modifier enum
enum HotkeyModifier {
  ctrl,
  shift,
  alt,
  meta,
}

/// Hotkey action definition
class HotkeyAction {
  final String id;
  final VoidCallback? handler;

  HotkeyAction({
    required this.id,
    this.handler,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
    };
  }
}

/// Hotkey event
class HotkeyEvent {
  final HotkeyEventType type;
  final HotkeyBinding binding;
  final String? context;
  final DateTime timestamp;

  HotkeyEvent({
    required this.type,
    required this.binding,
    this.context,
  }) : timestamp = DateTime.now();
}

/// Hotkey event type
enum HotkeyEventType {
  executed,
  conflict,
  error,
}

/// Extension for Set equality
extension SetEquality<T> on Set<T> {
  bool equals(Set<T> other) {
    if (length != other.length) return false;
    return difference(other).isEmpty;
  }
}