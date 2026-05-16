import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:termisol/backends/android_shell_backend.dart';

class MockProcess extends Mock implements Process {
  final _exitCodeCompleter = Completer<int>();

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return super.noSuchMethod(
      Invocation.method(#kill, [signal]),
      returnValue: true,
      returnValueForMissingStub: true,
    );
  }

  void completeExitCode(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }
}

class ExplodingMockProcess extends MockProcess {
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (signal == ProcessSignal.sigterm) {
      throw Exception('Simulated kill failure');
    } else if (signal == ProcessSignal.sigkill) {
      throw Exception('Simulated sigkill failure');
    }
    return false;
  }
}

void main() {
  group('AndroidShellBackend error handling', () {
    test('terminate handles exceptions during kill and fallback sigkill', () async {
      final backend = AndroidShellBackend();
      backend.setProcessForTesting(ExplodingMockProcess());

      // Should not throw
      await expectLater(backend.terminate(), completes);
    });

    test('stop handles exceptions during kill and fallback sigkill', () async {
      final backend = AndroidShellBackend();
      backend.setProcessForTesting(ExplodingMockProcess());

      // Should not throw
      await expectLater(backend.stop(), completes);
    });
  });
}
