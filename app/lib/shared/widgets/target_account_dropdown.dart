import 'package:flutter/material.dart';

import 'vietnamese_labels.dart';

class TargetAccountDropdown extends StatelessWidget {
  const TargetAccountDropdown({
    super.key,
    this.value,
    this.onChanged,
  });

  final String? value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      // `initialValue` does not respond to rebuilds, so the deprecated `value`
      // parameter remains the correct choice for this stateless widget pattern.
      // ignore: deprecated_member_use
      value: value,
      decoration: const InputDecoration(
        labelText: VN.paymentTargetAccountLabel,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text(VN.paymentNoAccount),
        ),
        for (final account in paymentTargetAccounts)
          DropdownMenuItem<String?>(
            value: account,
            child: Text(account),
          ),
      ],
      onChanged:
          onChanged == null ? null : (value) => onChanged!(value),
    );
  }
}
