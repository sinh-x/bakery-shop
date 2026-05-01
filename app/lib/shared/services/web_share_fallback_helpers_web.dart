// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> copyTextToClipboard(String text) async {
  try {
    final clipboard = html.window.navigator.clipboard;
    if (clipboard == null) return false;
    await clipboard.writeText(text);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> downloadBytesToBrowser(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      final link = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..style.display = 'none';
      html.document.body?.append(link);
      link.click();
      link.remove();
      return true;
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  } catch (_) {
    return false;
  }
}
