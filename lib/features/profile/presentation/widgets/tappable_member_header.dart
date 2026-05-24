import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/public_profile_repository.dart';
import 'profile_avatar.dart';
import 'user_profile_preview_sheet.dart';

/// Аватар + ім’я; по натисканню — прев’ю профілю.
class TappableMemberHeader extends ConsumerWidget {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double avatarRadius;
  final TextStyle? nameStyle;
  final bool showYouBadge;
  final MainAxisAlignment alignment;

  const TappableMemberHeader({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.avatarRadius = 18,
    this.nameStyle,
    this.showYouBadge = false,
    this.alignment = MainAxisAlignment.start,
  });

  factory TappableMemberHeader.fromProfile(
    PublicProfile profile, {
    Key? key,
    double avatarRadius = 18,
    TextStyle? nameStyle,
    bool showYouBadge = false,
    MainAxisAlignment alignment = MainAxisAlignment.start,
  }) {
    return TappableMemberHeader(
      key: key,
      userId: profile.id,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      avatarRadius: avatarRadius,
      nameStyle: nameStyle,
      showYouBadge: showYouBadge,
      alignment: alignment,
    );
  }

  void _openPreview(BuildContext context, WidgetRef ref) {
    showUserProfilePreview(context, ref, userId: userId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = nameStyle ??
        const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: Color(0xFF2E7D32),
        );

    return InkWell(
      onTap: () => _openPreview(context, ref),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          children: [
            ProfileAvatar(
              radius: avatarRadius,
              imageUrl: avatarUrl,
              initials: profileInitials(displayName),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showYouBadge) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(ви)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
