import 'package:flutter/material.dart';

/// Thème de l'app.
///
/// Contrainte d'accessibilité du §9 : contraste AA, cibles tactiles d'au moins
/// 44 points, et jamais de couleur seule pour porter une information.
ThemeData buildTheme() {
  const seed = Color(0xFF1F5673);

  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// « signalé il y a 3 j », « confirmé à l'instant » (§9, écran de détail).
String relativeDate(DateTime date) {
  final delta = DateTime.now().difference(date);

  if (delta.inMinutes < 1) return 'à l\'instant';
  if (delta.inMinutes < 60) return 'il y a ${delta.inMinutes} min';
  if (delta.inHours < 24) return 'il y a ${delta.inHours} h';
  if (delta.inDays < 31) return 'il y a ${delta.inDays} j';
  if (delta.inDays < 365) return 'il y a ${(delta.inDays / 30).round()} mois';
  return 'il y a ${(delta.inDays / 365).round()} an${delta.inDays >= 730 ? 's' : ''}';
}
