import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/events.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/event_history_list.dart';
import 'widgets/event_log_form.dart';

/// Events tab screen: quick-log form on top, scrollable event history below.
class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  // ignore: prefer_const_constructors
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.tabEvents),
        actions: const [AppBarOverflowMenu()],
      ),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: EventLogForm(),
          ),
          Divider(height: 1),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: EventHistoryList(),
            ),
          ),
        ],
      ),
    );
  }
}
