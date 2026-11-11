import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/models/movie_availability.dart';

void main() {
  group('MovieMatchingService Title Normalization Tests', () {
    test('normalizes punctuation, leading articles and whitespace', () {
      expect(MovieMatchingService.normalizeTitle('The Vagabond'), 'vagabond');
      expect(MovieMatchingService.normalizeTitle('A Night to Remember!'), 'night to remember');
      expect(MovieMatchingService.normalizeTitle('Night of the Living Dead: Part 1'), 'night of the living dead part 1');
      expect(MovieMatchingService.normalizeTitle('  The   Ducktators  (1942)  '), 'ducktators');
    });

    test('removes quality and release noise tags', () {
      expect(
        MovieMatchingService.normalizeTitle('Night of the Living Dead [1080p] [remastered]'),
        'night of the living dead',
      );
      expect(
        MovieMatchingService.normalizeTitle('The Vagabond (film) (1916)'),
        'vagabond',
      );
    });

    test('removes accents and diacritics', () {
      expect(MovieMatchingService.normalizeTitle('Amélie'), 'amelie');
      expect(MovieMatchingService.normalizeTitle('Café'), 'cafe');
    });

    test('calculates title similarity accurately', () {
      final sim1 = MovieMatchingService.calculateTitleSimilarity('The Vagabond', 'Vagabond (1916)');
      expect(sim1, greaterThanOrEqualTo(0.95));

      final sim2 = MovieMatchingService.calculateTitleSimilarity('Night of the Living Dead', 'Night of the Living Dead (Remastered)');
      expect(sim2, greaterThanOrEqualTo(0.85));

      final simDiff = MovieMatchingService.calculateTitleSimilarity('The Avengers', 'Night of the Living Dead');
      expect(simDiff, lessThan(0.2));
    });
  });

  group('MovieMatchingService Candidate Evaluation & Rules', () {
    final service = MovieMatchingService();

    test('Exact title and matching year is strongest candidate (score >= 0.95)', () {
      const movie = Movie(id: '1', title: 'The Vagabond', year: 1916);
      final candidate = InternetArchiveMovie(
        identifier: 'the-vagabond-1916_202304',
        title: 'The Vagabond (1916)',
        description: 'Charlie Chaplin 1916 comedy.',
        year: 1916,
        rightsInfo: const ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain (Verified)',
        ),
        itemPageUrl: 'https://archive.org/details/the-vagabond-1916_202304',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.confidenceScore, greaterThanOrEqualTo(0.95));
      expect(eval.isYearMatch, isTrue);
      expect(eval.isRemakeMismatch, isFalse);
      expect(eval.notes, contains('Strongest candidate'));
    });

    test('Similar title and matching year yields valid verified match', () {
      const movie = Movie(id: '2', title: 'Night of the Living Dead', year: 1968);
      final candidate = InternetArchiveMovie(
        identifier: 'notld-1968-restored',
        title: 'Night of the Living Dead (1968) [Restored Edition]',
        description: 'Horror classic.',
        year: 1968,
        rightsInfo: const ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain',
        ),
        itemPageUrl: 'https://archive.org/details/notld',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.confidenceScore, greaterThanOrEqualTo(0.85));
      expect(eval.isYearMatch, isTrue);
      expect(eval.isRemakeMismatch, isFalse);
    });

    test('Remake detection: year mismatch (>= 5 years) is explicitly rejected', () {
      const originalMovie = Movie(id: '3', title: 'Night of the Living Dead', year: 1968);
      final remakeCandidate = InternetArchiveMovie(
        identifier: 'turner_video_393545',
        title: 'Night of the Living Dead',
        description: '1990 modern remake directed by Tom Savini.',
        year: 1990,
        rightsInfo: const ArchiveRightsInfo(
          category: ArchiveRightsCategory.unclearOrRestricted,
          isCommercialReady: false,
          summary: 'Copyright 1990 Columbia Pictures',
        ),
        itemPageUrl: 'https://archive.org/details/turner_video_393545',
      );

      final eval = service.evaluateCandidate(originalMovie, remakeCandidate);
      expect(eval.confidenceScore, 0.0);
      expect(eval.isRemakeMismatch, isTrue);
      expect(eval.notes, contains('remake'));
    });

    test('Year difference of 1 year is accepted with minor tolerance', () {
      const movie = Movie(id: '4', title: 'The Vagabond', year: 1917);
      final candidate = InternetArchiveMovie(
        identifier: 'the-vagabond-1916',
        title: 'The Vagabond',
        description: 'Comedy.',
        year: 1916,
        rightsInfo: const ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain',
        ),
        itemPageUrl: 'https://archive.org/details/the-vagabond',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.isYearMatch, isTrue);
      expect(eval.isRemakeMismatch, isFalse);
      expect(eval.confidenceScore, greaterThanOrEqualTo(0.80));
    });

    test('Low title similarity (< 0.70) is rejected even if year matches', () {
      const movie = Movie(id: '5', title: 'The Avengers', year: 2012);
      final candidate = InternetArchiveMovie(
        identifier: 'other-movie-2012',
        title: 'Dark Knight Rises',
        description: 'Unrelated movie from 2012.',
        year: 2012,
        rightsInfo: const ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain',
        ),
        itemPageUrl: 'https://archive.org/details/other',
      );

      final eval = service.evaluateCandidate(movie, candidate);
      expect(eval.confidenceScore, 0.0);
      expect(eval.notes, contains('below minimum threshold'));
    });
  });

  group('MovieMatchingService End-to-End Availability Tests', () {
    test('Available to Watch: verifies rights, playable video, and reachable stream', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD' && request.url.path.contains('/download/')) {
          return http.Response('', 200, headers: const {'content-length': '150000000'});
        }
        if (request.url.path.contains('/metadata/the-vagabond-1916_202304')) {
          return http.Response(
            jsonEncode({
              'metadata': {
                'identifier': 'the-vagabond-1916_202304',
                'title': 'The Vagabond (1916)',
                'year': '1916',
                'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
              },
              'files': [
                {
                  'name': 'The Vagabond.mp4',
                  'format': 'MPEG4',
                  'size': '150000000',
                  'length': '1483.22',
                  'height': '480',
                  'width': '640',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'chaplin-vagabond', title: 'The Vagabond', year: 1916);
      final availability = await service.checkAvailability(movie);

      expect(availability.state, MovieAvailabilityState.availableToWatch);
      expect(availability.canWatch, isTrue);
      expect(availability.videoFile, isNotNull);
      expect(availability.videoFile!.name, 'The Vagabond.mp4');
      expect(availability.streamUrl, contains('The%20Vagabond.mp4'));
      expect(availability.attribution, contains('Internet Archive'));
      expect(availability.attribution, contains('Public Domain'));
    });

    test('Rights Not Verified: candidate found but copyright/license is restricted', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/advancedsearch.php')) {
          return http.Response(
            jsonEncode({
              'response': {
                'docs': [
                  {
                    'identifier': 'night-living-dead-restricted',
                    'title': 'Night of the Living Dead',
                    'year': '1968',
                    'rights': 'Copyright 1968 All Rights Reserved Commercial Restricted',
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      // Using non-curated title to exercise search flow
      const movie = Movie(id: 'custom-notld', title: 'Night of the Living Dead Special Edition', year: 1968);
      final availability = await service.checkAvailability(movie);

      expect(availability.state, MovieAvailabilityState.rightsNotVerified);
      expect(availability.canWatch, isFalse);
      expect(availability.reasonMessage, contains('Commercial streaming is prohibited'));
    });

    test('Video Unavailable: rights verified but direct playable MP4 is missing', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/advancedsearch.php')) {
          return http.Response(
            jsonEncode({
              'response': {
                'docs': [
                  {
                    'identifier': 'vintage-no-mp4',
                    'title': 'Vintage Film',
                    'year': '1920',
                    'licenseurl': 'https://creativecommons.org/publicdomain/zero/1.0/',
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url.path.contains('/metadata/vintage-no-mp4')) {
          return http.Response(
            jsonEncode({
              'metadata': {
                'identifier': 'vintage-no-mp4',
                'title': 'Vintage Film',
                'year': '1920',
                'licenseurl': 'https://creativecommons.org/publicdomain/zero/1.0/',
              },
              'files': [
                {
                  'name': 'vintage.torrent',
                  'format': 'Archive BitTorrent',
                  'size': '1024',
                },
                {
                  'name': 'vintage_meta.xml',
                  'format': 'Metadata',
                  'size': '2048',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'vintage-film', title: 'Vintage Film', year: 1920);
      final availability = await service.checkAvailability(movie);

      expect(availability.state, MovieAvailabilityState.videoUnavailable);
      expect(availability.canWatch, isFalse);
      expect(availability.reasonMessage, contains('playable MP4'));
    });

    test('Video Unavailable: playable MP4 exists but stream URL is unreachable', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/advancedsearch.php')) {
          return http.Response(
            jsonEncode({
              'response': {
                'docs': [
                  {
                    'identifier': 'unreachable-stream',
                    'title': 'Silent Treasure',
                    'year': '1922',
                    'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url.path.contains('/metadata/unreachable-stream')) {
          return http.Response(
            jsonEncode({
              'metadata': {
                'identifier': 'unreachable-stream',
                'title': 'Silent Treasure',
                'year': '1922',
                'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
              },
              'files': [
                {
                  'name': 'Silent Treasure.mp4',
                  'format': 'MPEG4',
                  'size': '120000000',
                },
              ],
            }),
            200,
          );
        }
        // HEAD /download/... returns 404: metadata and format look valid,
        // but no actual stream can be served.
        return http.Response('Not found', 404);
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'silent-treasure', title: 'Silent Treasure', year: 1922);
      final availability = await service.checkAvailability(movie);

      expect(availability.state, MovieAvailabilityState.videoUnavailable);
      expect(availability.canWatch, isFalse);
      expect(availability.reasonMessage, contains('not reachable'));
    });

    test('Metadata Only: modern commercial Hollywood movie returns metadataOnly', () async {
      final service = MovieMatchingService();

      const modernMovie = Movie(id: 'black_widow', title: 'Black Widow', year: 2021);
      final availability = await service.checkAvailability(modernMovie);

      expect(availability.state, MovieAvailabilityState.metadataOnly);
      expect(availability.canWatch, isFalse);
      expect(availability.displayName, 'Metadata Only');
      expect(availability.reasonMessage, contains('Modern commercial release'));
    });

    test('Ambiguous matches: conflicting candidates with identical confidence are rejected', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/advancedsearch.php')) {
          return http.Response(
            jsonEncode({
              'response': {
                'docs': [
                  {
                    'identifier': 'ambiguous_item_a',
                    'title': 'Mystery Cinema',
                    'year': '1930',
                    'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
                  },
                  {
                    'identifier': 'ambiguous_item_b',
                    'title': 'Mystery Cinema',
                    'year': '1931',
                    'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'mystery', title: 'Mystery Cinema', year: 1930);
      final availability = await service.checkAvailability(movie);

      // Ambiguity must not be accepted as playable stream
      expect(availability.canWatch, isFalse);
    });

    test('API failure / timeout gracefully falls back to noMatchingVideo without crashing', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Network down');
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'error-movie', title: 'Silent Classic', year: 1925);
      final availability = await service.checkAvailability(movie);

      expect(availability.state, MovieAvailabilityState.noMatchingVideo);
      expect(availability.canWatch, isFalse);
      expect(availability.reasonMessage, contains('encountered an error'));
    });

    test('Cached results prevent repeating the same Archive API searches', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: const {'content-length': '150000000'});
        }
        requestCount++;
        return http.Response(
          jsonEncode({
            'metadata': {
              'identifier': 'the-vagabond-1916_202304',
              'title': 'The Vagabond (1916)',
              'year': '1916',
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
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'chaplin-vagabond', title: 'The Vagabond', year: 1916);

      // First check
      final avail1 = await service.checkAvailability(movie);
      expect(avail1.canWatch, isTrue);
      expect(requestCount, 1);
      expect(service.cacheCount, 1);

      // Second check (immediate) - must hit cache without network request
      final avail2 = await service.checkAvailability(movie);
      expect(avail2.canWatch, isTrue);
      expect(requestCount, 1); // No new network request!

      // Force refresh bypasses cache
      final avail3 = await service.checkAvailability(movie, forceRefresh: true);
      expect(avail3.canWatch, isTrue);
      expect(requestCount, 2);
    });

    test('In-flight request deduplication prevents concurrent duplicate requests', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: const {'content-length': '150000000'});
        }
        requestCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
            'metadata': {
              'identifier': 'the-vagabond-1916_202304',
              'title': 'The Vagabond (1916)',
              'year': '1916',
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
      });

      final service = MovieMatchingService(
        archiveService: InternetArchiveService(client: mockClient),
      );

      const movie = Movie(id: 'chaplin-vagabond', title: 'The Vagabond', year: 1916);

      // Fire 3 simultaneous checks
      final futures = [
        service.checkAvailability(movie),
        service.checkAvailability(movie),
        service.checkAvailability(movie),
      ];

      final results = await Future.wait(futures);

      expect(results.length, 3);
      expect(results[0].canWatch, isTrue);
      expect(results[1].canWatch, isTrue);
      expect(results[2].canWatch, isTrue);
      expect(requestCount, 1); // Only 1 network call executed for all 3 calls!
    });
  });
}
