import 'dart:typed_data';

class ImageDownloadMetadata {
  const ImageDownloadMetadata({
    required this.extension,
    required this.mimeType,
  });

  final String extension;
  final String mimeType;
}

const _defaultImageMetadata = ImageDownloadMetadata(
  extension: 'jpg',
  mimeType: 'image/jpeg',
);

ImageDownloadMetadata imageDownloadMetadata(
  Uint8List bytes, {
  String? sourceName,
}) {
  final fromBytes = _metadataFromBytes(bytes);
  if (fromBytes != null) return fromBytes;

  final fromName = _metadataFromSourceName(sourceName);
  if (fromName != null) return fromName;

  return _defaultImageMetadata;
}

String imageDownloadFileName(String baseName, ImageDownloadMetadata metadata) {
  final cleanBase = baseName.replaceFirst(
    RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false),
    '',
  );
  return '$cleanBase.${metadata.extension}';
}

ImageDownloadMetadata? _metadataFromBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return _defaultImageMetadata;
  }

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return const ImageDownloadMetadata(extension: 'png', mimeType: 'image/png');
  }

  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return const ImageDownloadMetadata(
      extension: 'webp',
      mimeType: 'image/webp',
    );
  }

  if (bytes.length >= 6) {
    final header = String.fromCharCodes(bytes.take(6));
    if (header == 'GIF87a' || header == 'GIF89a') {
      return const ImageDownloadMetadata(
        extension: 'gif',
        mimeType: 'image/gif',
      );
    }
  }

  return null;
}

ImageDownloadMetadata? _metadataFromSourceName(String? sourceName) {
  if (sourceName == null || sourceName.isEmpty) return null;
  final match = RegExp(r'\.([a-zA-Z0-9]+)(?:[?#].*)?$').firstMatch(sourceName);
  if (match == null) return null;

  switch (match.group(1)?.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return _defaultImageMetadata;
    case 'png':
      return const ImageDownloadMetadata(
        extension: 'png',
        mimeType: 'image/png',
      );
    case 'webp':
      return const ImageDownloadMetadata(
        extension: 'webp',
        mimeType: 'image/webp',
      );
    case 'gif':
      return const ImageDownloadMetadata(
        extension: 'gif',
        mimeType: 'image/gif',
      );
  }

  return null;
}
