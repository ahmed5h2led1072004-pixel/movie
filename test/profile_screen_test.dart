import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movies/models/user_profile.dart';
import 'package:movies/screens/edit_profile_screen.dart';
import 'package:movies/screens/profile_screen.dart';
import 'package:movies/widgets/user_avatar.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'test-uid-123';

  @override
  String? get displayName => 'Test User';

  @override
  String? get email => 'test@example.com';

  @override
  Future<void> updateDisplayName(String? name) async {}

  @override
  Future<void> updatePhotoURL(String? photoURL) async {}
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  _FakeFirebaseAuth({User? user}) : currentUser = user ?? _FakeUser();

  @override
  User? currentUser;

  bool signedOut = false;

  @override
  Future<void> signOut() async {
    signedOut = true;
    currentUser = null;
  }
}

class _FakeImagePicker extends Fake implements ImagePicker {
  bool pickImageCalled = false;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pickImageCalled = true;
    return XFile('assets/avatars/avatar_option_5.jpg');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfile Model Tests', () {
    test('creates UserProfile from Firestore data map', () {
      final profile = UserProfile.fromFirestore(
        {
          'name': 'Sarah Connor',
          'email': 'sarah@resistance.org',
          'phone': '+1234567890',
          'avatar': 'https://storage.googleapis.com/avatar.jpg',
        },
        uid: 'uid-456',
      );

      expect(profile.uid, 'uid-456');
      expect(profile.name, 'Sarah Connor');
      expect(profile.email, 'sarah@resistance.org');
      expect(profile.phone, '+1234567890');
      expect(profile.avatar, 'https://storage.googleapis.com/avatar.jpg');

      final map = profile.toFirestore();
      expect(map['name'], 'Sarah Connor');
      expect(map['phone'], '+1234567890');
      expect(map['avatar'], 'https://storage.googleapis.com/avatar.jpg');
    });

