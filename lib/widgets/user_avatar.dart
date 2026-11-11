import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.avatar,
    this.imageFile,
    this.size = 118,
    this.borderColor,
    this.borderWidth = 0,
    this.backgroundColor = const Color(0xFF292A2A),
    this.fallbackIcon = Icons.person,
  });

  final String avatar;
  final File? imageFile;
  final double size;
  final Color? borderColor;
  final double borderWidth;
  final Color backgroundColor;
  final IconData fallbackIcon;

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      color: backgroundColor,
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        color: Colors.white70,
        size: size * 0.55,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (imageFile != null) {
      imageWidget = Image.file(
        imageFile!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } else if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      imageWidget = Image.network(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            color: backgroundColor,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFC400),
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } else if (!kIsWeb &&
        (avatar.startsWith('/') ||
            avatar.contains(r'\') ||
            avatar.contains('/data/'))) {
      final file = File(avatar);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      } else {
        imageWidget = _buildFallback();
      }
    } else if (avatar.isNotEmpty && avatar.startsWith('assets/')) {
      imageWidget = Image.asset(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } else {
      imageWidget = _buildFallback();
    }

    final hasBorder = borderWidth > 0 && borderColor != null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: hasBorder
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: ClipOval(child: imageWidget),
    );
  }
}
