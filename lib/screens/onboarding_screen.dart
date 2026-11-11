import 'package:flutter/material.dart';

import 'favorite_movies_onboarding_screen.dart';
import '../widgets/route_logo_mark.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF111312);
    const accent = Color(0xFFFFC400);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final logoSize = constraints.maxWidth * 0.29;
          final footerBottom = safeBottom > 0 ? safeBottom + 10 : 24.0;

          return Stack(
            children: [
              Positioned(
                top: constraints.maxHeight * 0.37,
                left: 0,
                right: 0,
                child: Center(
                  child: RouteLogoMark(
                    size: logoSize,
                    color: accent,
                    background: background,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: constraints.maxHeight * 0.22,
                child: Center(
                  child: SizedBox(
                    width: constraints.maxWidth * 0.72,
                    height: 54,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const FavoriteMoviesOnboardingScreen(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Get Started'),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: footerBottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Route',
                      style: TextStyle(
                        color: accent,
                        fontSize: 56,
                        height: 0.95,
                        fontWeight: FontWeight.w200,
                        letterSpacing: -3.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Training center & innovation space',
                      style: TextStyle(
                        color: accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 27),
                    Text(
                      'Supervised by Mohamed Nabil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
