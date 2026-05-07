import 'package:flutter/material.dart';

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
}
