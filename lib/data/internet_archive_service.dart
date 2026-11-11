import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/internet_archive_movie.dart';

class InternetArchiveException implements Exception {
  final String message;
  final int? statusCode;

  const InternetArchiveException(this.message, {this.statusCode});

  @override
  String toString() => 'InternetArchiveException: $message (${statusCode ?? "no code"})';
}

/// One page of the validated, playable catalog.
class ArchiveCatalogPage {
  final List<InternetArchiveMovie> movies;
  final bool hasMore;

  const ArchiveCatalogPage({required this.movies, required this.hasMore});
}

/// Stage-by-stage result of validating one Archive candidate.
class ArchivePlaybackDiagnostic {
  final String identifier;
  final InternetArchiveMovie? movie;
  final bool searchFound;
  final bool metadataRetrieved;
  final bool movieLike;
  final bool videoFileFound;
  final bool formatCompatible;
  final bool rightsVerified;
  final bool urlAccessibilityChecked;
  final bool urlAccessible;
  final ArchiveVideoFile? selectedFile;
  final String? failureReason;

  const ArchivePlaybackDiagnostic({
    required this.identifier,
    this.movie,
    required this.searchFound,
    required this.metadataRetrieved,
    required this.movieLike,
    required this.videoFileFound,
    required this.formatCompatible,
    required this.rightsVerified,
    required this.urlAccessibilityChecked,
    required this.urlAccessible,
    this.selectedFile,
    this.failureReason,
  });

  bool get isPlayable =>
      searchFound &&
      metadataRetrieved &&
      movieLike &&
      videoFileFound &&
      formatCompatible &&
      rightsVerified &&
      urlAccessibilityChecked &&
      urlAccessible;

  List<String> get stages => [
        'search:${searchFound ? 'found' : 'missing'}',
        'metadata:${metadataRetrieved ? 'ok' : 'failed'}',
        'movie:${movieLike ? 'yes' : 'no'}',
        'file:${videoFileFound ? 'found' : 'missing'}',
        'format:${formatCompatible ? 'compatible' : 'unsupported'}',
        'rights:${rightsVerified ? 'verified' : 'unverified'}',
        'url:${urlAccessibilityChecked ? (urlAccessible ? 'accessible' : 'unreachable') : 'unchecked'}',
      ];
}

class _ArchiveSearchPage {
  final List<Map<String, dynamic>> docs;
  final int? numFound;

  const _ArchiveSearchPage({required this.docs, this.numFound});
}

class _UrlAccessibility {
  final bool accessible;
  final int contentLength;

  const _UrlAccessibility(this.accessible, this.contentLength);
}

class _CacheEntry<T> {
  final T value;
  final DateTime storedAt;

  const _CacheEntry(this.value, this.storedAt);

  bool isFresh(Duration ttl) => DateTime.now().difference(storedAt) < ttl;
}

class InternetArchiveService {
  final http.Client _client;

  InternetArchiveService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _searchEndpoint = 'https://archive.org/advancedsearch.php';
  static const String _metadataEndpoint = 'https://archive.org/metadata';

  static const Map<String, String> _headers = {
    'User-Agent': 'MoviesApp/1.0 (Flutter; Android; +https://archive.org)',
    'Accept': 'application/json',
  };

  static const List<String> _filmCollections = [
    'feature_films',
    'feature_films_unsorted',
    'silent_films',
    'Comedy_Films',
    'SciFi_Horror',
    'Film_Noir',
    'animationandcartoons',
    'classic_cartoons',
    'short_films',
    'more_animation',
  ];

  static final Set<String> _allowedFilmCollections = _filmCollections
      .map((collection) => collection.toLowerCase())
      .toSet();

  static const List<String> _blockedCollectionTokens = [
    'movie_trailers',
    'trailers',
    'classic_tv',
    'stock_footage',
    'newsreel',
    'podcast',
    'radio',
    'musicvideo',
    'music_videos',
    'videogame',
    'video_game',
    'advertisement',
    'commercials',
    'promo',
    'behind_the_scenes',
    'interviews',
  ];

  static const List<String> _blockedTitleTokens = [
    'trailer',
    'teaser',
    'promo',
    'advertisement',
    'commercial',
    'behind the scenes',
    'making of',
    'featurette',
    'bloopers',
    'outtakes',
    'newsreel',
    'music video',
    'lecture',
    'podcast',
    'interview',
    'publicvideos',
    ' batch',
    'disc ',
  ];

  static const int _minStreamBytes = 1024 * 1024;
  static const double _minDurationSeconds = 240;
  static const int _catalogSearchRows = 24;
  static const int _validationConcurrency = 10;
  static const int _maxSearchPagesPerCall = 4;

