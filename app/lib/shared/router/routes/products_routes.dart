import 'package:go_router/go_router.dart';

import '../../../features/products/catalog_browse_screen.dart';
import '../../../features/products/product_form_screen.dart';
import '../../../features/products/widgets/catalog_viewer_loader.dart';
import '../../../features/products/widgets/product_edit_loader.dart';

/// Product feature route definitions (DG-308 Phase 4.2 / FR-FL-4).
List<RouteBase> productsRoutes() => [
      GoRoute(
        path: '/products/new',
        builder: (context, state) => ProductFormScreen(
          initialCategory: state.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: '/products/browse',
        builder: (context, state) => const CatalogBrowseScreen(),
      ),
      GoRoute(
        path: '/products/:id/catalog',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final initialPhotoId = state.extra as int?;
          return CatalogViewerLoader(
            productId: id,
            initialPhotoId: initialPhotoId,
          );
        },
      ),
      GoRoute(
        path: '/products/:id/edit',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ProductEditLoader(productId: id);
        },
      ),
    ];