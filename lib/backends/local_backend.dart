import 'dart:async';
import 'package:flutter/foundation.dart';

/// Local backend for terminal sessions
class LocalBackend {
  final String name = 'Local Backend';
  
  void initialize() {
    // Initialize local backend
  }
  
  Future<void> executeCommand(String command) async {
    // Simulate command execution
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<String> getWorkingDirectory() async {
    return '/home/house';
  }
  
  bool get isConnected => true;
}
