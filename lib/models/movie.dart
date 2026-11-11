class Movie {
  const Movie({
    required this.id,
    required this.title,
    this.year,
    this.rating,
    this.posterUrl,
    this.largeCoverImageUrl,
    this.backgroundImageUrl,
    this.trailerCode,
    this.imageAsset,
    this.genres = const [],
    this.description,
    this.runtime,
    this.language,
    this.cast = const [],
    this.availableQualities = const [],
    this.screenshots = const [],
    this.ratingIsInImage = false,
  });

  final String id;
  final String title;
  final int? year;
  final double? rating;
  final String? posterUrl;
  final String? largeCoverImageUrl;
  final String? backgroundImageUrl;
  final String? trailerCode;
  final String? imageAsset;
  final List<String> genres;
  final String? description;
  final int? runtime;
  final String? language;
  final List<String> cast;
  final List<String> availableQualities;
  final List<String> screenshots;
  final bool ratingIsInImage;

  factory Movie.fromJson(Map<String, dynamic> json, {String? documentId}) {
    int? asInt(dynamic value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    double? asDouble(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value');
    List<String> strings(dynamic value) => value is List
        ? value.map((item) => item.toString()).toList()
        : const [];

    List<String> parseCast(dynamic value) {
      if (value is! List) return const [];
      final result = <String>[];
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) {
          result.add(item.trim());
        } else if (item is Map) {
          final name = item['name']?.toString().trim();
          final character = item['character_name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
            if (character != null && character.isNotEmpty) {
              result.add('$name as $character');
            } else {
              result.add(name);
            }
          }
        }
      }
      return List<String>.unmodifiable(result);
    }

    List<String> parseQualities(dynamic rawTorrents, dynamic rawQualities) {
      if (rawQualities is List) {
        return rawQualities
            .map((q) => q.toString().trim())
            .where((q) => q.isNotEmpty)
            .toList();
      }
      if (rawTorrents is List) {
        final list = <String>[];
        for (final t in rawTorrents) {
          if (t is Map && t['quality'] != null) {
            final q = t['quality'].toString().trim();
            if (q.isNotEmpty && !list.contains(q)) {
              list.add(q);
            }
          }
        }
        return List<String>.unmodifiable(list);
      }
      return const [];
    }

    List<String> parseScreenshots(Map<String, dynamic> source) {
      if (source['screenshots'] is List) {
        return (source['screenshots'] as List)
            .map((s) => s.toString().trim())
            .where((s) => s.startsWith('http'))
            .toList();
      }
      final shots = <String>[];
      for (final prefix in ['large_screenshot_image', 'medium_screenshot_image']) {
        for (var i = 1; i <= 3; i++) {
          final url = source['$prefix$i']?.toString().trim();
          if (url != null && url.startsWith('http') && !shots.contains(url)) {
            shots.add(url);
          }
        }
        if (shots.isNotEmpty) break;
      }
      return List<String>.unmodifiable(shots);
    }

    final poster =
        json['medium_cover_image'] ?? json['posterUrl'] ?? json['poster'];
    return Movie(
      id:
          (json['id'] ??
                  documentId ??
                  json['imdb_code'] ??
                  json['url'] ??
                  json['title'] ??
                  'unknown')
              .toString(),
      title: (json['title'] ?? 'Unknown Movie').toString(),
      year: asInt(json['year']),
      rating: asDouble(json['rating'] ?? json['rating_average']),
      posterUrl: poster is String && poster.startsWith('http') ? poster : null,
      largeCoverImageUrl:
          (json['large_cover_image'] ?? json['largeCoverImageUrl'])?.toString(),
      backgroundImageUrl:
          (json['background_image_original'] ??
                  json['background_image'] ??
                  json['backgroundImageUrl'])
              ?.toString(),
      trailerCode: (json['yt_trailer_code'] ?? json['trailerCode'])?.toString(),
      imageAsset:
          json['imageAsset']?.toString() ??
          (poster is String && !poster.startsWith('http') ? poster : null),
      genres: strings(json['genres']),
      description:
          (json['description_full'] ??
                  json['description_intro'] ??
                  json['summary'] ??
                  json['description'])
              ?.toString(),
      runtime: asInt(json['runtime'] ?? json['runtimeInMinutes']),
      language: json['language']?.toString(),
      cast: parseCast(json['cast']),
      availableQualities: parseQualities(json['torrents'], json['availableQualities']),
      screenshots: parseScreenshots(json),
      ratingIsInImage: json['ratingIsInImage'] == true,
    );
  }

  factory Movie.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) => Movie.fromJson(data, documentId: documentId);

  Movie copyWith({
    String? id,
    String? title,
    int? year,
    double? rating,
    String? posterUrl,
    String? largeCoverImageUrl,
    String? backgroundImageUrl,
    String? trailerCode,
    String? imageAsset,
    List<String>? genres,
    String? description,
    int? runtime,
    String? language,
    List<String>? cast,
    List<String>? availableQualities,
    List<String>? screenshots,
    bool? ratingIsInImage,
  }) {
    return Movie(
      id: id ?? this.id,
      title: title ?? this.title,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      posterUrl: posterUrl ?? this.posterUrl,
      largeCoverImageUrl: largeCoverImageUrl ?? this.largeCoverImageUrl,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      trailerCode: trailerCode ?? this.trailerCode,
      imageAsset: imageAsset ?? this.imageAsset,
      genres: genres ?? this.genres,
      description: description ?? this.description,
      runtime: runtime ?? this.runtime,
      language: language ?? this.language,
      cast: cast ?? this.cast,
      availableQualities: availableQualities ?? this.availableQualities,
      screenshots: screenshots ?? this.screenshots,
      ratingIsInImage: ratingIsInImage ?? this.ratingIsInImage,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (year != null) 'year': year,
    if (rating != null) 'rating': rating,
    if (posterUrl != null) 'posterUrl': posterUrl,
    if (largeCoverImageUrl != null) 'largeCoverImageUrl': largeCoverImageUrl,
    if (backgroundImageUrl != null) 'backgroundImageUrl': backgroundImageUrl,
    if (trailerCode != null) 'trailerCode': trailerCode,
    if (imageAsset != null) 'imageAsset': imageAsset,
    'genres': genres,
    if (description != null) 'description': description,
    if (runtime != null) 'runtime': runtime,
    if (language != null) 'language': language,
    'cast': cast,
    'availableQualities': availableQualities,
    'screenshots': screenshots,
  };

  Map<String, dynamic> toFirestoreMovie() => {
    'id': id,
    'title': title,
    'year': (year ?? 0).toString(),
    'poster': imageAsset ?? posterUrl ?? 'assets/avengers_onboarding.jpg',
  };
}
