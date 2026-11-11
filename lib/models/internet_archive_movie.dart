enum ArchiveRightsCategory {
  publicDomain,
  creativeCommons,
  unclearOrRestricted,
}

class ArchiveRightsInfo {
  final String? licenseUrl;
  final String? rights;
  final ArchiveRightsCategory category;
  final bool isCommercialReady;
  final String summary;

  const ArchiveRightsInfo({
    this.licenseUrl,
    this.rights,
    required this.category,
    required this.isCommercialReady,
    required this.summary,
  });

  factory ArchiveRightsInfo.fromMetadata({String? licenseUrl, String? rights}) {
    final cleanLicense = licenseUrl?.trim().toLowerCase() ?? '';
    final cleanRights = rights?.trim().toLowerCase() ?? '';

    // Public domain via license deed/dedication is independently verifiable.
    final licenseIsPublicDomain = cleanLicense.contains('publicdomain/zero') ||
        cleanLicense.contains('publicdomain/mark') ||
        cleanLicense.contains('licenses/publicdomain') ||
        cleanLicense.contains('/publicdomain');
    // A free-text rights statement is uploader-supplied, so it is labelled
    // separately even though it still permits playback in this prototype.
    final statementIsPublicDomain =
        cleanRights.contains('public domain') || cleanRights.contains('pdm');

    if (licenseIsPublicDomain || statementIsPublicDomain) {
      return ArchiveRightsInfo(
        licenseUrl: licenseUrl,
        rights: rights,
        category: ArchiveRightsCategory.publicDomain,
        isCommercialReady: true,
        summary: licenseIsPublicDomain
            ? 'Public Domain (Verified)'
            : 'Public Domain (Rights Statement)',
      );
    }

    // Creative Commons detection
    if (cleanLicense.contains('creativecommons.org/licenses') ||
        cleanLicense.contains('creativecommons.org/publicdomain')) {
      final isNonCommercial = cleanLicense.contains('by-nc') ||
          cleanLicense.contains('/nc') ||
          cleanLicense.contains('-nc');
      final isNoDerivatives = cleanLicense.contains('by-nd') ||
          cleanLicense.contains('/nd') ||
          cleanLicense.contains('-nd');
      final String summary;
      if (isNonCommercial) {
        summary = 'Creative Commons (Non-Commercial)';
      } else if (isNoDerivatives) {
        summary = 'Creative Commons (No Derivatives)';
      } else {
        summary = 'Creative Commons (Attribution)';
      }
      return ArchiveRightsInfo(
        licenseUrl: licenseUrl,
        rights: rights,
        category: ArchiveRightsCategory.creativeCommons,
        isCommercialReady: !isNonCommercial,
        summary: summary,
      );
    }

    // Unclear or missing rights
    return ArchiveRightsInfo(
      licenseUrl: licenseUrl,
      rights: rights,
      category: ArchiveRightsCategory.unclearOrRestricted,
      isCommercialReady: false,
      summary: cleanRights.isNotEmpty
          ? 'Unclear Rights: "$rights"'
          : 'Missing License Information',
    );
  }
}

class ArchiveVideoFile {
  final String name;
  final String format;
  final int size;
  final double? lengthSeconds;
  final int? height;
  final int? width;
  final String downloadUrl;

  const ArchiveVideoFile({
    required this.name,
    required this.format,
    required this.size,
    this.lengthSeconds,
    this.height,
    this.width,
    required this.downloadUrl,
  });

  bool get isDirectPlayableMp4 {
    final lowerName = name.toLowerCase();
    final lowerFormat = format.toLowerCase();

    // video_player on Android reliably streams H.264 in an MP4 container.
    // Reject containers/codecs that would surface a "Play Movie" button but
    // fail at playback time.
    if (lowerFormat.contains('matroska') ||
        lowerFormat.contains('hevc') ||
        lowerFormat.contains('h.265') ||
        lowerFormat.contains('mpeg2') ||
        lowerFormat.contains('theora') ||
        lowerFormat.contains('vp8') ||
        lowerFormat.contains('vp9')) {
      return false;
    }

    const incompatibleExtensions = [
      '.ogv',
      '.webm',
      '.mkv',
      '.avi',
      '.flv',
      '.wmv',
      '.mpeg',
      '.mpg',
    ];
    if (incompatibleExtensions.any(lowerName.endsWith)) return false;

    return lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.m4v') ||
        lowerFormat.contains('mpeg4') ||
        lowerFormat.contains('h.264');
  }

