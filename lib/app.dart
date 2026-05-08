import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/service_registry.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
import 'main.dart' as main;
import 'vr/vr_terminal.dart';

/// root application widget for termisol.
/// all services are accessed lazily via the registry.
class TermisolApp extends StatefulWidget {
  final ServiceRegistry registry;

  const TermisolApp({super.key, required this.registry});

  @override
  State<TermisolApp> createState() => _TermisolAppState();
}

class _TermisolAppState extends State<TermisolApp> {
  @override
  void initState() {
    super.initState();
    main.ErrorReporter.onErrorChanged = () {
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.varelaRoundTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: PkmTheme.primary,
          secondary: PkmTheme.secondary,
          surface: PkmTheme.popup,
          surfaceContainerHighest: PkmTheme.tabActiveBg,
        ),
        scaffoldBackgroundColor: PkmTheme.background,
        textTheme: baseTextTheme,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: PkmTheme.popup,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: PkmTheme.popup,
        ),
      ),
      home: Stack(
        children: [
          HomeScreen(registry: widget.registry),
          if (main.ErrorReporter.currentError != null)
            _ErrorDialog(error: main.ErrorReporter.currentError!),
        ],
      ),
    );
  }
}

class _ErrorDialog extends StatelessWidget {
  final String error;

  const _ErrorDialog({required this.error});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: PkmTheme.popup,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: TextStyle(
                  color: PkmTheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'An unexpected error occurred. The error has been logged for review.',
                style: TextStyle(
                  color: PkmTheme.primary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Error details: ${error.length > 100 ? error.substring(0, 100) + '...' : error}',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  main.ErrorReporter.clearError();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: PkmTheme.primary,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermisolAppState extends State<TermisolApp> {
  bool _isVrMode = false;
  bool _vrDetectionComplete = false;

  @override
  void initState() {
    super.initState();
    _detectVrMode();
  }

  Future<void> _detectVrMode() async {
    try {
      // Check if VR is enabled in service registry
      final vrEnabled = widget.registry.isEnabled(TermisolFeatures.vrSupport);
      if (!vrEnabled) {
        setState(() {
          _vrDetectionComplete = true;
          _isVrMode = false;
        });
        return;
      }

      // Check if device supports VR
      final vrSupported = await VrPlatformChannel.isVrSupported();
      setState(() {
        _vrDetectionComplete = true;
        _isVrMode = vrSupported;
      });
    } catch (e) {
      // On error, default to 2D mode
      setState(() {
        _vrDetectionComplete = true;
        _isVrMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_vrDetectionComplete) {
      // Show loading screen while detecting VR
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final baseTextTheme = GoogleFonts.varelaRoundTextTheme(
      ThemeData.dark().textTheme,
    );

    final theme = ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: PkmTheme.primary,
        secondary: PkmTheme.secondary,
        surface: PkmTheme.popup,
        surfaceContainerHighest: PkmTheme.tabActiveBg,
      ),
      scaffoldBackgroundColor: PkmTheme.background,
      textTheme: baseTextTheme,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PkmTheme.popup,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: PkmTheme.popup,
      ),
    );

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: _isVrMode
          ? VrTerminal(
              registry: widget.registry,
              terminalWidget: HomeScreen(registry: widget.registry),
            )
          : HomeScreen(registry: widget.registry),
    );
  }
}
