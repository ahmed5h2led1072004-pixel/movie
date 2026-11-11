import '../models/movie.dart';
import 'movie_matching_service.dart';
import 'yts_api_service.dart';

/// Movie catalog boundary for YTS results and the existing local catalog.
class MovieRepository {
  const MovieRepository({this.apiService});

  final YtsApiService? apiService;

  List<Movie> get movies => localMovies;

  /// Loads remote movies when a YTS service is provided. On an API failure,
  /// local data remains available in [MovieFetchResult] as a fallback, while
  /// [MovieFetchResult.error] preserves the failure for the caller to report.
  Future<MovieFetchResult> fetchMovies({
    int limit = 20,
    int page = 1,
    String? queryTerm,
    String? genre,
    String? sortBy,
  }) async {
    final service = apiService;
    final fallback = genre != null && genre.trim().isNotEmpty
        ? byGenre(genre)
        : movies;
    if (service == null) {
      return MovieFetchResult(movies: fallback, usedLocalFallback: true);
    }

    try {
      final remoteMovies = await service.fetchMovies(
        limit: limit,
        page: page,
        queryTerm: queryTerm,
        genre: genre,
        sortBy: sortBy,
      );
      return MovieFetchResult(movies: remoteMovies);
    } on Object catch (error) {
      return MovieFetchResult(
        movies: fallback,
        usedLocalFallback: true,
        error: error,
      );
    }
  }

  static const int _searchApiPageSize = 50;
  static const int _searchMaxApiPages = 4;
  static const int _strongMatchScore = 6000;
  static const Set<String> _searchStopWords = {
    'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for',
    'with', 'from', 'by', 'vs', 'v',
  };

  /// Searches the remote catalog only. Unlike [fetchMovies], failures never
  /// fall back to local movies because they would not match the user's query.
  ///
  /// YTS returns at most `limit` results per page in non-relevance order, so a
  /// complete title can sit beyond the first page. This walks up to
  /// [_searchMaxApiPages] pages, ranks all candidates against the query, and
  /// returns the most relevant [limit] movies (exact title matches first).
  Future<MovieFetchResult> searchRemote(
    String query, {
    int limit = 20,
    int page = 1,
  }) async {
    final queryTerm =
        query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (queryTerm.length < 2) {
      return const MovieFetchResult(movies: []);
    }

    final service = apiService;
    if (service == null) {
      return MovieFetchResult(
        movies: const [],
        error: StateError('The YTS API service is not configured.'),
      );
    }

    try {
      var candidates = await _fetchSearchCandidates(service, queryTerm);
      var ranked = _rankSearchResults(candidates, queryTerm);

      // YTS matches whole words, so a partial word such as "Dark Knigh"
      // returns nothing even when "The Dark Knight" exists. Retry with the
      // individual query words and rank the merged candidates.
      final matchTokens = _matchTokens(_tokenize(queryTerm));
      if (!ranked.hasStrongMatches && matchTokens.length > 1) {
        final fallbackMovies =
            await _fetchTokenFallback(service, matchTokens);
        if (fallbackMovies.isNotEmpty) {
          candidates = [...candidates, ...fallbackMovies];
          ranked = _rankSearchResults(candidates, queryTerm);
        }
      }

      return MovieFetchResult(
        movies: ranked.movies.take(limit).toList(growable: false),
      );
    } on Object catch (error) {
      return MovieFetchResult(movies: const [], error: error);
    }
  }

  Future<List<Movie>> _fetchSearchCandidates(
    YtsApiService service,
    String queryTerm,
  ) async {
    final firstPage = await service.fetchMoviePage(
      limit: _searchApiPageSize,
      page: 1,
      queryTerm: queryTerm,
    );
    final movies = <Movie>[...firstPage.movies];

    final pageSize =
        firstPage.limit > 0 ? firstPage.limit : _searchApiPageSize;
    final availablePages =
        ((firstPage.totalCount + pageSize - 1) ~/ pageSize).clamp(
      1,
      _searchMaxApiPages,
    );

    if (availablePages > 1) {
      final remainingPages = await Future.wait([
        for (var page = 2; page <= availablePages; page++)
          _tryFetchSearchPage(service, queryTerm, page),
      ]);
      for (final page in remainingPages) {
        if (page != null) movies.addAll(page.movies);
      }
    }

    return movies;
  }

