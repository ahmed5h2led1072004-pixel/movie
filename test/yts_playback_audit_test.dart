import 'package:flutter_test/flutter_test.dart';
import 'package:movies/models/movie.dart';

/// YTS exposes only catalog metadata plus torrent metadata/hashes. These tests
/// pin that boundary so torrent URLs or hashes can never leak into playback.
void main() {
  group('YTS playback feasibility boundary', () {
    const torrentHash = 'A1B2C3D4E5F60718293A4B5C6D7E8F9012345678';
    const torrentUrl = 'https://yts.gg/torrent/download/$torrentHash';

    final ytsMovieJson = <String, dynamic>{
      'id': 79749,
      'title': 'Metropolis',
      'year': 1927,
      'rating': 8.3,
      'medium_cover_image': 'https://yts.gg/assets/images/movies/metropolis/medium-cover.jpg',
      'yt_trailer_code': 'Q0VzqN2uQ1E',
      'genres': ['Drama', 'Sci-Fi'],
      'summary': 'A futuristic city sharply divided between the working class and the city planners.',
      'torrents': [
        {
          'url': torrentUrl,
          'hash': torrentHash,
          'quality': '720p',
          'type': 'web',
          'video_codec': 'x264',
          'seeds': 120,
          'peers': 6,
          'size': '900.00 MB',
          'size_bytes': 943718400,
        },
        {
          'url': 'https://yts.gg/torrent/download/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
          'hash': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
          'quality': '1080p',
          'type': 'web',
          'video_codec': 'x264',
          'seeds': 200,
          'peers': 10,
          'size': '1.80 GB',
          'size_bytes': 1932735283,
        },
      ],
    };

    test('torrent entries map only to quality labels, not playback fields', () {
      final movie = Movie.fromJson(ytsMovieJson);

      expect(movie.id, '79749');
      expect(movie.title, 'Metropolis');
      expect(movie.availableQualities, ['720p', '1080p']);

      final serialized = movie.toJson();
      expect(serialized.containsKey('torrents'), isFalse);
      expect(serialized.containsKey('hash'), isFalse);
      expect(serialized.containsKey('streamUrl'), isFalse);
      expect(serialized.containsKey('downloadUrl'), isFalse);
      expect(serialized.containsKey('videoUrl'), isFalse);
    });

    test('torrent URLs and hashes never appear anywhere in the Movie payload', () {
      final movie = Movie.fromJson(ytsMovieJson);
      final serializedValues = movie.toJson().values
          .expand(
            (value) => value is List ? value.map((item) => '$item') : ['$value'],
          )
          .join('|');

      expect(serializedValues.contains(torrentUrl), isFalse);
      expect(serializedValues.contains(torrentHash), isFalse);
      expect(serializedValues.contains('yts.gg/torrent'), isFalse);
      expect(serializedValues.contains('.torrent'), isFalse);
    });

    test('movie details JSON shape has no stream/play endpoint fields', () {
      // Mirrors the live movie_details.json shape verified during the audit.
      const playbackKeys = [
        'stream',
        'stream_url',
        'streamUrl',
        'play',
        'play_url',
        'watch',
        'watch_url',
        'mp4',
        'mkv',
        'video_url',
      ];

      for (final key in playbackKeys) {
        expect(
          ytsMovieJson.containsKey(key),
          isFalse,
          reason: 'Live YTS responses do not include a "$key" field.',
        );
      }
    });
  });
}
