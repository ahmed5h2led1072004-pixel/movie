import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/screens/browse_screen.dart';

http.Response _response(List<Map<String, dynamic>> movies) => http.Response(
  jsonEncode({
    'status': 'ok',
    'data': {'movies': movies},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _movie(
  String id,
  String title, {
  String genre = 'Action',
  int year = 2020,
  double rating = 8.0,
}) => {
  'id': id,
  'title': title,
  'year': year,
  'rating': rating,
  'genres': [genre],
};

Future<void> _pumpBrowse(
  WidgetTester tester, {
  required http.Client client,
  String? initialGenre,
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
      home: BrowseScreen(
        initialGenre: initialGenre,
        repository: repository,
      ),
    ),
  );
}

void main() {
  testWidgets('initial load requests first genre and default sort from YTS', (
    tester,
  ) async {
    final requestedUrls = <Uri>[];
    final client = MockClient((request) async {
      requestedUrls.add(request.url);
      return _response([_movie('101', 'Gladiator')]);
    });

    await _pumpBrowse(tester, client: client);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(requestedUrls, hasLength(1));
    expect(requestedUrls.first.queryParameters['genre'], 'Action');
    expect(requestedUrls.first.queryParameters['sort_by'], 'date_added');
    expect(requestedUrls.first.queryParameters['page'], '1');
    expect(requestedUrls.first.queryParameters['limit'], '20');
    expect(find.text('Gladiator'), findsOneWidget);
  });

  testWidgets('switching genre chip triggers remote request with selected genre', (
    tester,
  ) async {
    final requestedGenres = <String?>[];
    final client = MockClient((request) async {
      final genre = request.url.queryParameters['genre'];
      requestedGenres.add(genre);
      return _response([_movie('102', '$genre Film')]);
    });

    await _pumpBrowse(tester, client: client);
    await tester.pumpAndSettle();
    expect(requestedGenres, ['Action']);
    expect(find.text('Action Film'), findsOneWidget);

    await tester.tap(find.text('Adventure'));
    await tester.pumpAndSettle();

    expect(requestedGenres, ['Action', 'Adventure']);
    expect(find.text('Adventure Film'), findsOneWidget);
  });

  testWidgets('changing sort dropdown triggers remote request with sort parameter', (
    tester,
  ) async {
    final requestedSorts = <String?>[];
    final client = MockClient((request) async {
      requestedSorts.add(request.url.queryParameters['sort_by']);
      return _response([_movie('103', 'Top Movie')]);
    });

    await _pumpBrowse(tester, client: client);
    await tester.pumpAndSettle();
    expect(requestedSorts, ['date_added']);

    await tester.tap(find.byKey(const Key('browse-sort-dropdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Top Rated').last);
    await tester.pumpAndSettle();

    expect(requestedSorts, ['date_added', 'rating']);
  });

  testWidgets('pagination loads next page and appends new movies', (
    tester,
  ) async {
    final requestedPages = <String?>[];
    final client = MockClient((request) async {
      final page = request.url.queryParameters['page'];
      requestedPages.add(page);
      if (page == '1') {
        final list = List.generate(
          20,
          (i) => _movie('$i', 'Action Movie $i'),
        );
        return _response(list);
      }
      return _response([_movie('999', 'Page 2 Special')]);
    });

    await _pumpBrowse(tester, client: client);
    await tester.pumpAndSettle();

    expect(requestedPages, ['1']);
    expect(find.text('Action Movie 0'), findsOneWidget);

    // Scroll near the bottom to trigger next page load
    await tester.drag(find.byType(GridView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(requestedPages, ['1', '2']);

    // Drag again to reveal the newly appended page 2 items
    await tester.drag(find.byType(GridView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 Special'), findsOneWidget);
  });

  testWidgets('successful empty API results show empty state without local fallback', (
    tester,
  ) async {
    final client = MockClient((request) async => _response(const []));

    await _pumpBrowse(tester, client: client);
    await tester.pumpAndSettle();

    expect(
      find.text('No movies available in this genre yet.'),
      findsOneWidget,
    );
    expect(find.text('Black Widow'), findsNothing);
  });

  testWidgets('genuine API failure for genre with local movies preserves fallback', (
    tester,
  ) async {
    final client = MockClient((request) async {
      throw http.ClientException('offline', request.url);
    });

    await _pumpBrowse(tester, client: client, initialGenre: 'Action');
    await tester.pumpAndSettle();

    expect(find.text('Black Widow'), findsOneWidget);
    expect(find.text('Iron Man 3'), findsOneWidget);
    expect(find.text('Joker'), findsNothing);
    expect(
      find.text('Could not load online movies. Showing saved movies.'),
      findsOneWidget,
    );
  });

  testWidgets('genuine API failure for genre without local movies shows error and retry', (
    tester,
  ) async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      if (attempts == 1) {
        throw http.ClientException('offline', request.url);
      }
      return _response([_movie('301', 'Toy Story', genre: 'Animation')]);
    });

    await _pumpBrowse(tester, client: client, initialGenre: 'Animation');
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to load movies. Please check your connection.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('browse-retry-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('browse-retry-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Toy Story'), findsOneWidget);
  });

  testWidgets('outdated delayed responses cannot replace newer genre results', (
    tester,
  ) async {
    final actionCompleter = Completer<http.Response>();
    final adventureCompleter = Completer<http.Response>();
    final client = MockClient((request) {
      final genre = request.url.queryParameters['genre'];
      return genre == 'Action'
          ? actionCompleter.future
          : adventureCompleter.future;
    });

    await _pumpBrowse(tester, client: client);
    await tester.pump();

    // Switch to Adventure while Action is still in flight
    await tester.tap(find.text('Adventure'));
    await tester.pump();

    adventureCompleter.complete(_response([_movie('201', 'Adventure Resolved')]));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Adventure Resolved'), findsOneWidget);

    // Old Action completes late
    actionCompleter.complete(_response([_movie('202', 'Action Delayed')]));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Adventure Resolved'), findsOneWidget);
    expect(find.text('Action Delayed'), findsNothing);
  });
}
