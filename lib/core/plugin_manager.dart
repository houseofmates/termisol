import 'dart:async';
import 'package:flutter/foundation.dart';

/// Plugin Manager stub.
class PluginManager {
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    _isInitialized = true;
  }

  Future<void> loadPlugin(String path) async {}

  Future<void> unloadPlugin(String id) async {}

  List<Map<String, dynamic>> getLoadedPlugins() {
    return [];
  }

  void dispose() {}
}