  factory ArchiveVideoFile.fromJson(
    Map<String, dynamic> json, {
    required String identifier,
  }) {
    final name = (json['name'] ?? '').toString();
    final format = (json['format'] ?? '').toString();
    final size = int.tryParse(json['size']?.toString() ?? '') ?? 0;
    final length = double.tryParse(json['length']?.toString() ?? '');
    final height = int.tryParse(json['height']?.toString() ?? '');
    final width = int.tryParse(json['width']?.toString() ?? '');

    final encodedName = Uri.encodeComponent(name).replaceAll('+', '%20');
    final downloadUrl =
        'https://archive.org/download/$identifier/$encodedName';

    return ArchiveVideoFile(
      name: name,
      format: format,
      size: size,
      lengthSeconds: length,
      height: height,
      width: width,
      downloadUrl: downloadUrl,
    );
  }
}

class InternetArchiveMovie {
  final String identifier;
  final String title;
  final String description;
  final int? year;
  final String? creator;
  final String? thumbnailUrl;
  final double? durationSeconds;
  final ArchiveRightsInfo rightsInfo;
  final List<ArchiveVideoFile> videoFiles;
  final List<String> collections;
  final String itemPageUrl;

  const InternetArchiveMovie({
    required this.identifier,
    required this.title,
    required this.description,
    this.year,
    this.creator,
    this.thumbnailUrl,
    this.durationSeconds,
    required this.rightsInfo,
    this.videoFiles = const [],
    this.collections = const [],
    required this.itemPageUrl,
  });

  /// The preferred direct playable MP4 video file
  ArchiveVideoFile? get primaryPlayableVideo {
    final playables = videoFiles.where((f) => f.isDirectPlayableMp4).toList();
    if (playables.isEmpty) return null;

    playables.sort((a, b) {
      final aRes = (a.height ?? 0) * (a.width ?? 0);
      final bRes = (b.height ?? 0) * (b.width ?? 0);
      if (aRes != bRes) return bRes.compareTo(aRes);
      return b.size.compareTo(a.size);
    });

    return playables.first;
  }

  bool get canStream {
    return rightsInfo.isCommercialReady && primaryPlayableVideo != null;
  }

