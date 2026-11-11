import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movies/screens/edit_profile_screen.dart';
import 'package:movies/screens/profile_screen.dart';
import 'package:movies/widgets/user_avatar.dart';

// ignore_for_file: subtype_of_sealed_class, must_be_immutable

// ---------------------------------------------------------------------------
// Fakes for Firebase Auth
// ---------------------------------------------------------------------------
class _FakeUser extends Fake implements User {
  _FakeUser({
    this.uid = 'user-uid-999',
    this.displayName = 'Original Name',
    this.photoURL = 'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-uid-999%2Fprofile%2Favatar.jpg?alt=media&token=initial-token',
  });

  @override
  final String uid;

  @override
  String? displayName;

  @override
  final String? email = 'tester@movies.com';

  @override
  String? photoURL;

  @override
  Future<void> updateDisplayName(String? name) async {
    displayName = name;
  }

  @override
  Future<void> updatePhotoURL(String? newPhotoURL) async {
    photoURL = newPhotoURL;
  }
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  _FakeFirebaseAuth({User? user}) : currentUser = user ?? _FakeUser();

  @override
  User? currentUser;
}

// ---------------------------------------------------------------------------
// Fakes for Firebase Storage
// ---------------------------------------------------------------------------
class _FakeTaskSnapshot extends Fake implements TaskSnapshot {
  _FakeTaskSnapshot({required this.ref});

  @override
  final Reference ref;

  @override
  final TaskState state = TaskState.success;
}

class _FakeUploadTask extends Fake implements UploadTask {
  _FakeUploadTask({
    required this.snapshot,
    this.shouldThrow,
  });

  @override
  final TaskSnapshot snapshot;
  final Exception? shouldThrow;

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) {
    final Future<TaskSnapshot> future = shouldThrow != null
        ? Future<TaskSnapshot>.error(shouldThrow!)
        : Future<TaskSnapshot>.value(snapshot);
    return future.then(onValue, onError: onError);
  }
}

class _StorageCallRecorder {
  final List<String> operations = [];
  String? uploadedPath;
  File? uploadedFile;
  SettableMetadata? uploadedMetadata;

  void record(String operation) => operations.add(operation);
}

class _FakeStorageReference extends Fake implements Reference {
  _FakeStorageReference({
    this.path = '',
    this.downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-uid-999%2Fprofile%2Favatar.jpg?alt=media&token=new-token-12345',
    this.getDownloadUrlThrows,
    this.putFileThrows,
    this.recorder,
  });

  final String path;
  final String downloadUrl;
  final FirebaseException? getDownloadUrlThrows;
  final FirebaseException? putFileThrows;
  final _StorageCallRecorder? recorder;

  final List<String> childCalls = [];
  File? uploadedFile;
  SettableMetadata? uploadedMetadata;

  @override
  Reference child(String childPath) {
    childCalls.add(childPath);
    final nextPath = path.isEmpty ? childPath : '$path/$childPath';
    return _FakeStorageReference(
      path: nextPath,
      downloadUrl: downloadUrl,
      getDownloadUrlThrows: getDownloadUrlThrows,
      putFileThrows: putFileThrows,
      recorder: recorder,
    );
  }

  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) {
    uploadedFile = file;
    uploadedMetadata = metadata;
    recorder?.record('putFile:$path');
    recorder?.uploadedPath = path;
    recorder?.uploadedFile = file;
    recorder?.uploadedMetadata = metadata;
    final snapshot = _FakeTaskSnapshot(ref: this);
    return _FakeUploadTask(
      snapshot: snapshot,
      shouldThrow: putFileThrows,
    );
  }

  @override
  Future<String> getDownloadURL() async {
    recorder?.record('getDownloadURL:$path');
    if (getDownloadUrlThrows != null) {
      throw getDownloadUrlThrows!;
    }
    return downloadUrl;
  }
}

class _FakeFirebaseStorage extends Fake implements FirebaseStorage {
  _FakeFirebaseStorage({_FakeStorageReference? rootRef})
      : rootReference = rootRef ?? _FakeStorageReference();

