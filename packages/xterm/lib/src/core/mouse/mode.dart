/// https://terminalguide.namepad.de/mouse/
enum MouseMode {
  none,

  clickOnly,

  upDownScroll(reportScroll: true),

  upDownScrollDrag(reportScroll: true),

  upDownScrollMove(reportScroll: true),
  ;

  const MouseMode({this.reportScroll = false});

  final bool reportScroll;
}

/// https://terminalguide.namepad.de/mouse/
enum MouseReportMode {
  /// the default mouse reporting mode where digits are encoded as bytes with
  /// `32 + code`. this mode has a range from 1 to 223.
  normal,

  /// when code < 96 this is the same as [normal], otherwise the `code + 32` is
  /// encoded as 2 bytes in utf-8. this mode has a range from 1 to 2015.
  utf,

  /// in this mode the code are encoded as 10-based numbers. tha range is
  /// unlimited.
  sgr,

  /// similar to [sgr], the difference is that the button id is encoded as
  /// `32 + code`.
  urxvt,
}
