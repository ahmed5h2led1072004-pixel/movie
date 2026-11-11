import 'package:flutter/material.dart';

import '../data/movie_repository.dart';
import '../data/yts_api_service.dart';
import '../models/movie.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import 'movie_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.repository});

  final MovieRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final MovieRepository _defaultRepository = MovieRepository(
    apiService: YtsApiService(),
  );

  late final MovieRepository _repository =
      widget.repository ?? _defaultRepository;

  static const int _popularPageSize = 20;
  static const int _actionPageSize = 20;

  late final Future<MovieFetchResult> _moviesRequest;
  late final PageController _featuredController;
  final ScrollController _popularScrollController = ScrollController();
  final ScrollController _actionScrollController = ScrollController();

  List<Movie> _popularMovies = const [];
  bool _isPopularLoading = true;
  bool _isPopularLoadingMore = false;
  bool _hasMorePopular = true;
  Object? _popularError;
  Object? _popularLoadMoreError;
  int _popularPage = 1;
  int _popularRequestVersion = 0;

  List<Movie> _actionMovies = const [];
  bool _isActionLoading = true;
  bool _isActionLoadingMore = false;
  bool _hasMoreAction = true;
  Object? _actionError;
  Object? _actionLoadMoreError;
  int _actionPage = 1;
  int _actionRequestVersion = 0;

  int _selectedTab = 0;
  bool _fallbackMessageShown = false;

  @override
  void initState() {
    super.initState();
    _moviesRequest = _repository.fetchMovies(
      limit: 20,
      sortBy: 'date_added',
    );
    _featuredController = PageController(
      initialPage: 1,
      viewportFraction: 0.56,
    );
    _popularScrollController.addListener(_onPopularScroll);
    _actionScrollController.addListener(_onActionScroll);
    _loadPopularMovies();
    _loadActionMovies();
  }

  @override
  void dispose() {
    _popularRequestVersion++;
    _actionRequestVersion++;
    _popularScrollController.removeListener(_onPopularScroll);
    _popularScrollController.dispose();
    _actionScrollController.removeListener(_onActionScroll);
    _actionScrollController.dispose();
    _featuredController.dispose();
    super.dispose();
  }

  void _onPopularScroll() {
    if (!_popularScrollController.hasClients) return;
    final maxScroll = _popularScrollController.position.maxScrollExtent;
    final currentScroll = _popularScrollController.position.pixels;
    if (currentScroll >= maxScroll - 250) {
      _loadNextPopularPage();
    }
  }

  Future<void> _loadPopularMovies({bool isRefresh = false}) async {
    if (isRefresh) {
      _popularPage = 1;
      _hasMorePopular = true;
    }
    final requestVersion = ++_popularRequestVersion;

    setState(() {
      _isPopularLoading = true;
      _popularError = null;
      _popularLoadMoreError = null;
    });

    try {
      final result = await _repository.fetchMovies(
        limit: _popularPageSize,
        page: 1,
        sortBy: 'download_count',
      );

      if (!mounted || requestVersion != _popularRequestVersion) return;

      if (result.error != null || (result.usedLocalFallback && result.error != null)) {
        setState(() {
          _isPopularLoading = false;
          _popularError = result.error;
        });
        return;
      }

      final movies = result.movies;
      final seen = <String>{};
      final unique = <Movie>[];
      for (final movie in movies) {
        if (seen.add(movie.id)) {
          unique.add(movie);
        }
      }

      setState(() {
        _isPopularLoading = false;
        _popularMovies = unique;
        _hasMorePopular = unique.length >= _popularPageSize;
      });
    } catch (error) {
      if (!mounted || requestVersion != _popularRequestVersion) return;
      setState(() {
        _isPopularLoading = false;
        _popularError = error;
      });
    }
  }

  Future<void> _loadNextPopularPage() async {
    if (_isPopularLoading || _isPopularLoadingMore || !_hasMorePopular) return;

    final nextPage = _popularPage + 1;
    final requestVersion = _popularRequestVersion;

    setState(() {
      _isPopularLoadingMore = true;
      _popularLoadMoreError = null;
    });

    try {
      final result = await _repository.fetchMovies(
        limit: _popularPageSize,
        page: nextPage,
        sortBy: 'download_count',
      );

      if (!mounted || requestVersion != _popularRequestVersion) return;

      if (result.error != null) {
        setState(() {
          _isPopularLoadingMore = false;
          _popularLoadMoreError = result.error;
        });
        return;
      }

      final newMovies = result.movies;
      if (newMovies.isEmpty) {
        setState(() {
          _isPopularLoadingMore = false;
          _hasMorePopular = false;
        });
        return;
      }

      final existingIds = _popularMovies.map((m) => m.id).toSet();
      final uniqueNew =
          newMovies.where((m) => !existingIds.contains(m.id)).toList();

      setState(() {
        _popularPage = nextPage;
        _isPopularLoadingMore = false;
        _popularMovies = [..._popularMovies, ...uniqueNew];
        if (newMovies.length < _popularPageSize || uniqueNew.isEmpty) {
          _hasMorePopular = false;
        }
      });
    } catch (error) {
      if (!mounted || requestVersion != _popularRequestVersion) return;
      setState(() {
        _isPopularLoadingMore = false;
        _popularLoadMoreError = error;
      });
    }
  }

  void _onActionScroll() {
    if (!_actionScrollController.hasClients) return;
    final maxScroll = _actionScrollController.position.maxScrollExtent;
    final currentScroll = _actionScrollController.position.pixels;
    if (currentScroll >= maxScroll - 250) {
      _loadNextActionPage();
    }
  }

  Future<void> _loadActionMovies({bool isRefresh = false}) async {
    if (isRefresh) {
      _actionPage = 1;
      _hasMoreAction = true;
    }
    final requestVersion = ++_actionRequestVersion;

    setState(() {
      _isActionLoading = true;
      _actionError = null;
      _actionLoadMoreError = null;
    });

    try {
      final result = await _repository.fetchMovies(
        limit: _actionPageSize,
        page: 1,
        genre: 'Action',
      );

      if (!mounted || requestVersion != _actionRequestVersion) return;

      if (result.error != null || (result.usedLocalFallback && result.error != null)) {
        setState(() {
          _isActionLoading = false;
          _actionError = result.error;
        });
        return;
      }

      final movies = result.movies;
      final seen = <String>{};
      final unique = <Movie>[];
      for (final movie in movies) {
        if (seen.add(movie.id)) {
          unique.add(movie);
        }
      }

      setState(() {
        _isActionLoading = false;
        _actionMovies = unique;
        _hasMoreAction = unique.length >= _actionPageSize;
      });
    } catch (error) {
      if (!mounted || requestVersion != _actionRequestVersion) return;
      setState(() {
        _isActionLoading = false;
        _actionError = error;
      });
    }
  }

  Future<void> _loadNextActionPage() async {
    if (_isActionLoading || _isActionLoadingMore || !_hasMoreAction) return;

    final nextPage = _actionPage + 1;
    final requestVersion = _actionRequestVersion;

    setState(() {
      _isActionLoadingMore = true;
      _actionLoadMoreError = null;
    });

    try {
      final result = await _repository.fetchMovies(
        limit: _actionPageSize,
        page: nextPage,
        genre: 'Action',
      );

      if (!mounted || requestVersion != _actionRequestVersion) return;

      if (result.error != null) {
        setState(() {
          _isActionLoadingMore = false;
          _actionLoadMoreError = result.error;
        });
        return;
      }

      final newMovies = result.movies;
      if (newMovies.isEmpty) {
        setState(() {
          _isActionLoadingMore = false;
          _hasMoreAction = false;
        });
        return;
      }

      final existingIds = _actionMovies.map((m) => m.id).toSet();
      final uniqueNew =
          newMovies.where((m) => !existingIds.contains(m.id)).toList();

      setState(() {
        _actionPage = nextPage;
        _isActionLoadingMore = false;
        _actionMovies = [..._actionMovies, ...uniqueNew];
        if (newMovies.length < _actionPageSize || uniqueNew.isEmpty) {
          _hasMoreAction = false;
        }
      });
    } catch (error) {
      if (!mounted || requestVersion != _actionRequestVersion) return;
      setState(() {
        _isActionLoadingMore = false;
        _actionLoadMoreError = error;
      });
    }
  }

  void _openMovieDetails(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MovieDetailsScreen(movie: movie)),
    );
  }

  void _openActionMovies() {
    Navigator.of(context).pushNamed('/browse', arguments: 'Action');
  }

  void _openPopularMovies() {
    Navigator.of(context).pushNamed(
      '/browse',
      arguments: {'sortBy': 'download_count'},
    );
  }

  void _showFallbackMessage() {
    if (_fallbackMessageShown) return;
    _fallbackMessageShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load latest movies. Showing saved movies.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF101111),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/home/home_background.png',
              fit: BoxFit.cover,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x44101111),
                    Color(0x99101111),
                    Color(0xFF101111),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final featuredHeight = (constraints.maxHeight * 0.39)
                    .clamp(330.0, 360.0)
                    .toDouble();
                final popularHeight = (constraints.maxHeight * 0.31)
                    .clamp(260.0, 290.0)
                    .toDouble();
                final actionHeight = (constraints.maxHeight * 0.31)
                    .clamp(260.0, 290.0)
                    .toDouble();

                return FutureBuilder<MovieFetchResult>(
                  future: _moviesRequest,
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState != ConnectionState.done;
                    final fetchResult = snapshot.data;
                    final movies = snapshot.hasError
                        ? _repository.movies
                        : fetchResult?.movies ?? _repository.movies;

                    if (snapshot.hasError ||
                        (fetchResult?.usedLocalFallback ?? false)) {
                      _showFallbackMessage();
                    }

                    final featuredMovies = movies.take(5).toList();

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 88),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 2),
                          Center(
                            child: GestureDetector(
                              key: const Key('dev-archive-header-trigger'),
                              onTap: () => Navigator.of(context).pushNamed('/archive-test'),
                              child: Image.asset(
                                'assets/home/available_now.png',
                                width: 270,
                                height: 68,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            height: featuredHeight,
                            child: isLoading
                                ? _buildLoadingCarousel()
                                : featuredMovies.isEmpty
                                ? _buildEmptyCarousel()
                                : PageView.builder(
                                    controller: _featuredController,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: featuredMovies.length,
                                    itemBuilder: (context, index) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: _buildMovieCard(
                                        featuredMovies[index],
                                        borderRadius: 13,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 36),
                          Center(
                            child: Image.asset(
                              'assets/home/watch_now.png',
                              width: 350,
                              height: 100,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 36),
                          // Popular Movies Section
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC400),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Popular Movies',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Semantics(
                                  button: true,
                                  label: 'See all popular movies',
                                  child: InkWell(
                                    key: const Key(
                                      'home-popular-see-all-button',
                                    ),
                                    onTap: _openPopularMovies,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/home/see_more.png',
                                          width: 82,
                                          height: 26,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 5),
                                        Image.asset(
                                          'assets/home/arrow_right.png',
                                          width: 12,
                                          height: 12,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: popularHeight,
                            child: _buildPopularSectionContent(),
                          ),
                          const SizedBox(height: 36),
                          // Action Section
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                            child: Row(
                              children: [
                                Semantics(
                                  button: true,
                                  label: 'Browse Action movies',
                                  child: InkWell(
                                    key: const Key('home-action-button'),
                                    onTap: _openActionMovies,
                                    child: Image.asset(
                                      'assets/home/action.png',
                                      width: 62,
                                      height: 28,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Semantics(
                                  button: true,
                                  label: 'See more Action movies',
                                  child: InkWell(
                                    key: const Key('home-see-more-button'),
                                    onTap: _openActionMovies,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/home/see_more.png',
                                          width: 82,
                                          height: 26,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 5),
                                        Image.asset(
                                          'assets/home/arrow_right.png',
                                          width: 12,
                                          height: 12,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: actionHeight,
                            child: _buildActionSectionContent(),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            right: 12,
            child: Semantics(
              button: true,
              label: 'Open Internet Archive Playback Test',
              child: IconButton(
                key: const Key('home-archive-test-button'),
                icon: const Icon(
                  Icons.video_library_rounded,
                  color: Color(0xFFFFC400),
                  size: 26,
                ),
                tooltip: 'Archive Playback Test',
                onPressed: () =>
                    Navigator.of(context).pushNamed('/archive-test'),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: safeBottom + 8,
            child: AppBottomNavigationBar(
              selectedIndex: _selectedTab,
              height: 64,
              onSelected: (index) {
                setState(() => _selectedTab = index);
                if (index == 1) {
                  Navigator.of(context).pushReplacementNamed('/search');
                  return;
                }
                if (index == 2) {
                  Navigator.of(context).pushReplacementNamed('/browse');
                  return;
                }
                if (index == 3) {
                  Navigator.of(context).pushReplacementNamed('/profile');
                  return;
                }
                if (index != 0) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(_tabMessage(index)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularSectionContent() {
    if (_isPopularLoading) {
      return _buildLoadingPopularList();
    }
    if (_popularError != null && _popularMovies.isEmpty) {
      return _buildPopularErrorCard();
    }
    if (_popularMovies.isEmpty) {
      return _buildEmptyPopularList();
    }

    final hasFooter = _isPopularLoadingMore || _popularLoadMoreError != null;

    return ListView.separated(
      key: const Key('home-popular-list-view'),
      controller: _popularScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: _popularMovies.length + (hasFooter ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (index < _popularMovies.length) {
          return SizedBox(
            width: 160,
            child: _buildMovieCard(
              _popularMovies[index],
              borderRadius: 12,
              compact: true,
            ),
          );
        }

        if (_popularLoadMoreError != null) {
          return SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: const Color(0xFF252626),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFFFC400),
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('home-popular-load-more-retry'),
                        onPressed: _loadNextPopularPage,
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            color: Color(0xFFFFC400),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: const ColoredBox(
              color: Color(0xFF252626),
              child: Center(
                child: SizedBox(
                  key: Key('home-popular-loading-more-indicator'),
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Color(0xFFFFC400),
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingPopularList() => ListView.separated(
        key: const Key('home-popular-loading-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            SizedBox(width: 160, child: _loadingCard(12)),
      );

  Widget _buildEmptyPopularList() => ListView(
        key: const Key('home-popular-empty-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: 240,
            child: _emptyCard('No popular movies found.', 12),
          ),
        ],
      );

  Widget _buildPopularErrorCard() => ListView(
        key: const Key('home-popular-error-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: const Color(0xFF252626),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white54,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Could not load popular movies.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          key: const Key('home-popular-retry-button'),
                          onPressed: () => _loadPopularMovies(isRefresh: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC400),
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _buildMovieCard(
    Movie movie, {
    required double borderRadius,
    bool compact = false,
  }) {
    return GestureDetector(
      onTap: () => _openMovieDetails(movie),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _HomeMoviePoster(movie: movie),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.55, 1],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(
              left: compact ? 9 : 15,
              right: compact ? 9 : 15,
              bottom: compact ? 10 : 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 18,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        movie.year?.toString() ?? '—',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: compact ? 11 : 14,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.star_rounded,
                        color: const Color(0xFFFFC400),
                        size: compact ? 14 : 17,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        movie.rating?.toStringAsFixed(1) ?? '—',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11 : 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCarousel() => PageView.builder(
        controller: _featuredController,
        itemCount: 3,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: _loadingCard(13),
        ),
      );

  Widget _buildEmptyCarousel() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: _emptyCard('No movies are available right now.', 13),
      );

  Widget _buildActionSectionContent() {
    if (_isActionLoading) {
      return _buildLoadingActionList();
    }
    if (_actionError != null && _actionMovies.isEmpty) {
      return _buildActionErrorCard();
    }
    if (_actionMovies.isEmpty) {
      return _buildEmptyActionList();
    }

    final hasFooter = _isActionLoadingMore || _actionLoadMoreError != null;

    return ListView.separated(
      key: const Key('home-action-list-view'),
      controller: _actionScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: _actionMovies.length + (hasFooter ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (index < _actionMovies.length) {
          return SizedBox(
            width: 160,
            child: _buildMovieCard(
              _actionMovies[index],
              borderRadius: 12,
              compact: true,
            ),
          );
        }

        if (_actionLoadMoreError != null) {
          return SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: const Color(0xFF252626),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFFFC400),
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('home-action-load-more-retry'),
                        onPressed: _loadNextActionPage,
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            color: Color(0xFFFFC400),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: const ColoredBox(
              color: Color(0xFF252626),
              child: Center(
                child: SizedBox(
                  key: Key('home-action-loading-more-indicator'),
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Color(0xFFFFC400),
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingActionList() => ListView.separated(
        key: const Key('home-action-loading-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            SizedBox(width: 160, child: _loadingCard(12)),
      );

  Widget _buildEmptyActionList() => ListView(
        key: const Key('home-action-empty-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(width: 220, child: _emptyCard('No Action movies found.', 12)),
        ],
      );

  Widget _buildActionErrorCard() => ListView(
        key: const Key('home-action-error-list'),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: const Color(0xFF252626),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white54,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Could not load Action movies.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          key: const Key('home-action-retry-button'),
                          onPressed: () => _loadActionMovies(isRefresh: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC400),
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _loadingCard(double radius) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: const ColoredBox(
          color: Color(0xFF252626),
          child: Center(
            child: Icon(
              Icons.local_movies_outlined,
              color: Color(0xFFFFC400),
              size: 44,
            ),
          ),
        ),
      );

  Widget _emptyCard(String message, double radius) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: const Color(0xFF252626),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      );

  String _tabMessage(int index) {
    switch (index) {
      case 1:
        return 'Search is coming soon';
      case 2:
        return 'Explore is coming soon';
      case 3:
        return 'Profile is coming soon';
      default:
        return 'Home';
    }
  }
}

class _HomeMoviePoster extends StatelessWidget {
  const _HomeMoviePoster({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final asset = movie.imageAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallbackPoster(),
      );
    }

    final posterUrl = movie.posterUrl ?? movie.largeCoverImageUrl;
    if (posterUrl == null || posterUrl.isEmpty) return _fallbackPoster();

    return Image.network(
      posterUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null ? child : _loadingPoster(),
      errorBuilder: (context, error, stackTrace) => _fallbackPoster(),
    );
  }

  Widget _loadingPoster() => const ColoredBox(
        color: Color(0xFF252626),
        child: Center(
          child: Icon(
            Icons.local_movies_outlined,
            color: Color(0xFFFFC400),
            size: 44,
          ),
        ),
      );

  Widget _fallbackPoster() => const ColoredBox(
        color: Color(0xFF252626),
        child: Center(
          child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
        ),
      );
}
