import 'dart:ui' as ui;

void main() async {
  final program = await ui.FragmentProgram.fromAsset('test');
  program.fragmentShader();
}
