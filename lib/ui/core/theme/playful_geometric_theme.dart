import 'package:flutter/material.dart';

class PlayfulGeometricColors {
  static const background = Color(0xFFFFFDF5);
  static const foreground = Color(0xFF1E293B);
  static const muted = Color(0xFFF1F5F9);
  static const mutedForeground = Color(0xFF64748B);
  static const accent = Color(0xFF8B5CF6);
  static const accentForeground = Colors.white;
  static const secondary = Color(0xFFF472B6);
  static const tertiary = Color(0xFFFBBF24);
  static const quaternary = Color(0xFF34D399);
  static const border = Color(0xFFE2E8F0);
  static const inputBorder = Color(0xFFCBD5E1);
  static const input = Colors.white;
  static const card = Colors.white;
  static const ring = accent;

  const PlayfulGeometricColors._();
}

class PlayfulGeometricRadius {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const full = 9999.0;

  const PlayfulGeometricRadius._();
}

class PlayfulGeometricBorders {
  static const chunky = 2.0;
  static const bold = 3.0;

  const PlayfulGeometricBorders._();
}

class PlayfulGeometricShadows {
  static const press = Offset(2, 2);
  static const pop = Offset(4, 4);
  static const hover = Offset(6, 6);
  static const sticker = Offset(8, 8);

  const PlayfulGeometricShadows._();
}

class PlayfulGeometricDecorations {
  static BoxDecoration sticker({
    Color color = PlayfulGeometricColors.card,
    Color shadowColor = PlayfulGeometricColors.border,
    double borderWidth = PlayfulGeometricBorders.chunky,
    Offset shadowOffset = PlayfulGeometricShadows.sticker,
    BorderRadius borderRadius =
        const BorderRadius.all(Radius.circular(PlayfulGeometricRadius.large)),
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: borderRadius,
      border: Border.all(
        color: PlayfulGeometricColors.foreground,
        width: borderWidth,
      ),
      boxShadow: shadowOffset == Offset.zero
          ? const []
          : [
              BoxShadow(
                color: shadowColor,
                offset: shadowOffset,
                blurRadius: 0,
                spreadRadius: 0,
              ),
            ],
    );
  }

  const PlayfulGeometricDecorations._();
}

