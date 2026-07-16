import 'package:bakery_app/shared/utils/phone_formatter.dart';
import 'package:bakery_app/shared/widgets/phone_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _kLabel = 'Số điện thoại';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        )),
      ),
    );

void main() {
  testWidgets('renders with the provided labelText', (tester) async {
    await tester.pumpWidget(_wrap(
      PhoneTextField(
        controller: TextEditingController(),
        labelText: _kLabel,
      ),
    ));
    expect(find.text(_kLabel), findsOneWidget);
    expect(find.byType(PhoneTextField), findsOneWidget);
  });

  testWidgets('uses the phone keyboard', (tester) async {
    await tester.pumpWidget(_wrap(
      PhoneTextField(
        controller: TextEditingController(),
        labelText: _kLabel,
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.phone);
  });

  testWidgets('applies PhoneInputFormatter for 10 digits -> xxxx-xxx-xxx',
      (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(
      PhoneTextField(controller: ctrl, labelText: _kLabel),
    ));
    await tester.enterText(find.byType(TextFormField), '0912345678');
    expect(ctrl.text, '0912-345-678');
  });

  testWidgets('applies PhoneInputFormatter for 9 digits -> xxx-xxx-xxx',
      (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(
      PhoneTextField(controller: ctrl, labelText: _kLabel),
    ));
    await tester.enterText(find.byType(TextFormField), '091234567');
    expect(ctrl.text, '091-234-567');
  });

  testWidgets('enforces 20-char length limit', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(
      PhoneTextField(controller: ctrl, labelText: _kLabel),
    ));
    await tester.enterText(find.byType(TextFormField), '1234567890123456789012');
    // PhoneInputFormatter formats first 10 digits as xxxx-xxx-xxx then appends
    // remaining unformatted digits; LengthLimittingTextInputFormatter caps
    // total chars at 20.
    expect(ctrl.text.length, lessThanOrEqualTo(20));
  });

  testWidgets('forwards textInputAction', (tester) async {
    await tester.pumpWidget(_wrap(
      PhoneTextField(
        controller: TextEditingController(),
        labelText: _kLabel,
        textInputAction: TextInputAction.next,
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textInputAction, TextInputAction.next);
  });

  testWidgets('forwards validator', (tester) async {
    String? validator(String? v) => v == null || v.isEmpty ? 'required' : null;
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(_wrap(
      Form(
        key: formKey,
        child: PhoneTextField(
          controller: TextEditingController(),
          labelText: _kLabel,
          validator: validator,
        ),
      ),
    ));
    expect(formKey.currentState!.validate(), false);
  });

  testWidgets('merges decorationExtras over defaults', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(
      PhoneTextField(
        controller: ctrl,
        labelText: _kLabel,
        decorationExtras: const InputDecoration(hintText: 'vd: 09xx...xxx'),
      ),
    ));
    // Label still present, plus the caller-supplied hint.
    expect(find.text(_kLabel), findsOneWidget);
    expect(find.text('vd: 09xx...xxx'), findsOneWidget);
  });

  testWidgets('both formatters are present', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(_wrap(
      PhoneTextField(controller: ctrl, labelText: _kLabel),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    final types = field.inputFormatters!.map((f) => f.runtimeType).toList();
    expect(types, contains(PhoneInputFormatter));
    expect(types, contains(LengthLimitingTextInputFormatter));
  });
}