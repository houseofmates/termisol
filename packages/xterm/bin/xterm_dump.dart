// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';

// import 'package:xterm/core/escape/handler.dart';
// import 'package:xterm/core/escape/parser.dart';

// final handler = debugterminalhandler();
// final protocol = escapeparser(handler);
// final input = bytesbuilder(copy: true);

// void main(list<string> args) async {
//   final inputstream = args.isnotempty ? file(args.first).openread() : stdin;

//   await for (var chunk in inputstream.transform(utf8decoder())) {
//     input.add(chunk);
//     protocol.write(chunk);
//   }

//   handler.flush();
// }

// extension stringescape on string {
//   string escapeinvisible() {
//     return this.replaceallmapped(regexp('[\x00-\x1f]'), (match) {
//       return '\\x${match.group(0)!.codeunitat(0).toradixstring(16).padleft(2, '0')}';
//     });
//   }
// }

// class debugterminalhandler implements escapehandler {
//   final stringbuffer = stringbuffer();

//   void flush() {
//     if (stringbuffer.isempty) return;
//     print(color.green('txt') + "'$stringbuffer'");
//     stringbuffer.clear();
//   }

//   void recordcommand(string description) {
//     flush();
//     final raw = input.tobytes().sublist(protocol.tokenbegin, protocol.tokenend);
//     final token = utf8.decode(raw).replaceall('\x1b', 'esc').escapeinvisible();
//     print(color.magenta('cmd ') + token.padright(40) + '$description');
//   }

//   @override
//   void writechar(int char) {
//     stringbuffer.writecharcode(char);
//   }

//   @override
//   void setcursor(int x, int y) {
//     recordcommand('setcursor $x, $y');
//   }

//   @override
//   void designatecharset(int charset) {
//     recordcommand('designatecharset $charset');
//   }

//   @override
//   void unkownescape(int char) {
//     recordcommand('unkownescape ${string.fromcharcode(char)}');
//   }

//   @override
//   void backspacereturn() {
//     recordcommand('backspacereturn');
//   }

//   @override
//   void carriagereturn() {
//     recordcommand('carriagereturn');
//   }

//   @override
//   void setcursorx(int x) {
//     recordcommand('setcursorx $x');
//   }

//   @override
//   void setcursory(int y) {
//     recordcommand('setcursory $y');
//   }

//   @override
//   void unkowncsi(int finalbyte) {
//     recordcommand('unkowncsi ${string.fromcharcode(finalbyte)}');
//   }

//   @override
//   void unkownsbc(int char) {
//     recordcommand('unkownsbc ${string.fromcharcode(char)}');
//   }

//   @override
//   nosuchmethod(invocation invocation) {
//     final name = invocation.membername;
//     final args = invocation.positionalarguments;
//     recordcommand('nosuchmethod: $name $args');
//   }
// }

// abstract class color {
//   static string red(string s) => '\u001b[31m$s\u001b[0m';
//   static string green(string s) => '\u001b[32m$s\u001b[0m';
//   static string yellow(string s) => '\u001b[33m$s\u001b[0m';
//   static string blue(string s) => '\u001b[34m$s\u001b[0m';
//   static string magenta(string s) => '\u001b[35m$s\u001b[0m';
//   static string cyan(string s) => '\u001b[36m$s\u001b[0m';
// }

// abstract class labels {
//   static final txt = color.green('txt');
// }