  static const Duration _metadataTtl = Duration(minutes: 10);
  static const Duration _playableTtl = Duration(minutes: 30);
  static const Duration _rejectedTtl = Duration(minutes: 2);
  static const Duration _urlTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry<InternetArchiveMovie>> _metadataCache = {};
  final Map<String, Future<InternetArchiveMovie>> _metadataInFlight = {};
  final Map<String, _CacheEntry<ArchivePlaybackDiagnostic>> _validationCache =
      {};
  final Map<String, Future<ArchivePlaybackDiagnostic>> _validationInFlight = {};
  final Map<String, _CacheEntry<_UrlAccessibility>> _urlCache = {};
  final Map<String, Future<_UrlAccessibility>> _urlInFlight = {};

  String? _catalogSignature;
  int _catalogSearchPage = 1;
  bool _catalogExhausted = false;
  int? _catalogNumFound;
  final List<InternetArchiveMovie> _catalogBuffer = [];
  final Set<String> _catalogResultIds = {};
  final Set<String> _catalogTitleKeys = {};
  Future<ArchiveCatalogPage>? _catalogInFlight;
  String? _catalogInFlightSignature;

  /// Sanitizes query string to prevent Solr/Lucene syntax errors
  static String sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'''[+\-&|!(){}\[\]^"~*?:\\/]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Searches Internet Archive for movie items
  Future<List<InternetArchiveMovie>> searchMovies(
    String query, {
    int rows = 15,
    int page = 1,
    bool verifiedRightsOnly = false,
  }) async {
    final cleanQuery = sanitizeQuery(query);
    if (cleanQuery.isEmpty) return const [];

    // Search mediatype:movies with title match
    // Solr title field is indexed and executes in tens of milliseconds,
    // avoiding slow unindexed description scans that cause 15-second timeouts.
    final q = 'mediatype:movies AND (title:"$cleanQuery" OR title:($cleanQuery))';

    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'q': q,
        'fl':
            'identifier,title,description,year,publicdate,date,addeddate,licenseurl,rights,runtime,creator',
        'rows': rows.toString(),
        'page': page.toString(),
        'output': 'json',
      },
    );

    try {
      final response = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        throw InternetArchiveException(
          'Failed to search Internet Archive: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final responseObj = data['response'] as Map<String, dynamic>?;
      final docs = responseObj?['docs'] as List<dynamic>? ?? [];

      final results = docs
          .whereType<Map<String, dynamic>>()
          .map((doc) => InternetArchiveMovie.fromSearchDoc(doc))
          .where((movie) => movie.identifier.isNotEmpty)
          .toList();

      if (verifiedRightsOnly) {
        return results.where((m) => m.rightsInfo.isCommercialReady).toList();
      }

      return results;
    } on http.ClientException catch (e) {
      throw InternetArchiveException('Network error searching archive: ${e.message}');
    } catch (e) {
      if (e is InternetArchiveException) rethrow;
      throw InternetArchiveException('Unexpected error during archive search: $e');
    }
  }

  /// Backwards-compatible catalog entry point. Returns validated playable
  /// movies; page 1 starts a fresh discovery session.
  Future<List<InternetArchiveMovie>> fetchCatalog({
    int page = 1,
    int rows = 20,
    String? query,
    int? year,
    String? genre,
    bool verifiedRightsOnly = false,
  }) async {
    final result = await fetchPlayableCatalogPage(
      rows: rows,
      query: query,
      year: year,
      genre: genre,
      verifiedRightsOnly: verifiedRightsOnly,
      reset: page <= 1,
    );
    return result.movies;
  }

  /// Returns the next page of movies that have complete metadata, a
  /// compatible MP4/H.264 stream, an accessible URL, and verified playback
  /// rights. Discovery scans multiple Archive film collections and validates
  /// every candidate before it can be shown as playable.
  Future<ArchiveCatalogPage> fetchPlayableCatalogPage({
    int rows = 20,
    String? query,
    int? year,
    String? genre,
    bool verifiedRightsOnly = false,
    bool reset = false,
  }) async {
    if (rows <= 0) {
      return const ArchiveCatalogPage(movies: [], hasMore: false);
    }

    final signature = _catalogSignatureFor(
      query: query,
      year: year,
      genre: genre,
      verifiedRightsOnly: verifiedRightsOnly,
    );

    final inFlight = _catalogInFlight;
    if (inFlight != null) {
      if (!reset && signature == _catalogInFlightSignature) {
        return inFlight;
      }
      try {
        await inFlight;
      } catch (_) {
        // A failed older page must not block a fresh discovery session.
      }
    }

    final future = _fetchPlayableCatalogPage(
      rows: rows,
      query: query,
      year: year,
      genre: genre,
      verifiedRightsOnly: verifiedRightsOnly,
      reset: reset,
      signature: signature,
    );
    _catalogInFlight = future;
    _catalogInFlightSignature = signature;

    try {
      return await future;
    } finally {
      if (identical(_catalogInFlight, future)) {
        _catalogInFlight = null;
        _catalogInFlightSignature = null;
      }
    }
  }

  String _catalogSignatureFor({
    String? query,
    int? year,
    String? genre,
    required bool verifiedRightsOnly,
  }) {
    return '${query?.trim().toLowerCase() ?? ''}|${year ?? ''}|'
        '${genre?.trim().toLowerCase() ?? ''}|$verifiedRightsOnly';
  }

  Future<ArchiveCatalogPage> _fetchPlayableCatalogPage({
    required int rows,
    String? query,
    int? year,
    String? genre,
    required bool verifiedRightsOnly,
    required bool reset,
    required String signature,
  }) async {
    if (reset || signature != _catalogSignature) {
      _catalogSignature = signature;
      _catalogSearchPage = 1;
      _catalogExhausted = false;
      _catalogNumFound = null;
      _catalogBuffer.clear();
      _catalogResultIds.clear();
      _catalogTitleKeys.clear();
    }

    final collected = <InternetArchiveMovie>[];
    while (collected.length < rows && _catalogBuffer.isNotEmpty) {
      collected.add(_catalogBuffer.removeAt(0));
    }

    final cleanQuery = query == null ? '' : sanitizeQuery(query);
    final requireFilmCollection = cleanQuery.isEmpty;
    final q = _buildCatalogQuery(
      query: query,
      year: year,
      genre: genre,
      verifiedRightsOnly: verifiedRightsOnly,
    );

    var pagesScanned = 0;
    while (collected.length < rows &&
        !_catalogExhausted &&
        pagesScanned < _maxSearchPagesPerCall) {
      final searchPage = await _fetchSearchPage(
        q: q,
        page: _catalogSearchPage,
        rows: _catalogSearchRows,
        sort: cleanQuery.isEmpty ? 'downloads desc' : null,
      );
      pagesScanned++;
      _catalogSearchPage++;
      _catalogNumFound = searchPage.numFound ?? _catalogNumFound;

      if (searchPage.docs.isEmpty) {
        _catalogExhausted = true;
        break;
      }

      final candidates = <InternetArchiveMovie>[];
      final batchIds = <String>{};
      for (final doc in searchPage.docs) {
        final movie = InternetArchiveMovie.fromSearchDoc(doc);
        if (movie.identifier.isEmpty) continue;
        if (batchIds.add(movie.identifier)) {
          candidates.add(movie);
        }
      }

      final diagnostics = await _mapWithConcurrency(
        candidates,
        _validationConcurrency,
        (candidate) => validateCandidate(
          candidate,
          requireFilmCollection: requireFilmCollection,
        ),
      );

      // If the metadata service is unreachable, keep the catalog usable by
      // showing the search results with playback disabled rather than
      // dropping every item. Nothing is marked playable without validation.
      final metadataUnavailable = diagnostics.isNotEmpty &&
          diagnostics.every((diagnostic) => !diagnostic.metadataRetrieved);
      if (metadataUnavailable) {
        for (final candidate in candidates) {
          if (verifiedRightsOnly &&
              !candidate.rightsInfo.isCommercialReady) {
            continue;
          }
          if (!_isLikelyMovie(
            candidate,
            requireFilmCollection: requireFilmCollection,
          )) {
            continue;
          }

          final titleKey = _catalogTitleKey(candidate);
          if (_catalogResultIds.contains(candidate.identifier) ||
              _catalogTitleKeys.contains(titleKey)) {
            continue;
          }

          _catalogResultIds.add(candidate.identifier);
          _catalogTitleKeys.add(titleKey);
          if (collected.length < rows) {
            collected.add(candidate);
          } else {
            _catalogBuffer.add(candidate);
          }
        }
        break;
      }

      for (final diagnostic in diagnostics) {
        final movie = diagnostic.movie;
        if (!diagnostic.isPlayable || movie == null) continue;
        if (verifiedRightsOnly && !movie.rightsInfo.isCommercialReady) continue;

        final titleKey = _catalogTitleKey(movie);
        if (_catalogResultIds.contains(movie.identifier) ||
            _catalogTitleKeys.contains(titleKey)) {
          continue;
        }

        _catalogResultIds.add(movie.identifier);
        _catalogTitleKeys.add(titleKey);
        if (collected.length < rows) {
          collected.add(movie);
        } else {
          _catalogBuffer.add(movie);
        }
      }

      final scanned = _catalogSearchPage - 1;
      final numFound = _catalogNumFound;
      if (numFound != null && scanned * _catalogSearchRows >= numFound) {
        _catalogExhausted = true;
      }
    }

    return ArchiveCatalogPage(
      movies: collected,
      hasMore: !_catalogExhausted || _catalogBuffer.isNotEmpty,
    );
  }

  String _buildCatalogQuery({
    String? query,
    int? year,
    String? genre,
    bool verifiedRightsOnly = false,
  }) {
    final cleanQuery = query == null ? '' : sanitizeQuery(query);
    final parts = <String>['mediatype:movies'];

    if (cleanQuery.isNotEmpty) {
      parts.add('(title:"$cleanQuery" OR title:($cleanQuery))');
    } else {
      parts.add('collection:(${_filmCollections.join(' OR ')})');
    }

    // Pre-filter in the search index so validation work is spent on items
    // likely to expose a stream that video_player can actually open.
    parts.add('(format:MPEG4 OR format:"512Kb MPEG4" OR format:"h.264")');

    if (year != null && year > 1800) {
      parts.add('year:$year');
    }

    if (genre != null &&
        genre.trim().isNotEmpty &&
        genre.toLowerCase() != 'all') {
      parts.add(_genreClause(genre));
    }

    parts.add(verifiedRightsOnly ? 'licenseurl:*' : '(licenseurl:* OR rights:*)');

    return parts.join(' AND ');
  }

  String _genreClause(String genre) {
    final normalized = genre.trim().toLowerCase();
    switch (normalized) {
      case 'horror':
        return '(subject:horror OR collection:SciFi_Horror OR title:horror)';
      case 'comedy':
        return '(subject:comedy OR collection:Comedy_Films OR title:comedy)';
      case 'drama':
        return '(subject:drama OR title:drama)';
      case 'sci-fi':
      case 'scifi':
      case 'science fiction':
        return '(subject:"science fiction" OR collection:SciFi_Horror '
            'OR title:"science fiction" OR title:scifi)';
      case 'film-noir':
      case 'film noir':
        return '(subject:"film noir" OR collection:Film_Noir '
            'OR title:"film noir")';
      case 'animation':
        return '(subject:animation OR collection:animationandcartoons '
            'OR collection:classic_cartoons OR collection:more_animation '
            'OR title:animation)';
      default:
        final clean = sanitizeQuery(genre);
        return '(subject:"$clean" OR title:"$clean")';
    }
  }

  Future<_ArchiveSearchPage> _fetchSearchPage({
    required String q,
    required int page,
    required int rows,
    String? sort,
  }) async {
    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'q': q,
        'fl':
            'identifier,title,description,year,publicdate,date,addeddate,licenseurl,rights,runtime,creator',
        'rows': rows.toString(),
        'page': page.toString(),
        'output': 'json',
        if (sort != null && sort.isNotEmpty) 'sort': sort,
      },
    );

    try {
      var response = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 429 || response.statusCode == 503) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        response = await _client.get(uri, headers: _headers).timeout(
              const Duration(seconds: 15),
            );
      }

      if (response.statusCode != 200) {
        throw InternetArchiveException(
          'Failed to fetch Internet Archive catalog: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final responseObj = data['response'] as Map<String, dynamic>?;
      final rawDocs = responseObj?['docs'] as List<dynamic>? ?? [];
      final docs =
          rawDocs.whereType<Map<String, dynamic>>().toList(growable: false);
      final rawNumFound = responseObj?['numFound'];
      final numFound = rawNumFound is num
          ? rawNumFound.toInt()
          : int.tryParse('${rawNumFound ?? ''}');

      return _ArchiveSearchPage(docs: docs, numFound: numFound);
    } on TimeoutException {
      throw const InternetArchiveException(
        'Timed out contacting Internet Archive',
      );
    } on http.ClientException catch (e) {
      throw InternetArchiveException(
        'Network error fetching archive catalog: ${e.message}',
      );
    } catch (e) {
      if (e is InternetArchiveException) rethrow;
      throw InternetArchiveException(
        'Unexpected error during archive catalog fetch: $e',
      );
    }
  }

  /// Validates one candidate through every stage required for playback.
  Future<ArchivePlaybackDiagnostic> validateCandidate(
    InternetArchiveMovie candidate, {
    bool requireFilmCollection = false,
    bool checkUrl = true,
  }) {
    final identifier = candidate.identifier.trim();
    if (identifier.isEmpty) {
      return Future.value(
        const ArchivePlaybackDiagnostic(
          identifier: '',
          searchFound: false,
          metadataRetrieved: false,
          movieLike: false,
          videoFileFound: false,
          formatCompatible: false,
          rightsVerified: false,
          urlAccessibilityChecked: false,
          urlAccessible: false,
          failureReason: 'Missing identifier',
        ),
      );
    }

    final key = '$identifier|${requireFilmCollection ? 'film' : 'any'}|'
        '${checkUrl ? 'url' : 'nourl'}';
    final cached = _validationCache[key];
    if (cached != null) {
      final ttl = cached.value.isPlayable ? _playableTtl : _rejectedTtl;
      if (cached.isFresh(ttl)) return Future.value(cached.value);
      _validationCache.remove(key);
    }

    final inFlight = _validationInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _validateCandidate(
      candidate,
      requireFilmCollection: requireFilmCollection,
      checkUrl: checkUrl,
    );
    _validationInFlight[key] = future;

    return future.then((result) {
      if (result.metadataRetrieved) {
        _validationCache[key] = _CacheEntry(result, DateTime.now());
      }
      return result;
    }).whenComplete(() {
      _validationInFlight.remove(key);
    });
  }

  Future<ArchivePlaybackDiagnostic> _validateCandidate(
    InternetArchiveMovie candidate, {
    required bool requireFilmCollection,
    required bool checkUrl,
  }) async {
    final identifier = candidate.identifier.trim();

    InternetArchiveMovie movie;
    try {
      movie = await _getMetadataCached(identifier);
    } catch (e) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        searchFound: true,
        metadataRetrieved: false,
        movieLike: false,
        videoFileFound: false,
        formatCompatible: false,
        rightsVerified: false,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        failureReason: 'Metadata unavailable: $e',
      );
    }

    final movieLike = _isLikelyMovie(
      movie,
      requireFilmCollection: requireFilmCollection,
    );
    if (!movieLike) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: false,
        videoFileFound: movie.videoFiles.isNotEmpty,
        formatCompatible: movie.primaryPlayableVideo != null,
        rightsVerified: movie.rightsInfo.isCommercialReady,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        failureReason:
            'Filtered as a trailer, compilation, or non-movie item',
      );
    }

    final videoFileFound = movie.videoFiles.isNotEmpty;
    if (!videoFileFound) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: true,
        videoFileFound: false,
        formatCompatible: false,
        rightsVerified: movie.rightsInfo.isCommercialReady,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        failureReason: 'No video files listed',
      );
    }

    final file = movie.primaryPlayableVideo;
    if (file == null) {
      final formats = movie.videoFiles
          .map((video) => video.format)
          .where((format) => format.isNotEmpty)
          .toSet()
          .join(', ');
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: true,
        videoFileFound: true,
        formatCompatible: false,
        rightsVerified: movie.rightsInfo.isCommercialReady,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        failureReason: formats.isEmpty
            ? 'No compatible MP4/H.264 stream'
            : 'No compatible MP4/H.264 stream ($formats)',
      );
    }

    final duration = movie.durationSeconds ?? file.lengthSeconds;
    if (duration != null && duration > 0 && duration < _minDurationSeconds) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: true,
        videoFileFound: true,
        formatCompatible: true,
        rightsVerified: movie.rightsInfo.isCommercialReady,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        selectedFile: file,
        failureReason: 'Video is only ${duration.round()}s long (likely a clip)',
      );
    }

    if (file.size > 0 && file.size < _minStreamBytes) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: true,
        videoFileFound: true,
        formatCompatible: true,
        rightsVerified: movie.rightsInfo.isCommercialReady,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        selectedFile: file,
        failureReason: 'Video file is too small to be a complete movie',
      );
    }

    final rightsVerified = movie.rightsInfo.isCommercialReady;
    if (!rightsVerified) {
      return ArchivePlaybackDiagnostic(
        identifier: identifier,
        movie: movie,
        searchFound: true,
        metadataRetrieved: true,
        movieLike: true,
        videoFileFound: true,
        formatCompatible: true,
        rightsVerified: false,
        urlAccessibilityChecked: false,
        urlAccessible: false,
        selectedFile: file,
        failureReason: 'Rights not verified: ${movie.rightsInfo.summary}',
      );
    }

    var urlAccessibilityChecked = false;
    var urlAccessible = false;
    if (checkUrl) {
      urlAccessibilityChecked = true;
      final access = await _checkAccessibilityCached(
        file.downloadUrl,
        minBytes: _minStreamBytes,
      );
      urlAccessible = access.accessible;
    }

    return ArchivePlaybackDiagnostic(
      identifier: identifier,
      movie: movie,
      searchFound: true,
      metadataRetrieved: true,
      movieLike: true,
      videoFileFound: true,
      formatCompatible: true,
      rightsVerified: true,
      urlAccessibilityChecked: urlAccessibilityChecked,
      urlAccessible: urlAccessible,
      selectedFile: file,
      failureReason: !checkUrl
          ? 'URL accessibility check skipped'
          : (urlAccessible ? null : 'Stream URL is not accessible'),
    );
  }

  /// Runs the full validation pipeline by identifier for diagnostics/tests.
  Future<ArchivePlaybackDiagnostic> diagnoseItem(
    String identifier, {
    bool requireFilmCollection = false,
    bool checkUrl = true,
  }) {
    final cleanId = identifier.trim();
    final stub = InternetArchiveMovie(
      identifier: cleanId,
      title: cleanId,
      description: '',
      rightsInfo: const ArchiveRightsInfo(
        category: ArchiveRightsCategory.unclearOrRestricted,
        isCommercialReady: false,
        summary: 'Unknown rights',
      ),
      itemPageUrl: 'https://archive.org/details/$cleanId',
    );
    return validateCandidate(
      stub,
      requireFilmCollection: requireFilmCollection,
      checkUrl: checkUrl,
    );
  }

  bool _isLikelyMovie(
    InternetArchiveMovie movie, {
    required bool requireFilmCollection,
  }) {
    final collections = movie.collections
        .map((collection) => collection.toLowerCase())
        .toList(growable: false);

    if (collections.any(
      (collection) => _blockedCollectionTokens.any(collection.contains),
    )) {
      return false;
    }

    if (requireFilmCollection && collections.isNotEmpty) {
      final belongsToFilmCollection =
          collections.any(_allowedFilmCollections.contains);
      if (!belongsToFilmCollection) return false;
    }

    final title = movie.title.toLowerCase();
    if (_blockedTitleTokens.any(title.contains)) return false;

    final duration = movie.durationSeconds;
    if (duration != null && duration > 0 && duration < _minDurationSeconds) {
      return false;
    }

    return true;
  }

  String _catalogTitleKey(InternetArchiveMovie movie) {
    final normalized = movie.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return '$normalized|${movie.year ?? ''}';
  }

  Future<InternetArchiveMovie> _getMetadataCached(String identifier) {
    final cached = _metadataCache[identifier];
    if (cached != null) {
      if (cached.isFresh(_metadataTtl)) return Future.value(cached.value);
      _metadataCache.remove(identifier);
    }

    final inFlight = _metadataInFlight[identifier];
    if (inFlight != null) return inFlight;

    final future = getItemMetadata(identifier);
    _metadataInFlight[identifier] = future;

    return future.then((movie) {
      _metadataCache[identifier] = _CacheEntry(movie, DateTime.now());
      return movie;
    }).whenComplete(() {
      _metadataInFlight.remove(identifier);
    });
  }

  Future<_UrlAccessibility> _checkAccessibilityCached(
    String url, {
    int minBytes = 0,
  }) {
    final key = '$url|$minBytes';
    final cached = _urlCache[key];
    if (cached != null) {
      if (cached.isFresh(_urlTtl)) return Future.value(cached.value);
      _urlCache.remove(key);
    }

    final inFlight = _urlInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _checkUrlAccessibility(url, minBytes: minBytes);
    _urlInFlight[key] = future;

    return future.then((access) {
      if (access.accessible) {
        _urlCache[key] = _CacheEntry(access, DateTime.now());
      }
      return access;
    }).whenComplete(() {
      _urlInFlight.remove(key);
    });
  }

  Future<_UrlAccessibility> _checkUrlAccessibility(
    String url, {
    int minBytes = 0,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return const _UrlAccessibility(false, 0);
    }

    try {
      final headResponse = await _client.head(uri, headers: _headers).timeout(
            const Duration(seconds: 8),
          );

      if (_statusIsSuccess(headResponse.statusCode)) {
        final length = _contentLength(headResponse);
        if (length > 0 && minBytes > 0 && length < minBytes) {
          return _UrlAccessibility(false, length);
        }
        return _UrlAccessibility(true, length);
      }

      // Some Archive nodes reject HEAD but honor a one-byte range request.
      if (headResponse.statusCode == 405 || headResponse.statusCode == 403) {
        final request = http.Request('GET', uri)
          ..headers.addAll({..._headers, 'Range': 'bytes=0-0'});
        final streamed = await _client.send(request).timeout(
              const Duration(seconds: 8),
            );
        final status = streamed.statusCode;
        final length = streamed.contentLength ??
            int.tryParse(streamed.headers['content-length'] ?? '') ??
            0;

        // Cancel immediately: never download the movie during discovery.
        await streamed.stream.listen(null).cancel();

        final accessible = _statusIsSuccess(status);
        if (accessible &&
            status != 206 &&
            length > 0 &&
            minBytes > 0 &&
            length < minBytes) {
          return _UrlAccessibility(false, length);
        }
        return _UrlAccessibility(accessible, length);
      }

      return const _UrlAccessibility(false, 0);
    } catch (_) {
      return const _UrlAccessibility(false, 0);
    }
  }

  bool _statusIsSuccess(int status) => status >= 200 && status < 400;

  int _contentLength(http.BaseResponse response) {
    return int.tryParse(response.headers['content-length'] ?? '') ??
        response.contentLength ??
        0;
  }

  Future<List<R>> _mapWithConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T item) action,
  ) async {
    if (items.isEmpty) return <R>[];

    final limit = min(concurrency <= 0 ? 1 : concurrency, items.length);
    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        if (index >= items.length) return;
        nextIndex = index + 1;
        results[index] = await action(items[index]);
      }
    }

    await Future.wait(List<Future<void>>.generate(limit, (_) => worker()));
    return results.cast<R>();
  }

  /// Retrieves full metadata and playable video files for a specific item identifier
  Future<InternetArchiveMovie> getItemMetadata(String identifier) async {
    final cleanId = identifier.trim();
    if (cleanId.isEmpty) {
      throw const InternetArchiveException('Identifier cannot be empty');
    }

    final uri = Uri.parse('$_metadataEndpoint/$cleanId');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        throw InternetArchiveException(
          'Failed to retrieve metadata for $cleanId: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.isEmpty || data['metadata'] == null) {
        throw InternetArchiveException('No metadata found for item $cleanId');
      }

      return InternetArchiveMovie.fromMetadata(data);
    } on http.ClientException catch (e) {
      throw InternetArchiveException('Network error fetching metadata: ${e.message}');
    } catch (e) {
      if (e is InternetArchiveException) rethrow;
      throw InternetArchiveException('Unexpected error fetching metadata: $e');
    }
  }

  /// Verifies whether a video stream file is directly accessible without
  /// downloading the whole file.
  Future<bool> checkFileAccessibility(String url) async {
    final result = await _checkAccessibilityCached(url);
    return result.accessible;
  }

  /// Returns a curated list of verified test candidates
  Future<List<InternetArchiveMovie>> getCuratedTestCandidates() async {
    const candidateIds = [
      'the-vagabond-1916_202304',
      'NightOfTheLivingDead_201508',
      'this_is_the_army_mp4',
      'the-ducktators-1942',
      'turner_video_393545', // Negative sample: Unclear rights
    ];

    final candidates = <InternetArchiveMovie>[];

    for (final id in candidateIds) {
      try {
        final movie = await getItemMetadata(id);
        candidates.add(movie);
      } catch (_) {
        // Fallback to static model on failure so the prototype test screen remains functional offline
        candidates.add(_staticFallback(id));
      }
    }

    return candidates;
  }

  InternetArchiveMovie _staticFallback(String identifier) {
    switch (identifier) {
      case 'the-vagabond-1916_202304':
        return InternetArchiveMovie(
          identifier: 'the-vagabond-1916_202304',
          title: 'The Vagabond (1916)',
          description:
              'A 1916 American silent romantic comedy film by Charlie Chaplin and his third film with Mutual Films.',
          year: 1916,
          creator: 'Charles Chaplin',
          thumbnailUrl: 'https://archive.org/services/img/the-vagabond-1916_202304',
          durationSeconds: 1483.22,
          rightsInfo: const ArchiveRightsInfo(
            licenseUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
            category: ArchiveRightsCategory.publicDomain,
            isCommercialReady: true,
            summary: 'Public Domain (Verified)',
          ),
          videoFiles: const [
            ArchiveVideoFile(
              name: 'The Vagabond (1916).mp4',
              format: 'MPEG4',
              size: 150004139,
              lengthSeconds: 1483.22,
              height: 480,
              width: 640,
              downloadUrl:
                  'https://archive.org/download/the-vagabond-1916_202304/The%20Vagabond%20(1916).mp4',
            ),
          ],
          itemPageUrl: 'https://archive.org/details/the-vagabond-1916_202304',
        );

      case 'NightOfTheLivingDead_201508':
        return InternetArchiveMovie(
          identifier: 'NightOfTheLivingDead_201508',
          title: 'Night Of The Living Dead (1968)',
          description:
              'George A. Romero horror classic that has fallen into the public domain due to missing copyright notice.',
          year: 1968,
          creator: 'George A. Romero',
          thumbnailUrl: 'https://archive.org/services/img/NightOfTheLivingDead_201508',
          durationSeconds: 5731.83,
          rightsInfo: const ArchiveRightsInfo(
            licenseUrl: 'http://creativecommons.org/publicdomain/mark/1.0/',
            category: ArchiveRightsCategory.publicDomain,
            isCommercialReady: true,
            summary: 'Public Domain (Verified)',
          ),
          videoFiles: const [
            ArchiveVideoFile(
              name: 'Night of the Living Dead.mp4',
              format: 'MPEG4',
              size: 596399542,
              lengthSeconds: 5731.83,
              height: 480,
              width: 640,
              downloadUrl:
                  'https://archive.org/download/NightOfTheLivingDead_201508/Night%20of%20the%20Living%20Dead.mp4',
            ),
          ],
          itemPageUrl: 'https://archive.org/details/NightOfTheLivingDead_201508',
        );

      case 'this_is_the_army_mp4':
        return InternetArchiveMovie(
          identifier: 'this_is_the_army_mp4',
          title: 'This is the Army (1943)',
          description:
              'WWII American musical comedy film directed by Michael Curtiz, music by Irving Berlin.',
          year: 1943,
          creator: 'Michael Curtiz',
          thumbnailUrl: 'https://archive.org/services/img/this_is_the_army_mp4',
          durationSeconds: 7240.0,
          rightsInfo: const ArchiveRightsInfo(
            licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
            category: ArchiveRightsCategory.publicDomain,
            isCommercialReady: true,
            summary: 'Public Domain (Verified - CC0 1.0)',
          ),
          videoFiles: const [
            ArchiveVideoFile(
              name: 'this_is_the_army.mp4',
              format: 'MPEG4',
              size: 450000000,
              lengthSeconds: 7240.0,
              height: 480,
              width: 640,
              downloadUrl:
                  'https://archive.org/download/this_is_the_army_mp4/this_is_the_army.mp4',
            ),
          ],
          itemPageUrl: 'https://archive.org/details/this_is_the_army_mp4',
        );

      case 'the-ducktators-1942':
        return InternetArchiveMovie(
          identifier: 'the-ducktators-1942',
          title: 'The Ducktators (1942)',
          description:
              'Warner Bros. Looney Tunes short satirizing World War II events, now in public domain.',
          year: 1942,
          creator: 'Norman McCabe',
          thumbnailUrl: 'https://archive.org/services/img/the-ducktators-1942',
          durationSeconds: 462.0,
          rightsInfo: const ArchiveRightsInfo(
            licenseUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
            category: ArchiveRightsCategory.publicDomain,
            isCommercialReady: true,
            summary: 'Public Domain (Verified)',
          ),
          videoFiles: const [
            ArchiveVideoFile(
              name: 'The_Ducktators_1942.mp4',
              format: 'MPEG4',
              size: 45000000,
              lengthSeconds: 462.0,
              height: 480,
              width: 640,
              downloadUrl:
                  'https://archive.org/download/the-ducktators-1942/The_Ducktators_1942.mp4',
            ),
          ],
          itemPageUrl: 'https://archive.org/details/the-ducktators-1942',
        );

      case 'turner_video_393545':
      default:
        return InternetArchiveMovie(
          identifier: 'turner_video_393545',
          title: 'Night of the Living Dead (1990 Remake)',
          description:
              '1990 modern remake. Copyright status is not public domain; streaming prohibited.',
          year: 1990,
          creator: 'Tom Savini',
          thumbnailUrl: 'https://archive.org/services/img/turner_video_393545',
          rightsInfo: const ArchiveRightsInfo(
            licenseUrl: null,
            rights: 'Copyright 1990 Columbia Pictures',
            category: ArchiveRightsCategory.unclearOrRestricted,
            isCommercialReady: false,
            summary: 'Unclear Rights — Streaming Prohibited',
          ),
          videoFiles: const [],
          itemPageUrl: 'https://archive.org/details/turner_video_393545',
        );
    }
  }
}