    test('UserProfile handles null/missing fields with safe defaults', () {
      final profile = UserProfile.fromFirestore(
        null,
        uid: 'uid-789',
        fallbackName: 'Default Hero',
        fallbackEmail: 'hero@default.com',
      );

      expect(profile.uid, 'uid-789');
      expect(profile.name, 'Default Hero');
      expect(profile.email, 'hero@default.com');
      expect(profile.phone, '');
      expect(profile.avatar, 'assets/avatars/avatar_hoodie.jpg');
    });
  });

  group('UserAvatar Widget Tests', () {
    testWidgets('renders fallback icon when avatar path is empty or invalid', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(avatar: '', size: 100),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('renders asset image when avatar starts with assets/', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatar: 'assets/avatars/avatar_hoodie.jpg',
              size: 100,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders network image loading/structure when url is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatar: 'https://example.com/avatar.jpg',
              size: 100,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('ProfileScreen User Information & Statistics Tests', () {
    testWidgets('displays user name, email, and phone number when available', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Bruce Wayne',
              'email': 'bruce@wayne-enterprises.com',
              'phone': '+1 555-0199',
              'avatar': 'assets/avatars/avatar_sunglasses.jpg',
            },
            watchlistCount: 3,
            historyCount: 7,
            favoritesCount: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bruce Wayne'), findsOneWidget);
      expect(find.text('bruce@wayne-enterprises.com'), findsOneWidget);
      expect(find.text('+1 555-0199'), findsOneWidget);
      expect(find.byIcon(Icons.call), findsOneWidget);
    });

    testWidgets('hides phone row when phone number is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Clark Kent',
              'email': 'clark@dailyplanet.com',
              'phone': '',
              'avatar': 'assets/avatars/avatar_hoodie.jpg',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clark Kent'), findsOneWidget);
      expect(find.text('clark@dailyplanet.com'), findsOneWidget);
      expect(find.byKey(const Key('profile-phone-row')), findsNothing);
    });

    testWidgets('displays statistics counts correctly', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(
            initialUserData: {
              'name': 'Tony Stark',
              'email': 'tony@stark.com',
              'phone': '123456789',
              'avatar': 'assets/avatars/avatar_beard.jpg',
            },
            watchlistCount: 5,
            historyCount: 12,
            favoritesCount: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.byKey(const Key('watchlist-count')), findsOneWidget);
      expect(find.byKey(const Key('history-count')), findsOneWidget);
      expect(find.byKey(const Key('favorites-count')), findsOneWidget);
    });
  });

  group('Logout Confirmation and Navigation Tests', () {
    testWidgets('tapping Exit shows confirmation dialog; Cancel dismisses it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeAuth = _FakeFirebaseAuth();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            auth: fakeAuth,
            initialUserData: const {
              'name': 'Natasha Romanoff',
              'email': 'natasha@avengers.org',
              'phone': '555-1234',
              'avatar': 'assets/avatars/avatar_option_1.jpg',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile-exit-button')));
      await tester.pumpAndSettle();

      expect(find.text('Log Out'), findsWidgets);
      expect(
        find.text('Are you sure you want to log out of your account?'),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.byKey(const Key('logout-cancel-button')));
      await tester.pumpAndSettle();

      expect(fakeAuth.signedOut, isFalse);
      expect(find.text('Are you sure you want to log out of your account?'), findsNothing);
    });

    testWidgets('confirming Log Out calls signOut and navigates to /login', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeAuth = _FakeFirebaseAuth();
      bool navigatedToLogin = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            auth: fakeAuth,
            initialUserData: const {
              'name': 'Steve Rogers',
              'email': 'steve@shield.gov',
              'phone': '1941-cap',
              'avatar': 'assets/avatars/avatar_option_2.jpg',
            },
            watchlistCount: 0,
            historyCount: 0,
            favoritesCount: 0,
          ),
          onGenerateRoute: (settings) {
            if (settings.name == '/login') {
              navigatedToLogin = true;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Login Screen Mock')),
              );
            }
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile-exit-button')));
      await tester.pumpAndSettle();

      // Tap Log Out in dialog
      await tester.tap(find.byKey(const Key('logout-confirm-button')));
      await tester.pumpAndSettle();

      expect(fakeAuth.signedOut, isTrue);
      expect(navigatedToLogin, isTrue);
      expect(find.text('Login Screen Mock'), findsOneWidget);
    });
  });

  group('EditProfileScreen Validation and Save Tests', () {
    testWidgets('displays validation error if name is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: EditProfileScreen(
            initialName: 'Thor Odinson',
            initialPhone: '123456789',
            initialAvatar: 'assets/avatars/avatar_option_3.jpg',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clear name
      await tester.enterText(find.byKey(const Key('edit-name-field')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('update-data-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your name'), findsOneWidget);
    });

    testWidgets('displays validation error if phone is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: EditProfileScreen(
            initialName: 'Thor Odinson',
            initialPhone: '123456789',
            initialAvatar: 'assets/avatars/avatar_option_3.jpg',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clear phone
      await tester.enterText(find.byKey(const Key('edit-phone-field')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('update-data-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your phone number'), findsOneWidget);
    });

    testWidgets('selecting an avatar from presets updates preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: EditProfileScreen(
            initialName: 'Peter Parker',
            initialPhone: '555-0100',
            initialAvatar: 'assets/avatars/avatar_option_1.jpg',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open avatar picker
      await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Change Profile Photo'), findsOneWidget);
      expect(find.byKey(const Key('pick-from-gallery-button')), findsOneWidget);

      // Select preset option 0
      await tester.tap(find.byKey(const Key('avatar-option-0')));
      await tester.pumpAndSettle();

      // Sheet is closed and screen updated
      expect(find.text('Change Profile Photo'), findsNothing);
    });

    testWidgets('picking from gallery invokes ImagePicker', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePicker = _FakeImagePicker();

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            initialName: 'Peter Parker',
            initialPhone: '555-0100',
            initialAvatar: 'assets/avatars/avatar_option_1.jpg',
            imagePicker: fakePicker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pick-from-gallery-button')));
      await tester.pumpAndSettle();

      expect(fakePicker.pickImageCalled, isTrue);
    });

    testWidgets('successful save returns updated data and shows feedback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? savedName;
      String? savedPhone;
      String? savedAvatar;

      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            initialName: 'Bruce Banner',
            initialPhone: '111-222',
            initialAvatar: 'assets/avatars/avatar_option_1.jpg',
            onSave: (name, phone, avatar, imageFile) async {
              savedName = name;
              savedPhone = phone;
              savedAvatar = avatar;
              return avatar;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit-name-field')),
        'Incredible Hulk',
      );
      await tester.enterText(
        find.byKey(const Key('edit-phone-field')),
        '999-HULK',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('update-data-button')));
      await tester.pumpAndSettle();

      expect(savedName, 'Incredible Hulk');
      expect(savedPhone, '999-HULK');
      expect(savedAvatar, 'assets/avatars/avatar_option_1.jpg');
    });
  });

  group('ProfileScreen Error Handling Tests', () {
    testWidgets('renders fallback without crashing when stream has error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            initialUserData: const {
              'name': 'Wanda Maximoff',
              'email': 'wanda@avengers.org',
              'phone': '12345',
              'avatar': 'assets/avatars/avatar_hoodie.jpg',
            },
            watchlistStream: Stream<QuerySnapshot<Map<String, dynamic>>>.error(
              'Watchlist error',
            ),
            historyStream: Stream<QuerySnapshot<Map<String, dynamic>>>.error(
              'History error',
            ),
            favoritesStream: Stream<QuerySnapshot<Map<String, dynamic>>>.error(
              'Favorites error',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wanda Maximoff'), findsOneWidget);
      expect(find.text('Could not load Watch List.'), findsOneWidget);
    });
  });
}
