import 'package:freezed_annotation/freezed_annotation.dart';

part 'staff.freezed.dart';
part 'staff.g.dart';

@freezed
sealed class Staff with _$Staff {
  const factory Staff({
    required String id,
    required String name,
    @Default('') String role,
    @Default('') String phone,
    @Default(true) bool active,
  }) = _Staff;

  factory Staff.fromJson(Map<String, dynamic> json) => _$StaffFromJson(json);
}
