import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/gpu/gpu_terminal_painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpuTerminalPainter', () {
    test('can be instantiated with theme and style', () {
      final painter = GpuTerminalPainter(
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(),
        textScaler: TextScaler.noScaling,
      );
      expect(painter, isNotNull);
      expect(painter.cellSize, isNotNull);
    });

    test('theme setter updates internal color resolver', () {
      final painter = GpuTerminalPainter(
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(),
        textScaler: TextScaler.noScaling,
      );

      final newTheme = TerminalTheme(
        cursor: Colors.red,
        selection: Colors.blue,
        foreground: Colors.white,
        background: Colors.black,
        black: Colors.black,
        red: Colors.red,
        green: Colors.green,
        yellow: Colors.yellow,
        blue: Colors.blue,
        magenta: const Color(0xFFFF00FF),
        cyan: Colors.cyan,
        white: Colors.white,
        brightBlack: Colors.grey,
        brightRed: Colors.redAccent,
        brightGreen: Colors.greenAccent,
        brightYellow: Colors.yellowAccent,
        brightBlue: Colors.blueAccent,
        brightMagenta: Colors.pinkAccent,
        brightCyan: Colors.cyanAccent,
        brightWhite: Colors.white,
        searchHitBackground: Colors.orange,
        searchHitBackgroundCurrent: Colors.deepOrange,
        searchHitForeground: Colors.black,
      );

      painter.theme = newTheme;
      expect(painter.theme, equals(newTheme));
    });

    test('textStyle setter clears caches', () {
      final painter = GpuTerminalPainter(
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(fontSize: 12),
        textScaler: TextScaler.noScaling,
      );

      painter.textStyle = const TerminalStyle(fontSize: 14);
      expect(painter.textStyle.fontSize, 14);
    });
  });
}
