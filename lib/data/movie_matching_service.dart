import 'dart:async';
import 'dart:math';

import '../models/internet_archive_movie.dart';
import '../models/movie.dart';
import '../models/movie_availability.dart';
import 'internet_archive_service.dart';

class _CacheEntry {
  final MovieAvailability availability;
  final DateTime expiresAt;

  const _CacheEntry({
    required this.availability,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Result of evaluating a candidate Internet Archive item against a target Movie.
class MatchEvaluation {
  final InternetArchiveMovie candidate;
  final double titleSimilarity;
  final double confidenceScore;
  final bool isYearMatch;
  final bool isRemakeMismatch;
  final bool isAmbiguous;
  final String notes;

  const MatchEvaluation({
    required this.candidate,
    required this.titleSimilarity,
    required this.confidenceScore,
    required this.isYearMatch,
    required this.isRemakeMismatch,
    required this.isAmbiguous,
    required this.notes,
  });
}

/// Service responsible for intelligent, rights-safe matching of YTS movies with Internet Archive items.
class MovieMatchingService {
  final InternetArchiveService _archiveService;
  final Duration cacheTtl;
  final Duration requestTimeout;

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<MovieAvailability>> _inFlight = {};

  MovieMatchingService({
    InternetArchiveService? archiveService,
    this.cacheTtl = const Duration(hours: 2),
    this.requestTimeout = const Duration(seconds: 8),
  }) : _archiveService = archiveService ?? InternetArchiveService();

  /// Curated identifiers for known verified archive candidates.
  static const Map<String, String> curatedMovieMap = {
    'vagabond': 'the-vagabond-1916_202304',
    'the vagabond': 'the-vagabond-1916_202304',
    'vagabond 1916': 'the-vagabond-1916_202304',
    'the vagabond 1916': 'the-vagabond-1916_202304',
    'the-vagabond-1916': 'the-vagabond-1916_202304',
    'night of the living dead': 'NightOfTheLivingDead_201508',
    'night of the living dead 1968': 'NightOfTheLivingDead_201508',
    'night of living dead': 'NightOfTheLivingDead_201508',
    'night of living dead 1968': 'NightOfTheLivingDead_201508',
    'this is the army': 'this_is_the_army_mp4',
    'this is the army 1943': 'this_is_the_army_mp4',
    'ducktators': 'the-ducktators-1942',
    'the ducktators': 'the-ducktators-1942',
    'ducktators 1942': 'the-ducktators-1942',
    'the ducktators 1942': 'the-ducktators-1942',
    'the-ducktators-1942': 'the-ducktators-1942',
    'nosferatu': 'Nosferatu_201902',
    'nosferatu 1922': 'Nosferatu_201902',
    'charade': 'charade-1963-cary-grant-audrey-hepburn-comedy-mystery-romance-thriller-full-movie',
    'charade 1963': 'charade-1963-cary-grant-audrey-hepburn-comedy-mystery-romance-thriller-full-movie',
    'carnival of souls': 'carnival-of-souls-pnm',
    'carnival of souls 1962': 'carnival-of-souls-pnm',
    'general': 'the-general-1926_202505',
    'the general': 'the-general-1926_202505',
    'general 1926': 'the-general-1926_202505',
    'the general 1926': 'the-general-1926_202505',
    'doa': 'd.-o.-a.-1950',
    'd o a': 'd.-o.-a.-1950',
    'd o a 1949': 'd.-o.-a.-1950',
    'doa 1949': 'd.-o.-a.-1950',
    'his girl friday': 'HisGirlFriday',
    'his girl friday 1940': 'HisGirlFriday',
    'gullivers travels': 'gullivers-travels-1939-1949-german-dub_202610',
    'gullivers travels 1939': 'gullivers-travels-1939-1949-german-dub_202610',
    'plan 9 from outer space': 'Plan_9_from_Outer_Space_1959',
    'plan 9 from outer space 1959': 'Plan_9_from_Outer_Space_1959',
    'metropolis': 'Metropolis1927_201308',
    'metropolis 1927': 'Metropolis1927_201308',
    'phantom of the opera': 'ThePhantomoftheOpera1925',
    'the phantom of the opera': 'ThePhantomoftheOpera1925',
    'phantom of the opera 1925': 'ThePhantomoftheOpera1925',
    'the phantom of the opera 1925': 'ThePhantomoftheOpera1925',
    'star is born': 'AStarIsBorn1937',
    'a star is born': 'AStarIsBorn1937',
    'a star is born 1937': 'AStarIsBorn1937',
    'detour': 'Detour1945',
    'detour 1945': 'Detour1945',
    'house on haunted hill': 'HouseOnHauntedHill1959',
    'house on haunted hill 1959': 'HouseOnHauntedHill1959',
    'little shop of horrors': 'TheLittleShopofHorrors',
    'the little shop of horrors': 'TheLittleShopofHorrors',
    'little shop of horrors 1960': 'TheLittleShopofHorrors',
    'the little shop of horrors 1960': 'TheLittleShopofHorrors',
    'scarlet street': 'ScarletStreet1945',
    'scarlet street 1945': 'ScarletStreet1945',
    'the kid': 'TheKid1921',
    'the kid 1921': 'TheKid1921',
  };

  /// Normalizes a movie title for robust string and token comparison.
  static String normalizeTitle(String title) {
    var s = title.trim().toLowerCase();

    // Remove text inside parentheses/brackets, such as years, quality tags, or extra labels
    s = s.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), ' ');
    s = s.replaceAll(RegExp(r'\[(?:19|20)\d{2}\]'), ' ');
    s = s.replaceAll(RegExp(r'\((?:film|movie|feature film|short|video|remastered|restored|edition|special edition|version)\)'), ' ');
    s = s.replaceAll(RegExp(r'\[(?:1080p|720p|bluray|dvdrip|web-rip|x264|h264|mp4|remastered|restored|edition|special edition|restored edition)\]'), ' ');
    s = s.replaceAll(RegExp(r'\b(?:1080p|720p|bluray|dvdrip|remastered|restored|special edition|restored edition|directors cut|director s cut)\b'), ' ');

    // Normalize accents / common diacritics
    s = s
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n');

    // Replace punctuation with space
    s = s.replaceAll(RegExp(r'''[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]'''), ' ');

    // Strip leading English articles
    s = s.replaceAll(RegExp(r'^(?:the|a|an)\s+'), '');

    // Collapse multiple whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Calculates Levenshtein distance between two normalized strings.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  /// Calculates combined title similarity score in range [0.0, 1.0].
  static double calculateTitleSimilarity(String titleA, String titleB) {
    final normA = normalizeTitle(titleA);
    final normB = normalizeTitle(titleB);

    if (normA == normB) return 1.0;
    if (normA.isEmpty || normB.isEmpty) return 0.0;

    // String Levenshtein ratio
    final maxLen = max(normA.length, normB.length);
    final distance = levenshteinDistance(normA, normB);
    final levScore = (1.0 - (distance / maxLen)).clamp(0.0, 1.0);

    // Stop words to exclude from token comparison for movie titles
    const stopWords = {'the', 'a', 'an', 'of', 'and', 'in', 'on', 'at', 'to'};
    final tokensA = normA
        .split(' ')
        .where((t) => t.isNotEmpty && !stopWords.contains(t))
        .toSet();
    final tokensB = normB
        .split(' ')
        .where((t) => t.isNotEmpty && !stopWords.contains(t))
        .toSet();

    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    final jaccardScore = union > 0 ? (intersection / union) : 0.0;

    return ((levScore * 0.5) + (jaccardScore * 0.5)).clamp(0.0, 1.0);
  }

  /// Evaluates an individual Archive candidate against a target Movie using matching rules:
  /// - Exact title + matching year: strongest candidate (score >= 0.95).
  /// - Similar title + matching year: require additional verification (score ~0.80).
  /// - Different release year (>= 5 years): Remake / Different version detection -> REJECTED.
  /// - Ambiguous candidates: flagged for rejection.
  MatchEvaluation evaluateCandidate(Movie movie, InternetArchiveMovie candidate) {
    final normMovie = normalizeTitle(movie.title);
    final normCandidate = normalizeTitle(candidate.title);
    final isExactTitle = normMovie == normCandidate;
    final titleSim = calculateTitleSimilarity(movie.title, candidate.title);

    final movieYear = movie.year;
    final candidateYear = candidate.year;

    bool isYearMatch = false;
    bool isRemakeMismatch = false;
    double yearFactor = 0.0;

    if (movieYear != null && candidateYear != null) {
      final diff = (movieYear - candidateYear).abs();
      if (diff == 0) {
        isYearMatch = true;
        yearFactor = 1.0;
      } else if (diff == 1) {
        // Minor variance (festival release vs copyright vs distribution)
        isYearMatch = true;
        yearFactor = 0.85;
      } else {
        // Remake / different film detection
        isRemakeMismatch = true;
        yearFactor = 0.0;
      }
    } else {
      // Year is missing in one source
      yearFactor = isExactTitle ? 0.70 : 0.40;
    }

    // Remakes must NEVER be confused with original movies
    if (isRemakeMismatch) {
      return MatchEvaluation(
        candidate: candidate,
        titleSimilarity: titleSim,
        confidenceScore: 0.0,
        isYearMatch: false,
        isRemakeMismatch: true,
        isAmbiguous: false,
        notes: 'Rejected: Release year mismatch ($movieYear vs $candidateYear) indicates different release or remake.',
      );
    }

    // Title similarity threshold check
    if (titleSim < 0.70) {
      return MatchEvaluation(
        candidate: candidate,
        titleSimilarity: titleSim,
        confidenceScore: 0.0,
        isYearMatch: isYearMatch,
        isRemakeMismatch: false,
        isAmbiguous: false,
        notes: 'Rejected: Title similarity ${titleSim.toStringAsFixed(2)} is below minimum threshold.',
      );
    }

    // Compute composite confidence score
    double score = isExactTitle
        ? (0.60 + (0.40 * yearFactor))
        : ((titleSim * 0.60) + (0.40 * yearFactor));

    return MatchEvaluation(
      candidate: candidate,
      titleSimilarity: titleSim,
      confidenceScore: score.clamp(0.0, 1.0),
      isYearMatch: isYearMatch,
      isRemakeMismatch: false,
      isAmbiguous: false,
      notes: isExactTitle && isYearMatch
          ? 'Strongest candidate: Exact title and matching release year.'
          : 'Candidate verified with similarity score ${score.toStringAsFixed(2)}.',
    );
  }

  /// Checks availability for a movie with caching, deduplication, and safety checks.
  Future<MovieAvailability> checkAvailability(
    Movie movie, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = movie.id.trim().isNotEmpty ? movie.id.trim() : movie.title.trim().toLowerCase();

    // 1. Check existing cache
    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        return cached.availability;
      }
    }

    // 2. Prevent duplicate in-flight requests for the same movie
    if (_inFlight.containsKey(cacheKey)) {
      return _inFlight[cacheKey]!;
    }

    final future = _resolveAvailability(movie);
    _inFlight[cacheKey] = future;

    try {
      final result = await future;
      _cache[cacheKey] = _CacheEntry(
        availability: result,
        expiresAt: DateTime.now().add(cacheTtl),
      );
      return result;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<MovieAvailability> _resolveAvailability(Movie movie) async {
    final normTitle = normalizeTitle(movie.title);

    // Fast check for known curated mappings (e.g., Chaplin, Romero classics)
    String? preferredId;
    if (movie.year != null) {
      preferredId = curatedMovieMap['$normTitle ${movie.year}'] ?? curatedMovieMap[normTitle];
    } else {
      preferredId = curatedMovieMap[normTitle];
    }

    // Modern recent movies (post-1980) without curated mapping are strictly metadata-only
    // unless explicitly verified, preventing inappropriate archive searches for modern commercial blockbusters
    if (movie.year != null && movie.year! > 1980 && preferredId == null) {
      return MovieAvailability.metadataOnly(
        reason: 'Modern commercial release (${movie.year}). Streaming rights not held in open public domain archive.',
      );
    }

    try {
      List<InternetArchiveMovie> searchResults = [];

      if (preferredId != null) {
        try {
          final curated = await _archiveService
              .getItemMetadata(preferredId)
              .timeout(requestTimeout);
          searchResults = [curated];
        } catch (_) {
          // If metadata call fails, fall back to search query
          searchResults = await _archiveService
              .searchMovies(movie.title, rows: 10)
              .timeout(requestTimeout);
        }
      } else {
        searchResults = await _archiveService
            .searchMovies(movie.title, rows: 10)
            .timeout(requestTimeout);
      }

      if (searchResults.isEmpty) {
        return MovieAvailability.noMatch(
          reason: 'No archive records found for "${movie.title}".',
        );
      }

      // Evaluate each candidate
      final evaluations = <MatchEvaluation>[];
      for (final candidate in searchResults) {
        final eval = evaluateCandidate(movie, candidate);
        if (eval.confidenceScore >= 0.75 && !eval.isRemakeMismatch) {
          evaluations.add(eval);
        }
      }

      if (evaluations.isEmpty) {
        return MovieAvailability.noMatch(
          reason: 'Archive items found, but none matched the movie title and year criteria.',
        );
      }

      // Sort by confidence score descending
      evaluations.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));

      // Ambiguity detection: if top 2 candidates have virtually identical scores
      // but differ in identifier / year, reject ambiguous match
      if (evaluations.length >= 2) {
        final top1 = evaluations[0];
        final top2 = evaluations[1];
        if ((top1.confidenceScore - top2.confidenceScore).abs() < 0.05 &&
            top1.candidate.identifier != top2.candidate.identifier &&
            top1.candidate.year != top2.candidate.year) {
          return MovieAvailability.noMatch(
            reason: 'Ambiguous match between multiple conflicting Archive candidates; streaming rejected.',
          );
        }
      }

      final bestMatch = evaluations.first;
      var candidateMovie = bestMatch.candidate;

      // 1. RIGHTS VERIFICATION: Never assume Internet Archive hosting means commercial streaming rights
      if (!candidateMovie.rightsInfo.isCommercialReady) {
        return MovieAvailability.rightsNotVerified(
          candidate: candidateMovie,
          reason: 'Rights unverified: ${candidateMovie.rightsInfo.summary}. Commercial streaming is prohibited.',
        );
      }

      // 2. TECHNICAL PLAYBACK CHECK: Direct MP4 verification
      var primaryVideo = candidateMovie.primaryPlayableVideo;
      if (primaryVideo == null) {
        // Fetch full metadata if search doc did not include files list
        try {
          candidateMovie = await _archiveService
              .getItemMetadata(candidateMovie.identifier)
              .timeout(requestTimeout);
          primaryVideo = candidateMovie.primaryPlayableVideo;
        } catch (_) {
          return MovieAvailability.videoUnavailable(
            candidate: candidateMovie,
            reason: 'Could not retrieve media files list for item ${candidateMovie.identifier}.',
          );
        }
      }

      if (primaryVideo == null || !primaryVideo.isDirectPlayableMp4) {
        return MovieAvailability.videoUnavailable(
          candidate: candidateMovie,
          reason: 'No direct playable MP4 video file found for item ${candidateMovie.identifier}.',
        );
      }

      // 3. STREAM ACCESSIBILITY: Confirm the file URL responds before exposing playback.
      final streamAccessible = await _archiveService
          .checkFileAccessibility(primaryVideo.downloadUrl);

      if (!streamAccessible) {
        return MovieAvailability.videoUnavailable(
          candidate: candidateMovie,
          reason:
              'Verified video file exists, but its stream URL is not reachable for item ${candidateMovie.identifier}.',
        );
      }

      // Passed rights, technical playback, and stream accessibility checks.
      return MovieAvailability.available(
        matchedMovie: candidateMovie,
        videoFile: primaryVideo,
        confidenceScore: bestMatch.confidenceScore,
      );
    } on TimeoutException {
      return MovieAvailability.noMatch(
        reason: 'Archive availability check timed out. Showing metadata only.',
      );
    } catch (e) {
      return MovieAvailability.noMatch(
        reason: 'Availability check encountered an error: $e',
      );
    }
  }

  /// Batch checks availability for a list of movies without blocking.
  Future<Map<String, MovieAvailability>> checkMultipleAvailability(
    List<Movie> movies,
  ) async {
    final results = <String, MovieAvailability>{};
    final futures = <Future<void>>[];

    for (final movie in movies) {
      futures.add(() async {
        final avail = await checkAvailability(movie);
        results[movie.id] = avail;
      }());
    }

    await Future.wait(futures);
    return results;
  }

  /// Clears internal in-memory cache (useful for testing or pull-to-refresh).
  void clearCache() {
    _cache.clear();
  }

  /// Inspects current cache size.
  int get cacheCount => _cache.length;
}
