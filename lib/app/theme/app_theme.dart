import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  const AppTheme._();

  // Soft pastel pink seed (#F8BBD0).
  static const _seed = Color(0xFFF8BBD0);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      // Applies Sour Gummy to all 15 TextTheme slots in one call.
      textTheme: GoogleFonts.sourGummyTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: base.colorScheme.surfaceContainer,
        titleTextStyle: GoogleFonts.sourGummy(
          textStyle: base.textTheme.titleLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: GoogleFonts.sourGummy(),
      ),
    );
  }
}
