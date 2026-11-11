// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:movies/data/internet_archive_service.dart';

void printMoviePage(String label, ArchiveCatalogPage page, int elapsedMs) {
  print('=== $label: ${page.movies.length} movies, hasMore=${page.hasMore}, '
      '${elapsedMs}ms ===');
  for (final movie in page.movies) {
    final file = movie.primaryPlayableVideo;
    print('  [${movie.identifier}] "${movie.title}" (${movie.year}) '
        'rights="${movie.rightsInfo.summary}" '
        'stream=${file?.name ?? "none"} '
        'url=${file != null}');
  }
}

void main() {
  test('LIVE Archive catalog and staged diagnostics', () async {
    final service = InternetArchiveService();

    final sw1 = Stopwatch()..start();
    final page1 = await service.fetchPlayableCatalogPage(rows: 20, reset: true);
    sw1.stop();
    printMoviePage('PAGE 1', page1, sw1.elapsedMilliseconds);

    final page1Ids = page1.movies.map((movie) => movie.identifier).toSet();

    final sw2 = Stopwatch()..start();
    final page2 = await service.fetchPlayableCatalogPage(rows: 20);
    sw2.stop();
    printMoviePage('PAGE 2', page2, sw2.elapsedMilliseconds);
    final page2Ids = page2.movies.map((movie) => movie.identifier).toList();
    final duplicates = page2Ids.where(page1Ids.contains).length;
    print('PAGE 2 overlap with page 1: $duplicates');

    final sw3 = Stopwatch()..start();
    final filtered = await service.fetchPlayableCatalogPage(
      rows: 5,
      query: 'Chaplin',
      verifiedRightsOnly: true,
      reset: true,
    );
    sw3.stop();
    printMoviePage('FILTERED query=Chaplin verifiedOnly', filtered,
        sw3.elapsedMilliseconds);

    final sw4 = Stopwatch()..start();
    final horror = await service.fetchPlayableCatalogPage(
      rows: 5,
      genre: 'Horror',
      reset: true,
    );
    sw4.stop();
    printMoviePage('FILTERED genre=Horror', horror, sw4.elapsedMilliseconds);

    const targets = [
      'NightOfTheLivingDead_201508',
      'sex_madness',
      'turner_video_393545',
      'this-id-does-not-exist-000',
    ];
    for (final id in targets) {
      final diagnostic = await service.diagnoseItem(id);
      print('=== DIAGNOSE [$id] playable=${diagnostic.isPlayable} ===');
      print('  stages: ${diagnostic.stages.join(' ')}');
      print('  movie="${diagnostic.movie?.title}" '
          'rights="${diagnostic.movie?.rightsInfo.summary}" '
          'file="${diagnostic.selectedFile?.name}" '
          'format="${diagnostic.selectedFile?.format}"');
      print('  failure: ${diagnostic.failureReason}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
