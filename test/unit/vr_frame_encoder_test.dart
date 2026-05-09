import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/vr/vr_frame_encoder.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('VrFrameEncoder', () {
    test('encodes an empty terminal to zeros', () {
      final terminal = Terminal(maxLines: 10);
      // Write some content to populate the buffer.
      terminal.write('');

      final encoder = VrFrameEncoder();
      final bytes = encoder.encode(terminal);

      expect(bytes, isA<Uint8List>());
      expect(bytes.every((b) => b == 0), isTrue);
    });

    test('encodes visible cells with correct stride', () {
      final terminal = Terminal(maxLines: 10);
      terminal.write('A');

      final encoder = VrFrameEncoder();
      final bytes = encoder.encode(terminal);

      // First cell should contain 'A' (0x41)
      final view = ByteData.view(bytes.buffer);
      expect(view.getUint32(0, Endian.little), 0x41);
    });

    test('respects maxRows and maxCols clamps', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('Line1\nLine2\nLine3\n');

      final encoder = VrFrameEncoder(maxRows: 2, maxCols: 4);
      final bytes = encoder.encode(terminal);

      expect(bytes.length, 2 * 4 * 13);
    });
  });
}
