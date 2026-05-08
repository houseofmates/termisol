import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Theme mode options for termisol.
enum TermisolThemeMode { dark, light, retro }

/// strict pkm aesthetic constants for termisol.
/// no operator overrides. no deviations.
class PkmTheme {
  PkmTheme._();

  static const Color background = Color(0xFF050505);
  static const Color popup = Color(0xFF000000);
  static const Color primary = Color(0xFFf6b012);
  static const Color secondary = Color(0xFF3c9fdd);
  static const Color text = Colors.white;
  static const Color tabActiveBg = Color(0xFF111111);
  static const Color tabInactiveBg = Color(0xFF0a0a0a);
  static const Color terminalBg = Color(0xFF000000);
  static const Color statusConnected = Color(0xFFf6b012);
  static const Color statusDisconnected = Color(0xFF3c9fdd);

  static const String fontUi = 'Varela Round';
  static const String fontTerminal = 'Droid Sans Mono';

  static const double tabBarHeight = 40.0;
  static const double mobileTopPadding = 0.0;

  /// Singleton notifier for the active theme mode.
  static final ValueNotifier<TermisolThemeMode> themeMode =
      ValueNotifier(TermisolThemeMode.dark);

  /// Map of terminal themes for each mode.
  static const Map<TermisolThemeMode, TerminalTheme> terminalThemes = {
    TermisolThemeMode.dark: TerminalTheme(
      cursor: Color(0xFFFFAA00),
      selection: Color(0xFF0A0E1A),
      foreground: Color(0xFFFFD6A5),
      background: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFFF0000),
      green: Color(0xFF00CC00),
      yellow: Color(0xFFCCCC00),
      blue: Color(0xFF0000FF),
      magenta: Color(0xFFFF00FF),
      cyan: Color(0xFF00CCCC),
      white: Color(0xFFE5E5E5),
      brightBlack: Color(0xFF808080),
      brightRed: Color(0xFFFF0000),
      brightGreen: Color(0xFF00FF00),
      brightYellow: Color(0xFFFFFF00),
      brightBlue: Color(0xFF6666FF),
      brightMagenta: Color(0xFFFF00FF),
      brightCyan: Color(0xFF00FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TermisolThemeMode.light: TerminalTheme(
      cursor: Color(0xFF333333),
      selection: Color(0xFFB0B0B0),
      foreground: Color(0xFF1A1A1A),
      background: Color(0xFFF0F0F0),
      black: Color(0xFF000000),
      red: Color(0xFFFF0000),
      green: Color(0xFF00CC00),
      yellow: Color(0xFFCCCC00),
      blue: Color(0xFF0000FF),
      magenta: Color(0xFFFF00FF),
      cyan: Color(0xFF00CCCC),
      white: Color(0xFFE5E5E5),
      brightBlack: Color(0xFF808080),
      brightRed: Color(0xFFFF0000),
      brightGreen: Color(0xFF00FF00),
      brightYellow: Color(0xFFFFFF00),
      brightBlue: Color(0xFF6666FF),
      brightMagenta: Color(0xFFFF00FF),
      brightCyan: Color(0xFF00FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TermisolThemeMode.retro: TerminalTheme(
      cursor: Color(0xFFFFB000),
      selection: Color(0xFF332200),
      foreground: Color(0xFFFFB000),
      background: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFFF4444),
      green: Color(0xFF44FF44),
      yellow: Color(0xFFFFFF44),
      blue: Color(0xFF4444FF),
      magenta: Color(0xFFFF44FF),
      cyan: Color(0xFF44FFFF),
      white: Color(0xFFCCCCCC),
      brightBlack: Color(0xFF666666),
      brightRed: Color(0xFFFF6666),
      brightGreen: Color(0xFF66FF66),
      brightYellow: Color(0xFFFFFF66),
      brightBlue: Color(0xFF6666FF),
      brightMagenta: Color(0xFFFF66FF),
      brightCyan: Color(0xFF66FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  };

  /// Returns the active terminal theme based on [themeMode].
  static TerminalTheme get activeTerminalTheme =>
      terminalThemes[themeMode.value]!;

  /// Map of Material themes for each mode.
  static final Map<TermisolThemeMode, ThemeData> materialThemes = {
    TermisolThemeMode.dark: _buildDarkTheme(),
    TermisolThemeMode.light: _buildLightTheme(),
    TermisolThemeMode.retro: _buildRetroTheme(),
  };

  /// Returns the active Material theme based on [themeMode].
  static ThemeData get activeMaterialTheme =>
      materialThemes[themeMode.value]!;

  static ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: popup,
        surfaceContainerHighest: tabActiveBg,
      ),
      scaffoldBackgroundColor: background,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: popup,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: popup,
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF333333),
        secondary: Color(0xFF3c9fdd),
        surface: Colors.white,
        surfaceContainerHighest: Color(0xFFF0F0F0),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
      ),
    );
  }

  static ThemeData _buildRetroTheme() {
    return ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFB000),
        secondary: Color(0xFFFFD54F),
        surface: Color(0xFF000000),
        surfaceContainerHighest: Color(0xFF111111),
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF000000),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF000000),
      ),
    );
  }
}
