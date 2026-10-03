import 'package:flutter/material.dart';

import 'labels.dart';

/// Onboarding, un seul écran (§9, écran 4).
///
/// Il dit ce que fait l'app, demande la géolocalisation, et annonce la couleur
/// sur les données. Il n'y a rien à créer, rien à accepter : pas de compte.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.remove_road, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 20),
              Text(AppLabels.appName, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(OnboardingLabels.pitch, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 28),
              const _Point(
                icon: Icons.person_off_outlined,
                title: OnboardingLabels.noAccountTitle,
                body: OnboardingLabels.noAccountBody,
              ),
              const _Point(
                icon: Icons.my_location,
                title: OnboardingLabels.locationTitle,
                body: OnboardingLabels.locationBody,
              ),
              const _Point(
                icon: Icons.public,
                title: OnboardingLabels.openDataTitle,
                body: OnboardingLabels.openDataBody,
              ),
              const Spacer(),
              FilledButton(
                onPressed: onStart,
                child: const Text(OnboardingLabels.start),
              ),
              const SizedBox(height: 8),
              Text(
                OnboardingLabels.permissionNotice,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
}
