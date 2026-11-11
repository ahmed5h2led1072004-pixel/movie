import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/movie.dart';
import '../widgets/app_bottom_navigation_bar.dart';
import '../widgets/user_avatar.dart';
import 'edit_profile_screen.dart';
import 'movie_details_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.auth,
    this.firestore,
    this.storage,
    this.imagePicker,
    this.initialUserData,
    this.watchlistCount,
    this.historyCount,
    this.favoritesCount,
    this.watchlistStream,
    this.historyStream,
    this.favoritesStream,
    this.initialSection = 0,
  });

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;
  final ImagePicker? imagePicker;
  final Map<String, dynamic>? initialUserData;
  final int? watchlistCount;
  final int? historyCount;
  final int? favoritesCount;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? watchlistStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? historyStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? favoritesStream;
  final int initialSection;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _yellow = Color(0xFFFFC400);
  static const double _headerHeight = 345.0;

  final ScrollController _scrollController = ScrollController();

  String _name = 'Loading...';
  String _email = '';
  String _phone = '';
  String _avatarAsset = 'assets/avatars/avatar_hoodie.jpg';

  late int _selectedSection = widget.initialSection;

  bool _isLoading = true;
  bool _isLoggingOut = false;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _watchlistStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _historyStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _favoritesStream;

  @override
  void initState() {
    super.initState();

    if (widget.initialUserData != null) {
      final data = widget.initialUserData!;
      _name = data['name']?.toString() ?? 'User';
      _email = data['email']?.toString() ?? '';
      _phone = data['phone']?.toString() ?? '';
      _avatarAsset =
          data['avatar']?.toString() ?? 'assets/avatars/avatar_hoodie.jpg';
      _isLoading = false;
    }

    _watchlistStream = widget.watchlistStream;
    _historyStream = widget.historyStream;
    _favoritesStream = widget.favoritesStream;

    User? user;
    if (widget.auth != null) {
      user = widget.auth!.currentUser;
    } else if (widget.initialUserData == null) {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        user = null;
      }
    }

    if (user != null) {
      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }

      if (firestore != null) {
        final userReference = firestore.collection('users').doc(user.uid);

        _watchlistStream ??= userReference.collection('watchlist').snapshots();

        _historyStream ??= userReference
            .collection('recently_watched')
            .orderBy('watchedAt', descending: true)
            .snapshots();

        _favoritesStream ??= userReference.collection('favorites').snapshots();
      }
    }

    if (widget.initialUserData == null) {
      _loadUserData();
    }
  }

  // Load user profile data
  Future<void> _loadUserData() async {
    try {
      User? user;
      if (widget.auth != null) {
        user = widget.auth!.currentUser;
      } else {
        try {
          user = FirebaseAuth.instance.currentUser;
        } catch (_) {
          user = null;
        }
      }

      if (user == null) {
        if (!mounted) return;

        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);

        return;
      }

      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }

      if (firestore == null) {
        if (!mounted) return;
        setState(() {
          _name = user?.displayName ?? 'User';
          _email = user?.email ?? '';
          _isLoading = false;
        });
        return;
      }

      final document =
          await firestore.collection('users').doc(user.uid).get();

      final data = document.data();

      if (!mounted) return;

      setState(() {
        _name = data?['name']?.toString() ?? user?.displayName ?? 'User';
        _email = data?['email']?.toString() ?? user?.email ?? '';
        _phone = data?['phone']?.toString() ?? '';
        _avatarAsset =
            data?['avatar']?.toString() ?? 'assets/avatars/avatar_hoodie.jpg';

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      final auth = widget.auth ?? FirebaseAuth.instance;
      setState(() {
        _name = auth.currentUser?.displayName ?? 'User';
        _email = auth.currentUser?.email ?? '';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load profile data.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Bottom navigation
  void _selectTab(int index) {
    const Map<int, String> routes = {0: '/home', 1: '/search', 2: '/browse'};

    final route = routes[index];

    if (route != null) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  // Profile sections
  void _selectSection(int section) {
    setState(() {
      _selectedSection = section;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        section == 0 ? 0 : _headerHeight,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // Edit profile
  Future<void> _editProfile() async {
    final result = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute<ProfileEditResult>(
        builder: (_) => EditProfileScreen(
          initialName: _name,
          initialPhone: _phone,
          initialAvatar: _avatarAsset,
          auth: widget.auth,
          firestore: widget.firestore,
          storage: widget.storage,
          imagePicker: widget.imagePicker,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _name = result.name;
      _phone = result.phone;
      _avatarAsset = result.avatarAsset;
    });

    unawaited(_loadUserData());
  }

  // Logout with confirmation
  Future<void> _logout() async {
    if (_isLoggingOut) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your account?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            key: const Key('logout-cancel-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            key: const Key('logout-confirm-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF2428),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      if (widget.auth != null) {
        await widget.auth!.signOut();
      } else {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }

      if (!mounted) return;

      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoggingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log out. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Confirmation dialog for removing a movie from a collection
  Future<bool> _confirmRemove({
    required String movieTitle,
    required String collectionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove from $collectionLabel?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "$movieTitle" from your $collectionLabel?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            key: const Key('remove-cancel-button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            key: const Key('remove-confirm-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF2428),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // Remove movie from Watch List
  Future<void> _removeFromWatchlist(String movieId, [String? movieTitle]) async {
    final confirmed = await _confirmRemove(
      movieTitle: movieTitle ?? 'this movie',
      collectionLabel: 'Watch List',
    );
    if (!confirmed || !mounted) return;

    User? user;
    if (widget.auth != null) {
      user = widget.auth!.currentUser;
    } else {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        user = null;
      }
    }

    if (user == null) return;

    try {
      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }
      if (firestore == null) return;

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('watchlist')
          .doc(movieId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movie removed from Watch List'),
          backgroundColor: Color(0xFF292929),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase error: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove movie. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Remove movie from Favorites
  Future<void> _removeFromFavorites(String movieId, [String? movieTitle]) async {
    final confirmed = await _confirmRemove(
      movieTitle: movieTitle ?? 'this movie',
      collectionLabel: 'Favorites',
    );
    if (!confirmed || !mounted) return;

    User? user;
    if (widget.auth != null) {
      user = widget.auth!.currentUser;
    } else {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        user = null;
      }
    }

    if (user == null) return;

    try {
      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }
      if (firestore == null) return;

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .doc(movieId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movie removed from Favorites'),
          backgroundColor: Color(0xFF292929),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase error: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove movie. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Remove movie from History
  Future<void> _removeFromHistory(String movieId, [String? movieTitle]) async {
    final confirmed = await _confirmRemove(
      movieTitle: movieTitle ?? 'this movie',
      collectionLabel: 'History',
    );
    if (!confirmed || !mounted) return;

    User? user;
    if (widget.auth != null) {
      user = widget.auth!.currentUser;
    } else {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {
        user = null;
      }
    }

    if (user == null) return;

    try {
      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }
      if (firestore == null) return;

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('recently_watched')
          .doc(movieId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movie removed from History'),
          backgroundColor: Color(0xFF292929),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase error: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove movie. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Open movie details
  void _openMovieDetails(Movie movie) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MovieDetailsScreen(
        movie: movie,
        auth: widget.auth,
        firestore: widget.firestore,
      ),
    ));
  }

  // Shared movie grid builder
  Widget _buildMovieGrid({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> movies,
    required String emptyMessage,
    String emptySubtitle = '',
    required bool showRemoveButton,
    required Future<void> Function(String movieId, String movieTitle)? onRemove,
  }) {
    if (movies.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image(
                  image: const AssetImage('assets/search/empty_search.png'),
                  width: 125,
                  height: 135,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.movie_outlined,
                      size: 64,
                      color: Colors.white24,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (emptySubtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    emptySubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      sliver: SliverGrid.builder(
        itemCount: movies.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.678,
        ),
        itemBuilder: (context, index) {
          final document = movies[index];
          final movie = document.data();

          final String poster = movie['poster']?.toString() ?? '';
          final String title = movie['title']?.toString() ?? 'Unknown Movie';
          final selectedMovie =
              Movie.fromFirestore(movie, documentId: document.id);

          return GestureDetector(
            onTap: () => _openMovieDetails(selectedMovie),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster.isNotEmpty)
                    Image(
                      image: poster.startsWith('http')
                          ? NetworkImage(poster)
                          : AssetImage(poster),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFF292929),
                          child: Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: Colors.white54,
                              size: 40,
                            ),
                          ),
                        );
                      },
                    )
                  else
                    const ColoredBox(
                      color: Color(0xFF292929),
                      child: Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: Colors.white54,
                          size: 40,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 5,
                    right: 5,
                    bottom: 5,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                      ),
                    ),
                  ),
                  if (showRemoveButton && onRemove != null)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: GestureDetector(
                        key: Key('remove-movie-button-${document.id}'),
                        onTap: () => onRemove(document.id, title),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            emptyMessage == 'Favorites are empty.'
                                ? Icons.favorite
                                : Icons.close_rounded,
                            color: emptyMessage == 'Favorites are empty.'
                                ? Colors.red
                                : Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Watch List content
  Widget _buildWatchlistContent(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'Could not load Watch List.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator(color: _yellow)),
      );
    }

    final movies = snapshot.data?.docs ?? [];

    return _buildMovieGrid(
      movies: movies,
      emptyMessage: 'Watch List is empty.',
      emptySubtitle: 'Save movies you want to watch later.',
      showRemoveButton: true,
      onRemove: _removeFromWatchlist,
    );
  }

  // Recently Watched content
  Widget _buildHistoryContent(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'Could not load History.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator(color: _yellow)),
      );
    }

    final movies = snapshot.data?.docs ?? [];

    return _buildMovieGrid(
      movies: movies,
      emptyMessage: 'History is empty.',
      emptySubtitle: 'Movies you open will appear here.',
      showRemoveButton: true,
      onRemove: _removeFromHistory,
    );
  }

  // Favorites content
  Widget _buildFavoritesContent(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'Could not load Favorites.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator(color: _yellow)),
      );
    }

    final movies = snapshot.data?.docs ?? [];

    return _buildMovieGrid(
      movies: movies,
      emptyMessage: 'Favorites are empty.',
      emptySubtitle: 'Mark your favorite movies to find them quickly.',
      showRemoveButton: true,
      onRemove: _removeFromFavorites,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF101111),
        body: Center(child: CircularProgressIndicator(color: _yellow)),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watchlistStream,
      builder: (context, watchlistSnapshot) {
        final int watchlistCount =
            widget.watchlistCount ?? watchlistSnapshot.data?.docs.length ?? 0;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _historyStream,
          builder: (context, historySnapshot) {
            final int historyCount =
                widget.historyCount ?? historySnapshot.data?.docs.length ?? 0;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _favoritesStream,
              builder: (context, favoritesSnapshot) {
                final int favoritesCount = widget.favoritesCount ??
                    favoritesSnapshot.data?.docs.length ??
                    0;

                return Scaffold(
                  backgroundColor: const Color(0xFF101111),
                  body: SafeArea(
                    top: false,
                    bottom: false,
                    child: Stack(
                      children: [
                        CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildProfileHeader(
                                watchlistCount,
                                historyCount,
                                favoritesCount,
                              ),
                            ),
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _ProfileTabsDelegate(
                                selectedSection: _selectedSection,
                                onSelect: _selectSection,
                              ),
                            ),
                            if (_selectedSection == 0)
                              _buildWatchlistContent(watchlistSnapshot)
                            else if (_selectedSection == 1)
                              _buildHistoryContent(historySnapshot)
                            else
                              _buildFavoritesContent(favoritesSnapshot),
                          ],
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: safeBottom + 8,
                          child: AppBottomNavigationBar(
                            selectedIndex: 3,
                            onSelected: _selectTab,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Profile header
  Widget _buildProfileHeader(
    int watchlistCount,
    int historyCount,
    int favoritesCount,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: _headerHeight),
      width: double.infinity,
      color: const Color(0xFF202020),
      child: Padding(
        padding: const EdgeInsets.only(top: 48, bottom: 12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  GestureDetector(
                    key: const Key('profile-avatar-trigger'),
                    onTap: _editProfile,
                    child: UserAvatar(
                      avatar: _avatarAsset,
                      size: 118,
                      borderColor: _yellow,
                      borderWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: _ProfileCount(
                            key: const Key('watchlist-count'),
                            value: watchlistCount.toString(),
                            label: 'Wish List',
                          ),
                        ),
                        Expanded(
                          child: _ProfileCount(
                            key: const Key('history-count'),
                            value: historyCount.toString(),
                            label: 'History',
                          ),
                        ),
                        Expanded(
                          child: _ProfileCount(
                            key: const Key('favorites-count'),
                            value: favoritesCount.toString(),
                            label: 'Favorites',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 27),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      key: const Key('profile-name-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _email,
                      key: const Key('profile-email-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    if (_phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        key: const Key('profile-phone-row'),
                        children: [
                          const Icon(
                            Icons.call,
                            size: 14,
                            color: _yellow,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _phone,
                            key: const Key('profile-phone-text'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 65,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        key: const Key('profile-edit-button'),
                        onPressed: _editProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _yellow,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 35,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        key: const Key('profile-exit-button'),
                        onPressed: _isLoggingOut ? null : _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF2428),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoggingOut
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Exit',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.logout_rounded, size: 20),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Profile tabs delegate
class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsDelegate({
    required this.selectedSection,
    required this.onSelect,
  });

  final int selectedSection;
  final ValueChanged<int> onSelect;

  @override
  double get minExtent => 96;

  @override
  double get maxExtent => 96;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFF202020),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _ProfileTab(
                  key: const Key('profile-tab-watchlist'),
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'Watch List',
                  onTap: () => onSelect(0),
                ),
                _ProfileTab(
                  key: const Key('profile-tab-history'),
                  icon: Icons.folder_rounded,
                  label: 'History',
                  onTap: () => onSelect(1),
                ),
                _ProfileTab(
                  key: const Key('profile-tab-favorites'),
                  icon: Icons.favorite_rounded,
                  label: 'Favorites',
                  onTap: () => onSelect(2),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 3,
            child: Row(
              children: [
                for (int i = 0; i < 3; i++)
                  Expanded(
                    child: ColoredBox(
                      color: selectedSection == i
                          ? const Color(0xFFFFC400)
                          : Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) {
    return oldDelegate.selectedSection != selectedSection;
  }
}

// Profile count
class _ProfileCount extends StatelessWidget {
  const _ProfileCount({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Profile tab
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFFC400), size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
