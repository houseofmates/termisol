import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';
import '../core/terminal_session.dart';
import 'terminal_view.dart';

/// A split pane that can contain multiple terminal views with draggable
/// resizable dividers. Supports horizontal (Row) and vertical (Column) splits.
class SplitPane extends StatefulWidget {
  final List<TerminalSession> sessions;
  final bool isHorizontal;
  final VoidCallback? onNewTab;
  final VoidCallback? onCloseTab;
  final ValueChanged<List<double>>? onResized;

  const SplitPane({
    super.key,
    required this.sessions,
    this.isHorizontal = false,
    this.onNewTab,
    this.onCloseTab,
    this.onResized,
  });

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  static const double _dividerThickness = 4.0;
  static const double _minPaneSize = 100.0;
  static const double _baseFlex = 1000.0;

  late List<double> _flexes;

  @override
  void initState() {
    super.initState();
    _equalizeFlexes();
  }

  @override
  void didUpdateWidget(SplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessions.length != oldWidget.sessions.length) {
      _equalizeFlexes();
    }
  }

  void _equalizeFlexes() {
    final count = widget.sessions.length;
    if (count <= 0) {
      _flexes = [];
      return;
    }
    _flexes = List<double>.filled(count, _baseFlex);
  }

  double get _totalFlex => _flexes.fold(0.0, (sum, f) => sum + f);

  void _onDrag(int dividerIndex, double delta, double availableSpace) {
    if (availableSpace <= 0) return;
    if (dividerIndex < 0 || dividerIndex >= _flexes.length - 1) return;

    final totalFlex = _totalFlex;
    final flexDelta = delta * totalFlex / availableSpace;

    setState(() {
      _flexes[dividerIndex] += flexDelta;
      _flexes[dividerIndex + 1] -= flexDelta;

      final minFlex = (_minPaneSize * totalFlex / availableSpace)
          .clamp(1.0, totalFlex / 2);

      if (_flexes[dividerIndex] < minFlex) {
        final diff = minFlex - _flexes[dividerIndex];
        _flexes[dividerIndex] = minFlex;
        _flexes[dividerIndex + 1] -= diff;
      }
      if (_flexes[dividerIndex + 1] < minFlex) {
        final diff = minFlex - _flexes[dividerIndex + 1];
        _flexes[dividerIndex + 1] = minFlex;
        _flexes[dividerIndex] -= diff;
      }
    });

    widget.onResized?.call(List<double>.from(_flexes));
  }

  void _equalizeAdjacent(int dividerIndex) {
    if (dividerIndex < 0 || dividerIndex >= _flexes.length - 1) return;
    final avg = (_flexes[dividerIndex] + _flexes[dividerIndex + 1]) / 2.0;
    setState(() {
      _flexes[dividerIndex] = avg;
      _flexes[dividerIndex + 1] = avg;
    });
    widget.onResized?.call(List<double>.from(_flexes));
  }

  List<Widget> _buildPanes(double availableSpace) {
    final count = widget.sessions.length;
    if (count == 0) {
      return const [Center(child: Text('No terminals'))];
    }
    if (count == 1) {
      return [
        TermisolTerminalView(
          session: widget.sessions.first,
          onNewTab: widget.onNewTab,
          onCloseTab: widget.onCloseTab,
        ),
      ];
    }

    final children = <Widget>[];
    for (int i = 0; i < count; i++) {
      children.add(
        Expanded(
          flex: math.max(1, _flexes[i].round()),
          child: TermisolTerminalView(
            session: widget.sessions[i],
            onNewTab: widget.onNewTab,
            onCloseTab: widget.onCloseTab,
          ),
        ),
      );
      if (i < count - 1) {
        children.add(_buildDivider(i, availableSpace));
      }
    }
    return children;
  }

  Widget _buildDivider(int index, double availableSpace) {
    final isHorizontal = widget.isHorizontal;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: isHorizontal
          ? (details) => _onDrag(index, details.delta.dx, availableSpace)
          : null,
      onVerticalDragUpdate: !isHorizontal
          ? (details) => _onDrag(index, details.delta.dy, availableSpace)
          : null,
      onDoubleTap: () => _equalizeAdjacent(index),
      child: MouseRegion(
        cursor: isHorizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: Container(
          width: isHorizontal ? _dividerThickness : double.infinity,
          height: isHorizontal ? double.infinity : _dividerThickness,
          color: PkmTheme.tabInactiveBg,
          alignment: Alignment.center,
          child: Container(
            width: isHorizontal ? 2.0 : 12.0,
            height: isHorizontal ? 12.0 : 2.0,
            decoration: BoxDecoration(
              color: PkmTheme.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = widget.isHorizontal;
        final totalSize = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dividerCount = math.max(0, widget.sessions.length - 1);
        final totalDividerSpace = dividerCount * _dividerThickness;
        final availableSpace = math.max(0.0, totalSize - totalDividerSpace);

        final panes = _buildPanes(availableSpace);

        if (widget.sessions.length <= 1) {
          return panes.isNotEmpty
              ? panes.first
              : const SizedBox.shrink();
        }

        return isHorizontal
            ? Row(children: panes)
            : Column(children: panes);
      },
    );
  }
}
