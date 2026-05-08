import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that persists the SSH passcode across app sessions.
///
/// The passcode is asked once when the app first launches, then reused
/// for every SSH connection (ubuntu, pop! os, etc.).
class SshPasscodeManager {
  static final SshPasscodeManager _instance = SshPasscodeManager._internal();
  factory SshPasscodeManager() => _instance;
  SshPasscodeManager._internal();

  String? _passcode;

  String? get passcode => _passcode;
  bool get hasPasscode => _passcode != null && _passcode!.isNotEmpty;

  /// Load saved passcode from shared preferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _passcode = prefs.getString('ssh_passcode');
  }

  /// Save passcode to shared preferences.
  Future<void> save(String passcode) async {
    final prefs = await SharedPreferences.getInstance();
    _passcode = passcode;
    await prefs.setString('ssh_passcode', passcode);
  }

  /// Clear saved passcode.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    _passcode = null;
    await prefs.remove('ssh_passcode');
  }
}
