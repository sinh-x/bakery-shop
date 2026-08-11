import 'package:flutter/material.dart';

import '../../../shared/widgets/vietnamese_labels.dart';

/// Shared radio group for the cake item candle type selection (DG-340).
///
/// Extracted from `cake_detail_body.dart`, `expandable_item_card.dart`, and
/// `work_item_edit_card.dart` to remove the ~40-line duplicated
/// `RadioGroup<String>` + 4 `RadioListTile<String>` tree (review finding
/// CQ-1). All three call sites now reduce to a single
/// `CandleTypeRadioGroup(groupValue: ..., onChanged: ...)` invocation plus a
/// section label.
///
/// The four options (`nen_so`, `nen_xoan`, `nen_nho`, `khong_nen`) are fixed
/// constants; callers own the selected value and persist it (FR2/AC7).
///
/// DG-361 Phase 1 — layout changed from vertical `Column` +
/// `RadioListTile` to horizontal `Wrap` + `Radio` so the four options render
/// in a single row on wide screens and automatically wrap to new lines on
/// narrow screens (≥ 360dp) without overflow (FR1/AC1/NFR3).
class CandleTypeRadioGroup extends StatelessWidget {
  const CandleTypeRadioGroup({
    super.key,
    required this.groupValue,
    required this.onChanged,
  });

  /// Currently selected candle type value (`nen_so`, `nen_xoan`, `nen_nho`,
  /// `khong_nen`) or `null` when nothing is selected yet.
  final String? groupValue;

  /// Notifies the caller when the user picks a different option. `null` is
  /// forwarded by `RadioGroup` when the selection is cleared.
  final ValueChanged<String?> onChanged;

  /// Builds a single tappable option row: a [Radio] button followed by its
  /// VN label. Tapping either the radio or the label selects the option,
  /// mirroring the previous `RadioListTile` affordance so existing widget
  /// tests that tap `find.text(...)` keep working.
  Widget _option(BuildContext context, String value, String label) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<String>(value: value),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _option(context, 'nen_so', VN.candleTypeNenSo),
          _option(context, 'nen_xoan', VN.candleTypeNenXoan),
          _option(context, 'nen_nho', VN.candleTypeNenNho),
          _option(context, 'khong_nen', VN.candleTypeKhongNen),
        ],
      ),
    );
  }
}