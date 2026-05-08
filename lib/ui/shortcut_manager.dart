import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A comprehensive, user-configurable keyboard shortcut manager for Termisol.
///
/// Shortcuts are stored as a map of action IDs to [ShortcutConfig] objects.
/// The default preset uses standard terminal shortcuts; users can switch to
/// Emacs or Vim presets via the settings UI.
class ShortcutManager {
  final Map<String, ShortcutConfig> _shortcuts = {};

  /// Returns an unmodifiable view of the current shortcuts.
  Map<String, ShortcutConfig> get shortcuts => Map.unmodifiable(_shortcuts);

  /// Load shortcuts from persistent storage or use defaults.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shortcutsJson = prefs.getString('user_shortcuts');
      
      if (shortcutsJson != null) {
        final Map<String, dynamic> shortcutsMap = jsonDecode(shortcutsJson);
        _shortcuts.clear();
        shortcutsMap.forEach((key, value) {
          _shortcuts[key] = ShortcutConfig(
            id: key,
            description: value['description'] ?? '',
            shortcut: value['shortcut'] ?? '',
          );
        });
      } else {
        _loadDefaults();
      }
    } catch (e) {
      // Fallback to defaults if loading fails
      _loadDefaults();
    }
  }

  /// Save shortcuts to persistent storage.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shortcutsMap = <String, dynamic>{};
      
      _shortcuts.forEach((key, config) {
        shortcutsMap[key] = {
          'description': config.description,
          'shortcut': config.shortcut,
        };
      });
      
      await prefs.setString('user_shortcuts', jsonEncode(shortcutsMap));
    } catch (e) {
      // Silently fail for now - could add retry logic or user notification
    }
  }

  /// Apply a preset (standard, emacs, vim).
  void applyPreset(ShortcutPreset preset) {
    _shortcuts.clear();
    switch (preset) {
      case ShortcutPreset.standard:
        _loadStandardPreset();
        break;
      case ShortcutPreset.emacs:
        _loadEmacsPreset();
        break;
      case ShortcutPreset.vim:
        _loadVimPreset();
        break;
    }
  }

  /// Get a human-readable reference of all shortcuts for display.
  List<ShortcutReference> getReference() {
    return _shortcuts.values.map((s) => s.toReference()).toList();
  }

  void _loadDefaults() => _loadStandardPreset();

  void _loadStandardPreset() {
    _add('new_tab', 'New Tab', 'Ctrl+Shift+T');
    _add('close_tab', 'Close Tab', 'Ctrl+Shift+W');
    _add('next_tab', 'Next Tab', 'Ctrl+Tab');
    _add('prev_tab', 'Previous Tab', 'Ctrl+Shift+Tab');
    _add('search', 'Search', 'Ctrl+F');
    _add('settings', 'Settings', 'Ctrl+,');
    _add('ai_assistant', 'AI Assistant', 'Ctrl+Alt+A');
    _add('auto_fix', 'Auto Fix Error', 'Ctrl+Shift+E');
    _add('copy', 'Copy', 'Ctrl+Shift+C');
    _add('paste', 'Paste', 'Ctrl+V');
    _add('paste_bracketed', 'Paste Bracketed', 'Ctrl+Shift+V');
    _add('select_all', 'Select All', 'Ctrl+Shift+A');
    _add('zoom_in', 'Zoom In', 'Ctrl+=');
    _add('zoom_out', 'Zoom Out', 'Ctrl+-');
    _add('toggle_fps', 'Toggle FPS', 'Ctrl+Shift+F');
  }

  void _loadEmacsPreset() {
    _loadStandardPreset();
    // Emacs users prefer different bindings for some actions.
    _add('copy', 'Copy', 'Alt+W');
    _add('paste', 'Paste', 'Ctrl+Y');
    _add('select_all', 'Select All', 'Ctrl+X+H');
  }

  void _loadVimPreset() {
    _loadStandardPreset();
    // Vim users get modal bindings (simplified here as direct keys).
    _add('copy', 'Copy', 'Y');
    _add('paste', 'Paste', 'P');
  }

  void _add(String id, String description, String shortcut) {
    _shortcuts[id] = ShortcutConfig(
      id: id,
      description: description,
      shortcut: shortcut,
    );
  }
}

/// Available shortcut presets.
enum ShortcutPreset { standard, emacs, vim }

/// Configuration for a single keyboard shortcut.
class ShortcutConfig {
  final String id;
  final String description;
  final String shortcut;

  ShortcutConfig({
    required this.id,
    required this.description,
    required this.shortcut,
  });

  ShortcutReference toReference() => ShortcutReference(
        description: description,
        shortcut: shortcut,
      );
}

/// Human-readable shortcut reference for display.
class ShortcutReference {
  final String description;
  final String shortcut;

  ShortcutReference({required this.description, required this.shortcut});
}

/// A widget that displays all keyboard shortcuts in a scrollable list.
class ShortcutReferenceOverlay extends StatelessWidget {
  final ShortcutManager manager;
  final VoidCallback onClose;

  const ShortcutReferenceOverlay({
    super.key,
    required this.manager,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final shortcuts = manager.getReference();
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00d4aa).withValues(alpha: 0.3)),
            ),
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Keyboard Shortcuts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF333333)),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: shortcuts.length,
                    itemBuilder: (context, index) {
                      final s = shortcuts[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.description,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0f0f0f),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade700),
                              ),
                              child: Text(
                                s.shortcut,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
