import 'package:flutter/material.dart';
import 'terminal_view.dart';
import '../core/terminal_session.dart';

/// A split pane that can contain multiple terminal views
class SplitPane extends StatefulWidget {
  final List<TerminalSession> sessions;
  final bool isHorizontal;
  final VoidCallback? onNewTab;
  final VoidCallback? onCloseTab;

  const SplitPane({
    super.key,
    required this.sessions,
    this.isHorizontal = false,
    this.onNewTab,
    this.onCloseTab,
  });

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) {
      return const Center(child: Text('No terminals'));
    }

    if (widget.sessions.length == 1) {
      return TermisolTerminalView(
        session: widget.sessions.first,
        onNewTab: widget.onNewTab,
        onCloseTab: widget.onCloseTab,
      );
    }

    // For multiple sessions, create split layout
    final children = widget.sessions.map((session) {
      return Expanded(
        child: TermisolTerminalView(
          session: session,
          onNewTab: widget.onNewTab,
          onCloseTab: widget.onCloseTab,
        ),
      );
    }).toList();

    return widget.isHorizontal
        ? Row(children: children)
        : Column(children: children);
  }
}