  Future<List<Movie>> _fetchTokenFallback(
    YtsApiService service,
    List<String> matchTokens,
  ) async {
    final tokens =
        matchTokens.where((token) => token.length >= 3).take(3).toList();
    if (tokens.length < 2) return const [];

    final pages = await Future.wait([
      for (final token in tokens) _tryFetchSearchPage(service, token, 1),
    ]);
    return [
      for (final page in pages) ...?page?.movies,
    ];
  }

  Future<YtsMoviePage?> _tryFetchSearchPage(
    YtsApiService service,
    String queryTerm,
    int page,
  ) async {
    try {
      return await service.fetchMoviePage(
        limit: _searchApiPageSize,
        page: page,
        queryTerm: queryTerm,
      );
    } on Object {
      return null;
    }
  }

  _RankedSearch _rankSearchResults(
    List<Movie> candidates,
    String queryTerm,
  ) {
    final normalizedQuery = _normalizeSearchText(queryTerm);
    final queryTokens = _tokenize(normalizedQuery);
    final matchTokens = _matchTokens(queryTokens);
    final compactQuery = normalizedQuery.replaceAll(' ', '');

    final scored = <_ScoredSearchMovie>[];
    for (var index = 0; index < candidates.length; index++) {
      final movie = candidates[index];
      final normalizedTitle = _normalizeSearchText(movie.title);
      final titleTokens = _tokenize(normalizedTitle);
      final score = _scoreSearchMatch(
        normalizedQuery: normalizedQuery,
        compactQuery: compactQuery,
        normalizedTitle: normalizedTitle,
        titleTokens: titleTokens,
        titleMatchTokens: _matchTokens(titleTokens),
        queryTokens: queryTokens,
        matchTokens: matchTokens,
      );
      scored.add(
        _ScoredSearchMovie(movie: movie, score: score, order: index),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });

    final strong =
        scored.where((entry) => entry.score >= _strongMatchScore).toList();
    final relevant = strong.isNotEmpty
        ? strong
        : scored.where((entry) => entry.score > 0).toList();
    final pool = relevant.isNotEmpty ? relevant : scored;

    final seenIds = <String>{};
    final movies = <Movie>[];
    for (final entry in pool) {
      final id = entry.movie.id.trim();
      final key =
          id.isNotEmpty ? id : '${entry.movie.title}|${entry.movie.year}';
      if (seenIds.add(key)) movies.add(entry.movie);
    }

    return _RankedSearch(
      movies: movies,
      hasStrongMatches: strong.isNotEmpty,
    );
  }

  int _scoreSearchMatch({
    required String normalizedQuery,
    required String compactQuery,
    required String normalizedTitle,
    required List<String> titleTokens,
    required List<String> titleMatchTokens,
    required List<String> queryTokens,
    required List<String> matchTokens,
  }) {
    if (normalizedQuery.isEmpty || normalizedTitle.isEmpty) return 0;

    if (normalizedTitle == normalizedQuery) return 10000;

    final compactTitle = normalizedTitle.replaceAll(' ', '');
    if (compactTitle == compactQuery) return 9500;

    if (normalizedTitle.startsWith('$normalizedQuery ')) return 9000;
    if ((' $normalizedTitle ').contains(' $normalizedQuery ')) return 8000;

    final tokensToMatch =
        matchTokens.isEmpty ? queryTokens : matchTokens;
    final titlesToMatch =
        matchTokens.isEmpty ? titleTokens : titleMatchTokens;
    if (tokensToMatch.isEmpty || titlesToMatch.isEmpty) return 0;

    var matched = 0;
    for (final token in tokensToMatch) {
      if (titlesToMatch.any((titleToken) => titleToken.startsWith(token))) {
        matched++;
      }
    }

    if (matched == tokensToMatch.length) {
      final extraTokens = titlesToMatch.length - matched;
      final precision =
          tokensToMatch.length / (tokensToMatch.length + extraTokens);
      return _strongMatchScore + (precision * 500).round();
    }

    if (matched > 0) {
      return 1000 + ((matched / tokensToMatch.length) * 1000).round();
    }
    return 0;
  }

  String _normalizeSearchText(String value) =>
      MovieMatchingService.normalizeTitle(value);

  List<String> _tokenize(String normalized) => normalized.isEmpty
      ? const []
      : normalized
          .split(' ')
          .where((token) => token.isNotEmpty)
          .toList(growable: false);

  List<String> _matchTokens(List<String> tokens) {
    final significant = tokens
        .where(
          (token) =>
              token.length > 1 && !_searchStopWords.contains(token),
        )
        .toList(growable: false);
    return significant.isEmpty ? tokens : significant;
  }

