import 'package:flutter_test/flutter_test.dart';
import 'package:movies/data/movie_matching_service.dart';
import 'package:movies/data/movie_repository.dart';
import 'package:movies/models/movie.dart';
import 'package:movies/models/movie_availability.dart';

void main() {
  test('Catalog & YTS matching statistics evaluation', () async {
    final service = MovieMatchingService();

    // Test dataset combining:
    // 1. The 11 local catalog movies (modern Hollywood releases)
    // 2. Curated public domain classics
    // 3. Negative samples (remakes, unclear rights, missing video)
    final testMovies = <Movie>[
      ...localMovies, // 11 movies: Black Widow, Captain America, Iron Man 3, Civil War, The Avengers, Doctor Strange 2, Joker, Baby Driver, 1917, Captain America narrow, The Dark Knight
      const Movie(id: 'chaplin_vagabond', title: 'The Vagabond', year: 1916),
      const Movie(id: 'notld_1968', title: 'Night of the Living Dead', year: 1968),
      const Movie(id: 'notld_1990', title: 'Night of the Living Dead', year: 1990), // Remake / Copyrighted
      const Movie(id: 'this_is_the_army', title: 'This is the Army', year: 1943),
      const Movie(id: 'ducktators', title: 'The Ducktators', year: 1942),
      const Movie(id: 'nosferatu_1922', title: 'Nosferatu', year: 1922),
      const Movie(id: 'nosferatu_remake', title: 'Nosferatu the Vampyre', year: 1979),
      const Movie(id: 'charade_1963', title: 'Charade', year: 1963),
      const Movie(id: 'carnival_souls', title: 'Carnival of Souls', year: 1962),
      const Movie(id: 'plan_9', title: 'Plan 9 from Outer Space', year: 1959),
      const Movie(id: 'general_keaton', title: 'The General', year: 1926),
      const Movie(id: 'metropolis_1927', title: 'Metropolis', year: 1927),
      const Movie(id: 'his_girl_friday', title: 'His Girl Friday', year: 1940),
      const Movie(id: 'gullivers_travels', title: "Gulliver's Travels", year: 1939),
    ];

    int totalChecked = testMovies.length;
    int successfulMatches = 0;
    int playableMovies = 0;
    int rightsRejected = 0;
    int metadataOnlyOrNoMatch = 0;

    for (final movie in testMovies) {
      final availability = await service.checkAvailability(movie);
      if (availability.state == MovieAvailabilityState.availableToWatch) {
        successfulMatches++;
        playableMovies++;
      } else if (availability.state == MovieAvailabilityState.rightsNotVerified) {
        successfulMatches++; // matched item, but rights rejected
        rightsRejected++;
      } else if (availability.state == MovieAvailabilityState.videoUnavailable) {
        successfulMatches++; // matched item, but video missing
      } else {
        metadataOnlyOrNoMatch++;
      }
    }

    // ignore: avoid_print
    print('=== MATCHING BENCHMARK RESULTS ===');
    // ignore: avoid_print
    print('Total Movies Checked: $totalChecked');
    // ignore: avoid_print
    print('Successful Matches: $successfulMatches');
    // ignore: avoid_print
    print('Technically Playable Movies: $playableMovies');
    // ignore: avoid_print
    print('Rejected Because of Rights: $rightsRejected');
    // ignore: avoid_print
    print('Metadata Only or No Match: $metadataOnlyOrNoMatch');
    // ignore: avoid_print
    print('=================================');

    expect(totalChecked, 25);
    expect(playableMovies, greaterThanOrEqualTo(4));
    expect(metadataOnlyOrNoMatch, greaterThanOrEqualTo(11));
  });
}
