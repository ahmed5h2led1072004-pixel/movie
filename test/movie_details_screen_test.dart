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

http.Response _detailsResponse(Map<String, dynamic> movie) => http.Response(
      jsonEncode({
        'status': 'ok',
        'status_message': 'Query was successful',
        'data': {'movie': movie},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _sampleMovieDetailsJson({
  int id = 42,
  String title = 'Inception',
  int year = 2010,
  double rating = 8.8,
  int runtime = 148,
  String language = 'en',
  String trailerCode = 'YoHD9XEInc0',
  List<String> genres = const ['Action', 'Sci-Fi'],
  String description = 'A thief who steals corporate secrets through dream-sharing.',
  List<Map<String, dynamic>>? cast,
  List<Map<String, dynamic>>? torrents,
  List<String>? screenshots,
}) => {
      'id': id,
      'title': title,
      'year': year,
      'rating': rating,
      'runtime': runtime,
      'language': language,
      'genres': genres,
      'description_full': description,
      'yt_trailer_code': trailerCode,
      'background_image': 'https://yts.mx/assets/images/movies/inception_2010/background.jpg',
      'medium_cover_image': 'https://yts.mx/assets/images/movies/inception_2010/medium-cover.jpg',
      'large_cover_image': 'https://yts.mx/assets/images/movies/inception_2010/large-cover.jpg',
      'cast': cast ??
          [
            {'name': 'Leonardo DiCaprio', 'character_name': 'Cobb'},
            {'name': 'Joseph Gordon-Levitt', 'character_name': 'Arthur'},
          ],
      'torrents': torrents ??
          [
            {'quality': '720p'},
            {'quality': '1080p'},
            {'quality': '2160p'},
          ],
      if (screenshots != null) ...{
        'screenshots': screenshots,
      },
    };

Future<void> _pumpMovieDetails(
  WidgetTester tester, {
  required Movie movie,
  required http.Client client,
  Future<void> Function(BuildContext, String)? onWatchTrailer,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final repository = MovieRepository(apiService: YtsApiService(client: client));
  await tester.pumpWidget(
    MaterialApp(
      home: MovieDetailsScreen(
        movie: movie,
        repository: repository,
        onWatchTrailer: onWatchTrailer,
      ),
    ),
  );
}

void main() {
  group('YtsApiService.fetchMovieDetails', () {
    test('sends request with correct query parameters and parses details', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return _detailsResponse(_sampleMovieDetailsJson());
      });

      final service = YtsApiService(client: client);
      final movie = await service.fetchMovieDetails('42');

      expect(requestedUri.path, contains('movie_details.json'));
      expect(requestedUri.queryParameters['movie_id'], '42');
      expect(requestedUri.queryParameters['with_images'], 'true');
      expect(requestedUri.queryParameters['with_cast'], 'true');

      expect(movie.id, '42');
      expect(movie.title, 'Inception');
      expect(movie.year, 2010);
      expect(movie.rating, 8.8);
      expect(movie.runtime, 148);
      expect(movie.language, 'en');
      expect(movie.trailerCode, 'YoHD9XEInc0');
      expect(movie.genres, ['Action', 'Sci-Fi']);
      expect(movie.description, contains('dream-sharing'));
      expect(movie.availableQualities, ['720p', '1080p', '2160p']);
      expect(movie.cast, ['Leonardo DiCaprio as Cobb', 'Joseph Gordon-Levitt as Arthur']);
    });

    test('handles missing optional fields safely', () async {
      final client = MockClient((request) async {
        return _detailsResponse({
          'id': 99,
          'title': 'Minimal Movie',
        });
      });

      final service = YtsApiService(client: client);
      final movie = await service.fetchMovieDetails('99');

      expect(movie.id, '99');
      expect(movie.title, 'Minimal Movie');
      expect(movie.year, isNull);
      expect(movie.rating, isNull);
      expect(movie.runtime, isNull);
      expect(movie.language, isNull);
      expect(movie.trailerCode, isNull);
      expect(movie.genres, isEmpty);
      expect(movie.cast, isEmpty);
      expect(movie.availableQualities, isEmpty);
      expect(movie.screenshots, isEmpty);
    });

    test('throws YtsApiException on HTTP error', () async {
      final client = MockClient((request) async => http.Response('Server error', 500));
      final service = YtsApiService(client: client);

      expect(
        () => service.fetchMovieDetails('123'),
        throwsA(isA<YtsApiException>()),
      );
    });

    test('throws YtsApiException on non-ok API status', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'status': 'error', 'status_message': 'Movie not found'}),
            200,
          ));
      final service = YtsApiService(client: client);

      expect(
        () => service.fetchMovieDetails('123'),
        throwsA(isA<YtsApiException>()),
      );
    });
  });

  group('MovieRepository.fetchMovieDetails', () {
    test('returns remote movie details on success', () async {
      final client = MockClient((request) async => _detailsResponse(_sampleMovieDetailsJson()));
      final repository = MovieRepository(apiService: YtsApiService(client: client));

      const fallback = Movie(id: '42', title: 'Fallback Title');
      final result = await repository.fetchMovieDetails('42', fallbackMovie: fallback);

      expect(result.usedFallback, isFalse);
      expect(result.error, isNull);
      expect(result.movie.title, 'Inception');
      expect(result.movie.runtime, 148);
    });

    test('returns fallback movie with usedFallback=true on API error', () async {
      final client = MockClient((request) async => throw http.ClientException('Network down'));
      final repository = MovieRepository(apiService: YtsApiService(client: client));

      const fallback = Movie(id: '42', title: 'Fallback Title', year: 2010);
      final result = await repository.fetchMovieDetails('42', fallbackMovie: fallback);

      expect(result.usedFallback, isTrue);
      expect(result.error, isNotNull);
      expect(result.movie.title, 'Fallback Title');
      expect(result.movie.year, 2010);
    });

    test('returns fallback when apiService is null', () async {
      const repository = MovieRepository(apiService: null);
      const fallback = Movie(id: '42', title: 'Offline Fallback');
      final result = await repository.fetchMovieDetails('42', fallbackMovie: fallback);

      expect(result.usedFallback, isTrue);
      expect(result.movie.title, 'Offline Fallback');
    });
  });

  group('MovieDetailsScreen Widget Tests', () {
    testWidgets('displays fallback movie immediately and updates when remote details arrive', (
      tester,
    ) async {
      final completer = Completer<http.Response>();
      final client = MockClient((request) => completer.future);

      const initialMovie = Movie(
        id: '42',
        title: 'Initial Title',
        year: 2010,
        description: 'Initial summary',
      );

      await _pumpMovieDetails(tester, movie: initialMovie, client: client);

      // Verify initial fallback is visible immediately
      expect(find.text('Initial Title'), findsOneWidget);
      expect(find.text('Initial summary'), findsOneWidget);

      // Complete the remote details response
      completer.complete(_detailsResponse(_sampleMovieDetailsJson(
        title: 'Enhanced Title',
        description: 'Detailed remote overview from API',
        runtime: 148,
      )));
      await tester.pumpAndSettle();

      // Screen updates with remote details
      expect(find.text('Enhanced Title'), findsOneWidget);
      expect(find.text('Detailed remote overview from API'), findsOneWidget);
      expect(find.text('148 min'), findsOneWidget);
      expect(find.text('Quality:'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('2160p'), findsOneWidget);
    });

    testWidgets('renders safely with missing optional fields', (tester) async {
      final client = MockClient((request) async => _detailsResponse({
            'id': 101,
            'title': 'Barebones Movie',
          }));

      const bareMovie = Movie(id: '101', title: 'Barebones Movie');
      await _pumpMovieDetails(tester, movie: bareMovie, client: client);
      await tester.pumpAndSettle();

      expect(find.text('Barebones Movie'), findsOneWidget);
      expect(find.text('No summary available yet.'), findsOneWidget);
      expect(find.text('—'), findsWidgets); // for missing runtime/rating
    });

    testWidgets('shows trailer buttons when trailer code exists and triggers callback', (
      tester,
    ) async {
      final client = MockClient((request) async => _detailsResponse(_sampleMovieDetailsJson(
            trailerCode: 'YoHD9XEInc0',
          )));

      const movieWithTrailer = Movie(
        id: '42',
        title: 'Inception',
        trailerCode: 'YoHD9XEInc0',
      );

      String? tappedTrailerCode;
      await _pumpMovieDetails(
        tester,
        movie: movieWithTrailer,
        client: client,
        onWatchTrailer: (context, code) async {
          tappedTrailerCode = code;
        },
      );
      await tester.pumpAndSettle();

      // Both the hero play button and the action button are present
      final playButton = find.byKey(const Key('watch-trailer-play-button'));
      final actionButton = find.byKey(const Key('watch-trailer-action-button'));
      expect(playButton, findsOneWidget);
      expect(actionButton, findsOneWidget);

      // Tap the action button
      await tester.tap(actionButton);
      await tester.pump();
      expect(tappedTrailerCode, 'YoHD9XEInc0');

      // Tap the hero play button
      tappedTrailerCode = null;
      await tester.tap(playButton);
      await tester.pump();
      expect(tappedTrailerCode, 'YoHD9XEInc0');
    });

    testWidgets('hides trailer buttons when no trailer code is available', (tester) async {
      final client = MockClient((request) async => _detailsResponse({
            'id': 55,
            'title': 'No Trailer Movie',
            'yt_trailer_code': null,
          }));

      const movieWithoutTrailer = Movie(
        id: '55',
        title: 'No Trailer Movie',
      );

      await _pumpMovieDetails(tester, movie: movieWithoutTrailer, client: client);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('watch-trailer-play-button')), findsNothing);
      expect(find.byKey(const Key('watch-trailer-action-button')), findsNothing);
    });

    testWidgets('API error displays retry banner and fallback movie remains visible', (
      tester,
    ) async {
      var detailsCallCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('movie_details.json')) {
          detailsCallCount++;
          if (detailsCallCount == 1) {
            throw http.ClientException('Failed to connect');
          }
          return _detailsResponse(_sampleMovieDetailsJson(
            title: 'Recovered Movie',
            runtime: 120,
          ));
        }
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {'movies': []}
          }),
          200,
        );
      });

      const fallbackMovie = Movie(
        id: '77',
        title: 'Offline Movie',
        year: 2022,
        description: 'Cached description',
      );

      await _pumpMovieDetails(tester, movie: fallbackMovie, client: client);
      await tester.pumpAndSettle();

      // Fallback is still fully visible
      expect(find.text('Offline Movie'), findsOneWidget);
      expect(find.text('Cached description'), findsOneWidget);

      // Retry banner is displayed
      final retryButton = find.byKey(const Key('details-retry-button'));
      expect(retryButton, findsOneWidget);

      // Tapping retry triggers second request and recovers
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(detailsCallCount, 2);
      expect(find.text('Recovered Movie'), findsOneWidget);
      expect(find.text('120 min'), findsOneWidget);
      expect(find.byKey(const Key('details-retry-button')), findsNothing);
    });
  });
}
