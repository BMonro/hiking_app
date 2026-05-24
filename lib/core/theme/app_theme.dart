import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {

  static const scaffold = Color(0xFFF3F5F2);

  static const scaffoldWarm = Color(0xFFFAFAF7);

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
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFE8F5E9),
      contentTextStyle: const TextStyle(
        color: Color(0xFF1B5E20),
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      actionTextColor: const Color(0xFF2E7D32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Color(0xFFA5D6A7)),
      ),
      elevation: 4,
    ),
  );

  static const Color toolbarBackground = AppColors.toolbar;
}
