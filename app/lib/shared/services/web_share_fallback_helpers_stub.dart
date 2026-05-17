import 'dart:typed_data';

Future<bool> copyTextToClipboard(String text) async {
  return false;
}

Future<bool> downloadBytesToBrowser(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  if (bytes.isEmpty || fileName.isEmpty) return false;
  return false;
}
