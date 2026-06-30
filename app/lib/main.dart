import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api/api_client.dart';
import 'data/api/config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  // Fetch server timezone config before UI boots so parseApiDateTime uses the
  // server's offset. Failures fall back to the default (+07:00).
  await initServerTimezone(container.read(configServiceProvider));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BakeryApp(),
    ),
  );
}
