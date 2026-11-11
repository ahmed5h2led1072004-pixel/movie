import 'dart:async';

import 'package:flutter/material.dart';

import '../data/movie_matching_service.dart';
import '../data/movie_repository.dart';
import '../data/yts_api_service.dart';
import '../models/movie.dart';
import '../models/movie_availability.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/movie_results_grid.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    this.initialGenre,
    this.initialSort,
    this.repository,
    this.matchingService,
  });

  final String? initialGenre;
  final String? initialSort;
  final MovieRepository? repository;
  final MovieMatchingService? matchingService;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

enum _BrowseState { loading, results, empty, error }

class _BrowseScreenState extends State<BrowseScreen> {
  static const _genres = [
    'Action',
    'Adventure',
    'Animation',
    'Biography',
    'Comedy',
    'Drama',
    'Fantasy',
  ];

  static const _sortOptions = <String, String>{
    'date_added': 'Latest',
    'rating': 'Top Rated',
    'year': 'Year',
    'download_count': 'Popular',
  };

  static const int _pageSize = 20;

  static final MovieRepository _defaultRepository = MovieRepository(
    apiService: YtsApiService(),
  );
  static final MovieMatchingService _defaultMatchingService =
      MovieMatchingService();

  late final MovieRepository _repository =
      widget.repository ?? _defaultRepository;
  late final MovieMatchingService _matchingService =
      widget.matchingService ?? _defaultMatchingService;
  final ScrollController _scrollController = ScrollController();

  int _selectedGenre = 0;
  String _selectedSort = 'date_added';
  int _requestVersion = 0;
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  _BrowseState _state = _BrowseState.loading;
  List<Movie> _movies = const [];

