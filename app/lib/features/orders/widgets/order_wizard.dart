import 'package:flutter/material.dart';

import '../../../data/models/customer.dart';
import '../../../features/customers/widgets/customer_profile_card.dart';
import '../../../features/customers/widgets/customer_search_field.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/phone_formatter.dart';
import 'section_header.dart';

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

class OrderWizard extends StatefulWidget {
  const OrderWizard({
    super.key,
    required this.data,
    required this.onDataChanged,
    required this.onFinalize,
    this.showCustomerStep = true,
    this.showDeliveryStep = true,
    this.showReviewStep = true,
    this.skipCustomerIfWalkIn = false,
    this.skipDeliveryIfPickup = true,
    this.shippingBusDefault = 25000,
    this.shippingDoorDefault = 20000,
    this.reviewTitle = 'Xem lại đơn hàng',
    this.reviewHint = 'Kiểm tra thông tin trước khi tạo đơn.',
    this.finalizeLabel = 'TẠO ĐƠN HÀNG',
    this.isProcessing = false,
    this.extraReviewWidgets,
    this.onCustomerSelected,
  });

  final OrderWizardData data;
  final VoidCallback onDataChanged;
  final VoidCallback onFinalize;
  final bool showCustomerStep;
  final bool showDeliveryStep;
  final bool showReviewStep;
  final bool skipCustomerIfWalkIn;
  final bool skipDeliveryIfPickup;
  final double shippingBusDefault;
  final double shippingDoorDefault;
  final String reviewTitle;
  final String reviewHint;
  final String finalizeLabel;
  final bool isProcessing;
  final List<Widget>? extraReviewWidgets;
  final ValueChanged<Customer?>? onCustomerSelected;

  @override
  State<OrderWizard> createState() => _OrderWizardState();
}

class _OrderWizardState extends State<OrderWizard> {
  late OrderWizardStep _currentStep;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  OrderWizardData get _data => widget.data;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _data.customerName;
    _phoneCtrl.text = _data.customerPhone;
    _addressCtrl.text = _data.deliveryAddress;
    _notesCtrl.text = _data.notes;
    _currentStep = _resolveInitialStep();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  OrderWizardStep _resolveInitialStep() {
    if (widget.showCustomerStep) return OrderWizardStep.customer;
    if (widget.showDeliveryStep) return OrderWizardStep.delivery;
    return OrderWizardStep.review;
  }

  void _syncToData() {
    _data.customerName = _nameCtrl.text;
    _data.customerPhone = _phoneCtrl.text;
    _data.deliveryAddress = _addressCtrl.text;
    _data.notes = _notesCtrl.text;
    widget.onDataChanged();
  }

  void _goNext() {
    _syncToData();
    final next = _nextStep(_currentStep);
    if (next != null) {
      setState(() => _currentStep = next);
    }
  }

  void _goBack() {
    final prev = _prevStep(_currentStep);
    if (prev != null) {
      setState(() => _currentStep = prev);
    }
  }

  OrderWizardStep? _nextStep(OrderWizardStep current) {
    switch (current) {
      case OrderWizardStep.customer:
        if (widget.showDeliveryStep) {
          if (widget.skipDeliveryIfPickup && _data.deliveryType == 'pickup') {
            return widget.showReviewStep ? OrderWizardStep.review : null;
          }
          return OrderWizardStep.delivery;
        }
        return widget.showReviewStep ? OrderWizardStep.review : null;
      case OrderWizardStep.delivery:
        return widget.showReviewStep ? OrderWizardStep.review : null;
      case OrderWizardStep.review:
        return null;
    }
  }

  OrderWizardStep? _prevStep(OrderWizardStep current) {
    switch (current) {
      case OrderWizardStep.customer:
        return null;
      case OrderWizardStep.delivery:
        return widget.showCustomerStep ? OrderWizardStep.customer : null;
      case OrderWizardStep.review:
        if (widget.showDeliveryStep &&
            !(widget.skipDeliveryIfPickup && _data.deliveryType == 'pickup')) {
          return OrderWizardStep.delivery;
        }
        return widget.showCustomerStep ? OrderWizardStep.customer : null;
    }
  }

  void _updateDeliveryType(String type) {
    setState(() {
      _data.deliveryType = type;
      switch (type) {
        case 'bus':
          _data.shippingFee = widget.shippingBusDefault;
          break;
        case 'door':
          _data.shippingFee = widget.shippingDoorDefault;
          break;
        case 'pickup':
        default:
          _data.shippingFee = 0;
          break;
      }
    });
    widget.onDataChanged();
  }

