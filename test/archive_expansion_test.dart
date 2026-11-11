// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/screens/archive_test_screen.dart';
import 'package:movies/widgets/archive_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const String _pdMark =
    'https://creativecommons.org/publicdomain/mark/1.0/';
const String _pdZero =
    'http://creativecommons.org/publicdomain/zero/1.0/';
const String _ccNc = 'http://creativecommons.org/licenses/by-nc-sa/3.0/';
const String _ccNd = 'http://creativecommons.org/licenses/by-nd/4.0/';

String _titleFor(String id) {
  switch (id) {
    case 'good-film':
    case 'duplicate-film':
      return 'Good Movie';
    case 'second-film':
      return 'Second Movie';
    case 'third-film':
      return 'Third Movie';
    case 'trailer-film':
      return 'Amazing Movie Trailer';
    case 'nc-film':
      return 'Non Commercial Film';
    case 'ogv-film':
      return 'Ogg Only Film';
    case 'matroska-film':
      return 'Matroska Film';
    case 'broken-film':
      return 'Broken Stream Film';
    case 'rights-statement-film':
      return 'Rights Statement Film';
    case 'restricted-film':
      return 'Restricted Film';
    case 'short-film':
      return 'Short Clip Film';
    case 'no-file-film':
      return 'No File Film';
    case 'tiny-head-film':
      return 'Tiny Head Film';
    default:
      return id;
  }
}

Map<String, dynamic> _doc(
  String id, {
  String? title,
  int year = 1930,
  String? licenseUrl = _pdMark,
  String? rights,
}) {
  return {
    'identifier': id,
    'title': title ?? _titleFor(id),
    'year': year,
    'runtime': '1:30:00',
    'licenseurl': ?licenseUrl,
    'rights': ?rights,
  };
}

Map<String, dynamic> _file(
  String name, {
  String format = 'h.264',
  int size = 12 * 1024 * 1024,
  double length = 5400,
  int height = 480,
  int width = 640,
}) {
  return {
    'name': name,
    'format': format,
    'size': '$size',
    'length': '$length',
    'height': '$height',
    'width': '$width',
  };
}

Map<String, dynamic> _metadata({
  required String id,
  String? title,
  int year = 1930,
  List<String> collections = const ['feature_films'],
  String? licenseUrl = _pdMark,
  String? rights,
  List<Map<String, dynamic>> files = const [],
}) {
  return {
    'metadata': {
      'identifier': id,
      'title': title ?? _titleFor(id),
      'year': year,
      'collection': collections,
      'licenseurl': ?licenseUrl,
      'rights': ?rights,
    },
    'files': files,
  };
}

class _ArchiveMock {
  _ArchiveMock({
    Map<int, List<Map<String, dynamic>>>? pages,
    Map<String, Map<String, dynamic>>? metadata,
    this.total = 100,
    this.headStatus = const {},
    this.headContentLength = const {},
    this.rangeFallback = false,
  })  : pages = pages ?? const {},
        metadata = metadata ?? const {};

  final Map<int, List<Map<String, dynamic>>> pages;
  final Map<String, Map<String, dynamic>> metadata;
  final int total;
  final Map<String, int> headStatus;
  final Map<String, int> headContentLength;
  final bool rangeFallback;

  final List<Uri> searchRequests = [];
  final Map<String, int> metadataCalls = {};
  final List<Uri> headRequests = [];
  final List<Uri> rangeRequests = [];
  final List<String?> rangeHeaders = [];

