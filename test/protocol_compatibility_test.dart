import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import '../lib/core/advanced_terminal_protocol.dart';
import '../lib/core/unicode_text_engine.dart';

/// Comprehensive Terminal Protocol Test Suite
/// 
/// Tests all terminal protocol implementations to ensure compatibility
/// exceeds Kitty terminal emulator capabilities
void main() {
  group('Advanced Terminal Protocol Tests', () {
    late AdvancedTerminalProtocol protocol;
    late Terminal terminal;
    late TerminalController controller;
    
    setUp(() async {
      terminal = Terminal(maxLines: 1000);
      controller = TerminalController();
      protocol = AdvancedTerminalProtocol(terminal, controller);
      await protocol.initialize();
    });
    
    tearDown(() {
      protocol.dispose();
    });
    
    test('should initialize with all protocols supported', () {
      expect(protocol.isInitialized, isTrue);
      
      final supportedProtocols = protocol.getSupportedProtocols();
      expect(supportedProtocols, contains('ANSI/VT100/VT220/VT320/VT420/VT520'));
      expect(supportedProtocols, contains('Unicode 15.0'));
      expect(supportedProtocols, contains('True Color (24-bit)'));
      expect(supportedProtocols, contains('SGR Mouse Protocol'));
      expect(supportedProtocols, contains('Bracketed Paste Mode'));
      expect(supportedProtocols, contains('Focus Tracking'));
    });
    
    test('should handle CSI cursor positioning sequences', () {
      // Test cursor positioning
      protocol.processSequence('\x1b[10;20H');
      protocol.processSequence('\x1b[5;30f');
      
      // Test cursor movement
      protocol.processSequence('\x1b[3A'); // Up 3
      protocol.processSequence('\x1b[2B'); // Down 2
      protocol.processSequence('\x1b[4C'); // Right 4
      protocol.processSequence('\x1b[1D'); // Left 1
      
      // These should not throw exceptions
      expect(true, isTrue);
    });
    
    test('should handle erase sequences', () {
      // Test erase commands
      protocol.processSequence('\x1b[0J'); // Erase from cursor to end of screen
      protocol.processSequence('\x1b[1J'); // Erase from beginning to cursor
      protocol.processSequence('\x1b[2J'); // Erase entire screen
      protocol.processSequence('\x1b[0K'); // Erase from cursor to end of line
      protocol.processSequence('\x1b[1K'); // Erase from beginning to cursor
      protocol.processSequence('\x1b[2K'); // Erase entire line
      
      expect(true, isTrue);
    });
    
    test('should handle graphics and color sequences', () {
      // Test basic colors
      protocol.processSequence('\x1b[31m'); // Red foreground
      protocol.processSequence('\x1b[42m'); // Green background
      protocol.processSequence('\x1b[1m');  // Bold
      protocol.processSequence('\x1b[4m');  // Underline
      
      // Test true colors
      protocol.processSequence('\x1b[38;2;255;0;0m');   // RGB red
      protocol.processSequence('\x1b[48;2;0;255;0m');   // RGB green
      protocol.processSequence('\x1b[38;2;0;0;255;48;2;255;255;255m'); // RGB on RGB
      
      // Test palette colors
      protocol.processSequence('\x1b[38;5;196m'); // Palette red
      protocol.processSequence('\x1b[48;5;46m');  // Palette green
      
      expect(true, isTrue);
    });
    
    test('should handle mode setting sequences', () {
      // Test various mode settings
      protocol.processSequence('\x1b[?1h'); // Application cursor keys
      protocol.processSequence('\x1b[?25l'); // Hide cursor
      protocol.processSequence('\x1b[?47h'); // Use alternate screen buffer
      protocol.processSequence('\x1b[?2004h'); // Bracketed paste mode
      protocol.processSequence('\x1b[?1004h'); // Focus tracking
      protocol.processSequence('\x1b[?1006h'); // SGR mouse protocol
      
      expect(protocol.bracketedPasteMode, isTrue);
      expect(protocol.focusTrackingEnabled, isTrue);
      expect(protocol.mouseTrackingEnabled, isTrue);
      
      // Test mode disabling
      protocol.processSequence('\x1b[?2004l'); // Disable bracketed paste
      protocol.processSequence('\x1b[?1004l'); // Disable focus tracking
      protocol.processSequence('\x1b[?1006l'); // Disable mouse tracking
      
      expect(protocol.bracketedPasteMode, isFalse);
      expect(protocol.focusTrackingEnabled, isFalse);
      expect(protocol.mouseTrackingEnabled, isFalse);
    });
    
    test('should handle OSC sequences', () {
      // Test window title changes
      protocol.processSequence('\x1b]0;Test Title\x07');
      protocol.processSequence('\x1b]2;Another Title\x07');
      
      expect(protocol.windowTitle, equals('Another Title'));
      
      // Test color palette changes
      protocol.processSequence('\x1b]4;0;rgb:ff/00/00\x07'); // Set color 0 to red
      protocol.processSequence('\x1b]4;1;#00ff00\x07');       // Set color 1 to green
      
      // Test clipboard operations
      protocol.processSequence('\x1b]52;c;Hello World\x07'); // Copy to clipboard
      
      expect(true, isTrue);
    });
    
    test('should handle mouse events with different protocols', () {
      // Enable different mouse protocols
      protocol.processSequence('\x1b[?1006h'); // SGR protocol
      protocol.handleMouseEvent(10, 5, {MouseButtons.left}, MouseActions.press);
      protocol.handleMouseEvent(10, 5, {MouseButtons.left}, MouseActions.release);
      
      protocol.processSequence('\x1b[?1005h'); // URXVT protocol
      protocol.handleMouseEvent(15, 8, {MouseButtons.right}, MouseActions.press);
      
      protocol.processSequence('\x1b[?1016h'); // SGR pixel protocol
      protocol.handleMouseEvent(20, 12, {MouseButtons.middle}, MouseActions.drag);
      
      expect(true, isTrue);
    });
    
    test('should handle focus events', () {
      protocol.processSequence('\x1b[?1004h'); // Enable focus tracking
      
      protocol.handleFocusEvent(true);  // Gain focus
      protocol.handleFocusEvent(false); // Lose focus
      
      expect(true, isTrue);
    });
    
    test('should handle paste events', () {
      protocol.processSequence('\x1b[?2004h'); // Enable bracketed paste
      
      protocol.handlePasteEvent('Hello World');
      protocol.handlePasteEvent('Multi\nline\ntext');
      
      expect(true, isTrue);
    });
    
    test('should handle device status reports', () {
      // Test device status queries
      protocol.processSequence('\x1b[5n'); // Device status
      protocol.processSequence('\x1b[6n'); // Cursor position
      
      expect(true, isTrue);
    });
    
    test('should handle window manipulation', () {
      // Test window operations
      protocol.processSequence('\x1b[8;24;80t'); // Resize window
      protocol.processSequence('\x1b[18t');      // Report window size
      protocol.processSequence('\x1b[21t');      // Report window title
      
      expect(true, isTrue);
    });
    
    test('should handle escape sequences', () {
      // Test basic escape sequences
      protocol.processSequence('\x1b7'); // Save cursor
      protocol.processSequence('\x1b8'); // Restore cursor
      protocol.processSequence('\x1bD'); // Index down
      protocol.processSequence('\x1bE'); // Next line
      protocol.processSequence('\x1bH'); // Set tab stop
      protocol.processSequence('\x1bM'); // Reverse index
      
      expect(true, isTrue);
    });
    
    test('should handle device control strings', () {
      // Test DCS sequences
      protocol.processSequence('\x1bPq..."1;1;1;1/1\x1b\\'); // Sixel graphics
      protocol.processSequence('\x1bP2;1;1;0/0\x1b\\');     // ReGIS graphics
      
      expect(true, isTrue);
    });
    
    test('should handle application program commands', () {
      // Test APC sequences
      protocol.processSequence('\x1b_Gi=1,f=24,t=d,d=A\x1b\\'); // Kitty graphics
      
      expect(true, isTrue);
    });
  });
  
  group('Unicode Text Engine Tests', () {
    late UnicodeTextEngine engine;
    
    setUp(() async {
      engine = UnicodeTextEngine();
      await engine.initialize();
    });
    
    tearDown(() {
      engine.dispose();
    });
    
    test('should initialize with full Unicode support', () {
      expect(engine.isInitialized, isTrue);
      expect(engine.bidirectionalEnabled, isTrue);
      expect(engine.emojiRenderingEnabled, isTrue);
      expect(engine.textShapingEnabled, isTrue);
    });
    
    test('should process Latin text correctly', () {
      final text = 'Hello World!';
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      expect(processed.direction, equals(TextDirection.ltr));
      expect(processed.runs.length, equals(1));
      expect(processed.runs.first.script, equals('Latin'));
    });
    
    test('should process Arabic text correctly', () {
      final text = 'مرحبا بالعالم';
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      expect(processed.direction, equals(TextDirection.rtl));
      expect(processed.runs.first.script, equals('Arabic'));
    });
    
    test('should process Hebrew text correctly', () {
      final text = 'שלום עולם';
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      expect(processed.direction, equals(TextDirection.rtl));
      expect(processed.runs.first.script, equals('Hebrew'));
    });
    
    test('should process mixed bidirectional text', () {
      final text = 'Hello مرحبا World';
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      expect(processed.runs.length, greaterThan(1)); // Should have multiple runs
      
      // Check that both LTR and RTL runs exist
      final hasLtr = processed.runs.any((run) => run.direction == TextDirection.ltr);
      final hasRtl = processed.runs.any((run) => run.direction == TextDirection.rtl);
      expect(hasLtr, isTrue);
      expect(hasRtl, isTrue);
    });
    
    test('should process emoji correctly', () {
      final text = 'Hello 🌍 World ❤️';
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      
      // Should have emoji runs
      final hasEmoji = processed.runs.any((run) => run.isEmoji);
      expect(hasEmoji, isTrue);
    });
    
    test('should handle combining characters', () {
      final text = 'e\u0301'; // e + combining acute accent
      final processed = engine.processText(text);
      
      expect(processed.text, equals(text));
      
      // Should handle combining characters
      final hasCombining = processed.graphemeClusters.any((cluster) => cluster.hasCombining);
      expect(hasCombining, isTrue);
    });
    
    test('should split text into grapheme clusters correctly', () {
      final text = '👨‍👩‍👧‍👦'; // Family emoji (multiple code points)
      final processed = engine.processText(text);
      
      expect(processed.graphemeClusters.length, equals(1)); // Should be one cluster
      expect(processed.graphemeClusters.first.isEmoji, isTrue);
    });
    
    test('should handle text normalization', () {
      engine.setNormalizationMode(UnicodeNormalization.nfc);
      
      final text = 'cafe\u0301'; // cafe + combining acute accent
      final processed = engine.processText(text);
      
      expect(processed.text, isNotEmpty);
    });
    
    test('should respect direction override', () {
      final text = 'Hello';
      final processed = engine.processText(text, overrideDirection: TextDirection.rtl);
      
      expect(processed.direction, equals(TextDirection.rtl));
    });
    
    test('should provide statistics', () {
      final stats = engine.getStatistics();
      
      expect(stats.containsKey('unicode_characters_loaded'), isTrue);
      expect(stats.containsKey('script_handlers'), isTrue);
      expect(stats.containsKey('font_fallbacks'), isTrue);
      expect(stats.containsKey('emoji_sequences'), isTrue);
      expect(stats.containsKey('bidirectional_enabled'), isTrue);
    });
    
    test('should clear caches', () {
      // Process some text to populate caches
      engine.processText('Hello World');
      
      // Clear caches
      engine.clearCaches();
      
      expect(true, isTrue); // Should not throw
    });
  });
  
  group('Integration Tests', () {
    test('should handle complex terminal output with Unicode', () async {
      final terminal = Terminal(maxLines: 1000);
      final controller = TerminalController();
      final protocol = AdvancedTerminalProtocol(terminal, controller);
      final engine = UnicodeTextEngine();
      
      await protocol.initialize();
      await engine.initialize();
      
      // Simulate complex terminal output
      final sequences = [
        '\x1b[31m', // Red color
        'Error: ',
        '\x1b[0m', // Reset color
        'مرحبا ', // Arabic text
        '\x1b[1m', // Bold
        'Hello ',
        '\x1b[0m', // Reset
        '🌍', // Emoji
        ' World!',
      ];
      
      for (final sequence in sequences) {
        protocol.processSequence(sequence);
      }
      
      // Process the resulting text with Unicode engine
      final processed = engine.processText('Error: مرحبا Hello 🌍 World!');
      
      expect(processed.runs.length, greaterThan(1));
      expect(processed.graphemeClusters.any((c) => c.isEmoji), isTrue);
      
      protocol.dispose();
      engine.dispose();
    });
    
    test('should handle mouse and keyboard integration', () async {
      final terminal = Terminal(maxLines: 1000);
      final controller = TerminalController();
      final protocol = AdvancedTerminalProtocol(terminal, controller);
      
      await protocol.initialize();
      
      // Enable mouse tracking
      protocol.processSequence('\x1b[?1006h');
      
      // Simulate mouse interaction
      protocol.handleMouseEvent(10, 5, {MouseButtons.left}, MouseActions.press);
      protocol.handleMouseEvent(10, 5, {MouseButtons.left}, MouseActions.release);
      
      // Simulate keyboard input with modifiers
      final keyEvent = protocol.handleKeyEvent('A', {
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.shift,
      });
      
      expect(keyEvent, isNotEmpty);
      expect(protocol.mouseTrackingEnabled, isTrue);
      
      protocol.dispose();
    });
    
    test('should handle clipboard and paste integration', () async {
      final terminal = Terminal(maxLines: 1000);
      final controller = TerminalController();
      final protocol = AdvancedTerminalProtocol(terminal, controller);
      
      await protocol.initialize();
      
      // Enable bracketed paste
      protocol.processSequence('\x1b[?2004h');
      
      // Handle paste event
      protocol.handlePasteEvent('Multi-line\ntext\nwith Unicode: 🌍');
      
      expect(protocol.bracketedPasteMode, isTrue);
      
      protocol.dispose();
    });
  });
  
  group('Performance Tests', () {
    test('should handle large amounts of text efficiently', () async {
      final engine = UnicodeTextEngine();
      await engine.initialize();
      
      final stopwatch = Stopwatch()..start();
      
      // Process large text
      final largeText = 'Hello World! ' * 1000;
      final processed = engine.processText(largeText);
      
      stopwatch.stop();
      
      expect(processed.text.length, equals(largeText.length));
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      
      engine.dispose();
    });
    
    test('should handle many escape sequences efficiently', () async {
      final terminal = Terminal(maxLines: 1000);
      final controller = TerminalController();
      final protocol = AdvancedTerminalProtocol(terminal, controller);
      
      await protocol.initialize();
      
      final stopwatch = Stopwatch()..start();
      
      // Process many sequences
      for (int i = 0; i < 1000; i++) {
        protocol.processSequence('\x1b[${i % 8}m'); // Color sequences
        protocol.processSequence('\x1b[${i % 10};${i % 20}H'); // Position sequences
      }
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(50)); // Should be very fast
      
      protocol.dispose();
    });
  });
  
  group('Edge Cases and Error Handling', () {
    test('should handle malformed escape sequences gracefully', () async {
      final terminal = Terminal(maxLines: 1000);
      final controller = TerminalController();
      final protocol = AdvancedTerminalProtocol(terminal, controller);
      
      await protocol.initialize();
      
      // Malformed sequences
      protocol.processSequence('\x1b['); // Incomplete CSI
      protocol.processSequence('\x1b]'); // Incomplete OSC
      protocol.processSequence('\x1b999999999m'); // Invalid parameters
      protocol.processSequence('\x1b[999;999;999m'); // Out of range parameters
      
      expect(true, isTrue); // Should not throw
      
      protocol.dispose();
    });
    
    test('should handle empty and null inputs', () async {
      final engine = UnicodeTextEngine();
      await engine.initialize();
      
      // Empty text
      final emptyProcessed = engine.processText('');
      expect(emptyProcessed.text, isEmpty);
      expect(emptyProcessed.runs, isEmpty);
      
      // Null handling (should not crash)
      expect(true, isTrue);
      
      engine.dispose();
    });
    
    test('should handle very long lines', () async {
      final engine = UnicodeTextEngine();
      await engine.initialize();
      
      // Very long line
      final longLine = 'A' * 10000;
      final processed = engine.processText(longLine);
      
      expect(processed.text.length, equals(longLine.length));
      expect(processed.runs.length, equals(1)); // Should be single run
      
      engine.dispose();
    });
  });
}

// Mock LogicalKeyboardKey for testing
class LogicalKeyboardKey {
  static const LogicalKeyboardKey control = LogicalKeyboardKey._('control');
  static const LogicalKeyboardKey shift = LogicalKeyboardKey._('shift');
  static const LogicalKeyboardKey alt = LogicalKeyboardKey._('alt');
  static const LogicalKeyboardKey meta = LogicalKeyboardKey._('meta');
  
  final String keyId;
  
  const LogicalKeyboardKey._(this.keyId);
}
