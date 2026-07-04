import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/data/providers/reconciliation_math.dart';
import 'package:bakery_app/data/providers/reconciliation_state.dart';
import 'package:flutter_test/flutter_test.dart';

ReconciliationDraftOption _option({int expected = 5, int price = 100000}) {
  return ReconciliationDraftOption(
    productId: 1,
    normalizedPrice: price,
    chipLabel: 'Gia goc',
    sourceChipIds: const <int>[],
    sourceChipLabels: const <String>[],
    expectedQty: expected,
  );
}

void main() {
  group('hasReconciliationOptionIssue surplus handling', () {
    test('surplus with no sale/waste is not an issue', () {
      final option = _option(expected: 5);
      final issue = hasReconciliationOptionIssue(
        option: option,
        counted: 8,
        saleRows: const <ReconciliationSaleRowInput>[],
        waste: 0,
        wasteReason: '',
      );
      expect(issue, isFalse);
    });

    test('surplus with sale rows is an issue', () {
      final option = _option(expected: 5);
      final issue = hasReconciliationOptionIssue(
        option: option,
        counted: 8,
        saleRows: <ReconciliationSaleRowInput>[
          ReconciliationSaleRowInput(
            quantity: 1,
            unitPrice: 12000,
            paymentMethod: 'cash',
          ),
        ],
        waste: 0,
        wasteReason: '',
      );
      expect(issue, isTrue);
    });

    test('surplus with waste is an issue', () {
      final option = _option(expected: 5);
      final issue = hasReconciliationOptionIssue(
        option: option,
        counted: 8,
        saleRows: const <ReconciliationSaleRowInput>[],
        waste: 1,
        wasteReason: ' spilled',
      );
      expect(issue, isTrue);
    });
  });

  group('validateReconciliationState surplus handling', () {
    ReconciliationState buildState({
      required int counted,
      List<ReconciliationSaleRowInput> saleRows = const <ReconciliationSaleRowInput>[],
      int waste = 0,
      String wasteReason = '',
      int expected = 5,
    }) {
      return ReconciliationState(
        draft: ReconciliationDraft(
          date: '2026-07-05',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh',
              category: 'banh_kem',
              expectedQty: expected,
              basePrice: 100000,
              priceChips: const <ReconciliationPriceChip>[],
              options: [_option(expected: expected)],
            ),
          ],
        ),
        countedQtyByOption: <String, int>{'1:100000': counted},
        wasteQtyByOption: <String, int>{'1:100000': waste},
        wasteReasonByOption: <String, String>{'1:100000': wasteReason},
        saleRowsByOption: <String, List<ReconciliationSaleRowInput>>{
          '1:100000': saleRows,
        },
      );
    }

    test('surplus with no sale/waste passes validation', () {
      final result = validateReconciliationState(
        buildState(counted: 8, expected: 5),
        'An',
      );
      expect(result, isNull);
    });

    test('surplus with sale rows fails validation', () {
      final result = validateReconciliationState(
        buildState(
          counted: 8,
          expected: 5,
          saleRows: <ReconciliationSaleRowInput>[
            ReconciliationSaleRowInput(
              quantity: 1,
              unitPrice: 12000,
              paymentMethod: 'cash',
            ),
          ],
        ),
        'An',
      );
      expect(result, isNotNull);
      expect(result!.optionErrors['1:100000'], isNotNull);
    });

    test('surplus with waste fails validation', () {
      final result = validateReconciliationState(
        buildState(counted: 8, expected: 5, waste: 1, wasteReason: 'spilled'),
        'An',
      );
      expect(result, isNotNull);
      expect(result!.optionErrors['1:100000'], isNotNull);
    });
  });

  group('ReconciliationState.surplusQtyFor', () {
    test('returns surplus when counted > expected', () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:100000': 8},
      );
      expect(state.surplusQtyFor('1:100000', 5), 3);
    });

    test('returns 0 when counted == expected', () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:100000': 5},
      );
      expect(state.surplusQtyFor('1:100000', 5), 0);
    });

    test('returns 0 when counted < expected (missing case)', () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:100000': 2},
      );
      expect(state.surplusQtyFor('1:100000', 5), 0);
    });

    test('returns 0 when option key absent', () {
      final state = ReconciliationState();
      expect(state.surplusQtyFor('1:100000', 5), 0);
    });

    test('hasSurplusFor reflects surplusQtyFor', () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:100000': 8},
      );
      expect(state.hasSurplusFor('1:100000', 5), isTrue);
      expect(state.hasSurplusFor('1:100000', 8), isFalse);
    });
  });

  group('buildSubmitLines surplus payload', () {
    test('surplus line includes counted > expected with zero sale/waste', () {
      final state = ReconciliationState(
        draft: ReconciliationDraft(
          date: '2026-07-05',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const <ReconciliationPriceChip>[],
            ),
          ],
        ),
        countedQtyByOption: const <String, int>{'1:100000': 8},
        wasteQtyByOption: const <String, int>{'1:100000': 0},
        wasteReasonByOption: const <String, String>{'1:100000': ''},
        saleRowsByOption:
            const <String, List<ReconciliationSaleRowInput>>{
              '1:100000': <ReconciliationSaleRowInput>[],
            },
      );
      final lines = buildSubmitLines(state);
      expect(lines.length, 1);
      expect(lines.single.expectedQty, 5);
      expect(lines.single.countedQty, 8);
      expect(lines.single.saleQty, 0);
      expect(lines.single.wasteQty, 0);
    });
  });
}