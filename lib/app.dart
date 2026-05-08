import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/service_registry.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
import 'core/production_config_system.dart';

class TermisolApp extends StatelessWidget {
  final ServiceRegistry registry;

  const TermisolApp({super.key, required this.registry});

  @override
  Widget build(BuildContext context) {
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

    // Check if running on VR device
    final isVr = _isVrDevice();

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: isVr ? _buildVrHome(registry) : HomeScreen(registry: registry),
    );
  }

  bool _isVrDevice() {
    if (!Platform.isAndroid) return false;
    return false; // VR support removed — uses standard Android build
  }

  Widget _buildVrHome(ServiceRegistry registry) {
    // For VR, use a simplified interface
    return Container(
      color: PkmTheme.background,
      child: Center(
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
