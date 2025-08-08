import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide phases you can tag batches/steps with.
enum FermentationPhase {
  planning,
  primary,
  secondary,
  coldCrash,
  conditioning,
  aged,
  completed,
  stalled,
}

/// ThemeExtension that carries semantic colors for fermentation statuses.
@immutable
class FermentaStatusTheme extends ThemeExtension<FermentaStatusTheme> {
  final Map<FermentationPhase, Color> fg;
  final Map<FermentationPhase, Color> bg;

  const FermentaStatusTheme({required this.fg, required this.bg});

  /// Light factory, derived from the app's ColorScheme.
  factory FermentaStatusTheme.light(ColorScheme c) {
    return FermentaStatusTheme(
      fg: {
        FermentationPhase.planning: c.onSurfaceVariant,
        FermentationPhase.primary: c.onTertiary,
        FermentationPhase.secondary: c.onPrimary,
        FermentationPhase.coldCrash: c.onSecondaryContainer,
        FermentationPhase.conditioning: c.onPrimaryContainer,
        FermentationPhase.aged: c.onSecondary,
        FermentationPhase.completed: c.onSecondary,
        FermentationPhase.stalled: c.onError,
      },
      bg: {
        FermentationPhase.planning: c.surfaceContainerHighest.withValues(alpha: 0.40),
        FermentationPhase.primary: c.tertiary.withValues(alpha: 0.22),
        FermentationPhase.secondary: c.primary.withValues(alpha: 0.18),
        FermentationPhase.coldCrash: c.secondary.withValues(alpha: 0.18),
        FermentationPhase.conditioning: c.primaryContainer.withValues(alpha: 0.26),
        FermentationPhase.aged: c.secondary.withValues(alpha: 0.22),
        FermentationPhase.completed: c.secondary.withValues(alpha: 0.18),
        FermentationPhase.stalled: c.error.withValues(alpha: 0.22),
      },
    );
  }

  /// Dark factory, derived from the app's ColorScheme.
  factory FermentaStatusTheme.dark(ColorScheme c) {
    return FermentaStatusTheme(
      fg: {
        FermentationPhase.planning: c.onSurfaceVariant,
        FermentationPhase.primary: c.onTertiary,
        FermentationPhase.secondary: c.onPrimary,
        FermentationPhase.coldCrash: c.onSecondaryContainer,
        FermentationPhase.conditioning: c.onPrimaryContainer,
        FermentationPhase.aged: c.onSecondary,
        FermentationPhase.completed: c.onSecondary,
        FermentationPhase.stalled: c.onError,
      },
      bg: {
        FermentationPhase.planning: c.surfaceContainerHighest.withValues(alpha: 0.22),
        FermentationPhase.primary: c.tertiary.withValues(alpha: 0.24),
        FermentationPhase.secondary: c.primary.withValues(alpha: 0.22),
        FermentationPhase.coldCrash: c.secondary.withValues(alpha: 0.20),
        FermentationPhase.conditioning: c.primaryContainer.withValues(alpha: 0.20),
        FermentationPhase.aged: c.secondary.withValues(alpha: 0.22),
        FermentationPhase.completed: c.secondary.withValues(alpha: 0.18),
        FermentationPhase.stalled: c.error.withValues(alpha: 0.24),
      },
    );
  }

  /// Foreground/text color for a given phase.
  Color fgFor(FermentationPhase phase) => fg[phase]!;

  /// Background "chip" color for a given phase.
  Color bgFor(FermentationPhase phase) => bg[phase]!;

  @override
  FermentaStatusTheme copyWith({
    Map<FermentationPhase, Color>? fg,
    Map<FermentationPhase, Color>? bg,
  }) =>
      FermentaStatusTheme(fg: fg ?? this.fg, bg: bg ?? this.bg);

  @override
  FermentaStatusTheme lerp(ThemeExtension<FermentaStatusTheme>? other, double t) {
    if (other is! FermentaStatusTheme) return this;
    Color lerp(Color a, Color b) => Color.lerp(a, b, t)!;
    Map<FermentationPhase, Color> lerpMap(
      Map<FermentationPhase, Color> a,
      Map<FermentationPhase, Color> b,
    ) {
      final out = <FermentationPhase, Color>{};
      for (final k in a.keys) {
        out[k] = lerp(a[k]!, b[k] ?? a[k]!);
      }
      return out;
    }

    return FermentaStatusTheme(
      fg: lerpMap(fg, other.fg),
      bg: lerpMap(bg, other.bg),
    );
  }
}

