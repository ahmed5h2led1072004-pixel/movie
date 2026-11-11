import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/screens/browse_screen.dart';
import 'package:movies/screens/home_screen.dart';

http.Response _moviesResponse(List<Map<String, dynamic>> movies) => http.Response(
      jsonEncode({
        'status': 'ok',
        'status_message': 'Query was successful',
        'data': {'movies': movies},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _movieJson(
  String id,
  String title, {
  int year = 2023,
  double rating = 8.5,
  List<String> genres = const ['Action'],
}) =>
    {
      'id': id,
      'title': title,
      'year': year,
      'rating': rating,
      'genres': genres,
      'medium_cover_image': 'https://yts.mx/assets/images/movies/$id/medium-cover.jpg',
    };

List<Map<String, dynamic>> _generateMovies(int count, {String prefix = 'Movie', int startId = 1}) =>
    List.generate(
      count,
      (i) => _movieJson('${startId + i}', '$prefix ${startId + i}', year: 2020 + (i % 4)),
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  required http.Client client,
  RouteFactory? onGenerateRoute,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final repository = MovieRepository(apiService: YtsApiService(client: client));
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(repository: repository),
      onGenerateRoute: onGenerateRoute ??
          (settings) {
            if (settings.name == '/browse') {
              final initialGenre = settings.arguments is String
                  ? settings.arguments! as String
                  : settings.arguments is Map
                      ? (settings.arguments as Map)['genre']?.toString()
                      : null;
              final initialSort = settings.arguments is Map
                  ? (settings.arguments as Map)['sortBy']?.toString()
                  : null;
              return MaterialPageRoute<void>(
                builder: (_) => BrowseScreen(
                  initialGenre: initialGenre,
                  initialSort: initialSort,
                  repository: repository,
                ),
              );
            }
            return null;
          },
    ),
  );
}

void main() {
  group('HomeScreen Popular Movies', () {
    testWidgets('Home initially fetches 20 popular movies sorted by download_count', (
      tester,
    ) async {
      final requestedUrls = <Uri>[];
      final client = MockClient((request) async {
        requestedUrls.add(request.url);
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          return _moviesResponse(_generateMovies(20, prefix: 'Popular Movie'));
        }
        return _moviesResponse(_generateMovies(5, prefix: 'Latest Movie'));
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      final popularRequest = requestedUrls.firstWhere(
        (uri) => uri.queryParameters['sort_by'] == 'download_count',
      );

      expect(popularRequest.queryParameters['limit'], '20');
      expect(popularRequest.queryParameters['page'], '1');
      expect(popularRequest.queryParameters['sort_by'], 'download_count');

      expect(find.byKey(const Key('home-popular-list-view')), findsOneWidget);
      expect(find.text('Popular Movie 1'), findsOneWidget);
      expect(find.text('Popular Movie 2'), findsOneWidget);
    });

    testWidgets('displays movie titles, release years, and ratings', (tester) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          return _moviesResponse([
            _movieJson('99', 'Spider-Man Popular', year: 2021, rating: 8.9),
          ]);
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      expect(find.text('Spider-Man Popular'), findsOneWidget);
      expect(find.text('2021'), findsOneWidget);
      expect(find.text('8.9'), findsOneWidget);
    });

    testWidgets('loads next page and appends new movies without replacing existing ones', (
      tester,
    ) async {
      final requestedPages = <int>[];
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          requestedPages.add(page);
          if (page == 1) {
            return _moviesResponse(_generateMovies(20, prefix: 'Page1 Movie', startId: 1));
          } else if (page == 2) {
            return _moviesResponse(_generateMovies(20, prefix: 'Page2 Movie', startId: 21));
          } else {
            return _moviesResponse([]);
          }
        }
        return _moviesResponse(_generateMovies(5, prefix: 'Latest'));
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      expect(find.text('Page1 Movie 1'), findsOneWidget);
      expect(requestedPages, contains(1));

      // Scroll near the end of the horizontal popular movies list
      final popularListFinder = find.byKey(const Key('home-popular-list-view'));
      await tester.drag(popularListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();

      expect(requestedPages, contains(2));

      // Drag again to scroll towards the end of the newly appended items
      await tester.drag(popularListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Page2 Movie 40'), findsOneWidget);
    });

    testWidgets('removes duplicate movie IDs when appending', (tester) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          if (page == 1) {
            return _moviesResponse(_generateMovies(20, prefix: 'Page1 Movie', startId: 1));
          } else {
            return _moviesResponse([
              _movieJson('20', 'Duplicate Movie 20'), // ID 20 was in page 1
              _movieJson('99', 'Unique Movie 99'),
            ]);
          }
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      expect(find.text('Page1 Movie 1'), findsOneWidget);

      final popularListFinder = find.byKey(const Key('home-popular-list-view'));
      await tester.drag(popularListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();

      // Only the first occurrence was preserved, duplicate was rejected
      expect(find.text('Duplicate Movie 20'), findsNothing);

      // Drag to bring Unique Movie 99 into view
      await tester.drag(popularListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Unique Movie 99'), findsOneWidget);
    });

    testWidgets('prevents multiple simultaneous pagination requests', (tester) async {
      var page2Requests = 0;
      final page2Completer = Completer<http.Response>();

      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          if (page == 1) {
            return _moviesResponse(_generateMovies(20, prefix: 'Movie', startId: 1));
          } else if (page == 2) {
            page2Requests++;
            return page2Completer.future;
          }
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      final popularListFinder = find.byKey(const Key('home-popular-list-view'));
      // Drag once to trigger pagination
      await tester.drag(popularListFinder, const Offset(-3500, 0));
      await tester.pump();

      expect(page2Requests, 1);

      // Drag again while request is in flight
      await tester.drag(popularListFinder, const Offset(-500, 0));
      await tester.pump();

      // Must still be 1 request
      expect(page2Requests, 1);

      // Finish page 2
      page2Completer.complete(
        _moviesResponse(_generateMovies(10, prefix: 'Page2 Movie', startId: 21)),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('handles empty API response with empty state', (tester) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          return _moviesResponse([]);
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-popular-empty-list')), findsOneWidget);
      expect(find.text('No popular movies found.'), findsOneWidget);
    });

    testWidgets('handles API error on initial load and allows retry', (tester) async {
      var callCount = 0;
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          callCount++;
          if (callCount == 1) {
            throw http.ClientException('Server unavailable');
          }
          return _moviesResponse([_movieJson('1', 'Recovered Popular Movie')]);
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      // Error state is shown
      expect(find.byKey(const Key('home-popular-error-list')), findsOneWidget);
      expect(find.text('Could not load popular movies.'), findsOneWidget);

      final retryButton = find.byKey(const Key('home-popular-retry-button'));
      expect(retryButton, findsOneWidget);

      // Tap retry
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(callCount, 2);
      expect(find.text('Recovered Popular Movie'), findsOneWidget);
      expect(find.byKey(const Key('home-popular-error-list')), findsNothing);
    });

    testWidgets('existing carousel and Action section still work', (tester) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['sort_by'] == 'date_added') {
          return _moviesResponse([
            _movieJson('100', 'Featured Carousel Movie', genres: ['Action']),
            _movieJson('101', 'Action Section Movie', genres: ['Action']),
          ]);
        }
        return _moviesResponse([]);
      });

      await _pumpHome(tester, client: client);
      await tester.pumpAndSettle();

      expect(find.text('Featured Carousel Movie'), findsWidgets);
      expect(find.byKey(const Key('home-action-button')), findsOneWidget);
      expect(find.byKey(const Key('home-see-more-button')), findsOneWidget);
    });

    testWidgets('See All navigation opens Browse screen with popular sorting', (tester) async {
      Object? capturedArguments;
      final client = MockClient((request) async => _moviesResponse([]));

      await _pumpHome(
        tester,
        client: client,
        onGenerateRoute: (settings) {
          if (settings.name == '/browse') {
            capturedArguments = settings.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Browse Screen Loaded')),
            );
          }
          return null;
        },
      );
      await tester.pumpAndSettle();

      final seeAllButton = find.byKey(const Key('home-popular-see-all-button'));
      expect(seeAllButton, findsOneWidget);

      await tester.tap(seeAllButton);
      await tester.pumpAndSettle();

      expect(find.text('Browse Screen Loaded'), findsOneWidget);
      expect(capturedArguments, isA<Map<String, dynamic>>());
      final mapArgs = capturedArguments as Map<String, dynamic>;
      expect(mapArgs['sortBy'], 'download_count');
    });
  });
}
