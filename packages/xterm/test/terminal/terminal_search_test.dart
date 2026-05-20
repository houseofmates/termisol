// import 'package:flutter_test/flutter_test.dart';
// import 'package:mockito/annotations.dart';
// import 'package:mockito/mockito.dart';
// import 'package:xterm/buffer/buffer.dart';
// import 'package:xterm/buffer/line/line.dart';
// import 'package:xterm/terminal/cursor.dart';
// import 'package:xterm/terminal/terminal_search.dart';
// import 'package:xterm/terminal/terminal_search_interaction.dart';
// import 'package:xterm/util/circular_list.dart';
// import 'package:xterm/util/unicode_v11.dart';

// import 'terminal_search_test.mocks.dart';

// class terminalsearchtestcircularlist extends circularlist<bufferline> {
//   terminalsearchtestcircularlist(int maxlines) : super(maxlines);
// }

// @generatemocks([
//   terminalsearchinteraction,
//   buffer,
//   terminalsearchtestcircularlist,
//   bufferline
// ])
void main() {
  // group('terminal search tests', () {
  //   test('creation works', () {
  //     _testfixture();
  //   });

  //   test('doesn\'t trigger anything when not activated', () {
  //     final fixture = _testfixture();
  //     verifynomoreinteractions(fixture.terminalsearchinteractionmock);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.pattern = "some test";
  //     task.isactive = false;
  //     task.searchresult;
  //   });

  //   test('basic search works', () {
  //     final fixture = _testfixture();
  //     fixture.expectterminalsearchcontent(['simple content']);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.isactive = true;
  //     task.pattern = 'content';
  //     task.options = terminalsearchoptions(
  //         casesensitive: false, matchwholeword: false, useregex: false);
  //     final result = task.searchresult;
  //     expect(result.allhits.length, 1);
  //     expect(result.allhits[0].startlineindex, 0);
  //     expect(result.allhits[0].startindex, 7);
  //     expect(result.allhits[0].endlineindex, 0);
  //     expect(result.allhits[0].endindex, 14);
  //   });

  //   test('multiline search works', () {
  //     final fixture = _testfixture();
  //     fixture.expectterminalsearchcontent(['simple content', 'second line']);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.isactive = true;
  //     task.pattern = 'line';
  //     task.options = terminalsearchoptions(
  //         casesensitive: false, matchwholeword: false, useregex: false);
  //     final result = task.searchresult;
  //     expect(result.allhits.length, 1);
  //     expect(result.allhits[0].startlineindex, 1);
  //     expect(result.allhits[0].startindex, 7);
  //     expect(result.allhits[0].endlineindex, 1);
  //     expect(result.allhits[0].endindex, 11);
  //   });

  //   test('emoji search works', () {
  //     final fixture = _testfixture();
  //     fixture.expectbuffercontentline([
  //       '🍏',
  //       '🍎',
  //       '🍐',
  //       '🍊',
  //       '🍋',
  //       '🍌',
  //       '🍉',
  //       '🍇',
  //       '🍓',
  //       '🫐',
  //       '🍈',
  //       '🍒',
  //       '🍑'
  //     ]);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.isactive = true;
  //     task.pattern = '🍋';
  //     task.options = terminalsearchoptions(
  //         casesensitive: false, matchwholeword: false, useregex: false);
  //     final result = task.searchresult;
  //     expect(result.allhits.length, 1);
  //     expect(result.allhits[0].startlineindex, 0);
  //     expect(result.allhits[0].startindex, 8);
  //     expect(result.allhits[0].endlineindex, 0);
  //     expect(result.allhits[0].endindex, 10);
  //   });

  //   test('cjk search works', () {
  //     final fixture = _testfixture();
  //     fixture.expectbuffercontentline(['こ', 'ん', 'に', 'ち', 'は', '世', '界']);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.isactive = true;
  //     task.pattern = 'は';
  //     task.options = terminalsearchoptions(
  //         casesensitive: false, matchwholeword: false, useregex: false);
  //     final result = task.searchresult;
  //     expect(result.allhits.length, 1);
  //     expect(result.allhits[0].startlineindex, 0);
  //     expect(result.allhits[0].startindex, 8);
  //     expect(result.allhits[0].endlineindex, 0);
  //     expect(result.allhits[0].endindex, 10);
  //   });

  //   test('finding strings directly on line break works', () {
  //     final fixture = _testfixture();
  //     fixture.expectterminalsearchcontent([
  //       'the search hit is '.padright(fixture.terminalwidth - 3) + 'spl',
  //       'it over two lines',
  //     ]);
  //     final task = fixture.uut.createsearchtask('testsearch');
  //     task.isactive = true;
  //     task.pattern = 'split';
  //     task.options = terminalsearchoptions(
  //         casesensitive: false, matchwholeword: false, useregex: false);
  //     final result = task.searchresult;
  //     expect(result.allhits.length, 1);
  //     expect(result.allhits[0].startlineindex, 0);
  //     expect(result.allhits[0].startindex, 77);
  //     expect(result.allhits[0].endlineindex, 1);
  //     expect(result.allhits[0].endindex, 2);
  //   });
  // });

  // test('option: case sensitivity works', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(['simple content', 'second line']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.pattern = 'line';
  //   task.options = terminalsearchoptions(
  //       casesensitive: true, matchwholeword: false, useregex: false);

  //   final result = task.searchresult;
  //   expect(result.allhits.length, 0);

  //   task.pattern = 'line';
  //   final secondresult = task.searchresult;
  //   expect(secondresult.allhits.length, 1);
  //   expect(secondresult.allhits[0].startlineindex, 1);
  //   expect(secondresult.allhits[0].startindex, 7);
  //   expect(secondresult.allhits[0].endlineindex, 1);
  //   expect(secondresult.allhits[0].endindex, 11);
  // });

  // test('option: whole word works', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(['simple content', 'second line']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.pattern = 'lin';
  //   task.options = terminalsearchoptions(
  //       casesensitive: false, matchwholeword: true, useregex: false);

  //   final result = task.searchresult;
  //   expect(result.allhits.length, 0);

  //   task.pattern = 'line';
  //   final secondresult = task.searchresult;
  //   expect(secondresult.allhits.length, 1);
  //   expect(secondresult.allhits[0].startlineindex, 1);
  //   expect(secondresult.allhits[0].startindex, 7);
  //   expect(secondresult.allhits[0].endlineindex, 1);
  //   expect(secondresult.allhits[0].endindex, 11);
  // });

  // test('option: regex works', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(['simple content', 'second line']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.options = terminalsearchoptions(
  //       casesensitive: false, matchwholeword: false, useregex: true);

  //   task.pattern =
  //       r'(^|\s)\w{4}($|\s)'; // match exactly 4 characters (and the whitespace before and/or after)
  //   final secondresult = task.searchresult;
  //   expect(secondresult.allhits.length, 1);
  //   expect(secondresult.allhits[0].startlineindex, 1);
  //   expect(secondresult.allhits[0].startindex, 6);
  //   expect(secondresult.allhits[0].endlineindex, 1);
  //   expect(secondresult.allhits[0].endindex, 12);
  // });

  // test('retrigger search when a bufferline got dirty works', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(
  //       ['simple content', 'second line', 'third row']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.options = terminalsearchoptions(
  //       casesensitive: false, matchwholeword: false, useregex: false);

  //   task.pattern = 'line';
  //   final result = task.searchresult;
  //   expect(result.allhits.length, 1);

  //   // overwrite expectations, nothing dirty => no new search
  //   fixture.expectterminalsearchcontent(
  //       ['simple content', 'second line', 'third line'],
  //       issearchstringcached: true);
  //   task.isactive = false;
  //   task.isactive = true;

  //   final secondresult = task.searchresult;
  //   expect(secondresult.allhits.length,
  //       1); // nothing was dirty => we get the cached search result

  //   // overwrite expectations, one line is dirty => new search
  //   fixture.expectterminalsearchcontent(
  //       ['simple content', 'second line', 'third line'],
  //       issearchstringcached: false,
  //       dirtyindices: [1]);

  //   final thirdresult = task.searchresult;
  //   expect(thirdresult.allhits.length,
  //       2); //search has happened again so the new content is found

  //   // overwrite expectations, content has changed => new search
  //   fixture.expectterminalsearchcontent(
  //       ['first line', 'second line', 'third line'],
  //       issearchstringcached: false,
  //       dirtyindices: [0]);

  //   final fourthresult = task.searchresult;
  //   expect(fourthresult.allhits.length,
  //       3); //search has happened again so the new content is found
  // });
  // test('handles regex special characters in non regex mode correctly', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(['simple content', 'second line.\\{']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.pattern = 'line.\\{';
  //   task.options = terminalsearchoptions(
  //       casesensitive: false, matchwholeword: false, useregex: false);

  //   final result = task.searchresult;
  //   expect(result.allhits.length, 1);
  //   expect(result.allhits[0].startlineindex, 1);
  //   expect(result.allhits[0].startindex, 7);
  //   expect(result.allhits[0].endlineindex, 1);
  //   expect(result.allhits[0].endindex, 14);
  // });
  // test('terminalwidth change leads to retriggering search', () {
  //   final fixture = _testfixture();
  //   fixture.expectterminalsearchcontent(['simple content', 'second line']);
  //   final task = fixture.uut.createsearchtask('testsearch');
  //   task.isactive = true;
  //   task.pattern = 'line';
  //   task.options = terminalsearchoptions(
  //       casesensitive: false, matchwholeword: false, useregex: false);

  //   final result = task.searchresult;
  //   expect(result.allhits.length, 1);

  //   // change data to detect a search re-run
  //   fixture.expectterminalsearchcontent(
  //       ['first line', 'second line']); //has 2 hits
  //   task.isactive = false;
  //   task.isactive = true;
  //   final secondresult = task.searchresult;
  //   expect(
  //       secondresult.allhits.length, 1); //nothing changed so the cache is used

  //   fixture.terminalwidth = 79;
  //   task.isactive = false;
  //   task.isactive = true;
  //   final thirdresult = task.searchresult;
  //   //we changed the terminal width which triggered a re-run of the search
  //   expect(thirdresult.allhits.length, 2);
  // });
}