  final _FakeStorageReference rootReference;

  @override
  Reference ref([String? path]) {
    if (path != null) {
      return rootReference.child(path);
    }
    return rootReference;
  }
}

// ---------------------------------------------------------------------------
// Fakes for Cloud Firestore
// ---------------------------------------------------------------------------
class _FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference({this.shouldThrow});

  final Exception? shouldThrow;
  Map<String, dynamic>? lastSavedData;
  SetOptions? lastSetOptions;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    lastSavedData = Map<String, dynamic>.from(data);
    lastSetOptions = options;
  }
}

class _FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference({this.docRef});

  final _FakeDocumentReference? docRef;
  String? requestedDocId;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    requestedDocId = path;
    return docRef ?? _FakeDocumentReference();
  }
}

class _FakeFirebaseFirestore extends Fake implements FirebaseFirestore {
  _FakeFirebaseFirestore({this.docRef});

  final _FakeDocumentReference? docRef;
  String? requestedCollection;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    requestedCollection = collectionPath;
    return _FakeCollectionReference(
      docRef: docRef ?? _FakeDocumentReference(),
    );
  }
}

// ---------------------------------------------------------------------------
// Fake Image Picker
// ---------------------------------------------------------------------------
class _FakeImagePickerWithFile extends Fake implements ImagePicker {
  _FakeImagePickerWithFile(this.filePath);

