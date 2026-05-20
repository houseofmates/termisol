import 'dart:io';

import 'package:pty/pty.dart';
import 'package:test/test.dart';

void main() {
  test('Can instantiate and kill PseudoTerminal', () async {
    final pty = PseudoTerminal.start(_getShell(), []);
    pty.kill();
    await pty.exitCode;
  }, timeout: Timeout.factor(0.3));

  // on windows pseudoterminal only works in flutter release mode..

  // test('can read exit code', () async {
  //   final pty = pseudoterminal.start(_getshell(), []);
  //   pty.write('exit 3\n');
  //   expect(await pty.exitcode, equals(3));
  // }, timeout: timeout.factor(0.3));

  // test('echo test', () async {
  //   final pty = pseudoterminal.start(_getshell(), []);
  //   pty.write('echo hello world\n');

  //   final output = await pty.out.single.timeout(duration(seconds: 10));
  //   expect(output, equals('hello world'));

  //   pty.kill();
  //   await pty.exitcode.timeout(duration(seconds: 10));
  // }, timeout: timeout.factor(0.3));
}

String _getShell() {
  if (Platform.isWindows) {
    return 'cmd';
  }

  return 'sh';
}