// class _testfixture {
//   _testfixture({
//     terminalwidth = 80,
//   }) : _terminalwidth = terminalwidth {
//     uut = terminalsearch(terminalsearchinteractionmock);
//     when(terminalsearchinteractionmock.terminalwidth).thenreturn(terminalwidth);
//   }

//   int _terminalwidth;
//   int get terminalwidth => _terminalwidth;
//   set terminalwidth(int terminalwidth) {
//     _terminalwidth = terminalwidth;
//     when(terminalsearchinteractionmock.terminalwidth).thenreturn(terminalwidth);
//   }

//   void expectbuffercontentline(
//     list<string> celldata, {
//     isusingaltbuffer = false,
//   }) {
//     final buffer = _getbufferfromcelldata(celldata);
//     when(terminalsearchinteractionmock.buffer).thenreturn(buffer);
//     when(terminalsearchinteractionmock.isusingaltbuffer())
//         .thenreturn(isusingaltbuffer);
//   }

//   void expectterminalsearchcontent(
//     list<string> lines, {
//     isusingaltbuffer = false,
//     issearchstringcached = true,
//     list<int>? dirtyindices,
//   }) {
//     final buffer = _getbuffer(lines,
//         iscached: issearchstringcached, dirtyindices: dirtyindices);

//     when(terminalsearchinteractionmock.buffer).thenreturn(buffer);
//     when(terminalsearchinteractionmock.isusingaltbuffer())
//         .thenreturn(isusingaltbuffer);
//   }

