import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/screens/movie_details_screen.dart';

http.Response _jsonResponse(dynamic body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _ytsMovieJson({
  required int id,
  required String title,
  int year = 2020,
  double rating = 7.5,
  List<String> genres = const ['Action', 'Thriller'],
  String summary = 'Sample movie summary',
}) =>
    {
      'id': id,
      'title': title,
      'year': year,
      'rating': rating,
      'runtime': 110,
      'genres': genres,
      'summary': summary,
      'description_full': summary,
      'medium_cover_image': 'https://example.com/$id.jpg',
      'large_cover_image': 'https://example.com/${id}_large.jpg',
    };

void main() {
  setUp(() {
    MovieRepository.clearSimilarMoviesCache();
  });

  group('MovieRepository.fetchSimilarMovies - Recommendation & Ranking Algorithm', () {
    test('excludes the current movie by ID and by title', () async {
      const currentMovie = Movie(
        id: '100',
        title: 'The Dark Knight',
        year: 2008,
        genres: ['Action', 'Crime', 'Drama'],
      );

      final candidatePool = [
        const Movie(
          id: '100', // same id
          title: 'The Dark Knight',
          year: 2008,
          genres: ['Action', 'Crime'],
        ),
        const Movie(
          id: '999', // same title, different id
          title: 'the dark knight',
          year: 2008,
          genres: ['Action', 'Crime'],
        ),
        const Movie(
          id: '101',
          title: 'Batman Begins',
          year: 2005,
          genres: ['Action', 'Crime'],
        ),
      ];

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': candidatePool
                .map((m) => _ytsMovieJson(
                      id: int.parse(m.id),
                      title: m.title,
                      year: m.year ?? 2020,
                      genres: m.genres,
                    ))
                .toList()
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      expect(results.any((m) => m.id == '100'), isFalse);
      expect(results.any((m) => m.title.toLowerCase() == 'the dark knight'), isFalse);
      expect(results.length, 1);
      expect(results.first.id, '101');
    });

    test('deduplicates movies with identical IDs from different sources', () async {
      const currentMovie = Movie(
        id: '10',
        title: 'Avengers: Endgame',
        year: 2019,
        genres: ['Action', 'Sci-Fi'],
      );

      // Suggestions endpoint and genre endpoint return overlapping movie '20'
      final client = MockClient((request) async {
        if (request.url.path.contains('movie_suggestions.json')) {
          return _jsonResponse({
            'status': 'ok',
            'data': {
              'movies': [
                _ytsMovieJson(id: 20, title: 'Avengers: Infinity War', year: 2018, genres: ['Action', 'Sci-Fi']),
                _ytsMovieJson(id: 30, title: 'Iron Man', year: 2008, genres: ['Action', 'Sci-Fi']),
              ]
            }
          });
        }
        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': [
              _ytsMovieJson(id: 20, title: 'Avengers: Infinity War', year: 2018, genres: ['Action', 'Sci-Fi']),
              _ytsMovieJson(id: 40, title: 'Captain America', year: 2016, genres: ['Action', 'Sci-Fi']),
              _ytsMovieJson(id: 50, title: 'Thor: Ragnarok', year: 2017, genres: ['Action', 'Sci-Fi']),
            ]
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      final ids = results.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'IDs must be unique');
      expect(ids.length, lessThanOrEqualTo(4));
    });

    test('displays exactly 4 movies when at least 4 relevant results are available', () async {
      const currentMovie = Movie(
        id: '10',
        title: 'Action Hero',
        year: 2020,
        genres: ['Action', 'Adventure'],
      );

      final candidatePool = List.generate(
        10,
        (i) => _ytsMovieJson(
          id: 100 + i,
          title: 'Action Hero Part ${i + 2}',
          year: 2020 + (i % 3),
          genres: ['Action', 'Adventure'],
        ),
      );

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': candidatePool}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      expect(results.length, 4, reason: 'Must display exactly 4 movies when >= 4 available');
    });

    test('never displays more than 4 movies even if limit parameter is high or more exist', () async {
      const currentMovie = Movie(
        id: '10',
        title: 'Sci-Fi Classic',
        year: 2021,
        genres: ['Sci-Fi'],
      );

      final candidatePool = List.generate(
        15,
        (i) => _ytsMovieJson(
          id: 500 + i,
          title: 'Sci-Fi Galaxy $i',
          year: 2021,
          genres: ['Sci-Fi'],
        ),
      );

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': candidatePool}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 10);

      expect(results.length, 4);
    });

    test('displays fewer than 4 movies if fewer relevant movies exist', () async {
      const currentMovie = Movie(
        id: '10',
        title: 'Rare Niche Movie',
        year: 2020,
        genres: ['Documentary'],
      );

      final candidatePool = [
        _ytsMovieJson(id: 701, title: 'Documentary One', year: 2019, genres: ['Documentary']),
        _ytsMovieJson(id: 702, title: 'Documentary Two', year: 2021, genres: ['Documentary']),
      ];

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': candidatePool}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      expect(results.length, 2);
      expect(results.map((m) => m.id), ['701', '702']);
    });

    test('returns empty list when no similar or relevant movies exist', () async {
      const currentMovie = Movie(
        id: '10',
        title: 'Unmatchable Movie',
        year: 1920,
        genres: ['NicheGenreX'],
      );

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': []}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      expect(results, isEmpty);
    });

    test('ranks by similarity: shared genres and title keywords rank higher than unrelated', () async {
      const currentMovie = Movie(
        id: '1',
        title: 'Spider-Man Homecoming',
        year: 2017,
        genres: ['Action', 'Sci-Fi', 'Adventure'],
      );

      final candidatePool = [
        _ytsMovieJson(
          id: 101,
          title: 'Spider-Man Far From Home',
          year: 2019,
          genres: ['Action', 'Sci-Fi', 'Adventure'],
          rating: 7.5,
        ),
        _ytsMovieJson(
          id: 102,
          title: 'Avengers Infinity War',
          year: 2018,
          genres: ['Action', 'Sci-Fi'],
          rating: 8.4,
        ),
        _ytsMovieJson(
          id: 103,
          title: 'Inception',
          year: 2010,
          genres: ['Action'],
          rating: 8.8,
        ),
        _ytsMovieJson(
          id: 104,
          title: 'Pride and Prejudice',
          year: 1940,
          genres: ['Romance', 'Drama'],
          rating: 7.0,
        ),
      ];

      final client = MockClient((request) async {
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': candidatePool}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final results = await repository.fetchSimilarMovies(currentMovie, limit: 4);

      expect(results.length, 3, reason: 'Pride and Prejudice has 0 similarity score and must be omitted');
      expect(results[0].title, 'Spider-Man Far From Home');
      expect(results[1].title, 'Avengers Infinity War');
      expect(results[2].title, 'Inception');
    });

    test('caches recommendation results in memory for the same movie', () async {
      const currentMovie = Movie(
        id: '55',
        title: 'Cached Movie',
        year: 2020,
        genres: ['Comedy'],
      );

      var networkCalls = 0;
      final client = MockClient((request) async {
        networkCalls++;
        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': [
              _ytsMovieJson(id: 56, title: 'Comedy Partner', year: 2020, genres: ['Comedy']),
            ]
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      final res1 = await repository.fetchSimilarMovies(currentMovie);
      expect(res1.length, 1);
      final callsAfterFirst = networkCalls;

      final res2 = await repository.fetchSimilarMovies(currentMovie);
      expect(res2.length, 1);
      expect(networkCalls, callsAfterFirst, reason: 'Second request must hit the static in-memory cache');
    });
  });

  group('MovieDetailsScreen - Similar Movies UI & Navigation Tests', () {
    setUp(() {
      MovieRepository.clearSimilarMoviesCache();
    });

    Widget createTestApp({
      required Movie movie,
      required MovieRepository repository,
    }) {
      return MaterialApp(
        home: MovieDetailsScreen(
          movie: movie,
          repository: repository,
        ),
      );
    }

    testWidgets('displays loading grid initially and resolves to 4 movie cards', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path.contains('movie_details.json')) {
          return _jsonResponse({
            'status': 'ok',
            'data': {'movie': _ytsMovieJson(id: 111, title: 'Main Movie', genres: ['Action'])}
          });
        }
        return completer.future;
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      const movie = Movie(id: '111', title: 'Main Movie', year: 2021, genres: ['Action']);

      await tester.pumpWidget(createTestApp(movie: movie, repository: repository));
      await tester.pump();
      expect(find.byKey(const Key('similar-movies-loading-grid')), findsOneWidget);

      completer.complete(_jsonResponse({
        'status': 'ok',
        'data': {
          'movies': [
            _ytsMovieJson(id: 112, title: 'Similar 1', genres: ['Action']),
            _ytsMovieJson(id: 113, title: 'Similar 2', genres: ['Action']),
            _ytsMovieJson(id: 114, title: 'Similar 3', genres: ['Action']),
            _ytsMovieJson(id: 115, title: 'Similar 4', genres: ['Action']),
          ]
        }
      }));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('similar-movies-grid')), findsOneWidget);
      expect(find.text('Similar 1'), findsOneWidget);
      expect(find.text('Similar 2'), findsOneWidget);
      expect(find.text('Similar 3'), findsOneWidget);
      expect(find.text('Similar 4'), findsOneWidget);
    });

    testWidgets('shows clean empty state when no similar movies exist', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = MockClient((request) async {
        if (request.url.path.contains('movie_details.json')) {
          return _jsonResponse({
            'status': 'ok',
            'data': {'movie': _ytsMovieJson(id: 88, title: 'Lonely Movie', genres: [])}
          });
        }
        return _jsonResponse({
          'status': 'ok',
          'data': {'movies': []}
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      const movie = Movie(id: '88', title: 'Lonely Movie', year: 2021);

      await tester.pumpWidget(createTestApp(movie: movie, repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('similar-movies-empty-state')), findsOneWidget);
      expect(find.text('No similar movies found.'), findsOneWidget);
    });

    testWidgets('shows error state on network failure and allows retry', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var shouldFail = true;
      final client = MockClient((request) async {
        if (request.url.path.contains('movie_details.json')) {
          return _jsonResponse({
            'status': 'ok',
            'data': {'movie': _ytsMovieJson(id: 99, title: 'Retry Movie', genres: ['Drama'])}
          });
        }
        if (shouldFail) {
          throw http.ClientException('Connection failed');
        }
        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': [
              _ytsMovieJson(id: 100, title: 'Drama Ally', genres: ['Drama']),
            ]
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      const movie = Movie(id: '99', title: 'Retry Movie', year: 2021, genres: ['Drama']);

      await tester.pumpWidget(createTestApp(movie: movie, repository: repository));
      await tester.pumpAndSettle();

      // Error state appears
      final errorState = find.byKey(const Key('similar-movies-error-state'));
      expect(errorState, findsOneWidget);
      expect(find.text('Could not load similar movies.'), findsOneWidget);

      // Scroll to retry button and tap it
      shouldFail = false;
      final retryBtn = find.byKey(const Key('similar-movies-retry-button'));
      await tester.scrollUntilVisible(
        retryBtn,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // Successfully loads similar movie
      expect(find.byKey(const Key('similar-movies-grid')), findsOneWidget);
      expect(find.text('Drama Ally'), findsOneWidget);
    });

    testWidgets('tapping similar movie opens its MovieDetailsScreen, and back button returns', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = MockClient((request) async {
        final path = request.url.path;
        final movieId = request.url.queryParameters['movie_id'];

        if (path.contains('movie_details.json')) {
          if (movieId == '200') {
            return _jsonResponse({
              'status': 'ok',
              'data': {'movie': _ytsMovieJson(id: 200, title: 'Destination Movie', genres: ['Action'])}
            });
          }
          return _jsonResponse({
            'status': 'ok',
            'data': {'movie': _ytsMovieJson(id: 1, title: 'Source Movie', genres: ['Action'])}
          });
        }

        if (movieId == '200') {
          return _jsonResponse({
            'status': 'ok',
            'data': {
              'movies': [
                _ytsMovieJson(id: 300, title: 'Third Movie', year: 2023, genres: ['Action']),
              ]
            }
          });
        }

        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': [
              _ytsMovieJson(id: 200, title: 'Destination Movie', year: 2022, genres: ['Action']),
            ]
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      const sourceMovie = Movie(id: '1', title: 'Source Movie', year: 2020, genres: ['Action']);

      await tester.pumpWidget(createTestApp(movie: sourceMovie, repository: repository));
      await tester.pumpAndSettle();

      // Ensure Destination Movie is in similar movies grid
      expect(find.text('Destination Movie'), findsOneWidget);

      // Scroll to card and tap it
      final destinationCard = find.byKey(const Key('similar-movie-card-200'));
      await tester.scrollUntilVisible(
        destinationCard,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(destinationCard);
      await tester.pumpAndSettle();

      // Now the active screen displays Destination Movie
      expect(find.text('Destination Movie'), findsWidgets);

      // Press back button
      final backButton = find.byKey(const Key('movie-details-back-button'));
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // We are back at Source Movie
      expect(find.text('Source Movie'), findsOneWidget);
    });

    testWidgets('prevents duplicate navigation from rapid double taps', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = MockClient((request) async {
        if (request.url.path.contains('movie_details.json')) {
          return _jsonResponse({
            'status': 'ok',
            'data': {'movie': _ytsMovieJson(id: 1, title: 'Origin Movie', genres: ['Action'])}
          });
        }
        return _jsonResponse({
          'status': 'ok',
          'data': {
            'movies': [
              _ytsMovieJson(id: 50, title: 'Fast Tap Target', genres: ['Action']),
            ]
          }
        });
      });

      final repository = MovieRepository(apiService: YtsApiService(client: client));
      const movie = Movie(id: '1', title: 'Origin Movie', genres: ['Action']);

      await tester.pumpWidget(createTestApp(movie: movie, repository: repository));
      await tester.pumpAndSettle();

      final targetCard = find.byKey(const Key('similar-movie-card-50'));
      await tester.scrollUntilVisible(
        targetCard,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Rapidly tap the card twice
      await tester.tap(targetCard);
      await tester.tap(targetCard, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Only one new MovieDetailsScreen should be pushed on the Navigator stack
      final backButton = find.byKey(const Key('movie-details-back-button'));
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // We should be immediately back to Origin Movie (not a duplicate Destination screen)
      expect(find.text('Origin Movie'), findsOneWidget);
    });
  });
}
