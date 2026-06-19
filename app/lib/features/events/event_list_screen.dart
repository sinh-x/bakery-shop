import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/shared/labels/events.dart';
import '../../providers/events_provider.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/event_history_list.dart';

/// Full-screen events tab: scrollable history with filter bar + FAB to log new event.
class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  @override
  String screenRoutePath() => '/events';

  @override
  void invalidateProviders() {
    ref.invalidate(eventsProvider);
  }

  @override
  void initState() {
    super.initState();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    super.dispose();
  }

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