  late final http.Client client = MockClient((request) async {
    if (request.url.path.contains('advancedsearch.php')) {
      searchRequests.add(request.url);
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      return http.Response(
        jsonEncode({
          'response': {
            'numFound': total,
            'docs': pages[page] ?? const [],
          },
        }),
        200,
      );
    }

    if (request.url.path.startsWith('/metadata/')) {
      final id = request.url.pathSegments.last;
      metadataCalls[id] = (metadataCalls[id] ?? 0) + 1;
      final fixture = metadata[id];
      if (fixture == null) {
        return http.Response('Not found', 404);
      }
      return http.Response(jsonEncode(fixture), 200);
    }

    if (request.url.path.startsWith('/download/')) {
      if (request.method == 'HEAD') {
        headRequests.add(request.url);
        if (rangeFallback) {
          return http.Response('', 405);
        }
        final id = request.url.pathSegments[1];
        final status = headStatus[id] ?? 200;
        final length = headContentLength[id];
        return http.Response(
          '',
          status,
          headers: length == null ? const {} : {'content-length': '$length'},
        );
      }

      if (request.headers['Range'] == 'bytes=0-0') {
        rangeRequests.add(request.url);
        rangeHeaders.add(request.headers['Range']);
        return http.Response(
          '',
          206,
          headers: {'content-length': '1'},
        );
      }
    }

    return http.Response('Not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Expanded Archive discovery', () {
    test('catalog query covers multiple film collections, streams, and rights',
        () async {
      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film')],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
        },
        total: 100,
      );
      final service = InternetArchiveService(client: mock.client);

      final page = await service.fetchPlayableCatalogPage(rows: 1, reset: true);

      expect(page.movies.map((m) => m.identifier), ['good-film']);
      final request = mock.searchRequests.single;
      final q = request.queryParameters['q']!;

      expect(q, contains('mediatype:movies'));
      expect(q, contains('collection:(feature_films'));
      expect(q, contains('feature_films_unsorted'));
      expect(q, contains('silent_films'));
      expect(q, contains('Film_Noir'));
      expect(q, contains('format:MPEG4'));
      expect(q, contains('format:"512Kb MPEG4"'));
      expect(q, contains('format:"h.264"'));
      expect(q, contains('(licenseurl:* OR rights:*)'));
      expect(request.queryParameters['sort'], 'downloads desc');
      expect(request.queryParameters['rows'], '24');
    });

    test('verified-rights mode requires license evidence in the query',
        () async {
      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film')],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
        },
      );
      final service = InternetArchiveService(client: mock.client);

      await service.fetchPlayableCatalogPage(
        rows: 1,
        verifiedRightsOnly: true,
        reset: true,
      );

      final q = mock.searchRequests.single.queryParameters['q']!;
      expect(q, contains('licenseurl:*'));
      expect(q, isNot(contains('OR rights:*')));
    });

