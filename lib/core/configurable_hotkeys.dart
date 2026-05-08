import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configurable Hotkeys
///
/// Maps keybindings to terminal and application actions with conflict
/// detection, multi-key chord support, and profile-based presets.
class ConfigurableHotkeys {
  final Map<String, HotkeyBinding> _bindings = {};
  final Map<String, HotkeyProfile> _profiles = {};
  final Map<String, HotkeyContext> _contexts = {};
  String? _activeProfileName;
  bool _enabled = true;
  final StreamController<HotkeyEvent> _eventController = StreamController<HotkeyEvent>.broadcast();

  Stream<HotkeyEvent> get events => _eventController.stream;
  String? get activeProfileName => _activeProfileName;
  bool get isEnabled => _enabled;

  Future<void> initialize({String? profileName}) async {
    _contexts['global'] = HotkeyContext(name: 'global');
    _contexts['terminal'] = HotkeyContext(name: 'terminal', parent: 'global');

    _profiles['default'] = HotkeyProfile(
      name: 'default',
      description: 'Default hotkey bindings',
      bindings: _getDefaultBindings(),
    );

    _profiles['vim'] = HotkeyProfile(
      name: 'vim',
      description: 'Vim-style keybindings',
      bindings: _getVimBindings(),
    );

    _profiles['emacs'] = HotkeyProfile(
      name: 'emacs',
      description: 'Emacs-style keybindings',
      bindings: _getEmacsBindings(),
    );

    await _loadCustomBindings();
    await setProfile(profileName ?? 'default');
    debugPrint('ConfigurableHotkeys initialized (profile: $_activeProfileName)');
  }

  Future<bool> setProfile(String name) async {
    final profile = _profiles[name];
    if (profile == null) return false;

    _activeProfileName = name;
    _bindings.clear();
    for (final binding in profile.bindings) {
      _bindings[binding.id] = binding;
    }
    return true;
  }

  bool registerBinding(HotkeyBinding binding) {
    final existing = _bindings[binding.id];
    if (existing != null) {
      if (binding.overwrite) {
        _bindings[binding.id] = binding;
        return true;
      }
      return false;
    }
    _bindings[binding.id] = binding;
    return true;
  }

  void unregisterBinding(String id) {
    _bindings.remove(id);
  }

  HotkeyBinding? getBinding(String id) => _bindings[id];

  List<HotkeyBinding> getBindingsForAction(String action) {
    return _bindings.values.where((b) => b.action == action).toList();
  }

  HotkeyBinding? matchKey(LogicalKeyboardKey key, {Set<LogicalKeyboardKey> pressed = const {}}) {
    if (!_enabled) return null;

    for (final binding in _bindings.values) {
      if (binding.matches(key, pressed: pressed)) {
        return binding;
      }
    }
    return null;
  }

  List<HotkeyBinding> findConflicts(HotkeyBinding binding) {
    return _bindings.values.where((b) =>
        b.id != binding.id &&
        b.key == binding.key &&
        b.ctrl == binding.ctrl &&
        b.alt == binding.alt &&
        b.shift == binding.shift &&
        b.meta == binding.meta &&
        b.context == binding.context
    ).toList();
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> importBindings(List<Map<String, dynamic>> bindingsData) async {
    for (final data in bindingsData) {
      final binding = HotkeyBinding.fromJson(data);
      _bindings[binding.id] = binding;
    }
    await persist();
  }

  Future<List<Map<String, dynamic>>> exportBindings() async {
    return _bindings.values.map((b) => b.toJson()).toList();
  }

  void addProfile(HotkeyProfile profile) {
    _profiles[profile.name] = profile;
  }

  List<HotkeyProfile> getProfiles() => _profiles.values.toList();

  List<HotkeyBinding> searchBindings(String query) {
    final lower = query.toLowerCase();
    return _bindings.values.where((b) =>
        b.description.toLowerCase().contains(lower) ||
        b.action.toLowerCase().contains(lower) ||
        b.key.toString().toLowerCase().contains(lower)
    ).toList();
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _bindings.values.map((b) => b.toJson()).toList();
      await prefs.setString('hotkey_bindings', json.encode(data));
      await prefs.setString('hotkey_active_profile', _activeProfileName ?? 'default');
    } catch (e) {
      debugPrint('Failed to persist hotkeys: $e');
    }
  }

