import 'package:flutter/material.dart';

import 'movie_discovery_onboarding_screen.dart';

class FavoriteMoviesOnboardingScreen extends StatelessWidget {
  const FavoriteMoviesOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC400);

    return Scaffold(
      backgroundColor: const Color(0xFF111312),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/movie_collage_onboarding.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.34, 0.55, 0.76, 1],
                colors: [
                  Color(0x33000000),
                  Color(0x22000000),
                  Color(0x77000000),
                  Color(0xE6000000),
                  Color(0xFF111312),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Find Your Next\nFavorite Movie Here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 25),
                  Text(
                    'Get access to a huge library of movies\n'
                    'to suit all tastes. You will surely like it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 18,
                      height: 1.55,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 39),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const MovieDiscoveryOnboardingScreen(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Explore Now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
