import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order_draft.dart';
import '../../features/orders/widgets/order_wizard.dart';

class OrderCreateState {
  final List<DraftOrderItem> items;
  final OrderWizardData wizardData;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final String source;
  final int currentStage;
  final String? selectedCategorySlug;

  const OrderCreateState({
    this.items = const [],
    required this.wizardData,
    this.dueDate,
    this.dueTime,
    this.source = '',
    this.currentStage = 1,
    this.selectedCategorySlug,
  });

  OrderCreateState copyWith({
    List<DraftOrderItem>? items,
    OrderWizardData? wizardData,
    DateTime? dueDate,
    TimeOfDay? dueTime,
    String? source,
    int? currentStage,
    String? selectedCategorySlug,
    bool clearSelectedCategorySlug = false,
  }) {
    return OrderCreateState(
      items: items ?? this.items,
      wizardData: wizardData ?? this.wizardData,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      source: source ?? this.source,
      currentStage: currentStage ?? this.currentStage,
      selectedCategorySlug: clearSelectedCategorySlug
          ? null
          : selectedCategorySlug ?? this.selectedCategorySlug,
    );
  }
}

class OrderCreateStateNotifier extends Notifier<OrderCreateState> {
  @override
  OrderCreateState build() =>
      const OrderCreateState(wizardData: OrderWizardData());

  void updateItems(List<DraftOrderItem> items) {
    state = state.copyWith(items: items);
  }

  void updateWizardData(OrderWizardData wizardData) {
    state = state.copyWith(wizardData: wizardData);
  }

  void updateDueDate(DateTime? dueDate) {
    state = state.copyWith(dueDate: dueDate);
  }

  void updateDueTime(TimeOfDay? dueTime) {
    state = state.copyWith(dueTime: dueTime);
  }

  void updateSource(String source) {
    state = state.copyWith(source: source);
  }

  void goToStage(int stage) {
    state = state.copyWith(currentStage: stage);
  }

  void updateSelectedCategorySlug(String? slug) {
    state = slug == null
        ? state.copyWith(clearSelectedCategorySlug: true)
        : state.copyWith(selectedCategorySlug: slug);
  }

  void reset() {
    state = const OrderCreateState(wizardData: OrderWizardData());
  }
}

final orderCreateStateProvider =
    NotifierProvider<OrderCreateStateNotifier, OrderCreateState>(
  OrderCreateStateNotifier.new,
);
