import 'internet_archive_movie.dart';

/// Distinct availability states for movies in the application.
enum MovieAvailabilityState {
  /// The movie has verified streaming rights and at least one direct playable stream.
  availableToWatch,

  /// The movie is in the catalog for information/metadata purposes only.
  metadataOnly,

  /// The archive search or catalog check found no corresponding video entry.
  noMatchingVideo,

  /// A video item exists, but rights are unclear, copyrighted, or commercial streaming is not verified.
  rightsNotVerified,

  /// Rights may be clear, but no playable MP4/H.264 video file is currently accessible.
  videoUnavailable,
}

/// Unified movie availability model connecting metadata with streaming capabilities.
class MovieAvailability {
  final MovieAvailabilityState state;
  final InternetArchiveMovie? matchedMovie;
  final ArchiveVideoFile? videoFile;
  final String? attribution;
  final String? licenseUrl;
  final String? streamUrl;
  final String? reasonMessage;
  final double confidenceScore;
  final DateTime checkedAt;

  const MovieAvailability({
    required this.state,
    this.matchedMovie,
    this.videoFile,
    this.attribution,
    this.licenseUrl,
    this.streamUrl,
    this.reasonMessage,
    this.confidenceScore = 0.0,
    required this.checkedAt,
  });

  /// True ONLY when the movie passes both rights verification and technical playback checks.
  bool get canWatch =>
      state == MovieAvailabilityState.availableToWatch &&
      streamUrl != null &&
      streamUrl!.isNotEmpty;

  /// User-facing human-readable availability label.
  String get displayName {
    switch (state) {
      case MovieAvailabilityState.availableToWatch:
        return 'Available to Watch';
      case MovieAvailabilityState.metadataOnly:
        return 'Metadata Only';
      case MovieAvailabilityState.noMatchingVideo:
        return 'No Matching Video';
      case MovieAvailabilityState.rightsNotVerified:
        return 'Rights Not Verified';
      case MovieAvailabilityState.videoUnavailable:
        return 'Video Unavailable';
    }
  }

  /// Factory for a movie that is fully playable and rights-cleared.
  factory MovieAvailability.available({
    required InternetArchiveMovie matchedMovie,
    required ArchiveVideoFile videoFile,
    required double confidenceScore,
  }) {
    final rightsSummary = matchedMovie.rightsInfo.summary;
    return MovieAvailability(
      state: MovieAvailabilityState.availableToWatch,
      matchedMovie: matchedMovie,
      videoFile: videoFile,
      streamUrl: videoFile.downloadUrl,
      attribution: 'Internet Archive ($rightsSummary)',
      licenseUrl: matchedMovie.rightsInfo.licenseUrl,
      reasonMessage: 'Verified open license ($rightsSummary) with playable direct video file.',
      confidenceScore: confidenceScore,
      checkedAt: DateTime.now(),
    );
  }

  /// Factory for catalog metadata-only movies (e.g. modern releases without open streaming).
  factory MovieAvailability.metadataOnly({
    String? reason,
    DateTime? checkedAt,
  }) {
    return MovieAvailability(
      state: MovieAvailabilityState.metadataOnly,
      reasonMessage: reason ?? 'Catalog metadata only. Commercial streaming not available in open archive.',
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  /// Factory when archive search yielded no valid match or candidate was rejected.
  factory MovieAvailability.noMatch({
    String? reason,
    DateTime? checkedAt,
  }) {
    return MovieAvailability(
      state: MovieAvailabilityState.noMatchingVideo,
      reasonMessage: reason ?? 'No matching video found in open archive catalog.',
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  /// Factory when an item matched, but rights/commercial streaming could not be verified.
  factory MovieAvailability.rightsNotVerified({
    InternetArchiveMovie? candidate,
    String? reason,
    DateTime? checkedAt,
  }) {
    final summary = candidate?.rightsInfo.summary ?? 'Unverified';
    return MovieAvailability(
      state: MovieAvailabilityState.rightsNotVerified,
      matchedMovie: candidate,
      attribution: candidate != null ? 'Internet Archive ($summary)' : null,
      licenseUrl: candidate?.rightsInfo.licenseUrl,
      reasonMessage: reason ??
          'Streaming prohibited: License is $summary. Commercial streaming rights could not be verified.',
      confidenceScore: candidate != null ? 0.5 : 0.0,
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  /// Factory when rights are clear or item exists, but direct playable video file is missing.
  factory MovieAvailability.videoUnavailable({
    InternetArchiveMovie? candidate,
    String? reason,
    DateTime? checkedAt,
  }) {
    return MovieAvailability(
      state: MovieAvailabilityState.videoUnavailable,
      matchedMovie: candidate,
      attribution: candidate != null ? 'Internet Archive (${candidate.rightsInfo.summary})' : null,
      licenseUrl: candidate?.rightsInfo.licenseUrl,
      reasonMessage: reason ?? 'Archive entry exists, but no playable MP4 video file is available.',
      confidenceScore: candidate != null ? 0.6 : 0.0,
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'MovieAvailability($state, canWatch: $canWatch, score: ${confidenceScore.toStringAsFixed(2)}, stream: $streamUrl)';
}

/// Filter options for movie browse and search screens.
enum MovieAvailabilityFilter {
  all,
  availableToWatch,
  metadataOnly,
}
