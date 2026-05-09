import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show CellColor, PaletteBuilder, TerminalTheme;

/// Resolves terminal cell colors into Flutter [Color] values.
///
/// Maintains a 256-color palette built from the active [TerminalTheme] and
/// handles the four CellColor encoding types: normal, named, palette, and rgb.
class TerminalColorResolver {
  TerminalColorResolver(this._theme) : _palette = PaletteBuilder(_theme).build();

  TerminalTheme _theme;
  List<Color> _palette;

  TerminalTheme get theme => _theme;

  set theme(TerminalTheme value) {
    if (_theme == value) return;
    _theme = value;
    _palette = PaletteBuilder(value).build();
  }

  void updateTheme(TerminalTheme value) => theme = value;

  @pragma('vm:prefer-inline')
  Color resolveForeground(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _palette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  @pragma('vm:prefer-inline')
  Color resolveBackground(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _palette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
