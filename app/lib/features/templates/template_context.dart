import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/vietnamese_labels.dart' show formatVND;
import '../../shared/utils/order_helpers.dart' show deliveryTypeLabel;

/// Resolved placeholder values for a message template (DG-375 Phase 4.3 / FR4).
///
/// Holds the string representation of every order field that a template body
/// may reference. Built from an [Order] (order detail / edit wizard) or from
/// the order create wizard's in-progress state (no `Order` exists yet — see
/// [TemplateContext.fromWizard]).
///
/// The [resolvePlaceholders] method on [MessageTemplateResolver] consumes a
/// [TemplateContext] to produce the final filled template text. Empty fields
/// render as `(trống)` per the requirements doc §11 Risk mitigation.
///
/// [deliveryType] stores the *raw* delivery-type slug (`pickup` / `delivery`
/// / `bus` / `door`). The `valueFor('delivery_type')` simple substitution
/// maps it to the Vietnamese display label; `rawValueFor('delivery_type')`
/// returns the canonical slug (`pickup` / `delivery`) used by
/// `{field, select: ...}` branches so the seeded templates' `pickup` vs
/// `delivery` branches match for all delivery orders.
@immutable
class TemplateContext {
  const TemplateContext({
    required this.customerName,
    required this.customerPhone,
    required this.orderCode,
    required this.publicOrderCode,
    required this.dueDate,
    required this.dueTime,
    required this.totalPrice,
    required this.itemsList,
    required this.deliveryType,
    required this.deliveryAddress,
    required this.shippingFee,
    required this.notes,
    required this.source,
    required this.createdBy,
    this.status = '',
  });

  /// Build a [TemplateContext] from a saved [Order] (order detail / edit).
  factory TemplateContext.fromOrder(Order order) {
    return TemplateContext(
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      orderCode: order.orderRef,
      publicOrderCode: order.publicOrderCode,
      dueDate: _formatDueDate(order.dueDate),
      dueTime: order.dueTime ?? '',
      totalPrice: formatVND(order.totalPrice),
      itemsList: _formatItemsList(order.items),
      deliveryType: order.deliveryType,
      deliveryAddress: order.deliveryAddress,
      shippingFee: formatVND(order.shippingFee),
      notes: order.notes,
      source: order.source,
      createdBy: order.displayCreatedBy,
      status: order.status,
    );
  }

  /// Build a [TemplateContext] from the order create / edit wizard's
  /// in-progress state. The wizard has not produced an `Order` yet, so the
  /// caller supplies the raw fields directly.
  ///
  /// [itemsList] is pre-formatted by the caller (e.g. from `DraftOrderItem`s).
  /// [status] is empty for the create wizard (no status yet).
  factory TemplateContext.fromWizard({
    required String customerName,
    required String customerPhone,
    required String orderCode,
    required String publicOrderCode,
    required DateTime? dueDate,
    required TimeOfDay? dueTime,
    required double totalPrice,
    required String itemsList,
    required String deliveryType,
    required String deliveryAddress,
    required double shippingFee,
    required String notes,
    required String source,
    required String createdBy,
    String status = '',
  }) {
    return TemplateContext(
      customerName: customerName,
      customerPhone: customerPhone,
      orderCode: orderCode,
      publicOrderCode: publicOrderCode,
      dueDate: dueDate != null ? formatDisplayDate(dueDate) : '',
      dueTime: dueTime != null ? formatHourMinute(dueTime.hour, dueTime.minute) : '',
      totalPrice: formatVND(totalPrice),
      itemsList: itemsList,
      deliveryType: deliveryType,
      deliveryAddress: deliveryAddress,
      shippingFee: formatVND(shippingFee),
      notes: notes,
      source: source,
      createdBy: createdBy,
      status: status,
    );
  }

  final String customerName;
  final String customerPhone;
  final String orderCode;
  final String publicOrderCode;
  final String dueDate;
  final String dueTime;
  final String totalPrice;
  final String itemsList;
  final String deliveryType;
  final String deliveryAddress;
  final String shippingFee;
  final String notes;
  final String source;
  final String createdBy;
  final String status;

  /// Returns the resolved value for a simple placeholder name (without
  /// braces), or the empty string when the field is unknown.
  ///
  /// `delivery_type` maps the raw slug to the Vietnamese display label for
  /// plain ``{delivery_type}`` substitution. Select branches use
  /// [rawValueFor] to match against the canonical slug.
  String valueFor(String field) {
    switch (field) {
      case 'customer_name':
        return customerName;
      case 'customer_phone':
        return customerPhone;
      case 'order_code':
        return orderCode;
      case 'public_order_code':
        return publicOrderCode;
      case 'due_date':
        return dueDate;
      case 'due_time':
        return dueTime;
      case 'total_price':
        return totalPrice;
      case 'items_list':
        return itemsList;
      case 'delivery_type':
        return deliveryTypeLabel(deliveryType);
      case 'delivery_address':
        return deliveryAddress;
      case 'shipping_fee':
        return shippingFee;
      case 'notes':
        return notes;
      case 'source':
        return source;
      case 'created_by':
        return createdBy;
      case 'status':
        return status;
      default:
        return '';
    }
  }

  /// Returns the raw slug for select-style placeholders. `delivery_type` maps
  /// to the canonical slug used in template bodies (`pickup` / `delivery`).
  /// `bus` and `door` are normalized to `delivery` for select matching so the
  /// default templates' `pickup` vs `delivery` branches work for all delivery
  /// orders.
  String rawValueFor(String field) {
    if (field == 'delivery_type') {
      if (deliveryType == 'pickup') return 'pickup';
      return 'delivery';
    }
    return valueFor(field);
  }

  /// Formats a backend date-only string (`yyyy-MM-dd`) as `dd/MM/yyyy` for
  /// template display. Returns the input unchanged when it cannot be parsed,
  /// or the empty string when null/empty.
  static String _formatDueDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = parseApiDate(raw);
    if (parsed == null) return raw;
    return formatDisplayDate(parsed);
  }

  static String _formatItemsList(List<OrderItem> items) {
    if (items.isEmpty) return '';
    final lines = <String>[];
    for (final item in items) {
      final qty = item.quantity > 1 ? ' x${item.quantity}' : '';
      lines.add('- ${item.productName}$qty');
    }
    return lines.join('\n');
  }
}