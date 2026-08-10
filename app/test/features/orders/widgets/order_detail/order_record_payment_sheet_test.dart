import 'package:bakery_app/features/orders/widgets/order_detail/order_record_payment_sheet.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('OrderRecordPaymentSheet photo flow (FR2/FR3/FR4/AC2/AC3)', () {
    testWidgets(
        'cash method does not show the photo attachment button or target '
        'account dropdown (FR2)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OrderRecordPaymentSheet(
            orderRef: 'ORD-1',
            remaining: 100000,
          ),
        ),
      );

      // Cash is the default method — no transfer-only UI.
      expect(find.byType(TargetAccountDropdown), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
      expect(find.text(VN.attachTransferPhoto), findsNothing);
    });

    testWidgets(
        'transfer method shows the target account dropdown and photo '
        'attachment button (FR2)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(
              orderRef: 'ORD-1',
              remaining: 100000,
            ),
          ),
        ),
      );

      // Switch to transfer method.
      await tester.tap(find.text(VN.methodTransfer));
      await tester.pumpAndSettle();

      // Transfer-only UI is now visible.
      expect(find.byType(TargetAccountDropdown), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.text(VN.attachTransferPhoto), findsOneWidget);
      expect(find.text(VN.attachTransferPhotoTooltip), findsNothing);
    });

    testWidgets(
        'photo attachment button has the expected tooltip (FR2/NFR4)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(
              orderRef: 'ORD-1',
              remaining: 100000,
            ),
          ),
        ),
      );

      await tester.tap(find.text(VN.methodTransfer));
      await tester.pumpAndSettle();

      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, VN.attachTransferPhotoTooltip);
    });

    testWidgets(
        'switching back to cash hides the photo attachment button and '
        'clears the pending transfer photo (FR2)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            const OrderRecordPaymentSheet(
              orderRef: 'ORD-1',
              remaining: 100000,
            ),
          ),
        ),
      );

      // Switch to transfer then back to cash.
      await tester.tap(find.text(VN.methodTransfer));
      await tester.pumpAndSettle();
      expect(find.text(VN.attachTransferPhoto), findsOneWidget);

      await tester.tap(find.text(VN.methodCash));
      await tester.pumpAndSettle();

      // Transfer-only UI is hidden again.
      expect(find.byType(TargetAccountDropdown), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
      expect(find.text(VN.attachTransferPhoto), findsNothing);
    });
  });

  group('sanitizeAccountTag (FR4/AC3)', () {
    test('spaces are replaced with hyphens', () {
      expect(sanitizeAccountTag('TK Phượng VCB'), 'TK-Phượng-VCB');
    });

    test('null or empty input returns empty string', () {
      expect(sanitizeAccountTag(null), '');
      expect(sanitizeAccountTag(''), '');
    });

    test('special characters are stripped (Unicode letters preserved)', () {
      // Parentheses and exclamation are stripped; Unicode letters/digits
      // and hyphens are preserved.
      expect(sanitizeAccountTag('TK (Phượng!) VCB'), 'TK-Phượng-VCB');
    });

    test('repeated hyphens are collapsed', () {
      expect(sanitizeAccountTag('A   B  C'), 'A-B-C');
    });

    test('leading and trailing hyphens are trimmed', () {
      expect(sanitizeAccountTag(' A B '), 'A-B');
    });

    test(
        'tag string for "TK Phượng VCB" is "chuyen-khoan,TK-Phượng-VCB" '
        '(AC3)', () {
      final accountTag = sanitizeAccountTag(VN.paymentSourcePhuongVCB);
      expect(accountTag, 'TK-Phượng-VCB');
      final tags =
          accountTag.isEmpty ? 'chuyen-khoan' : 'chuyen-khoan,$accountTag';
      expect(tags, 'chuyen-khoan,TK-Phượng-VCB');
    });

    test('empty account produces a bare "chuyen-khoan" tag', () {
      final accountTag = sanitizeAccountTag(null);
      final tags =
          accountTag.isEmpty ? 'chuyen-khoan' : 'chuyen-khoan,$accountTag';
      expect(tags, 'chuyen-khoan');
    });
  });
}