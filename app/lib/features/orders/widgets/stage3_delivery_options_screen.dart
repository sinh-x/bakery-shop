import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'order_stage_indicator.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage3DeliveryOptionsScreen extends ConsumerStatefulWidget {
  const Stage3DeliveryOptionsScreen({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  ConsumerState<Stage3DeliveryOptionsScreen> createState() =>
      _Stage3DeliveryOptionsScreenState();
}

class _Stage3DeliveryOptionsScreenState
    extends ConsumerState<Stage3DeliveryOptionsScreen> {
  final _addressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(orderCreateStateProvider);
    _addressCtrl.text = state.wizardData.deliveryAddress;
    _deliveryPhoneCtrl.text = state.wizardData.deliveryPhone;
    _notesCtrl.text = state.wizardData.notes;
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncToState() {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final state = ref.read(orderCreateStateProvider);
    final updated = state.wizardData;
    updated.deliveryAddress = _addressCtrl.text;
    updated.deliveryPhone = _deliveryPhoneCtrl.text;
    updated.notes = _notesCtrl.text;
    notifier.updateWizardData(updated);
  }

  void _updateDeliveryType(String type) {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final state = ref.read(orderCreateStateProvider);
    final updated = state.wizardData;
    updated.deliveryType = type;
    switch (type) {
      case 'bus':
        updated.shippingFee = 25000;
        break;
      case 'door':
        updated.shippingFee = 20000;
        break;
      case 'pickup':
      default:
        updated.shippingFee = 0;
        break;
    }
    notifier.updateWizardData(updated);
  }

  void _setShippingFee(double fee) {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final state = ref.read(orderCreateStateProvider);
    final updated = state.wizardData;
    updated.shippingFee = fee;
    notifier.updateWizardData(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderCreateStateProvider);
    final data = state.wizardData;
    final needsAddress = data.needsAddress;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: OrderStageIndicator(currentStage: 3),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  selected: {data.deliveryType},
                  onSelectionChanged: (s) =>
                      _updateDeliveryType(s.first),
                ),
                if (needsAddress) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _deliveryPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: OrdersLabels.deliveryPhone,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => _syncToState(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.deliveryAddress,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _syncToState(),
                  ),
                ],
                if (data.deliveryType == 'bus' ||
                    data.deliveryType == 'door') ...[
                  const SizedBox(height: 20),
                  const SectionHeader(VN.shippingFee),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: data.shippingFee >= 5000
                            ? () =>
                                _setShippingFee(data.shippingFee - 5000.0)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          data.shippingFee == 0
                              ? VN.shippingFree
                              : formatVND(data.shippingFee),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () =>
                            _setShippingFee(data.shippingFee + 5000.0),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
                if (data.needsNotes) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.notes,
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    onChanged: (_) => _syncToState(),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeader(VN.dueDate),
                _buildDatePickerRow(context, state.dueDate, state.dueTime),
              ],
            ),
          ),
        ),
        _buildNavigation(),
      ],
    );
  }

  Widget _buildDatePickerRow(
    BuildContext context,
    DateTime? dueDate,
    TimeOfDay? dueTime,
  ) {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final dateStr = dueDate != null
        ? '${dueDate.day}/${dueDate.month}/${dueDate.year}'
        : 'Chưa chọn';
    final timeStr = dueTime != null
        ? '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}'
        : 'Chưa chọn';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: dueDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                notifier.updateDueDate(picked);
              }
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(dateStr),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final initialTime = dueTime ?? const TimeOfDay(hour: 9, minute: 0);
              final picked = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (picked != null) {
                notifier.updateDueTime(picked);
              }
            },
            icon: const Icon(Icons.access_time, size: 16),
            label: Text(timeStr),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: widget.onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              _syncToState();
              widget.onContinue();
            },
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}
