import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'core/service_registry.dart';
import 'core/vr_platform_channel.dart';
import 'ui/home_screen.dart';
import 'vr/vr_terminal.dart';
import 'config/pkm_theme.dart';

class TermisolApp extends StatefulWidget {
  final ServiceRegistry registry;

  const TermisolApp({super.key, required this.registry});

  @override
  State<TermisolApp> createState() => _TermisolAppState();
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
      final vrEnabled = widget.registry.isEnabled(TermisolFeatures.vrSupport);
      if (!vrEnabled) {
        if (mounted) {
          setState(() {
            _vrDetectionComplete = true;
            _isVrMode = false;
          });
        }
        return;
      }

      final vrSupported = await VrPlatformChannel.isVrSupported();
      if (mounted) {
        setState(() {
          _vrDetectionComplete = true;
          _isVrMode = vrSupported;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('VR detection failed: $e\n$stack');
      }
      if (mounted) {
        setState(() {
          _vrDetectionComplete = true;
          _isVrMode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_vrDetectionComplete) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
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
