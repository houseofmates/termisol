import 'package:flutter/material.dart';
import '../core/terminal_session.dart';
import '../ui/terminal_view.dart';
import '../config/pkm_theme.dart';

/// VR terminal view for Oculus Quest 2
class VrTerminalView extends StatelessWidget {
  final TerminalSession session;

  const VrTerminalView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'VR Terminal Mode',
              style: TextStyle(
                color: PkmTheme.primary,
                fontSize: 24,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: TermisolTerminalView(session: session),
            ),
            const Text(
              'Use Quest controllers to interact',
              style: TextStyle(
                color: PkmTheme.text,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}