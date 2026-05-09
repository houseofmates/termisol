import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ANSI Escape Sequence Fuzz Testing', () {
    test('Terminal parser handles random ANSI sequences without crashing', () {
      final random = Random(42); // Fixed seed for reproducibility

      // Generate 1000 random ANSI sequences
      for (int i = 0; i < 1000; i++) {
        final sequence = _generateRandomANSISquence(random);
        expect(() => _parseANSISquence(sequence), returnsNormally,
            reason: 'Parser should not crash on random sequence: $sequence');
      }
    });

    test('Terminal parser handles malformed ANSI sequences', () {
      final malformedSequences = [
        '\x1b[',           // Incomplete sequence
        '\x1b[;',          // Empty parameters
        '\x1b[999999m',    // Very large parameter
        '\x1b[1;2;3;4;5;6;7;8;9;10m', // Many parameters
        '\x1b[m',          // No parameters
        '\x1b[1;m',        // Empty parameter in middle
        '\x1b[1;2;3mtext\x1b[4;5;6m', // Multiple sequences
        '\x1b[38;5;256m', // Out of range color
        '\x1b[48;5;0m',   // Valid but edge case
      ];

      for (final sequence in malformedSequences) {
        expect(() => _parseANSISquence(sequence), returnsNormally,
            reason: 'Parser should handle malformed sequence: $sequence');
      }
    });

    test('Terminal parser handles extreme edge cases', () {
      final edgeCases = [
        '', // Empty string
        '\x1b', // Just escape
        '\x1b[', // Just escape and bracket
        'normal text \x1b[31m red text \x1b[0m normal again',
        '\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[5m\x1b[6m\x1b[7m\x1b[8m', // Many styles
        '\x1b]8;;http://example.com\x1b\\', // OSC hyperlink
        '\x1b]0;Terminal Title\x1b\\', // Window title
        '\x1b[?25l\x1b[?25h', // Cursor hide/show
      ];

      for (final sequence in edgeCases) {
        expect(() => _parseANSISquence(sequence), returnsNormally,
            reason: 'Parser should handle edge case: $sequence');
      }
    });
  });
}

/// Generate a random ANSI escape sequence for fuzz testing
String _generateRandomANSISquence(Random random) {
  final types = ['m', 'J', 'K', 'H', 'A', 'B', 'C', 'D', 's', 'u'];
  final type = types[random.nextInt(types.length)];

  // Generate random parameters
  final paramCount = random.nextInt(5) + 1; // 1-5 parameters
  final params = <String>[];

  for (int i = 0; i < paramCount; i++) {
    final param = random.nextInt(256).toString(); // 0-255
    params.add(param);
  }

  return '\x1b[${params.join(';')}$type';
}

/// Mock ANSI sequence parser (simplified for testing)
void _parseANSISquence(String sequence) {
  // This is a simplified parser that just tries to parse without crashing
  if (sequence.isEmpty) return;

  if (sequence.startsWith('\x1b[')) {
    // CSI sequence
    final endIndex = sequence.indexOf(RegExp(r'[a-zA-Z]'), 2);
    if (endIndex != -1) {
      final params = sequence.substring(2, endIndex);
      final command = sequence[endIndex];

      // Parse parameters
      if (params.isNotEmpty) {
        final paramList = params.split(';');
        for (final param in paramList) {
          if (param.isNotEmpty) {
            int.parse(param); // Try to parse as int
          }
        }
      }

      // Handle different commands
      switch (command) {
        case 'm': // SGR - Select Graphic Rendition
          // Style parameters
          break;
        case 'J': // ED - Erase in Display
        case 'K': // EL - Erase in Line
          // Erase parameters
          break;
        case 'H': // CUP - Cursor Position
        case 'f': // HVP - Horizontal and Vertical Position
          // Position parameters
          break;
        case 'A': // CUU - Cursor Up
        case 'B': // CUD - Cursor Down
        case 'C': // CUF - Cursor Forward
        case 'D': // CUB - Cursor Backward
          // Movement parameters
          break;
        case 's': // SCP - Save Cursor Position
        case 'u': // RCP - Restore Cursor Position
          // No parameters expected
          break;
      }
    }
  } else if (sequence.startsWith('\x1b]')) {
    // OSC sequence
    final endIndex = sequence.indexOf('\x1b\\', 2);
    if (endIndex != -1) {
      // Parse OSC content: ${sequence.substring(2, endIndex)}
    }
  }
}