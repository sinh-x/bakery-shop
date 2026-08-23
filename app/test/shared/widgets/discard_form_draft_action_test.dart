import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/widgets/discard_form_draft_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('is absent for a clean draft', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscardFormDraftAction(isDirty: false, onDiscard: () {}),
        ),
      ),
    );

    expect(find.text(SharedLabels.clearDraft), findsNothing);
  });

  testWidgets('cancelled confirmation preserves the draft', (tester) async {
    var discardCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscardFormDraftAction(
            isDirty: true,
            onDiscard: () => discardCount++,
          ),
        ),
      ),
    );

    await tester.tap(find.text(SharedLabels.clearDraft));
    await tester.pumpAndSettle();
    expect(
      find.text(SharedLabels.clearDraftConfirmationMessage),
      findsOneWidget,
    );

    await tester.tap(find.text(SharedLabels.keepDraft));
    await tester.pumpAndSettle();

    expect(discardCount, 0);
  });

  testWidgets('confirmed action clears the dirty draft', (tester) async {
    var discarded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscardFormDraftAction(
            isDirty: true,
            onDiscard: () => discarded = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text(SharedLabels.clearDraft));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, SharedLabels.clearDraft),
    );
    await tester.pumpAndSettle();

    expect(discarded, isTrue);
  });
}
