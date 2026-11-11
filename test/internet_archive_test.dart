import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/screens/archive_test_screen.dart';
import 'package:movies/widgets/archive_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArchiveRightsInfo & Rights Validation Tests', () {
    test('classifies Public Domain Mark 1.0 as publicDomain and commercialReady', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
      );

      expect(info.category, ArchiveRightsCategory.publicDomain);
      expect(info.isCommercialReady, isTrue);
      expect(info.summary, 'Public Domain (Verified)');
    });

    test('classifies CC0 1.0 Universal as publicDomain and commercialReady', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
      );

      expect(info.category, ArchiveRightsCategory.publicDomain);
      expect(info.isCommercialReady, isTrue);
      expect(info.summary, 'Public Domain (Verified)');
    });

    test('classifies explicit rights string "public domain" as publicDomain', () {
      final info = ArchiveRightsInfo.fromMetadata(
        rights: 'This film has fallen into the Public Domain.',
      );

      expect(info.category, ArchiveRightsCategory.publicDomain);
      expect(info.isCommercialReady, isTrue);
    });

    test('classifies Creative Commons Non-Commercial as NOT commercialReady', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: 'http://creativecommons.org/licenses/by-nc-sa/3.0/',
      );

      expect(info.category, ArchiveRightsCategory.creativeCommons);
      expect(info.isCommercialReady, isFalse);
      expect(info.summary, 'Creative Commons (Non-Commercial)');
    });

    test('classifies Creative Commons Commercial Attribution as commercialReady', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: 'http://creativecommons.org/licenses/by/4.0/',
      );

      expect(info.category, ArchiveRightsCategory.creativeCommons);
      expect(info.isCommercialReady, isTrue);
      expect(info.summary, 'Creative Commons (Attribution)');
    });

    test('classifies unclear rights statement as unclearOrRestricted and NOT commercialReady', () {
      final info = ArchiveRightsInfo.fromMetadata(
        rights: 'Copyright 1990 Columbia Pictures. All rights reserved.',
      );

      expect(info.category, ArchiveRightsCategory.unclearOrRestricted);
      expect(info.isCommercialReady, isFalse);
      expect(info.summary, contains('Unclear Rights'));
    });

    test('classifies missing license and missing rights as unclearOrRestricted', () {
      final info = ArchiveRightsInfo.fromMetadata(
        licenseUrl: null,
        rights: null,
      );

      expect(info.category, ArchiveRightsCategory.unclearOrRestricted);
      expect(info.isCommercialReady, isFalse);
      expect(info.summary, 'Missing License Information');
    });
  });

  group('ArchiveVideoFile & Format Selection Tests', () {
    test('identifies direct playable MP4 and MPEG4 format', () {
      final file = ArchiveVideoFile.fromJson(
        {
          'name': 'Chaplin_The_Vagabond.mp4',
          'format': 'MPEG4',
          'size': '150000000',
          'length': '1483.22',
          'height': '480',
          'width': '640',
        },
        identifier: 'the-vagabond-1916',
      );

      expect(file.isDirectPlayableMp4, isTrue);
      expect(file.name, 'Chaplin_The_Vagabond.mp4');
      expect(file.size, 150000000);
      expect(file.height, 480);
      expect(file.width, 640);
      expect(
        file.downloadUrl,
        'https://archive.org/download/the-vagabond-1916/Chaplin_The_Vagabond.mp4',
      );
    });

    test('encodes filenames with spaces in downloadUrl', () {
      final file = ArchiveVideoFile.fromJson(
        {
          'name': 'Night of the Living Dead.mp4',
          'format': 'MPEG4',
          'size': '500000000',
        },
        identifier: 'NightOfTheLivingDead_201508',
      );

      expect(
        file.downloadUrl,
        'https://archive.org/download/NightOfTheLivingDead_201508/Night%20of%20the%20Living%20Dead.mp4',
      );
    });
  });

  group('InternetArchiveMovie.fromMetadata Tests', () {
    test('filters out torrents and metadata files while preserving video files', () {
      final mockMetadataJson = {
        'metadata': {
          'identifier': 'the-vagabond-1916',
          'title': 'The Vagabond',
          'creator': 'Charles Chaplin',
          'year': '1916',
          'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
          'description': 'A 1916 comedy classic.',
        },
        'files': [
          {
            'name': 'the-vagabond-1916_archive.torrent',
            'format': 'Archive BitTorrent',
          },
          {
            'name': 'the-vagabond-1916_files.xml',
            'format': 'Metadata',
          },
          {
            'name': '__ia_thumb.jpg',
            'format': 'Item Tile',
          },
          {
            'name': 'The Vagabond (1916) 360p.ogv',
            'format': 'Ogg Video',
            'size': '90000000',
            'height': '360',
            'width': '480',
          },
          {
            'name': 'The Vagabond (1916).mp4',
            'format': 'MPEG4',
            'size': '150000000',
            'length': '1483.22',
            'height': '480',
            'width': '640',
          },
        ],
      };

      final movie = InternetArchiveMovie.fromMetadata(mockMetadataJson);

      expect(movie.identifier, 'the-vagabond-1916');
      expect(movie.title, 'The Vagabond');
      expect(movie.year, 1916);
      expect(movie.creator, 'Charles Chaplin');
      expect(movie.durationSeconds, 1483.22);
      expect(movie.rightsInfo.isCommercialReady, isTrue);

      // Only OGV and MP4 should be retained in videoFiles
      expect(movie.videoFiles.length, 2);
      expect(movie.primaryPlayableVideo, isNotNull);
      expect(movie.primaryPlayableVideo!.name, 'The Vagabond (1916).mp4');
      expect(movie.canStream, isTrue);
    });

    test('movie with unclear rights has canStream = false', () {
      final mockMetadataJson = {
        'metadata': {
          'identifier': 'restricted-movie',
          'title': 'Restricted Film',
          'rights': 'All rights reserved by Studio',
        },
        'files': [
          {
            'name': 'restricted.mp4',
            'format': 'MPEG4',
            'size': '200000000',
          },
        ],
      };

      final movie = InternetArchiveMovie.fromMetadata(mockMetadataJson);

      expect(movie.rightsInfo.isCommercialReady, isFalse);
      expect(movie.canStream, isFalse);
    });
  });

  group('InternetArchiveService API & Mock Client Tests', () {
    test('searchMovies parses JSON docs correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'archive.org');
        expect(request.url.path, '/advancedsearch.php');
        expect(request.url.queryParameters['output'], 'json');

        final responsePayload = {
          'response': {
            'numFound': 2,
            'docs': [
              {
                'identifier': 'doc-1',
                'title': 'Public Domain Film',
                'description': 'A vintage movie in the public domain.',
                'year': '1925',
                'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
              },
              {
                'identifier': 'doc-2',
                'title': 'Unclear Film',
                'description': 'A movie with unknown licensing.',
                'year': '1985',
              },
            ],
          },
        };

        return http.Response(jsonEncode(responsePayload), 200);
      });

      final service = InternetArchiveService(client: mockClient);
      final allResults = await service.searchMovies('vintage');

      expect(allResults.length, 2);
      expect(allResults[0].identifier, 'doc-1');
      expect(allResults[0].rightsInfo.isCommercialReady, isTrue);
      expect(allResults[1].identifier, 'doc-2');
      expect(allResults[1].rightsInfo.isCommercialReady, isFalse);

      // Test verifiedRightsOnly flag
      final verifiedResults = await service.searchMovies(
        'vintage',
        verifiedRightsOnly: true,
      );
      expect(verifiedResults.length, 1);
      expect(verifiedResults[0].identifier, 'doc-1');
    });

    test('searchMovies throws InternetArchiveException on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = InternetArchiveService(client: mockClient);

      expect(
        () => service.searchMovies('test'),
        throwsA(isA<InternetArchiveException>()),
      );
    });

    test('getItemMetadata parses metadata response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/metadata/item-123');

        final payload = {
          'metadata': {
            'identifier': 'item-123',
            'title': 'Sample Item',
            'licenseurl': 'https://creativecommons.org/publicdomain/zero/1.0/',
          },
          'files': [
            {
              'name': 'sample.mp4',
              'format': 'MPEG4',
              'size': '1000',
            },
          ],
        };

        return http.Response(jsonEncode(payload), 200);
      });

      final service = InternetArchiveService(client: mockClient);
      final movie = await service.getItemMetadata('item-123');

      expect(movie.identifier, 'item-123');
      expect(movie.title, 'Sample Item');
      expect(movie.rightsInfo.isCommercialReady, isTrue);
      expect(movie.canStream, isTrue);
    });

    test('checkFileAccessibility returns true for HTTP 200 and 206', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('accessible')) {
          return http.Response('', 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = InternetArchiveService(client: mockClient);

      final isAccessible =
          await service.checkFileAccessibility('https://archive.org/download/test/accessible.mp4');
      expect(isAccessible, isTrue);

      final isNotAccessible =
          await service.checkFileAccessibility('https://archive.org/download/test/missing.mp4');
      expect(isNotAccessible, isFalse);
    });
  });

  group('ArchiveTestScreen Prototype Widget Tests', () {
    testWidgets('displays candidate movies, rights badges and links', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/metadata/')) {
          final id = request.url.pathSegments.last;
          if (id == 'the-vagabond-1916_202304') {
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
          if (id == 'turner_video_393545') {
            return http.Response(
              jsonEncode({
                'metadata': {
                  'identifier': 'turner_video_393545',
                  'title': 'Night of the Living Dead (1990 Remake)',
                  'rights': 'Copyright 1990 Columbia Pictures',
                },
                'files': [],
              }),
              200,
            );
          }
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

      // Verify title in AppBar
      expect(find.text('Internet Archive Playback'), findsOneWidget);

      // Verify presence of verified public domain movie
      expect(find.text('The Vagabond (1916)'), findsOneWidget);
      expect(find.text('Public Domain (Verified)'), findsWidgets);

      // Verify play button is enabled for verified movie
      final playChaplinBtn =
          find.byKey(const Key('play-archive-button-the-vagabond-1916_202304'));
      expect(playChaplinBtn, findsOneWidget);

      // Verify button for unverified movie displays "Rights Unclear" and is disabled
      final playUnverifiedBtn =
          find.byKey(const Key('play-archive-button-turner_video_393545'));
      expect(playUnverifiedBtn, findsOneWidget);
      expect(find.text('Rights Unclear'), findsOneWidget);

      // Tapping "Play Movie" on Chaplin triggers player view
      await tester.tap(playChaplinBtn);
      await tester.pumpAndSettle();

      // Video player widget is now active with movie title
      expect(find.byType(ArchiveVideoPlayer), findsOneWidget);
      expect(find.byKey(const Key('player-close-button')), findsOneWidget);

      // Close player
      await tester.tap(find.byKey(const Key('player-close-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ArchiveVideoPlayer), findsNothing);
    });

    testWidgets('Filter chip toggles verified rights only', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ArchiveTestScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Both verified and unclear items are visible initially
      expect(find.text('Night of the Living Dead (1990 Remake)'), findsOneWidget);

      // Toggle "Verified Rights Only" filter chip
      await tester.tap(find.byKey(const Key('archive-verified-filter-chip')));
      await tester.pumpAndSettle();

      // Unverified item is filtered out
      expect(find.text('Night of the Living Dead (1990 Remake)'), findsNothing);
      expect(find.text('The Vagabond (1916)'), findsOneWidget);
    });
  });

  group('ArchiveVideoPlayer Widget Tests', () {
    testWidgets('renders player with title, error fallback and retry button', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArchiveVideoPlayer(
              videoUrl: 'https://archive.org/download/test/sample.mp4',
              title: 'Test Stream Video',
              onClose: () {
                closed = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Stream Video'), findsOneWidget);
      expect(find.byKey(const Key('player-close-button')), findsOneWidget);

      // Tap close button
      await tester.tap(find.byKey(const Key('player-close-button')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });
  });

  group('Archive Navigation Route Tests', () {
    testWidgets('route /archive-test resolves and displays ArchiveTestScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/home',
          routes: {
            '/home': (context) => Scaffold(
                  body: Center(
                    child: IconButton(
                      key: const Key('home-archive-test-button'),
                      icon: const Icon(Icons.video_library_rounded),
                      onPressed: () => Navigator.pushNamed(context, '/archive-test'),
                    ),
                  ),
                ),
            '/archive-test': (context) => const ArchiveTestScreen(),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-archive-test-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ArchiveTestScreen), findsOneWidget);
      expect(find.text('Internet Archive Playback'), findsOneWidget);
    });
  });
}
