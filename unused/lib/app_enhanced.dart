import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'core/service_registry.dart';
import 'core/terminal_session.dart';
import 'session_restore_manager.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';

/// Enhanced app with session restore and crash recovery.
/// Restores previous terminal tabs on app restart.
class TermisolAppEnhanced extends StatefulWidget {
  final ServiceRegistry registry;

  const TermisolAppEnhanced({super.key, required this.registry});

  @override
  State<TermisolAppEnhanced> createState() => _TermisolAppEnhancedState();
}

class _TermisolAppEnhancedState extends State<TermisolAppEnhanced> {
  late final SessionRestoreManager _sessionRestore;
  List<TerminalSession> _restoredSessions = [];
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _sessionRestore = SessionRestoreManager();
    _restoreSessions();
  }

  /// Restore previous sessions.
  Future<void> _restoreSessions() async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);

    try {
      await _sessionRestore.load();
      final savedSessions = _sessionRestore.getSavedSessions();

      for (final sessionState in savedSessions) {
        final session = TerminalSession(
          id: sessionState.id,
          name: sessionState.name,
        );

        await session.start(workingDirectory: sessionState.workingDirectory);
        _restoredSessions.add(session);
      }
    } catch (e, stack) {
      if (mounted) {
        debugPrint('Failed to restore sessions: $e\n$stack');
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  /// Save current sessions before app exit.
  Future<void> _saveSessions() async {
    try {
      for (final session in _restoredSessions) {
        await _sessionRestore.saveSession(session);
      }
    } catch (e, stack) {
      debugPrint('Failed to save sessions: $e\n$stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termisol Enhanced',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: _createMaterialColor(PkmTheme.primary),
        scaffoldBackgroundColor: PkmTheme.background,
      ),
      home: _isRestoring
          ? Scaffold(
              backgroundColor: PkmTheme.background,
              body: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(PkmTheme.primary),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Restoring sessions...',
                      style: TextStyle(
                        color: PkmTheme.text,
                        fontSize: 16,
                        fontFamily: PkmTheme.fontUi,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : HomeScreen(
              registry: widget.registry,
            ),
    );
  }

  @override
  void dispose() {
    _saveSessions();
    _sessionRestore.dispose();
    super.dispose();
  }

  MaterialColor _createMaterialColor(Color color) {
    final strengths = <double>[0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
    final swatch = <int, Color>{};
    final r = color.r, g = color.g, b = color.b;
    for (final strength in strengths) {
      final ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromARGB(
        255,
        (r + (ds < 0 ? (255 - r) * -ds * 10 : r * ds * 10)).clamp(0, 255).round(),
        (g + (ds < 0 ? (255 - g) * -ds * 10 : g * ds * 10)).clamp(0, 255).round(),
        (b + (ds < 0 ? (255 - b) * -ds * 10 : b * ds * 10)).clamp(0, 255).round(),
      );
    }
    return MaterialColor(color.value, swatch);
  }
}
