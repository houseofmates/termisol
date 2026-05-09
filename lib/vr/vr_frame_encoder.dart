import 'dart:typed_data';

import 'package:xterm/xterm.dart' show CellContent, CellData, Terminal;

/// Encodes the visible terminal buffer into a compact binary format suitable
/// for transmission to the native VR renderer.
///
/// Each cell is encoded as 13 bytes:
///   - codepoint : Uint32 (4 bytes)
///   - foreground: Uint32 (4 bytes)
///   - background: Uint32 (4 bytes)
///   - flags     : Uint8  (1 byte)
class VrFrameEncoder {
  VrFrameEncoder({this.maxRows = 40, this.maxCols = 80});

  final int maxRows;
  final int maxCols;

  /// Encode the visible portion of [terminal] into a flat byte array.
  Uint8List encode(Terminal terminal) {
    final buffer = terminal.buffer;
    final rows = terminal.viewHeight.clamp(1, maxRows);
    final cols = terminal.viewWidth.clamp(1, maxCols);

    final cellCount = rows * cols;
    final out = Uint8List(cellCount * 13);
    final view = ByteData.view(out.buffer);

    var offset = 0;
    final cellData = CellData.empty();
    final visibleStart = buffer.height - rows;

    for (var r = 0; r < rows; r++) {
      final lineIndex = visibleStart + r;
      if (lineIndex < 0 || lineIndex >= buffer.lines.length) {
        offset += cols * 13;
        continue;
      }
      final line = buffer.lines[lineIndex];
      final lineLength = line.length < cols ? line.length : cols;

      for (var c = 0; c < lineLength; c++) {
        line.getCellData(c, cellData);
        view.setUint32(offset, cellData.content & CellContent.codepointMask, Endian.little);
        view.setUint32(offset + 4, cellData.foreground, Endian.little);
        view.setUint32(offset + 8, cellData.background, Endian.little);
        view.setUint8(offset + 12, cellData.flags);
        offset += 13;
      }
      // Pad remaining columns with zeros.
      offset += (cols - lineLength) * 13;
    }

    return out;
  }
}
