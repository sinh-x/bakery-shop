import 'package:flutter/material.dart';

import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/event_history_list.dart';
import 'widgets/event_log_form.dart';

/// Events tab screen: quick-log form on top, scrollable event history below.
class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.tabEvents)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: const EventLogForm(),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const EventHistoryList(),
            ),
          ),
        ],
      ),
    );
  }
}
