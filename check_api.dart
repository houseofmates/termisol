import 'dart:ui' as ui;

void main() async {
  final program = await ui.FragmentProgram.fromAsset('test');
  final shader = program.fragmentShader();
  shader.setFloat(0, 1.0);
}
