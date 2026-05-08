import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

/// Global configuration system inspired by Alacritty's YAML-driven approach.
///
/// Supports hot-reloading from disk and hierarchical defaults.
class GlobalConfig extends ChangeNotifier {
  static const String _jsonFile = 'termisol_config.json';
  static const String _yamlFile = 'termisol_config.yaml';

  Map<String, dynamic> _data = {};
  bool _loaded = false;
  StreamSubscription<FileSystemEvent>? _watcher;

  bool get isLoaded => _loaded;

  // ── performance ──
  bool get gpuAcceleration => _get('performance.gpu_acceleration', true);
  int get targetFps => _get('performance.target_fps', 60);
  int get scrollbackLines => _get('terminal.scrollback_lines', 50000);

  // ── appearance ──
  String get fontFamily => _get('font.family', 'monospace');
  double get fontSize => (_get('font.size', 14) as num).toDouble();
  String get theme => _get('theme', 'dark');

  // ── behavior ──
  bool get cursorBlink => _get('cursor.blink', true);
  bool get bracketedPaste => _get('clipboard.bracketed_paste', true);

  /// Load from disk, preferring YAML then JSON.
  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final yamlFile = File('${dir.path}/$_yamlFile');
      final jsonFile = File('${dir.path}/$_jsonFile');

      if (await yamlFile.exists()) {
        final yamlString = await yamlFile.readAsString();
        final yamlMap = loadYaml(yamlString) as Map<dynamic, dynamic>?;
        _data = _yamlToJson(yamlMap ?? {});
      } else if (await jsonFile.exists()) {
        final jsonString = await jsonFile.readAsString();
        _data = jsonDecode(jsonString) as Map<String, dynamic>;
      } else {
        _data = _defaults();
        await save();
      }

      _loaded = true;
      notifyListeners();

      // Start hot-reload watcher
      _startWatcher(yamlFile.existsSync() ? yamlFile : jsonFile);
    } catch (e) {
      debugPrint('[CONFIG] Load failed: $e');
      _data = _defaults();
      _loaded = true;
      notifyListeners();
    }
  }

  /// Persist current config as JSON.
  Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_jsonFile');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
    } catch (e) {
      debugPrint('[CONFIG] Save failed: $e');
    }
  }

  /// Get a nested value using dot notation with validation.
  T _get<T>(String path, T defaultValue) {
    if (path.isEmpty) {
      debugPrint('[CONFIG] Empty path provided, returning default value');
      return defaultValue;
    }
    
    final parts = path.split('.');
    dynamic current = _data;
    
    try {
      for (final part in parts) {
        if (current is! Map || !current.containsKey(part)) {
          debugPrint('[CONFIG] Path not found: $path, returning default');
          return defaultValue;
        }
        current = current[part];
      }
      
      // Type validation with conversion
      if (current is T) {
        return current;
      }
      
      // Attempt type conversion for common cases
      if (T == String && current != null) {
        return current.toString() as T;
      }
      if (T == int && current is num) {
        return current.toInt() as T;
      }
      if (T == double && current is num) {
        return current.toDouble() as T;
      }
      if (T == bool && current is String) {
        return (current.toLowerCase() == 'true') as T;
      }
      
      debugPrint('[CONFIG] Type mismatch for $path: expected $T, got ${current.runtimeType}');
      return defaultValue;
    } catch (e) {
      debugPrint('[CONFIG] Error accessing $path: $e, returning default');
      return defaultValue;
    }
  }

  /// Set a nested value using dot notation.
  void set(String path, dynamic value) {
    final parts = path.split('.');
    dynamic current = _data;
    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (current[part] is! Map) {
        current[part] = <String, dynamic>{};
      }
      current = current[part];
    }
    current[parts.last] = value;
    save();
    notifyListeners();
  }

  void _startWatcher(File file) {
    if (!file.existsSync()) return;
    try {
      final watcher = file.parent.watch(events: FileSystemEvent.modify);
      _watcher = watcher.listen((event) async {
        if (event.path == file.path) {
          await load();
          debugPrint('[CONFIG] Hot-reloaded from disk');
        }
      });
    } catch (e) {
      debugPrint('[CONFIG] Watcher failed: $e');
    }
  }

  Map<String, dynamic> _yamlToJson(Map<dynamic, dynamic> yaml) {
    final result = <String, dynamic>{};
    for (final entry in yaml.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        result[key] = _yamlToJson(value as Map<dynamic, dynamic>);
      } else if (value is List) {
        result[key] = value.map((v) => v is Map ? _yamlToJson(v) : v).toList();
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _defaults() => {
        'performance': {
          'gpu_acceleration': true,
          'target_fps': 60,
        },
        'terminal': {
          'scrollback_lines': 50000,
        },
        'font': {
          'family': 'monospace',
          'size': 14,
        },
        'theme': 'dark',
        'cursor': {
          'blink': true,
        },
        'clipboard': {
          'bracketed_paste': true,
        },
      };

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }
}
