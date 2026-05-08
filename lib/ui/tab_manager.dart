import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../core/terminal_session.dart';

/// Manages a collection of terminal tabs with ordering, pinning, and metadata.
///
/// This class is intentionally separate from the UI so it can be tested
/// independently and reused across different presentation layers.
class TabManager extends ChangeNotifier {
  final List<TerminalSession> _tabs = [];
  final List<bool> _pinned = [];
  int _activeIndex = 0;

  UnmodifiableListView<TerminalSession> get tabs => UnmodifiableListView(_tabs);
  int get activeIndex => _activeIndex;
  int get count => _tabs.length;
  bool get canCloseActive => _tabs.length > 1;

  TerminalSession? get activeTab => _tabs.isEmpty ? null : _tabs[_activeIndex];

  /// Create a new tab and make it active.
  TerminalSession addTab({String? name}) {
    final id = 'session_${DateTime.now().millisecondsSinceEpoch}_${_tabs.length}';
    final session = TerminalSession(
      id: id,
      name: name ?? 'tab ${_tabs.length + 1}',
    );
    _tabs.add(session);
    _pinned.add(false);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return session;
  }

  /// Close the tab at [index]. Pinned tabs cannot be closed.
  bool closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return false;
    if (_pinned[index]) return false;
    if (_tabs.length <= 1) return false;

    final session = _tabs.removeAt(index);
    _pinned.removeAt(index);
    session.disposeSession();

    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    }
    notifyListeners();
    return true;
  }

  /// Switch to the tab at [index].
  void switchTo(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Switch to the next tab, wrapping around.
  void nextTab() {
    if (_tabs.isEmpty) return;
    switchTo((_activeIndex + 1) % _tabs.length);
  }

  /// Switch to the previous tab, wrapping around.
  void prevTab() {
    if (_tabs.isEmpty) return;
    switchTo((_activeIndex - 1 + _tabs.length) % _tabs.length);
  }

  /// Toggle the pinned state of the tab at [index].
  void togglePin(int index) {
    if (index < 0 || index >= _pinned.length) return;
    _pinned[index] = !_pinned[index];
    notifyListeners();
  }

  bool isPinned(int index) {
    if (index < 0 || index >= _pinned.length) return false;
    return _pinned[index];
  }

  /// Reorder tabs by moving the tab at [fromIndex] to [toIndex].
  void reorder(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= _tabs.length) return;
    if (toIndex < 0 || toIndex >= _tabs.length) return;

    final session = _tabs.removeAt(fromIndex);
    final pinned = _pinned.removeAt(fromIndex);

    _tabs.insert(toIndex, session);
    _pinned.insert(toIndex, pinned);

    // Update active index to follow the moved tab.
    if (_activeIndex == fromIndex) {
      _activeIndex = toIndex;
    } else if (fromIndex < _activeIndex && toIndex >= _activeIndex) {
      _activeIndex--;
    } else if (fromIndex > _activeIndex && toIndex <= _activeIndex) {
      _activeIndex++;
    }

    notifyListeners();
  }

  /// Update the name of the tab at [index].
  void renameTab(int index, String name) {
    if (index < 0 || index >= _tabs.length) return;
    if (name.trim().isEmpty) return;
    
    // Create a new session with the updated name since TerminalSession.name is final
    final oldSession = _tabs[index];
    final newSession = TerminalSession(
      id: oldSession.id,
      name: name.trim(),
    );
    
    // Copy session data from old session
    newSession.copyFrom(oldSession);
    
    // Replace the old session
    _tabs[index] = newSession;
    oldSession.disposeSession();
    
    notifyListeners();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.disposeSession();
    }
    _tabs.clear();
    _pinned.clear();
    super.dispose();
  }
}
