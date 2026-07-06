import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api/api_client.dart';
import 'data/api/config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Configure the server timezone before runApp so every formatDisplay*
  // helper uses the server's timezone offset from the first frame (DG-202 AC6).
  await initServerTimezone();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const BakeryApp(),
    ),
  );
}
