import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const controlRadius = BorderRadius.all(Radius.circular(16));
  static const surfaceRadius = BorderRadius.all(Radius.circular(20));

  static ThemeData get light {
    final colors = ColorScheme.fromSeed(seedColor: const Color(0xFFF8BBD0));
    const inputBorder = OutlineInputBorder(borderRadius: controlRadius);
    const controlShape = RoundedRectangleBorder(borderRadius: controlRadius);
    const dialogShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    );
    const buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      shape: WidgetStatePropertyAll(controlShape),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'SourGummy',
      inputDecorationTheme: InputDecorationTheme(
        border: inputBorder,
        enabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.outline),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colors.onSurface.withValues(alpha: 0.38),
          ),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        alignLabelWithHint: true,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(
                color: colors.onSurface.withValues(alpha: 0.38),
              );
            }
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colors.primary, width: 2);
            }
            return BorderSide(color: colors.outline);
          }),
        ),
      ),
      filledButtonTheme: const FilledButtonThemeData(style: buttonStyle),
      textButtonTheme: const TextButtonThemeData(style: buttonStyle),
      chipTheme: const ChipThemeData(shape: controlShape),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: controlShape,
      ),
      dialogTheme: const DialogThemeData(shape: dialogShape),
      timePickerTheme: const TimePickerThemeData(shape: dialogShape),
    );
  }
}
