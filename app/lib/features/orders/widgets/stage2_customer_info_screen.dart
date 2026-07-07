import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../shared/utils/phone_formatter.dart';
import '../../customers/widgets/customer_profile_card.dart';
import '../../customers/widgets/customer_search_field.dart';
import 'section_header.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

const _sourceOptions = [
  'Tại tiệm',
  'Online',
  'Điện thoại',
];

class Stage2CustomerInfoScreen extends ConsumerStatefulWidget {
  const Stage2CustomerInfoScreen({
    super.key,
    required this.onBack,
    required this.onContinue,
    this.posMode = false,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final bool posMode;

  @override
  ConsumerState<Stage2CustomerInfoScreen> createState() =>
      _Stage2CustomerInfoScreenState();
}

class _Stage2CustomerInfoScreenState
    extends ConsumerState<Stage2CustomerInfoScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(orderCreateStateProvider);
    _nameCtrl.text = state.wizardData.customerName;
    _phoneCtrl.text = state.wizardData.customerPhone;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _syncToState() {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final state = ref.read(orderCreateStateProvider);
    notifier.updateWizardData(
      state.wizardData.copyWith(
        customerName: _nameCtrl.text,
        customerPhone: _phoneCtrl.text,
      ),
    );
  }

  void _onCustomerSelected(Customer? c) {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final state = ref.read(orderCreateStateProvider);
    var updated = state.wizardData.copyWith(
      selectedCustomer: c,
      clearSelectedCustomer: c == null,
    );
    if (c != null) {
      _nameCtrl.text = c.name;
      if (c.phone.isNotEmpty) _phoneCtrl.text = c.phone;
      updated = updated.copyWith(
        customerName: c.name,
        customerPhone: c.phone,
      );
    }
    notifier.updateWizardData(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderCreateStateProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(VN.customer),
                CustomerSearchField(
                  controller: _nameCtrl,
                  onSelected: _onCustomerSelected,
                  clearOnFocus: widget.posMode,
                ),
                if (state.wizardData.selectedCustomer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CustomerProfileCard(
                      customer: state.wizardData.selectedCustomer!,
                      mode: CustomerProfileCardMode.compact,
                    ),
                  ),
                if (state.wizardData.selectedCustomer == null) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.customerPhone,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneInputFormatter()],
                    onChanged: (_) => _syncToState(),
                  ),
                ],
                if (!widget.posMode) ...[
                  const SizedBox(height: 20),
                  const SectionHeader(VN.orderSource),
                  SegmentedButton<String>(
                    segments: _sourceOptions
                        .map((s) => ButtonSegment<String>(
                              value: s,
                              label: Text(s),
                            ))
                        .toList(),
                    selected: {state.source.isNotEmpty ? state.source : 'Tại tiệm'},
                    onSelectionChanged: (s) {
                      ref
                          .read(orderCreateStateProvider.notifier)
                          .updateSource(s.first);
                    },
                  ),
                ],
                StageSummaryCard(
                  items: state.items,
                  wizardData: state.wizardData,
                  source: state.source,
                  showProducts: true,
                ),
              ],
            ),
          ),
        ),
        _buildNavigation(),
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
