// ignore_for_file: avoid_print

import 'package:movies/data/yts_api_service.dart';

Future<void> main() async {
  final service = YtsApiService();
  try {
    final movies = await service.fetchMovies(limit: 5);
    if (movies.isEmpty) {
      print('YTS request succeeded, but returned no movies.');
      return;
    }

    for (final movie in movies) {
      print('${movie.title} (ID: ${movie.id})');
    }
  } finally {
    service.close();
  }
}
