import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/service_registry.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';

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

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: HomeScreen(registry: registry),
    );
  }
}
