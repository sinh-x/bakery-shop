import 'package:bakery_app/shared/widgets/upload_progress_indicator.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

PhotoUploadState _state(PhotoUploadStatus status, {String? error}) =>
    PhotoUploadState(status: status, errorMessage: error);

void main() {
  group('UploadProgressIndicator', () {
    testWidgets('renders nothing when states is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const UploadProgressIndicator(states: []),
      ));

      expect(find.byType(UploadProgressIndicator), findsOneWidget);
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
    });

    testWidgets('renders one row per photo with matching status icon',
        (tester) async {
      final states = [
        _state(PhotoUploadStatus.pending),
        _state(PhotoUploadStatus.uploading),
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.error, error: 'boom'),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);

      // Per-photo status lines present.
      expect(
        find.text(VN.photoUploadStatus(1, VN.photoUploadStatusLabels['pending']!)),
        findsOneWidget,
      );
      expect(
        find.text(VN.photoUploadStatus(3, VN.photoUploadStatusLabels['success']!)),
        findsOneWidget,
      );
      expect(
        find.text(VN.photoUploadFailed(4, 'boom')),
        findsOneWidget,
      );
    });

    testWidgets('shows success-only count summary while uploading', (tester) async {
      final states = [
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.uploading),
        _state(PhotoUploadStatus.pending),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(find.text(VN.uploadedPhotosCount(1, 3)), findsOneWidget);
    });

    testWidgets('shows error count summary while uploading when any failed',
        (tester) async {
      final states = [
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.error, error: 'x'),
        _state(PhotoUploadStatus.uploading),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(
        find.text(VN.uploadedPhotosCountWithErrors(1, 1, 3)),
        findsOneWidget,
      );
    });

    testWidgets('shows terminal success summary when all done', (tester) async {
      final states = [
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.success),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(find.text(VN.photoUploadComplete(2)), findsOneWidget);
    });

    testWidgets('shows terminal error summary when batch finished with errors',
        (tester) async {
      final states = [
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.error, error: 'bad'),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(
        find.text(VN.photoUploadCompleteWithErrors(1, 1, 2)),
        findsOneWidget,
      );
    });

    testWidgets('compact variant renders a single inline row', (tester) async {
      final states = [
        _state(PhotoUploadStatus.success),
        _state(PhotoUploadStatus.uploading),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states, compact: true),
      ));

      // Compact renders exactly one Row (the inline row), no per-photo rows.
      final rows = tester.widgetList<Row>(find.byType(Row));
      expect(rows, isNotEmpty);
      // The summary text is present in the compact row.
      expect(find.text(VN.uploadedPhotosCount(1, 2)), findsOneWidget);
      // No per-photo error/pending icons in compact mode.
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
    });

    testWidgets('error row displays the error message text', (tester) async {
      final states = [
        _state(PhotoUploadStatus.error, error: 'disk full'),
      ];

      await tester.pumpWidget(_wrap(
        UploadProgressIndicator(states: states),
      ));

      expect(find.textContaining('disk full'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });
  });
}