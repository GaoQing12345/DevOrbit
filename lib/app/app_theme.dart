import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const accent = Color(0xFF087665);
  static const ink = Color(0xFF111715);
  static const paper = Color(0xFFF4F7F6);

  static ThemeData light() => _base(_lightScheme());

  static ThemeData dark() => _base(_darkScheme());

  static ColorScheme _lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD8EEE9),
      onPrimaryContainer: const Color(0xFF123D35),
      secondary: const Color(0xFF49645E),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDCE8E4),
      onSecondaryContainer: const Color(0xFF263C37),
      surface: paper,
      onSurface: const Color(0xFF17201E),
      surfaceContainerLowest: const Color(0xFFF1F4F3),
      surfaceContainerLow: const Color(0xFFF7F9F8),
      surfaceContainer: const Color(0xFFEDF1EF),
      surfaceContainerHigh: const Color(0xFFE7ECEA),
      surfaceContainerHighest: const Color(0xFFDEE5E2),
      onSurfaceVariant: const Color(0xFF5C6965),
      outline: const Color(0xFF9EAAA6),
      outlineVariant: const Color(0xFFD7DFDC),
      error: const Color(0xFFB42318),
      surfaceTint: Colors.transparent,
    );
  }

  static ColorScheme _darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF53B9A6),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF63C6B3),
      onPrimary: const Color(0xFF062E27),
      primaryContainer: const Color(0xFF164B41),
      onPrimaryContainer: const Color(0xFFCDEFE8),
      secondary: const Color(0xFFA8C9C1),
      onSecondary: const Color(0xFF17332D),
      secondaryContainer: const Color(0xFF2A4540),
      onSecondaryContainer: const Color(0xFFD8E7E3),
      surface: ink,
      onSurface: const Color(0xFFE6ECEA),
      surfaceContainerLowest: const Color(0xFF0D1211),
      surfaceContainerLow: const Color(0xFF151C1A),
      surfaceContainer: const Color(0xFF1A2320),
      surfaceContainerHigh: const Color(0xFF202A27),
      surfaceContainerHighest: const Color(0xFF28332F),
      onSurfaceVariant: const Color(0xFFAAB7B3),
      outline: const Color(0xFF6D7A76),
      outlineVariant: const Color(0xFF34413D),
      error: const Color(0xFFFFB4AB),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    );
    final baseTextTheme =
        (scheme.brightness == Brightness.dark
                ? typography.white
                : typography.black)
            .apply(
              fontFamily: isMacOS ? '.AppleSystemUIFont' : 'Segoe UI Variable',
              fontFamilyFallback: const [
                'Segoe UI',
                'PingFang SC',
                'Microsoft YaHei',
                'Noto Sans SC',
                'Roboto',
              ],
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            );
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(letterSpacing: 0),
      displayMedium: baseTextTheme.displayMedium?.copyWith(letterSpacing: 0),
      displaySmall: baseTextTheme.displaySmall?.copyWith(letterSpacing: 0),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(letterSpacing: 0),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(letterSpacing: 0),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(letterSpacing: 0),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.55,
        letterSpacing: 0,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
        letterSpacing: 0,
      ),
    );

    final rounded6 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(5),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
          iconSize: const WidgetStatePropertyAll(19),
          shape: WidgetStatePropertyAll(rounded6),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withAlpha(80)
                : scheme.onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? scheme.surfaceContainerHigh
                : Colors.transparent,
          ),
          overlayColor: WidgetStatePropertyAll(scheme.primary.withAlpha(18)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: rounded6,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          side: BorderSide(color: scheme.outlineVariant),
          shape: rounded6,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: rounded6,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withAlpha(150),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(rounded6),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 18,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        titleTextStyle: textTheme.titleMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: rounded6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
    );
  }
}