  final String filePath;
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
    return XFile(filePath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleImageFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('movies_profile_test_');
    sampleImageFile = File('${tempDir.path}/test_avatar.jpg');
    sampleImageFile.writeAsBytesSync(List.filled(1024, 0xFF));
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Scenario A: User Changes Profile Picture', () {
    testWidgets(
      'uploads new image to users/{uid}/profile/avatar.jpg, retrieves valid URL, updates Firestore and Auth',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final user = _FakeUser(
          uid: 'user-777',
          displayName: 'Tony Stark',
        );
        final fakeAuth = _FakeFirebaseAuth(user: user);

        final recorder = _StorageCallRecorder();
        final fakeStorageRef = _FakeStorageReference(
          downloadUrl:
              'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-777%2Fprofile%2Favatar.jpg?alt=media&token=valid-token-777',
          recorder: recorder,
        );
        final fakeStorage = _FakeFirebaseStorage(rootRef: fakeStorageRef);

        final docRef = _FakeDocumentReference();
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        final fakePicker = _FakeImagePickerWithFile(sampleImageFile.path);

        ProfileEditResult? poppedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (navContext) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        poppedResult =
                            await Navigator.of(navContext).push<ProfileEditResult>(
                          MaterialPageRoute<ProfileEditResult>(
                            builder: (_) => EditProfileScreen(
                              initialName: 'Tony Stark',
                              initialPhone: '+1-555-0100',
                              initialAvatar:
                                  'assets/avatars/avatar_option_1.jpg',
                              auth: fakeAuth,
                              storage: fakeStorage,
                              firestore: fakeFirestore,
                              imagePicker: fakePicker,
                            ),
                          ),
                        );
                      },
                      child: const Text('Launch Edit'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Launch Edit Screen
        await tester.tap(find.text('Launch Edit'));
        await tester.pumpAndSettle();

        // Open Avatar picker sheet and pick from gallery
        await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pick-from-gallery-button')));
        await tester.pumpAndSettle();

        expect(fakePicker.pickImageCalled, isTrue);

        // Edit name & phone
        await tester.enterText(
          find.byKey(const Key('edit-name-field')),
          'Iron Man Updated',
        );
        await tester.enterText(
          find.byKey(const Key('edit-phone-field')),
          '+1-555-9999',
        );
        await tester.pumpAndSettle();

        // Press Update Data button
        await tester.tap(find.byKey(const Key('update-data-button')));
        await tester.pumpAndSettle();

        // Verify popped result
        expect(poppedResult, isNotNull);
        expect(poppedResult!.name, 'Iron Man Updated');
        expect(poppedResult!.phone, '+1-555-9999');
        expect(
          poppedResult!.avatarAsset,
          'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-777%2Fprofile%2Favatar.jpg?alt=media&token=valid-token-777',
        );

        // Verify Firestore update
        expect(docRef.lastSavedData, isNotNull);
        expect(docRef.lastSavedData!['name'], 'Iron Man Updated');
        expect(docRef.lastSavedData!['phone'], '+1-555-9999');
        expect(
          docRef.lastSavedData!['avatar'],
          'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-777%2Fprofile%2Favatar.jpg?alt=media&token=valid-token-777',
        );

        // Verify Firebase Auth updates
        expect(user.displayName, 'Iron Man Updated');
        expect(
          user.photoURL,
          'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-777%2Fprofile%2Favatar.jpg?alt=media&token=valid-token-777',
        );

        // Verify the exact per-user storage path and upload metadata
        expect(recorder.uploadedPath, 'users/user-777/profile/avatar.jpg');
        expect(recorder.uploadedFile, isNotNull);
        expect(recorder.uploadedMetadata?.contentType, 'image/jpeg');
        expect(
          recorder.uploadedMetadata?.customMetadata?['userId'],
          'user-777',
        );

        // Verify the URL is read from the same reference used for upload,
        // without an extra Storage existence/metadata check.
        expect(recorder.operations, [
          'putFile:users/user-777/profile/avatar.jpg',
          'getDownloadURL:users/user-777/profile/avatar.jpg',
        ]);
      },
    );
  });

  group('Scenario B: User Updates Information Without Changing Picture', () {
    testWidgets(
      'preserves existing profile image URL, updates name/phone, does not attempt Storage upload',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const existingAvatarUrl =
            'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-888%2Fprofile%2Favatar.jpg?alt=media&token=existing-token';

        final user = _FakeUser(
          uid: 'user-888',
          displayName: 'Peter Parker',
          photoURL: existingAvatarUrl,
        );
        final fakeAuth = _FakeFirebaseAuth(user: user);

        final fakeStorageRef = _FakeStorageReference();
        final fakeStorage = _FakeFirebaseStorage(rootRef: fakeStorageRef);

        final docRef = _FakeDocumentReference();
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        ProfileEditResult? poppedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (navContext) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        poppedResult =
                            await Navigator.of(navContext).push<ProfileEditResult>(
                          MaterialPageRoute<ProfileEditResult>(
                            builder: (_) => EditProfileScreen(
                              initialName: 'Peter Parker',
                              initialPhone: '+1-555-0100',
                              initialAvatar: existingAvatarUrl,
                              auth: fakeAuth,
                              storage: fakeStorage,
                              firestore: fakeFirestore,
                            ),
                          ),
                        );
                      },
                      child: const Text('Launch Edit'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Launch Edit'));
        await tester.pumpAndSettle();

        // Update name and phone only (DO NOT change photo)
        await tester.enterText(
          find.byKey(const Key('edit-name-field')),
          'Spider-Man',
        );
        await tester.enterText(
          find.byKey(const Key('edit-phone-field')),
          '+1-555-4321',
        );
        await tester.pumpAndSettle();

        // Press Update Data
        await tester.tap(find.byKey(const Key('update-data-button')));
        await tester.pumpAndSettle();

        // Verify popped result preserves existing avatar URL
        expect(poppedResult, isNotNull);
        expect(poppedResult!.name, 'Spider-Man');
        expect(poppedResult!.phone, '+1-555-4321');
        expect(poppedResult!.avatarAsset, existingAvatarUrl);

        // Verify Firestore update preserves existing avatar URL and did not overwrite with null or empty
        expect(docRef.lastSavedData, isNotNull);
        expect(docRef.lastSavedData!['name'], 'Spider-Man');
        expect(docRef.lastSavedData!['phone'], '+1-555-4321');
        expect(docRef.lastSavedData!['avatar'], existingAvatarUrl);

        // Verify Storage was never invoked
        expect(fakeStorageRef.uploadedFile, isNull);
        expect(fakeStorageRef.childCalls, isEmpty);
      },
    );
  });

  group('Error Handling and Data Protection Tests', () {
    testWidgets(
      'keeps the selected image and old profile data when the download URL cannot be retrieved',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialAvatar = 'assets/avatars/avatar_option_1.jpg';
        const existingPhotoUrl =
            'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-err-1%2Fprofile%2Favatar.jpg?alt=media&token=old-token';

        final user = _FakeUser(
          uid: 'user-err-1',
          photoURL: existingPhotoUrl,
        );
        final fakeAuth = _FakeFirebaseAuth(user: user);

        // The upload completes, but the URL lookup returns object-not-found.
        final recorder = _StorageCallRecorder();
        final fakeStorageRef = _FakeStorageReference(
          getDownloadUrlThrows: FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
            message: 'No object exists at the desired reference.',
          ),
          recorder: recorder,
        );
        final fakeStorage = _FakeFirebaseStorage(rootRef: fakeStorageRef);

        final docRef = _FakeDocumentReference();
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        final fakePicker = _FakeImagePickerWithFile(sampleImageFile.path);

        await tester.pumpWidget(
          MaterialApp(
            home: EditProfileScreen(
              initialName: 'Doctor Strange',
              initialPhone: '+1-555-7777',
              initialAvatar: initialAvatar,
              auth: fakeAuth,
              storage: fakeStorage,
              firestore: fakeFirestore,
              imagePicker: fakePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pick photo
        await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pick-from-gallery-button')));
        await tester.pumpAndSettle();

        // Tap Update Data
        await tester.tap(find.byKey(const Key('update-data-button')));
        await tester.pumpAndSettle();

        // Verify a meaningful error that does not ask the user to reselect
        expect(
          find.text(
            'Failed to update profile: The uploaded image could not be confirmed in Firebase Storage. Please tap Update Data to try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('select your picture again'), findsNothing);

        // Upload was attempted and no metadata lookup was made
        expect(recorder.operations, [
          'putFile:users/user-err-1/profile/avatar.jpg',
          'getDownloadURL:users/user-err-1/profile/avatar.jpg',
        ]);

        // Firestore was NOT updated because no valid URL was obtained
        expect(docRef.lastSavedData, isNull);

        // Auth profile photo is preserved untouched
        expect(user.photoURL, existingPhotoUrl);

        // Button is re-enabled so the user can retry with the same selection
        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('update-data-button')),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      'handles Firestore save error gracefully, reports failure to user',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final user = _FakeUser(uid: 'user-err-2');
        final fakeAuth = _FakeFirebaseAuth(user: user);

        final docRef = _FakeDocumentReference(
          shouldThrow: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        );
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        await tester.pumpWidget(
          MaterialApp(
            home: EditProfileScreen(
              initialName: 'Captain Marvel',
              initialPhone: '+1-555-8888',
              initialAvatar: 'assets/avatars/avatar_option_2.jpg',
              auth: fakeAuth,
              firestore: fakeFirestore,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('update-data-button')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Failed to update profile: Permission denied. Please ensure you are logged in and authorized to update this profile.',
          ),
          findsOneWidget,
        );

        // Button state is restored
        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('update-data-button')),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      'UserAvatar gracefully handles broken/missing remote image reference without crashing',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: UserAvatar(
                avatar:
                    'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fnonexistent%2Fprofile%2Favatar.jpg?alt=media&token=invalid',
                size: 120,
              ),
            ),
          ),
        );
        await tester.pump();

        // Image widget is present and does not throw uncaught error
        expect(find.byType(UserAvatar), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'preserves existing profile picture when a new upload attempt fails',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialValidStorageUrl =
            'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fuser-preserve%2Fprofile%2Favatar.jpg?alt=media&token=pre-existing-good-token';

        final user = _FakeUser(
          uid: 'user-preserve',
          displayName: 'Black Widow',
          photoURL: initialValidStorageUrl,
        );
        final fakeAuth = _FakeFirebaseAuth(user: user);

        // Upload fails due to network timeout
        final fakeStorageRef = _FakeStorageReference(
          putFileThrows: FirebaseException(
            plugin: 'firebase_storage',
            code: 'retry-limit-exceeded',
            message: 'Max retry time exceeded.',
          ),
        );
        final fakeStorage = _FakeFirebaseStorage(rootRef: fakeStorageRef);

        final docRef = _FakeDocumentReference();
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        final fakePicker = _FakeImagePickerWithFile(sampleImageFile.path);

        await tester.pumpWidget(
          MaterialApp(
            home: EditProfileScreen(
              initialName: 'Black Widow',
              initialPhone: '+1-555-3333',
              initialAvatar: initialValidStorageUrl,
              auth: fakeAuth,
              storage: fakeStorage,
              firestore: fakeFirestore,
              imagePicker: fakePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pick photo from gallery
        await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pick-from-gallery-button')));
        await tester.pumpAndSettle();

        // Attempt to update
        await tester.tap(find.byKey(const Key('update-data-button')));
        await tester.pumpAndSettle();

        // Expect timeout error notification
        expect(
          find.text(
            'Failed to update profile: Upload timed out. Please check your internet connection.',
          ),
          findsOneWidget,
        );

        // Firestore was NEVER updated with broken/partial data
        expect(docRef.lastSavedData, isNull);

        // Firebase Auth photoURL is preserved untouched
        expect(user.photoURL, initialValidStorageUrl);
      },
    );

    testWidgets(
      'rejects non-existent or empty picked image file and prevents upload',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final user = _FakeUser(uid: 'user-empty-check');
        final fakeAuth = _FakeFirebaseAuth(user: user);
        final fakeStorage = _FakeFirebaseStorage();
        final docRef = _FakeDocumentReference();
        final fakeFirestore = _FakeFirebaseFirestore(docRef: docRef);

        // Picker returns a non-existent file path
        final fakePicker = _FakeImagePickerWithFile(
          '${tempDir.path}/does_not_exist_file.jpg',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: EditProfileScreen(
              initialName: 'Thor',
              initialPhone: '+1-555-1111',
              initialAvatar: 'assets/avatars/avatar_option_3.jpg',
              auth: fakeAuth,
              storage: fakeStorage,
              firestore: fakeFirestore,
              imagePicker: fakePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap change photo
        await tester.tap(find.byKey(const Key('avatar-picker-trigger')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pick-from-gallery-button')));
        await tester.pumpAndSettle();

        // Validation error is displayed immediately
        expect(
          find.text('Selected image file does not exist.'),
          findsOneWidget,
        );

        // Firestore and Storage were never touched
        expect(docRef.lastSavedData, isNull);
      },
    );

    testWidgets(
      'ProfileScreen reload / app restart persists saved Storage download URL and renders UserAvatar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const persistedStorageUrl =
            'https://firebasestorage.googleapis.com/v0/b/movies-138a9.firebasestorage.app/o/users%2Fpersisted-uid%2Fprofile%2Favatar.jpg?alt=media&token=persisted-token';

        await tester.pumpWidget(
          const MaterialApp(
            home: ProfileScreen(
              initialUserData: {
                'name': 'Captain America',
                'email': 'cap@avengers.org',
                'phone': '+1 555-1941',
                'avatar': persistedStorageUrl,
              },
              watchlistCount: 10,
              historyCount: 25,
              favoritesCount: 7,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Captain America'), findsOneWidget);
        expect(find.text('cap@avengers.org'), findsOneWidget);
        expect(find.text('+1 555-1941'), findsOneWidget);
        expect(find.byType(UserAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'default avatar is safely used when user profile has no picture or null avatar',
      (tester) async {
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
                'name': 'Hawkeye',
                'email': 'clint@avengers.org',
                'phone': '',
                'avatar': '',
              },
              watchlistCount: 0,
              historyCount: 0,
              favoritesCount: 0,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hawkeye'), findsOneWidget);
        expect(find.byType(UserAvatar), findsOneWidget);
        // UserAvatar falls back to person icon when avatar is empty string
        expect(find.byIcon(Icons.person), findsOneWidget);
      },
    );
  });
}
