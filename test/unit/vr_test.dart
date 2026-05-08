import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/service_registry.dart';
import 'package:termisol/core/vr_platform_channel.dart';
import 'package:termisol/vr/vr_terminal.dart';

void main() {
  late ServiceRegistry registry;

  setUp(() {
    registry = ServiceRegistry();  // Create new instance for each test
    // Enable VR support for tests
    registry.register(TermisolFeatures.vrSupport, () => true, enabled: true);
  });

  tearDown(() {
    // No need to reset since we create new instances
  });

  group('VrTerminal', () {
    testWidgets('should initialize with service registry', (tester) async {
      final terminalWidget = Container(key: const Key('terminal'), child: const Text('Terminal'));
      final vrTerminal = VrTerminal(
        registry: registry,
        terminalWidget: terminalWidget,
      );

      await tester.pumpWidget(MaterialApp(home: vrTerminal));
      await tester.pumpAndSettle();

      // Should show 2D fallback initially since VR platform channel isn't mocked
      expect(find.byKey(const Key('terminal')), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
    });

    testWidgets('should display status message when VR disabled', (tester) async {
      // Disable VR support
      registry.register(TermisolFeatures.vrSupport, () => false, enabled: false);

      final terminalWidget = const SizedBox();
      final vrTerminal = VrTerminal(
        registry: registry,
        terminalWidget: terminalWidget,
      );

      await tester.pumpWidget(MaterialApp(home: vrTerminal));
      await tester.pumpAndSettle();

      expect(find.text('VR support disabled'), findsOneWidget);
    });

    testWidgets('should build valid widget tree', (tester) async {
      final terminalWidget = Container(
        key: const Key('terminal_content'),
        child: const Text('Test Terminal'),
      );

      final vrTerminal = VrTerminal(
        registry: registry,
        terminalWidget: terminalWidget,
      );

      await tester.pumpWidget(MaterialApp(home: vrTerminal));
      await tester.pumpAndSettle();

      // Verify the terminal widget is embedded
      expect(find.byKey(const Key('terminal_content')), findsOneWidget);
      expect(find.text('Test Terminal'), findsOneWidget);

      // Verify widget tree structure
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(Column), findsOneWidget);
    });

    testWidgets('should handle VR platform channel errors gracefully', (tester) async {
      final terminalWidget = const SizedBox();
      final vrTerminal = VrTerminal(
        registry: registry,
        terminalWidget: terminalWidget,
      );

      await tester.pumpWidget(MaterialApp(home: vrTerminal));
      await tester.pumpAndSettle();

      // Should still show fallback UI even if VR initialization fails
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('VrPlatformChannel', () {
    test('VrInitResult should parse from json correctly', () {
      final json = {
        'success': true,
        'deviceInfo': {
          'deviceType': 'quest2',
          'supportsHandTracking': true,
          'supportsEyeTracking': true,
          'supportsSpatialAudio': false,
          'displayRefreshRate': 90.0,
        }
      };

      final result = VrInitResult.fromJson(json);

      expect(result.success, true);
      expect(result.deviceInfo?.deviceType, 'quest2');
      expect(result.deviceInfo?.supportsHandTracking, true);
      expect(result.deviceInfo?.supportsEyeTracking, true);
      expect(result.deviceInfo?.supportsSpatialAudio, false);
      expect(result.deviceInfo?.displayRefreshRate, 90.0);
    });

    test('HandTrackingData should parse from json correctly', () {
      final json = {
        'leftHand': {
          'position': {'x': 100.0, 'y': 200.0},
          'confidence': 0.95,
          'gesture': 1,
          'fingers': [
            {'type': 0, 'tipPosition': {'x': 100.0, 'y': 200.0}, 'confidence': 0.9},
            {'type': 1, 'tipPosition': {'x': 120.0, 'y': 200.0}, 'confidence': 0.9},
          ],
          'isTracked': true,
        },
        'rightHand': {
          'position': {'x': 300.0, 'y': 200.0},
          'confidence': 0.92,
          'gesture': 1,
          'fingers': [],
          'isTracked': true,
        },
        'confidence': 0.95,
      };

      final data = HandTrackingData.fromJson(json);

      expect(data.confidence, 0.95);
      expect(data.leftHand.position, const Offset(100.0, 200.0));
      expect(data.leftHand.confidence, 0.95);
      expect(data.leftHand.gesture, HandGesture.open);
      expect(data.leftHand.isTracked, true);
      expect(data.leftHand.fingers.length, 2);
      expect(data.rightHand.position, const Offset(300.0, 200.0));
    });

    test('EyeTrackingData should parse from json correctly', () {
      final json = {
        'gazePosition': {'x': 400.0, 'y': 300.0},
        'pupilDilation': 0.6,
        'leftEyeBlink': false,
        'rightEyeBlink': true,
        'confidence': 0.9,
      };

      final data = EyeTrackingData.fromJson(json);

      expect(data.gazePosition, const Offset(400.0, 300.0));
      expect(data.pupilDilation, 0.6);
      expect(data.leftEyeBlink, false);
      expect(data.rightEyeBlink, true);
      expect(data.confidence, 0.9);
    });

    test('HapticPattern should convert to json correctly', () {
      final pattern = HapticPattern(
        name: 'test',
        pattern: [0, 100, 50, 100],
        amplitude: 0.8,
      );

      final json = pattern.toJson();

      expect(json['name'], 'test');
      expect(json['pattern'], [0, 100, 50, 100]);
      expect(json['amplitude'], 0.8);
    });
  });
}