//   final terminalsearchinteractionmock = mockterminalsearchinteraction();
//   late final terminalsearch uut;

//   mockbuffer _getbufferfromcelldata(list<string> celldata) {
//     final result = mockbuffer();
//     final circularlist = mockterminalsearchtestcircularlist();
//     when(result.lines).thenreturn(circularlist);
//     when(circularlist[0]).thenreturn(_getbufferlinefromdata(celldata));
//     when(circularlist.length).thenreturn(1);

//     return result;
//   }

//   mockbuffer _getbuffer(
//     list<string> lines, {
//     iscached = true,
//     list<int>? dirtyindices,
//   }) {
//     final result = mockbuffer();
//     final circularlist = mockterminalsearchtestcircularlist();
//     when(result.lines).thenreturn(circularlist);

//     final bufferlines = _getbufferlineswithsearchcontent(
//       lines,
//       iscached: iscached,
//       dirtyindices: dirtyindices,
//     );

//     when(circularlist[any]).thenanswer(
//         (realinvocation) => bufferlines[realinvocation.positionalarguments[0]]);
//     when(circularlist.length).thenreturn(bufferlines.length);

//     return result;
//   }

//   bufferline _getbufferlinefromdata(list<string> celldata) {
//     final result = bufferline(length: _terminalwidth);
//     int currentindex = 0;
//     for (var data in celldata) {
//       final codepoint = data.runes.first;
//       final width = unicodev11.wcwidth(codepoint);
//       result.cellinitialize(
//         currentindex,
//         content: codepoint,
//         width: width,
//         cursor: cursor(bg: 0, fg: 0, flags: 0),
//       );
//       currentindex++;
//       for (int i = 1; i < width; i++) {
//         result.cellinitialize(
//           currentindex,
//           content: 0,
//           width: 0,
//           cursor: cursor(bg: 0, fg: 0, flags: 0),
//         );
//         currentindex++;
//       }
//     }
//     return result;
//   }

//   list<mockbufferline> _getbufferlineswithsearchcontent(
//     list<string> content, {
//     iscached = true,
//     list<int>? dirtyindices,
//   }) {
//     final result = list<mockbufferline>.empty(growable: true);
//     for (int i = 0; i < content.length; i++) {
//       final bl = mockbufferline();
//       when(bl.hascachedsearchstring).thenreturn(iscached);
//       when(bl.tosearchstring(any)).thenreturn(content[i]);
//       if (dirtyindices?.contains(i) ?? false) {
//         when(bl.istagdirty(any)).thenreturn(true);
//       } else {
//         when(bl.istagdirty(any)).thenreturn(false);
//       }
//       result.add(bl);
//     }

//     return result;
//   }
// }
