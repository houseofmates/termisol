enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64 + 4, isWheel: true),

  wheelDown(id: 64 + 5, isWheel: true),

  wheelLeft(id: 64 + 6, isWheel: true),

  wheelRight(id: 64 + 7, isWheel: true),
  ;

  /// the id that is used to report a button press or release to the terminal.
  ///
  /// mouse wheel up / down use button ids 4 = 0100 (binary) and 5 = 0101 (binary).
  /// the bits three and four of the button are transposed by 64 and 128
  /// respectively, when reporting the id of the button and have have to be
  /// adjusted correspondingly.
  final int id;

  /// whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
