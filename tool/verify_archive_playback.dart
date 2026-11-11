// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
import 'package:movies/data/internet_archive_service.dart';

void main() async {
  final client = http.Client();
  final service = InternetArchiveService(client: client);

  final candidateIds = [
    ('the-vagabond-1916_202304', 'The Vagabond (1916)'),
    ('NightOfTheLivingDead_201508', 'Night of the Living Dead (1968)'),
    ('this_is_the_army_mp4', 'This Is the Army (1943)'),
    ('the-ducktators-1942', 'The Ducktators (1942)'),
  ];

  print('================================================================');
  print('INTERNET ARCHIVE PLAYBACK & RIGHTS VERIFICATION FOR ANDROID');
  print('================================================================\n');

  for (final entry in candidateIds) {
    final id = entry.$1;
    final name = entry.$2;

    print('----------------------------------------------------------------');
    print('Testing candidate: $name (ID: $id)');
    print('----------------------------------------------------------------');

    try {
      // 1. Retrieve fresh metadata from official archive.org endpoint
      print('[1] Fetching metadata from https://archive.org/metadata/$id ...');
      final movie = await service.getItemMetadata(id);

      print('    Title: ${movie.title}');
      print('    Year: ${movie.year}');
      print('    Creator: ${movie.creator ?? "N/A"}');
      print('    Duration: ${movie.durationSeconds != null ? "${(movie.durationSeconds! / 60).toStringAsFixed(1)} minutes" : "N/A"}');
      print('    Thumbnail: ${movie.thumbnailUrl}');
      print('    Item Page: ${movie.itemPageUrl}');

      // 2. Check rights information
      print('[2] Rights & License Inspection:');
      print('    License URL: ${movie.rightsInfo.licenseUrl ?? "None"}');
      print('    Rights Text: ${movie.rightsInfo.rights ?? "None"}');
      print('    Rights Category: ${movie.rightsInfo.category.name}');
      print('    Commercial Ready: ${movie.rightsInfo.isCommercialReady}');
      print('    Summary: ${movie.rightsInfo.summary}');

      // 3. Inspect available video files
      print('[3] Video Files Discovered (${movie.videoFiles.length} files):');
      for (final file in movie.videoFiles) {
        final mb = (file.size / (1024 * 1024)).toStringAsFixed(1);
        final resolution = file.height != null ? '${file.width}x${file.height}' : 'unknown res';
        print('    - ${file.name} | Format: ${file.format} | Size: $mb MB | Res: $resolution | Playable: ${file.isDirectPlayableMp4}');
      }

      final primary = movie.primaryPlayableVideo;
      if (primary == null) {
        print('    [!] ERROR: No direct playable MP4 file found!');
        continue;
      }

      print('[4] Selected Primary Playable File:');
      print('    File Name: ${primary.name}');
      print('    Format: ${primary.format}');
      print('    Download/Stream URL: ${primary.downloadUrl}');

      // 4. Test HTTP Accessibility & Range Streaming
      print('[5] Testing HTTP Accessibility & Byte-Range Streaming:');
      final uri = Uri.parse(primary.downloadUrl);
      final head = await client.head(uri).timeout(const Duration(seconds: 15));

      print('    HTTP HEAD Status: ${head.statusCode}');
      print('    Content-Type: ${head.headers['content-type']}');
      print('    Content-Length: ${head.headers['content-length']} bytes');
      print('    Accept-Ranges: ${head.headers['accept-ranges']}');
      print('    Location (redirect): ${head.headers['location']}');

      // Test byte-range request for streaming initialization
      final streamTest = await client.get(
        uri,
        headers: {'Range': 'bytes=0-1023'}, // first 1KB of MP4 header
      ).timeout(const Duration(seconds: 15));

      print('    HTTP Range Request (bytes=0-1023) Status: ${streamTest.statusCode}');
      print('    Range Content-Range: ${streamTest.headers['content-range']}');
      print('    Range Bytes Received: ${streamTest.bodyBytes.length} bytes');

      final isAccessible = streamTest.statusCode == 200 || streamTest.statusCode == 206;
      final canStream = movie.canStream && isAccessible;

      print('\n    ===> PLAYBACK ELIGIBILITY VERDICT: ${canStream ? "PASS - READY FOR IN-APP STREAMING" : "FAIL"}');
      print('         - Rights Verified: ${movie.rightsInfo.isCommercialReady}');
      print('         - Playable MP4 Found: ${primary.isDirectPlayableMp4}');
      print('         - HTTP Range Streaming Accessible: $isAccessible\n');

    } catch (e, stack) {
      print('    [ERROR] Failed to verify $id: $e');
      print(stack);
    }
  }

  client.close();
  print('================================================================');
  print('VERIFICATION COMPLETE');
  print('================================================================');
}
