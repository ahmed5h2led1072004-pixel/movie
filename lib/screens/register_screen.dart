import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _background = Color(0xFF111312);
  static const _accent = Color(0xFFFFC400);
  static const _fieldColor = Color(0xFF272828);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  int _selectedAvatar = 1;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _useArabicFlag = false;
  bool _isLoading = false;

  final List<String> _avatarAssets = [
    'assets/avatars/avatar_sunglasses.jpg',
    'assets/avatars/avatar_hoodie.jpg',
    'assets/avatars/avatar_beard.jpg',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _fieldColor,
        ),
      );
  }

  Future<void> _createAccount() async {
    if (_isLoading) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('Passwords do not match');
      return;
    }

    if (_passwordController.text.length < 6) {
      _showMessage('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Create account using Firebase Authentication.
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      final user = credential.user;

      if (user == null) {
        throw Exception('User account could not be created');
      }

      // Save the profile first; Firestore is the app's profile source of truth.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'avatar': _avatarAssets[_selectedAvatar],
        'createdAt': FieldValue.serverTimestamp(),
      });

      var displayNameSynced = true;
      try {
        await user.updateDisplayName(_nameController.text.trim());
      } catch (_) {
        displayNameSynced = false;
      }

      if (!mounted) return;

      _showMessage(
        displayNameSynced
            ? 'Account created successfully!'
            : 'Account created. Your profile name could not be synced.',
      );

      // Step 4: Navigate to Home Screen.
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address';
          break;

        case 'weak-password':
          message = 'Password is too weak';
          break;

        case 'operation-not-allowed':
          message = 'Email registration is not enabled in Firebase';
          break;

        case 'network-request-failed':
          message = 'Please check your internet connection';
          break;

        default:
          message = e.message ?? 'Something went wrong. Please try again';
      }

      _showMessage(message);
    } on FirebaseException catch (e) {
      _showMessage('Account created, but saving profile failed: ${e.message}');
      if (FirebaseAuth.instance.currentUser != null && mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      _showMessage('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(15, 4, 15, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Text(
                              'Register',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 21,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: _accent,
                                  size: 30,
                                ),
                                tooltip: 'Back to login',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildAvatar(
                            index: 0,
                            asset: _avatarAssets[0],
                            size: 86,
                          ),
                          _buildAvatar(
                            index: 1,
                            asset: _avatarAssets[1],
                            size: 150,
                          ),
                          _buildAvatar(
                            index: 2,
                            asset: _avatarAssets[2],
                            size: 86,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Avatar',
                        style: TextStyle(color: Colors.white, fontSize: 17),
                      ),
                      const SizedBox(height: 18),
                      _buildInput(
                        icon: Icons.badge_outlined,
                        hint: 'Name',
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _required(value, 'Name'),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(
                        icon: Icons.email_rounded,
                        hint: 'Email',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _required(value, 'Email'),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(
                        icon: Icons.lock_rounded,
                        hint: 'Password',
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _required(value, 'Password'),
                        trailing: _visibilityButton(
                          visible: _passwordVisible,
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(
                        icon: Icons.lock_rounded,
                        hint: 'Confirm Password',
                        controller: _confirmPasswordController,
                        obscureText: !_confirmPasswordVisible,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            _required(value, 'Confirm password'),
                        trailing: _visibilityButton(
                          visible: _confirmPasswordVisible,
                          onPressed: () => setState(
                            () => _confirmPasswordVisible =
                                !_confirmPasswordVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(
                        icon: Icons.call_rounded,
                        hint: 'Phone Number',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        validator: (value) => _required(value, 'Phone number'),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _createAccount,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: _accent.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('Create Account'),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Already Have Account ? ',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: const Text(
                              'Login',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildLanguageSwitch(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _required(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  Widget _buildAvatar({
    required int index,
    required String asset,
    required double size,
  }) {
    final selected = _selectedAvatar == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedAvatar = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected ? Border.all(color: _accent, width: 2) : null,
        ),
        child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
      ),
    );
  }

  Widget _buildInput({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? trailing,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: _fieldColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              obscureText: obscureText,
              validator: validator,
              style: const TextStyle(color: Colors.white, fontSize: 17),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white, fontSize: 17),
                border: InputBorder.none,
                isCollapsed: true,
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _visibilityButton({
    required bool visible,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        color: Colors.white,
        size: 25,
      ),
      tooltip: visible ? 'Hide password' : 'Show password',
    );
  }

  Widget _buildLanguageSwitch() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: _accent, width: 2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _languageOption(
            flag: '🇺🇸',
            selected: !_useArabicFlag,
            onTap: () => setState(() => _useArabicFlag = false),
          ),
          _languageOption(
            flag: '🇪🇬',
            selected: _useArabicFlag,
            onTap: () => setState(() => _useArabicFlag = true),
          ),
        ],
      ),
    );
  }

  Widget _languageOption({
    required String flag,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(flag, style: const TextStyle(fontSize: 21)),
      ),
    );
  }
}