  void _setShippingFee(double fee) {
    setState(() => _data.shippingFee = fee);
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepIndicator(),
        const SizedBox(height: 16),
        Expanded(child: _buildCurrentStep()),
        _buildNavigation(),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final steps = <OrderWizardStep>[];
    if (widget.showCustomerStep) steps.add(OrderWizardStep.customer);
    if (widget.showDeliveryStep) steps.add(OrderWizardStep.delivery);
    if (widget.showReviewStep) steps.add(OrderWizardStep.review);

    if (steps.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) Expanded(child: Container(height: 2, color: _stepColor(steps[i]))),
            _stepDot(steps[i]),
          ],
        ],
      ),
    );
  }

  Color _stepColor(OrderWizardStep step) {
    final steps = <OrderWizardStep>[];
    if (widget.showCustomerStep) steps.add(OrderWizardStep.customer);
    if (widget.showDeliveryStep) steps.add(OrderWizardStep.delivery);
    if (widget.showReviewStep) steps.add(OrderWizardStep.review);

    final currentIdx = steps.indexOf(_currentStep);
    final stepIdx = steps.indexOf(step);
    if (stepIdx <= currentIdx) return Theme.of(context).colorScheme.primary;
    return Colors.grey.shade300;
  }

  Widget _stepDot(OrderWizardStep step) {
    final isCurrent = step == _currentStep;
    final isPast = _isStepBefore(step, _currentStep);
    final color = isCurrent || isPast
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade300;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent ? color : (isPast ? color.withValues(alpha: 0.3) : Colors.transparent),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: isPast
            ? Icon(Icons.check, size: 16, color: color)
            : Text(
                _stepLabel(step),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? Theme.of(context).colorScheme.onPrimary : color,
                ),
              ),
      ),
    );
  }

  bool _isStepBefore(OrderWizardStep a, OrderWizardStep b) {
    const order = [OrderWizardStep.customer, OrderWizardStep.delivery, OrderWizardStep.review];
    return order.indexOf(a) < order.indexOf(b);
  }

  String _stepLabel(OrderWizardStep step) {
    switch (step) {
      case OrderWizardStep.customer:
        return '1';
      case OrderWizardStep.delivery:
        return '2';
      case OrderWizardStep.review:
        return '3';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case OrderWizardStep.customer:
        return _buildCustomerStep();
      case OrderWizardStep.delivery:
        return _buildDeliveryStep();
      case OrderWizardStep.review:
        return _buildReviewStep();
    }
  }

  Widget _buildCustomerStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(VN.customer),
          CustomerSearchField(
            controller: _nameCtrl,
            onSelected: (c) {
              setState(() {
                _data.selectedCustomer = c;
                if (c != null) {
                  _nameCtrl.text = c.name;
                  if (c.phone.isNotEmpty) _phoneCtrl.text = c.phone;
                }
              });
              widget.onCustomerSelected?.call(c);
              widget.onDataChanged();
            },
          ),
          if (_data.selectedCustomer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CustomerProfileCard(
                customer: _data.selectedCustomer!,
                mode: CustomerProfileCardMode.compact,
              ),
            ),
          if (_data.selectedCustomer == null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: VN.customerPhone,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
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
            selected: {_data.deliveryType},
            onSelectionChanged: (s) => _updateDeliveryType(s.first),
          ),
          if (_data.needsAddress) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: VN.customerPhone,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: VN.deliveryAddress,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_data.deliveryType == 'bus' || _data.deliveryType == 'door') ...[
            const SizedBox(height: 20),
            const SectionHeader(VN.shippingFee),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: _data.shippingFee >= 5000
                      ? () => _setShippingFee(_data.shippingFee - 5000.0)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _data.shippingFee == 0
                        ? VN.shippingFree
                        : formatVND(_data.shippingFee),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton.filled(
                  onPressed: () => _setShippingFee(_data.shippingFee + 5000.0),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
          if (_data.needsNotes) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.notes,
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.reviewTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.reviewHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.showCustomerStep) ...[
            const SectionHeader(VN.customer),
            _buildReviewRow(VN.customerName, _data.customerName),
            if (_data.customerPhone.isNotEmpty)
              _buildReviewRow(VN.customerPhone, _data.customerPhone),
            const SizedBox(height: 16),
          ],
          if (widget.showDeliveryStep) ...[
            const SectionHeader(VN.deliveryType),
            _buildReviewRow(VN.deliveryType, _deliveryTypeLabel(_data.deliveryType)),
            if (_data.needsAddress) ...[
              if (_data.customerPhone.isNotEmpty)
                _buildReviewRow(VN.customerPhone, _data.customerPhone),
              if (_data.deliveryAddress.isNotEmpty)
                _buildReviewRow(VN.deliveryAddress, _data.deliveryAddress),
            ],
            if (_data.shippingFee > 0)
              _buildReviewRow(VN.shippingFee, formatVND(_data.shippingFee)),
            if (_data.notes.isNotEmpty)
              _buildReviewRow(VN.notes, _data.notes),
            const SizedBox(height: 16),
          ],
          if (widget.extraReviewWidgets != null) ...widget.extraReviewWidgets!,
        ],
      ),
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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

  Widget _buildNavigation() {
    final hasPrev = _prevStep(_currentStep) != null;
    final hasNext = _nextStep(_currentStep) != null;
    final isReview = _currentStep == OrderWizardStep.review;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (hasPrev)
            OutlinedButton(
              onPressed: _goBack,
              child: const Text('Quay lại'),
            )
          else
            const SizedBox.shrink(),
          const Spacer(),
          if (isReview)
            FilledButton(
              onPressed: widget.isProcessing ? null : widget.onFinalize,
              child: widget.isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.finalizeLabel),
            )
          else if (hasNext)
            FilledButton(
              onPressed: _goNext,
              child: const Text('Tiếp tục'),
            ),
        ],
      ),
    );
  }
}
