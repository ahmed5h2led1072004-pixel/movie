// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movies/data/internet_archive_service.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/data/yts_api_service.dart';
import 'package:movies/models/movie.dart';

void main() {
  test('Diagnostics: Fetch real YTS movies and test Archive search and matching', () async {
    final ytsService = YtsApiService();
    final client = http.Client();
    final archiveService = InternetArchiveService(client: client);
    final matchingService = MovieMatchingService(archiveService: archiveService);

    print('Fetching 50+ movies across various genres from live YTS API...');
    final movies = <Movie>[];

    try {
      final p1 = await ytsService.fetchMovies(limit: 20, page: 1, sortBy: 'download_count');
      movies.addAll(p1);
      print('Fetched ${p1.length} movies (popular)');

      final p2 = await ytsService.fetchMovies(limit: 20, page: 1, genre: 'Film-Noir');
      movies.addAll(p2);
      print('Fetched ${p2.length} Film-Noir movies');

      final p3 = await ytsService.fetchMovies(limit: 20, page: 1, genre: 'Horror', sortBy: 'year');
      movies.addAll(p3);
      print('Fetched ${p3.length} Horror movies');
    } catch (e) {
      print('Error fetching from YTS: $e');
    }

    // De-duplicate
    final uniqueMovies = <String, Movie>{};
    for (final m in movies) {
      uniqueMovies[m.id] = m;
    }
    final targetMovies = uniqueMovies.values.take(50).toList();
    print('\nTesting ${targetMovies.length} unique YTS movies:\n');

    int candidatesFound = 0;
    int confidentMatches = 0;
    int rightsPassed = 0;
    int technicallyPlayable = 0;
    int availableToWatch = 0;

    final records = <Map<String, dynamic>>[];

    for (int i = 0; i < targetMovies.length; i++) {
      final movie = targetMovies[i];
      print('----------------------------------------------------');
      print('Movie #${i + 1}: "${movie.title}" (${movie.year}) [ID: ${movie.id}]');

      try {
        final searchResults = await archiveService.searchMovies(movie.title, rows: 5);
        final found = searchResults.isNotEmpty;
        if (found) candidatesFound++;

        final avail = await matchingService.checkAvailability(movie);
        final candidate = avail.matchedMovie ?? (searchResults.isNotEmpty ? searchResults.first : null);
        final isMatch = avail.matchedMovie != null;
        if (isMatch) confidentMatches++;

        final rightsOk = candidate?.rightsInfo.isCommercialReady ?? false;
        if (rightsOk) rightsPassed++;

        final isPlayable = avail.videoFile != null;
        if (isPlayable) technicallyPlayable++;

        if (avail.canWatch) availableToWatch++;

        print('  Archive candidate found: $found');
        if (candidate != null) {
          print('  Candidate: "${candidate.title}" (${candidate.year}) [${candidate.identifier}]');
          print('  Rights: ${candidate.rightsInfo.summary} (CommercialReady: ${candidate.rightsInfo.isCommercialReady})');
        }
        print('  State: ${avail.state.name} | canWatch: ${avail.canWatch}');
        print('  Score: ${avail.confidenceScore.toStringAsFixed(2)}');
        print('  Reason: ${avail.reasonMessage}');

        records.add({
          'index': i + 1,
          'title': movie.title,
          'year': movie.year,
          'candidateFound': found,
          'candidateTitle': candidate?.title,
          'candidateYear': candidate?.year,
          'confidence': avail.confidenceScore,
          'rightsStatus': candidate?.rightsInfo.summary ?? 'None',
          'streamExists': avail.streamUrl != null,
          'finalState': avail.state.name,
          'reason': avail.reasonMessage,
        });
      } catch (e) {
        print('  Error checking movie: $e');
        records.add({
          'index': i + 1,
          'title': movie.title,
          'year': movie.year,
          'candidateFound': false,
          'error': '$e',
          'finalState': 'error',
        });
      }
    }

    print('\n======================================================');
    print('REAL YTS DIAGNOSTICS SUMMARY');
    print('======================================================');
    print('Total Movies Checked: ${targetMovies.length}');
    print('Archive Candidates Found: $candidatesFound');
    print('Confident Matches: $confidentMatches');
    print('Rights Passed: $rightsPassed');
    print('Technically Playable: $technicallyPlayable');
    print('Available to Watch: $availableToWatch');
    print('======================================================\n');

    expect(targetMovies.length, greaterThanOrEqualTo(50));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
