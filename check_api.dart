import 'dart:ui' as ui;
import 'dart:typed_data';

void main() async {
  final program = await ui.FragmentProgram.fromAsset('test');
  final shader = program.fragmentShader(
    floatUniforms: Float32List(0),
  );
}