class PlayfulGeometricTheme {
  static ThemeData build() {
    final colorScheme = const ColorScheme(
      brightness: Brightness.light,
      primary: PlayfulGeometricColors.accent,
      onPrimary: PlayfulGeometricColors.accentForeground,
      secondary: PlayfulGeometricColors.secondary,
      onSecondary: PlayfulGeometricColors.foreground,
      tertiary: PlayfulGeometricColors.tertiary,
      onTertiary: PlayfulGeometricColors.foreground,
      error: Color(0xFFEF4444),
      onError: Colors.white,
      surface: PlayfulGeometricColors.background,
      onSurface: PlayfulGeometricColors.foreground,
      outline: PlayfulGeometricColors.foreground,
      outlineVariant: PlayfulGeometricColors.border,
      shadow: PlayfulGeometricColors.foreground,
      inverseSurface: PlayfulGeometricColors.foreground,
      onInverseSurface: Colors.white,
      inversePrimary: PlayfulGeometricColors.tertiary,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: PlayfulGeometricColors.background,
      canvasColor: PlayfulGeometricColors.background,
      fontFamily: 'Plus Jakarta Sans',
      shadowColor: PlayfulGeometricColors.foreground,
    );
    final textTheme = _buildTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: PlayfulGeometricColors.background,
        foregroundColor: PlayfulGeometricColors.foreground,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(
            color: PlayfulGeometricColors.border,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
        titleTextStyle: textTheme.titleLarge,
        toolbarTextStyle: textTheme.bodyLarge,
      ),
      cardTheme: CardThemeData(
        color: PlayfulGeometricColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.large),
          side: const BorderSide(
            color: PlayfulGeometricColors.foreground,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PlayfulGeometricColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.large),
          side: const BorderSide(
            color: PlayfulGeometricColors.foreground,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: PlayfulGeometricColors.foreground,
        textColor: PlayfulGeometricColors.foreground,
        selectedColor: PlayfulGeometricColors.foreground,
        selectedTileColor: PlayfulGeometricColors.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.medium),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PlayfulGeometricColors.input,
        focusColor: PlayfulGeometricColors.muted,
        hoverColor: PlayfulGeometricColors.muted,
        labelStyle: textTheme.labelLarge,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: PlayfulGeometricColors.mutedForeground,
        ),
        errorStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.error,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: _inputBorder(PlayfulGeometricColors.inputBorder),
        enabledBorder: _inputBorder(PlayfulGeometricColors.inputBorder),
        focusedBorder: _inputBorder(
          PlayfulGeometricColors.accent,
          width: PlayfulGeometricBorders.bold,
        ),
        errorBorder: _inputBorder(colorScheme.error),
        focusedErrorBorder: _inputBorder(
          colorScheme.error,
          width: PlayfulGeometricBorders.bold,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(
          backgroundColor: Colors.transparent,
          foregroundColor: PlayfulGeometricColors.foreground,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(
          backgroundColor: PlayfulGeometricColors.accent,
          foregroundColor: PlayfulGeometricColors.accentForeground,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonStyle(
          backgroundColor: PlayfulGeometricColors.accent,
          foregroundColor: PlayfulGeometricColors.accentForeground,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          backgroundColor: Colors.transparent,
          foregroundColor: PlayfulGeometricColors.foreground,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: PlayfulGeometricColors.accent,
        foregroundColor: PlayfulGeometricColors.accentForeground,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
          side: const BorderSide(
            color: PlayfulGeometricColors.foreground,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll<Color>(
            PlayfulGeometricColors.foreground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered)
                ? PlayfulGeometricColors.tertiary
                : Colors.transparent;
          }),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
            ),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: PlayfulGeometricColors.border,
        thickness: PlayfulGeometricBorders.chunky,
        space: 18,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: PlayfulGeometricColors.card,
        selectedItemColor: PlayfulGeometricColors.accent,
        unselectedItemColor: PlayfulGeometricColors.foreground,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: PlayfulGeometricColors.card,
        selectedIconTheme: const IconThemeData(
          color: PlayfulGeometricColors.accentForeground,
          size: 28,
        ),
        unselectedIconTheme: const IconThemeData(
          color: PlayfulGeometricColors.foreground,
          size: 24,
        ),
        selectedLabelTextStyle: textTheme.labelMedium,
        unselectedLabelTextStyle: textTheme.labelMedium,
        indicatorColor: PlayfulGeometricColors.accent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
          side: const BorderSide(
            color: PlayfulGeometricColors.foreground,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: PlayfulGeometricColors.accentForeground,
        unselectedLabelColor: PlayfulGeometricColors.foreground,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: PlayfulGeometricColors.border,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: PlayfulGeometricColors.accent,
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
          border: Border.all(
            color: PlayfulGeometricColors.foreground,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? PlayfulGeometricColors.quaternary
              : PlayfulGeometricColors.card;
        }),
        side: const BorderSide(
          color: PlayfulGeometricColors.foreground,
          width: PlayfulGeometricBorders.chunky,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.small),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(
          PlayfulGeometricColors.foreground,
        ),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? PlayfulGeometricColors.quaternary
              : PlayfulGeometricColors.muted;
        }),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          PlayfulGeometricColors.foreground,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll<double>(
          PlayfulGeometricBorders.chunky,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: PlayfulGeometricColors.accent,
        inactiveTrackColor: PlayfulGeometricColors.border,
        thumbColor: PlayfulGeometricColors.secondary,
        overlayColor: PlayfulGeometricColors.accent.withAlpha(56),
        valueIndicatorColor: PlayfulGeometricColors.accent,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: Colors.white,
        ),
        trackHeight: 8,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PlayfulGeometricColors.foreground,
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: Colors.white),
        actionTextColor: PlayfulGeometricColors.tertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.large),
          side: const BorderSide(
            color: PlayfulGeometricColors.tertiary,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: PlayfulGeometricColors.card,
        collapsedBackgroundColor: PlayfulGeometricColors.card,
        iconColor: PlayfulGeometricColors.foreground,
        collapsedIconColor: PlayfulGeometricColors.foreground,
        textColor: PlayfulGeometricColors.foreground,
        collapsedTextColor: PlayfulGeometricColors.foreground,
        shape: const Border(
          bottom: BorderSide(
            color: PlayfulGeometricColors.border,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
        collapsedShape: const Border(
          bottom: BorderSide(
            color: PlayfulGeometricColors.border,
            width: PlayfulGeometricBorders.chunky,
          ),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    TextStyle heading(TextStyle? style, double size, FontWeight weight) {
      return (style ?? const TextStyle()).copyWith(
        fontFamily: 'Outfit',
        color: PlayfulGeometricColors.foreground,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: 0,
      );
    }

    TextStyle body(TextStyle? style, double size, FontWeight weight) {
      return (style ?? const TextStyle()).copyWith(
        fontFamily: 'Plus Jakarta Sans',
        color: PlayfulGeometricColors.foreground,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: 0,
      );
    }

    return base.copyWith(
      displayLarge: heading(base.displayLarge, 64, FontWeight.w800),
      displayMedium: heading(base.displayMedium, 52, FontWeight.w800),
      displaySmall: heading(base.displaySmall, 42, FontWeight.w800),
      headlineLarge: heading(base.headlineLarge, 34, FontWeight.w800),
      headlineMedium: heading(base.headlineMedium, 28, FontWeight.w800),
      headlineSmall: heading(base.headlineSmall, 24, FontWeight.w800),
      titleLarge: heading(base.titleLarge, 21, FontWeight.w800),
      titleMedium: heading(base.titleMedium, 16, FontWeight.w700),
      titleSmall: heading(base.titleSmall, 14, FontWeight.w700),
      bodyLarge: body(base.bodyLarge, 16, FontWeight.w500),
      bodyMedium: body(base.bodyMedium, 14, FontWeight.w500),
      bodySmall: body(base.bodySmall, 12, FontWeight.w400).copyWith(
        color: PlayfulGeometricColors.mutedForeground,
      ),
      labelLarge: body(base.labelLarge, 14, FontWeight.w700).copyWith(
        letterSpacing: 0.7,
      ),
      labelMedium: body(base.labelMedium, 12, FontWeight.w700).copyWith(
        letterSpacing: 0.7,
      ),
      labelSmall: body(base.labelSmall, 11, FontWeight.w700).copyWith(
        letterSpacing: 0.7,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(
    Color color, {
    double width = PlayfulGeometricBorders.chunky,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(PlayfulGeometricRadius.large),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ButtonStyle _buttonStyle({
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return ButtonStyle(
      animationDuration: const Duration(milliseconds: 220),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return PlayfulGeometricColors.muted;
        }
        if (backgroundColor == Colors.transparent &&
            states.contains(WidgetState.hovered)) {
          return PlayfulGeometricColors.tertiary;
        }
        return backgroundColor;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return PlayfulGeometricColors.mutedForeground;
        }
        return foregroundColor;
      }),
      overlayColor: const WidgetStatePropertyAll<Color>(
        PlayfulGeometricColors.quaternary,
      ),
      elevation: const WidgetStatePropertyAll<double>(0),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
        ),
      ),
      side: const WidgetStatePropertyAll<BorderSide>(
        BorderSide(
          color: PlayfulGeometricColors.foreground,
          width: PlayfulGeometricBorders.chunky,
        ),
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  const PlayfulGeometricTheme._();
}