class AppTheme {
  // ---------- Color Schemes (yours, kept) ----------
  static const ColorScheme _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8E5B26),
    onPrimary: Colors.white,
    secondary: Color(0xFFA3C567),
    onSecondary: Colors.black,
    tertiary: Color(0xFFB24F47),
    onTertiary: Colors.white,
    error: Color(0xFFD14343),
    onError: Colors.white,
    surface: Color(0xFF2A2A28),
    onSurface: Color(0xFFEDEAE5),
    surfaceContainerHighest: Color(0xFF6C6C63),
    onSurfaceVariant: Color(0xFFCFCFCF),
    outline: Color(0xFF8D8D84),
    shadow: Colors.black54,
    inverseSurface: Color(0xFFFDF9F0),
    onInverseSurface: Color(0xFF1A1A1A),
    inversePrimary: Color(0xFFFFD9B0),
    surfaceTint: Color(0xFF8E5B26),
  );

  static const ColorScheme _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8E5B26),
    onPrimary: Colors.white,
    secondary: Color(0xFFA3C567),
    onSecondary: Colors.black,
    tertiary: Color(0xFFB24F47),
    onTertiary: Colors.white,
    error: Color(0xFFD14343),
    onError: Colors.white,
    surface: Color(0xFFFAF4E7),
    onSurface: Color(0xFF2F2F2F),
    surfaceContainerHighest: Color(0xFFDCD6C4),
    onSurfaceVariant: Color(0xFF4F4F4F),
    outline: Color(0xFFB7B4A5),
    shadow: Colors.black12,
    inverseSurface: Color(0xFF2F2F2F),
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFBF8244),
    surfaceTint: Color(0xFF8E5B26),
  );

  // ---------- Typography ----------
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = ThemeData(brightness: scheme.brightness).textTheme;
    final bask = GoogleFonts.libreBaskervilleTextTheme(base);
    final robo = GoogleFonts.robotoTextTheme(base);

    return base.copyWith(
      displayLarge: bask.displayLarge?.copyWith(fontSize: 57, fontWeight: FontWeight.w700),
      displayMedium: bask.displayMedium?.copyWith(fontSize: 45, fontWeight: FontWeight.w700),
      displaySmall: bask.displaySmall?.copyWith(fontSize: 36, fontWeight: FontWeight.w700),
      headlineLarge: bask.headlineLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
      headlineMedium: bask.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
      headlineSmall: bask.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge: bask.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: robo.titleMedium?.copyWith(letterSpacing: 0.1, fontWeight: FontWeight.w600),
      titleSmall: robo.titleSmall?.copyWith(letterSpacing: 0.1, fontWeight: FontWeight.w600),
      bodyLarge: robo.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
      bodyMedium: robo.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
      bodySmall: robo.bodySmall?.copyWith(fontSize: 12, height: 1.35),
      labelLarge: robo.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: robo.labelMedium?.copyWith(letterSpacing: 0.2),
      labelSmall: robo.labelSmall?.copyWith(letterSpacing: 0.3),
    );
  }

  // ---------- Shared shapes ----------
  static const double _radius = 16.0;
  static final RoundedRectangleBorder _shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));

  // ---------- Component helpers ----------
  static ButtonStyle _filledButton(ColorScheme c) => FilledButton.styleFrom(
        shape: _shape,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      );

  static ButtonStyle _elevatedButton(ColorScheme c) => ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        shape: _shape,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      );

  static ButtonStyle _outlinedButton(ColorScheme c) => OutlinedButton.styleFrom(
        shape: _shape,
        side: BorderSide(color: c.outline),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith(
          (s) => (s.contains(WidgetState.pressed) || s.contains(WidgetState.hovered))
              ? c.primary.withValues(alpha: 0.08)
              : null,
        ),
      );

  static ButtonStyle _textButton(ColorScheme c) => TextButton.styleFrom(
        shape: _shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  static InputDecorationTheme _inputs(ColorScheme c, {required bool dark}) {
    final fill = dark
        ? c.surfaceContainerHighest.withValues(alpha: 0.30)
        : c.surfaceContainerHighest.withValues(alpha: 0.50);

    OutlineInputBorder border(Color color, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: w));

    return InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      hintStyle: TextStyle(color: c.onSurfaceVariant.withValues(alpha: 0.7)),
      labelStyle: TextStyle(color: c.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      disabledBorder: border(c.outline.withValues(alpha: 0.2)),
      focusedBorder: border(c.primary, 1.4),
      errorBorder: border(c.error),
      focusedErrorBorder: border(c.error, 1.4),
    );
  }

  static CardThemeData _cards(ColorScheme c, {required bool dark}) => CardThemeData(
        elevation: dark ? 0 : 1,
        color: dark ? c.surfaceContainerHighest.withValues(alpha: 0.30) : c.surface,
        surfaceTintColor: Colors.transparent,
        shape: _shape,
        margin: const EdgeInsets.all(8),
      );

  static TabBarThemeData _tabs(ColorScheme c) => TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        labelColor: c.primary,
        unselectedLabelColor: c.onSurfaceVariant,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 3),
          insets: EdgeInsets.symmetric(horizontal: 8),
        ),
      ).copyWith(
        // color must be set outside const
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: c.primary),
          insets: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );

  static NavigationBarThemeData _navBar(ColorScheme c) => NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      );

  static BottomNavigationBarThemeData _bottomNav(ColorScheme c) => BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.onSurfaceVariant,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      );

  static ChipThemeData _chips(ColorScheme c) => ChipThemeData(
        shape: _shape,
        backgroundColor: c.surface,
        selectedColor: c.primary.withValues(alpha: 0.16),
        side: BorderSide(color: c.outline),
        labelStyle: TextStyle(color: c.onSurface),
        secondaryLabelStyle: TextStyle(color: c.onPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      );

  static DialogThemeData _dialog(ColorScheme c) => DialogThemeData(
        shape: _shape,
        elevation: 0,
        backgroundColor: c.surface,
      );

  static SnackBarThemeData _snack(ColorScheme c) => SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverseSurface,
        contentTextStyle: TextStyle(color: c.onInverseSurface, fontWeight: FontWeight.w600),
        actionTextColor: c.inversePrimary,
        shape: _shape,
      );

  static TooltipThemeData _tooltip(ColorScheme c) => TooltipThemeData(
        decoration: ShapeDecoration(
          color: c.inverseSurface,
          shape: _shape,
        ),
        textStyle: TextStyle(color: c.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(milliseconds: 2500),
      );

  static ExpansionTileThemeData _expansion(ColorScheme c) => ExpansionTileThemeData(
        backgroundColor: c.surface,
        collapsedBackgroundColor: c.surface,
        shape: _shape,
        collapsedShape: _shape,
        textColor: c.onSurface,
        collapsedTextColor: c.onSurfaceVariant,
        iconColor: c.primary,
        collapsedIconColor: c.onSurfaceVariant,
      );

  static PopupMenuThemeData _menu(ColorScheme c) => PopupMenuThemeData(
        shape: _shape,
        color: c.surface,
        elevation: 4,
        textStyle: TextStyle(color: c.onSurface),
      );

  static ScrollbarThemeData _scrollbars(ColorScheme c) => const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(true),
        thickness: WidgetStatePropertyAll(6),
        radius: Radius.circular(999),
      );

  static DividerThemeData _dividers(ColorScheme c) => DividerThemeData(
        color: c.outline.withValues(alpha: 0.5),
        thickness: 1,
        space: 24,
      );

  static ProgressIndicatorThemeData _progress(ColorScheme c) =>
      ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.outline.withValues(alpha: 0.25),
      );

  static SwitchThemeData _switches(ColorScheme c) => SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
          if (states.contains(WidgetState.selected)) return const Icon(Icons.check);
          return const Icon(Icons.close);
        }),
        trackOutlineColor: WidgetStatePropertyAll(c.outline.withValues(alpha: 0.5)),
      );

  static SegmentedButtonThemeData _segments(ColorScheme c) => SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(_shape),
          side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? c.primary.withValues(alpha: 0.12)
                : c.surface,
          ),
        ),
      );

  // ---------- Light Theme ----------
  static ThemeData get lightTheme {
    const c = _light;
    final t = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      textTheme: t,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: c.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 4,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: t.titleLarge?.copyWith(color: c.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledButton(c)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(c)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedButton(c)),
      textButtonTheme: TextButtonThemeData(style: _textButton(c)),
      inputDecorationTheme: _inputs(c, dark: false),
      cardTheme: _cards(c, dark: false),
      tabBarTheme: _tabs(c),
      bottomNavigationBarTheme: _bottomNav(c),
      navigationBarTheme: _navBar(c),
      chipTheme: _chips(c),
      dialogTheme: _dialog(c),
      snackBarTheme: _snack(c),
      tooltipTheme: _tooltip(c),
      expansionTileTheme: _expansion(c),
      popupMenuTheme: _menu(c),
      scrollbarTheme: _scrollbars(c),
      dividerTheme: _dividers(c),
      progressIndicatorTheme: _progress(c),
      switchTheme: _switches(c),
      segmentedButtonTheme: _segments(c),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
      // <- Extensions live here
      extensions: <ThemeExtension<dynamic>>[
        FermentaStatusTheme.light(c),
      ],
    );
  }

  // ---------- Dark Theme ----------
  static ThemeData get darkTheme {
    const c = _dark;
    final t = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      textTheme: t,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: c.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 4,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: t.titleLarge?.copyWith(color: c.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledButton(c)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(c)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedButton(c)),
      textButtonTheme: TextButtonThemeData(style: _textButton(c)),
      inputDecorationTheme: _inputs(c, dark: true),
      cardTheme: _cards(c, dark: true),
      tabBarTheme: _tabs(c),
      bottomNavigationBarTheme: _bottomNav(c),
      navigationBarTheme: _navBar(c),
      chipTheme: _chips(c),
      dialogTheme: _dialog(c),
      snackBarTheme: _snack(c),
      tooltipTheme: _tooltip(c),
      expansionTileTheme: _expansion(c),
      popupMenuTheme: _menu(c),
      scrollbarTheme: _scrollbars(c),
      dividerTheme: _dividers(c),
      progressIndicatorTheme: _progress(c),
      switchTheme: _switches(c),
      segmentedButtonTheme: _segments(c),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
      extensions: <ThemeExtension<dynamic>>[
        FermentaStatusTheme.dark(c),
      ],
    );
  }
}
