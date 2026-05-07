import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Advanced Keyboard Handler - Vim-style bindings and custom macros
/// 
/// Implements sophisticated keyboard handling:
/// - Vim-style modal editing
/// - Custom key bindings and macros
/// - Layer-based configuration
/// - International keyboard support
/// - Context-sensitive mappings
class AdvancedKeyboardHandler {
  bool _isInitialized = false;
  KeyboardMode _currentMode = KeyboardMode.normal;
  
  // Key bindings by mode
  final Map<KeyboardMode, Map<KeyBinding, KeyAction>> _bindings = {};
  
  // Macros
  final Map<String, List<KeyEvent>> _macros = {};
  final Map<String, String> _macroNames = {};
  
  // Recording state
  bool _isRecording = false;
  String? _recordingMacro;
  final List<KeyEvent> _recordedKeys = [];
  
  // International keyboard support
  final Map<String, KeyboardLayout> _layouts = {};
  KeyboardLayout _currentLayout = KeyboardLayout.us;
  
  // Custom actions
  final Map<String, KeyActionCallback> _customActions = {};
  
  AdvancedKeyboardHandler();
  
  bool get isInitialized => _isInitialized;
  KeyboardMode get currentMode => _currentMode;
  bool get isRecording => _isRecording;
  String? get recordingMacro => _recordingMacro;
  
  /// Initialize keyboard handler with default bindings
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load keyboard layouts
      await _loadKeyboardLayouts();
      
      // Initialize default bindings
      _initializeDefaultBindings();
      
