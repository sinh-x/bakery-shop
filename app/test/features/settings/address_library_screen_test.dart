import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/settings/address_library_screen.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [AddressService] with an in-memory store for the management
/// screen. Mirrors the template management screen test pattern
/// (DG-375 Phase 4).
class _FakeAddressService extends AddressService {
  _FakeAddressService(this._store) : super(Dio());

  final List<AddressLibraryEntry> _store;
  int _nextId = 100;

  @override
  Future<List<AddressLibraryEntry>> listLibrary({String? search}) async {
    if (search == null || search.isEmpty) {
      return List<AddressLibraryEntry>.from(_store);
    }
    final lower = search.toLowerCase();
    return _store
        .where((e) => e.displayAddress.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<AddressLibraryEntry> createLibraryEntry({
    required String displayAddress,
    String? googleMapsUrl,
  }) async {
    final entry = AddressLibraryEntry(
      id: _nextId++,
      displayAddress: displayAddress,
      googleMapsUrl: googleMapsUrl,
    );
    _store.add(entry);
    return entry;
  }

  @override
  Future<AddressLibraryEntry> updateLibraryEntry(
    int id, {
    String? displayAddress,
    String? googleMapsUrl,
  }) async {
    final i = _store.indexWhere((e) => e.id == id);
    if (i < 0) {
      throw Exception('not found');
    }
    final existing = _store[i];
    final updated = AddressLibraryEntry(
      id: id,
      displayAddress: displayAddress ?? existing.displayAddress,
      googleMapsUrl: googleMapsUrl ?? existing.googleMapsUrl,
    );
    _store[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteLibraryEntry(int id) async {
    _store.removeWhere((e) => e.id == id);
  }
}

List<AddressLibraryEntry> _seedStore() => const <AddressLibraryEntry>[
      AddressLibraryEntry(
        id: 1,
        displayAddress: '123 Lê Lợi',
        googleMapsUrl: 'https://maps.app.goo.gl/abc',
      ),
      AddressLibraryEntry(
        id: 2,
        displayAddress: '45 Trần Phú',
        googleMapsUrl: null,
      ),
    ];

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  List<AddressLibraryEntry>? seed,
}) async {
  final store = seed != null
      ? List<AddressLibraryEntry>.from(seed)
      : <AddressLibraryEntry>[];
  final fake = _FakeAddressService(store);
  final container = ProviderContainer(
    overrides: [addressServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AddressLibraryScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('AddressLibraryScreen (DG-385 Phase 5 / FR6/FR8/AC6)', () {
    testWidgets('renders title and seed entries (FR6/AC6)', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.text(AddressLabels.libraryTitle), findsOneWidget);
      expect(find.text('123 Lê Lợi'), findsOneWidget);
      expect(find.text('45 Trần Phú'), findsOneWidget);
    });

    testWidgets('shows empty state when library is empty', (tester) async {
      await _pumpScreen(tester, seed: const <AddressLibraryEntry>[]);
      expect(find.text(AddressLabels.libraryEmpty), findsOneWidget);
    });

    testWidgets('search filters entries by address text (FR6/AC6)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.enterText(
        find.byType(TextField),
        'Lê Lợi',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('123 Lê Lợi'), findsOneWidget);
      expect(find.text('45 Trần Phú'), findsNothing);
    });

    testWidgets('clear search restores full list', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      // First filter down to one.
      await tester.enterText(find.byType(TextField), 'Lê Lợi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      // Tap the clear suffix icon to reset.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('123 Lê Lợi'), findsOneWidget);
      expect(find.text('45 Trần Phú'), findsOneWidget);
    });

    testWidgets('edit + delete affordances are rendered on each row',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('FAB is present for adding entries (FR6/AC6)', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('delete confirmation appears and cancels (FR6/AC6)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text(AddressLabels.libraryDeleteConfirmTitle),
          findsOneWidget);
      expect(find.textContaining('123 Lê Lợi'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, VN.cancel));
      await tester.pumpAndSettle();
      expect(find.text('123 Lê Lợi'), findsOneWidget);
    });

    testWidgets('delete confirmation deletes the entry when confirmed',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, AddressLabels.libraryDeleteConfirmAction));
      await tester.pumpAndSettle();
      expect(find.text('123 Lê Lợi'), findsNothing);
    });

    testWidgets('editor dialog creates a new entry (FR8/AC6)', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text(AddressLabels.editorCreateTitle), findsOneWidget);
      // Enter into the address field identified by its label.
      await tester.enterText(
        find.widgetWithText(TextField, AddressLabels.editorAddressLabel),
        '78 Hai Bà Trưng',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, VN.save));
      await tester.pumpAndSettle();
      expect(find.text('78 Hai Bà Trưng'), findsOneWidget);
    });

    testWidgets('editor dialog validates required address', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      // Try to save without entering an address.
      await tester.tap(find.widgetWithText(FilledButton, VN.save));
      await tester.pumpAndSettle();
      expect(find.text(AddressLabels.editorAddressRequired), findsOneWidget);
      // Dialog still open.
      expect(find.text(AddressLabels.editorCreateTitle), findsOneWidget);
    });

    testWidgets('editor dialog edits an existing entry (FR8/AC6)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text(AddressLabels.editorEditTitle), findsOneWidget);
      // The address field is pre-filled. We avoid `find.text` because the
      // row behind the dialog also renders the same address. Locate the
      // address field by its labelText (always rendered) and read the
      // TextEditingController.
      final addressField = find
          .widgetWithText(TextField, AddressLabels.editorAddressLabel);
      final controller =
          (tester.widget(addressField) as TextField).controller;
      expect(controller?.text, '123 Lê Lợi');
    });

    testWidgets(
      'open-maps shortcut appears only on rows with a googleMapsUrl (FB-2)',
      (tester) async {
        await _pumpScreen(tester, seed: _seedStore());
        // _seedStore() has one entry with a link ('123 Lê Lợi') and one
        // without ('45 Trần Phú'), so exactly one open-in-new icon renders.
        expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      },
    );
  });
}