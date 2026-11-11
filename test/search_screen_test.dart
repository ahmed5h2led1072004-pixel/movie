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

http.Response _response(List<Map<String, dynamic>> movies) => http.Response(
  jsonEncode({
    'status': 'ok',
    'data': {'movies': movies},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _movie(String id, String title) => {
  'id': id,
  'title': title,
  'year': 2010,
  'rating': 8.8,
};

Future<void> _pumpSearch(WidgetTester tester, http.Client client) async {
  final repository = MovieRepository(apiService: YtsApiService(client: client));
  await tester.pumpWidget(
    MaterialApp(home: SearchScreen(repository: repository)),
  );
}

class _ControlledRepository extends MovieRepository {
  _ControlledRepository(this.searchHandler);

  final Future<MovieFetchResult> Function(String query) searchHandler;

  @override
  Future<MovieFetchResult> searchRemote(
    String query, {
    int limit = 20,
    int page = 1,
  }) => searchHandler(query);
}

void main() {
  testWidgets('starts empty and does not search with fewer than two chars', (
    tester,
  ) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return _response(const []);
    });
    await _pumpSearch(tester, client);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(find.byKey(const Key('search-empty-illustration')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(requests, 0);
    expect(find.byKey(const Key('search-empty-illustration')), findsOneWidget);
  });

  testWidgets('debounces and lowercases the query sent to YTS', (tester) async {
    final queries = <String?>[];
    final client = MockClient((request) async {
      queries.add(request.url.queryParameters['query_term']);
      return _response([_movie('1', 'Inception')]);
    });
    await _pumpSearch(tester, client);

    await tester.enterText(find.byType(TextField), 'INCEPTION');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(queries, ['inception']);
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('2010'), findsOneWidget);
    expect(find.text('8.8'), findsOneWidget);
  });

  testWidgets('an empty remote result shows no-results state', (tester) async {
    final client = MockClient((request) async => _response(const []));
    await _pumpSearch(tester, client);

    await tester.enterText(find.byType(TextField), 'nonexistentmovietitle');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.text('No movies found. Try a different title.'),
      findsOneWidget,
    );
    expect(find.text('Black Widow'), findsNothing);
  });

  testWidgets('older delayed responses cannot replace newer search results', (
    tester,
  ) async {
    final requests = <String>[];
    final batmanResponse = Completer<http.Response>();
    final inceptionResponse = Completer<http.Response>();
    final client = MockClient((request) {
      final query = request.url.queryParameters['query_term']!;
      requests.add(query);
      return query == 'batman'
          ? batmanResponse.future
          : inceptionResponse.future;
    });
    await _pumpSearch(tester, client);

    await tester.enterText(find.byType(TextField), 'Batman');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(requests, ['batman']);

    await tester.enterText(find.byType(TextField), 'Inception');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(requests, ['batman', 'inception']);

    inceptionResponse.complete(_response([_movie('2', 'Inception')]));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Inception'), findsNWidgets(2));

    batmanResponse.complete(_response([_movie('3', 'Batman Begins')]));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Inception'), findsNWidgets(2));
    expect(find.text('Batman Begins'), findsNothing);
  });

  testWidgets(
    'an older request error after three and four characters is ignored',
    (tester) async {
      final oldRequest = Completer<MovieFetchResult>();
      final requests = <String>[];
      final repository = _ControlledRepository((query) {
        requests.add(query);
        if (query == 'in') return oldRequest.future;
        return Future.value(
          MovieFetchResult(
            movies: [
              Movie(id: '1606', title: 'Inception', year: 2010, rating: 8.8),
            ],
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: SearchScreen(repository: repository)),
      );

      await tester.enterText(find.byType(TextField), 'in');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'inc');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Inception'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ince');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(requests, ['in', 'inc', 'ince']);
      expect(find.text('Inception'), findsOneWidget);

      oldRequest.completeError(StateError('stale request failure'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('temporarily unavailable'), findsNothing);
      expect(find.text('Inception'), findsOneWidget);
    },
  );

  testWidgets('API errors show retry without local search results', (
    tester,
  ) async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      if (attempts == 1) {
        throw http.ClientException('offline', request.url);
      }
      return _response([_movie('4', 'Interstellar')]);
    });
    await _pumpSearch(tester, client);

    await tester.enterText(find.byType(TextField), 'Interstellar');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.text('Black Widow'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Interstellar'), findsNWidgets(2));
    expect(attempts, 2);
  });
}
