import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/order/order_create_state_provider.dart';
import 'order_customer_section.dart';
import 'section_header.dart';
import 'stage1_responsive_content.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

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
  bool _customerTouched = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(orderCreateStateProvider);
    _nameCtrl.text = state.wizardData.customerName;
    _phoneCtrl.text = state.wizardData.customerPhone;
    if (state.wizardData.selectedCustomer != null) {
      _customerTouched = true;
    }
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
    _customerTouched = true;
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
    final sourcesAsync = ref.watch(orderSourcesProvider);

    return Column(
      children: [
        Expanded(
          child: Stage1ResponsiveContent(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(VN.customer),
                  OrderCustomerSection(
                    selectedCustomer: state.wizardData.selectedCustomer,
                    customerTouched: _customerTouched,
                    onSelected: _onCustomerSelected,
                    onClearSelection: () {
                      _customerTouched = true;
                      _onCustomerSelected(null);
                    },
                    nameCtrl: _nameCtrl,
                    phoneCtrl: _phoneCtrl,
                  ),
                  if (!widget.posMode) ...[
                    const SizedBox(height: 20),
                    const SectionHeader(VN.orderSource),
                    const SizedBox(height: 8),
                    _buildSourceSelector(state, sourcesAsync),
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
        ),
        _buildNavigation(),
      ],
    );
  }

  Widget _buildSourceSelector(
    OrderCreateState state,
    AsyncValue<List<String>> sourcesAsync,
  ) {
    final sources = sourcesAsync.maybeWhen(
      data: (list) => list.isNotEmpty ? list : null,
      orElse: () => null,
    ) ??
        const [
          OrdersLabels.sourceTaiTiem,
          OrdersLabels.sourceOnline,
          OrdersLabels.sourceDienThoai,
        ];

    return SegmentedButton<String>(
      segments: sources
          .map((s) => ButtonSegment<String>(
                value: s,
                label: Text(s),
              ))
          .toList(),
      selected: {
        state.source.isNotEmpty ? state.source : OrdersLabels.sourceTaiTiem,
      },
      onSelectionChanged: (s) {
        ref.read(orderCreateStateProvider.notifier).updateSource(s.first);
      },
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
              final state = ref.read(orderCreateStateProvider);
              if (state.wizardData.customerName.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(OrdersLabels.validationCustomerNameRequired)),
                );
                return;
              }
              widget.onContinue();
            },
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}