    test('search, year, and genre filters are encoded into the query',
        () async {
      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film', title: 'Nosferatu')],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            title: 'Nosferatu',
            year: 1922,
            collections: const ['feature_films', 'Film_Noir'],
            files: [_file('good.mp4')],
          ),
        },
      );
      final service = InternetArchiveService(client: mock.client);

      await service.fetchPlayableCatalogPage(
        rows: 1,
        query: 'Nosferatu',
        year: 1922,
        genre: 'Horror',
        reset: true,
      );

      final q = mock.searchRequests.single.queryParameters['q']!;
      expect(q, contains('title:"Nosferatu"'));
      expect(q, contains('year:1922'));
      expect(q, contains('collection:SciFi_Horror'));
      expect(q, contains('format:MPEG4'));
    });
  });

  group('Candidate validation', () {
    late _ArchiveMock mock;
    late InternetArchiveService service;

    setUp(() {
      mock = _ArchiveMock(
        pages: {
          1: [
            _doc('good-film'),
            _doc('second-film'),
            _doc('duplicate-film'),
            _doc('trailer-film'),
            _doc('nc-film', licenseUrl: _ccNc),
            _doc('ogv-film'),
            _doc('matroska-film'),
            _doc('broken-film'),
            _doc('rights-statement-film',
                licenseUrl: null, rights: 'This film is in the public domain'),
            _doc('restricted-film',
                licenseUrl: null, rights: 'Copyright 1990. All rights reserved.'),
            _doc('short-film'),
            _doc('no-file-film'),
            _doc('tiny-head-film'),
          ],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
          'second-film': _metadata(
            id: 'second-film',
            title: 'Second Movie',
            files: [_file('second.mp4')],
          ),
          'duplicate-film': _metadata(
            id: 'duplicate-film',
            title: 'Good Movie',
            files: [_file('duplicate.mp4')],
          ),
          'trailer-film': _metadata(
            id: 'trailer-film',
            title: 'Amazing Movie Trailer',
            collections: const ['feature_films', 'movie_trailers'],
            files: [_file('trailer.mp4')],
          ),
          'nc-film': _metadata(
            id: 'nc-film',
            licenseUrl: _ccNc,
            files: [_file('nc.mp4')],
          ),
          'ogv-film': _metadata(
            id: 'ogv-film',
            files: [_file('ogv.ogv', format: 'Ogg Video')],
          ),
          'matroska-film': _metadata(
            id: 'matroska-film',
            files: [_file('matroska.mp4', format: 'Matroska')],
          ),
          'broken-film': _metadata(
            id: 'broken-film',
            files: [_file('broken.mp4')],
          ),
          'rights-statement-film': _metadata(
            id: 'rights-statement-film',
            licenseUrl: null,
            rights: 'This film is in the public domain',
            files: [_file('rights.mp4')],
          ),
          'restricted-film': _metadata(
            id: 'restricted-film',
            licenseUrl: null,
            rights: 'Copyright 1990. All rights reserved.',
            files: [_file('restricted.mp4')],
          ),
          'short-film': _metadata(
            id: 'short-film',
            files: [_file('short.mp4', length: 120)],
          ),
          'no-file-film': _metadata(id: 'no-file-film', files: const []),
          'tiny-head-film': _metadata(
            id: 'tiny-head-film',
            files: [_file('tiny.mp4')],
          ),
        },
        total: 13,
        headStatus: {'broken-film': 404},
        headContentLength: {'tiny-head-film': 100},
      );
      service = InternetArchiveService(client: mock.client);
    });

    test('only validated, playable movies are returned', () async {
      final page = await service.fetchPlayableCatalogPage(
        rows: 20,
        reset: true,
      );
      final ids = page.movies.map((movie) => movie.identifier).toList();

      expect(ids, containsAll(['good-film', 'second-film']));
      expect(ids, contains('rights-statement-film'));
      expect(ids, isNot(contains('duplicate-film')));
      expect(ids, isNot(contains('trailer-film')));
      expect(ids, isNot(contains('nc-film')));
      expect(ids, isNot(contains('ogv-film')));
      expect(ids, isNot(contains('matroska-film')));
      expect(ids, isNot(contains('broken-film')));
      expect(ids, isNot(contains('restricted-film')));
      expect(ids, isNot(contains('short-film')));
      expect(ids, isNot(contains('no-file-film')));
      expect(ids, isNot(contains('tiny-head-film')));
    });

    test('diagnostics distinguish each validation stage', () async {
      final good = await service.diagnoseItem('good-film');
      expect(good.searchFound, isTrue);
      expect(good.metadataRetrieved, isTrue);
      expect(good.movieLike, isTrue);
      expect(good.videoFileFound, isTrue);
      expect(good.formatCompatible, isTrue);
      expect(good.rightsVerified, isTrue);
      expect(good.urlAccessibilityChecked, isTrue);
      expect(good.urlAccessible, isTrue);
      expect(good.selectedFile?.name, 'good.mp4');
      expect(good.isPlayable, isTrue);
      expect(good.failureReason, isNull);

      final missingMetadata = await service.diagnoseItem('missing-film');
      expect(missingMetadata.metadataRetrieved, isFalse);
      expect(missingMetadata.isPlayable, isFalse);
      expect(missingMetadata.failureReason, contains('Metadata unavailable'));

      final trailer = await service.diagnoseItem('trailer-film');
      expect(trailer.metadataRetrieved, isTrue);
      expect(trailer.movieLike, isFalse);
      expect(trailer.isPlayable, isFalse);
      expect(trailer.failureReason, contains('trailer'));

      final unsupported = await service.diagnoseItem('matroska-film');
      expect(unsupported.videoFileFound, isTrue);
      expect(unsupported.formatCompatible, isFalse);
      expect(unsupported.failureReason, contains('compatible MP4'));

      final restricted = await service.diagnoseItem('restricted-film');
      expect(restricted.formatCompatible, isTrue);
      expect(restricted.rightsVerified, isFalse);
      expect(restricted.urlAccessibilityChecked, isFalse);
      expect(restricted.failureReason, contains('Rights not verified'));

      final broken = await service.diagnoseItem('broken-film');
      expect(broken.rightsVerified, isTrue);
      expect(broken.urlAccessibilityChecked, isTrue);
      expect(broken.urlAccessible, isFalse);
      expect(broken.failureReason, contains('URL'));

      final tiny = await service.diagnoseItem('tiny-head-film');
      expect(tiny.urlAccessible, isFalse);
      expect(tiny.failureReason, contains('URL'));
    });

    test('metadata outage returns disabled search results, never playable ones',
        () async {
      final outageMock = _ArchiveMock(
        pages: {
          1: [_doc('offline-one'), _doc('offline-two')],
        },
        total: 80,
      );
      final outageService =
          InternetArchiveService(client: outageMock.client);

      final page = await outageService.fetchPlayableCatalogPage(
        rows: 20,
        reset: true,
      );

      expect(page.movies.length, 2);
      expect(page.movies.every((movie) => !movie.canStream), isTrue);
      expect(page.hasMore, isTrue);
      expect(outageMock.metadataCalls.length, 2);
    });
  });

  group('Catalog pagination and caching', () {
    test('pages advance, identifiers/titles dedupe, and metadata is cached',
        () async {
      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film'), _doc('second-film'), _doc('duplicate-film')],
          2: [_doc('good-film'), _doc('third-film')],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
          'second-film': _metadata(
            id: 'second-film',
            title: 'Second Movie',
            files: [_file('second.mp4')],
          ),
          'duplicate-film': _metadata(
            id: 'duplicate-film',
            title: 'Good Movie',
            files: [_file('duplicate.mp4')],
          ),
          'third-film': _metadata(
            id: 'third-film',
            title: 'Third Movie',
            files: [_file('third.mp4')],
          ),
        },
        total: 100,
      );
      final service = InternetArchiveService(client: mock.client);

      final first =
          await service.fetchPlayableCatalogPage(rows: 2, reset: true);
      expect(first.movies.map((m) => m.identifier), ['good-film', 'second-film']);
      expect(first.hasMore, isTrue);

      final second = await service.fetchPlayableCatalogPage(rows: 2);
      expect(second.movies.map((m) => m.identifier), ['third-film']);

      final requestedPages = mock.searchRequests
          .map((uri) => int.parse(uri.queryParameters['page']!))
          .toList();
      expect(requestedPages, containsAllInOrder([1, 2]));
      expect(mock.metadataCalls['good-film'], 1);
      expect(mock.metadataCalls['second-film'], 1);
      expect(mock.metadataCalls['third-film'], 1);
      expect(mock.headRequests.length,
          greaterThanOrEqualTo(2));
    });

    test('reset restarts discovery while reusing validated caches', () async {
      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film')],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
        },
        total: 100,
      );
      final service = InternetArchiveService(client: mock.client);

      await service.fetchPlayableCatalogPage(rows: 1, reset: true);
      await service.fetchPlayableCatalogPage(rows: 1, reset: true);

      expect(mock.searchRequests.length, 2);
      expect(mock.metadataCalls['good-film'], 1);
      expect(mock.headRequests.length, 1);
    });
  });

  group('Rights and stream compatibility', () {
    test('public-domain license evidence is labelled differently from a ',
        () {
      final licensed = ArchiveRightsInfo.fromMetadata(licenseUrl: _pdZero);
      final statement = ArchiveRightsInfo.fromMetadata(
        rights: 'This film has fallen into the Public Domain.',
      );

      expect(licensed.category, ArchiveRightsCategory.publicDomain);
      expect(licensed.isCommercialReady, isTrue);
      expect(licensed.summary, 'Public Domain (Verified)');

      expect(statement.category, ArchiveRightsCategory.publicDomain);
      expect(statement.isCommercialReady, isTrue);
      expect(statement.summary, 'Public Domain (Rights Statement)');
    });

    test('CC non-commercial is rejected and CC no-derivatives is labelled',
        () {
      final nc = ArchiveRightsInfo.fromMetadata(licenseUrl: _ccNc);
      expect(nc.category, ArchiveRightsCategory.creativeCommons);
      expect(nc.isCommercialReady, isFalse);
      expect(nc.summary, 'Creative Commons (Non-Commercial)');

      final nd = ArchiveRightsInfo.fromMetadata(licenseUrl: _ccNd);
      expect(nd.category, ArchiveRightsCategory.creativeCommons);
      expect(nd.isCommercialReady, isTrue);
      expect(nd.summary, 'Creative Commons (No Derivatives)');
    });

    test('portable MP4 is accepted while Matroska/OGV are not', () {
      final mp4 = ArchiveVideoFile.fromJson(
        {'name': 'movie.mp4', 'format': '512Kb MPEG4', 'size': '100'},
        identifier: 'x',
      );
      final matroska = ArchiveVideoFile.fromJson(
        {'name': 'movie.mp4', 'format': 'Matroska', 'size': '100'},
        identifier: 'x',
      );
      final ogv = ArchiveVideoFile.fromJson(
        {'name': 'movie.ogv', 'format': 'h.264', 'size': '100'},
        identifier: 'x',
      );

      expect(mp4.isDirectPlayableMp4, isTrue);
      expect(matroska.isDirectPlayableMp4, isFalse);
      expect(ogv.isDirectPlayableMp4, isFalse);
    });

    test('HEAD rejection falls back to a one-byte range request', () async {
      final mock = _ArchiveMock(rangeFallback: true);
      final service = InternetArchiveService(client: mock.client);

      final accessible = await service.checkFileAccessibility(
        'https://archive.org/download/range-test/range-test.mp4',
      );

      expect(accessible, isTrue);
      expect(mock.rangeRequests, hasLength(1));
      expect(mock.rangeHeaders.single, 'bytes=0-0');
    });
  });

  group('Archive screen integration', () {
    testWidgets('validated catalog renders playable cards', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = _ArchiveMock(
        pages: {
          1: [_doc('good-film'), _doc('nc-film', licenseUrl: _ccNc)],
        },
        metadata: {
          'good-film': _metadata(
            id: 'good-film',
            files: [_file('good.mp4')],
          ),
          'nc-film': _metadata(
            id: 'nc-film',
            licenseUrl: _ccNc,
            files: [_file('nc.mp4')],
          ),
        },
        total: 2,
      );
      final service = InternetArchiveService(client: mock.client);

      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveTestScreen(archiveService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Good Movie'), findsOneWidget);
      expect(find.text('Non Commercial Film'), findsNothing);

      final playButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('play-archive-button-good-film')),
      );
      expect(playButton.onPressed, isNotNull);
    });
  });

  group('ArchiveVideoPlayer resilience', () {
    late VideoPlayerPlatform originalPlatform;
    late _NeverInitializeVideoPlayerPlatform platform;

    setUpAll(() {
      originalPlatform = VideoPlayerPlatform.instance;
      platform = _NeverInitializeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
    });

    tearDownAll(() {
      VideoPlayerPlatform.instance = originalPlatform;
    });

    testWidgets('initialization timeout shows retry and retry creates a fresh controller',
        (tester) async {
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
              title: 'Timeout Movie',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(platform.createCount, 1);

      await tester.pump(const Duration(seconds: 21));
      await tester.pump();

      expect(find.textContaining('Timed out while opening'), findsOneWidget);
      expect(find.byKey(const Key('player-retry-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('player-retry-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(platform.createCount, 2);

      // Let the retry attempt time out too so no timer outlives the test.
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

class _NeverInitializeVideoPlayerPlatform extends VideoPlayerPlatform {
  int createCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    createCount++;
    return createCount;
  }

  @override
  Future<void> dispose(int textureId) async {}

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) => const Stream.empty();

  @override
  Widget buildView(int textureId) => const SizedBox();

  @override
  Future<void> play(int textureId) async {}

  @override
  Future<void> pause(int textureId) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {}
}
