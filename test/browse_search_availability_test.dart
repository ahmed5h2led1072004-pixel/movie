import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/models/internet_archive_movie.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/models/movie_availability.dart';
import 'package:movies/screens/browse_screen.dart';
import 'package:movies/screens/search_screen.dart';

class _FakeMatchingService extends MovieMatchingService {
  final Map<String, MovieAvailability> customMap;

  _FakeMatchingService(this.customMap);

  @override
  Future<MovieAvailability> checkAvailability(Movie movie, {bool forceRefresh = false}) async {
    return customMap[movie.id] ?? MovieAvailability.metadataOnly();
  }

  @override
  Future<Map<String, MovieAvailability>> checkMultipleAvailability(List<Movie> movies) async {
    final res = <String, MovieAvailability>{};
    for (final m in movies) {
      res[m.id] = customMap[m.id] ?? MovieAvailability.metadataOnly();
    }
    return res;
  }
}

class _FakeRepository extends MovieRepository {
  final List<Movie> sampleMovies;

  const _FakeRepository(this.sampleMovies);

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
    final q = query.toLowerCase();
    return MovieFetchResult(
      movies: sampleMovies.where((m) => m.title.toLowerCase().contains(q)).toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const watchableMovie = Movie(
    id: 'movie-watchable',
    title: 'The Vagabond',
    year: 1916,
  );

  const metadataOnlyMovie = Movie(
    id: 'movie-metadata',
    title: 'Modern Hollywood Action',
    year: 2022,
  );

  late _FakeMatchingService fakeMatching;

  setUp(() {
    fakeMatching = _FakeMatchingService({
      'movie-watchable': MovieAvailability.available(
        matchedMovie: const InternetArchiveMovie(
          identifier: 'the-vagabond-1916_202304',
          title: 'The Vagabond (1916)',
          description: 'Chaplin',
          rightsInfo: ArchiveRightsInfo(
            category: ArchiveRightsCategory.publicDomain,
            isCommercialReady: true,
            summary: 'Public Domain',
          ),
          itemPageUrl: 'https://archive.org',
        ),
        videoFile: const ArchiveVideoFile(
          name: 'vagabond.mp4',
          format: 'MPEG4',
          size: 100,
          downloadUrl: 'https://archive.org/vagabond.mp4',
        ),
        confidenceScore: 0.99,
      ),
      'movie-metadata': MovieAvailability.metadataOnly(),
    });
  });

  group('BrowseScreen Availability Filter Tests', () {
    testWidgets('allows users to filter between All, Watchable, and Metadata Only', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakeRepository([watchableMovie, metadataOnlyMovie]);

      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(
            repository: repository,
            matchingService: fakeMatching,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially "All Movies" is selected, both movies visible
      expect(find.text('The Vagabond'), findsOneWidget);
      expect(find.text('Modern Hollywood Action'), findsOneWidget);
      expect(find.byKey(const Key('browse-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('browse-filter-watchable')), findsOneWidget);
      expect(find.byKey(const Key('browse-filter-metadata')), findsOneWidget);

      // Select "Available to Watch"
      await tester.tap(find.byKey(const Key('browse-filter-watchable')));
      await tester.pumpAndSettle();

      // Only watchable movie is displayed
      expect(find.text('The Vagabond'), findsOneWidget);
      expect(find.text('Modern Hollywood Action'), findsNothing);

      // Select "Metadata Only"
      await tester.tap(find.byKey(const Key('browse-filter-metadata')));
      await tester.pumpAndSettle();

      // Only metadata movie is displayed
      expect(find.text('The Vagabond'), findsNothing);
      expect(find.text('Modern Hollywood Action'), findsOneWidget);

      // Reset back to "All Movies"
      await tester.tap(find.byKey(const Key('browse-filter-all')));
      await tester.pumpAndSettle();

      expect(find.text('The Vagabond'), findsOneWidget);
      expect(find.text('Modern Hollywood Action'), findsOneWidget);
    });
  });

  group('SearchScreen Availability Filter Tests', () {
    testWidgets('allows users to filter search results by availability', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakeRepository([
        const Movie(id: 'movie-watchable', title: 'Night Movie Classic', year: 1968),
        const Movie(id: 'movie-metadata', title: 'Night Movie Modern', year: 2020),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            repository: repository,
            matchingService: fakeMatching,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter query "Night"
      await tester.enterText(find.byType(TextField), 'Night');
      await tester.pump(const Duration(milliseconds: 600)); // debounce
      await tester.pumpAndSettle();

      // Both results show
      expect(find.text('Night Movie Classic'), findsOneWidget);
      expect(find.text('Night Movie Modern'), findsOneWidget);

      // Filter chips are visible
      expect(find.byKey(const Key('search-filter-watchable')), findsOneWidget);

      // Filter by "Available to Watch"
      await tester.tap(find.byKey(const Key('search-filter-watchable')));
      await tester.pumpAndSettle();

      expect(find.text('Night Movie Classic'), findsOneWidget);
      expect(find.text('Night Movie Modern'), findsNothing);

      // Filter by "Metadata Only"
      await tester.tap(find.byKey(const Key('search-filter-metadata')));
      await tester.pumpAndSettle();

      expect(find.text('Night Movie Classic'), findsNothing);
      expect(find.text('Night Movie Modern'), findsOneWidget);
    });
  });
}
