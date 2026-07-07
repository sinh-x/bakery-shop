import '../../../data/models/customer.dart';

enum OrderWizardStep { customer, delivery, review }

class OrderWizardData {
  String customerName;
  String customerPhone;
  Customer? selectedCustomer;
  String deliveryType;
  String deliveryAddress;
  String deliveryPhone;
  double shippingFee;
  String notes;
  String source;

  OrderWizardData({
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

  bool get needsAddress => deliveryType == 'bus' || deliveryType == 'door';
  bool get needsNotes => deliveryType != 'pickup';
}
