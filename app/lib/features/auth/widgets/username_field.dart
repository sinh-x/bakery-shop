import 'package:flutter/material.dart';

import '../../../shared/labels/auth.dart';

/// Username form field for the login screen.
class UsernameField extends StatelessWidget {
  const UsernameField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: AuthLabels.usernameLabel,
        hintText: AuthLabels.usernameHint,
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person_outline),
      ),
      textInputAction: TextInputAction.next,
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? AuthLabels.usernameLabel : null,
    );
  }
}