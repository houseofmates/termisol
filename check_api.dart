import 'dart:ui' as ui;

void main() {
  final shader = ui.Gradient.linear(
    ui.Offset(0, 0),
    ui.Offset(1, 1),
    [const ui.Color(0xFF000000), const ui.Color(0xFFFFFFFF)],
  );
}
