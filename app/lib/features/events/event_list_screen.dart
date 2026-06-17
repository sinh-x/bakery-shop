import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/shared/labels/events.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/event_history_list.dart';

/// Full-screen events tab: scrollable history with filter bar + FAB to log new event.
class EventListScreen extends StatelessWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.tabEvents),
        actions: const [AppBarOverflowMenu()],
      ),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: EventHistoryList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/events/new'),
        tooltip: VN.createEvent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
