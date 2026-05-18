import 'package:flutter/material.dart';

/// Поле форми з червоною обводкою та текстом помилки під полем.
class AuthFormField extends StatelessWidget {
  const AuthFormField({
    super.key,
    required this.controller,
    required this.decoration,
    this.errorText,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;

  static const _errorColor = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final radius = BorderRadius.circular(12);
    final normalBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: hasError ? _errorColor : Colors.grey.shade400,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: decoration.copyWith(
            border: normalBorder,
            enabledBorder: normalBorder,
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: hasError ? _errorColor : const Color(0xFF2E7D32),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: const BorderSide(color: _errorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: const BorderSide(color: _errorColor, width: 2),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: _errorColor,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
