import 'package:flutter/material.dart';

abstract final class DmxColors {
  static const canvas = Color(0xff151310);
  static const panel = Color(0xff272421);
  static const raised = Color(0xff34302b);
  static const elevated = Color(0xff423b34);
  static const inset = Color(0xff0e0d0c);
  static const border = Color(0xff62564a);
  static const iron = Color(0xff242321);
  static const ironRaised = Color(0xff33312e);
  static const rust = Color(0xffa35d3d);
  static const rustDark = Color(0xff573526);
  static const bezel = Color(0xffb88c52);
  static const text = Color(0xfff2eee7);
  static const muted = Color(0xffb8b0a7);
  static const teal = Color(0xff61b5aa);
  static const amber = Color(0xffe6a33a);
  static const red = Color(0xffdf5656);
  static const green = Color(0xff69c184);
  static const blue = Color(0xff65a8e8);
}

ThemeData dmxTheme() {
  const radius = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: DmxColors.amber,
          brightness: Brightness.dark,
          surface: DmxColors.panel,
          error: DmxColors.red,
        ).copyWith(
          primary: DmxColors.amber,
          onPrimary: const Color(0xff281504),
          secondary: DmxColors.rust,
          onSecondary: DmxColors.text,
          surface: DmxColors.iron,
          onSurface: DmxColors.text,
        ),
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Nunito',
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 38,
        height: 1.08,
        fontWeight: FontWeight.w800,
        color: DmxColors.text,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w800,
        color: DmxColors.text,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: DmxColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: DmxColors.text,
      ),
      bodyLarge: TextStyle(fontSize: 17, height: 1.45, color: DmxColors.text),
      bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: DmxColors.muted),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
    cardTheme: const CardThemeData(
      color: DmxColors.iron,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0xaa000000),
      elevation: 7,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: DmxColors.rustDark, width: 1.5),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: DmxColors.inset,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: DmxColors.rustDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: DmxColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: DmxColors.amber, width: 2),
      ),
      labelStyle: TextStyle(color: DmxColors.muted),
      floatingLabelStyle: TextStyle(color: DmxColors.amber),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DmxColors.amber,
        foregroundColor: const Color(0xff281504),
        side: const BorderSide(color: DmxColors.bezel),
        elevation: 4,
        shadowColor: const Color(0x99e6a33a),
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DmxColors.text,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: DmxColors.rust),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: DmxColors.muted,
      collapsedIconColor: DmxColors.muted,
      shape: RoundedRectangleBorder(side: BorderSide.none),
      collapsedShape: RoundedRectangleBorder(side: BorderSide.none),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: DmxColors.amber,
      inactiveTrackColor: DmxColors.inset,
      thumbColor: DmxColors.amber,
      overlayColor: Color(0x33e6a33a),
      trackHeight: 10,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 14),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? DmxColors.amber
            : DmxColors.muted,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DmxColors.amber,
      linearTrackColor: DmxColors.inset,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: DmxColors.ironRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: DmxColors.rust, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: DmxColors.ironRaised,
      contentTextStyle: TextStyle(color: DmxColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: DmxColors.amber),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DmxColors.inset,
      selectedColor: DmxColors.rustDark,
      side: const BorderSide(color: DmxColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(color: DmxColors.text),
    ),
    focusColor: const Color(0x33e6a33a),
    hoverColor: const Color(0x1fe6a33a),
    splashColor: const Color(0x33e6a33a),
    dividerColor: DmxColors.border,
  );
}
