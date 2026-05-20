import 'dart:math' show min;

const _kMaxColumns = 1024;

/// manages the tab stop state for a terminal.
class TabStops {
  final _stops = List<bool>.filled(_kMaxColumns, false);

  TabStops() {
    _initialize();
  }

  /// initializes the tab stops to the default 8 column intervals.
  void _initialize() {
    const interval = 8;
    for (var i = 0; i < _kMaxColumns; i += interval) {
      _stops[i] = true;
    }
  }

  /// finds the next tab stop index, which satisfies [start] <= index < [end].
  int? find(int start, int end) {
    if (start >= end) {
      return null;
    }
    end = min(end, _stops.length);
    for (var i = start; i < end; i++) {
      if (_stops[i]) {
        return i;
      }
    }
    return null;
  }

  /// sets the tab stop at [index]. if there is already a tab stop at [index],
  /// this method does nothing.
  ///
  /// see also:
  /// * [clearat] which does the opposite.
  void setAt(int index) {
    assert(index >= 0 && index < _kMaxColumns);
    _stops[index] = true;
  }

  /// clears the tab stop at [index]. if there is no tab stop at [index], this
  /// method does nothing.
  void clearAt(int index) {
    assert(index >= 0 && index < _kMaxColumns);
    _stops[index] = false;
  }

  /// clears all tab stops without resetting them to the default 8 column
  /// intervals.
  void clearAll() {
    _stops.fillRange(0, _kMaxColumns, false);
  }

  /// returns true if there is a tab stop at [index].
  bool isSetAt(int index) {
    return _stops[index];
  }

  /// resets the tab stops to the default 8 column intervals.
  void reset() {
    clearAll();
    _initialize();
  }
}
