import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Отваря документа в нов раздел; оттам „Печат / PDF“.
bool openPrintPage(String html) {
  final blob = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final w = web.window.open(url, '_blank');
  return w != null;
}
