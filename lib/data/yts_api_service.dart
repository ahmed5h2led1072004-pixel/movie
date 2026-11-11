import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/movie.dart';

/// HTTP client for the YTS v2 API. UI code should use [MovieRepository].
class YtsApiService {
  YtsApiService({http.Client? client, this.baseUrl = defaultBaseUrl})
    : _client = client ?? http.Client();

  static const String defaultBaseUrl = 'https://movies-api.accel.li/api/v2/';
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _client;
  final String baseUrl;

  /// Fetches a single page from `list_movies.json` with optional YTS
  /// search/filter parameters. The response also carries pagination metadata
  /// (`movie_count`, `page_number`, `limit`) needed to walk further pages.
  Future<YtsMoviePage> fetchMoviePage({
    int limit = 20,
    int page = 1,
    String? queryTerm,
    String? genre,
    String? sortBy,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'Must be positive');
    }

    final queryParameters = <String, String>{
      'limit': '$limit',
      'page': '$page',
      if (queryTerm != null && queryTerm.trim().isNotEmpty)
        'query_term': queryTerm.trim(),
      if (genre != null && genre.trim().isNotEmpty) 'genre': genre.trim(),
      if (sortBy != null && sortBy.trim().isNotEmpty) 'sort_by': sortBy.trim(),
    };
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse('${normalizedBaseUrl}list_movies.json')
        .replace(queryParameters: queryParameters);
    _debugYtsLog('GET $uri');

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _debugYtsLog('Request timed out: $error\n$stackTrace');
      throw YtsApiException('The YTS request timed out.', cause: error);
    } on http.ClientException catch (error, stackTrace) {
      _debugYtsLog('HTTP client failure: $error\n$stackTrace');
      throw YtsApiException(
        'Could not connect to the YTS service.',
        cause: error,
      );
    } catch (error, stackTrace) {
      _debugYtsLog('Unexpected request failure: $error\n$stackTrace');
      rethrow;
    }

    _debugYtsLog('HTTP status ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YtsApiException(
        'The YTS service returned HTTP ${response.statusCode}.',
      );
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error, stackTrace) {
      _debugYtsLog('Invalid JSON response: $error\n$stackTrace');
      throw YtsApiException(
        'The YTS service returned invalid JSON.',
        cause: error,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      _debugYtsLog('Response JSON root was not an object.');
      throw YtsApiException('The YTS response has an invalid format.');
    }
    _debugYtsLog('API status ${decoded['status']}');
    if (decoded['status'] != 'ok') {
      final message = decoded['status_message']?.toString();
      _debugYtsLog('API error message: ${message ?? '(none)'}');
      throw YtsApiException(
        message == null || message.isEmpty
            ? 'The YTS API reported an unsuccessful response.'
            : 'The YTS API request failed: $message',
      );
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      _debugYtsLog('Response did not contain a valid data object.');
      throw YtsApiException('The YTS response is missing its data object.');
    }
    // YTS omits the `movies` key entirely when a query has no results.
    final rawMovies = data['movies'];
    if (rawMovies == null) {
      return YtsMoviePage(
        movies: const [],
        page: page,
        limit: limit,
        totalCount: 0,
      );
    }
    if (rawMovies is! List) {
      throw YtsApiException('The YTS movies field is not a list.');
    }

    final movies = rawMovies
        .whereType<Map<String, dynamic>>()
        .where((movie) => movie['id'] != null && movie['title'] is String)
        .map(Movie.fromJson)
        .toList(growable: false);

    return YtsMoviePage(
      movies: movies,
      page: _asPositiveInt(data['page_number']) ?? page,
      limit: _asPositiveInt(data['limit']) ?? limit,
      totalCount: _asPositiveInt(data['movie_count']) ?? movies.length,
    );
  }

  /// Fetches movies from `list_movies.json` with optional YTS search/filter
  /// parameters. Empty successful responses are returned as an empty list.
  Future<List<Movie>> fetchMovies({
    int limit = 20,
    int page = 1,
    String? queryTerm,
    String? genre,
    String? sortBy,
  }) async {
    final result = await fetchMoviePage(
      limit: limit,
      page: page,
      queryTerm: queryTerm,
      genre: genre,
      sortBy: sortBy,
    );
    return result.movies;
  }

  /// Fetches detailed movie information from `movie_details.json`.
  Future<Movie> fetchMovieDetails(
    String movieId, {
    bool withImages = true,
    bool withCast = true,
  }) async {
    final trimmedId = movieId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError.value(movieId, 'movieId', 'Must not be empty');
    }

    final queryParameters = <String, String>{
      'movie_id': trimmedId,
      if (withImages) 'with_images': 'true',
      if (withCast) 'with_cast': 'true',
    };
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse('${normalizedBaseUrl}movie_details.json')
        .replace(queryParameters: queryParameters);
    _debugYtsLog('GET $uri');

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _debugYtsLog('Request timed out: $error\n$stackTrace');
      throw YtsApiException('The YTS request timed out.', cause: error);
    } on http.ClientException catch (error, stackTrace) {
      _debugYtsLog('HTTP client failure: $error\n$stackTrace');
      throw YtsApiException(
        'Could not connect to the YTS service.',
        cause: error,
      );
    } catch (error, stackTrace) {
      _debugYtsLog('Unexpected request failure: $error\n$stackTrace');
      rethrow;
    }

    _debugYtsLog('HTTP status ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YtsApiException(
        'The YTS service returned HTTP ${response.statusCode}.',
      );
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error, stackTrace) {
      _debugYtsLog('Invalid JSON response: $error\n$stackTrace');
      throw YtsApiException(
        'The YTS service returned invalid JSON.',
        cause: error,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      _debugYtsLog('Response JSON root was not an object.');
      throw YtsApiException('The YTS response has an invalid format.');
    }
    _debugYtsLog('API status ${decoded['status']}');
    if (decoded['status'] != 'ok') {
      final message = decoded['status_message']?.toString();
      _debugYtsLog('API error message: ${message ?? '(none)'}');
      throw YtsApiException(
        message == null || message.isEmpty
            ? 'The YTS API reported an unsuccessful response.'
            : 'The YTS API request failed: $message',
      );
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      _debugYtsLog('Response did not contain a valid data object.');
      throw YtsApiException('The YTS response is missing its data object.');
    }
    final movieData = data['movie'];
    if (movieData is! Map<String, dynamic>) {
      _debugYtsLog('Response data did not contain a valid movie object.');
      throw YtsApiException('The YTS response is missing movie details.');
    }

    return Movie.fromJson(movieData);
  }

  /// Fetches movie suggestions from `movie_suggestions.json`.
  Future<List<Movie>> fetchMovieSuggestions(String movieId) async {
    final trimmedId = movieId.trim();
    if (trimmedId.isEmpty) return const [];

    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.parse('${normalizedBaseUrl}movie_suggestions.json')
        .replace(queryParameters: {'movie_id': trimmedId});
    _debugYtsLog('GET $uri');

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _debugYtsLog('fetchMovieSuggestions timed out: $error\n$stackTrace');
      throw YtsApiException('The YTS request timed out.', cause: error);
    } on http.ClientException catch (error, stackTrace) {
      _debugYtsLog('fetchMovieSuggestions client failure: $error\n$stackTrace');
      throw YtsApiException(
        'Could not connect to the YTS service.',
        cause: error,
      );
    } catch (error, stackTrace) {
      _debugYtsLog('fetchMovieSuggestions failed: $error\n$stackTrace');
      rethrow;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != 'ok') {
        return const [];
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return const [];
      final rawMovies = data['movies'];
      if (rawMovies == null || rawMovies is! List) return const [];

      return rawMovies
          .whereType<Map<String, dynamic>>()
          .where((movie) => movie['id'] != null && movie['title'] is String)
          .map(Movie.fromJson)
          .toList(growable: false);
    } catch (error) {
      _debugYtsLog('Failed to parse movie suggestions: $error');
      return const [];
    }
  }

  void close() => _client.close();
}

int? _asPositiveInt(dynamic value) {
  final parsed = value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

void _debugYtsLog(String message) {
  if (kDebugMode) debugPrint('[YTS] $message');
}

/// One page of YTS `list_movies.json` results.
class YtsMoviePage {
  const YtsMoviePage({
    required this.movies,
    required this.page,
    required this.limit,
    required this.totalCount,
  });

  final List<Movie> movies;
  final int page;
  final int limit;
  final int totalCount;

  bool get hasMore => page * limit < totalCount;
}

class YtsApiException implements Exception {
  const YtsApiException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'YtsApiException: $message';
}
