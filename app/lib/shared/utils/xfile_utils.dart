import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Creates an [XFile] from raw [bytes] with cross-platform handling.
///
/// On web (`kIsWeb`), builds an in-memory [XFile.fromData] since the
/// filesystem is unavailable — the share sheet / download helpers consume
/// the bytes directly.
///
/// On native platforms, writes [bytes] to a temporary file under
/// [getTemporaryDirectory] and returns an [XFile] backed by that path.
/// Callers that need to clean up the temp file afterwards can read
/// `xfile.path` (it is a real filesystem path on native).
///
/// [fileName] is required and used both for the in-memory name (web) and
/// the temp file basename (native). [mimeType] is optional and forwarded
/// to the [XFile] for both paths.
Future<XFile> createXFileFromBytes(
  Uint8List bytes, {
  required String fileName,
  String? mimeType,
}) async {
  if (kIsWeb) {
    return XFile.fromData(bytes, mimeType: mimeType, name: fileName);
  }
  final tmpDir = await getTemporaryDirectory();
  final file = File('${tmpDir.path}/$fileName');
  await file.writeAsBytes(bytes);
  return XFile(file.path, mimeType: mimeType);
}