import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/internet_archive_service.dart';
import '../models/internet_archive_movie.dart';
import '../widgets/archive_video_player.dart';

class ArchiveTestScreen extends StatefulWidget {
  final InternetArchiveService? archiveService;

  const ArchiveTestScreen({
    super.key,
    this.archiveService,
  });

  @override
  State<ArchiveTestScreen> createState() => _ArchiveTestScreenState();
}

class _ArchiveTestScreenState extends State<ArchiveTestScreen> {
  static const Color _yellow = Color(0xFFFFC400);

  late final InternetArchiveService _service =
      widget.archiveService ?? InternetArchiveService();

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<String> _availableGenres = [
    'All',
    'Horror',
    'Comedy',
    'Drama',
    'Sci-Fi',
    'Film-Noir',
    'Animation',
  ];

  static const List<String> _availableEras = [
    'All Eras',
    '1920',
    '1930',
    '1940',
    '1950',
    '1960',
  ];

  List<InternetArchiveMovie> _movies = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  bool _verifiedOnly = false;
  String _selectedGenre = 'All';
  int? _selectedYear;

  InternetArchiveMovie? _activeMovie;
  String? _activeVideoUrl;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialCandidates();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 300) {
      _loadNextPage();
    }
  }

  Future<void> _loadInitialCandidates({bool isRefresh = false}) async {
    if (isRefresh) {
      _hasMore = true;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pageResult = await _service.fetchPlayableCatalogPage(
        rows: 20,
        query: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        year: _selectedYear,
        genre: _selectedGenre != 'All' ? _selectedGenre : null,
        verifiedRightsOnly: _verifiedOnly,
        reset: true,
      );
      final results = pageResult.movies;

      if (!mounted) return;

      if (results.isNotEmpty) {
        setState(() {
          _movies = results;
          _isLoading = false;
          _hasMore = pageResult.hasMore;
        });
        return;
      }

      // If empty and not actively searching with custom query/filter, fall back to curated test candidates
      if (_searchController.text.trim().isEmpty &&
          _selectedYear == null &&
          _selectedGenre == 'All') {
        final candidates = await _service.getCuratedTestCandidates();
        if (!mounted) return;
        setState(() {
          _movies = _verifiedOnly
              ? candidates.where((m) => m.rightsInfo.isCommercialReady).toList()
              : candidates;
          _isLoading = false;
          _hasMore = false;
        });
      } else {
        setState(() {
          _movies = [];
          _isLoading = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // In offline / test mocked environment, fall back to curated test candidates
      if (_searchController.text.trim().isEmpty &&
          _selectedYear == null &&
          _selectedGenre == 'All') {
        try {
          final candidates = await _service.getCuratedTestCandidates();
          if (!mounted) return;
          setState(() {
            _movies = _verifiedOnly
                ? candidates.where((m) => m.rightsInfo.isCommercialReady).toList()
                : candidates;
            _isLoading = false;
            _hasMore = false;
          });
          return;
        } catch (_) {}
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load Internet Archive movies: $e';
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final pageResult = await _service.fetchPlayableCatalogPage(
        rows: 20,
        query: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        year: _selectedYear,
        genre: _selectedGenre != 'All' ? _selectedGenre : null,
        verifiedRightsOnly: _verifiedOnly,
      );

      if (!mounted) return;

      final existingIds = _movies.map((m) => m.identifier).toSet();
      final uniqueNew = pageResult.movies
          .where((m) => !existingIds.contains(m.identifier))
          .toList();

      setState(() {
        _isLoadingMore = false;
        _hasMore = pageResult.hasMore && uniqueNew.isNotEmpty;
        if (uniqueNew.isNotEmpty) {
          _movies = [..._movies, ...uniqueNew];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load more movies: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _performSearch(String query) async {
    _hasMore = true;
    _loadInitialCandidates();
  }

  Future<void> _playMovie(InternetArchiveMovie movie) async {
    // Check rights first
    if (!movie.rightsInfo.isCommercialReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Streaming is prohibited for items with unverified rights.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    var primaryVideo = movie.primaryPlayableVideo;

    // If metadata was incomplete, fetch full item metadata first
    if (primaryVideo == null) {
      setState(() => _isLoading = true);
      try {
        final fullMovie = await _service.getItemMetadata(movie.identifier);
        primaryVideo = fullMovie.primaryPlayableVideo;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not retrieve video files: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    }

    if (primaryVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No direct MP4/H.264 video file found for streaming.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _activeMovie = movie;
      _activeVideoUrl = primaryVideo?.downloadUrl;
    });
  }

  Future<void> _openArchiveUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Widget _buildRightsChip(ArchiveRightsInfo rights) {
    Color bg;
    Color fg;
    IconData icon;

    switch (rights.category) {
      case ArchiveRightsCategory.publicDomain:
        bg = const Color(0xFF1E3A1E);
        fg = const Color(0xFF4CAF50);
        icon = Icons.verified_user_rounded;
        break;
      case ArchiveRightsCategory.creativeCommons:
        bg = const Color(0xFF1E2E3E);
        fg = const Color(0xFF64B5F6);
        icon = Icons.copyright_rounded;
        break;
      case ArchiveRightsCategory.unclearOrRestricted:
        bg = const Color(0xFF3E1E1E);
        fg = const Color(0xFFEF5350);
        icon = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rights.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Internet Archive Playback',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            key: const Key('archive-refresh-button'),
            icon: const Icon(Icons.refresh, color: _yellow),
            onPressed: () => _loadInitialCandidates(isRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Active Video Player if selected
          if (_activeVideoUrl != null && _activeMovie != null)
            ArchiveVideoPlayer(
              key: ValueKey(_activeVideoUrl),
              videoUrl: _activeVideoUrl!,
              title: _activeMovie!.title,
              onClose: () {
                setState(() {
                  _activeMovie = null;
                  _activeVideoUrl = null;
                });
              },
            ),

          // Search and Filters Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: const Color(0xFF181818),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search TextField
                TextField(
                  key: const Key('archive-search-field'),
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _performSearch,
                  decoration: InputDecoration(
                    hintText: 'Search archive.org movies (e.g. Chaplin, Horror)...',
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: _yellow),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54),
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward, color: _yellow),
                            onPressed: () => _performSearch(_searchController.text),
                          ),
                    filled: true,
                    fillColor: const Color(0xFF252626),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
                const SizedBox(height: 8),

                // Rights & Genre Filter Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      FilterChip(
                        key: const Key('archive-verified-filter-chip'),
                        selected: _verifiedOnly,
                        label: const Text('Verified Rights Only'),
                        labelStyle: TextStyle(
                          color: _verifiedOnly ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        selectedColor: _yellow,
                        backgroundColor: const Color(0xFF252626),
                        checkmarkColor: Colors.black,
                        onSelected: (val) {
                          setState(() {
                            _verifiedOnly = val;
                          });
                          _loadInitialCandidates();
                        },
                      ),
                      const SizedBox(width: 8),

                      // Era / Year Filter
                      ..._availableEras.map((era) {
                        final isSelected = era == 'All Eras'
                            ? _selectedYear == null
                            : _selectedYear == int.tryParse(era);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: Key('archive-era-chip-$era'),
                            selected: isSelected,
                            label: Text(era),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontSize: 11,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            selectedColor: _yellow,
                            backgroundColor: const Color(0xFF252626),
                            onSelected: (selected) {
                              setState(() {
                                _selectedYear = (selected && era != 'All Eras')
                                    ? int.tryParse(era)
                                    : null;
                              });
                              _loadInitialCandidates();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Genres Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _availableGenres.map((genre) {
                      final isSelected = _selectedGenre == genre;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('archive-genre-chip-$genre'),
                          selected: isSelected,
                          label: Text(genre),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          selectedColor: _yellow,
                          backgroundColor: const Color(0xFF252626),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedGenre = genre;
                              });
                              _loadInitialCandidates();
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Content list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _yellow),
                        SizedBox(height: 14),
                        Text(
                          'Checking streams and rights...',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () =>
                                  _loadInitialCandidates(isRefresh: true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _yellow,
                                foregroundColor: Colors.black,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _movies.isEmpty
                        ? Center(
                            key: const Key('archive-empty-state'),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search_off_rounded,
                                      color: Colors.white38, size: 54),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No movies found matching criteria.',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 16),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    key: const Key('archive-reset-filters-button'),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _selectedGenre = 'All';
                                        _selectedYear = null;
                                        _verifiedOnly = false;
                                      });
                                      _loadInitialCandidates();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _yellow,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('Reset Filters'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _movies.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              if (index >= _movies.length) {
                                return Center(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 16),
                                    child: _isLoadingMore
                                        ? const SizedBox(
                                            key: Key(
                                                'archive-loading-more-indicator'),
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              color: _yellow,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : ElevatedButton.icon(
                                            key: const Key(
                                                'archive-load-more-button'),
                                            onPressed: _loadNextPage,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF252626),
                                              foregroundColor: _yellow,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            icon: const Icon(Icons.expand_more),
                                            label: const Text(
                                              'Load More Movies',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                  ),
                                );
                              }

                              final movie = _movies[index];
                              final isPlayable = movie.canStream;
                              final unavailableLabel =
                                  movie.rightsInfo.isCommercialReady
                                      ? 'Stream Unavailable'
                                      : 'Rights Unclear';

                              return Card(
                                key: Key('archive-movie-card-${movie.identifier}'),
                                color: const Color(0xFF202020),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Poster / Thumbnail
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 90,
                                          height: 130,
                                          child: movie.thumbnailUrl != null
                                              ? Image.network(
                                                  movie.thumbnailUrl!,
                                                  fit: BoxFit.cover,
                                                  loadingBuilder: (context,
                                                      child, progress) {
                                                    if (progress == null) {
                                                      return child;
                                                    }
                                                    return const ColoredBox(
                                                      color: Color(0xFF2E2E2E),
                                                      child: Center(
                                                        child: SizedBox(
                                                          width: 22,
                                                          height: 22,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: _yellow,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  errorBuilder: (context,
                                                          error, stackTrace) =>
                                                      const ColoredBox(
                                                    color: Color(0xFF2E2E2E),
                                                    child: Center(
                                                      child: Icon(
                                                        Icons
                                                            .movie_creation_outlined,
                                                        color: Colors.white38,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : const ColoredBox(
                                                  color: Color(0xFF2E2E2E),
                                                  child: Center(
                                                    child: Icon(
                                                      Icons
                                                          .movie_creation_outlined,
                                                      color: Colors.white38,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Movie metadata and actions
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              movie.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                if (movie.year != null)
                                                  '${movie.year}',
                                                if (movie.runtimeFormatted !=
                                                    null)
                                                  movie.runtimeFormatted!,
                                                if (movie.creator != null)
                                                  'Directed by ${movie.creator}',
                                              ].join(' • '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // Rights status chip
                                            _buildRightsChip(movie.rightsInfo),
                                            const SizedBox(height: 10),

                                            // Action Buttons in Wrap
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                ElevatedButton.icon(
                                                  key: Key(
                                                      'play-archive-button-${movie.identifier}'),
                                                  onPressed: isPlayable
                                                      ? () => _playMovie(movie)
                                                      : null,
                                                  style: ElevatedButton
                                                      .styleFrom(
                                                    backgroundColor: _yellow,
                                                    foregroundColor:
                                                        Colors.black,
                                                    disabledBackgroundColor:
                                                        Colors.white12,
                                                    disabledForegroundColor:
                                                        Colors.white24,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 14,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.play_arrow,
                                                      size: 18),
                                                  label: Text(
                                                    isPlayable
                                                        ? 'Play Movie'
                                                        : unavailableLabel,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  key: Key(
                                                      'open-item-page-${movie.identifier}'),
                                                  onPressed: () =>
                                                      _openArchiveUrl(
                                                          movie.itemPageUrl),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.white60,
                                                    visualDensity: VisualDensity
                                                        .compact,
                                                  ),
                                                  icon: const Icon(
                                                      Icons.open_in_new,
                                                      size: 14),
                                                  label: const Text(
                                                    'Archive Page',
                                                    style:
                                                        TextStyle(fontSize: 11),
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
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