  MovieAvailabilityFilter _availabilityFilter = MovieAvailabilityFilter.all;
  final Map<String, MovieAvailability> _availabilityMap = {};
  bool _isResolvingAvailability = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSort != null &&
        _sortOptions.containsKey(widget.initialSort)) {
      _selectedSort = widget.initialSort!;
    }
    final initialIndex = _genres.indexWhere(
      (genre) =>
          genre.toLowerCase() == widget.initialGenre?.trim().toLowerCase(),
    );
    if (initialIndex >= 0) _selectedGenre = initialIndex;

    final initialFallback = _repository.byGenre(_genres[_selectedGenre]);
    if (initialFallback.isNotEmpty) {
      _movies = initialFallback;
      _state = _BrowseState.results;
    }

    _scrollController.addListener(_onScroll);
    _loadMovies();
  }

  @override
  void dispose() {
    _requestVersion++;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMovies() async {
    final requestVersion = ++_requestVersion;

    setState(() {
      if (_movies.isEmpty) {
        _state = _BrowseState.loading;
      }
      _currentPage = 1;
      _hasMore = true;
      _isLoadingMore = false;
    });

    try {
      final result = await _repository.fetchMovies(
        limit: _pageSize,
        page: 1,
        genre: _genres[_selectedGenre],
        sortBy: _selectedSort,
      );

      if (!mounted || requestVersion != _requestVersion) return;

      if (result.error != null && result.movies.isEmpty) {
        setState(() {
          _movies = const [];
          _state = _BrowseState.error;
        });
        return;
      }

      setState(() {
        _movies = result.movies;
        _state =
            result.movies.isEmpty ? _BrowseState.empty : _BrowseState.results;
        _hasMore = result.movies.length >= _pageSize;
      });

      _resolveAvailability(result.movies);

      if (result.usedLocalFallback && mounted) {
        _showFallbackMessage();
      }
    } catch (_) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _movies = const [];
        _state = _BrowseState.error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _state != _BrowseState.results) return;

    final requestVersion = _requestVersion;
    final nextPage = _currentPage + 1;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final service = _repository.apiService;
      if (service == null) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
        return;
      }

      final newMovies = await service.fetchMovies(
        limit: _pageSize,
        page: nextPage,
        genre: _genres[_selectedGenre],
        sortBy: _selectedSort,
      );

      if (!mounted || requestVersion != _requestVersion) return;

      setState(() {
        _isLoadingMore = false;
        if (newMovies.isEmpty) {
          _hasMore = false;
        } else {
          _currentPage = nextPage;
          final existingIds = _movies.map((m) => m.id).toSet();
          final uniqueNewMovies =
              newMovies.where((m) => !existingIds.contains(m.id)).toList();
          _movies = [..._movies, ...uniqueNewMovies];
          if (newMovies.length < _pageSize) {
            _hasMore = false;
          }
          _resolveAvailability(uniqueNewMovies);
        }
      });
    } catch (_) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not load more movies.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
      }
    }
  }

  void _resolveAvailability(List<Movie> movies) {
    if (movies.isEmpty) return;
    setState(() {
      _isResolvingAvailability = true;
    });
    unawaited(
      _matchingService.checkMultipleAvailability(movies).then((results) {
        if (!mounted) return;
        setState(() {
          _availabilityMap.addAll(results);
          _isResolvingAvailability = false;
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _isResolvingAvailability = false;
        });
      }),
    );
  }

  List<Movie> get _displayMovies {
    switch (_availabilityFilter) {
      case MovieAvailabilityFilter.all:
        return _movies;
      case MovieAvailabilityFilter.availableToWatch:
        return _movies
            .where((m) => _availabilityMap[m.id]?.canWatch == true)
            .toList();
      case MovieAvailabilityFilter.metadataOnly:
        return _movies
            .where((m) {
              final avail = _availabilityMap[m.id];
              if (avail == null) return false;
              return !avail.canWatch;
            })
            .toList();
    }
  }

  void _showFallbackMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load online movies. Showing saved movies.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }

  void _onGenreSelected(int index) {
    if (_selectedGenre == index && _state != _BrowseState.error) return;
    setState(() {
      _selectedGenre = index;
      _availabilityMap.clear();
      _isResolvingAvailability = false;
    });
    _loadMovies();
  }

  void _onSortChanged(String? newSort) {
    if (newSort == null || newSort == _selectedSort) return;
    setState(() {
      _selectedSort = newSort;
      _availabilityMap.clear();
      _isResolvingAvailability = false;
    });
    _loadMovies();
  }

  void _selectTab(int index) {
    if (index == 2) return;
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (index == 1) {
      Navigator.of(context).pushReplacementNamed('/search');
    } else {
      Navigator.of(context).pushReplacementNamed('/profile');
    }
  }

  Widget _buildBody() {
    switch (_state) {
      case _BrowseState.loading:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC400)),
        );
      case _BrowseState.empty:
        return const Center(
          child: Text(
            'No movies available in this genre yet.',
            style: TextStyle(color: Colors.white70),
          ),
        );
      case _BrowseState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white54,
                  size: 42,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Failed to load movies. Please check your connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('browse-retry-button'),
                  onPressed: _loadMovies,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC400),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case _BrowseState.results:
        final displayed = _displayMovies;
        if (displayed.isEmpty && _movies.isNotEmpty) {
          final hasPendingChecks =
              _movies.any((m) => !_availabilityMap.containsKey(m.id));
          if (_isResolvingAvailability && hasPendingChecks) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFFC400)),
                  SizedBox(height: 16),
                  Text(
                    'Checking movie availability & streaming rights...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_alt_off_rounded,
                    color: Colors.white54,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _availabilityFilter == MovieAvailabilityFilter.availableToWatch
                        ? 'No movies currently available to watch in this genre.'
                        : 'No metadata-only movies found.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  if (_hasMore &&
                      _availabilityFilter ==
                          MovieAvailabilityFilter.availableToWatch) ...[
                    FilledButton.icon(
                      key: const Key('browse-load-more-available-button'),
                      onPressed: _isLoadingMore ? null : _loadMore,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC400),
                        foregroundColor: Colors.black,
                      ),
                      icon: _isLoadingMore
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.arrow_downward_rounded, size: 16),
                      label: Text(_isLoadingMore
                          ? 'Checking Next Page...'
                          : 'Check Next Page'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    key: const Key('browse-reset-filter-button'),
                    onPressed: () {
                      setState(() {
                        _availabilityFilter = MovieAvailabilityFilter.all;
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E2E2E),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Show All Movies'),
                  ),
                ],
              ),
            ),
          );
        }
        return MovieResultsGrid(
          movies: displayed,
          showMovieMetadata: true,
          controller: _scrollController,
          isLoadingMore: _isLoadingMore,
          hasMore: _hasMore,
          onLoadMore: _loadMore,
          availabilityMap: _availabilityMap,
        );
    }
  }

  Widget _buildAvailabilityFilter() {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _buildFilterChip(
            filter: MovieAvailabilityFilter.all,
            label: 'All Movies',
            key: const Key('browse-filter-all'),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            filter: MovieAvailabilityFilter.availableToWatch,
            label: 'Available to Watch',
            icon: Icons.play_circle_fill_rounded,
            key: const Key('browse-filter-watchable'),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            filter: MovieAvailabilityFilter.metadataOnly,
            label: 'Metadata Only',
            icon: Icons.info_outline_rounded,
            key: const Key('browse-filter-metadata'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required MovieAvailabilityFilter filter,
    required String label,
    IconData? icon,
    Key? key,
  }) {
    final isSelected = _availabilityFilter == filter;
    return GestureDetector(
      key: key,
      onTap: () {
        if (_availabilityFilter != filter) {
          setState(() {
            _availabilityFilter = filter;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFC400) : const Color(0xFF222323),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFC400) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.black : const Color(0xFFFFC400),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF101111),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          scrollDirection: Axis.horizontal,
                          itemCount: _genres.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final selected = _selectedGenre == index;
                            return GestureDetector(
                              onTap: () => _onGenreSelected(index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFFFFC400)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: const Color(0xFFFFC400),
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _genres[index],
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.black
                                        : const Color(0xFFFFC400),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('browse-sort-dropdown'),
                            value: _selectedSort,
                            dropdownColor: const Color(0xFF292A2A),
                            icon: const Icon(
                              Icons.sort_rounded,
                              color: Color(0xFFFFC400),
                              size: 26,
                            ),
                            style: const TextStyle(
                              color: Color(0xFFFFC400),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            onChanged: _onSortChanged,
                            items: _sortOptions.entries
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildAvailabilityFilter(),
                Expanded(child: _buildBody()),
              ],
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: safeBottom + 8,
              child: AppBottomNavigationBar(
                selectedIndex: 2,
                onSelected: _selectTab,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
