// import 'dart:async';

// import 'package:flutter_test/flutter_test.dart';
// import 'package:xterm/terminal/terminal_backend.dart';
// import 'package:xterm/terminal/terminal_isolate.dart';

void main() {
  // group('start behavior tests', () {
  //   test('using terminalisolate when not started throws exception', () {
  //     final fixture = _testfixture();
  //     expect(() => fixture.uut.terminalwidth, throwsa(isa<exception>()));
  //   });
  //   test('using terminalisolate after started doesn\'t throw exceptions',
  //       () async {
  //     final fixture = _testfixture();

  //     await fixture.uut.start(testingdontwaitforbootup: true);

  //     //no throw
  //     fixture.uut.showcursor;
  //   });
  // });
}

// class _testfixture {
//   _testfixture() {
//     fakebackend = fakebackend();
//     uut = terminalisolate(maxlines: 10000, backend: fakebackend);
//   }

//   late final terminalisolate uut;
//   late final fakebackend fakebackend;
// }

// class fakebackend implements terminalbackend {
//   @override
//   void ackprocessed() {}

//   @override
//   // todo: implement exitcode
//   future<int> get exitcode => _exitcodecompleter.future;

//   @override
//   void init() {
//     _exitcodecompleter = completer<int>();
//     _outstream = streamcontroller<string>();
//     _hasinitbeencalled = true;
//   }

//   @override
//   stream<string> get out => _outstream.stream;

//   @override
//   void resize(int width, int height, int pixelwidth, int pixelheight) {
//     _width = width;
//     _height = height;
//     _pixelwidth = pixelwidth;
//     _pixelheight = pixelheight;
//   }

//   @override
//   void terminate() {
//     _isterminated = true;
//   }

//   @override
//   void write(string _) {}

//   bool get hasinitbeencalled => _hasinitbeencalled;
//   bool get isterminated => _isterminated;

//   int? get width => _width;
//   int? get height => _height;
//   int? get pixelwidth => _pixelwidth;
//   int? get pixelheight => _pixelheight;

//   bool _hasinitbeencalled = false;
//   bool _isterminated = false;
//   int? _width;
//   int? _height;
//   int? _pixelwidth;
//   int? _pixelheight;

//   late final _exitcodecompleter;
//   late final _outstream;
// }
