import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Shared helper to get the display label for a tag category.
String getCategoryLabel(String category) {
  switch (category) {
    case VN.tagCategoriesDoiTuong:
      return VN.doiTuong;
    case VN.tagCategoriesDip:
      return VN.dip;
    case VN.tagCategoriesPhongCach:
      return VN.phongCach;
    default:
      return category;
  }
}
