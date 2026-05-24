import 'dart:io';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final double radius;
  final String? imageUrl;
  final File? localImage;
  final String initials;
  final Color backgroundColor;

  const ProfileAvatar({
    super.key,
    required this.radius,
    required this.initials,
    this.imageUrl,
    this.localImage,
    this.backgroundColor = const Color(0xFF2E7D32),
  });

  @override
  Widget build(BuildContext context) {
    if (localImage != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(localImage!),
      );
    }

    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: ClipOval(
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsChild(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: Center(
                  child: SizedBox(
                    width: radius * 0.6,
                    height: radius * 0.6,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: _initialsChild(),
    );
  }

  Widget _initialsChild() {
    return Text(
      initials,
      style: TextStyle(
        fontSize: radius * 0.58,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
