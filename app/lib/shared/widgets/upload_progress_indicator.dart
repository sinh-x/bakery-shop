import 'package:flutter/material.dart';

import 'vietnamese_labels.dart';

/// Per-photo upload status reported by [UploadProgressIndicator].
enum PhotoUploadStatus { pending, uploading, success, error }

/// Immutable state describing a single photo's upload progress.
///
/// The shared [PhotoUploadNotifier] (Phase 2) will emit a list of these
/// states; until then, screens may construct them directly to feed the
/// widget. [errorMessage] is shown only when [status] is [error].
class PhotoUploadState {
  const PhotoUploadState({
    required this.status,
    this.errorMessage,
  });

  final PhotoUploadStatus status;
  final String? errorMessage;

  PhotoUploadState copyWith({PhotoUploadStatus? status, String? errorMessage}) {
    return PhotoUploadState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Shared widget rendering per-photo upload progress and error states with a
/// count summary (e.g. "2/5 uploaded").
///
/// Replaces the duplicated `CircularProgressIndicator` + `Text(VN.uploadingPhotos)`
/// pattern across the 6 photo-upload locations. Per FR5/NFR4 the widget stays
/// under 200 lines and updates within 100ms of each state transition (NFR1)
/// because it is fed by a `Listenable`/`Notifier` rebuilt via `const`.
///
/// The widget is presentational only — it owns no upload logic. Callers pass
/// the current [states] list (typically watched from a Riverpod provider).
/// When [states] is empty the widget renders nothing, so it can remain
/// mounted in forms that have no pending upload.
class UploadProgressIndicator extends StatelessWidget {
  const UploadProgressIndicator({
    super.key,
    required this.states,
    this.compact = false,
  });

  /// Current per-photo states, ordered to match the picker selection order.
  final List<PhotoUploadState> states;

  /// When true, renders a single inline row (icon + count) suitable for
  /// embedding inside an existing button row. Defaults to a full column.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final done = states.where((s) => s.status == PhotoUploadStatus.success).length;
    final failed = states.where((s) => s.status == PhotoUploadStatus.error).length;
    final total = states.length;
    final isUploading = states.any((s) =>
        s.status == PhotoUploadStatus.pending ||
        s.status == PhotoUploadStatus.uploading);
    // Terminal summary (AC6): once every photo reaches a final state, show
    // a distinct "upload complete" summary so the user can confirm the
    // result before the screen pops/resets. DG-333 Phase 6.
    final summary = isUploading
        ? (failed > 0
            ? VN.uploadedPhotosCountWithErrors(done, failed, total)
            : VN.uploadedPhotosCount(done, total))
        : (failed > 0
            ? VN.photoUploadCompleteWithErrors(done, failed, total)
            : VN.photoUploadComplete(total));

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < states.length; i++)
            _PhotoRow(index: i + 1, state: states[i]),
          const SizedBox(height: 6),
          Text(summary, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.index, required this.state});

  final int index;
  final PhotoUploadState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (state.status) {
      PhotoUploadStatus.pending => Icon(
          Icons.radio_button_unchecked,
          size: 16,
          color: theme.colorScheme.outline,
        ),
      PhotoUploadStatus.uploading => SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      PhotoUploadStatus.success => Icon(
          Icons.check_circle,
          size: 16,
          color: theme.colorScheme.primary,
        ),
      PhotoUploadStatus.error => Icon(
          Icons.error,
          size: 16,
          color: theme.colorScheme.error,
        ),
    };

    final label = state.status == PhotoUploadStatus.error && state.errorMessage != null
        ? VN.photoUploadFailed(index, state.errorMessage!)
        : VN.photoUploadStatus(index, VN.photoUploadStatusLabels[state.status.name]!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}