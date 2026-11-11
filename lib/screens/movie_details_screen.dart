import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/movie_matching_service.dart';
import '../data/movie_repository.dart';
import '../data/yts_api_service.dart';
import '../models/movie.dart';
import '../models/movie_availability.dart';
import '../widgets/archive_video_player.dart';

class MovieDetailsScreen extends StatefulWidget {
  const MovieDetailsScreen({
    super.key,
    required this.movie,
    this.repository,
    this.onWatchTrailer,
    this.auth,
    this.firestore,
    this.initialIsSaved,
    this.initialIsFavorite,
    this.onToggleWatchlist,
    this.onToggleFavorite,
    this.onRecordWatched,
    this.matchingService,
  });

  final Movie movie;
  final MovieRepository? repository;
  final Future<void> Function(BuildContext context, String trailerCode)?
      onWatchTrailer;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final bool? initialIsSaved;
  final bool? initialIsFavorite;
  final Future<void> Function()? onToggleWatchlist;
  final Future<void> Function()? onToggleFavorite;
  final Future<void> Function()? onRecordWatched;
  final MovieMatchingService? matchingService;

  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  static final MovieRepository _defaultRepository = MovieRepository(
    apiService: YtsApiService(),
  );
  static final MovieMatchingService _defaultMatchingService =
      MovieMatchingService();

  late final MovieRepository _repository =
      widget.repository ?? _defaultRepository;
  late final MovieMatchingService _matchingService =
      widget.matchingService ?? _defaultMatchingService;

  late Movie _movie = widget.movie;
  bool _isLoadingDetails = false;
  bool _detailsFailed = false;
  String? _detailsErrorMessage;

  MovieAvailability? _availability;
  bool _isCheckingAvailability = true;
  bool _isPlayingVideo = false;

  late bool _isSaved = widget.initialIsSaved ?? false;
  bool _isSaving = false;
  late bool _isChecking = widget.initialIsSaved == null;
  bool _watchlistCheckFailed = false;

  late bool _isFavorite = widget.initialIsFavorite ?? false;
  bool _isTogglingFavorite = false;
  late bool _isCheckingFavorite = widget.initialIsFavorite == null;
  bool _favoriteCheckFailed = false;

  bool _isSubmittingReview = false;
  bool _isLoadingMyReview = true;
  bool _reviewLoadFailed = false;
  bool _hasReview = false;

  bool _isRecordingWatched = false;

  List<Movie> _similarMovies = const [];
  bool _isLoadingSimilar = true;
  bool _similarFailed = false;
  bool _isNavigatingToSimilar = false;

  int _selectedRating = 5;

  final TextEditingController _reviewController = TextEditingController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reviewsStream;

  String get _movieId => _movie.id;
  Map<String, dynamic> get _movieData => _movie.toFirestoreMovie();

  final Color _yellow = const Color(0xFFFFC400);

