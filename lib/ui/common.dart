import 'package:flutter/material.dart';

import '../core/flyability.dart';
import '../core/site.dart';
import '../core/thermal_model.dart';
import '../services/app_state.dart';

const aericBlue = Color(0xFF1E88E5);
const goColor = Color(0xFF2E7D32);
const marginalColor = Color(0xFFF9A825);
const noGoColor = Color(0xFFC62828);

Color verdictColor(Verdict v) => switch (v) {
      Verdict.go => goColor,
      Verdict.marginal => marginalColor,
      Verdict.noGo => noGoColor,
    };

/// Colour scale for estimated climb rates (grey → yellow → orange → red).
Color climbColor(double climbMs) => switch (ThermalStrength.fromClimb(climbMs)) {
      ThermalStrength.none => const Color(0xFF9E9E9E),
      ThermalStrength.weak => const Color(0xFFFFD54F),
      ThermalStrength.moderate => const Color(0xFFFFA726),
      ThermalStrength.strong => const Color(0xFFF4511E),
      ThermalStrength.veryStrong => const Color(0xFFB71C1C),
    };

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 14});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Planning aid only – thermal values are model estimates (easily ±50 %). Always check the site, '
          'local rules, airspace and conditions in person. Weather: Open-Meteo.com (forecast & ERA5 archive).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

/// Star that adds/removes a site from the favourites.
class FavouriteButton extends StatelessWidget {
  const FavouriteButton(this.site, {super.key});
  final Site site;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final fav = app.isFavourite(site);
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
      icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
      onPressed: () => app.toggleFavourite(site),
    );
  }
}