      _isInitialized = true;
      debugPrint('⌨️ Advanced Keyboard Handler initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Advanced Keyboard Handler: $e');
    }
  }
  
  /// Load international keyboard layouts
  Future<void> _loadKeyboardLayouts() async {
    _layouts = {
      'us': KeyboardLayout.us,
      'uk': KeyboardLayout.uk,
      'de': KeyboardLayout.german,
      'fr': KeyboardLayout.french,
      'es': KeyboardLayout.spanish,
      'it': KeyboardLayout.italian,
      'ru': KeyboardLayout.russian,
      'ja': KeyboardLayout.japanese,
      'ko': KeyboardLayout.korean,
      'zh': KeyboardLayout.chinese,
    };
  }
  
  /// Initialize default key bindings
  void _initializeDefaultBindings() {
    // Normal mode bindings (Vim-style)
    _bindings[KeyboardMode.normal] = {
      // Movement
      const KeyBinding(LogicalKeyboardKey.keyH, control: false): KeyAction.moveLeft,
      const KeyBinding(LogicalKeyboardKey.keyJ, control: false): KeyAction.moveDown,
      const KeyBinding(LogicalKeyboardKey.keyK, control: false): KeyAction.moveUp,
      const KeyBinding(LogicalKeyboardKey.keyL, control: false): KeyAction.moveRight,
      const KeyBinding(LogicalKeyboardKey.keyW, control: false): KeyAction.moveWordForward,
      const KeyBinding(LogicalKeyboardKey.keyB, control: false): KeyAction.moveWordBackward,
      const KeyBinding(LogicalKeyboardKey.key0, control: false): KeyAction.moveToStartOfLine,
      const KeyBinding(LogicalKeyboardKey.dollar, control: false): KeyAction.moveToEndOfLine,
      const KeyBinding(LogicalKeyboardKey.keyG, control: false): KeyAction.moveToTop,
      const KeyBinding(LogicalKeyboardKey.keyG, shift: true): KeyAction.moveToBottom,
      
      // Editing
      const KeyBinding(LogicalKeyboardKey.keyX, control: false): KeyAction.deleteChar,
      const KeyBinding(LogicalKeyboardKey.keyD, control: false): KeyAction.deleteChar,
      const KeyBinding(LogicalKeyboardKey.keyD, shift: true): KeyAction.deleteLine,
      const KeyBinding(LogicalKeyboardKey.keyC, control: false): KeyAction.copyToClipboard,
      const KeyBinding(LogicalKeyboardKey.keyY, control: false): KeyAction.pasteFromClipboard,
      const KeyBinding(LogicalKeyboardKey.keyP, control: false): KeyAction.pasteFromClipboard,
      const KeyBinding(LogicalKeyboardKey.keyU, control: false): KeyAction.undo,
      const KeyBinding(LogicalKeyboardKey.keyR, control: false): KeyAction.redo,
      
      // Mode switching
      const KeyBinding(LogicalKeyboardKey.keyI, control: false): KeyAction.enterInsertMode,
      const KeyBinding(LogicalKeyboardKey.keyA, control: false): KeyAction.enterInsertModeAppend,
      const KeyBinding(LogicalKeyboardKey.keyO, control: false): KeyAction.enterInsertModeNewLine,
      const KeyBinding(LogicalKeyboardKey.keyO, shift: true): KeyAction.enterInsertModeNewLineAbove,
      const KeyBinding(LogicalKeyboardKey.escape, control: false): KeyAction.enterNormalMode,
      const KeyBinding(LogicalKeyboardKey.keyV, control: false): KeyAction.enterVisualMode,
      const KeyBinding(LogicalKeyboardKey.keyV, shift: true): KeyAction.enterVisualLineMode,
      
      // Search
      const KeyBinding(LogicalKeyboardKey.slash, control: false): KeyAction.searchForward,
      const KeyBinding(LogicalKeyboardKey.question, control: false): KeyAction.searchBackward,
      const KeyBinding(LogicalKeyboardKey.keyN, control: false): KeyAction.nextSearch,
      const KeyBinding(LogicalKeyboardKey.keyN, shift: true): KeyAction.previousSearch,
      
      // Terminal specific
      const KeyBinding(LogicalKeyboardKey.keyT, control: true): KeyAction.newTab,
      const KeyBinding(LogicalKeyboardKey.keyW, control: true): KeyAction.closeTab,
      const KeyBinding(LogicalKeyboardKey.tab, control: true): KeyAction.nextTab,
      const KeyBinding(LogicalKeyboardKey.tab, control: true, shift: true): KeyAction.previousTab,
      const KeyBinding(LogicalKeyboardKey.keyF, control: true): KeyAction.search,
      const KeyBinding(LogicalKeyboardKey.keyC, control: true, shift: true): KeyAction.copy,
      const KeyBinding(LogicalKeyboardKey.keyV, control: true, shift: true): KeyAction.paste,
      
      // Macros
      const KeyBinding(LogicalKeyboardKey.keyQ, control: false): KeyAction.startMacroRecording,
      const KeyBinding(LogicalKeyboardKey.keyQ, shift: true): KeyAction.stopMacroRecording,
      const KeyBinding(LogicalKeyboardKey.at, control: false): KeyAction.playMacro,
    };
    
    // Insert mode bindings
    _bindings[KeyboardMode.insert] = {
      const KeyBinding(LogicalKeyboardKey.escape, control: false): KeyAction.enterNormalMode,
      const KeyBinding(LogicalKeyboardKey.keyC, control: true, shift: true): KeyAction.copy,
      const KeyBinding(LogicalKeyboardKey.keyV, control: true, shift: true): KeyAction.paste,
      const KeyBinding(LogicalKeyboardKey.keyZ, control: true): KeyAction.undo,
      const KeyBinding(LogicalKeyboardKey.keyY, control: true): KeyAction.redo,
    };
    
    // Visual mode bindings
    _bindings[KeyboardMode.visual] = {
      const KeyBinding(LogicalKeyboardKey.escape, control: false): KeyAction.enterNormalMode,
      const KeyBinding(LogicalKeyboardKey.keyD, shift: true): KeyAction.deleteSelection,
      const KeyBinding(LogicalKeyboardKey.keyY, control: false): KeyAction.copySelection,
      const KeyBinding(LogicalKeyboardKey.keyC, control: false): KeyAction.copySelection,
      const KeyBinding(LogicalKeyboardKey.keyX, control: false): KeyAction.cutSelection,
    };
    
    // Command mode bindings
    _bindings[KeyboardMode.command] = {
      const KeyBinding(LogicalKeyboardKey.escape, control: false): KeyAction.enterNormalMode,
      const KeyBinding(LogicalKeyboardKey.enter, control: false): KeyAction.executeCommand,
      const KeyBinding(LogicalKeyboardKey.tab, control: false): KeyAction.commandCompletion,
      const KeyBinding(LogicalKeyboardKey.arrowUp, control: false): KeyAction.commandHistoryUp,
      const KeyBinding(LogicalKeyboardKey.arrowDown, control: false): KeyAction.commandHistoryDown,
    };
  }
  
  /// Handle key event with advanced processing
  KeyActionResult handleKeyEvent(KeyEvent event, {TerminalController? controller}) {
    if (!_isInitialized) return KeyActionResult.notHandled;
    
    try {
      // Handle macro recording
      if (_isRecording) {
        _recordedKeys.add(event);
        if (event.logicalKey == LogicalKeyboardKey.escape && event.isControlPressed) {
          _stopMacroRecording();
          return KeyActionResult.handled;
        }
        return KeyActionResult.recording;
      }
      
      // Handle macro playback
      if (event.logicalKey == LogicalKeyboardKey.at && event.isControlPressed) {
        _playMacro();
        return KeyActionResult.handled;
      }
      
      // Create key binding
      final binding = KeyBinding(
        event.logicalKey,
        control: event.isControlPressed,
        shift: event.isShiftPressed,
        alt: event.isAltPressed,
        meta: event.isMetaPressed,
      );
      
      // Look up binding for current mode
      final modeBindings = _bindings[_currentMode];
      if (modeBindings == null) return KeyActionResult.notHandled;
      
      final action = modeBindings[binding];
      if (action == null) return KeyActionResult.notHandled;
      
      // Execute action
      return _executeKeyAction(action, event, controller);
    } catch (e) {
      debugPrint('⚠️ Failed to handle key event: $e');
      return KeyActionResult.notHandled;
    }
  }
  
  /// Execute key action
  KeyActionResult _executeKeyAction(
    KeyAction action,
    KeyEvent event,
    TerminalController? controller,
  ) {
    switch (action) {
      // Movement actions
      case KeyAction.moveLeft:
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.arrowLeft);
        }
        return KeyActionResult.handled;
        
      case KeyAction.moveDown:
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.arrowDown);
        }
        return KeyActionResult.handled;
        
      case KeyAction.moveUp:
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.arrowUp);
        }
        return KeyActionResult.handled;
        
      case KeyAction.moveRight:
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.arrowRight);
        }
        return KeyActionResult.handled;
        
      // Mode switching
      case KeyAction.enterNormalMode:
        _currentMode = KeyboardMode.normal;
        return KeyActionResult.modeChanged;
        
      case KeyAction.enterInsertMode:
        _currentMode = KeyboardMode.insert;
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.keyI);
        }
        return KeyActionResult.modeChanged;
        
      case KeyAction.enterInsertModeAppend:
        _currentMode = KeyboardMode.insert;
        if (controller != null) {
          controller.sendKey(LogicalKeyboardKey.keyA);
        }
        return KeyActionResult.modeChanged;
        
      case KeyAction.enterVisualMode:
        _currentMode = KeyboardMode.visual;
        return KeyActionResult.modeChanged;
        
      case KeyAction.enterCommandMode:
        _currentMode = KeyboardMode.command;
        return KeyActionResult.modeChanged;
        
      // Search actions
      case KeyAction.search:
        _currentMode = KeyboardMode.command;
        return KeyActionResult.search;
        
      case KeyAction.searchForward:
        _currentMode = KeyboardMode.command;
        return KeyActionResult.search;
        
      case KeyAction.searchBackward:
        _currentMode = KeyboardMode.command;
        return KeyActionResult.search;
        
      // Tab management
      case KeyAction.newTab:
        return KeyActionResult.newTab;
        
      case KeyAction.closeTab:
        return KeyActionResult.closeTab;
        
      case KeyAction.nextTab:
        return KeyActionResult.nextTab;
        
      case KeyAction.previousTab:
        return KeyActionResult.previousTab;
        
      // Clipboard actions
      case KeyAction.copy:
        return KeyActionResult.copy;
        
      case KeyAction.paste:
        return KeyActionResult.paste;
        
      case KeyAction.copySelection:
        return KeyActionResult.copy;
        
      case KeyAction.cutSelection:
        return KeyActionResult.cut;
        
      // Macro actions
      case KeyAction.startMacroRecording:
        _startMacroRecording();
        return KeyActionResult.recording;
        
      case KeyAction.stopMacroRecording:
        _stopMacroRecording();
        return KeyActionResult.recordingStopped;
        
      case KeyAction.playMacro:
        _playMacro();
        return KeyActionResult.handled;
        
      // Custom actions
      case KeyAction.custom:
        return KeyActionResult.handled;
        
      default:
        return KeyActionResult.notHandled;
    }
  }
  
  /// Start macro recording
  void _startMacroRecording() {
    _isRecording = true;
    _recordingMacro = 'macro_${DateTime.now().millisecondsSinceEpoch}';
    _recordedKeys.clear();
    debugPrint('🎬 Started recording macro: $_recordingMacro');
  }
  
  /// Stop macro recording
  void _stopMacroRecording() {
    if (!_isRecording || _recordingMacro == null) return;
    
    _macros[_recordingMacro!] = List.from(_recordedKeys);
    _macroNames[_recordingMacro!] = 'Macro ${_macros.length}';
    
    _isRecording = false;
    final macroName = _recordingMacro;
    _recordingMacro = null;
    _recordedKeys.clear();
    
    debugPrint('🛑 Stopped recording macro: $macroName');
  }
  
  /// Play last recorded macro
  void _playMacro() {
    if (_macros.isEmpty) return;
    
    final lastMacro = _macros.keys.last;
    final keys = _macros[lastMacro]!;
    
    for (final key in keys) {
      // Simulate key events
      // This would need to be integrated with the terminal controller
    }
    
    debugPrint('▶️ Played macro: $lastMacro');
  }
  
  /// Add custom key binding
  void addKeyBinding(
    KeyboardMode mode,
    KeyBinding binding,
    KeyAction action,
  ) {
    if (!_bindings.containsKey(mode)) {
      _bindings[mode] = {};
    }
    _bindings[mode]![binding] = action;
    debugPrint('⌨️ Added binding for $mode: $binding -> $action');
  }
  
  /// Remove key binding
  void removeKeyBinding(KeyboardMode mode, KeyBinding binding) {
    final modeBindings = _bindings[mode];
    if (modeBindings != null) {
      modeBindings.remove(binding);
      debugPrint('⌨️ Removed binding for $mode: $binding');
    }
  }
  
  /// Add custom action
  void addCustomAction(String name, KeyActionCallback callback) {
    _customActions[name] = callback;
    debugPrint('⌨️ Added custom action: $name');
  }
  
  /// Set keyboard layout
  void setKeyboardLayout(String layoutName) {
    final layout = _layouts[layoutName];
    if (layout != null) {
      _currentLayout = layout;
      debugPrint('⌨️ Set keyboard layout: $layoutName');
    }
  }
  
  /// Get available keyboard layouts
  List<String> getAvailableLayouts() {
    return _layouts.keys.toList();
  }
  
  /// Get current keyboard layout
  String getCurrentLayout() {
    for (final entry in _layouts.entries) {
      if (entry.value == _currentLayout) {
        return entry.key;
      }
    }
    return 'us';
  }
  
  /// Get bindings for mode
  Map<KeyBinding, KeyAction>? getBindingsForMode(KeyboardMode mode) {
    return _bindings[mode];
  }
  
  /// Get all macros
  Map<String, List<KeyEvent>> get macros => Map.unmodifiable(_macros);
  
  /// Get macro names
  Map<String, String> get macroNames => Map.unmodifiable(_macroNames);
  
  /// Delete macro
  void deleteMacro(String macroId) {
    _macros.remove(macroId);
    _macroNames.remove(macroId);
    debugPrint('🗑️ Deleted macro: $macroId');
  }
  
  /// Export bindings to JSON
  String exportBindings() {
    final data = <String, dynamic>{
      'bindings': {},
      'macros': {},
      'layout': getCurrentLayout(),
    };
    
    for (final modeEntry in _bindings.entries) {
      final modeName = modeEntry.key.toString();
      final bindings = <String, String>{};
      
      for (final bindingEntry in modeEntry.value.entries) {
        bindings[bindingEntry.key.toString()] = bindingEntry.value.toString();
      }
      
      data['bindings'][modeName] = bindings;
    }
    
    for (final macroEntry in _macros.entries) {
      data['macros'][macroEntry.key] = macroEntry.value
          .map((key) => key.toString())
          .toList();
    }
    
    return jsonEncode(data);
  }
  
  /// Import bindings from JSON
  void importBindings(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      
      // Import bindings
      final bindingsData = data['bindings'] as Map<String, dynamic>?;
      if (bindingsData != null) {
        for (final modeEntry in bindingsData.entries) {
          final mode = KeyboardMode.values.firstWhere(
            (m) => m.toString() == modeEntry.key,
            orElse: () => KeyboardMode.normal,
          );
          
          final modeBindings = <KeyBinding, KeyAction>{};
          final bindings = modeEntry.value as Map<String, dynamic>;
          
          for (final bindingEntry in bindings.entries) {
            // Parse binding and action from strings
            // This would need proper parsing logic
          }
          
          _bindings[mode] = modeBindings;
        }
      }
      
      // Import macros
      final macrosData = data['macros'] as Map<String, dynamic>?;
      if (macrosData != null) {
        for (final macroEntry in macrosData.entries) {
          final keys = (macroEntry.value as List)
              .map((key) => key.toString())
              .toList();
          // Parse keys back to KeyEvent objects
          // This would need proper parsing logic
        }
      }
      
      // Set layout
      final layoutName = data['layout'] as String?;
      if (layoutName != null) {
        setKeyboardLayout(layoutName);
      }
      
      debugPrint('⌨️ Imported bindings from JSON');
    } catch (e) {
      debugPrint('⚠️ Failed to import bindings: $e');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _isRecording = false;
    _recordingMacro = null;
    _recordedKeys.clear();
    _bindings.clear();
    _macros.clear();
    _macroNames.clear();
    _customActions.clear();
    _isInitialized = false;
    debugPrint('⌨️ Advanced Keyboard Handler disposed');
  }
}