  List<Movie> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return movies
        .where((movie) => movie.title.toLowerCase().contains(normalized))
        .toList();
  }

  List<Movie> byGenre(String genre) => movies
      .where(
        (movie) => movie.genres.any(
          (item) => item.toLowerCase() == genre.toLowerCase(),
        ),
      )
      .toList();

  /// Fetches detailed movie information from YTS when an [apiService] is available.
  /// If the request fails, or no API service is provided, returns [fallbackMovie]
  /// or a matching local movie, with [MovieDetailsResult.usedFallback] set to true.
  Future<MovieDetailsResult> fetchMovieDetails(
    String movieId, {
    Movie? fallbackMovie,
  }) async {
    final effectiveFallback = fallbackMovie ??
        movies.cast<Movie?>().firstWhere(
              (m) => m?.id == movieId,
              orElse: () => null,
            ) ??
        Movie(id: movieId, title: 'Movie Details');

    final service = apiService;
    if (service == null) {
      return MovieDetailsResult(
        movie: effectiveFallback,
        usedFallback: true,
      );
    }

    try {
      final remoteDetails = await service.fetchMovieDetails(movieId);
      final merged = Movie(
        id: remoteDetails.id.isNotEmpty
            ? remoteDetails.id
            : effectiveFallback.id,
        title: remoteDetails.title.isNotEmpty &&
                remoteDetails.title != 'Unknown Movie'
            ? remoteDetails.title
            : effectiveFallback.title,
        year: remoteDetails.year ?? effectiveFallback.year,
        rating: remoteDetails.rating ?? effectiveFallback.rating,
        posterUrl: remoteDetails.posterUrl ?? effectiveFallback.posterUrl,
        largeCoverImageUrl: remoteDetails.largeCoverImageUrl ??
            effectiveFallback.largeCoverImageUrl,
        backgroundImageUrl: remoteDetails.backgroundImageUrl ??
            effectiveFallback.backgroundImageUrl,
        trailerCode: (remoteDetails.trailerCode != null &&
                remoteDetails.trailerCode!.isNotEmpty)
            ? remoteDetails.trailerCode
            : effectiveFallback.trailerCode,
        imageAsset: remoteDetails.imageAsset ?? effectiveFallback.imageAsset,
        genres: remoteDetails.genres.isNotEmpty
            ? remoteDetails.genres
            : effectiveFallback.genres,
        description: (remoteDetails.description != null &&
                remoteDetails.description!.isNotEmpty)
            ? remoteDetails.description
            : effectiveFallback.description,
        runtime: remoteDetails.runtime ?? effectiveFallback.runtime,
        language: remoteDetails.language ?? effectiveFallback.language,
        cast: remoteDetails.cast.isNotEmpty
            ? remoteDetails.cast
            : effectiveFallback.cast,
        availableQualities: remoteDetails.availableQualities.isNotEmpty
            ? remoteDetails.availableQualities
            : effectiveFallback.availableQualities,
        screenshots: remoteDetails.screenshots.isNotEmpty
            ? remoteDetails.screenshots
            : effectiveFallback.screenshots,
        ratingIsInImage: remoteDetails.ratingIsInImage,
      );
      return MovieDetailsResult(movie: merged);
    } on Object catch (error) {
      return MovieDetailsResult(
        movie: effectiveFallback,
        usedFallback: true,
        error: error,
      );
    }
  }

  static final Map<String, List<Movie>> _similarMoviesCache = {};
  static final Map<String, Future<List<Movie>>> _inFlightSimilar = {};

  /// Clears the in-memory cache of similar movies (useful for testing).
  static void clearSimilarMoviesCache() {
    _similarMoviesCache.clear();
    _inFlightSimilar.clear();
  }

  /// Retrieves dynamically ranked similar movie recommendations for [currentMovie].
  /// Guaranteed to return at most [limit] movies (defaults to 4).
  Future<List<Movie>> fetchSimilarMovies(
    Movie currentMovie, {
    int limit = 4,
  }) async {
    final cacheKey = currentMovie.id.trim();
    if (cacheKey.isNotEmpty && _similarMoviesCache.containsKey(cacheKey)) {
      return _similarMoviesCache[cacheKey]!;
    }

    if (cacheKey.isNotEmpty && _inFlightSimilar.containsKey(cacheKey)) {
      return _inFlightSimilar[cacheKey]!;
    }

    final future = _computeSimilarMovies(currentMovie, limit: limit);
    if (cacheKey.isNotEmpty) {
      _inFlightSimilar[cacheKey] = future;
    }

    try {
      final results = await future;
      if (cacheKey.isNotEmpty) {
        _similarMoviesCache[cacheKey] = results;
      }
      return results;
    } finally {
      if (cacheKey.isNotEmpty) {
        _inFlightSimilar.remove(cacheKey);
      }
    }
  }

  Future<List<Movie>> _computeSimilarMovies(
    Movie currentMovie, {
    int limit = 4,
  }) async {
    final candidatePool = <Movie>[];
    final seenIds = <String>{currentMovie.id};

    final service = apiService;
    var hadNetworkSuccess = false;
    Object? lastNetworkError;

    // 1. If numeric ID, try the dedicated YTS movie_suggestions endpoint
    if (service != null && int.tryParse(currentMovie.id) != null) {
      try {
        final suggestions = await service.fetchMovieSuggestions(currentMovie.id);
        hadNetworkSuccess = true;
        for (final m in suggestions) {
          if (seenIds.add(m.id)) {
            candidatePool.add(m);
          }
        }
      } catch (e) {
        lastNetworkError = e;
      }
    }

    // 2. Query candidates by the movie's genres
    final genres = currentMovie.genres;
    if (service != null && genres.isNotEmpty) {
      for (final genre in genres.take(3)) {
        if (candidatePool.length >= 25) break;
        try {
          final res = await service.fetchMovies(
            limit: 10,
            genre: genre,
            sortBy: 'download_count',
          );
          hadNetworkSuccess = true;
          for (final m in res) {
            if (seenIds.add(m.id)) {
              candidatePool.add(m);
            }
          }
        } catch (e) {
          lastNetworkError ??= e;
        }
      }
    }

    // If service was provided but every network request failed, rethrow error
    if (service != null && !hadNetworkSuccess && lastNetworkError != null) {
      throw lastNetworkError;
    }

    // 3. Fallback candidates from local catalog only when offline/unconfigured
    if (service == null) {
      for (final m in localMovies) {
        if (seenIds.add(m.id)) {
          candidatePool.add(m);
        }
      }
    }

    // 4. Calculate similarity score for each candidate and rank
    final scored = <MapEntry<Movie, double>>[];
    final currentTitleNorm = currentMovie.title.trim().toLowerCase();

    for (final candidate in candidatePool) {
      if (candidate.id == currentMovie.id) continue;
      if (candidate.title.trim().toLowerCase() == currentTitleNorm) continue;

      final score = _calculateSimilarityScore(currentMovie, candidate);
      if (score > 0) {
        scored.add(MapEntry(candidate, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    final effectiveLimit = limit.clamp(1, 4);
    return scored.take(effectiveLimit).map((e) => e.key).toList();
  }

  double _calculateSimilarityScore(Movie current, Movie candidate) {
    // Shared genres (primary factor: 3 points per shared genre)
    final currentGenres = current.genres.map((g) => g.trim().toLowerCase()).toSet();
    final candidateGenres = candidate.genres.map((g) => g.trim().toLowerCase()).toSet();
    final sharedGenres = currentGenres.intersection(candidateGenres);

    // Title keyword overlap (2 points per shared significant token)
    final currentKeywords = _extractTitleKeywords(current.title);
    final candidateKeywords = _extractTitleKeywords(candidate.title);
    final sharedKeywords = currentKeywords.intersection(candidateKeywords);

    // Hard requirement: must have at least one shared genre or shared title keyword
    if (sharedGenres.isEmpty && sharedKeywords.isEmpty) {
      return 0.0;
    }

    double score = 0.0;
    score += sharedGenres.length * 3.0;
    score += sharedKeywords.length * 2.0;

    // Release year proximity
    if (current.year != null && candidate.year != null) {
      final diff = (current.year! - candidate.year!).abs();
      if (diff <= 3) {
        score += 2.0;
      } else if (diff <= 7) {
        score += 1.0;
      } else if (diff > 25) {
        score -= 0.5;
      }
    }

    // Quality/Rating bonus
    if (candidate.rating != null && candidate.rating! > 0) {
      score += (candidate.rating! * 0.1);
    }

    return score;
  }

  Set<String> _extractTitleKeywords(String title) {
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for',
      'with', 'by', 'from', 'part', 'vol', 'volume', 'chapter', 'movie',
      'film', 'vs', '1', '2', '3', '4', '5', 'i', 'ii', 'iii', 'iv', 'v'
    };
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();
  }
}

class _ScoredSearchMovie {
  const _ScoredSearchMovie({
    required this.movie,
    required this.score,
    required this.order,
  });

  final Movie movie;
  final int score;
  final int order;
}

class _RankedSearch {
  const _RankedSearch({
    required this.movies,
    required this.hasStrongMatches,
  });

  final List<Movie> movies;
  final bool hasStrongMatches;
}

class MovieFetchResult {
  const MovieFetchResult({
    required this.movies,
    this.usedLocalFallback = false,
    this.error,
  });

  final List<Movie> movies;
  final bool usedLocalFallback;
  final Object? error;
}

class MovieDetailsResult {
  const MovieDetailsResult({
    required this.movie,
    this.usedFallback = false,
    this.error,
  });

  final Movie movie;
  final bool usedFallback;
  final Object? error;
}

const localMovies = <Movie>[
  Movie(
    id: 'black_widow',
    title: 'Black Widow',
    year: 2021,
    rating: 6.7,
    imageAsset: 'assets/search/black_widow_results.jpg',
    ratingIsInImage: true,
    genres: ['Action', 'Adventure'],
    description: 'Natasha Romanoff confronts her past.',
    runtime: 134,
  ),
  Movie(
    id: 'captain_first_avenger',
    title: 'Captain America: The First Avenger',
    year: 2011,
    rating: 6.9,
    imageAsset: 'assets/search/captain_first_avenger_results.jpg',
    ratingIsInImage: true,
    genres: ['Action', 'Adventure'],
    runtime: 124,
  ),
  Movie(
    id: 'iron_man_3',
    title: 'Iron Man 3',
    year: 2013,
    rating: 7.1,
    imageAsset: 'assets/search/iron_man_3_results.jpg',
    ratingIsInImage: true,
    genres: ['Action', 'Adventure'],
    runtime: 130,
  ),
  Movie(
    id: 'civil_war',
    title: 'Captain America: Civil War',
    year: 2016,
    rating: 7.8,
    imageAsset: 'assets/search/civil_war_results.jpg',
    ratingIsInImage: true,
    genres: ['Action', 'Drama', 'Adventure'],
    runtime: 147,
  ),
  Movie(
    id: 'the_avengers',
    title: 'The Avengers',
    year: 2012,
    rating: 8.0,
    imageAsset: 'assets/avengers_onboarding.jpg',
    genres: ['Action', 'Adventure', 'Fantasy'],
    runtime: 143,
  ),
  Movie(
    id: 'doctor_strange_multiverse_of_madness',
    title: 'Doctor Strange in the Multiverse of Madness',
    year: 2022,
    rating: 7.6,
    imageAsset: 'assets/doctor_strange_reviews_onboarding.jpg',
    genres: ['Action', 'Adventure', 'Fantasy'],
    description: 'Doctor Strange journeys into the multiverse to confront a powerful adversary.',
    runtime: 126,
    cast: [
      'Hayley Atwell',
      'Elizabeth Olsen',
      'Rachel McAdams',
      'Charlize Theron',
    ],
  ),
  Movie(
    id: 'joker',
    title: 'Joker',
    year: 2019,
    rating: 8.4,
    imageAsset: 'assets/search/joker_results.jpg',
    ratingIsInImage: true,
    genres: ['Drama'],
    runtime: 122,
  ),
  Movie(
    id: 'baby_driver',
    title: 'Baby Driver',
    year: 2017,
    rating: 7.6,
    imageAsset: 'assets/home/baby_driver.png',
    genres: ['Action', 'Drama'],
    runtime: 113,
  ),
  Movie(
    id: '1917',
    title: '1917',
    year: 2019,
    rating: 8.2,
    imageAsset: 'assets/home/1917_featured.png',
    genres: ['Drama'],
    runtime: 119,
  ),
  Movie(
    id: 'captain_america',
    title: 'Captain America',
    year: 2011,
    rating: 6.9,
    imageAsset: 'assets/home/captain_america_narrow.png',
    genres: ['Action', 'Adventure'],
  ),
  Movie(
    id: 'dark_knight',
    title: 'The Dark Knight',
    year: 2008,
    rating: 9.0,
    imageAsset: 'assets/home/dark_knight.png',
    genres: ['Action', 'Drama'],
    runtime: 152,
  ),
];
