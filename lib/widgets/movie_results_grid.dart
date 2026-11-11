import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../models/movie_availability.dart';
import '../screens/movie_details_screen.dart';

class MovieResultsGrid extends StatelessWidget {
  const MovieResultsGrid({
    super.key,
    required this.movies,
    this.showMovieMetadata = false,
    this.controller,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
    this.availabilityMap,
  });

  final List<Movie> movies;
  final bool showMovieMetadata;
  final ScrollController? controller;
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final Map<String, MovieAvailability>? availabilityMap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: movies.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 8,
        childAspectRatio: 0.683,
      ),
      itemBuilder: (context, index) => _movieItem(context, movies[index]),
    );
  }

  Widget _movieItem(BuildContext context, Movie movie) => GestureDetector(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieDetailsScreen(movie: movie),
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _poster(movie),
          if (showMovieMetadata)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.58, 1],
                  colors: [Colors.transparent, Color(0xD9000000)],
                ),
              ),
            ),
          if (showMovieMetadata)
            Positioned(
              left: 9,
              right: 9,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  if (movie.year != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      movie.year.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!movie.ratingIsInImage && movie.rating != null)
            Positioned(
              top: 12,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC151616),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC400),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          if (availabilityMap != null && availabilityMap!.containsKey(movie.id))
            _buildAvailabilityBadge(availabilityMap![movie.id]!),
        ],
      ),
    ),
  );

  Widget _buildAvailabilityBadge(MovieAvailability availability) {
    if (availability.canWatch) {
      return Positioned(
        top: 12,
        right: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xE62E7D32),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
              SizedBox(width: 2),
              Text(
                'Watch',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (availability.state == MovieAvailabilityState.rightsNotVerified) {
      return Positioned(
        top: 12,
        right: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xCC3E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: const Text(
            'Restricted',
            style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Positioned(
      top: 12,
      right: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xCC252626),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Metadata',
          style: TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
    );
  }

  Widget _poster(Movie movie) {
    final asset = movie.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: _imageFallback,
      );
    }

    final url =
        movie.posterUrl ?? movie.largeCoverImageUrl ?? movie.backgroundImageUrl;
    if (url == null || url.isEmpty) return _imageFallbackPlaceholder();

    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null ? child : _imageLoadingPlaceholder(),
      errorBuilder: _imageFallback,
    );
  }

  Widget _imageLoadingPlaceholder() => const ColoredBox(
    color: Color(0xFF292929),
    child: Center(
      child: CircularProgressIndicator(
        color: Color(0xFFFFC400),
        strokeWidth: 2,
      ),
    ),
  );

  Widget _imageFallbackPlaceholder() => const ColoredBox(
    color: Color(0xFF292929),
    child: Center(
      child: Icon(Icons.movie_outlined, color: Colors.white54, size: 40),
    ),
  );

  Widget _imageFallback(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => _imageFallbackPlaceholder();
}
