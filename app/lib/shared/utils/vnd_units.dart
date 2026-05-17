double vndFromThousands(double thousands) => thousands * 1000;

double vndToThousands(double amount) => amount / 1000;

String vndThousandsTextFromAmount(double amount) =>
    vndToThousands(amount).round().toString();

double? parseVndFromThousandsText(String input) {
  final raw = double.tryParse(input.trim());
  if (raw == null) return null;
  return vndFromThousands(raw);
}