/// Key binding data structure
class KeyBinding {
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  
  const KeyBinding(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeyBinding &&
        other.key == key &&
        other.control == control &&
        other.shift == shift &&
        other.alt == alt &&
        other.meta == meta;
  }
  
  @override
  int get hashCode {
    return Object.hash(key, control, shift, alt, meta);
  }
  
  @override
  String toString() {
    final parts = <String>[];
    if (control) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Meta');
    parts.add(key.keyLabel);
    return parts.join('+');
  }
}

/// Keyboard mode enumeration
enum KeyboardMode {
  normal,
  insert,
  visual,
  visualLine,
  command,
}

/// Key action enumeration
enum KeyAction {
  // Movement
  moveLeft,
  moveDown,
  moveUp,
  moveRight,
  moveWordForward,
  moveWordBackward,
  moveToStartOfLine,
  moveToEndOfLine,
  moveToTop,
  moveToBottom,
  
  // Editing
  deleteChar,
  deleteLine,
  deleteSelection,
  copyToClipboard,
  pasteFromClipboard,
  copySelection,
  cutSelection,
  undo,
  redo,
  
  // Mode switching
  enterNormalMode,
  enterInsertMode,
  enterInsertModeAppend,
  enterInsertModeNewLine,
  enterInsertModeNewLineAbove,
  enterVisualMode,
  enterVisualLineMode,
  enterCommandMode,
  
  // Search
  search,
  searchForward,
  searchBackward,
  nextSearch,
  previousSearch,
  
  // Terminal actions
  newTab,
  closeTab,
  nextTab,
  previousTab,
  copy,
  paste,
  
  // Macros
  startMacroRecording,
  stopMacroRecording,
  playMacro,
  
  // Custom
  custom,
}

/// Key action result enumeration
enum KeyActionResult {
  notHandled,
  handled,
  modeChanged,
  search,
  newTab,
  closeTab,
  nextTab,
  previousTab,
  copy,
  paste,
  cut,
  recording,
  recordingStopped,
}

/// Keyboard layout enumeration
enum KeyboardLayout {
  us,
  uk,
  german,
  french,
  spanish,
  italian,
  russian,
  japanese,
  korean,
  chinese,
}

/// Custom action callback type
typedef KeyActionCallback = void Function(KeyEvent event);
