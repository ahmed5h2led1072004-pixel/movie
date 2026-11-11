import 'dart:async';

import 'package:flutter/material.dart';

import '../data/movie_matching_service.dart';
import '../data/movie_repository.dart';
import '../data/yts_api_service.dart';
import '../models/movie.dart';
import '../models/movie_availability.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/movie_results_grid.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.repository, this.matchingService});

  /// Optional repository injection keeps search behavior testable.
  final MovieRepository? repository;
  final MovieMatchingService? matchingService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { initial, loading, results, empty, error }

class _SearchScreenState extends State<SearchScreen> {
  static final MovieRepository _defaultRepository = MovieRepository(
    apiService: YtsApiService(),
  );
  static final MovieMatchingService _defaultMatchingService =
      MovieMatchingService();
  static const _debounceDuration = Duration(milliseconds: 500);

  final _searchController = TextEditingController();
  late final MovieRepository _repository =
      widget.repository ?? _defaultRepository;
  late final MovieMatchingService _matchingService =
      widget.matchingService ?? _defaultMatchingService;

  Timer? _debounce;
  int _requestVersion = 0;
  _SearchState _searchState = _SearchState.initial;
  List<Movie> _results = const [];

  MovieAvailabilityFilter _availabilityFilter = MovieAvailabilityFilter.all;
  final Map<String, MovieAvailability> _availabilityMap = {};
  bool _isResolvingAvailability = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _requestVersion++;
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final requestVersion = ++_requestVersion;

    setState(() {
      _results = const [];
      _availabilityMap.clear();
      _isResolvingAvailability = false;
      _searchState = query.length < 2
          ? _SearchState.initial
          : _SearchState.loading;
    });

    if (query.length < 2) return;

    _debounce = Timer(_debounceDuration, () => _search(query, requestVersion));
  }

  Future<void> _search(String query, int requestVersion) async {
    late final MovieFetchResult result;
    try {
      result = await _repository.searchRemote(query);
    } catch (_) {
      if (!mounted || requestVersion != _requestVersion) return;

      setState(() {
        _results = const [];
        _searchState = _SearchState.error;
      });
      return;
    }

    if (!mounted || requestVersion != _requestVersion) return;

    setState(() {
      if (result.error != null) {
        _searchState = _SearchState.error;
        _results = const [];
      } else if (result.movies.isEmpty) {
        _searchState = _SearchState.empty;
        _results = const [];
      } else {
        _searchState = _SearchState.results;
        _results = result.movies;
      }
    });

    if (result.movies.isNotEmpty) {
      _resolveAvailability(result.movies, requestVersion);
    }
  }

  void _resolveAvailability(List<Movie> movies, int requestVersion) {
    if (movies.isEmpty) return;
    setState(() {
      _isResolvingAvailability = true;
    });
    unawaited(
      _matchingService.checkMultipleAvailability(movies).then((availabilities) {
        if (!mounted || requestVersion != _requestVersion) return;
        setState(() {
          _availabilityMap.addAll(availabilities);
          _isResolvingAvailability = false;
        });
      }).catchError((_) {
        if (!mounted || requestVersion != _requestVersion) return;
        setState(() {
          _isResolvingAvailability = false;
        });
      }),
    );
  }

  List<Movie> get _filteredResults {
    switch (_availabilityFilter) {
      case MovieAvailabilityFilter.all:
        return _results;
      case MovieAvailabilityFilter.availableToWatch:
        return _results
            .where((m) => _availabilityMap[m.id]?.canWatch == true)
            .toList();
      case MovieAvailabilityFilter.metadataOnly:
        return _results
            .where((m) {
              final avail = _availabilityMap[m.id];
              if (avail == null) return false;
              return !avail.canWatch;
            })
            .toList();
    }
  }

  void _retrySearch() {
    final query = _searchController.text.trim();
    if (query.length < 2) return;

    _debounce?.cancel();
    final requestVersion = ++_requestVersion;
    setState(() {
      _results = const [];
      _searchState = _SearchState.loading;
    });
    _search(query, requestVersion);
  }

  void _selectTab(int index) {
    if (index == 1) return;
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/home');
      return;
    }
    if (index == 2) {
      Navigator.of(context).pushReplacementNamed('/browse');
      return;
    }
    Navigator.of(context).pushReplacementNamed('/profile');
  }

  Widget _buildSearchState() {
    switch (_searchState) {
      case _SearchState.initial:
        return const Center(
          child: Image(
            key: Key('search-empty-illustration'),
            image: AssetImage('assets/search/empty_search.png'),
            width: 130,
            height: 140,
            fit: BoxFit.contain,
          ),
        );
      case _SearchState.loading:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC400)),
        );
      case _SearchState.results:
        final filtered = _filteredResults;
        if (filtered.isEmpty && _results.isNotEmpty) {
          final hasPending =
              _results.any((m) => !_availabilityMap.containsKey(m.id));
          if (_isResolvingAvailability && hasPending) {
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
                    _availabilityFilter ==
                            MovieAvailabilityFilter.availableToWatch
                        ? 'No watchable movies found for this search.'
                        : 'No metadata-only movies found for this search.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const Key('search-reset-filter-button'),
                    onPressed: () {
                      setState(() {
                        _availabilityFilter = MovieAvailabilityFilter.all;
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC400),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Show All Movies'),
                  ),
                ],
              ),
            ),
          );
        }
        return MovieResultsGrid(
          movies: filtered,
          showMovieMetadata: true,
          availabilityMap: _availabilityMap,
        );
      case _SearchState.empty:
        return const Center(
          child: Text(
            'No movies found. Try a different title.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        );
      case _SearchState.error:
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
                  'Search is temporarily unavailable. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retrySearch,
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
    }
  }

  Widget _buildAvailabilityFilter() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            filter: MovieAvailabilityFilter.all,
            label: 'All Movies',
            key: const Key('search-filter-all'),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            filter: MovieAvailabilityFilter.availableToWatch,
            label: 'Available to Watch',
            icon: Icons.play_circle_fill_rounded,
            key: const Key('search-filter-watchable'),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            filter: MovieAvailabilityFilter.metadataOnly,
            label: 'Metadata Only',
            icon: Icons.info_outline_rounded,
            key: const Key('search-filter-metadata'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 22, 15, 82),
              child: Column(
                children: [
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF292A2A),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _retrySearch(),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(color: Colors.white, fontSize: 16),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 31,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 59,
                          minHeight: 56,
                        ),
                      ),
                    ),
                  ),
                  if (_searchState == _SearchState.results ||
                      _results.isNotEmpty)
                    _buildAvailabilityFilter(),
                  Expanded(child: _buildSearchState()),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: safeBottom + 8,
              child: AppBottomNavigationBar(
                selectedIndex: 1,
                onSelected: _selectTab,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
