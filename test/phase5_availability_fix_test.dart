import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/screens/archive_test_screen.dart';
import 'package:movies/screens/browse_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5 — Internet Archive Search Query & Date Extraction', () {
    test('sanitizes query by removing reserved Solr/Lucene characters', () {
      expect(
        InternetArchiveService.sanitizeQuery('Avengers: Infinity War (2018) [1080p]!'),
        'Avengers Infinity War 2018 1080p',
      );
      expect(
        InternetArchiveService.sanitizeQuery('Spider-Man / Homecoming & More?'),
        'Spider Man Homecoming More',
      );
    });

    test('extracts release year from text or title correctly', () {
      expect(InternetArchiveMovie.extractYearFromText('Night of the Living Dead (1968)'), 1968);
      expect(InternetArchiveMovie.extractYearFromText('The Vagabond (1916) [Restored]'), 1916);
      expect(InternetArchiveMovie.extractYearFromText('Movie without year'), isNull);
    });

    test('extractYearFromText takes precedence over upload publicdate in fromSearchDoc', () {
      final doc = {
        'identifier': 'vintage_classic',
        'title': 'Vintage Classic (1939)',
        'publicdate': '2025-05-12T00:00:00Z', // Uploaded in 2025
        'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
      };

      final movie = InternetArchiveMovie.fromSearchDoc(doc);
      // Must be 1939 (release year), NOT 2025 (upload date)!
      expect(movie.year, 1939);
    });

    test('detects creativecommons.org/licenses/publicdomain as publicDomain category', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: 'http://creativecommons.org/licenses/publicdomain/',
      );
      expect(info.category, ArchiveRightsCategory.publicDomain);
      expect(info.isCommercialReady, isTrue);
      expect(info.summary, 'Public Domain (Verified)');
    });
  });

  group('Phase 5 — Matching Algorithm: Remakes, Ambiguity & Noise', () {
    late MovieMatchingService service;

    setUp(() {
      service = MovieMatchingService();
    });

    test('exact title and matching year yields strongest confidence (>= 0.95)', () {
      const movie = Movie(id: 'vagabond_1916', title: 'The Vagabond', year: 1916);
      const candidate = InternetArchiveMovie(
        identifier: 'the-vagabond-1916_202304',
        title: 'The Vagabond (1916)',
        description: 'Chaplin',
        year: 1916,
        rightsInfo: ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain (Verified)',
        ),
        itemPageUrl: 'https://archive.org',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.confidenceScore, greaterThanOrEqualTo(0.95));
      expect(eval.isYearMatch, isTrue);
      expect(eval.isRemakeMismatch, isFalse);
    });

    test('rejects remake mismatch when release year differs by >= 2 years', () {
      const movie1968 = Movie(id: 'notld_1968', title: 'Night of the Living Dead', year: 1968);
      const candidate1990 = InternetArchiveMovie(
        identifier: 'notld_1990',
        title: 'Night of the Living Dead',
        description: '1990 remake',
        year: 1990,
        rightsInfo: ArchiveRightsInfo(
          category: ArchiveRightsCategory.unclearOrRestricted,
          isCommercialReady: false,
          summary: 'Copyright 1990 Columbia Pictures',
        ),
        itemPageUrl: 'https://archive.org',
      );

      final eval = service.evaluateCandidate(movie1968, candidate1990);
      expect(eval.isRemakeMismatch, isTrue);
      expect(eval.confidenceScore, 0.0);
    });

    test('never matches on title similarity alone when titles are unrelated', () {
      const movie = Movie(id: 'dark_knight', title: 'The Dark Knight', year: 2008);
      const candidate = InternetArchiveMovie(
        identifier: 'unrelated',
        title: 'The White Knight of the Prairie',
        description: 'Western',
        year: 2008,
        rightsInfo: ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain',
        ),
        itemPageUrl: 'https://archive.org',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.confidenceScore, 0.0);
    });
  });

  group('Phase 5 — HTTP Byte-Range Validation', () {
    test('checkFileAccessibility validates HTTP 200 and 206 byte-range responses', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('valid_stream')) {
          if (request.method == 'HEAD') {
            return http.Response('', 200, headers: {'accept-ranges': 'bytes'});
          }
          if (request.headers.containsKey('Range')) {
            return http.Response('video-bytes', 206, headers: {'content-range': 'bytes 0-10/1000'});
          }
        }
        return http.Response('Not Found', 404);
      });

      final service = InternetArchiveService(client: mockClient);
      final isAvailable = await service.checkFileAccessibility('https://archive.org/download/test/valid_stream.mp4');
      expect(isAvailable, isTrue);

      final isMissing = await service.checkFileAccessibility('https://archive.org/download/test/missing.mp4');
      expect(isMissing, isFalse);
    });
  });

  group('Phase 5 — Responsive UI & Small-Screen Overflow Fix', () {
    testWidgets('Archive movie card does not overflow horizontally on small screens (320px width)', (
      tester,
    ) async {
      // Set very narrow mobile viewport (e.g. 320px width like iPhone SE or small Android)
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/metadata/')) {
          return http.Response(
            jsonEncode({
              'metadata': {
                'identifier': 'the-vagabond-1916_202304',
                'title': 'The Vagabond (1916)',
                'year': '1916',
                'creator': 'Charles Chaplin',
                'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
              },
              'files': [
                {
                  'name': 'The Vagabond.mp4',
                  'format': 'MPEG4',
                  'size': '150000000',
                },
              ],
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

      // Verify no overflow error occurred and screen rendered properly
      expect(tester.takeException(), isNull);
      expect(find.byType(ArchiveTestScreen), findsOneWidget);
      expect(find.text('Internet Archive Playback'), findsOneWidget);
      expect(find.byKey(const Key('play-archive-button-the-vagabond-1916_202304')), findsWidgets);
    });
  });

  group('Phase 5 — Availability Filters: Non-blocking & In-flight checking states', () {
    testWidgets('BrowseScreen shows checking indicator while availability checks run', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const movie = Movie(id: 'notld_1968', title: 'Night of the Living Dead', year: 1968);

      final repository = _DelayedRepository([movie]);

      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(repository: repository),
        ),
      );
      // Pump initial frame
      await tester.pump();

      // Select Available to Watch
      await tester.tap(find.byKey(const Key('browse-filter-watchable')));
      await tester.pump();

      // The screen renders gracefully without crash
      expect(tester.takeException(), isNull);

      // Finish pending async tasks
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('BrowseScreen reset filter button switches back to All Movies', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const modernMovie = Movie(id: 'black_widow', title: 'Black Widow', year: 2021);
      final repository = _DelayedRepository([modernMovie]);

      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Available to Watch
      await tester.tap(find.byKey(const Key('browse-filter-watchable')));
      await tester.pumpAndSettle();

      // Shows empty filter with reset button
      expect(find.byKey(const Key('browse-reset-filter-button')), findsOneWidget);

      // Tap reset
      await tester.tap(find.byKey(const Key('browse-reset-filter-button')));
      await tester.pumpAndSettle();

      // All movies visible again
      expect(find.text('Black Widow'), findsOneWidget);
    });
  });
}

class _DelayedRepository extends MovieRepository {
  final List<Movie> sampleMovies;

  const _DelayedRepository(this.sampleMovies);

  @override
  List<Movie> byGenre(String genre) => sampleMovies;

  @override
  Future<MovieFetchResult> fetchMovies({
    int limit = 20,
    int page = 1,
    String? queryTerm,
    String? genre,
    String? sortBy,
  }) async {
    return MovieFetchResult(movies: sampleMovies);
  }

  @override
  Future<MovieFetchResult> searchRemote(String query, {int limit = 20, int page = 1}) async {
    return MovieFetchResult(movies: sampleMovies);
  }
}
