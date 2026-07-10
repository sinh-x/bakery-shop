import '../../../data/models/customer.dart';

enum OrderWizardStep { customer, delivery, review }

class OrderWizardData {
  final String customerName;
  final String customerPhone;
  final Customer? selectedCustomer;
  final String deliveryType;
  final String deliveryAddress;
  final String deliveryPhone;
  final double shippingFee;
  final String notes;
  final String source;

  const OrderWizardData({
    this.customerName = '',
    this.customerPhone = '',
    this.selectedCustomer,
    this.deliveryType = 'pickup',
    this.deliveryAddress = '',
    this.deliveryPhone = '',
    this.shippingFee = 0.0,
    this.notes = '',
    this.source = '',
  });

  OrderWizardData copyWith({
    String? customerName,
    String? customerPhone,
    Customer? selectedCustomer,
    bool clearSelectedCustomer = false,
    String? deliveryType,
    String? deliveryAddress,
    String? deliveryPhone,
    double? shippingFee,
    String? notes,
    String? source,
  }) {
    return OrderWizardData(
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      selectedCustomer: clearSelectedCustomer
          ? null
          : selectedCustomer ?? this.selectedCustomer,
      deliveryType: deliveryType ?? this.deliveryType,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryPhone: deliveryPhone ?? this.deliveryPhone,
      shippingFee: shippingFee ?? this.shippingFee,
      notes: notes ?? this.notes,
      source: source ?? this.source,
    );
  }

  bool get needsAddress => deliveryType == 'bus' || deliveryType == 'door';
  bool get needsNotes => deliveryType != 'pickup';
}
