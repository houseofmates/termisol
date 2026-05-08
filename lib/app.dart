import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/service_registry.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
import 'core/production_config_system.dart';

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
    PkmTheme.themeMode.addListener(_onThemeChanged);
    _loadSavedTheme();
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
        // Invalid saved theme, ignore
      }
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

    // Check if running on VR device
    final isVr = _isVrDevice();

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: isVr ? _buildVrHome(widget.registry) : HomeScreen(registry: widget.registry),
    );
  }

  bool _isVrDevice() {
    if (!Platform.isAndroid) return false;
    // Check config for VR support
    try {
      final config = ProductionConfigSystem();
      final isVr = config.get<bool>('device.is_vr') ?? false;
      final vrSupport = config.get<bool>('features.vr_support') ?? false;
      return isVr || vrSupport;
    } catch (e) {
      return false;
    }
  }

  Widget _buildVrHome(ServiceRegistry registry) {
    // For VR, use a simplified interface
    return Container(
      color: PkmTheme.background,
      child: const Center(
        child: Text(
          'VR Mode Not Fully Implemented',
          style: TextStyle(
            color: PkmTheme.primary,
            fontSize: 24,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
      ),
    );
  }
}
