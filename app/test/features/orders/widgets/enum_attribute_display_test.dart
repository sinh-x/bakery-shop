import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/features/orders/widgets/enum_attribute_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _nhanBanh = EnumAttribute(
  attributeType: 'nhan_banh',
  labelVi: 'Nhân bánh',
  options: [
    EnumOption(id: 1, valueVi: 'Sầu riêng', isDefault: true),
    EnumOption(id: 2, valueVi: 'Sô-cô-la'),
  ],
);

const _mauKem = EnumAttribute(
  attributeType: 'mau_kem',
  labelVi: 'Màu kem',
  options: [
    EnumOption(id: 10, valueVi: 'Hồng'),
    EnumOption(id: 11, valueVi: 'Trắng'),
  ],
);

Future<List<Widget>> _capture(
  WidgetTester tester,
  Map<String, dynamic> attributes,
  List<EnumAttribute> enumAttributes,
) async {
  late List<Widget> result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            result = buildEnumAttributeLines(context, attributes, enumAttributes);
            return Column(children: result);
          },
        ),
      ),
    ),
  );
  return result;
}

void main() {
  group('buildEnumAttributeLines', () {
    testWidgets('AC-6: renders "<label>: <value>" for an enum selection', (tester) async {
      await _capture(
        tester,
        {'nhan_banh': 'Sô-cô-la'},
        const [_nhanBanh],
      );
      expect(find.text('Nhân bánh: Sô-cô-la'), findsOneWidget);
    });

    testWidgets('renders one line per enum attribute (Q3)', (tester) async {
      await _capture(
        tester,
        {'nhan_banh': 'Sầu riêng', 'mau_kem': 'Hồng'},
        const [_nhanBanh, _mauKem],
      );
      expect(find.text('Nhân bánh: Sầu riêng'), findsOneWidget);
      expect(find.text('Màu kem: Hồng'), findsOneWidget);
    });

    testWidgets('returns empty when no enum attributes', (tester) async {
      final widgets = await _capture(tester, {'nhan_banh': 'Sầu riêng'}, const []);
      expect(widgets, isEmpty);
    });

    testWidgets('AC-1: skips attributes with no stored value', (tester) async {
      await _capture(tester, const {}, const [_nhanBanh]);
      expect(find.textContaining('Nhân bánh:'), findsNothing);
    });

    testWidgets('skips attributes with empty-string value', (tester) async {
      await _capture(
        tester,
        {'nhan_banh': ''},
        const [_nhanBanh],
      );
      expect(find.textContaining('Nhân bánh:'), findsNothing);
    });

    testWidgets('renders only the attributes that have a value', (tester) async {
      await _capture(
        tester,
        {'nhan_banh': 'Dâu'},
        const [_nhanBanh, _mauKem],
      );
      expect(find.text('Nhân bánh: Dâu'), findsOneWidget);
      expect(find.textContaining('Màu kem'), findsNothing);
    });
  });
}
