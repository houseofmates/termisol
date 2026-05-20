enum PointerInput {
  /// taps / buttons presses & releases.
  tap,

  /// scroll / mouse wheels events.
  scroll,

  /// drag events, a pointer is in a down state and dragged across the terminal.
  drag,

  /// move events, a pointer is in an up state and moved across the terminal.
  move,
}

class PointerInputs {
  final Set<PointerInput> inputs;

  const PointerInputs(this.inputs);

  const PointerInputs.none() : inputs = const <PointerInput>{};

  const PointerInputs.all()
      : inputs = const <PointerInput>{
          PointerInput.tap,
          PointerInput.scroll,
          PointerInput.drag,
          PointerInput.move,
        };
}