  FirebaseAuth? get _auth {
    if (widget.auth != null) return widget.auth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    if (widget.firestore != null) return widget.firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  User? get _currentUser => _auth?.currentUser;

  CollectionReference<Map<String, dynamic>>? get _reviewsReference {
    try {
      final firestore = _firestore;
      if (firestore == null) return null;

      return firestore
          .collection('movies')
          .doc(_movieId)
          .collection('reviews');
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    final reviewsRef = _reviewsReference;
    if (reviewsRef != null) {
      _reviewsStream = reviewsRef.snapshots();
    }
    if (widget.initialIsSaved == null) {
      _checkIfSaved();
    }
    if (widget.initialIsFavorite == null) {
      _checkIfFavorite();
    }
    _loadMyReview();
    _loadMovieDetails();
    _checkMovieAvailability();
    _recordRecentlyViewed();
    _loadSimilarMovies();
  }

  Future<void> _checkMovieAvailability() async {
    setState(() {
      _isCheckingAvailability = true;
    });

    try {
      final avail = await _matchingService.checkAvailability(_movie);
      if (!mounted) return;
      setState(() {
        _availability = avail;
        _isCheckingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availability = MovieAvailability.metadataOnly();
        _isCheckingAvailability = false;
      });
    }
  }

  Future<void> _watchNow() async {
    await _recordMovieAsWatched();
    if (!mounted) return;
    setState(() {
      _isPlayingVideo = true;
    });
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>>? _getMovieReference() {
    try {
      final user = _currentUser;
      final firestore = _firestore;
      if (user == null || firestore == null) return null;

      return firestore
          .collection('users')
          .doc(user.uid)
          .collection('watchlist')
          .doc(_movieId);
    } catch (_) {
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>>? _getFavoriteReference() {
    try {
      final user = _currentUser;
      final firestore = _firestore;
      if (user == null || firestore == null) return null;

      return firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .doc(_movieId);
    } catch (_) {
      return null;
    }
  }

  // Record movie in Recently Watched when screen is opened
  Future<void> _recordRecentlyViewed() async {
    final user = _currentUser;
    final firestore = _firestore;
    if (user == null || firestore == null) return;

    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('recently_watched')
          .doc(_movieId)
          .set({
            ..._movieData,
            'watchedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Background recording error is ignored
    }
  }

  // Check if movie is saved in Watch List.
  Future<void> _checkIfSaved() async {
    try {
      final reference = _getMovieReference();

      if (reference == null) {
        if (!mounted) return;

        setState(() {
          _isChecking = false;
        });
        return;
      }

      final document = await reference.get();

      if (!mounted) return;

      setState(() {
        _isSaved = document.exists;
        _isChecking = false;
        _watchlistCheckFailed = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isChecking = false;
        _watchlistCheckFailed = true;
      });
    }
  }

  // Check if movie is in Favorite Movies.
  Future<void> _checkIfFavorite() async {
    try {
      final reference = _getFavoriteReference();

      if (reference == null) {
        if (!mounted) return;

        setState(() {
          _isCheckingFavorite = false;
        });
        return;
      }

      final document = await reference.get();

      if (!mounted) return;

      setState(() {
        _isFavorite = document.exists;
        _isCheckingFavorite = false;
        _favoriteCheckFailed = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isCheckingFavorite = false;
        _favoriteCheckFailed = true;
      });
    }
  }

  void _retryWatchlistCheck() {
    setState(() {
      _isChecking = true;
      _watchlistCheckFailed = false;
    });
    _checkIfSaved();
  }

  void _retryFavoriteCheck() {
    setState(() {
      _isCheckingFavorite = true;
      _favoriteCheckFailed = false;
    });
    _checkIfFavorite();
  }

  // Load the current user's review.
  Future<void> _loadMyReview() async {
    try {
      User? user;
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        user = null;
      }

      if (user == null) {
        if (!mounted) return;

        setState(() {
          _isLoadingMyReview = false;
        });
        return;
      }

      final ref = _reviewsReference;
      if (ref == null) {
        if (!mounted) return;

        setState(() {
          _isLoadingMyReview = false;
        });
        return;
      }

      final document = await ref.doc(user.uid).get();

      if (!mounted) return;

      if (document.exists) {
        final data = document.data()!;

        setState(() {
          _hasReview = true;
          _selectedRating = ((data['rating'] as num?)?.toInt() ?? 5)
              .clamp(1, 5)
              .toInt();
          _reviewController.text = data['comment']?.toString() ?? '';
          _isLoadingMyReview = false;
          _reviewLoadFailed = false;
        });
      } else {
        setState(() {
          _hasReview = false;
          _isLoadingMyReview = false;
          _reviewLoadFailed = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingMyReview = false;
        _reviewLoadFailed = true;
      });
    }
  }

  void _retryMyReviewLoad() {
    setState(() {
      _isLoadingMyReview = true;
      _reviewLoadFailed = false;
    });
    _loadMyReview();
  }

  Future<void> _loadMovieDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _detailsFailed = false;
      _detailsErrorMessage = null;
    });

    final result = await _repository.fetchMovieDetails(
      widget.movie.id,
      fallbackMovie: _movie,
    );

    if (!mounted) return;

    setState(() {
      _movie = result.movie;
      _isLoadingDetails = false;
      _detailsFailed = result.usedFallback && result.error != null;
      if (_detailsFailed) {
        _detailsErrorMessage = 'Could not load full movie details.';
      }
    });

    if (_movie.genres.isNotEmpty && _similarMovies.isEmpty) {
      _loadSimilarMovies();
    }
  }

  Future<void> _loadSimilarMovies() async {
    setState(() {
      _isLoadingSimilar = true;
      _similarFailed = false;
    });

    try {
      final results = await _repository.fetchSimilarMovies(_movie, limit: 4);
      if (!mounted) return;
      setState(() {
        _similarMovies = results;
        _isLoadingSimilar = false;
        _similarFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSimilar = false;
        _similarFailed = true;
      });
    }
  }

  void _openSimilarMovie(Movie movie) {
    if (_isNavigatingToSimilar) return;
    _isNavigatingToSimilar = true;

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MovieDetailsScreen(
              movie: movie,
              repository: _repository,
              matchingService: _matchingService,
              auth: widget.auth,
              firestore: widget.firestore,
              onWatchTrailer: widget.onWatchTrailer,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() {
              _isNavigatingToSimilar = false;
            });
          }
        });
  }

