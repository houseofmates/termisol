import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/whisper_service.dart';

void main() {
  group('WhisperService Security Tests', () {
    test('WhisperService accepts https non-local URL', () {
      expect(
        () => WhisperService(serverUrl: 'https://api.example.com'),
        returnsNormally,
      );
    });

    test('WhisperService accepts http localhost', () {
      expect(
        () => WhisperService(serverUrl: 'http://localhost:9000'),
        returnsNormally,
      );
    });

    test('WhisperService accepts http 127.0.0.1', () {
      expect(
        () => WhisperService(serverUrl: 'http://127.0.0.1:9000'),
        returnsNormally,
      );
    });

    test('WhisperService rejects http non-local URL', () {
      expect(
        () => WhisperService(serverUrl: 'http://192.168.1.100:9000'),
        throwsArgumentError,
      );
    });

    test('WhisperService default URL is secure', () {
      final service = WhisperService();
      expect(service.serverUrl, startsWith('https://'));
    });
  });
}
