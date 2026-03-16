import 'package:flutter/material.dart';

import 'shared/router/app_router.dart';
import 'shared/theme/bakery_theme.dart';
import 'shared/widgets/vietnamese_labels.dart';

class BakeryApp extends StatelessWidget {
  const BakeryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: VN.appName,
      theme: BakeryTheme.light(),
      darkTheme: BakeryTheme.dark(),
      routerConfig: appRouter,
    );
  }
}
