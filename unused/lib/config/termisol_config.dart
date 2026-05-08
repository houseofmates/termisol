import 'dart:ui' as ui;

/// Terminal appearance and behavior configuration for Termisol.
///
/// This class holds all user-configurable terminal settings. It is immutable;
/// use [copyWith] to create modified instances. Values can be loaded from and
/// saved to JSON for persistence.
class TermisolConfig {
  final String fontFamily;
  final double fontSize;
  final ui.Color backgroundColor;
  final ui.Color foregroundColor;
  final ui.Color cursorColor;
  final bool cursorBlink;
  final double cursorBlinkRate;
  final CursorStyle cursorStyle;
  final int scrollbackLines;
  final bool enableLigatures;
  final ClipboardConfig clipboard;
  final ShellConfig shell;
  final BehaviorConfig behavior;
  final TabConfig tabs;

  const TermisolConfig({
    this.fontFamily = 'monospace',
    this.fontSize = 14.0,
    this.backgroundColor = const ui.Color(0xFF000000),
    this.foregroundColor = const ui.Color(0xFF00FF00),
    this.cursorColor = const ui.Color(0xFF00FF00),
    this.cursorBlink = true,
    this.cursorBlinkRate = 500.0,
    this.cursorStyle = CursorStyle.block,
    this.scrollbackLines = 50000,
    this.enableLigatures = false,
    this.clipboard = const ClipboardConfig(),
    this.shell = const ShellConfig(),
    this.behavior = const BehaviorConfig(),
    this.tabs = const TabConfig(),
  });

  /// Default dark configuration optimized for readability.
  static const TermisolConfig defaultConfig = TermisolConfig(
    fontFamily: 'JetBrains Mono',
    fontSize: 14.0,
    backgroundColor: ui.Color(0xFF0A0A0A),
    foregroundColor: ui.Color(0xFF00D4AA),
    cursorColor: ui.Color(0xFF00D4AA),
    cursorBlink: true,
    cursorBlinkRate: 500.0,
    cursorStyle: CursorStyle.block,
    scrollbackLines: 100000,
    enableLigatures: false,
    clipboard: ClipboardConfig(),
    shell: ShellConfig(),
    behavior: BehaviorConfig(),
    tabs: TabConfig(),
  );

  TermisolConfig copyWith({
    String? fontFamily,
    double? fontSize,
    ui.Color? backgroundColor,
    ui.Color? foregroundColor,
    ui.Color? cursorColor,
    bool? cursorBlink,
    double? cursorBlinkRate,
    CursorStyle? cursorStyle,
    int? scrollbackLines,
    bool? enableLigatures,
    ClipboardConfig? clipboard,
    ShellConfig? shell,
    BehaviorConfig? behavior,
    TabConfig? tabs,
  }) {
    return TermisolConfig(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      cursorColor: cursorColor ?? this.cursorColor,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      cursorBlinkRate: cursorBlinkRate ?? this.cursorBlinkRate,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      enableLigatures: enableLigatures ?? this.enableLigatures,
      clipboard: clipboard ?? this.clipboard,
      shell: shell ?? this.shell,
      behavior: behavior ?? this.behavior,
      tabs: tabs ?? this.tabs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'backgroundColor': backgroundColor.value,
      'foregroundColor': foregroundColor.value,
      'cursorColor': cursorColor.value,
      'cursorBlink': cursorBlink,
      'cursorBlinkRate': cursorBlinkRate,
      'cursorStyle': cursorStyle.name,
      'scrollbackLines': scrollbackLines,
      'enableLigatures': enableLigatures,
      'clipboard': clipboard.toJson(),
      'shell': shell.toJson(),
      'behavior': behavior.toJson(),
      'tabs': tabs.toJson(),
    };
  }

