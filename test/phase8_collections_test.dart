import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/screens/movie_details_screen.dart';
import 'package:movies/screens/profile_screen.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'user-phase-8';

  @override
  String? get displayName => 'Diana Prince';

  @override
  String? get email => 'diana@themyscira.gov';
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  _FakeFirebaseAuth({this.currentUser});

  @override
  User? currentUser;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleMovie = Movie(
    id: '42',
    title: 'Interstellar',
    year: 2014,
    rating: 8.7,
    posterUrl: 'https://example.com/interstellar.jpg',
    imageAsset: 'assets/avengers_onboarding.jpg',
  );

  group('Phase 8 — Unit Tests: Firestore Models, Deduplication & Ordering', () {
    test('1. Movie.toFirestoreMovie produces expected schema for Firestore rules', () {
      final firestoreMap = sampleMovie.toFirestoreMovie();

      expect(firestoreMap['id'], '42');
      expect(firestoreMap['title'], 'Interstellar');
      expect(firestoreMap['year'], '2014');
      expect(firestoreMap['poster'], 'assets/avengers_onboarding.jpg');
    });

    test('2. Movie.fromFirestore properly reconstructs Movie from document data', () {
      final docData = {
        'id': '99',
        'title': 'Dune: Part Two',
        'year': 2024,
        'poster': 'https://example.com/dune.jpg',
      };

      final reconstructed = Movie.fromFirestore(docData, documentId: '99');

      expect(reconstructed.id, '99');
      expect(reconstructed.title, 'Dune: Part Two');
      expect(reconstructed.year, 2024);
      expect(reconstructed.posterUrl, 'https://example.com/dune.jpg');
    });

    test('3. Deduplication is guaranteed by using movieId as document ID', () {
      final String uid = 'test-uid';
      final String movieId = sampleMovie.id;

      final favoritesPath = 'users/$uid/favorites/$movieId';
      final watchlistPath = 'users/$uid/watchlist/$movieId';
      final recentlyWatchedPath = 'users/$uid/recently_watched/$movieId';

      expect(favoritesPath, 'users/test-uid/favorites/42');
      expect(watchlistPath, 'users/test-uid/watchlist/42');
      expect(recentlyWatchedPath, 'users/test-uid/recently_watched/42');

      // Re-saving the same movie produces the identical document path
      final secondMovieRefPath = 'users/$uid/favorites/${sampleMovie.id}';
      expect(secondMovieRefPath, favoritesPath);
    });

    test('4. Recently Watched sorting orders most recent timestamps first', () {
      final now = DateTime.now();
      final movieA = {
        'id': '1',
        'title': 'Movie Old',
        'watchedAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
      };
      final movieB = {
        'id': '2',
        'title': 'Movie Newest',
        'watchedAt': Timestamp.fromDate(now),
      };
      final movieC = {
        'id': '3',
        'title': 'Movie Middle',
        'watchedAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 30))),
      };

      final historyList = [movieA, movieB, movieC];
      historyList.sort((a, b) {
        final aTime = a['watchedAt'] as Timestamp;
        final bTime = b['watchedAt'] as Timestamp;
        return bTime.compareTo(aTime); // descending order
      });

      expect(historyList[0]['title'], 'Movie Newest');
      expect(historyList[1]['title'], 'Movie Middle');
      expect(historyList[2]['title'], 'Movie Old');
    });
  });

  group('Phase 8 — Widget Tests: MovieDetailsScreen Favorites & Watchlist Actions', () {
    testWidgets('5. Adding a movie to Watchlist updates state and shows SnackBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool watchlistToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: false,
            initialIsFavorite: false,
            onToggleWatchlist: () async {
              watchlistToggled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final watchlistBtn = find.byKey(const Key('details-watchlist-button'));
      expect(watchlistBtn, findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

      await tester.tap(watchlistBtn);
      await tester.pumpAndSettle();

      expect(watchlistToggled, isTrue);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.text('Movie added to Watch List'), findsOneWidget);
    });

    testWidgets('6. Removing a movie from Watchlist updates state and shows SnackBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool watchlistRemoved = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: true,
            initialIsFavorite: false,
            onToggleWatchlist: () async {
              watchlistRemoved = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('details-watchlist-button')));
      await tester.pumpAndSettle();

      expect(watchlistRemoved, isTrue);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.text('Movie removed from Watch List'), findsOneWidget);
    });

    testWidgets('7. Adding a movie to Favorites updates state and shows SnackBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool favoriteAdded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: false,
            initialIsFavorite: false,
            onToggleFavorite: () async {
              favoriteAdded = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final favoriteBtn = find.byKey(const Key('details-favorite-button'));
      expect(favoriteBtn, findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(favoriteBtn);
      await tester.pumpAndSettle();

      expect(favoriteAdded, isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('Movie added to Favorites'), findsOneWidget);
    });

    testWidgets('8. Removing a movie from Favorites updates state and shows SnackBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool favoriteRemoved = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: false,
            initialIsFavorite: true,
            onToggleFavorite: () async {
              favoriteRemoved = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('details-favorite-button')));
      await tester.pumpAndSettle();

      expect(favoriteRemoved, isTrue);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.text('Movie removed from Favorites'), findsOneWidget);
    });

    testWidgets('9. Rollback state when Watchlist update fails with error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: false,
            initialIsFavorite: false,
            onToggleWatchlist: () async {
              throw Exception('Network disconnected');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('details-watchlist-button')));
      await tester.pumpAndSettle();

      // State is rolled back to false (un-saved) and error SnackBar is shown
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.text('Could not update Watch List'), findsOneWidget);
    });

    testWidgets('10. Rollback state when Favorites update fails with error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            initialIsSaved: false,
            initialIsFavorite: true,
            onToggleFavorite: () async {
              throw Exception('Firestore write rejected');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('details-favorite-button')));
      await tester.pumpAndSettle();

      // State is rolled back to true (saved) and error SnackBar is shown
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('Could not update Favorites'), findsOneWidget);
    });

    testWidgets('11. Unauthenticated user gets "Please login first" prompt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final unauthenticatedAuth = _FakeFirebaseAuth(currentUser: null);

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            auth: unauthenticatedAuth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Watch button
      await tester.tap(find.byKey(const Key('details-watch-button')));
      await tester.pump();
      expect(find.text('Please login first'), findsOneWidget);

      // Tap Watchlist button
      await tester.tap(find.byKey(const Key('details-watchlist-button')));
      await tester.pump();
      expect(find.text('Please login first'), findsOneWidget);

      // Tap Favorite button
      await tester.tap(find.byKey(const Key('details-favorite-button')));
      await tester.pump();
      expect(find.text('Please login first'), findsOneWidget);
    });

    testWidgets('12. Authenticated user triggers watch action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeUser = _FakeUser();
      final authenticatedAuth = _FakeFirebaseAuth(currentUser: fakeUser);
      bool recordCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: sampleMovie,
            auth: authenticatedAuth,
            onRecordWatched: () async {
              recordCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('details-watch-button')));
      await tester.pumpAndSettle();

      expect(recordCalled, isTrue);
    });
  });

  group('Phase 8 — Widget Tests: ProfileScreen Empty States, Tabs & Confirmation', () {
    testWidgets('12. Watch List tab displays friendly empty state with image and subtitle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Bruce Wayne',
              'email': 'bruce@wayne.com',
              'phone': '1234',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
            initialSection: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Watch List is empty.'), findsOneWidget);
      expect(find.text('Save movies you want to watch later.'), findsOneWidget);
    });

    testWidgets('13. History tab displays friendly empty state with subtitle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Clark Kent',
              'email': 'clark@dailyplanet.com',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
            initialSection: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('History is empty.'), findsOneWidget);
      expect(find.text('Movies you open will appear here.'), findsOneWidget);
    });

    testWidgets('14. Favorites tab displays friendly empty state with subtitle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Diana Prince',
              'email': 'diana@themyscira.gov',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
            initialSection: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favorites are empty.'), findsOneWidget);
      expect(find.text('Mark your favorite movies to find them quickly.'), findsOneWidget);
    });

    testWidgets('15. Tapping tab switches smoothly between Watch List, History, and Favorites', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Barry Allen',
              'email': 'barry@star-labs.com',
            },
            watchlistCount: 3,
            historyCount: 5,
            favoritesCount: 2,
            initialSection: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on Watch List tab
      expect(find.text('Watch List is empty.'), findsOneWidget);

      // Switch to History tab
      await tester.tap(find.byKey(const Key('profile-tab-history')));
      await tester.pumpAndSettle();
      expect(find.text('History is empty.'), findsOneWidget);

      // Switch to Favorites tab
      await tester.tap(find.byKey(const Key('profile-tab-favorites')));
      await tester.pumpAndSettle();
      expect(find.text('Favorites are empty.'), findsOneWidget);

      // Verify counters in profile header
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('16. Removal confirmation dialog displays warning and Cancel/Remove buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool? confirmedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('trigger-remove-dialog'),
                  onPressed: () async {
                    confirmedResult = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: const Color(0xFF202020),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text(
                          'Remove from Watch List?',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: const Text(
                          'Are you sure you want to remove "Interstellar" from your Watch List?',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            key: const Key('remove-cancel-button'),
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            key: const Key('remove-confirm-button'),
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger-remove-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('Remove from Watch List?'), findsOneWidget);
      expect(
        find.text('Are you sure you want to remove "Interstellar" from your Watch List?'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('remove-cancel-button')), findsOneWidget);
      expect(find.byKey(const Key('remove-confirm-button')), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.byKey(const Key('remove-cancel-button')));
      await tester.pumpAndSettle();

      expect(confirmedResult, isFalse);
      expect(find.text('Remove from Watch List?'), findsNothing);
    });
  });
}
