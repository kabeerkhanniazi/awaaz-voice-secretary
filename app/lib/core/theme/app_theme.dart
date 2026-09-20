import 'package:flutter/material.dart';

/// Calm, neutral design: one accent colour, the platform font, flat surfaces
/// separated by thin lines. Light and dark follow the system setting.
class AppTheme {
  // Accent: a quiet deep green (calls, "go")
  static const Color _accentLight = Color(0xFF1F6F5C);
  static const Color _accentDark = Color(0xFF5BB79E);
  static const Color _dangerLight = Color(0xFFB3402A);
  static const Color _dangerDark = Color(0xFFE0735E);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        accent: _accentLight,
        danger: _dangerLight,
        background: const Color(0xFFF7F7F5),
        surface: const Color(0xFFFFFFFF),
        container: const Color(0xFFF0F0ED),
        outline: const Color(0xFFE2E2DE),
        text: const Color(0xFF1C1C1A),
        textMuted: const Color(0xFF6B6B66),
        status: const StatusColors(warning: Color(0xFF9A6200), live: _accentLight),
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        accent: _accentDark,
        danger: _dangerDark,
        background: const Color(0xFF121212),
        surface: const Color(0xFF191919),
        container: const Color(0xFF222222),
        outline: const Color(0xFF2E2E2E),
        text: const Color(0xFFEDEDEB),
        textMuted: const Color(0xFF9D9D98),
        status: const StatusColors(warning: Color(0xFFE0A84A), live: _accentDark),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color accent,
    required Color danger,
    required Color background,
    required Color surface,
    required Color container,
    required Color outline,
    required Color text,
    required Color textMuted,
    required StatusColors status,
  }) {
    final onAccent = brightness == Brightness.light ? Colors.white : const Color(0xFF0B1F1A);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: container,
      surfaceContainerHigh: container,
      surfaceContainerHighest: container,
      outline: outline,
      outlineVariant: outline,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final textTheme = base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: text),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: text),
        );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.12),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? text : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? accent : textMuted),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        subtitleTextStyle: TextStyle(fontSize: 13, color: textMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: container,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.2),
        ),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.12),
        side: BorderSide(color: outline),
        labelStyle: TextStyle(fontSize: 13, color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: text,
        contentTextStyle: TextStyle(color: surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onAccent : textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : container,
        ),
        trackOutlineColor: WidgetStateProperty.all(outline),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: textMuted, width: 1.5),
      ),
    );
  }
}

/// Colours with a meaning beyond the scheme: waiting states and "live".
class StatusColors extends ThemeExtension<StatusColors> {
  final Color warning;
  final Color live;

  const StatusColors({required this.warning, required this.live});

  static StatusColors of(BuildContext context) => Theme.of(context).extension<StatusColors>()!;

  @override
  StatusColors copyWith({Color? warning, Color? live}) =>
      StatusColors(warning: warning ?? this.warning, live: live ?? this.live);

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      warning: Color.lerp(warning, other.warning, t)!,
      live: Color.lerp(live, other.live, t)!,
    );
  }
}
