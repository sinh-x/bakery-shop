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

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: const Wrap(
        spacing: 4,
        children: [
          RadioListTile<String>(
            title: Text(VN.candleTypeNenSo),
            value: 'nen_so',
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            title: Text(VN.candleTypeNenXoan),
            value: 'nen_xoan',
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            title: Text(VN.candleTypeNenNho),
            value: 'nen_nho',
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            title: Text(VN.candleTypeKhongNen),
            value: 'khong_nen',
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}