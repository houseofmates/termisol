import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../backends/ssh_backend.dart';
import '../config/pkm_theme.dart';
import '../config/ssh_passcode_manager.dart';
import '../core/terminal_session.dart';

/// startup connection profile chooser.
class ConnectionProfiles extends StatefulWidget {
  final void Function(TerminalSession session) onConnect;

  const ConnectionProfiles({super.key, required this.onConnect});

  @override
  State<ConnectionProfiles> createState() => _ConnectionProfilesState();
}

class _ConnectionProfilesState extends State<ConnectionProfiles> {
  bool? _localShellAvailable;
  bool _probing = true;

  @override
  void initState() {
    super.initState();
    _probeLocalShell();
  }

  Future<void> _probeLocalShell() async {
    if (!Platform.isAndroid) {
      setState(() {
        _localShellAvailable = true;
        _probing = false;
      });
      return;
    }

    final shells = [
      '/data/data/com.termux/files/usr/bin/bash',
      '/system/xbin/bash',
      '/system/bin/sh',
      '/system/xbin/sh',
      '/vendor/bin/sh',
    ];
    bool found = false;
    for (final path in shells) {
      if (await File(path).exists()) {
        found = true;
        break;
      }
    }
    setState(() {
      _localShellAvailable = found;
      _probing = false;
    });
  }

  void _connectSsh(String host, String user) {
    final passcode = SshPasscodeManager().passcode;

    final id = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final session = TerminalSession(id: id, name: host);
    session.terminal.write('\r\n\x1b[33mconnecting to $host...\x1b[0m\r\n');
    widget.onConnect(session);
    unawaited(session.startWithBackend(SshBackend(
      host: host,
      port: 22,
      username: user,
      password: passcode,
    )));
  }

  void _connectLocal() {
    final id = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final session = TerminalSession(id: id, name: 'local');
    session.start();
    widget.onConnect(session);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PkmTheme.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'connect',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: PkmTheme.text,
                  fontFamily: PkmTheme.fontUi,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'select a target to begin',
                style: TextStyle(
                  fontSize: 14,
                  color: PkmTheme.primary,
                  fontFamily: PkmTheme.fontUi,
                ),
              ),
              const SizedBox(height: 32),
              _ProfileCard(
                label: 'ubuntu',
                subtitle: 'ssh: house@192.168.4.250',
                icon: Icons.computer,
                onTap: () => _connectSsh('192.168.4.250', 'house'),
              ),
              const SizedBox(height: 12),
              _ProfileCard(
                label: 'pop! os',
                subtitle: 'ssh: house@192.168.4.233',
                icon: Icons.desktop_windows,
                onTap: () => _connectSsh('192.168.4.233', 'house'),
              ),
              if (_probing)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: PkmTheme.primary,
                    ),
                  ),
                )
              else if (_localShellAvailable == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ProfileCard(
                    label: 'local device',
                    subtitle: 'android native shell',
                    icon: Icons.phone_android,
                    onTap: _connectLocal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: const BoxDecoration(
          color: PkmTheme.tabInactiveBg,
          border: Border(
            left: BorderSide(color: PkmTheme.primary, width: 3),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: PkmTheme.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PkmTheme.secondary,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward,
              color: PkmTheme.primary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
