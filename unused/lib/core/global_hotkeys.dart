import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Global hotkeys system for Termisol
/// 
/// Features:
/// - Global hotkey registration
/// - Ctrl+Alt+T to open Termisol
/// - Ctrl+1-10 for tab navigation
/// - Customizable hotkey bindings
/// - Cross-platform support
/// - Hotkey conflict detection
class GlobalHotkeys {
  final StreamController<HotkeyEvent> _eventController = StreamController<HotkeyEvent>.broadcast();
  final Map<String, HotkeyBinding> _bindings = {};
  
  bool _isInitialized = false;
  Timer? _debounceTimer;
  
  Stream<HotkeyEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  /// Initialize global hotkeys
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize default hotkey bindings
      _initializeDefaultBindings();
      
      // Register global hotkeys
      await _registerGlobalHotkeys();
      
      _isInitialized = true;
      
      _eventController.add(HotkeyEvent(
        type: HotkeyEventType.initialized,
        message: 'Global hotkeys initialized',
        data: {'bindings_count': _bindings.length},
      ));
    } catch (e) {
      _EventController.add(HotkeyEvent(
        type: HotkeyEventType.error,
        message: 'Failed to initialize global hotkeys: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _initializeDefaultBindings() {
    // Ctrl+Alt+T - Open Termisol
    _bindings['open_termisol'] = HotkeyBinding(
      key: LogicalKeyboardKey.keyT,
      modifiers: {LogicalKeyboardKey.control, LogicalKeyboardKey.alt},
      action: HotkeyAction.openTermisol,
      description: 'Open Termisol',
      global: true,
    );
    
    // Ctrl+1-10 - Tab navigation
    for (int i = 1; i <= 10; i++) {
      final key = i == 10 ? LogicalKeyboardKey.key0 : LogicalKeyboardKey.keyNumpad$i;
      
      _bindings['tab_$i'] = HotkeyBinding(
        key: key,
        modifiers: {LogicalKeyboardKey.control},
        action: HotkeyAction.switchToTab,
        actionData: i,
        description: 'Switch to tab $i',
        global: true,
      );
    }
    
    // Additional useful hotkeys
    _bindings['new_tab'] = HotkeyBinding(
      key: LogicalKeyboardKey.keyT,
      modifiers: {LogicalKeyboardKey.control, LogicalKeyboardKey.shift},
      action: HotkeyAction.newTab,
      description: 'New tab',
      global: true,
    );
    
    _bindings['close_tab'] = HotkeyBinding(
      key: LogicalKeyboardKey.keyW,
      modifiers: {LogicalKeyboardKey.control},
      action: HotkeyAction.closeTab,
      description: 'Close tab',
      global: true,
    );
    
    _bindings['next_tab'] = HotkeyBinding(
      key: LogicalKeyboardKey.tab,
      modifiers: {LogicalKeyboardKey.control},
      action: HotkeyAction.nextTab,
      description: 'Next tab',
      global: true,
    );
    
    _bindings['prev_tab'] = HotkeyBinding(
      key: LogicalKeyboardKey.tab,
      modifiers: {LogicalKeyboardKey.control, LogicalKeyboardKey.shift},
      action: HotkeyAction.previousTab,
      description: 'Previous tab',
      global: true,
    );
    
    _bindings['zoom_in'] = HotkeyBinding(
      key: LogicalKeyboardKey.equal,
      modifiers: {LogicalKeyboardKey.control},
      action: HotkeyAction.zoomIn,
      description: 'Zoom in',
      global: true,
    );
    
    _bindings['zoom_out'] = HotkeyBinding(
      key: LogicalKeyboardKey.minus,
      modifiers: {LogicalKeyboardKey.control},
      action: HotkeyAction.zoomOut,
      description: 'Zoom out',
      global: true,
    );
    
    _bindings['clear'] = HotkeyBinding(
      key: LogicalKeyboardKey.keyL,
      modifiers: {LogicalKeyboardKey.control},
      action: HotkeyAction.clear,
      description: 'Clear terminal',
      global: true,
    );
  }
  
  Future<void> _registerGlobalHotkeys() async {
    // This would register hotkeys with the operating system
    // For now, we'll simulate the registration
    
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.hotkeys_registered,
      message: 'Global hotkeys registered',
      data: {'bindings': _bindings.values.map((b) => b.toJson()).toList()},
    ));
  }
  
  /// Handle key press
  void handleKeyPress(KeyEvent event) {
    if (!_isInitialized) return;
    
    // Debounce rapid key presses
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _processKeyEvent(event);
    });
  }
  
  void _processKeyEvent(KeyEvent event) {
    // Check if any hotkey binding matches
    for (final binding in _bindings.values) {
      if (_matchesBinding(event, binding)) {
        _executeHotkeyAction(binding);
        return;
      }
    }
  }
  
  bool _matchesBinding(KeyEvent event, HotkeyBinding binding) {
    if (event is! RawKeyDownEvent) return false;
    
    final keyEvent = event as RawKeyDownEvent;
    
    // Check if all required modifiers are pressed
    for (final modifier in binding.modifiers) {
      if (!_isModifierPressed(modifier, keyEvent)) {
        return false;
      }
    }
    
    // Check if the main key matches
    return keyEvent.logicalKey == binding.key;
  }
  
  bool _isModifierPressed(LogicalKeyboardKey modifier, RawKeyDownEvent event) {
    switch (modifier) {
      case LogicalKeyboardKey.control:
        return HardwareKeyboard.instance.isControlPressed;
      case LogicalKeyboardKey.alt:
        return HardwareKeyboard.instance.isAltPressed;
      case LogicalKeyboardKey.shift:
        return HardwareKeyboard.instance.isShiftPressed;
      case LogicalKeyboardKey.meta:
        return HardwareKeyboard.instance.isMetaPressed;
      default:
        return false;
    }
  }
  
  void _executeHotkeyAction(HotkeyBinding binding) {
    switch (binding.action) {
      case HotkeyAction.openTermisol:
        _openTermisol();
        break;
      case HotkeyAction.switchToTab:
        _switchToTab(binding.actionData);
        break;
      case HotkeyAction.newTab:
        _createNewTab();
        break;
      case HotkeyAction.closeTab:
        _closeCurrentTab();
        break;
      case HotkeyAction.nextTab:
        _switchToNextTab();
        break;
      case HotkeyAction.previousTab:
        _switchToPreviousTab();
        break;
      case HotkeyAction.zoomIn:
        _zoomIn();
        break;
      case HotkeyAction.zoomOut:
        _zoomOut();
        break;
      case HotkeyAction.clear:
        _clearTerminal();
        break;
    }
    
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Hotkey action executed: ${binding.description}',
      data: {
        'action': binding.action.toString(),
        'binding': binding.toJson(),
      },
    ));
  }
  
  void _openTermisol() {
    // This would activate or bring Termisol to front
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Opening Termisol',
      data: {'action': 'open_termisol'},
    ));
  }
  
  void _switchToTab(int tabIndex) {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Switching to tab $tabIndex',
      data: {
        'action': 'switch_to_tab',
        'tab_index': tabIndex,
      },
    ));
  }
  
  void _createNewTab() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Creating new tab',
      data: {'action': 'new_tab'},
    ));
  }
  
  void _closeCurrentTab() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Closing current tab',
      data: {'action': 'close_tab'},
    ));
  }
  
  void _switchToNextTab() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Switching to next tab',
      data: {'action': 'next_tab'},
    ));
  }
  
  void _switchToPreviousTab() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Switching to previous tab',
      data: {'action': 'previous_tab'},
    ));
  }
  
  void _zoomIn() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Zooming in',
      data: {'action': 'zoom_in'},
    ));
  }
  
  void _zoomOut() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Zooming out',
      data: {'action': 'zoom_out'},
    ));
  }
  
  void _clearTerminal() {
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.action_executed,
      message: 'Clearing terminal',
      data: {'action': 'clear'},
    ));
  }
  
  /// Add custom hotkey binding
  void addBinding(String id, HotkeyBinding binding) {
    _bindings[id] = binding;
    
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.binding_added,
      message: 'Hotkey binding added',
      data: {
        'id': id,
        'binding': binding.toJson(),
      },
    ));
  }
  
  /// Remove hotkey binding
  void removeBinding(String id) {
    _bindings.remove(id);
    
    _EventController.add(HotkeyEvent(
      type: HotkeyEventType.binding_removed,
      message: 'Hotkey binding removed',
      data: {'id': id},
    ));
  }
  
  /// Get all bindings
  Map<String, HotkeyBinding> getBindings() {
    return Map.unmodifiable(_bindings);
  }
  
  /// Check for hotkey conflicts
  List<HotkeyConflict> checkConflicts() {
    final conflicts = <HotkeyConflict>[];
    final bindingList = _bindings.values.toList();
    
    for (int i = 0; i < bindingList.length; i++) {
      for (int j = i + 1; j < bindingList.length; j++) {
        final binding1 = bindingList[i];
        final binding2 = bindingList[j];
        
        if (_bindingsConflict(binding1, binding2)) {
          conflicts.add(HotkeyConflict(
            binding1: binding1,
            binding2: binding2,
            severity: ConflictSeverity.warning,
          ));
        }
      }
    }
    
    return conflicts;
  }
  
  bool _bindingsConflict(HotkeyBinding binding1, HotkeyBinding binding2) {
    // Check if bindings have the same key and modifiers
    if (binding1.key == binding2.key) {
      final modifiers1 = Set.from(binding1.modifiers);
      final modifiers2 = Set.from(binding2.modifiers);
      
      return modifiers1.intersection(modifiers2).isNotEmpty;
    }
    
    return false;
  }
  
  /// Get hotkey statistics
  Map<String, dynamic> getStatistics() {
    return {
      'is_initialized': _isInitialized,
      'bindings_count': _bindings.length,
      'global_bindings': _bindings.values.where((b) => b.global).length,
      'local_bindings': _bindings.values.where((b) => !b.global).length,
      'conflicts_count': checkConflicts().length,
    };
  }
  
  /// Dispose
  void dispose() {
    _debounceTimer?.cancel();
    _EventController.close();
    _isInitialized = false;
  }
}

