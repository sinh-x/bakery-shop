import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../shared/utils/phone_formatter.dart';
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
    required this.orderStateProvider,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final bool posMode;
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState> orderStateProvider;

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
    final state = ref.read(widget.orderStateProvider);
    _nameCtrl.text = state.wizardData.customerName;
    _phoneCtrl.text = formatPhone(state.wizardData.customerPhone);
    if (state.wizardData.selectedCustomer != null) {
      _customerTouched = true;
    }
    _nameCtrl.addListener(_syncToState);
    _phoneCtrl.addListener(_syncToState);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_syncToState);
    _phoneCtrl.removeListener(_syncToState);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _syncToState() {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    final state = ref.read(widget.orderStateProvider);
    notifier.updateWizardData(
      state.wizardData.copyWith(
        customerName: _nameCtrl.text,
        customerPhone: _phoneCtrl.text,
      ),
    );
  }

  void _onCustomerSelected(Customer? c) {
    _customerTouched = true;
    final notifier = ref.read(widget.orderStateProvider.notifier);
    final state = ref.read(widget.orderStateProvider);
    var updated = state.wizardData.copyWith(
      selectedCustomer: c,
      clearSelectedCustomer: c == null,
    );
    if (c != null) {
      _nameCtrl.text = c.name;
      if (c.phone.isNotEmpty) _phoneCtrl.text = formatPhone(c.phone);
      updated = updated.copyWith(
        customerName: c.name,
        customerPhone: formatPhone(c.phone),
      );
    }
    notifier.updateWizardData(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.orderStateProvider);
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
                  ProductSummaryCard(items: state.items),
                  CustomerSummaryCard(
                    wizardData: state.wizardData,
                    source: state.source,
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

  static const _defaultSources = [
    OrdersLabels.sourceFbDoangia,
    OrdersLabels.sourceFbPageMoi,
    OrdersLabels.sourceZalo,
    OrdersLabels.sourceDienThoai,
    OrdersLabels.sourceTaiTiem,
  ];

  Widget _buildSourceSelector(
    OrderCreateState state,
    AsyncValue<List<String>> sourcesAsync,
  ) {
    final sources = sourcesAsync.maybeWhen(
      data: (list) => list.isNotEmpty ? list : null,
      orElse: () => null,
    ) ??
        _defaultSources;

    final selectedSource =
        state.source.isNotEmpty ? state.source : OrdersLabels.sourceTaiTiem;

    final row1 = sources.where((s) =>
        s == OrdersLabels.sourceFbDoangia ||
        s == OrdersLabels.sourceFbPageMoi).toList();
    final row2 = sources.where((s) =>
        s == OrdersLabels.sourceZalo ||
        s == OrdersLabels.sourceDienThoai ||
        s == OrdersLabels.sourceTaiTiem).toList();

    return Column(
      children: [
        if (row1.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 8,
              children: row1.map((s) => ChoiceChip(
                label: Text(s),
                selected: selectedSource == s,
                onSelected: (_) {
                  ref.read(widget.orderStateProvider.notifier).updateSource(s);
                },
              )).toList(),
            ),
          ),
        if (row2.isNotEmpty)
          Wrap(
            spacing: 8,
            children: row2.map((s) => ChoiceChip(
              label: Text(s),
              selected: selectedSource == s,
              onSelected: (_) {
                ref.read(widget.orderStateProvider.notifier).updateSource(s);
              },
            )).toList(),
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
              final state = ref.read(widget.orderStateProvider);
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
