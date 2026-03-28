import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// No-op on web — native only.
Future<void> printNative(BuildContext context, Uint8List imageBytes, dynamic ref) async {}

/// Open receipt image in a browser print window.
void printWeb(Uint8List imageBytes) {
  final base64 = base64Encode(imageBytes);
  final html = '''
<!DOCTYPE html>
<html>
<head><title>In phiếu</title>
<style>
  body { margin: 0; display: flex; justify-content: center; }
  img { max-width: 100%; height: auto; }
  @media print { body { margin: 0; } }
</style>
</head>
<body>
<img src="data:image/png;base64,$base64" onload="window.print()">
</body>
</html>
''';
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}

/// No-op on web — save handled differently.
Future<void> saveToFile(Uint8List imageBytes, String fileName) async {
  // Trigger download via anchor element
  final base64 = base64Encode(imageBytes);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = 'data:image/png;base64,$base64';
  anchor.download = fileName;
  anchor.click();
}
