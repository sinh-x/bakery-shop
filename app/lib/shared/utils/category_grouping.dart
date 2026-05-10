import '../../data/models/category.dart';

typedef CategoryKeySelector<T> = String Function(T item);
typedef ItemLabelSelector<T> = String Function(T item);

class GroupedCategorySection<T> {
  const GroupedCategorySection({
    required this.categoryKey,
    required this.categoryName,
    required this.items,
    required this.categoryPosition,
  });

  final String categoryKey;
  final String categoryName;
  final List<T> items;
  final int categoryPosition;
}

List<GroupedCategorySection<T>> groupItemsByCategory<T>({
  required List<T> items,
  required List<Category> categories,
  required CategoryKeySelector<T> categoryKeyOf,
  required ItemLabelSelector<T> itemLabelOf,
}) {
  final categoryBySlug = <String, Category>{
    for (final category in categories) category.slug: category,
  };

  final buckets = <String, List<T>>{};
  for (final item in items) {
    final key = categoryKeyOf(item).trim();
    buckets.putIfAbsent(key, () => <T>[]).add(item);
  }

  final sections = buckets.entries.map((entry) {
    final key = entry.key;
    final bucketItems = [...entry.value]
      ..sort((a, b) => itemLabelOf(a).compareTo(itemLabelOf(b)));
    final category = categoryBySlug[key];
    return GroupedCategorySection<T>(
      categoryKey: key,
      categoryName: category?.name ?? key,
      categoryPosition: category?.position ?? 0,
      items: bucketItems,
    );
  }).toList();

  sections.sort((a, b) {
    final hasOrderA = a.categoryPosition > 0;
    final hasOrderB = b.categoryPosition > 0;
    if (hasOrderA && hasOrderB && a.categoryPosition != b.categoryPosition) {
      return a.categoryPosition.compareTo(b.categoryPosition);
    }
    if (hasOrderA != hasOrderB) {
      return hasOrderA ? -1 : 1;
    }
    final byName = a.categoryName.compareTo(b.categoryName);
    if (byName != 0) return byName;
    return a.categoryKey.compareTo(b.categoryKey);
  });

  return sections;
}

List<GroupedCategorySection<T>> filterGroupedSections<T>({
  required List<GroupedCategorySection<T>> sections,
  required bool Function(T item) matches,
}) {
  final filtered = <GroupedCategorySection<T>>[];
  for (final section in sections) {
    final matchingItems = section.items.where(matches).toList();
    if (matchingItems.isEmpty) {
      continue;
    }
    filtered.add(
      GroupedCategorySection<T>(
        categoryKey: section.categoryKey,
        categoryName: section.categoryName,
        categoryPosition: section.categoryPosition,
        items: matchingItems,
      ),
    );
  }
  return filtered;
}
