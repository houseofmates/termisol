import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/service_registry.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
import 'core/production_config_system.dart';
import 'core/terminal_session.dart';
import 'vr/vr_terminal_view.dart';

class TermisolApp extends StatefulWidget {
  final ServiceRegistry registry;

  const TermisolApp({super.key, required this.registry});

  @override
  State<TermisolApp> createState() => _TermisolAppState();
}

class _TermisolAppState extends State<TermisolApp> {
  bool _isVr = false;

  @override
  void initState() {
    super.initState();
    PkmTheme.themeMode.addListener(_onThemeChanged);
    _loadSavedTheme();
    _detectVr();
  }

  @override
  void dispose() {
    PkmTheme.themeMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('termisol_theme_mode');
    if (saved != null) {
      try {
        PkmTheme.themeMode.value = TermisolThemeMode.values.byName(saved);
      } catch (_) {
        // invalid saved theme, ignore
      }
    }
  }

  Future<void> _detectVr() async {
    bool isVr = false;
    try {
      final config = ProductionConfigSystem();
      await config.initialize();
      final configVr = config.get<bool>('device.is_vr') ?? false;
      final featureVr = config.get<bool>('features.vr_support') ?? false;
      isVr = configVr || featureVr;

      if (Platform.isAndroid && !isVr) {
        const channel = MethodChannel('com.termisol/vr');
        final buildInfo = await channel.invokeMethod<Map<dynamic, dynamic>>('getBuildInfo');
        final model = (buildInfo?['model'] as String? ?? '').toLowerCase();
        final manufacturer = (buildInfo?['manufacturer'] as String? ?? '').toLowerCase();
        isVr = model.contains('quest') ||
               model.contains('oculus') ||
               manufacturer.contains('oculus');
      }
    } catch (e) {
      debugPrint('vr detection failed: $e');
    }

    if (mounted) {
      setState(() => _isVr = isVr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.varelaRoundTextTheme(
      PkmTheme.themeMode.value == TermisolThemeMode.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    );

    final theme = PkmTheme.activeMaterialTheme.copyWith(
      textTheme: baseTextTheme,
    );

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: _isVr ? _VrHome(registry: widget.registry) : HomeScreen(registry: widget.registry),
    );
  }
}

class _VrHome extends StatefulWidget {
  final ServiceRegistry registry;

  const _VrHome({required this.registry});

  @override
  State<_VrHome> createState() => _VrHomeState();
}

class _VrHomeState extends State<_VrHome> {
  TerminalSession? _session;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final session = TerminalSession(
      id: 'vr_main',
      name: 'VR Terminal',
    );
    try {
      await session.start();
      if (mounted) {
        setState(() {
          _session = session;
          _starting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _starting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_starting) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null || _session == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'vr session failed: ${_error ?? 'unknown'}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: VrTerminalView(session: _session!),
    );
  }
}
