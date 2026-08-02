import 'dart:typed_data';

import 'package:bakery_app/providers/photo_upload_provider.dart';
import 'package:bakery_app/shared/widgets/upload_progress_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

XFile _file(String name) =>
    XFile.fromData(Uint8List.fromList(const <int>[1, 2, 3]), path: name);

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('PhotoUploadNotifier.uploadAll', () {
    test('empty list is a no-op and leaves state empty', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      await notifier.uploadAll(<XFile>[], (_) async {});

      final state = container.read(photoUploadNotifierProvider);
      expect(state.totalCount, 0);
      expect(state.items, isEmpty);
    });

    test('single file success transitions pending→uploading→success',
        () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      await notifier.uploadAll(
        [_file('a.jpg')],
        (_) async {},
      );

      final state = container.read(photoUploadNotifierProvider);
      expect(state.totalCount, 1);
      expect(state.completedCount, 1);
      expect(state.failedCount, 0);
      expect(state.items.single.fileName, 'a.jpg');
      expect(state.items.single.state.status, PhotoUploadStatus.success);
      expect(state.items.single.state.errorMessage, isNull);
    });

    test('mixed success/failure records per-photo terminal states', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);
      var call = 0;

      await notifier.uploadAll(
        [_file('ok1.jpg'), _file('bad.jpg'), _file('ok2.jpg')],
        (_) async {
          call += 1;
          if (call == 2) {
            throw Exception('boom');
          }
        },
      );

      final state = container.read(photoUploadNotifierProvider);
      expect(state.totalCount, 3);
      expect(state.completedCount, 2);
      expect(state.failedCount, 1);
      expect(state.items[0].state.status, PhotoUploadStatus.success);
      expect(state.items[1].state.status, PhotoUploadStatus.error);
      expect(state.items[1].state.errorMessage, contains('boom'));
      expect(state.items[2].state.status, PhotoUploadStatus.success);
    });

    test('continues remaining files after a mid-batch failure', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);
      var call = 0;

      await notifier.uploadAll(
        [_file('x.jpg'), _file('y.jpg'), _file('z.jpg')],
        (_) async {
          call += 1;
          if (call == 1) throw Exception('first failed');
        },
      );

      final state = container.read(photoUploadNotifierProvider);
      expect(state.completedCount, 2);
      expect(state.failedCount, 1);
      expect(call, 3);
    });

    test('error message propagation stores raw exception toString', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      await notifier.uploadAll(
        [_file('f.jpg')],
        (_) async => throw StateError('network down'),
      );

      final state = container.read(photoUploadNotifierProvider);
      expect(state.items.single.state.status, PhotoUploadStatus.error);
      expect(state.items.single.state.errorMessage,
          contains('network down'));
    });
  });

  group('PhotoUploadBatchState convenience accessors', () {
    test('isUploading true while any item pending or uploading', () {
      const state = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.uploading),
        ),
        PhotoUploadItem(
          fileName: 'b',
          state: PhotoUploadState(status: PhotoUploadStatus.pending),
        ),
      ]);

      expect(state.isUploading, isTrue);
      expect(state.isComplete, isFalse);
      expect(state.uploadingCount, 1);
      expect(state.pendingCount, 1);
    });

    test('hasErrors true when any item errored', () {
      const state = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.success),
        ),
        PhotoUploadItem(
          fileName: 'b',
          state: PhotoUploadState(
            status: PhotoUploadStatus.error,
            errorMessage: 'nope',
          ),
        ),
      ]);

      expect(state.hasErrors, isTrue);
      expect(state.completedCount, 1);
      expect(state.failedCount, 1);
    });

    test('isComplete true only when non-empty and nothing pending/uploading',
        () {
      const done = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.success),
        ),
      ]);
      const withError = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.error),
        ),
      ]);
      final empty = PhotoUploadBatchState.empty();
      const stillUploading = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.uploading),
        ),
      ]);

      expect(done.isComplete, isTrue);
      expect(withError.isComplete, isTrue);
      expect(empty.isComplete, isFalse);
      expect(stillUploading.isComplete, isFalse);
    });

    test('states getter preserves selection order', () {
      const state = PhotoUploadBatchState([
        PhotoUploadItem(
          fileName: 'a',
          state: PhotoUploadState(status: PhotoUploadStatus.success),
        ),
        PhotoUploadItem(
          fileName: 'b',
          state: PhotoUploadState(status: PhotoUploadStatus.error),
        ),
      ]);

      expect(state.states.map((s) => s.status), [
        PhotoUploadStatus.success,
        PhotoUploadStatus.error,
      ]);
    });
  });

  group('PhotoUploadNotifier.reset', () {
    test('clears state back to empty after a batch', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      await notifier.uploadAll([_file('a.jpg')], (_) async {});
      expect(container.read(photoUploadNotifierProvider).totalCount, 1);

      notifier.reset();

      final state = container.read(photoUploadNotifierProvider);
      expect(state.totalCount, 0);
      expect(state.items, isEmpty);
      expect(state.isComplete, isFalse);
    });

    test('reset on fresh notifier stays empty', () {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      notifier.reset();

      expect(container.read(photoUploadNotifierProvider).totalCount, 0);
    });

    test('notifier can be reused for a fresh batch after reset', () async {
      final container = _container();
      final notifier = container.read(photoUploadNotifierProvider.notifier);

      await notifier.uploadAll([_file('a.jpg')], (_) async {});
      notifier.reset();
      await notifier.uploadAll(
        [_file('b.jpg'), _file('c.jpg')],
        (_) async {},
      );

      final state = container.read(photoUploadNotifierProvider);
      expect(state.totalCount, 2);
      expect(state.completedCount, 2);
      expect(state.items.map((i) => i.fileName), ['b.jpg', 'c.jpg']);
    });
  });
}