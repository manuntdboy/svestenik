import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Ctrl+K (⌘K) в браузъра: хваща се преди браузъра да го вземе за своята
/// търсачка в адресната лента. Връща функция, която спира слушането.
void Function() listenCtrlK(void Function() onPress) {
  final handler = ((web.KeyboardEvent e) {
    if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && (e.key == 'k' || e.key == 'K' || e.code == 'KeyK')) {
      e.preventDefault();
      e.stopPropagation();
      onPress();
    }
  }).toJS;
  web.window.addEventListener('keydown', handler, true.toJS);
  return () => web.window.removeEventListener('keydown', handler, true.toJS);
}
