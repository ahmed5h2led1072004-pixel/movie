import 'package:flutter/material.dart';

import 'watchlist_onboarding_screen.dart';

class GenresOnboardingScreen extends StatelessWidget {
  const GenresOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC400);
    const background = Color(0xFF111312);

    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelFraction = constraints.maxHeight < 720 ? 0.5 : 0.42;
          final panelHeight = constraints.maxHeight * panelFraction;

          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4B160C), Color(0xFFB82B12)],
                  ),
                ),
              ),
              Positioned.fill(
                child: Image.asset(
                  'assets/oppenheimer_onboarding.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.42, 0.62, 1],
                    colors: [
                      Color(0x55912A0A),
                      Color(0x22912808),
                      Color(0xAA38180F),
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
                      padding: const EdgeInsets.fromLTRB(26, 28, 26, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Explore All Genres',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 17),
                          const Text(
                            'Discover movies from every genre, in all '
                            'available qualities. Find something new and '
                            'exciting to watch every day.',
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
                                    builder: (_) =>
                                        const WatchlistOnboardingScreen(),
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
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).maybePop();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: const BorderSide(
                                  color: accent,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Back'),
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