  Future<void> _loadCustomBindings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('hotkey_bindings');
      if (data != null) {
        final list = json.decode(data) as List;
        final customProfile = HotkeyProfile(
          name: 'custom',
          description: 'Custom bindings',
          bindings: list.map((d) => HotkeyBinding.fromJson(d as Map<String, dynamic>)).toList(),
        );
        _profiles['custom'] = customProfile;
      }
      _activeProfileName = prefs.getString('hotkey_active_profile') ?? 'default';
    } catch (e) {
      _activeProfileName = 'default';
    }
  }

  void dispose() {
    _bindings.clear();
    _profiles.clear();
    _contexts.clear();
    _eventController.close();
  }

  void handleAction(String action, {String? context, Map<String, dynamic>? args}) {
    _eventController.add(HotkeyEvent(action: action, context: context, args: args));
  }

  // ── Default binding presets ──────────────────────────────────────────

  List<HotkeyBinding> _getDefaultBindings() {
    return [
      b('new_tab', 'New Tab', LogicalKeyboardKey.keyT, ctrl: true),
      b('close_tab', 'Close Tab', LogicalKeyboardKey.keyW, ctrl: true),
      b('split_horizontal', 'Split Horizontal', LogicalKeyboardKey.keyD, ctrl: true, shift: true),
      b('split_vertical', 'Split Vertical', LogicalKeyboardKey.keyD, ctrl: true, shift: true, alt: true),
      b('copy', 'Copy', LogicalKeyboardKey.keyC, ctrl: true, shift: true),
      b('paste', 'Paste', LogicalKeyboardKey.keyV, ctrl: true, shift: true),
      b('search', 'Search', LogicalKeyboardKey.keyF, ctrl: true, shift: true),
      b('settings', 'Settings', LogicalKeyboardKey.comma, ctrl: true),
      b('command_palette', 'Command Palette', LogicalKeyboardKey.keyP, ctrl: true, shift: true),
      b('zoom_in', 'Zoom In', LogicalKeyboardKey.equal, ctrl: true, shift: true),
      b('zoom_out', 'Zoom Out', LogicalKeyboardKey.minus, ctrl: true),
      b('previous_tab', 'Previous Tab', LogicalKeyboardKey.tab, ctrl: true, shift: true),
      b('next_tab', 'Next Tab', LogicalKeyboardKey.tab, ctrl: true),
      b('focus_terminal', 'Focus Terminal', LogicalKeyboardKey.escape),
      b('clear_terminal', 'Clear Terminal', LogicalKeyboardKey.keyK, ctrl: true),
      b('toggle_fullscreen', 'Toggle Fullscreen', LogicalKeyboardKey.f11),
      b('navigate_up', 'Scroll Up', LogicalKeyboardKey.arrowUp, shift: true),
      b('navigate_down', 'Scroll Down', LogicalKeyboardKey.arrowDown, shift: true),
    ];
  }

  List<HotkeyBinding> _getVimBindings() {
    return [
      b('vim_escape', 'Vim Escape', LogicalKeyboardKey.escape),
      b('vim_normal', 'Normal Mode', LogicalKeyboardKey.keyJ, ctrl: true),
      b('navigate_up', 'Move Up', LogicalKeyboardKey.keyK),
      b('navigate_down', 'Move Down', LogicalKeyboardKey.keyJ),
      b('command_palette', 'Command Palette', LogicalKeyboardKey.colon),
    ];
  }

  List<HotkeyBinding> _getEmacsBindings() {
    return [
      b('command_palette', 'Command Palette', LogicalKeyboardKey.keyX, alt: true),
      b('search', 'Search', LogicalKeyboardKey.keyS, ctrl: true),
      b('beginning_of_line', 'Beginning of Line', LogicalKeyboardKey.keyA, ctrl: true),
      b('end_of_line', 'End of Line', LogicalKeyboardKey.keyE, ctrl: true),
      b('kill_line', 'Kill Line', LogicalKeyboardKey.keyK, ctrl: true),
    ];
  }

  static HotkeyBinding b(String id, String desc, LogicalKeyboardKey key,
      {bool ctrl = false, bool alt = false, bool shift = false, bool meta = false, String context = 'global'}) {
    return HotkeyBinding(
      id: id,
      description: desc,
      action: id,
      key: key,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      meta: meta,
      context: context,
    );
  }
}

class HotkeyBinding {
  final String id;
  final String description;
  final String action;
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;
  final String context;
  final bool overwrite;

  HotkeyBinding({
    required this.id,
    required this.description,
    required this.action,
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.context = 'global',
    this.overwrite = false,
  });

  bool matches(LogicalKeyboardKey key, {Set<LogicalKeyboardKey> pressed = const {}}) {
    if (key != this.key) return false;
    return switch (ctrl == pressed.contains(LogicalKeyboardKey.controlLeft) || ctrl == pressed.contains(LogicalKeyboardKey.controlRight)) {
      true when (alt == pressed.contains(LogicalKeyboardKey.altLeft) || alt == pressed.contains(LogicalKeyboardKey.altRight)) =>
        true when (shift == pressed.contains(LogicalKeyboardKey.shiftLeft) || shift == pressed.contains(LogicalKeyboardKey.shiftRight)) =>
          true when (meta == pressed.contains(LogicalKeyboardKey.metaLeft) || meta == pressed.contains(LogicalKeyboardKey.metaRight)) => true,
      _ => false,
    };
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'description': description, 'action': action,
    'key': key.keyId, 'ctrl': ctrl, 'alt': alt, 'shift': shift, 'meta': meta,
    'context': context,
  };

  factory HotkeyBinding.fromJson(Map<String, dynamic> json) {
    return HotkeyBinding(
      id: json['id'] as String,
      description: json['description'] as String,
      action: json['action'] as String,
      key: LogicalKeyboardKey.fromInt(json['key'] as int),
      ctrl: json['ctrl'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
      context: json['context'] as String? ?? 'global',
    );
  }
}

class HotkeyProfile {
  final String name;
  final String description;
  final List<HotkeyBinding> bindings;

  HotkeyProfile({required this.name, this.description = '', required this.bindings});
}

class HotkeyContext {
  final String name;
  final String? parent;

  HotkeyContext({required this.name, this.parent});
}

class HotkeyEvent {
  final String action;
  final String? context;
  final Map<String, dynamic>? args;
  final DateTime timestamp;

  HotkeyEvent({required this.action, this.context, this.args}) : timestamp = DateTime.now();
}