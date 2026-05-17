import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers/fingerprint_provider.dart';
import 'shared/build_fingerprint.dart';
import 'shared/router/app_router.dart';
import 'shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class BakeryApp extends ConsumerWidget {
  const BakeryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisonAsync = ref.watch(fingerprintComparisonProvider);

    return MaterialApp.router(
      title: VN.appName,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: BakeryTheme.light(),
      darkTheme: BakeryTheme.dark(),
      routerConfig: appRouter,
      builder: (context, child) {
        final comparison = comparisonAsync.asData?.value;
        final showWarning =
            comparison?.state == FingerprintComparisonState.mismatch;

        if (!showWarning) {
          return child ?? const SizedBox.shrink();
        }

        return Column(
          children: [
            _FingerprintWarningStrip(comparison: comparison!),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}

class _FingerprintWarningStrip extends StatelessWidget {
  const _FingerprintWarningStrip({required this.comparison});

  final FingerprintComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ColoredBox(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    VN.fingerprintMismatchStrip(
                      shortBuildFingerprint(comparison.clientFingerprint),
                      shortBuildFingerprint(comparison.serverFingerprint),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
