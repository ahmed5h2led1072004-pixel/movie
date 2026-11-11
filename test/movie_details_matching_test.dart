import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/models/movie_availability.dart';
import 'package:movies/screens/movie_details_screen.dart';
import 'package:movies/widgets/archive_video_player.dart';

class _FakeMatchingService extends MovieMatchingService {
  final MovieAvailability availabilityToReturn;

  _FakeMatchingService(this.availabilityToReturn);

  @override
  Future<MovieAvailability> checkAvailability(Movie movie, {bool forceRefresh = false}) async {
    return availabilityToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MovieDetailsScreen Availability Integration Tests', () {
    testWidgets('shows Watch Now button and attribution banner when availableToWatch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const matchedArchive = InternetArchiveMovie(
        identifier: 'the-vagabond-1916_202304',
        title: 'The Vagabond (1916)',
        description: 'Charlie Chaplin comedy',
        rightsInfo: ArchiveRightsInfo(
          category: ArchiveRightsCategory.publicDomain,
          isCommercialReady: true,
          summary: 'Public Domain (Verified)',
        ),
        itemPageUrl: 'https://archive.org/details/the-vagabond-1916_202304',
      );

      const videoFile = ArchiveVideoFile(
        name: 'The Vagabond.mp4',
        format: 'MPEG4',
        size: 150000000,
        downloadUrl: 'https://archive.org/download/the-vagabond/The%20Vagabond.mp4',
      );

      final fakeService = _FakeMatchingService(
        MovieAvailability.available(
          matchedMovie: matchedArchive,
          videoFile: videoFile,
          confidenceScore: 0.98,
        ),
      );

      const movie = Movie(
        id: 'chaplin-vagabond',
        title: 'The Vagabond',
        year: 1916,
        description: 'A silent romantic comedy.',
      );

      bool recordedWatched = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: movie,
            matchingService: fakeService,
            initialIsSaved: false,
            initialIsFavorite: false,
            onRecordWatched: () async {
              recordedWatched = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Watch Now button is visible
      final watchNowButton = find.byKey(const Key('details-watch-now-button'));
      expect(watchNowButton, findsOneWidget);
      expect(find.text('Watch Now'), findsOneWidget);

      // Verify Attribution banner is visible
      final attributionBanner = find.byKey(const Key('details-attribution-banner'));
      expect(attributionBanner, findsOneWidget);
      expect(find.textContaining('Public Domain (Verified)'), findsOneWidget);

      // Verify unavailable banner is NOT visible
      expect(find.byKey(const Key('details-unavailable-banner')), findsNothing);

      // Tap Watch Now: launches player and records watched
      await tester.tap(watchNowButton);
      await tester.pumpAndSettle();

      expect(recordedWatched, isTrue);
      expect(find.byType(ArchiveVideoPlayer), findsOneWidget);
      expect(find.byKey(const Key('details-in-app-video-player')), findsOneWidget);

      // Close player
      await tester.tap(find.byKey(const Key('player-close-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ArchiveVideoPlayer), findsNothing);
    });

    testWidgets('shows Unavailable banner when rights are not verified and hides Watch Now', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const candidate = InternetArchiveMovie(
        identifier: 'turner_video_393545',
        title: 'Night of the Living Dead (1990 Remake)',
        description: '1990 modern remake',
        rightsInfo: ArchiveRightsInfo(
          category: ArchiveRightsCategory.unclearOrRestricted,
          isCommercialReady: false,
          summary: 'Copyright 1990 Columbia Pictures',
        ),
        itemPageUrl: 'https://archive.org/details/turner_video_393545',
      );

      final fakeService = _FakeMatchingService(
        MovieAvailability.rightsNotVerified(
          candidate: candidate,
          reason: 'Streaming prohibited: Copyright 1990 Columbia Pictures.',
        ),
      );

      const movie = Movie(
        id: 'notld-1990',
        title: 'Night of the Living Dead',
        year: 1990,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: movie,
            matchingService: fakeService,
            initialIsSaved: false,
            initialIsFavorite: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Watch Now button must NOT be present
      expect(find.byKey(const Key('details-watch-now-button')), findsNothing);

      // Unavailable banner must be present with reason
      final unavailableBanner = find.byKey(const Key('details-unavailable-banner'));
      expect(unavailableBanner, findsOneWidget);
      expect(find.text('Rights Not Verified'), findsOneWidget);
      expect(find.textContaining('Streaming prohibited'), findsOneWidget);

      // Standard Watch button is still available to mark as watched in history
      expect(find.byKey(const Key('details-watch-button')), findsOneWidget);
    });

    testWidgets('shows Metadata Only banner for modern release without streaming match', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = _FakeMatchingService(
        MovieAvailability.metadataOnly(
          reason: 'Modern commercial release (2021). Metadata only.',
        ),
      );

      const movie = Movie(
        id: 'black_widow',
        title: 'Black Widow',
        year: 2021,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MovieDetailsScreen(
            movie: movie,
            matchingService: fakeService,
            initialIsSaved: false,
            initialIsFavorite: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('details-watch-now-button')), findsNothing);
      expect(find.byKey(const Key('details-unavailable-banner')), findsOneWidget);
      expect(find.text('Metadata Only'), findsOneWidget);
      expect(find.textContaining('Modern commercial release (2021)'), findsOneWidget);
    });
  });
}
