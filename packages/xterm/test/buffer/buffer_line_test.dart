// import 'package:flutter_test/flutter_test.dart';
// import 'package:xterm/buffer/line/line.dart';
// import 'package:xterm/terminal/cursor.dart';

void main() {
  // group("bufferline tests", () {
  //   test("creation test", () {
  //     final line = bufferline();
  //     expect(line, isnotnull);
  //   });

  //   test("set iswrapped", () {
  //     final line = bufferline(iswrapped: false);
  //     expect(line.iswrapped, isfalse);

  //     line.iswrapped = true;
  //     expect(line.iswrapped, istrue);

  //     line.iswrapped = false;
  //     expect(line.iswrapped, isfalse);
  //   });

  //   test("ensure() works", () {
  //     final line = bufferline(length: 10);
  //     expect(() => line.cellsetcontent(1000, 65), throwsrangeerror);

  //     line.ensure(1000);
  //     line.cellsetcontent(1000, 65);
  //   });

  //   test("insert() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(0, 65);
  //     line.cellsetcontent(1, 66);
  //     line.cellsetcontent(2, 67);

  //     line.insert(1);

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //     ];

  //     expect(result, equals([65, 0, 66, 67]));
  //   });

  //   test("insertn() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(0, 65);
  //     line.cellsetcontent(1, 66);
  //     line.cellsetcontent(2, 67);

  //     line.insertn(1, 2);

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //       line.cellgetcontent(4),
  //     ];

  //     expect(result, equals([65, 0, 0, 66, 67]));
  //   });

  //   test("removen() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(0, 65);
  //     line.cellsetcontent(1, 66);
  //     line.cellsetcontent(2, 67);
  //     line.cellsetcontent(3, 68);
  //     line.cellsetcontent(4, 69);

  //     line.removen(1, 2);

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //       line.cellgetcontent(4),
  //     ];

  //     expect(result, equals([65, 68, 69, 0, 0]));
  //   });

  //   test("clear() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(1, 65);
  //     line.cellsetcontent(2, 66);
  //     line.cellsetcontent(3, 67);
  //     line.cellsetcontent(4, 68);
  //     line.cellsetcontent(5, 69);

  //     line.clear();

  //     final result = [
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //       line.cellgetcontent(4),
  //       line.cellgetcontent(5),
  //     ];

  //     expect(result, equals([0, 0, 0, 0, 0]));
  //   });

  //   test("cellinitialize() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellinitialize(
  //       0,
  //       content: 0x01,
  //       width: 0x02,
  //       cursor: cursor(fg: 0x03, bg: 0x04, flags: 0x05),
  //     );

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetwidth(0),
  //       line.cellgetfgcolor(0),
  //       line.cellgetbgcolor(0),
  //       line.cellgetflags(0),
  //     ];

  //     expect(result, equals([0x01, 0x02, 0x03, 0x04, 0x05]));
  //   });

  //   test("cellhascontent() works", () {
  //     final line = bufferline(length: 10);

  //     line.cellsetcontent(0, 0x01);
  //     expect(line.cellhascontent(0), istrue);

  //     line.cellsetcontent(0, 0x00);
  //     expect(line.cellhascontent(0), isfalse);
  //   });

  //   test("cellgetcontent() and cellsetcontent() works", () {
  //     final line = bufferline(length: 10);
  //     final content = 0x01;
  //     line.cellsetcontent(0, content);
  //     expect(line.cellgetcontent(0), equals(content));
  //   });

  //   test("cellgetfgcolor() and cellsetfgcolor() works", () {
  //     final line = bufferline(length: 10);
  //     final content = 0x01;
  //     line.cellsetfgcolor(0, content);
  //     expect(line.cellgetfgcolor(0), equals(content));
  //   });

  //   test("cellgetbgcolor() and cellsetbgcolor() works", () {
  //     final line = bufferline(length: 10);
  //     final content = 0x01;
  //     line.cellsetbgcolor(0, content);
  //     expect(line.cellgetbgcolor(0), equals(content));
  //   });

  //   test("cellhasflag() and cellsetflag() works", () {
  //     final line = bufferline(length: 10);
  //     final flag = 0x03;
  //     line.cellsetflag(0, flag);
  //     expect(line.cellhasflag(0, flag), istrue);
  //   });

  //   test("cellgetflags() and cellsetflags() works", () {
  //     final line = bufferline(length: 10);
  //     final content = 0x01;
  //     line.cellsetflags(0, content);
  //     expect(line.cellgetflags(0), equals(content));
  //   });

  //   test("cellgetwidth() and cellsetwidth() works", () {
  //     final line = bufferline(length: 10);
  //     final content = 0x01;
  //     line.cellsetwidth(0, content);
  //     expect(line.cellgetwidth(0), equals(content));
  //   });

  //   test("gettrimmedlength() works", () {
  //     final line = bufferline(length: 10);
  //     expect(line.gettrimmedlength(), equals(0));

  //     line.cellsetcontent(5, 0x01);
  //     expect(line.gettrimmedlength(), equals(5));

  //     line.clear();
  //     expect(line.gettrimmedlength(), equals(0));
  //   });

  //   test("copycellsfrom() works", () {
  //     final line1 = bufferline(length: 10);
  //     final line2 = bufferline(length: 10);

  //     line1.cellsetcontent(0, 123);
  //     line1.cellsetcontent(1, 124);
  //     line1.cellsetcontent(2, 125);

  //     line2.copycellsfrom(line1, 1, 3, 2);

  //     expect(line2.cellgetcontent(2), equals(0));
  //     expect(line2.cellgetcontent(3), equals(124));
  //     expect(line2.cellgetcontent(4), equals(125));
  //     expect(line2.cellgetcontent(5), equals(0));
  //   });

  //   test("removerange() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(0, 65);
  //     line.cellsetcontent(1, 66);
  //     line.cellsetcontent(2, 67);
  //     line.cellsetcontent(3, 68);
  //     line.cellsetcontent(4, 69);

  //     line.removerange(1, 3);

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //       line.cellgetcontent(4),
  //     ];

  //     expect(result, equals([65, 68, 69, 0, 0]));
  //   });

  //   test("clearrange() works", () {
  //     final line = bufferline(length: 10);
  //     line.cellsetcontent(0, 65);
  //     line.cellsetcontent(1, 66);
  //     line.cellsetcontent(2, 67);
  //     line.cellsetcontent(3, 68);
  //     line.cellsetcontent(4, 69);

  //     line.clearrange(1, 3);

  //     final result = [
  //       line.cellgetcontent(0),
  //       line.cellgetcontent(1),
  //       line.cellgetcontent(2),
  //       line.cellgetcontent(3),
  //       line.cellgetcontent(4),
  //     ];

  //     expect(result, equals([65, 0, 0, 68, 69]));
  //   });
  // });
}
