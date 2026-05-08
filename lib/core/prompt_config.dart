/// Centralized prompt color configuration for all termisol backends.
///
/// username@hostname: ~/directory $
/// ^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^
///     #f6b012            #35c7ff
///
/// Main terminal text: #d8ba75
class PromptConfig {
  PromptConfig._();

  // ANSI 24-bit color escapes
  static const String _usernameColor = r'\[\e[38;2;246;176;18m\]';
  static const String _directoryColor = r'\[\e[38;2;53;199;255m\]';
  static const String _promptCharColor = r'\[\e[38;2;216;186;117m\]';
  static const String _reset = r'\[\e[0m\]';

  /// Bash/zsh PS1 string with termisol colors.
  /// Uses \u, \h, \w which bash/zsh interpret.
  static String get bashPs1 =>
      '$_usernameColor\\u@\\h$_reset:$_directoryColor\\w$_reset$_promptCharColor\\\$_reset ';

  /// Portable PS1 for shells that don't support \\u/\\h/\\w (e.g. Android /system/bin/sh).
  /// Callers should substitute USER, HOST, and PWD before sending.
  static String portablePs1({required String user, required String host, required String pwd}) {
    return '$_usernameColor$user@$host$_reset:$_directoryColor$pwd$_reset$_promptCharColor\$$_reset ';
  }

  /// Raw escape sequences (without the bash \\[\\] wrappers) for direct terminal.write() usage.
  static String get usernameAnsi => '\x1b[38;2;246;176;18m';
  static String get directoryAnsi => '\x1b[38;2;53;199;255m';
  static String get promptCharAnsi => '\x1b[38;2;216;186;117m';
  static String get resetAnsi => '\x1b[0m';
}
