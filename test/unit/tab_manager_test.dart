import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/ui/tab_manager.dart';

void main() {
  group('TabManager', () {
    test('adds tabs and tracks active index', () {
      final manager = TabManager();
      expect(manager.count, 0);

      manager.addTab(name: 'first');
      expect(manager.count, 1);
      expect(manager.activeIndex, 0);

      manager.addTab(name: 'second');
      expect(manager.count, 2);
      expect(manager.activeIndex, 1);
    });

    test('prevents closing last tab', () {
      final manager = TabManager();
      manager.addTab();

      expect(manager.closeTab(0), isFalse);
      expect(manager.count, 1);
    });

    test('switches tabs correctly', () {
      final manager = TabManager();
      manager.addTab();
      manager.addTab();

      manager.switchTo(0);
      expect(manager.activeIndex, 0);

      manager.nextTab();
      expect(manager.activeIndex, 1);

      manager.nextTab();
      expect(manager.activeIndex, 0);
    });

    test('pins prevent close', () {
      final manager = TabManager();
      manager.addTab();
      manager.addTab();

      manager.togglePin(0);
      expect(manager.isPinned(0), isTrue);
      expect(manager.closeTab(0), isFalse);
      expect(manager.closeTab(1), isTrue);
    });

    test('reorder moves tabs', () {
      final manager = TabManager();
      manager.addTab(name: 'a');
      manager.addTab(name: 'b');

      manager.reorder(0, 1);
      expect(manager.tabs[0].name, 'b');
      expect(manager.tabs[1].name, 'a');
    });
  });
}
