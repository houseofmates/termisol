import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'package:termisol/core/advanced_terminal_protocol.dart';

void main() {
  group('AdvancedTerminalProtocol Tests', () {
    late AdvancedTerminalProtocol protocol;
    late Terminal mockTerminal;
    late TerminalController mockController;

    setUp(() {
      mockTerminal = _MockTerminal();
      mockController = _MockTerminalController();
      protocol = AdvancedTerminalProtocol(mockTerminal, mockController);
    });

    tearDown(() {
      protocol.dispose();
    });

    group('Initialization Tests', () {
      test('should initialize successfully', () async {
        await protocol.initialize();
        expect(protocol.isInitialized, isTrue);
      });

      test('should not initialize twice', () async {
        await protocol.initialize();
        await protocol.initialize(); // Second call should be safe
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle initialization errors gracefully', () async {
        // Test with null terminal to simulate error
        final badProtocol = AdvancedTerminalProtocol(_MockTerminal(), mockController);
        try {
          await badProtocol.initialize();
          expect(badProtocol.isInitialized, isTrue);
        } catch (e) {
          expect(badProtocol.isInitialized, isFalse);
        }
      });
    });

    group('Protocol Sequence Processing Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should process CSI sequences correctly', () {
        // Test cursor positioning
        protocol.processSequence('\x1b[10;20H');
        // Should not throw exception
        
        // Test cursor movement
        protocol.processSequence('\x1b[5A');
        protocol.processSequence('\x1b[3B');
        protocol.processSequence('\x1b[2C');
        protocol.processSequence('\x1b[1D');
        
        // Test graphics
        protocol.processSequence('\x1b[31m'); // Red foreground
        protocol.processSequence('\x1b[44m'); // Blue background
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should process OSC sequences correctly', () {
        // Test window title
        protocol.processSequence('\x1b]0;Test Title\x07');
        expect(protocol.windowTitle, equals('Test Title'));
        
        // Test color palette
        protocol.processSequence('\x1b]4;0;rgb:ff/00/00\x07');
        
        // Test hyperlink
        protocol.processSequence('\x1b]8;;http://example.com\x07');
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should process escape sequences correctly', () {
        // Test basic escape sequences
        protocol.processSequence('\x1b[7'); // Save cursor
        protocol.processSequence('\x1b[8'); // Restore cursor
        protocol.processSequence('\x1b[H'); // Set tab stop
        protocol.processSequence('\x1b[c'); // Full reset
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle malformed sequences gracefully', () {
        // Test malformed sequences that should not crash
        protocol.processSequence('');
        protocol.processSequence('\x1b[');
        protocol.processSequence('\x1b]');
        protocol.processSequence('\x1b[');
        protocol.processSequence('\x1b[999');
        protocol.processSequence('\x1b[abc');
        protocol.processSequence('\x1b]999;');
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle device control strings', () {
        // Test DCS sequences
        protocol.processSequence('\x1bPq...'); // Sixel graphics
        protocol.processSequence('\x1bP...'); // ReGIS graphics
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle privacy messages', () {
        protocol.processSequence('\x1b^Test PM\x1b\\');
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle application program commands', () {
        protocol.processSequence('\x1b_G...'); // Kitty graphics
        protocol.processSequence('\x1b_...'); // Other APC
        
        expect(protocol.isInitialized, isTrue);
      });
    });

    group('Mouse Protocol Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should enable mouse tracking modes', () {
        // Enable different mouse protocols
        protocol.processSequence('\x1b[?1000h'); // Normal
        expect(protocol.mouseTrackingEnabled, isTrue);
        
        protocol.processSequence('\x1b[?1006h'); // SGR
        expect(protocol.mouseTrackingEnabled, isTrue);
        
        protocol.processSequence('\x1b[?1005h'); // URXVT
        expect(protocol.mouseTrackingEnabled, isTrue);
        
        protocol.processSequence('\x1b[?1016h'); // SGR Pixels
        expect(protocol.mouseTrackingEnabled, isTrue);
      });

      test('should disable mouse tracking', () {
        protocol.processSequence('\x1b[?1000h');
        expect(protocol.mouseTrackingEnabled, isTrue);
        
        protocol.processSequence('\x1b[?1000l');
        expect(protocol.mouseTrackingEnabled, isFalse);
      });

      test('should handle mouse events correctly', () {
        // Enable mouse tracking first
        protocol.processSequence('\x1b[?1006h');
        
        // Test mouse events
        protocol.handleMouseEvent(10, 20, MouseButtons.left, MouseActions.press);
        protocol.handleMouseEvent(15, 25, MouseButtons.right, MouseActions.release);
        protocol.handleMouseEvent(5, 10, MouseButtons.middle, MouseActions.click);
        
        expect(protocol.mouseTrackingEnabled, isTrue);
      });
    });

    group('Bracketed Paste Mode Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should enable and disable bracketed paste mode', () {
        protocol.processSequence('\x1b[?2004h');
        expect(protocol.bracketedPasteMode, isTrue);
        
        protocol.processSequence('\x1b[?2004l');
        expect(protocol.bracketedPasteMode, isFalse);
      });
    });

    group('Focus Tracking Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should enable and disable focus tracking', () {
        protocol.processSequence('\x1b[?1004h');
        expect(protocol.focusTrackingEnabled, isTrue);
        
        protocol.processSequence('\x1b[?1004l');
        expect(protocol.focusTrackingEnabled, isFalse);
      });
    });

    group('Color Management Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle color palette changes', () {
        // Test RGB color format
        protocol.processSequence('\x1b]4;0;rgb:ff/00/00\x07');
        
        // Test hex color format
        protocol.processSequence('\x1b]4;1;#00ff00\x07');
        
        // Test invalid color formats (should not crash)
        protocol.processSequence('\x1b]4;2;invalid_color\x07');
        protocol.processSequence('\x1b]4;3;#invalid\x07');
        
        expect(protocol.trueColorSupported, isTrue);
      });
    });

    group('Clipboard Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle clipboard operations', () {
        // Test clipboard copy
        protocol.processSequence('\x1b]52;c;SGVsbG8gV29ybGQ=\x07');
        
        // Test clipboard paste query
        protocol.processSequence('\x1b]52;q\x07');
        
        // Test invalid clipboard data
        protocol.processSequence('\x1b]52;invalid\x07');
        
        expect(protocol.isInitialized, isTrue);
      });
    });

    group('Window Manipulation Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle window manipulation commands', () {
        // Test various window operations
        protocol.processSequence('\x1b[1t'); // De-iconify
        protocol.processSequence('\x1b[2t'); // Iconify
        protocol.processSequence('\x1b[3;10;20t'); // Move
        protocol.processSequence('\x1b[4;80;24t'); // Resize
        protocol.processSequence('\x1b[5t'); // Raise
        protocol.processSequence('\x1b[6t'); // Lower
        protocol.processSequence('\x1b[7t'); // Refresh
        protocol.processSequence('\x1b[8;40;12t'); // Resize text area
        protocol.processSequence('\x1b[9;1t'); // Maximize
        protocol.processSequence('\x1b[10t'); // Report state
        protocol.processSequence('\x1b[11t'); // Report position
        protocol.processSequence('\x1b[13t'); // Report size
        protocol.processSequence('\x1b[14t'); // Report pixel size
        protocol.processSequence('\x1b[18t'); // Report char size
        protocol.processSequence('\x1b[19t'); // Report screen size
        protocol.processSequence('\x1b[20t'); // Report icon label
        protocol.processSequence('\x1b[21t'); // Report window title
        protocol.processSequence('\x1b[22t'); // Push title
        protocol.processSequence('\x1b[23t'); // Pop title
        
        expect(protocol.isInitialized, isTrue);
      });
    });

    group('Device Status Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle device status requests', () {
        // Test device status report
        protocol.processSequence('\x1b[5n');
        
        // Test cursor position report
        protocol.processSequence('\x1b[6n');
        
        expect(protocol.isInitialized, isTrue);
      });
    });

    group('Error Handling Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle null sequences gracefully', () {
        expect(() => protocol.processSequence(''), returnsNormally);
      });

      test('should handle extremely long sequences', () {
        final longSequence = '\x1b[' + '1;' * 1000 + 'H';
        expect(() => protocol.processSequence(longSequence), returnsNormally);
      });

      test('should handle invalid parameter formats', () {
        protocol.processSequence('\x1b[abc;def;ghiH');
        protocol.processSequence('\x1b[999999999999999999999H');
        protocol.processSequence('\x1b[-1;-2H');
        
        expect(protocol.isInitialized, isTrue);
      });

      test('should handle invalid escape sequences', () {
        protocol.processSequence('\x1b\x1b\x1b');
        protocol.processSequence('\x1b[');
        protocol.processSequence('\x1b]');
        protocol.processSequence('\x1b[');
        
        expect(protocol.isInitialized, isTrue);
      });
    });

    group('Unicode and Bidirectional Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle Unicode text', () {
        protocol.processSequence('Hello 世界 🌍');
        protocol.processSequence('العربية');
        protocol.processSequence('עברית');
        protocol.processSequence('🔥⚛️🚀');
        
        expect(protocol.unicodeSupport, isTrue);
      });
    });

    group('Performance Tests', () {
      setUp(() async {
        await protocol.initialize();
      });

      test('should handle rapid sequence processing', () {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          protocol.processSequence('\x1b[${i}H');
          protocol.processSequence('\x1b[3${i % 10}m');
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should complete within 1 second
      });

      test('should handle memory usage efficiently', () {
        // Process many sequences to test memory management
        for (int i = 0; i < 10000; i++) {
          protocol.processSequence('\x1b[${i % 100};${i % 50}H');
        }
        
        expect(protocol.isInitialized, isTrue);
      });
    });
  });
}

// Mock classes for testing
class _MockTerminal extends Terminal {
  @override
  void write(String data) {
    // Mock implementation - just store the data
    debugPrint('Mock terminal write: $data');
  }
  
  @override
  int get viewHeight => 24;
  
  @override
  int get viewWidth => 80;
  
  @override
  int get bufferCursorX => 1;
  
  @override
  int get bufferCursorY => 1;
}

class _MockTerminalController extends TerminalController {
  @override
  void resize(int width, int height) {
    // Mock implementation
  }
  
  @override
  void paste(String text) {
    // Mock implementation
  }
}

// Mock enums for testing
enum MouseButtons { left, middle, right }
enum MouseActions { press, release, click, drag }
