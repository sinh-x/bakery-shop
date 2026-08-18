import 'package:flutter/material.dart';

import '../../../shared/labels/auth.dart';

/// Password form field for the login screen, with an obscure-text toggle.
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: AuthLabels.passwordLabel,
        hintText: AuthLabels.passwordHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: onToggleObscure,
        ),
      ),
      textInputAction: TextInputAction.done,
      validator: (value) =>
          (value == null || value.isEmpty) ? AuthLabels.passwordLabel : null,
    );
  }
}