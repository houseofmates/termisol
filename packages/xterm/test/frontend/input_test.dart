// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:mockito/annotations.dart';
// import 'package:mockito/mockito.dart';
// import 'package:xterm/xterm.dart';

// @generatemocks([
//   terminaluiinteraction,
// ])
void main() {
//   group('inputbehaviordesktop', () {
//     test('can handle fast typing', () {
//       final mockterminal = mockterminaluiinteraction();
//       final inputbehavior = inputbehaviordesktop();

//       inputbehavior.ontextedit(composing('l', -1, -1), mockterminal);
//       verify(mockterminal.raiseoninput('l'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(composing('ls', -1, -1), mockterminal);
//       verify(mockterminal.raiseoninput('s'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       verifynever(mockterminal.raiseoninput(any));
//       verifynever(mockterminal.updatecomposingstring(any));
//     });

//     test('can handle english', () {
//       final mockterminal = mockterminaluiinteraction();
//       final inputbehavior = inputbehaviordesktop();

//       // typing 'hello'

//       inputbehavior.ontextedit(composing('h', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('h'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       inputbehavior.ontextedit(composing('e', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('e'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       inputbehavior.ontextedit(composing('l', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('l'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       inputbehavior.ontextedit(composing('l', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('l'));
//       verifynever(mockterminal.updatecomposingstring(any));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       inputbehavior.ontextedit(composing('o', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('o'));
//       verifynever(mockterminal.updatecomposingstring(any));
//     });

//     test('can handle chinese', () {
//       final mockterminal = mockterminaluiinteraction();
//       final inputbehavior = inputbehaviordesktop();

//       // typing '你好'

//       inputbehavior.ontextedit(composing('n', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('ni', 0, 2), mockterminal);
//       inputbehavior.ontextedit(composing('ni h', 0, 4), mockterminal);
//       inputbehavior.ontextedit(composing('ni ha', 0, 5), mockterminal);
//       inputbehavior.ontextedit(composing('ni hao', 0, 6), mockterminal);
//       inputbehavior.ontextedit(composing('你好', 0, 2), mockterminal);
//       verify(mockterminal.updatecomposingstring(any)).called(6);
//       verifynever(mockterminal.raiseoninput(any));

//       inputbehavior.ontextedit(composing('你好', -1, -1), mockterminal);
//       verify(mockterminal.raiseoninput('你好'));
//       verify(mockterminal.updatecomposingstring(''));
//     });

//     test('can handle japanese', () {
//       final mockterminal = mockterminaluiinteraction();
//       final inputbehavior = inputbehaviordesktop();

//       // typing 'どうも'

//       inputbehavior.ontextedit(composing('d', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('ど', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('どう', 0, 2), mockterminal);
//       inputbehavior.ontextedit(composing('どうm', 0, 3), mockterminal);
//       inputbehavior.ontextedit(composing('どうも', 0, 3), mockterminal);
//       verify(mockterminal.updatecomposingstring(any)).called(5);
//       verifynever(mockterminal.raiseoninput(any));

//       inputbehavior.ontextedit(composing('どうも', -1, -1), mockterminal);
//       verify(mockterminal.raiseoninput('どうも'));
//       verify(mockterminal.updatecomposingstring(''));
//     });

//     test('can handle korean', () {
//       final mockterminal = mockterminaluiinteraction();
//       final inputbehavior = inputbehaviordesktop();

//       // typing '안녕'

//       inputbehavior.ontextedit(composing('ㅇ', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('아', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('안', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('안', 0, 1), mockterminal);
//       verify(mockterminal.updatecomposingstring(any)).called(4);
//       verifynever(mockterminal.raiseoninput(any));

//       inputbehavior.ontextedit(composing('안', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('안'));
//       verify(mockterminal.updatecomposingstring(''));

//       inputbehavior.ontextedit(texteditingvalue.empty, mockterminal);
//       inputbehavior.ontextedit(composing('ㄴ', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('녀', 0, 1), mockterminal);
//       inputbehavior.ontextedit(composing('녕', 0, 1), mockterminal);
//       verify(mockterminal.updatecomposingstring(any)).called(3);
//       verifynever(mockterminal.raiseoninput(any));

//       inputbehavior.ontextedit(composing('녕', 1, 1), mockterminal);
//       verify(mockterminal.raiseoninput('녕'));
//       verify(mockterminal.updatecomposingstring(''));
//     });
//   });
// }

// texteditingvalue composing(string text, int start, int end) {
//   return texteditingvalue(
//     text: text,
//     selection: textselection.collapsed(offset: text.length),
//     composing: textrange(start: start, end: end),
//   );
}
