import 'package:flutter/services.dart';

/// Format phone: 10 digits → xxxx-xxx-xxx, 9 digits → xxx-xxx-xxx, else as-is.
String formatPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return '${digits.substring(0, 4)}-${digits.substring(4, 7)}-${digits.substring(7)}';
  } else if (digits.length == 9) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  return phone;
}

/// TextInputFormatter that auto-formats phone numbers as user types.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    String formatted;
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.length <= 6) {
      formatted = '${digits.substring(0, 3)}-${digits.substring(3)}';
    } else if (digits.length <= 9) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    } else {
      // 10+ digits: xxxx-xxx-xxxx
      formatted =
          '${digits.substring(0, 4)}-${digits.substring(4, 7)}-${digits.substring(7, 10)}';
      if (digits.length > 10) {
        formatted += digits.substring(10);
      }
    }

    // Map cursor through formatting by counting digit positions
    int digitsBefore = 0;
    for (int i = 0;
        i < newValue.selection.baseOffset && i < newValue.text.length;
        i++) {
      if (newValue.text.codeUnitAt(i) >= 48 &&
          newValue.text.codeUnitAt(i) <= 57) {
        digitsBefore++;
      }
    }
    int offset = formatted.length;
    for (int i = 0, count = 0; i < formatted.length; i++) {
      if (count == digitsBefore) {
        offset = i;
        break;
      }
      if (formatted.codeUnitAt(i) >= 48 && formatted.codeUnitAt(i) <= 57) {
        count++;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
