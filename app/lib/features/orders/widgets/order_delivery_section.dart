import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';
import 'section_header.dart';

class OrderDeliverySection extends StatelessWidget {
  const OrderDeliverySection({
    super.key,
    required this.deliveryType,
    this.deliveryAddress,
    this.customerPhone,
    this.shippingFee,
    this.notes,
    this.mode = OrderDeliverySectionMode.readOnly,
    this.onDeliveryTypeChanged,
    this.onShippingFeeChanged,
    this.addressCtrl,
    this.phoneCtrl,
    this.notesCtrl,
    this.shippingBusDefault = 25000,
    this.shippingDoorDefault = 20000,
  });

  final String deliveryType;
  final String? deliveryAddress;
  final String? customerPhone;
  final double? shippingFee;
  final String? notes;
  final OrderDeliverySectionMode mode;
  final ValueChanged<String>? onDeliveryTypeChanged;
  final ValueChanged<double>? onShippingFeeChanged;
  final TextEditingController? addressCtrl;
  final TextEditingController? phoneCtrl;
  final TextEditingController? notesCtrl;
  final double shippingBusDefault;
  final double shippingDoorDefault;

  bool get _needsAddress => deliveryType == 'bus' || deliveryType == 'door';

  @override
  Widget build(BuildContext context) {
    if (mode == OrderDeliverySectionMode.readOnly) {
      return _buildReadOnly(context);
    }
    return _buildEditable(context);
  }

  Widget _buildReadOnly(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(context, Icons.local_shipping_outlined, VN.deliveryType, _deliveryTypeLabel(deliveryType)),
        if (_needsAddress) ...[
          if (customerPhone != null && customerPhone!.isNotEmpty)
            _buildInfoRow(context, Icons.phone_outlined, VN.customerPhone, customerPhone!),
          if (deliveryAddress != null && deliveryAddress!.isNotEmpty)
            _buildInfoRow(context, Icons.location_on_outlined, VN.deliveryAddress, deliveryAddress!),
        ],
        if (shippingFee != null && shippingFee! > 0)
          _buildInfoRow(context, Icons.monetization_on_outlined, VN.shippingFee, formatVND(shippingFee!)),
        if (notes != null && notes!.isNotEmpty)
          _buildInfoRow(context, Icons.notes, VN.notes, notes!),
      ],
    );
  }

  Widget _buildEditable(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.deliveryType),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'pickup',
              label: Text(VN.pickup),
              icon: Icon(Icons.store, size: 16),
            ),
            ButtonSegment(
              value: 'bus',
              label: Text(VN.deliveryBus),
              icon: Icon(Icons.directions_bus, size: 16),
            ),
            ButtonSegment(
              value: 'door',
              label: Text(VN.deliveryDoor),
              icon: Icon(Icons.home, size: 16),
            ),
          ],
          selected: {deliveryType},
          onSelectionChanged: (s) => onDeliveryTypeChanged?.call(s.first),
        ),
        if (_needsAddress && addressCtrl != null) ...[
          const SizedBox(height: 12),
          if (phoneCtrl != null) ...[
            TextFormField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: VN.customerPhone,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: VN.deliveryAddress,
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                _needsAddress && (v == null || v.trim().isEmpty)
                ? VN.fieldRequired
                : null,
          ),
        ],
        if ((deliveryType == 'bus' || deliveryType == 'door') && onShippingFeeChanged != null) ...[
          const SizedBox(height: 20),
          const SectionHeader(VN.shippingFee),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                onPressed: (shippingFee ?? 0) >= 5000
                    ? () => onShippingFeeChanged!((shippingFee ?? 0) - 5000.0)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  (shippingFee ?? 0) == 0
                      ? VN.shippingFree
                      : formatVND(shippingFee!),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filled(
                onPressed: () => onShippingFeeChanged!((shippingFee ?? 0) + 5000.0),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
        if (notesCtrl != null) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: notesCtrl,
            decoration: const InputDecoration(
              labelText: VN.notes,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  String _deliveryTypeLabel(String type) {
    switch (type) {
      case 'bus':
        return VN.deliveryBus;
      case 'door':
        return VN.deliveryDoor;
      case 'pickup':
      default:
        return VN.pickup;
    }
  }
}

enum OrderDeliverySectionMode { editable, readOnly }
