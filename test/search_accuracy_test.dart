import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/screens/search_screen.dart';

Movie _movie(String id, String title, {int year = 2020}) =>
    Movie(id: id, title: title, year: year);

YtsMoviePage _page(
  List<Movie> movies, {
  int page = 1,
  int limit = 50,
  int? total,
}) =>
    YtsMoviePage(
      movies: movies,
      page: page,
      limit: limit,
      totalCount: total ?? movies.length,
    );

typedef _PageHandler = FutureOr<YtsMoviePage> Function(
  String? queryTerm,
  int page,
);

class _FakeYtsService extends Fake implements YtsApiService {
  _FakeYtsService(this.handler);

  final _PageHandler handler;
  final List<String> requests = [];
  final List<int> limits = [];

  @override
  Future<YtsMoviePage> fetchMoviePage({
    int limit = 20,
    int page = 1,
    String? queryTerm,
    String? genre,
    String? sortBy,
  }) async {
    requests.add('${queryTerm ?? ''}#$page');
    limits.add(limit);
    return handler(queryTerm, page);
  }
}

http.Response _jsonResponse(
  List<Map<String, dynamic>> movies, {
  required int total,
  required int page,
  int limit = 50,
}) =>
    http.Response(
      jsonEncode({
        'status': 'ok',
        'data': {
          'movie_count': total,
          'page_number': page,
          'limit': limit,
          'movies': movies,
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _jsonMovie(String id, String title) => {
      'id': id,
      'title': title,
      'year': 2020,
      'rating': 8.0,
    };

void main() {
  group('YtsApiService pagination and query encoding', () {
    test('sends query_term with encoded spaces/ampersands and parses metadata',
        () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return _jsonResponse(
          [_jsonMovie('7', 'Halloween')],
          total: 174,
          page: 2,
        );
      });
      final service = YtsApiService(
        client: client,
        baseUrl: 'https://example.test/api/v2/',
      );

      final page = await service.fetchMoviePage(
        limit: 50,
        page: 2,
        queryTerm: 'Halloween & Knives',
      );

      expect(captured.path, '/api/v2/list_movies.json');
      expect(captured.queryParameters['query_term'], 'Halloween & Knives');
      expect(captured.queryParameters['limit'], '50');
      expect(captured.queryParameters['page'], '2');
      expect(captured.query, contains('%26'));
      expect(page.page, 2);
      expect(page.limit, 50);
      expect(page.totalCount, 174);
      expect(page.hasMore, isTrue);
      expect(page.movies.single.id, '7');
    });

    test('returns an empty page when the API omits movies', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {'movie_count': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = YtsApiService(client: client);

      final page = await service.fetchMoviePage(queryTerm: 'nothing');

      expect(page.movies, isEmpty);
      expect(page.totalCount, 0);
      expect(page.hasMore, isFalse);
    });

    test('fetchMovies still returns the parsed list', () async {
      final client = MockClient(
        (request) async => _jsonResponse(
          [_jsonMovie('1', 'Inception')],
          total: 1,
          page: 1,
        ),
      );
      final service = YtsApiService(client: client);

      final movies = await service.fetchMovies(queryTerm: 'inception');

      expect(movies.single.title, 'Inception');
    });
  });

  group('MovieRepository multi-page search', () {
    test('fetches later pages and ranks the exact title first', () async {
      final pageOne = [
        for (var i = 0; i < 50; i++) _movie('p1-$i', 'Halloween Spin-off $i'),
      ];
      final pageTwo = [
        for (var i = 0; i < 23; i++) _movie('p2-$i', 'Halloween Legacy $i'),
        _movie('exact', 'Halloween'),
      ];
      final service = _FakeYtsService((query, page) {
        if (page == 1) return _page(pageOne, total: 74);
        if (page == 2) return _page(pageTwo, page: 2, total: 74);
        return _page(const [], page: page, total: 74);
      });
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('halloween');

      expect(result.error, isNull);
      expect(result.movies.first.title, 'Halloween');
      expect(service.requests, ['halloween#1', 'halloween#2']);
      expect(service.limits, [50, 50]);
    });

    test('walks to page three when the exact title is the last result',
        () async {
      final pageOne = [
        for (var i = 0; i < 50; i++) _movie('a1-$i', 'Alien Spin-off $i'),
      ];
      final pageTwo = [
        for (var i = 0; i < 50; i++) _movie('a2-$i', 'Alien Attack $i'),
      ];
      final pageThree = [
        for (var i = 0; i < 37; i++) _movie('a3-$i', 'Alien Legacy $i'),
        _movie('alien', 'Alien'),
      ];
      final service = _FakeYtsService((query, page) {
        if (page == 1) return _page(pageOne, total: 138);
        if (page == 2) return _page(pageTwo, page: 2, total: 138);
        if (page == 3) return _page(pageThree, page: 3, total: 138);
        return _page(const [], page: page, total: 138);
      });
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('alien');

      expect(result.movies.first.title, 'Alien');
      expect(service.requests, ['alien#1', 'alien#2', 'alien#3']);
    });

    test('caps pagination at four API pages', () async {
      final service = _FakeYtsService(
        (query, page) => _page(
          [for (var i = 0; i < 50; i++) _movie('$page-$i', 'Movie $page $i')],
          page: page,
          total: 1000,
        ),
      );
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('movie');

      expect(result.error, isNull);
      expect(service.requests, ['movie#1', 'movie#2', 'movie#3', 'movie#4']);
    });

    test('retries with individual words when the API rejects a partial word',
        () async {
      final candidates = [
        _movie('1', 'The Dark Knight'),
        _movie('2', 'The Dark Knight Rises'),
        _movie('3', 'Dark City'),
        _movie('4', 'Darkest Hour'),
        _movie('5', 'The Knight Before Christmas'),
      ];
      final service = _FakeYtsService((query, page) {
        if (query == 'dark knigh') return _page(const []);
        if (query == 'dark') return _page(candidates);
        return _page(const []);
      });
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('Dark Knigh');

      final titles = result.movies.map((movie) => movie.title).toList();
      expect(titles, containsAll(['The Dark Knight', 'The Dark Knight Rises']));
      expect(titles, isNot(contains('Dark City')));
      expect(titles, isNot(contains('Darkest Hour')));
      expect(titles, isNot(contains('The Knight Before Christmas')));
      expect(service.requests, containsAll(['dark#1', 'knigh#1']));
    });

    test('normalizes capitalization, extra spaces, and punctuation', () async {
      final service = _FakeYtsService(
        (query, page) => _page([
          _movie('1', 'The Dark Knight Rises'),
          _movie('2', 'The Dark Knight'),
        ]),
      );
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('  THE   dark  KNIGHT ');

      expect(result.movies.first.title, 'The Dark Knight');
      expect(service.requests.first, 'the dark knight#1');
    });

    test('ranks separator variants such as Spider-Man and WALL·E', () async {
      final service = _FakeYtsService(
        (query, page) => _page([
          _movie('1', 'Spider-Man: Far From Home'),
          _movie('2', 'Spider-Man'),
          _movie('3', 'Spider Man 2'),
          _movie('4', 'WALL·E'),
        ]),
      );
      final repository = MovieRepository(apiService: service);

      for (final query in ['spider man', 'spiderman', 'SPIDER-MAN']) {
        final result = await repository.searchRemote(query);
        expect(result.movies.first.title, 'Spider-Man', reason: query);
      }

      final wallE = await repository.searchRemote('WALL-E');
      expect(wallE.movies.first.title, 'WALL·E');
    });

    test('filters unrelated year-only matches when an exact title exists',
        () async {
      final service = _FakeYtsService(
        (query, page) => _page([
          _movie('1', 'The Little American'),
          _movie('2', 'His Wedding Night'),
          _movie('3', '1917'),
        ]),
      );
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('1917');

      expect(result.movies.map((movie) => movie.title).toList(), ['1917']);
    });

    test('keeps API results when nothing matches strongly', () async {
      final service = _FakeYtsService(
        (query, page) => _page([_movie('1', 'Star Wars')]),
      );
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('star trek');

      expect(result.movies.map((movie) => movie.title).toList(), ['Star Wars']);
    });

    test('deduplicates movies by id', () async {
      final service = _FakeYtsService(
        (query, page) => _page([
          _movie('1', 'Dune: Part Two'),
          _movie('1', 'Dune: Part Two'),
        ]),
      );
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('dune');

      expect(result.movies.length, 1);
    });

    test('does not call the API for queries shorter than two characters',
        () async {
      final service = _FakeYtsService((query, page) => _page(const []));
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('  a  ');

      expect(result.movies, isEmpty);
      expect(service.requests, isEmpty);
    });

    test('surfaces API failures without local fallback results', () async {
      final service = _FakeYtsService((query, page) {
        throw YtsApiException('offline');
      });
      final repository = MovieRepository(apiService: service);

      final result = await repository.searchRemote('batman');

      expect(result.error, isNotNull);
      expect(result.movies, isEmpty);
    });
  });

  group('SearchScreen integration', () {
    testWidgets(
        'shows a full title found on a later page and replaces it on a new query',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = MockClient((request) async {
        final query = request.url.queryParameters['query_term'];
        final page =
            int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;

        if (query == 'halloween') {
          if (page == 1) {
            return _jsonResponse(
              [
                for (var i = 0; i < 50; i++)
                  _jsonMovie('h1-$i', 'Halloween Spin-off $i'),
              ],
              total: 51,
              page: 1,
            );
          }
          return _jsonResponse(
            [_jsonMovie('halloween', 'Halloween')],
            total: 51,
            page: 2,
          );
        }
        if (query == 'inception') {
          return _jsonResponse(
            [_jsonMovie('inception', 'Inception')],
            total: 1,
            page: 1,
          );
        }
        return _jsonResponse(const [], total: 0, page: page);
      });

      final repository = MovieRepository(
        apiService: YtsApiService(client: client),
      );
      await tester.pumpWidget(
        MaterialApp(home: SearchScreen(repository: repository)),
      );

      await tester.enterText(find.byType(TextField), 'Halloween');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // One match in the search field, one exact card from page 2.
      expect(find.text('Halloween'), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'Inception');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Halloween'), findsNothing);
      expect(find.text('Inception'), findsNWidgets(2));
    });
  });
}
