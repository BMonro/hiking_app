import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Кольори застосунку Hikora.
abstract final class AppColors {
  /// Фон основних екранів (світло-сірий).
  static const scaffold = Color(0xFFF3F5F2);

  /// Альтернативний фон (головна, досягнення).
  static const scaffoldWarm = Color(0xFFFAFAF7);

  /// Верхня шапка — біла, щоб відділялась від контенту.
  static const toolbar = Color(0xFFFFFFFF);

  static const toolbarBorder = Color(0xFFD8E0D8);
}

class AppTheme {
  static final lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffold,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.light,
      surface: AppColors.toolbar,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Color(0x14000000),
      backgroundColor: AppColors.toolbar,
      foregroundColor: Color(0xFF1C241C),
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1C241C),
      ),
      iconTheme: IconThemeData(color: Color(0xFF1C241C)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: Color(0xFF2E7D32),
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
    ),
  );

  /// Для явного задання в AppBar (якщо екран перевизначає scaffold).
  static const Color toolbarBackground = AppColors.toolbar;
}
