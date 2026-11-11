import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/user_avatar.dart';
import 'forgot_password_screen.dart';

class ProfileEditResult {
  const ProfileEditResult({
    required this.name,
    required this.phone,
    required this.avatarAsset,
  });

  final String name;
  final String phone;
  final String avatarAsset;
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialPhone,
    required this.initialAvatar,
    this.auth,
    this.firestore,
    this.storage,
    this.imagePicker,
    this.onSave,
  });

  final String initialName;
  final String initialPhone;
  final String initialAvatar;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;
  final ImagePicker? imagePicker;
  final Future<String?> Function(
    String name,
    String phone,
    String avatar,
    File? imageFile,
  )? onSave;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _yellow = Color(0xFFFFC400);
  static const Color _fieldColor = Color(0xFF292A2A);
  static const Color _deleteRed = Color(0xFFEF2428);
  static const String _storageBucket = 'movies-138a9.firebasestorage.app';

  static const List<String> _avatars = [
    'assets/avatars/avatar_option_1.jpg',
    'assets/avatars/avatar_option_2.jpg',
    'assets/avatars/avatar_option_3.jpg',
    'assets/avatars/avatar_option_4.jpg',
    'assets/avatars/avatar_option_5.jpg',
    'assets/avatars/avatar_option_6.jpg',
    'assets/avatars/avatar_option_7.jpg',
    'assets/avatars/avatar_option_8.jpg',
    'assets/avatars/avatar_option_9.jpg',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late String _avatarAsset;
  late int _selectedAvatarIndex;

  File? _pickedImageFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _avatarAsset = widget.initialAvatar;
    _selectedAvatarIndex = _avatars.indexOf(widget.initialAvatar);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showNotification(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String? _validateImageFile(File file) {
    try {
      if (!file.existsSync()) {
        return 'Selected image file does not exist.';
      }
      final size = file.lengthSync();
      if (size <= 0) {
        return 'Selected image file is empty.';
      }
      if (size > 10 * 1024 * 1024) {
        return 'Selected image is too large (maximum 10 MB).';
      }
      return null;
    } catch (_) {
      return 'Could not read the selected image file.';
    }
  }

  String _detectContentType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  void _evictCachedNetworkImage(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    try {
      PaintingBinding.instance.imageCache.evict(NetworkImage(url));
    } catch (_) {}
  }

  FirebaseStorage _resolveStorage() {
    if (widget.storage != null) {
      return widget.storage!;
    }
    try {
      return FirebaseStorage.instanceFor(bucket: _storageBucket);
    } catch (_) {
      return FirebaseStorage.instance;
    }
  }

  String _formatFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'object-not-found':
        return 'The uploaded image could not be confirmed in Firebase Storage. Please tap Update Data to try again.';
      case 'unauthorized':
      case 'permission-denied':
        return 'Permission denied. Please ensure you are logged in and authorized to update this profile.';
      case 'quota-exceeded':
        return 'Storage quota exceeded. Please contact support.';
      case 'canceled':
        return 'Image upload was cancelled.';
      case 'retry-limit-exceeded':
        return 'Upload timed out. Please check your internet connection.';
      case 'invalid-url':
      case 'upload-incomplete':
        return e.message ?? 'Image upload was incomplete. Please try again.';
      default:
        final msg = e.message;
        if (msg != null && msg.trim().isNotEmpty) {
          return msg.trim();
        }
        return 'An error occurred (${e.code}). Please try again.';
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = widget.imagePicker ?? ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked != null && mounted) {
        final file = File(picked.path);
        final validationError = _validateImageFile(file);
        if (validationError != null) {
          _showNotification(validationError);
          return;
        }

        setState(() {
          _pickedImageFile = file;
          _selectedAvatarIndex = -1;
        });
      }
    } catch (e) {
      _showNotification('Could not pick image from gallery.');
    }
  }

  Future<void> _showAvatarPickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        height: 520,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        decoration: const BoxDecoration(
          color: Color(0xFF202020),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Change Profile Photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('pick-from-gallery-button'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFromGallery();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _fieldColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _yellow.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.photo_library_rounded,
                      color: _yellow,
                      size: 26,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose from Gallery',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Select a photo from your device',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Or choose an avatar:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.zero,
                itemCount: _avatars.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final isSelected =
                      _pickedImageFile == null && index == _selectedAvatarIndex;

                  return GestureDetector(
                    key: Key('avatar-option-$index'),
                    onTap: () {
                      setState(() {
                        _selectedAvatarIndex = index;
                        _avatarAsset = _avatars[index];
                        _pickedImageFile = null;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF9E7800)
                            : const Color(0xFF292A2A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? _yellow : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: ClipOval(
                        child: Image.asset(
                          _avatars[index],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.person, color: Colors.white70),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _fieldColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account?'),
        content: const Text('This will remove your account from this app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (shouldDelete == true && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _updateData() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      _showNotification('Please enter your name');
      return;
    }

    if (name.length > 100) {
      _showNotification('Name must be 100 characters or less');
      return;
    }

    if (phone.isEmpty) {
      _showNotification('Please enter your phone number');
      return;
    }

    if (phone.length > 32) {
      _showNotification('Phone number must be 32 characters or less');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String finalAvatar = _avatarAsset.trim().isNotEmpty
          ? _avatarAsset
          : (widget.initialAvatar.trim().isNotEmpty
              ? widget.initialAvatar
              : 'assets/avatars/avatar_hoodie.jpg');

      // Validate picked image if user selected one
      if (_pickedImageFile != null) {
        final validationError = _validateImageFile(_pickedImageFile!);
        if (validationError != null) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          _showNotification(validationError);
          return;
        }
      }

      // Handle custom onSave for tests / injection
      if (widget.onSave != null) {
        final customResult = await widget.onSave!(
          name,
          phone,
          _avatarAsset,
          _pickedImageFile,
        );

        if (customResult != null && customResult.trim().isNotEmpty) {
          finalAvatar = customResult;
        }

        if (!mounted) return;

        setState(() => _isSaving = false);
        _showNotification('Profile updated successfully!', isError: false);
        Navigator.of(context).pop(
          ProfileEditResult(
            name: name,
            phone: phone,
            avatarAsset: finalAvatar,
          ),
        );
        return;
      }

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
        throw Exception('User is not signed in');
      }

      // Scenario A: Upload to Firebase Storage if a local gallery photo was chosen
      if (_pickedImageFile != null) {
        final storage = _resolveStorage();

        // Consistent and predictable storage reference: users/{uid}/profile/avatar.jpg
        final storageRef = storage
            .ref()
            .child('users')
            .child(user.uid)
            .child('profile')
            .child('avatar.jpg');

        final contentType = _detectContentType(_pickedImageFile!.path);
        final metadata = SettableMetadata(
          contentType: contentType,
          cacheControl: 'public, max-age=3600',
          customMetadata: {
            'userId': user.uid,
            'uploadedAt': DateTime.now().toUtc().toIso8601String(),
          },
        );

        // Awaiting the upload task is the completion check. The completed
        // snapshot means the selected local file was stored successfully.
        final uploadTask = storageRef.putFile(_pickedImageFile!, metadata);
        final snapshot = await uploadTask;

        if (snapshot.state != TaskState.success) {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'upload-incomplete',
            message: 'Image upload failed to complete (${snapshot.state.name}).',
          );
        }

        // Use the same reference for the upload and for the download URL.
        final downloadUrl = (await storageRef.getDownloadURL()).trim();
        if (downloadUrl.isEmpty) {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'invalid-url',
            message: 'Download URL retrieved from Firebase Storage is empty.',
          );
        }

        // Refresh cached images so the new picture is shown immediately.
        _evictCachedNetworkImage(_avatarAsset);
        _evictCachedNetworkImage(downloadUrl);

        finalAvatar = downloadUrl;
      }

      // Save to Firestore user document (Scenario A & Scenario B)
      FirebaseFirestore? firestore = widget.firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          firestore = null;
        }
      }

      if (firestore == null) {
        throw Exception('Firestore is not initialized');
      }

      await firestore.collection('users').doc(user.uid).set({
        'name': name,
        'phone': phone,
        'avatar': finalAvatar,
      }, SetOptions(merge: true));

      // Sync display name and photo with Firebase Auth
      try {
        await user.updateDisplayName(name);
        if (finalAvatar.startsWith('http://') ||
            finalAvatar.startsWith('https://')) {
          await user.updatePhotoURL(finalAvatar);
        }
      } catch (_) {
        // Auth sync failure is non-fatal since Firestore is source of truth
      }

      if (!mounted) return;

      setState(() => _isSaving = false);
      _showNotification('Profile updated successfully!', isError: false);

      Navigator.of(context).pop(
        ProfileEditResult(
          name: name,
          phone: phone,
          avatarAsset: finalAvatar,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final readableError = _formatFirebaseError(e);
      _showNotification('Failed to update profile: $readableError');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showNotification('Could not update profile. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF101111),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
                child: Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Text(
                            'Edit Profile',
                            style: TextStyle(
                              color: _yellow,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              key: const Key('edit-profile-back-button'),
                              onPressed: () => Navigator.pop(context),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 42,
                                height: 42,
                              ),
                              icon: const Icon(
                                Icons.arrow_back,
                                color: _yellow,
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    GestureDetector(
                      key: const Key('avatar-picker-trigger'),
                      onTap: _showAvatarPickerSheet,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomRight,
                        children: [
                          UserAvatar(
                            avatar: _avatarAsset,
                            imageFile: _pickedImageFile,
                            size: 140,
                            borderColor: _yellow,
                            borderWidth: 2,
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _yellow,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF101111),
                                  width: 2.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _showAvatarPickerSheet,
                      icon: const Icon(Icons.edit, color: _yellow, size: 16),
                      label: const Text(
                        'Change Photo',
                        style: TextStyle(
                          color: _yellow,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _ProfileEditField(
                      key: const Key('edit-name-field'),
                      controller: _nameController,
                      icon: Icons.person,
                      hint: 'Name',
                    ),
                    const SizedBox(height: 18),
                    _ProfileEditField(
                      key: const Key('edit-phone-field'),
                      controller: _phoneController,
                      icon: Icons.call,
                      hint: 'Phone Number',
                      keyboardType: TextInputType.phone,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.only(top: 20),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Reset Password',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Column(
                children: [
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('delete-account-button'),
                      onPressed: _deleteAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _deleteRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Delete Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('update-data-button'),
                      onPressed: _isSaving ? null : _updateData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _yellow,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                            _yellow.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Update Data',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
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

class _ProfileEditField extends StatelessWidget {
  const _ProfileEditField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF292A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54, fontSize: 18),
          prefixIcon: Icon(icon, color: Colors.white70, size: 24),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
        ),
      ),
    );
  }
}
