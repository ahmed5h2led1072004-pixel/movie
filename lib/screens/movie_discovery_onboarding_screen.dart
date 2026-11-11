import 'package:flutter/material.dart';

import 'genres_onboarding_screen.dart';

class MovieDiscoveryOnboardingScreen extends StatelessWidget {
  const MovieDiscoveryOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC400);
    const background = Color(0xFF111312);

    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = constraints.maxHeight * 0.38;

          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF07343A), Color(0xFF08717B)],
                  ),
                ),
              ),
              Positioned.fill(
                child: Image.asset(
                  'assets/avengers_onboarding.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.42, 0.66, 1],
                    colors: [
                      Color(0x5A003B44),
                      Color(0x3000333B),
                      Color(0xAA0B2326),
                      Color(0xFF111312),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: panelHeight,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111312),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(26, 30, 26, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Discover Movies',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Explore a vast collection of movies in all '
                            'qualities and genres. Find your next favorite '
                            'film with ease.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              height: 1.28,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed: () {
                        Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                            builder: (_) => const GenresOnboardingScreen(),
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Next'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
