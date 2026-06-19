import 'package:bakery_app/data/api/paper_mode_service.dart';
import 'package:bakery_app/features/settings/widgets/settings_sections.dart';
import 'package:bakery_app/providers/paper_mode_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePaperModeService extends PaperModeService {
  _FakePaperModeService({
    PaperModeStatus? status,
    this.setStatus,
    this.setThrows,
  })  : _status = status ??
            const PaperModeStatus(paperMode: 'label', defaultMode: 'label'),
        super(Dio());

  final PaperModeStatus _status;
  String? setStatus;
  Object? setThrows;
  List<String> setCalls = [];

  @override
  Future<PaperModeStatus> getStatus() async {
    if (setThrows != null && setCalls.isEmpty) {
      // When configured to fail only on set, getStatus still returns _status.
    }
    return _status;
  }

  @override
  Future<void> setMode(String mode) async {
    setCalls.add(mode);
    if (setThrows != null) {
      throw setThrows!;
    }
  }
}

class _ThrowingPaperModeService extends PaperModeService {
  _ThrowingPaperModeService() : super(Dio());

  @override
  Future<PaperModeStatus> getStatus() async {
    throw Exception('network down');
  }
}

void main() {
  group('PaperModeSection', () {
    testWidgets('shows dropdown with label/roll options when loaded',
        (tester) async {
      final service = _FakePaperModeService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperModeServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: Scaffold(body: PaperModeSection())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.paperModeLabel), findsOneWidget);
      expect(find.text(VN.paperModeHelp), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      // The roll option is not the selected value, so it appears once.
      expect(find.text(VN.paperModeRollOption), findsOneWidget);
      // The selected label option appears both as the current value and as a
      // menu item; verify it is present.
      expect(find.text(VN.paperModeLabelOption), findsWidgets);
    });

    testWidgets('shows error message when load fails', (tester) async {
      final service = _ThrowingPaperModeService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperModeServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: Scaffold(body: PaperModeSection())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.paperModeLoadError), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('persists selection and shows saved snackbar', (tester) async {
      final service = _FakePaperModeService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperModeServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: Scaffold(body: PaperModeSection())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.paperModeRollOption).last);
      await tester.pumpAndSettle();

      expect(service.setCalls, ['roll']);
      expect(find.text(VN.paperModeSaved), findsOneWidget);
    });

    testWidgets('shows failure snackbar when set mode fails', (tester) async {
      final service =
          _FakePaperModeService(setThrows: Exception('server error'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperModeServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: Scaffold(body: PaperModeSection())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(VN.paperModeRollOption).last);
      await tester.pumpAndSettle();

      expect(service.setCalls, ['roll']);
      expect(find.text(VN.paperModeSaveFailed), findsOneWidget);
    });
  });
}