import 'package:flutter/material.dart';

import 'start_watching_onboarding_screen.dart';

class ReviewsOnboardingScreen extends StatelessWidget {
  const ReviewsOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC400);
    const background = Color(0xFF111312);

    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelFraction = constraints.maxHeight < 720 ? 0.5 : 0.46;
          final panelHeight = constraints.maxHeight * panelFraction;

          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF35110D), Color(0xFF7A2018)],
                  ),
                ),
              ),
              Positioned.fill(
                child: Image.asset(
                  'assets/doctor_strange_reviews_onboarding.jpg',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.18),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.4, 0.6, 1],
                    colors: [
                      Color(0x55490D0A),
                      Color(0x22490D0A),
                      Color(0xAA23130F),
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
                            'Rate, Review, and Learn',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Share your thoughts on the movies you’ve '
                            'watched. Dive deep into film details and help '
                            'others discover great movies with your reviews.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
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
                                        const StartWatchingOnboardingScreen(),
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
                              onPressed: () => Navigator.of(context).maybePop(),
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
