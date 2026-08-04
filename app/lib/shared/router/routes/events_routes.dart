import 'package:go_router/go_router.dart';

import '../../../data/models/event.dart';
import '../../../features/events/event_detail_screen.dart';
import '../../../features/events/event_form_screen.dart';

/// Event feature route definitions (DG-308 Phase 4.2 / FR-FL-4).
List<RouteBase> eventsRoutes() => [
      GoRoute(
        path: '/events/new',
        builder: (context, state) => const EventFormScreen(),
      ),
      GoRoute(
        path: '/events/:id',
        builder: (context, state) {
          final event = state.extra as BakeryEvent;
          return EventDetailScreen(event: event);
        },
      ),
      GoRoute(
        path: '/events/:id/edit',
        builder: (context, state) {
          final event = state.extra as BakeryEvent;
          return EventFormScreen(event: event);
        },
      ),
    ];