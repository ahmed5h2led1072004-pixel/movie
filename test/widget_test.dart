import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movies/main.dart';
import 'package:movies/screens/browse_screen.dart';
import 'package:movies/screens/home_screen.dart';
import 'package:movies/screens/onboarding_screen.dart';

class _SignedInUser extends Fake implements User {}

void main() {
  testWidgets('signed-out users see onboarding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthGate(authStateChanges: Stream.value(null))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('authenticated users go directly to home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(authStateChanges: Stream.value(_SignedInUser())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  for (final buttonKey in const [
    Key('home-action-button'),
    Key('home-see-more-button'),
  ]) {
    testWidgets('Home $buttonKey opens Action movies', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const HomeScreen(),
          onGenerateRoute: (settings) {
            if (settings.name != '/browse') return null;
            return MaterialPageRoute<void>(
              builder: (_) =>
                  BrowseScreen(initialGenre: settings.arguments as String?),
            );
          },
        ),
      );

      await tester.ensureVisible(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      await tester.drag(find.byType(GridView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final posterAssets = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => (image.image as AssetImage).assetName)
          .toList();
      expect(posterAssets, contains('assets/search/black_widow_results.jpg'));
      expect(posterAssets, contains('assets/search/iron_man_3_results.jpg'));
      expect(posterAssets, isNot(contains('assets/search/joker_results.jpg')));
    });
  }
}