  factory TermisolConfig.fromJson(Map<String, dynamic> json) {
    return TermisolConfig(
      fontFamily: json['fontFamily'] ?? 'monospace',
      fontSize: (json['fontSize'] ?? 14.0).toDouble(),
      backgroundColor: ui.Color(json['backgroundColor'] ?? 0xFF000000),
      foregroundColor: ui.Color(json['foregroundColor'] ?? 0xFF00FF00),
      cursorColor: ui.Color(json['cursorColor'] ?? 0xFF00FF00),
      cursorBlink: json['cursorBlink'] ?? true,
      cursorBlinkRate: (json['cursorBlinkRate'] ?? 500.0).toDouble(),
      cursorStyle: CursorStyle.values.byName(json['cursorStyle'] ?? 'block'),
      scrollbackLines: json['scrollbackLines'] ?? 50000,
      enableLigatures: json['enableLigatures'] ?? false,
      clipboard: ClipboardConfig.fromJson(json['clipboard'] ?? {}),
      shell: ShellConfig.fromJson(json['shell'] ?? {}),
      behavior: BehaviorConfig.fromJson(json['behavior'] ?? {}),
      tabs: TabConfig.fromJson(json['tabs'] ?? {}),
    );
  }
}

/// Cursor visual style.
enum CursorStyle { block, line, bar }

/// Clipboard-related settings.
class ClipboardConfig {
  final bool enableBracketedPaste;
  final bool copyOnSelect;
  final bool trimTrailingWhitespace;
  final int historySize;

  const ClipboardConfig({
    this.enableBracketedPaste = true,
    this.copyOnSelect = false,
    this.trimTrailingWhitespace = true,
    this.historySize = 50,
  });

  Map<String, dynamic> toJson() => {
    'enableBracketedPaste': enableBracketedPaste,
    'copyOnSelect': copyOnSelect,
    'trimTrailingWhitespace': trimTrailingWhitespace,
    'historySize': historySize,
  };

  factory ClipboardConfig.fromJson(Map<String, dynamic> json) {
    return ClipboardConfig(
      enableBracketedPaste: json['enableBracketedPaste'] ?? true,
      copyOnSelect: json['copyOnSelect'] ?? false,
      trimTrailingWhitespace: json['trimTrailingWhitespace'] ?? true,
      historySize: json['historySize'] ?? 50,
    );
  }
}

/// Shell execution settings.
class ShellConfig {
  final String shellPath;
  final List<String> arguments;
  final String? workingDirectory;

  const ShellConfig({
    this.shellPath = 'auto',
    this.arguments = const ['-l'],
    this.workingDirectory,
  });

  Map<String, dynamic> toJson() => {
    'shellPath': shellPath,
    'arguments': arguments,
    'workingDirectory': workingDirectory,
  };

  factory ShellConfig.fromJson(Map<String, dynamic> json) {
    return ShellConfig(
      shellPath: json['shellPath'] ?? 'auto',
      arguments: List<String>.from(json['arguments'] ?? ['-l']),
      workingDirectory: json['workingDirectory'],
    );
  }
}

/// General behavior settings.
class BehaviorConfig {
  final bool closeOnExit;
  final bool confirmBeforeClose;
  final bool notifyOnBell;
  final bool scrollOnInput;

  const BehaviorConfig({
    this.closeOnExit = true,
    this.confirmBeforeClose = true,
    this.notifyOnBell = false,
    this.scrollOnInput = true,
  });

  Map<String, dynamic> toJson() => {
    'closeOnExit': closeOnExit,
    'confirmBeforeClose': confirmBeforeClose,
    'notifyOnBell': notifyOnBell,
    'scrollOnInput': scrollOnInput,
  };

  factory BehaviorConfig.fromJson(Map<String, dynamic> json) {
    return BehaviorConfig(
      closeOnExit: json['closeOnExit'] ?? true,
      confirmBeforeClose: json['confirmBeforeClose'] ?? true,
      notifyOnBell: json['notifyOnBell'] ?? false,
      scrollOnInput: json['scrollOnInput'] ?? true,
    );
  }
}

/// Tab bar appearance and behavior settings.
class TabConfig {
  final TabPosition position;
  final bool showCloseButton;

  const TabConfig({
    this.position = TabPosition.top,
    this.showCloseButton = true,
  });

  Map<String, dynamic> toJson() => {
    'position': position.name,
    'showCloseButton': showCloseButton,
  };

  factory TabConfig.fromJson(Map<String, dynamic> json) {
    return TabConfig(
      position: TabPosition.values.byName(json['position'] ?? 'top'),
      showCloseButton: json['showCloseButton'] ?? true,
    );
  }
}

/// Tab bar position.
enum TabPosition { top, bottom }