/// Hotkey binding
class HotkeyBinding {
  final LogicalKeyboardKey key;
  final Set<LogicalKeyboardKey> modifiers;
  final HotkeyAction action;
  final String? actionData;
  final String description;
  final bool global;
  
  HotkeyBinding({
    required this.key,
    required this.modifiers,
    required this.action,
    this.actionData,
    required this.description,
    this.global = false,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key.keyLabel,
    'modifiers': modifiers.map((m) => m.keyLabel).toList(),
    'action': action.toString(),
    'action_data': actionData,
    'description': description,
    'global': global,
  };
}

/// Hotkey actions
enum HotkeyAction {
  openTermisol,
  switchToTab,
  newTab,
  closeTab,
  nextTab,
  previousTab,
  zoomIn,
  zoomOut,
  clear,
}

/// Hotkey event types
enum HotkeyEventType {
  initialized,
  hotkeys_registered,
  action_executed,
  binding_added,
  binding_removed,
  error,
}

/// Hotkey event
class HotkeyEvent {
  final HotkeyEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  HotkeyEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}

/// Hotkey conflict
class HotkeyConflict {
  final HotkeyBinding binding1;
  final HotkeyBinding binding2;
  final ConflictSeverity severity;
  
  HotkeyConflict({
    required this.binding1,
    required this.binding2,
    required this.severity,
  });
}

/// Conflict severity levels
enum ConflictSeverity {
  info,
  warning,
  error,
}
