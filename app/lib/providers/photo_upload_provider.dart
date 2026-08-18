import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../shared/widgets/upload_progress_indicator.dart';

/// Typed exception thrown when a photo-upload batch completes with one or
/// more per-photo failures (DG-333 Phase 5.6-c1-fix m3).
///
/// Replaces the prior `throw Exception(<user-facing VN string>)` pattern in
/// `knowledge_form_screen._uploadNewPhotos` so callers can catch a
/// structured failure instead of string-matching on the user-facing
/// message. The [userMessage] getter formats the VN summary from the
/// structured counts so the catch handler can surface it directly.
class PhotoUploadPartialFailure implements Exception {
  PhotoUploadPartialFailure({
    required this.completedCount,
    required this.failedCount,
    required this.totalCount,
  });

  final int completedCount;
  final int failedCount;
  final int totalCount;

  /// User-facing summary string built from the structured counts.
  String get userMessage => '$completedCount/$totalCount ảnh ($failedCount lỗi)';

  @override
  String toString() => 'PhotoUploadPartialFailure($completedCount/$totalCount, '
      '$failedCount failed)';
}

/// Per-photo upload item tracked by [PhotoUploadNotifier].
///
/// Wraps the Phase 1 [PhotoUploadState] with the originating [fileName] so
/// callers and the [UploadProgressIndicator] can correlate state entries to
/// the picker selection order. [fileName] is read from the [XFile] passed to
/// [PhotoUploadNotifier.uploadAll]; it is purely informational and never
/// used to dedupe uploads (each list entry is distinct by position).
class PhotoUploadItem {
  const PhotoUploadItem({
    required this.fileName,
    required this.state,
  });

  /// Display name of the source file (e.g. `IMG_0001.jpg`).
  final String fileName;

  /// Per-photo status + optional error message consumed by the indicator.
  final PhotoUploadState state;

  PhotoUploadItem copyWith({String? fileName, PhotoUploadState? state}) {
    return PhotoUploadItem(
      fileName: fileName ?? this.fileName,
      state: state ?? this.state,
    );
  }
}

/// Aggregate state emitted by [PhotoUploadNotifier].
///
/// Holds the ordered list of [PhotoUploadItem]s plus convenience accessors
/// used by screens (`totalCount`, `completedCount`, `hasErrors`, `isUploading`).
/// The [states] getter maps each item's [PhotoUploadState] so the shared
/// [UploadProgressIndicator] can consume it directly without coupling to
/// [PhotoUploadItem].
class PhotoUploadBatchState {
  const PhotoUploadBatchState([this.items = const []]);

  final List<PhotoUploadItem> items;

  /// Per-photo states in selection order — feed to [UploadProgressIndicator].
  List<PhotoUploadState> get states =>
      items.map((item) => item.state).toList(growable: false);

  int get totalCount => items.length;

  int get completedCount =>
      items.where((i) => i.state.status == PhotoUploadStatus.success).length;

  int get failedCount =>
      items.where((i) => i.state.status == PhotoUploadStatus.error).length;

  int get pendingCount => items
      .where((i) => i.state.status == PhotoUploadStatus.pending)
      .length;

  int get uploadingCount => items
      .where((i) => i.state.status == PhotoUploadStatus.uploading)
      .length;

  /// True once any item has errored (used to surface summary variants).
  bool get hasErrors => failedCount > 0;

  /// True while at least one item is still pending or uploading.
  bool get isUploading => pendingCount > 0 || uploadingCount > 0;

  /// True when every item has reached a terminal state (success or error).
  bool get isComplete => items.isNotEmpty && !isUploading;

  static PhotoUploadBatchState empty() => const PhotoUploadBatchState();
}

/// Shared Riverpod [Notifier] managing per-photo upload state for all six
/// photo-upload locations (events, expenses, quick-log, orders, knowledge,
/// catalog).
///
/// The notifier is the single source of truth for upload progress/error state
/// (FR4). It owns no network logic: callers pass a per-file [uploadCallback]
/// so the same notifier can wrap `EventService.uploadEventPhoto`,
/// `OrderPhotosNotifier.upload`, `CatalogNotifier.addPhoto`, and
/// `KnowledgeService.attachPhoto` without importing any API service directly
/// (NFR2). Each per-file state transition emits a new state so the
/// [UploadProgressIndicator] rebuilds within 100ms (NFR1).
///
/// Usage:
/// ```dart
/// final upload = ref.read(photoUploadNotifierProvider.notifier);
/// await upload.uploadAll(files, (file) => eventService.uploadEventPhoto(id, file));
/// ```
class PhotoUploadNotifier extends Notifier<PhotoUploadBatchState> {
  @override
  PhotoUploadBatchState build() => PhotoUploadBatchState.empty();

  /// Uploads [files] sequentially, updating per-photo state after each file.
  ///
  /// All items are initialised as [PhotoUploadStatus.pending], then iterated
  /// in order: each item is marked [PhotoUploadStatus.uploading], the
  /// [uploadCallback] is awaited, and on success/error the item transitions
  /// to the corresponding terminal state. Remaining files continue after a
  /// failure (FR2). State is emitted after every transition so watchers
  /// observe progress incrementally.
  ///
  /// Returns when every file has reached a terminal state (success or error).
  /// Safe to call with an empty list (no-op, state stays empty — call
  /// [reset] first if reusing a notifier instance across batches).
  Future<void> uploadAll(
    List<XFile> files,
    Future<void> Function(XFile file) uploadCallback,
  ) async {
    if (files.isEmpty) return;

    state = PhotoUploadBatchState(
      files
          .map((f) => PhotoUploadItem(
                fileName: f.name,
                state: const PhotoUploadState(
                    status: PhotoUploadStatus.pending),
              ))
          .toList(growable: false),
    );

    for (int i = 0; i < files.length; i++) {
      _update(i, status: PhotoUploadStatus.uploading);
      try {
        await uploadCallback(files[i]);
        _update(i, status: PhotoUploadStatus.success);
      } catch (e) {
        _update(
          i,
          status: PhotoUploadStatus.error,
          errorMessage: e.toString(),
        );
      }
    }
  }

  void _update(int index, {required PhotoUploadStatus status, String? errorMessage}) {
    final items = List<PhotoUploadItem>.from(state.items);
    items[index] = items[index].copyWith(
      state: items[index].state.copyWith(
        status: status,
        errorMessage: errorMessage ?? items[index].state.errorMessage,
      ),
    );
    state = PhotoUploadBatchState(items);
  }

  /// Clears state so the notifier can drive a fresh batch of uploads.
  void reset() => state = PhotoUploadBatchState.empty();
}

final photoUploadNotifierProvider =
    NotifierProvider<PhotoUploadNotifier, PhotoUploadBatchState>(
  PhotoUploadNotifier.new,
);