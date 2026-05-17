import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts between VND and thousand-unit text', () {
    expect(vndToThousands(200000), 200);
    expect(vndFromThousands(200), 200000);
    expect(vndThousandsTextFromAmount(150000), '150');
    expect(parseVndFromThousandsText('250'), 250000);
  });
}
