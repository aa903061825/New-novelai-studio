import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

class StudioTheme {
  static ThemeData build() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: StudioTokens.primary,
      onPrimary: StudioTokens.onPrimary,
      secondary: StudioTokens.secondary,
      onSecondary: StudioTokens.onPrimary,
      tertiary: StudioTokens.active,
      onTertiary: StudioTokens.onPrimary,
      error: StudioTokens.danger,
      onError: Colors.white,
      surface: StudioTokens.surface1,
      onSurface: StudioTokens.textPrimary,
      outline: StudioTokens.border,
      outlineVariant: StudioTokens.borderStrong,
      shadow: Colors.black,
      inverseSurface: StudioTokens.textPrimary,
      onInverseSurface: StudioTokens.surfaceBase,
      inversePrimary: StudioTokens.primary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: StudioTokens.surface1,
      canvasColor: StudioTokens.surface1,
      dividerColor: StudioTokens.border,
      splashColor: StudioTokens.primary.withAlpha(24),
      highlightColor: StudioTokens.primary.withAlpha(18),
      hoverColor: StudioTokens.primary.withAlpha(16),
    );
    final textTheme = _buildTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: StudioTokens.surface1,
        foregroundColor: StudioTokens.textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        toolbarTextStyle: textTheme.bodyMedium,
      ),
      cardTheme: CardThemeData(
        color: StudioTokens.surface3,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: StudioTokens.radiusCard,
          side: StudioTokens.cardBorderSide,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: StudioTokens.surface3,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioTokens.radiusLarge),
          side: const BorderSide(color: StudioTokens.borderStrong),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: StudioTokens.surface2,
        hoverColor: StudioTokens.surface3,
        labelStyle: textTheme.labelLarge,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: StudioTokens.textMuted,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: StudioTokens.danger,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: _inputBorder(StudioTokens.border),
        enabledBorder: _inputBorder(StudioTokens.border),
        focusedBorder: _inputBorder(StudioTokens.primary),
        errorBorder: _inputBorder(StudioTokens.danger),
        focusedErrorBorder: _inputBorder(StudioTokens.danger),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(
          foregroundColor: StudioTokens.textPrimary,
          backgroundColor: Colors.transparent,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(
          foregroundColor: StudioTokens.onPrimary,
          backgroundColor: StudioTokens.primary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(
          foregroundColor: StudioTokens.onPrimary,
          backgroundColor: StudioTokens.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          foregroundColor: StudioTokens.textPrimary,
          backgroundColor: Colors.transparent,
          borderColor: StudioTokens.borderStrong,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: StudioTokens.surface2,
        selectedColor: StudioTokens.primary,
        disabledColor: StudioTokens.surface2,
        secondarySelectedColor: StudioTokens.secondary,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: StudioTokens.onPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: const StadiumBorder(
          side: BorderSide(color: StudioTokens.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: StudioTokens.surface4,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: StudioTokens.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioTokens.radiusMedium),
          side: const BorderSide(color: StudioTokens.borderStrong),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: StudioTokens.border,
        indicatorColor: StudioTokens.primary,
        labelColor: StudioTokens.primary,
        unselectedLabelColor: StudioTokens.textSecondary,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: StudioTokens.primary,
        foregroundColor: StudioTokens.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    TextStyle? apply(TextStyle? style, Color color) {
      return style?.copyWith(
        color: color,
        letterSpacing: 0,
        height: 1.18,
      );
    }

    return base.copyWith(
      displayLarge: apply(base.displayLarge, StudioTokens.textPrimary),
      displayMedium: apply(base.displayMedium, StudioTokens.textPrimary),
      displaySmall: apply(base.displaySmall, StudioTokens.textPrimary),
      headlineLarge: apply(base.headlineLarge, StudioTokens.textPrimary),
      headlineMedium: apply(base.headlineMedium, StudioTokens.textPrimary),
      headlineSmall: apply(base.headlineSmall, StudioTokens.textPrimary),
      titleLarge: apply(base.titleLarge, StudioTokens.textPrimary)?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: apply(base.titleMedium, StudioTokens.textPrimary)?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleSmall: apply(base.titleSmall, StudioTokens.textPrimary)?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: apply(base.bodyLarge, StudioTokens.textPrimary),
      bodyMedium: apply(base.bodyMedium, StudioTokens.textSecondary),
      bodySmall: apply(base.bodySmall, StudioTokens.textMuted),
      labelLarge: apply(base.labelLarge, StudioTokens.textPrimary)?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelMedium: apply(base.labelMedium, StudioTokens.textSecondary),
      labelSmall: apply(base.labelSmall, StudioTokens.textMuted),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(StudioTokens.radiusMedium),
      borderSide: BorderSide(color: color),
    );
  }

  static ButtonStyle _buttonStyle({
    required Color foregroundColor,
    required Color backgroundColor,
    Color? borderColor,
  }) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.all(foregroundColor),
      backgroundColor: WidgetStateProperty.all(backgroundColor),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return StudioTokens.primary.withAlpha(46);
        }
        if (states.contains(WidgetState.hovered)) {
          return StudioTokens.primary.withAlpha(24);
        }
        return null;
      }),
      minimumSize: WidgetStateProperty.all(const Size(44, 40)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        const StadiumBorder(),
      ),
      side: WidgetStateProperty.all(
        BorderSide(color: borderColor ?? Colors.transparent),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
      ),
      elevation: WidgetStateProperty.all(0),
    );
  }

  const StudioTheme._();
}
