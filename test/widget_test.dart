import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';
import 'package:termisol/core/plugin_ecosystem.dart';
import 'package:termisol/core/audio_alert_service.dart';
import 'package:termisol/core/keyboard_macro_reader.dart';
import 'package:termisol/core/sync_services.dart';
import 'package:termisol/core/docker_operations.dart';
import 'package:termisol/core/integrated_debugger_nim.dart';
import 'package:termisol/core/task_runner.dart';
import 'package:termisol/core/configurable_hotkeys.dart';
import 'package:termisol/core/smooth_animations.dart';
import 'package:termisol/core/auto_backup_system.dart';
import 'package:termisol/core/auto_ssh_key_management.dart';
import 'package:termisol/core/multihop_ssh.dart';
import 'package:termisol/core/tunnel_management.dart';
import 'package:termisol/core/ssh_connection_persistence.dart';
import 'package:termisol/core/code_intelligence.dart';
import 'package:termisol/core/database_client.dart';
import 'package:termisol/core/session_recovery.dart';
import 'package:termisol/core/command_guard.dart';
import 'package:termisol/core/asciicast_recorder.dart';
import 'package:termisol/core/terminal_pane_manager.dart';

void main() {
  testWidgets('App widget can be instantiated', (WidgetTester tester) async {
    // Create a basic service registry for testing
    final registry = ServiceRegistry.instance;

    final app = TermisolApp(registry: registry);

    // Test that the app can be built
    await tester.pumpWidget(app);

    expect(app, isNotNull);
    expect(find.text('termisol'), findsOneWidget);
  });
}