  String? get runtimeFormatted {
    if (durationSeconds == null || durationSeconds! <= 0) return null;
    final total = durationSeconds!.toInt();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  static double? parseRuntimeSeconds(dynamic runtimeValue) {
    if (runtimeValue == null) return null;
    final str = runtimeValue.toString().trim();
    if (str.isEmpty) return null;

    final numVal = double.tryParse(str);
    if (numVal != null) return numVal;

    final parts = str.split(':');
    if (parts.length == 3) {
      final h = double.tryParse(parts[0]) ?? 0;
      final m = double.tryParse(parts[1]) ?? 0;
      final s = double.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    } else if (parts.length == 2) {
      final m = double.tryParse(parts[0]) ?? 0;
      final s = double.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    return null;
  }

  static int? extractYearFromText(String text) {
    final match = RegExp(r'\b(18\d{2}|19\d{2}|20\d{2})\b').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static String? _firstString(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      for (final entry in value) {
        final text = entry?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    final text = value.toString().trim();
    return text.isEmpty ? const [] : [text];
  }

  static int? _parseYear(dynamic value) {
    final text = _firstString(value);
    if (text == null) return null;
    return int.tryParse(text.split('-').first.trim());
  }

  factory InternetArchiveMovie.fromSearchDoc(Map<String, dynamic> doc) {
    final identifier = _firstString(doc['identifier']) ?? '';
    final title = _firstString(doc['title']) ?? 'Untitled';
    final description = _stringList(doc['description']).join(' ');
    final year = _parseYear(doc['year']) ??
        extractYearFromText(title) ??
        _parseYear(doc['date']);
    final creator = _firstString(doc['creator']);
    final durationSeconds = parseRuntimeSeconds(doc['runtime']);
    final licenseUrl = _firstString(doc['licenseurl']);
    final rights = _firstString(doc['rights']);

    final rightsInfo = ArchiveRightsInfo.fromMetadata(
      licenseUrl: licenseUrl,
      rights: rights,
    );

    return InternetArchiveMovie(
      identifier: identifier,
      title: title,
      description: description,
      year: year,
      creator: creator,
      durationSeconds: durationSeconds,
      rightsInfo: rightsInfo,
      collections: _stringList(doc['collection']),
      thumbnailUrl: 'https://archive.org/services/img/$identifier',
      itemPageUrl: 'https://archive.org/details/$identifier',
    );
  }

  factory InternetArchiveMovie.fromMetadata(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    final identifier = _firstString(meta['identifier']) ?? '';
    final title = _firstString(meta['title']) ?? 'Untitled';
    final description = _stringList(meta['description']).join(' ');
    final year = _parseYear(meta['year']) ??
        extractYearFromText(title) ??
        _parseYear(meta['date']);
    final creator = _firstString(meta['creator']);
    final licenseUrl = _firstString(meta['licenseurl']);
    final rights = _firstString(meta['rights']);
    final metadataRuntime = parseRuntimeSeconds(meta['runtime']);

    final rightsInfo = ArchiveRightsInfo.fromMetadata(
      licenseUrl: licenseUrl,
      rights: rights,
    );

    final rawFiles = json['files'] as List<dynamic>? ?? [];
    final videoFiles = <ArchiveVideoFile>[];
    String? customThumb;

    for (final raw in rawFiles) {
      if (raw is! Map<String, dynamic>) continue;
      final format = (_firstString(raw['format']) ?? '').toLowerCase();
      final rawName = _firstString(raw['name']) ?? '';
      final name = rawName.toLowerCase();
      if (rawName.isEmpty) continue;

      // Check for thumbnail
      if (name == '__ia_thumb.jpg' ||
          format.contains('item tile') ||
          format.contains('thumbnail')) {
        final encoded = Uri.encodeComponent(rawName).replaceAll('+', '%20');
        customThumb ??= 'https://archive.org/download/$identifier/$encoded';
      }

      // Filter out non-video formats (torrents, metadata xml, sqlite, etc.)
      if (format.contains('bittorrent') ||
          format.contains('metadata') ||
          format.contains('sqlite') ||
          name.endsWith('.xml') ||
          name.endsWith('.torrent') ||
          name.endsWith('.sqlite')) {
        continue;
      }

      if (format.contains('mpeg4') ||
          format.contains('video') ||
          format.contains('h.264') ||
          name.endsWith('.mp4') ||
          name.endsWith('.ogv') ||
          name.endsWith('.webm')) {
        videoFiles.add(ArchiveVideoFile.fromJson(raw, identifier: identifier));
      }
    }

    double? duration = metadataRuntime;
    if (duration == null || duration <= 0) {
      for (final f in videoFiles) {
        if (f.lengthSeconds != null && f.lengthSeconds! > 0) {
          duration = f.lengthSeconds;
          break;
        }
      }
    }

    return InternetArchiveMovie(
      identifier: identifier,
      title: title,
      description: description,
      year: year,
      creator: creator,
      thumbnailUrl:
          customThumb ?? 'https://archive.org/services/img/$identifier',
      durationSeconds: duration,
      rightsInfo: rightsInfo,
      videoFiles: videoFiles,
      collections: _stringList(meta['collection']),
      itemPageUrl: 'https://archive.org/details/$identifier',
    );
  }
}
