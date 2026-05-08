import 'package:flutter/widgets.dart';

/// Global dispatcher for GNOME header bar button actions.
class HeaderbarActions {
  static final ValueNotifier<String?> action = ValueNotifier<String?>(null);

  static void dispatch(String actionName) {
    action.value = actionName;
    // Clear after a frame so the same action can be fired again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action.value = null;
    });
  }
}
