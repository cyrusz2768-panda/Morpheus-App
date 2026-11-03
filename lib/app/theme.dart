import 'package:flutter/material.dart';

/// Builds the visual language used throughout the application.
///
/// Keeping theme values here avoids hard-coded colors and font sizes inside
/// feature pages. A later design pass can change the whole application without
/// rewriting the dream editor.
ThemeData buildAppTheme() {
  const seedColor = Color(0xFF4D4A8A);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF7F6FB),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
      alignLabelWithHint: true,
    ),
  );
}
