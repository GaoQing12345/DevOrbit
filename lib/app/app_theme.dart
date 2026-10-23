import 'package:flutter/material.dart';

/// macOS-native design tokens.
///
/// The palette is deliberately colourless: macOS surfaces are neutral greys and
/// colour is reserved for the system accent, so the tools never compete with
/// the user's own syntax highlighting or diff colours.
class AppTheme {
  /// System accent (macOS `controlAccentColor` default, blue).
  static const accent = Color(0xFF007AFF);

  // Light surfaces.
  static const _windowLight = Color(0xFFECECEC);
  static const _contentLight = Color(0xFFFFFFFF);
  static const _sidebarLight = Color(0xFFF2F2F4);

  // Dark surfaces.
  static const _windowDark = Color(0xFF1C1C1E);
  static const _contentDark = Color(0xFF242426);
  static const _sidebarDark = Color(0xFF2A2A2C);

  /// System amber, used for warnings and modified-line markers.
  static const warning = Color(0xFFD18A16);

  /// Radius for controls: buttons, fields, segmented controls, menu items.
  static const radiusControl = 6.0;

  /// Radius for cards, grouped boxes and panels.
  static const radiusPanel = 10.0;

  /// Height of a standard macOS push button.
  static const controlHeight = 28.0;

  static final ThemeData _lightTheme = _base(_lightScheme());
  static final ThemeData _darkTheme = _base(_darkScheme());

  static ThemeData light() => _lightTheme;

  static ThemeData dark() => _darkTheme;

  static ColorScheme _lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: accent,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD6E9FF),
      onPrimaryContainer: Color(0xFF003A6B),
      secondary: Color(0xFF636366),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8E8EA),
      onSecondaryContainer: Color(0xFF1D1D1F),
      tertiary: Color(0xFF8E8E93),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFD70015),
      onError: Color(0xFFFFFFFF),
      // Window background; content panels paint `surfaceContainerLowest` (white).
      surface: _windowLight,
      onSurface: Color(0xFF1D1D1F),
      surfaceContainerLowest: _contentLight,
      surfaceContainerLow: Color(0xFFF7F7F8),
      surfaceContainer: _sidebarLight,
      surfaceContainerHigh: Color(0xFFE6E6E8),
      surfaceContainerHighest: Color(0xFFDDDDDF),
      onSurfaceVariant: Color(0xFF6E6E73),
      outline: Color(0xFFC6C6C8),
      outlineVariant: Color(0xFFD8D8DC),
      shadow: Color(0x33000000),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF2C2C2E),
      onInverseSurface: Color(0xFFF5F5F7),
      inversePrimary: Color(0xFF8CC8FF),
      surfaceTint: Colors.transparent,
    );
  }

  static ColorScheme _darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF0A84FF),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF004A8F),
      onPrimaryContainer: Color(0xFFD6E9FF),
      secondary: Color(0xFFAEAEB2),
      onSecondary: Color(0xFF1C1C1E),
      secondaryContainer: Color(0xFF3A3A3C),
      onSecondaryContainer: Color(0xFFF5F5F7),
      tertiary: Color(0xFF8E8E93),
      onTertiary: Color(0xFF1C1C1E),
      error: Color(0xFFFF453A),
      onError: Color(0xFF1C1C1E),
      surface: _windowDark,
      onSurface: Color(0xFFF5F5F7),
      surfaceContainerLowest: Color(0xFF171719),
      surfaceContainerLow: _contentDark,
      surfaceContainer: _sidebarDark,
      surfaceContainerHigh: Color(0xFF323234),
      surfaceContainerHighest: Color(0xFF3A3A3C),
      onSurfaceVariant: Color(0xFF98989D),
      outline: Color(0xFF48484A),
      outlineVariant: Color(0xFF3A3A3C),
      shadow: Color(0x99000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFF5F5F7),
      onInverseSurface: Color(0xFF1C1C1E),
      inversePrimary: Color(0xFF007AFF),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final textTheme = _textTheme(scheme);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );
    final hover = scheme.surfaceContainerHigh;
    final pressed = scheme.surfaceContainerHighest;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      canvasColor: scheme.surfaceContainerLowest,
      dividerColor: scheme.outlineVariant,
      // macOS has no ripple: interaction reads as a fill change.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: hover.withAlpha(150),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(radiusControl),
        ),
        textStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w400,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 16),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
          maximumSize: const WidgetStatePropertyAll(Size(28, 28)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          iconSize: const WidgetStatePropertyAll(16),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withAlpha(70)
                : scheme.onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return pressed;
            if (states.contains(WidgetState.hovered)) return hover;
            return Colors.transparent;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(0, controlHeight),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              shape: controlShape,
              side: BorderSide(color: scheme.outlineVariant),
              backgroundColor: scheme.surfaceContainerLowest,
              foregroundColor: scheme.onSurface,
              textStyle: textTheme.labelLarge,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return pressed;
                if (states.contains(WidgetState.hovered)) {
                  return scheme.surfaceContainerLow;
                }
                return scheme.surfaceContainerLowest;
              }),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: controlShape,
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.onSurface.withAlpha(38);
        }),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        isDense: true,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withAlpha(140),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusControl),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusControl),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.surfaceContainerLowest,
          ),
          elevation: const WidgetStatePropertyAll(12),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusPanel),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 12,
        position: PopupMenuPosition.under,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.surfaceContainerLowest,
          ),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusPanel),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 24,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 10,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        linearMinHeight: 3,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 24)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.surfaceContainerLowest;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minVerticalPadding: 6,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => scheme.onSurface.withAlpha(
            states.contains(WidgetState.hovered) ? 90 : 55,
          ),
        ),
        crossAxisMargin: 2,
      ),
    );
  }

  /// macOS type ramp: 13pt is the body size, headings are tight and semibold.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021(
      platform: TargetPlatform.macOS,
      colorScheme: scheme,
    );
    final ramp =
        (scheme.brightness == Brightness.dark ? base.white : base.black).apply(
          fontFamily: '.AppleSystemUIFont',
          fontFamilyFallback: const [
            'SF Pro Text',
            'PingFang SC',
            'Hiragino Sans GB',
            'Helvetica Neue',
          ],
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    TextStyle? t(
      TextStyle? style,
      double size,
      FontWeight weight, [
      double? height,
    ]) => style?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
    );

    return ramp.copyWith(
      displayLarge: t(ramp.displayLarge, 34, FontWeight.w700),
      displayMedium: t(ramp.displayMedium, 28, FontWeight.w700),
      displaySmall: t(ramp.displaySmall, 24, FontWeight.w600),
      headlineLarge: t(ramp.headlineLarge, 22, FontWeight.w600),
      headlineMedium: t(ramp.headlineMedium, 20, FontWeight.w600),
      headlineSmall: t(ramp.headlineSmall, 17, FontWeight.w600),
      titleLarge: t(ramp.titleLarge, 15, FontWeight.w600),
      titleMedium: t(ramp.titleMedium, 13, FontWeight.w600),
      titleSmall: t(ramp.titleSmall, 12, FontWeight.w600),
      bodyLarge: t(ramp.bodyLarge, 14, FontWeight.w400, 1.45),
      bodyMedium: t(ramp.bodyMedium, 13, FontWeight.w400, 1.45),
      bodySmall: t(ramp.bodySmall, 11.5, FontWeight.w400, 1.35),
      labelLarge: t(ramp.labelLarge, 13, FontWeight.w500),
      labelMedium: t(ramp.labelMedium, 11.5, FontWeight.w500),
      labelSmall: t(ramp.labelSmall, 10.5, FontWeight.w500),
    );
  }
}
