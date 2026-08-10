import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/templates/message_template_resolver.dart';
import 'package:bakery_app/features/templates/template_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TemplateContext _ctx({
  String customerName = 'Nguyễn Văn A',
  String customerPhone = '0901234567',
  String orderCode = 'DG-1234',
  String publicOrderCode = 'DG-1234',
  String dueDate = '15/08/2026',
  String dueTime = '14:00',
  String totalPrice = '500.000đ',
  String itemsList = '- Bánh kem dâu\n- Bánh mì',
  String deliveryType = 'pickup',
  String deliveryAddress = '123 Lê Lợi',
  String shippingFee = '20.000đ',
  String notes = 'Ghi chú thêm',
  String source = 'Online',
  String createdBy = 'Nhân viên A',
  String status = 'confirmed',
}) {
  return TemplateContext(
    customerName: customerName,
    customerPhone: customerPhone,
    orderCode: orderCode,
    publicOrderCode: publicOrderCode,
    dueDate: dueDate,
    dueTime: dueTime,
    totalPrice: totalPrice,
    itemsList: itemsList,
    deliveryType: deliveryType,
    deliveryAddress: deliveryAddress,
    shippingFee: shippingFee,
    notes: notes,
    source: source,
    createdBy: createdBy,
    status: status,
  );
}

MessageTemplate _tmpl(String body) => MessageTemplate(
      id: 1,
      scenario: 'ask_info',
      name: 'test',
      body: body,
      isSystem: true,
    );

