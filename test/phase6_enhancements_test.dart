// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/screens/archive_test_screen.dart';
import 'package:movies/screens/browse_screen.dart';
import 'package:movies/screens/home_screen.dart';
import 'package:movies/widgets/archive_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _textureCounter = 1;
  final Map<int, StreamController<VideoEvent>> _controllers = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int textureId) async {
    _controllers.remove(textureId)?.close();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _textureCounter++;
    final controller = StreamController<VideoEvent>.broadcast();
    _controllers[id] = controller;
    Timer.run(() {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 90),
          size: const Size(1920, 1080),
        ),
      );
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _controllers[textureId]?.stream ?? const Stream.empty();
  }

  @override
  Widget buildView(int textureId) {
    return const SizedBox(width: 320, height: 180);
  }

  @override
  Future<void> play(int textureId) async {
    _controllers[textureId]?.add(
      VideoEvent(eventType: VideoEventType.isPlayingStateUpdate, isPlaying: true),
    );
  }

  @override
  Future<void> pause(int textureId) async {
    _controllers[textureId]?.add(
      VideoEvent(eventType: VideoEventType.isPlayingStateUpdate, isPlaying: false),
    );
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {}
}

http.Response _ytsResponse(List<Map<String, dynamic>> movies) => http.Response(
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
  double rating = 8.0,
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

List<Map<String, dynamic>> _generateActionMovies(int count, {int startId = 1}) =>
    List.generate(
      count,
      (i) => _movieJson(
        '${startId + i}',
        'Action Movie ${startId + i}',
        year: 2020 + (i % 4),
        genres: ['Action', 'Thriller'],
      ),
    );

Future<void> _pumpHomeScreen(
  WidgetTester tester, {
  required http.Client client,
  RouteFactory? onGenerateRoute,
}) async {
  tester.view.physicalSize = const Size(800, 2200);
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
                  : null;
              return MaterialPageRoute<void>(
                builder: (_) => BrowseScreen(
                  initialGenre: initialGenre,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
  });

  group('Phase 6 — Home Screen Multi-Movie Action Section', () {
    testWidgets('Action section displays multiple movies (at least 10)', (tester) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['genre'] == 'Action') {
          return _ytsResponse(_generateActionMovies(15, startId: 100));
        }
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          return _ytsResponse([_movieJson('1', 'Popular Film')]);
        }
        return _ytsResponse([_movieJson('2', 'Featured Film')]);
      });

      await _pumpHomeScreen(tester, client: client);
      await tester.pumpAndSettle();

      // Action list view is displayed
      expect(find.byKey(const Key('home-action-list-view')), findsOneWidget);

      // Verify multiple action movies are rendered
      expect(find.text('Action Movie 100'), findsOneWidget);
      expect(find.text('Action Movie 101'), findsOneWidget);
      expect(find.text('Action Movie 102'), findsOneWidget);
      expect(find.text('Action Movie 103'), findsOneWidget);
    });

    testWidgets('Action section supports horizontal swiping and scroll pagination', (tester) async {
      final requestedPages = <int>[];
      final client = MockClient((request) async {
        if (request.url.queryParameters['genre'] == 'Action') {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          requestedPages.add(page);
          if (page == 1) {
            return _ytsResponse(_generateActionMovies(20, startId: 1));
          } else {
            return _ytsResponse(_generateActionMovies(10, startId: 21));
          }
        }
        return _ytsResponse([]);
      });

      await _pumpHomeScreen(tester, client: client);
      await tester.pumpAndSettle();

      expect(requestedPages, contains(1));
      expect(find.text('Action Movie 1'), findsOneWidget);

      final actionListFinder = find.byKey(const Key('home-action-list-view'));
      // Drag horizontally to scroll near the end of Action list
      await tester.drag(actionListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();

      expect(requestedPages, contains(2));

      // Drag to the end of the newly appended items
      await tester.drag(actionListFinder, const Offset(-3500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Action Movie 30'), findsOneWidget);
    });

    testWidgets('Action section handles API error independently without affecting Popular', (
      tester,
    ) async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['genre'] == 'Action') {
          throw http.ClientException('Network timeout for Action');
        }
        if (request.url.queryParameters['sort_by'] == 'download_count') {
          return _ytsResponse([_movieJson('99', 'Safe Popular Movie')]);
        }
        return _ytsResponse([]);
      });

      await _pumpHomeScreen(tester, client: client);
      await tester.pumpAndSettle();

      // Popular movies loaded successfully
      expect(find.text('Safe Popular Movie'), findsOneWidget);

      // Action movies displays error card with retry button
      expect(find.byKey(const Key('home-action-error-list')), findsOneWidget);
      expect(find.byKey(const Key('home-action-retry-button')), findsOneWidget);
    });

    testWidgets('Action See More button navigates to Browse with Action genre selected', (
      tester,
    ) async {
      Object? capturedArgs;
      final client = MockClient((request) async => _ytsResponse([]));

      await _pumpHomeScreen(
        tester,
        client: client,
        onGenerateRoute: (settings) {
          if (settings.name == '/browse') {
            capturedArgs = settings.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Browse Opened')),
            );
          }
          return null;
        },
      );
      await tester.pumpAndSettle();

      final seeMoreBtn = find.byKey(const Key('home-see-more-button'));
      expect(seeMoreBtn, findsOneWidget);

      await tester.tap(seeMoreBtn);
      await tester.pumpAndSettle();

      expect(find.text('Browse Opened'), findsOneWidget);
      expect(capturedArgs, 'Action');
    });
  });

  group('Phase 6 — Expanded Internet Archive Catalog & Pagination', () {
    test('InternetArchiveMovie parses runtime in seconds and formatted string', () {
      final m1 = InternetArchiveMovie.fromSearchDoc({
        'identifier': 'test-film-1',
        'title': 'Test Movie 1',
        'runtime': '01:30:00',
      });
      expect(m1.durationSeconds, 5400.0);
      expect(m1.runtimeFormatted, '1h 30m');

      final m2 = InternetArchiveMovie.fromSearchDoc({
        'identifier': 'test-film-2',
        'title': 'Test Movie 2',
        'runtime': '45:12',
      });
      expect(m2.durationSeconds, 2712.0);
      expect(m2.runtimeFormatted, '45m');
    });

    testWidgets('ArchiveTestScreen loads 20 movies initially and loads next page on Load More', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final requestedPages = <int>[];
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('advancedsearch.php')) {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          requestedPages.add(page);
          final docs = List.generate(
            20,
            (i) => {
              'identifier': 'ia-film-${page * 100 + i}',
              'title': 'Archive Classic ${page * 100 + i}',
              'year': 1930 + (i % 20),
              'publicdate': '2024-01-01T00:00:00Z',
              'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
              'runtime': '1:20:00',
            },
          );
          return http.Response(
            jsonEncode({
              'responseHeader': {'status': 0},
              'response': {'docs': docs},
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = InternetArchiveService(client: mockClient);
      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveTestScreen(archiveService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedPages, contains(1));
      expect(find.text('Archive Classic 100'), findsOneWidget);
      expect(find.text('Archive Classic 101'), findsOneWidget);

      // Scroll down to trigger pagination
      await tester.drag(find.byType(ListView), const Offset(0, -3500));
      await tester.pumpAndSettle();

      expect(requestedPages, contains(2));
    });

    testWidgets('ArchiveTestScreen search and genre filter triggers filtered search', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final queries = <String>[];
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('advancedsearch.php')) {
          queries.add(request.url.queryParameters['q'] ?? '');
          return http.Response(
            jsonEncode({
              'responseHeader': {'status': 0},
              'response': {
                'docs': [
                  {
                    'identifier': 'nosferatu-1922',
                    'title': 'Nosferatu (1922)',
                    'year': 1922,
                    'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
                  }
                ]
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = InternetArchiveService(client: mockClient);
      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveTestScreen(archiveService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Submit search query
      final searchField = find.byKey(const Key('archive-search-field'));
      await tester.enterText(searchField, 'Nosferatu');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Nosferatu (1922)'), findsOneWidget);
      expect(queries.any((q) => q.contains('Nosferatu')), isTrue);

      // Select Horror genre chip
      final horrorChip = find.byKey(const Key('archive-genre-chip-Horror'));
      expect(horrorChip, findsOneWidget);
      await tester.tap(horrorChip);
      await tester.pumpAndSettle();

      expect(queries.any((q) => q.contains('Horror')), isTrue);
    });
  });

  group('Phase 6 — Fullscreen Landscape Video Player', () {
    testWidgets('ArchiveVideoPlayer exposes fullscreen button and opens landscape player', (
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
          home: Scaffold(
            body: ArchiveVideoPlayer(
              videoUrl: 'https://archive.org/download/sample/movie.mp4',
              title: 'Nosferatu Fullscreen Test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fullscreen button is visible in controls
      final fsBtn = find.byKey(const Key('player-fullscreen-button'));
      expect(fsBtn, findsOneWidget);

      // Tap fullscreen button
      await tester.tap(fsBtn);
      await tester.pumpAndSettle();

      // ArchiveFullscreenVideoPage is now active
      expect(find.byType(ArchiveFullscreenVideoPage), findsOneWidget);
      expect(find.text('Nosferatu Fullscreen Test'), findsWidgets);

      // Fullscreen playback controls exist
      expect(find.byKey(const Key('fullscreen-play-pause-button')), findsOneWidget);
      expect(find.byKey(const Key('fullscreen-seek-forward-button')), findsOneWidget);
      expect(find.byKey(const Key('fullscreen-seek-backward-button')), findsOneWidget);
      expect(find.byKey(const Key('fullscreen-exit-button')), findsOneWidget);

      // Tap exit button
      await tester.tap(find.byKey(const Key('fullscreen-exit-button')));
      await tester.pumpAndSettle();

      // Successfully returned from fullscreen back to inline player
      expect(find.byType(ArchiveFullscreenVideoPage), findsNothing);
      expect(find.byType(ArchiveVideoPlayer), findsOneWidget);
    });

    testWidgets('ArchiveVideoPlayer inline seek buttons seek relative duration', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArchiveVideoPlayer(
              videoUrl: 'https://archive.org/download/sample/movie.mp4',
              title: 'Seek Test Movie',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final seekFwd = find.byKey(const Key('player-seek-forward-button'));
      final seekBwd = find.byKey(const Key('player-seek-backward-button'));

      expect(seekFwd, findsOneWidget);
      expect(seekBwd, findsOneWidget);

      await tester.tap(seekFwd);
      await tester.pump();
      await tester.tap(seekBwd);
      await tester.pump();
    });
  });
}
