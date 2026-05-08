import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/service_registry.dart';
import 'core/terminal_session.dart';
import 'session_restore_manager.dart';
import 'ui/home_screen.dart';
import 'ui/terminal_view_enhanced.dart';
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
    
    // Initialize session restore manager
    _sessionRestore = SessionRestoreManager();
    
    // Restore previous sessions on app start
    _restoreSessions();
  }

  /// Restore previous sessions.
  Future<void> _restoreSessions() async {
    if (_isRestoring) return;
    _isRestoring = true;
    
    try {
      final savedSessions = _sessionRestore.getSavedSessions();
      
      for (final sessionState in savedSessions) {
        final session = TerminalSession(
          id: sessionState.id,
          name: sessionState.name,
        );
        
        // Restore working directory
        await session.start(workingDirectory: sessionState.workingDirectory);
        
        _restoredSessions.add(session);
        debugPrint('🔄 Restored session: ${sessionState.name}');
      }
      
      setState(() {});
    } catch (e) {
      debugPrint('❌ Failed to restore sessions: $e');
    } finally {
      _isRestoring = false;
    }
  }

  /// Save current sessions before app exit.
  Future<void> _saveSessions() async {
    try {
      // Save all active sessions (would come from HomeScreen)
      for (final session in _restoredSessions) {
        await _sessionRestore.saveSession(session);
      }
      
      debugPrint('💾 Saved ${_restoredSessions.length} sessions');
    } catch (e) {
      debugPrint('❌ Failed to save sessions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termisol Enhanced',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: PkmTheme.primary,
        scaffoldBackgroundColor: PkmTheme.background,
      ),
      home: _isRestoring
          ? const Scaffold(
              backgroundColor: PkmTheme.background,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: PkmTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
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
          : HomeScreenEnhanced(
              registry: widget.registry,
              initialSessions: _restoredSessions,
              onSessionCreated: (session) {
                _restoredSessions.add(session);
                setState(() {});
              },
              onSessionDestroyed: (sessionId) {
                _restoredSessions.removeWhere((s) => s.id == sessionId);
                setState(() {});
              },
            ),
    );
  }

  @override
  void dispose() {
    _saveSessions();
    _sessionRestore.dispose();
    super.dispose();
  }
}
