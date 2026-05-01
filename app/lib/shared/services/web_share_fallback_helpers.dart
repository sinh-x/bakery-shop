import 'dart:typed_data';

import 'web_share_fallback_helpers_stub.dart'
    if (dart.library.html) 'web_share_fallback_helpers_web.dart'
    as impl;

/// Shared web fallback helpers used by share and download flows.
///
/// The web implementation is loaded only when compiling for web via conditional
/// imports. Non-web builds call into the stub which returns `false`.
class WebShareFallbackHelpers {
  static Future<bool> copyText(String text) => impl.copyTextToClipboard(text);

  static Future<bool> downloadBytes(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/octet-stream',
  }) => impl.downloadBytesToBrowser(bytes, fileName, mimeType: mimeType);
}