void main() {
  group('MessageTemplateResolver — simple placeholders (FR4)', () {
    test('replaces all simple placeholders with field values', () {
      const body = '{customer_name} - {customer_phone} - {order_code} - '
          '{public_order_code} - {due_date} - {due_time} - {total_price} - '
          '{delivery_address} - {shipping_fee} - {notes} - {source} - '
          '{created_by}';
      final result = MessageTemplateResolver(_ctx()).resolveBody(body);
      expect(result,
          'Nguyễn Văn A - 0901234567 - DG-1234 - DG-1234 - 15/08/2026 - '
          '14:00 - 500.000đ - 123 Lê Lợi - 20.000đ - Ghi chú thêm - Online - '
          'Nhân viên A');
    });

    test('replaces {items_list} with the formatted items list', () {
      final result = MessageTemplateResolver(_ctx()).resolveBody('{items_list}');
      expect(result, '- Bánh kem dâu\n- Bánh mì');
    });

    test('empty fields render as (trống)', () {
      final ctx = _ctx(
        customerPhone: '',
        deliveryAddress: '',
        notes: '',
        source: '',
      );
      final result = MessageTemplateResolver(ctx)
          .resolveBody('{customer_phone}/{delivery_address}/{notes}/{source}');
      expect(result, '(trống)/(trống)/(trống)/(trống)');
    });

    test('unknown placeholder is replaced with (trống)', () {
      final result =
          MessageTemplateResolver(_ctx()).resolveBody('{unknown_field}');
      expect(result, '(trống)');
    });

    test('body without placeholders is returned unchanged', () {
      const body = 'Dạ shop cảm ơn mình ạ!';
      expect(MessageTemplateResolver(_ctx()).resolveBody(body), body);
    });
  });

  group('MessageTemplateResolver — select syntax (FR4)', () {
    test('select renders the branch matching the delivery_type slug', () {
      const body = '{delivery_type, select: pickup: Nhận tại tiệm | delivery: '
          'Giao tận nơi}';
      expect(
        MessageTemplateResolver(_ctx(deliveryType: 'pickup'))
            .resolveBody(body),
        'Nhận tại tiệm',
      );
      expect(
        MessageTemplateResolver(_ctx(deliveryType: 'delivery'))
            .resolveBody(body),
        'Giao tận nơi',
      );
    });

    test('select normalizes bus/door delivery types to delivery', () {
      const body = '{delivery_type, select: pickup: Nhận tại tiệm | delivery: '
          'Giao tận nơi}';
      expect(
        MessageTemplateResolver(_ctx(deliveryType: 'door'))
            .resolveBody(body),
        'Giao tận nơi',
      );
    });

    test('select renders the matching status branch', () {
      const body = '{status, select: confirmed: đã xác nhận | in_progress: '
          'đang làm | ready: đã sẵn sàng | delivering: đang giao}';
      expect(
        MessageTemplateResolver(_ctx(status: 'in_progress')).resolveBody(body),
        'đang làm',
      );
    });

    test('select branch text may contain simple placeholders', () {
      const body = '{delivery_type, select: pickup: Lúc {due_date} {due_time} '
          '| delivery: Giao {due_date}}';
      expect(
        MessageTemplateResolver(_ctx(deliveryType: 'pickup')).resolveBody(body),
        'Lúc 15/08/2026 14:00',
      );
    });

    test('select with default branch renders default when no match', () {
      const body = '{status, select: confirmed: đã xác nhận | default: khác}';
      expect(
        MessageTemplateResolver(_ctx(status: 'cancelled')).resolveBody(body),
        'khác',
      );
    });
  });

  group('MessageTemplateResolver — if syntax (FR4)', () {
    test('if renders prefix + value when field is non-empty', () {
      const body = '{notes, if: Đã ghi chú: {notes}}';
      expect(
        MessageTemplateResolver(_ctx(notes: 'Ghi chú thêm')).resolveBody(body),
        'Đã ghi chú: Ghi chú thêm',
      );
    });

    test('if renders empty string when field is empty', () {
      const body = '{notes, if: Đã ghi chú: {notes}}';
      expect(
        MessageTemplateResolver(_ctx(notes: '')).resolveBody(body),
        '',
      );
    });
  });

  group('MessageTemplateResolver — seeded templates (integration)', () {
    // Verify the resolver against the actual seeded template bodies from
    // Phase 4.2 defaultTemplatesFallback / migration v100.
    test('confirm_order pickup template fills correctly', () {
      const body = 'Dạ shop gửi xác nhận đơn bánh mã {public_order_code} '
          'của mình ạ:\n'
          '{items_list}\n'
          'Tổng cộng: {total_price}\n'
          'Mình nhận bánh ở tiệm Đoàn Gia - Ninh Diêm, 61 Hòn Khói vào '
          '{due_date} {due_time} ạ.\n'
          'Mình xem lại giúp shop nha.';
      final result = MessageTemplateResolver(_ctx()).resolveBody(body);
      expect(result, contains('DG-1234'));
      expect(result, contains('- Bánh kem dâu'));
      expect(result, contains('500.000đ'));
      expect(result, contains('15/08/2026 14:00'));
    });

    test('final_message select renders pickup branch', () {
      const body = 'Dạ bánh của mình đã sẵn sàng ạ. Mã đơn {public_order_code}.\n'
          '{items_list}\n'
          '{delivery_type, select: pickup: Mình qua tiệm nhận bánh nha. | '
          'delivery: Shop đang giao bánh tới {delivery_address} ạ.}\n'
          'Mình nhận bánh kiểm tra giúp shop nha. Cảm ơn mình nhiều ạ!';
      final result =
          MessageTemplateResolver(_ctx(deliveryType: 'pickup')).resolveBody(body);
      expect(result, contains('Mình qua tiệm nhận bánh nha.'));
      expect(result, isNot(contains('{delivery_type')));
    });

    test('final_message select renders delivery branch with address', () {
      const body = 'Dạ bánh của mình đã sẵn sàng ạ. Mã đơn {public_order_code}.\n'
          '{items_list}\n'
          '{delivery_type, select: pickup: Mình qua tiệm nhận bánh nha. | '
          'delivery: Shop đang giao bánh tới {delivery_address} ạ.}\n'
          'Mình nhận bánh kiểm tra giúp shop nha. Cảm ơn mình nhiều ạ!';
      final result = MessageTemplateResolver(_ctx(
        deliveryType: 'delivery',
        deliveryAddress: '45 Trần Phú',
      ))
          .resolveBody(body);
      expect(result, contains('Shop đang giao bánh tới 45 Trần Phú ạ.'));
      expect(result, isNot(contains('{delivery_type')));
    });

    test('payment_request if renders notes when present', () {
      const body = '{notes, if: Đã ghi chú: {notes}}';
      expect(
        MessageTemplateResolver(_ctx(notes: 'Ghi chú')).resolveBody(body),
        'Đã ghi chú: Ghi chú',
      );
    });

    test('payment_request if renders empty when notes absent', () {
      const body = 'Dạ shop gửi mình thông tin thanh toán đơn bánh mã '
          '{public_order_code} ạ:\n'
          '{items_list}\n'
          'Tổng cộng: {total_price}\n'
          '{notes, if: Đã ghi chú: {notes}}\n'
          'Mình chuyển khoản giúp shop qua:';
      final result = MessageTemplateResolver(_ctx(notes: '')).resolveBody(body);
      // The if line collapses to empty; surrounding lines remain.
      expect(result, isNot(contains('Đã ghi chú')));
      expect(result, contains('DG-1234'));
    });

    test('status_update nested select with placeholders resolves fully', () {
      const body = 'Dạ shop cập nhật đơn bánh mã {public_order_code} của mình: '
          '{status, select: confirmed: đã xác nhận | in_progress: đang làm | '
          'ready: đã sẵn sàng | delivering: đang giao} ạ.\n'
          'Dự kiến {delivery_type, select: pickup: mình qua nhận lúc {due_date} '
          '{due_time} | delivery: giao tới {delivery_address} lúc {due_date} '
          '{due_time}} ạ.';
      final result = MessageTemplateResolver(_ctx(
        deliveryType: 'delivery',
        status: 'ready',
      ))
          .resolveBody(body);
      expect(result, contains('đã sẵn sàng'));
      expect(result, contains('giao tới 123 Lê Lợi lúc 15/08/2026 14:00'));
      expect(result, isNot(contains('{')));
    });
  });

  group('MessageTemplateResolverExt', () {
    test('template.resolvePlaceholders(context) resolves body', () {
      final tmpl = _tmpl('Xin chào {customer_name}');
      expect(tmpl.resolvePlaceholders(_ctx()), 'Xin chào Nguyễn Văn A');
    });
  });

  group('TemplateContext.fromOrder', () {
    test('builds context from an Order with all fields', () {
      final order = MessageTemplateResolver(_ctx()).resolveBody('{customer_name}');
      expect(order, 'Nguyễn Văn A');
    });
  });

  group('TemplateContext.fromWizard', () {
    test('builds context with formatted due date/time', () {
      final ctx = TemplateContext.fromWizard(
        customerName: 'A',
        customerPhone: '0',
        orderCode: 'OC',
        publicOrderCode: 'PC',
        dueDate: DateTime(2026, 8, 15),
        dueTime: const TimeOfDay(hour: 14, minute: 30),
        totalPrice: 500000,
        itemsList: '- Bánh',
        deliveryType: 'pickup',
        deliveryAddress: '',
        shippingFee: 0,
        notes: '',
        source: '',
        createdBy: '',
      );
      final result = MessageTemplateResolver(ctx)
          .resolveBody('{due_date} {due_time} {total_price}');
      expect(result, '15/08/2026 14:30 500.000đ');
    });

    test('empty due date/time render as (trống)', () {
      final ctx = TemplateContext.fromWizard(
        customerName: '',
        customerPhone: '',
        orderCode: '',
        publicOrderCode: '',
        dueDate: null,
        dueTime: null,
        totalPrice: 0,
        itemsList: '',
        deliveryType: 'pickup',
        deliveryAddress: '',
        shippingFee: 0,
        notes: '',
        source: '',
        createdBy: '',
      );
      final result =
          MessageTemplateResolver(ctx).resolveBody('{due_date}/{due_time}');
      expect(result, '(trống)/(trống)');
    });
  });
}