  bool get _hasTrailer {
    final code = _movie.trailerCode?.trim();
    return code != null && code.isNotEmpty;
  }

  Future<void> _openTrailer() async {
    final code = _movie.trailerCode?.trim();
    if (code == null || code.isEmpty) {
      _showMessage('Trailer is not available for this movie.');
      return;
    }

    if (widget.onWatchTrailer != null) {
      await widget.onWatchTrailer!(context, code);
      return;
    }

    final youtubeUri = Uri.parse('https://www.youtube.com/watch?v=$code');
    try {
      final launched = await launchUrl(
        youtubeUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        final fallback = await launchUrl(
          youtubeUri,
          mode: LaunchMode.platformDefault,
        );
        if (!fallback && mounted) {
          _showTrailerDialog(code, youtubeUri);
        }
      }
    } catch (_) {
      if (mounted) {
        _showTrailerDialog(code, youtubeUri);
      }
    }
  }

  void _showTrailerDialog(String trailerCode, Uri youtubeUri) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF252626),
        title: const Text(
          'Watch Trailer',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'YouTube trailer code: $trailerCode\n$youtubeUri',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFFFC400)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    final bg = _movie.backgroundImageUrl;
    if (bg != null && bg.startsWith('http')) {
      return Image.network(
        bg,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.1),
        errorBuilder: _fallbackLargeCover,
      );
    }
    return _fallbackLargeCover(context, Object(), StackTrace.empty);
  }

  Widget _fallbackLargeCover(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) {
    final large = _movie.largeCoverImageUrl;
    if (large != null && large.startsWith('http')) {
      return Image.network(
        large,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.1),
        errorBuilder: _fallbackPoster,
      );
    }
    return _fallbackPoster(context, error, stack);
  }

  Widget _fallbackPoster(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) {
    final poster = _movie.posterUrl;
    if (poster != null && poster.startsWith('http')) {
      return Image.network(
        poster,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.1),
        errorBuilder: _fallbackAsset,
      );
    }
    return _fallbackAsset(context, error, stack);
  }

  Widget _fallbackAsset(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) {
    final asset = _movie.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.1),
        errorBuilder: _heroImageError,
      );
    }
    return _heroImageError(context, error, stack);
  }

  Widget _heroImageError(BuildContext context, Object error, StackTrace? stack) =>
      const ColoredBox(color: Color(0xFF252626), child: Center(child: Icon(Icons.movie_outlined, color: Colors.white54, size: 64)));

  // Add movie to Recently Watched.
  Future<void> _recordMovieAsWatched() async {
    if (_isRecordingWatched) return;

    if (widget.onRecordWatched != null) {
      await widget.onRecordWatched!();
      return;
    }

    final user = _currentUser;
    final firestore = _firestore;

    if (user == null) {
      _showMessage('Please login first');
      return;
    }

    if (firestore == null) return;

    setState(() {
      _isRecordingWatched = true;
    });

    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('recently_watched')
          .doc(_movieId)
          .set({
            ..._movieData,
            'watchedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;

      _showMessage('Movie marked as watched');
    } on FirebaseException catch (e) {
      if (!mounted) return;

      _showMessage('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Could not save movie to History');
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingWatched = false;
        });
      }
    }
  }

  // Add or remove movie from Watch List.
  Future<void> _toggleWatchlist() async {
    if (_isSaving) return;

    if (widget.onToggleWatchlist != null) {
      final previousSaved = _isSaved;
      setState(() {
        _isSaving = true;
        _isSaved = !previousSaved;
      });
      try {
        await widget.onToggleWatchlist!();
        if (!mounted) return;
        _showMessage(
          previousSaved
              ? 'Movie removed from Watch List'
              : 'Movie added to Watch List',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSaved = previousSaved;
        });
        _showMessage('Could not update Watch List');
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
      return;
    }

    final user = _currentUser;

    if (user == null) {
      _showMessage('Please login first');
      return;
    }

    final reference = _getMovieReference();

    if (reference == null) return;

    final previousSaved = _isSaved;
    setState(() {
      _isSaving = true;
      _isSaved = !previousSaved;
    });

    try {
      if (previousSaved) {
        await reference.delete();

        if (!mounted) return;

        _showMessage('Movie removed from Watch List');
      } else {
        await reference.set({
          ..._movieData,
          'addedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;

        _showMessage('Movie added to Watch List');
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaved = previousSaved;
      });

      _showMessage('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaved = previousSaved;
      });

      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // Add or remove movie from Favorite Movies.
  Future<void> _toggleFavorite() async {
    if (_isTogglingFavorite || _isCheckingFavorite) return;

    if (widget.onToggleFavorite != null) {
      final previousFavorite = _isFavorite;
      setState(() {
        _isTogglingFavorite = true;
        _isFavorite = !previousFavorite;
      });
      try {
        await widget.onToggleFavorite!();
        if (!mounted) return;
        _showMessage(
          previousFavorite
              ? 'Movie removed from Favorites'
              : 'Movie added to Favorites',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isFavorite = previousFavorite;
        });
        _showMessage('Could not update Favorites');
      } finally {
        if (mounted) {
          setState(() {
            _isTogglingFavorite = false;
          });
        }
      }
      return;
    }

    final user = _currentUser;

    if (user == null) {
      _showMessage('Please login first');
      return;
    }

    final reference = _getFavoriteReference();

    if (reference == null) return;

    final previousFavorite = _isFavorite;
    setState(() {
      _isTogglingFavorite = true;
      _isFavorite = !previousFavorite;
    });

    try {
      if (previousFavorite) {
        await reference.delete();

        if (!mounted) return;

        _showMessage('Movie removed from Favorites');
      } else {
        await reference.set({
          ..._movieData,
          'addedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;

        _showMessage('Movie added to Favorites');
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        _isFavorite = previousFavorite;
      });

      _showMessage('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFavorite = previousFavorite;
      });

      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFavorite = false;
        });
      }
    }
  }

  // Submit or update a review.
  Future<void> _submitReview() async {
    if (_isLoadingMyReview || _reviewLoadFailed) return;

    final user = _currentUser;

    if (user == null) {
      _showMessage('Please login first');
      return;
    }

    final comment = _reviewController.text.trim();

    if (comment.isEmpty) {
      _showMessage('Please write your review first');
      return;
    }

    if (comment.length > 1000) {
      _showMessage('Review must not exceed 1000 characters');
      return;
    }

    final ref = _reviewsReference;
    if (ref == null) {
      _showMessage('Review service is currently unavailable');
      return;
    }

    if (_isSubmittingReview) return;

    setState(() {
      _isSubmittingReview = true;
    });

    try {
      final reference = ref.doc(user.uid);
      var userName = user.displayName ?? user.email?.split('@').first ?? 'User';
      try {
        final firestore = _firestore;
        if (firestore != null) {
          final profile = await firestore
              .collection('users')
              .doc(user.uid)
              .get();
          final profileName = profile.data()?['name']?.toString().trim();
          if (profileName != null && profileName.isNotEmpty) {
            userName = profileName;
          }
        }
      } catch (_) {
        // Keep the Auth name fallback if the profile read is unavailable.
      }

      final reviewData = <String, dynamic>{
        'userId': user.uid,
        'userName': userName,
        'rating': _selectedRating,
        'comment': comment,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!_hasReview) {
        reviewData['createdAt'] = FieldValue.serverTimestamp();
      }

      await reference.set(reviewData, SetOptions(merge: true));

      if (!mounted) return;

      final wasExistingReview = _hasReview;

      setState(() {
        _hasReview = true;
        _reviewLoadFailed = false;
      });

      _showMessage(
        wasExistingReview
            ? 'Your review has been updated successfully'
            : 'Review submitted successfully',
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      _showMessage('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF292929),
        ),
      );
  }

  Widget _buildRatingStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final rating = index + 1;

        return IconButton(
          onPressed:
              _isSubmittingReview || _isLoadingMyReview || _reviewLoadFailed
              ? null
              : () {
                  setState(() {
                    _selectedRating = rating;
                  });
                },
          icon: Icon(
            rating <= _selectedRating
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            color: _yellow,
            size: 38,
          ),
        );
      }),
    );
  }

  Widget _buildReviewsSection() {
    final stream = _reviewsStream;
    if (stream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Unable to load reviews.',
            style: TextStyle(color: Colors.white70),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFC400)),
          );
        }

        final reviews = snapshot.data?.docs.toList() ?? [];

        reviews.sort((a, b) {
          final aDate = a.data()['createdAt'];
          final bDate = b.data()['createdAt'];

          if (aDate is Timestamp && bDate is Timestamp) {
            return bDate.compareTo(aDate);
          }

          if (aDate is Timestamp) return -1;
          if (bDate is Timestamp) return 1;

          return 0;
        });

        final validRatings = reviews
            .map((review) => review.data()['rating'])
            .whereType<num>()
            .map((rating) => rating.toDouble())
            .where((rating) => rating >= 1 && rating <= 5)
            .toList(growable: false);
        final averageRating = validRatings.isEmpty
            ? 0.0
            : validRatings.reduce((a, b) => a + b) / validRatings.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ratings & Reviews',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF252626),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, color: _yellow, size: 42),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${reviews.length} reviews',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _hasReview ? 'Edit Your Review' : 'Write a Review',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Select your rating',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (_reviewLoadFailed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _retryMyReviewLoad,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Could not load your review. Retry.'),
                  style: TextButton.styleFrom(foregroundColor: _yellow),
                ),
              ),
            _buildRatingStars(),
            TextField(
              controller: _reviewController,
              enabled:
                  !_isSubmittingReview &&
                  !_isLoadingMyReview &&
                  !_reviewLoadFailed,
              maxLines: 4,
              maxLength: 1000,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Share your opinion about this movie...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF252626),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _isSubmittingReview ||
                        _isLoadingMyReview ||
                        _reviewLoadFailed
                    ? null
                    : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _yellow,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmittingReview
                    ? const SizedBox(
                        width: 23,
                        height: 23,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _hasReview ? 'Update Review' : 'Submit Review',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'User Reviews',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No reviews yet. Be the first to review this movie!',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
            ...reviews.map((review) {
              final data = review.data();

              final name = data['userName'] ?? 'User';
              final comment = data['comment']?.toString() ?? '';
              final rating = ((data['rating'] as num?)?.toInt() ?? 0).clamp(
                0,
                5,
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF252626),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFFFC400),
                          child: Icon(Icons.person, color: Colors.black),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: _yellow,
                              size: 17,
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      comment.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final heroHeight = screen.height * 0.84;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_isPlayingVideo && _availability?.streamUrl != null)
              SafeArea(
                bottom: false,
                child: ArchiveVideoPlayer(
                  key: const Key('details-in-app-video-player'),
                  videoUrl: _availability!.streamUrl!,
                  title: _movie.title,
                  onClose: () {
                    setState(() {
                      _isPlayingVideo = false;
                    });
                  },
                ),
              ),
            SizedBox(
              height: heroHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildHeroImage(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.38, 0.66, 0.9, 1],
                        colors: [
                          Color(0x44000000),
                          Color(0x11000000),
                          Color(0x33000000),
                          Color(0xD9000000),
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                  if (_isLoadingDetails)
                    Positioned(
                      top: safeTop,
                      left: 0,
                      right: 0,
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        color: Color(0xFFFFC400),
                      ),
                    ),
                  Positioned(
                    top: safeTop + 12,
                    left: 14,
                    right: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const Key('movie-details-back-button'),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          tooltip: 'Back',
                        ),
                        IconButton(
                          key: const Key('details-watchlist-button'),
                          onPressed: (_isSaving || _isChecking)
                              ? null
                              : (_watchlistCheckFailed
                                    ? _retryWatchlistCheck
                                    : _toggleWatchlist),
                          icon: _isSaving || _isChecking
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFFFC400),
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _watchlistCheckFailed
                                      ? Icons.refresh_rounded
                                      : _isSaved
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  color: _watchlistCheckFailed
                                      ? Colors.white70
                                      : _isSaved
                                      ? const Color(0xFFFFC400)
                                      : Colors.white,
                                  size: 31,
                                ),
                          tooltip: _watchlistCheckFailed
                              ? 'Retry watchlist check'
                              : _isSaved
                              ? 'Remove from watchlist'
                              : 'Save movie',
                        ),
                      ],
                    ),
                  ),
                  if (_hasTrailer)
                    Align(
                      alignment: const Alignment(0, -0.05),
                      child: _PlayButton(
                        key: const Key('watch-trailer-play-button'),
                        onPressed: _openTrailer,
                      ),
                    ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Column(
                      children: [
                        Text(
                          _movie.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _movie.year?.toString() ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_detailsFailed) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1F1F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _detailsErrorMessage ??
                                  'Could not load full movie details.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const Key('details-retry-button'),
                            onPressed: _loadMovieDetails,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFFC400),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Availability and Watch section
                  if (_isCheckingAvailability) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFC400),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('details-watch-button'),
                        onPressed: _isRecordingWatched
                            ? null
                            : _recordMovieAsWatched,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF0222A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: _isRecordingWatched
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Watch'),
                      ),
                    ),
                  ] else if (_availability != null && _availability!.canWatch) ...[
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        key: const Key('details-watch-now-button'),
                        onPressed: _watchNow,
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        label: const Text('Watch Now'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF0222A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('details-attribution-banner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E281E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF4CAF50),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Source: ${_availability!.attribution ?? "Internet Archive"}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        key: const Key('details-watch-button'),
                        onPressed: _isRecordingWatched
                            ? null
                            : _recordMovieAsWatched,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isRecordingWatched
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Mark as Watched'),
                      ),
                    ),
                  ] else ...[
                    if (_availability != null)
                      Container(
                        key: const Key('details-unavailable-banner'),
                        margin: const EdgeInsets.only(top: 4, bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252626),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _availability!.state ==
                                      MovieAvailabilityState.rightsNotVerified
                                  ? Icons.gavel_rounded
                                  : Icons.info_outline_rounded,
                              color: _availability!.state ==
                                      MovieAvailabilityState.rightsNotVerified
                                  ? Colors.orangeAccent
                                  : Colors.white54,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _availability!.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _availability!.reasonMessage ??
                                        'Streaming is not available for this movie.',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_availability!.attribution != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Source: ${_availability!.attribution}',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('details-watch-button'),
                        onPressed: _isRecordingWatched
                            ? null
                            : _recordMovieAsWatched,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF0222A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: _isRecordingWatched
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Watch'),
                      ),
                    ),
                  ],
                  if (_hasTrailer) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('watch-trailer-action-button'),
                        onPressed: _openTrailer,
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFFFFC400),
                          size: 24,
                        ),
                        label: const Text(
                          'Watch Trailer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFFFFC400),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Expanded(
                          child: _MovieStat(
                            key: const Key('details-favorite-button'),
                            icon: _favoriteCheckFailed
                                ? Icons.refresh_rounded
                                : _isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            value: _isCheckingFavorite
                                ? '...'
                                : _favoriteCheckFailed
                                ? 'Retry'
                                : (_isFavorite ? 'Saved' : 'Save'),
                            onTap: _isCheckingFavorite || _isTogglingFavorite
                                ? null
                                : (_favoriteCheckFailed
                                      ? _retryFavoriteCheck
                                      : _toggleFavorite),
                            isActive: _isFavorite,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _MovieStat(
                            icon: Icons.schedule_rounded,
                            value: _movie.runtime != null
                                ? '${_movie.runtime} min'
                                : '—',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _MovieStat(
                            icon: Icons.star_rounded,
                            value: _movie.rating?.toStringAsFixed(1) ?? '—',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_movie.availableQualities.isNotEmpty ||
                      (_movie.language != null &&
                          _movie.language!.isNotEmpty)) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_movie.availableQualities.isNotEmpty) ...[
                          const Text(
                            'Quality:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final quality in _movie.availableQualities)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF252626),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFFC400)
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              child: Text(
                                quality,
                                style: const TextStyle(
                                  color: Color(0xFFFFC400),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                        if (_movie.language != null &&
                            _movie.language!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252626),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _movie.language!.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Screen Shots',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_movie.screenshots.isNotEmpty) ...[
                    for (final shot in _movie.screenshots) ...[
                      AspectRatio(
                        aspectRatio: 2.4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            shot,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                              color: Color(0xFF252626),
                              child: Center(
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: Colors.white54,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ] else ...[
                    for (final asset in const [
                      'assets/movie_details/screenshot_01.jpg',
                      'assets/movie_details/screenshot_02.jpg',
                      'assets/movie_details/screenshot_03.jpg',
                    ]) ...[
                      AspectRatio(
                        aspectRatio: 2.4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(asset, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _movie.description?.trim().isNotEmpty == true
                        ? _movie.description!.trim()
                        : 'No summary available yet.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_movie.cast.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Cast',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final member in _movie.cast) ...[
                      Builder(
                        builder: (context) {
                          final hasCharacter = member.contains(' as ');
                          final actorName = hasCharacter
                              ? member.split(' as ').first.trim()
                              : member.trim();
                          final characterName = hasCharacter
                              ? member.split(' as ').last.trim()
                              : '—';
                          final initials = actorName
                              .split(' ')
                              .map((part) => part.isNotEmpty ? part[0] : '')
                              .take(2)
                              .join()
                              .toUpperCase();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252626),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF383A3A),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Text(
                                    initials.isNotEmpty ? initials : '?',
                                    style: const TextStyle(
                                      color: Color(0xFFFFC400),
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Name : $actorName',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Character : $characterName',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                  if (_movie.genres.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Genres',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: [
                        for (final genre in _movie.genres)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252626),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              genre,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildReviewsSection(),
                  const SizedBox(height: 28),
                  _buildSimilarSection(),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  Widget _buildSimilarSection() {
    return Column(
      key: const Key('similar-movies-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Similar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingSimilar)
          _buildSimilarLoadingGrid()
        else if (_similarFailed && _similarMovies.isEmpty)
          _buildSimilarErrorState()
        else if (_similarMovies.isEmpty)
          _buildSimilarEmptyState()
        else
          _buildSimilarGrid(),
      ],
    );
  }

  Widget _buildSimilarGrid() {
    return GridView.builder(
      key: const Key('similar-movies-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _similarMovies.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 16,
        childAspectRatio: 0.683,
      ),
      itemBuilder: (context, index) {
        final movie = _similarMovies[index];
        return _buildSimilarMovieCard(movie, index);
      },
    );
  }

  Widget _buildSimilarMovieCard(Movie movie, int index) {
    return Semantics(
      button: true,
      label: 'View details for ${movie.title}',
      child: GestureDetector(
        key: Key('similar-movie-card-${movie.id}'),
        onTap: () => _openSimilarMovie(movie),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildSimilarPoster(movie),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.6, 1.0],
                    colors: [Colors.transparent, Color(0xDD000000)],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          movie.year != null ? '${movie.year}' : '—',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        if (movie.rating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFC400),
                            size: 13,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            movie.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimilarPoster(Movie movie) {
    final asset = movie.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _similarFallbackPoster(),
      );
    }

    final posterUrl = movie.posterUrl ?? movie.largeCoverImageUrl;
    if (posterUrl != null && posterUrl.isNotEmpty) {
      return Image.network(
        posterUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: Color(0xFF252626),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFC400),
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _similarFallbackPoster(),
      );
    }

    return _similarFallbackPoster();
  }

  Widget _similarFallbackPoster() => const ColoredBox(
        color: Color(0xFF252626),
        child: Center(
          child: Icon(Icons.movie_outlined, color: Colors.white38, size: 40),
        ),
      );

  Widget _buildSimilarLoadingGrid() {
    return GridView.builder(
      key: const Key('similar-movies-loading-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 16,
        childAspectRatio: 0.683,
      ),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: const ColoredBox(
            color: Color(0xFF252626),
            child: Center(
              child: Icon(
                Icons.local_movies_outlined,
                color: Color(0xFFFFC400),
                size: 36,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimilarEmptyState() {
    return Container(
      key: const Key('similar-movies-empty-state'),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.movie_filter_outlined, color: Colors.white38, size: 40),
          SizedBox(height: 8),
          Text(
            'No similar movies found.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarErrorState() {
    return Container(
      key: const Key('similar-movies-error-state'),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.refresh_rounded, color: Colors.white38, size: 36),
          const SizedBox(height: 8),
          const Text(
            'Could not load similar movies.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            key: const Key('similar-movies-retry-button'),
            onPressed: _loadSimilarMovies,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC400),
              foregroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFC400),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(7),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFC400),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MovieStat extends StatelessWidget {
  const _MovieStat({
    super.key,
    required this.icon,
    required this.value,
    this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF252626),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(17)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.redAccent : const Color(0xFFFFC400),
                size: 28,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
