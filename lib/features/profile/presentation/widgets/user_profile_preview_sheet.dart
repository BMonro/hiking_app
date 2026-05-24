import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/public_profile_repository.dart';
import 'profile_avatar.dart';

String profileInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.length >= 2
        ? parts.first.substring(0, 2).toUpperCase()
        : parts.first[0].toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String fitnessLevelUa(String? v) {
  return switch (v) {
    'beginner' => 'Початківець',
    'intermediate' => 'Середній',
    'advanced' => 'Досвідчений',
    _ => 'Не вказано',
  };
}

Future<void> showUserProfilePreview(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UserProfilePreviewSheet(userId: userId),
  );
}

class _UserProfilePreviewSheet extends ConsumerStatefulWidget {
  final String userId;

  const _UserProfilePreviewSheet({required this.userId});

  @override
  ConsumerState<_UserProfilePreviewSheet> createState() =>
      _UserProfilePreviewSheetState();
}

class _UserProfilePreviewSheetState
    extends ConsumerState<_UserProfilePreviewSheet> {
  PublicProfile? _profile;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref
          .read(publicProfileRepositoryProvider)
          .fetchById(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _error = p == null ? 'Профіль не знайдено' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottom),
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        _error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  )
                : _buildContent(_profile!),
      ),
    );
  }

  Widget _buildContent(PublicProfile profile) {
    final bio = profile.bio ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: ProfileAvatar(
            radius: 44,
            imageUrl: profile.avatarUrl,
            initials: profileInitials(profile.displayName),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          profile.displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _infoRow(Icons.cake_outlined, 'Вік', profile.age?.toString() ?? '—'),
        const SizedBox(height: 6),
        _infoRow(
          Icons.fitness_center_outlined,
          'Підготовка',
          fitnessLevelUa(profile.fitnessLevel),
        ),
        const SizedBox(height: 6),
        _infoRow(
          Icons.terrain_outlined,
          'Завершені походи',
          '${profile.experienceCount}',
        ),
        if (profile.phoneNumber != null) ...[
          const SizedBox(height: 6),
          _infoRow(
            Icons.phone_outlined,
            'Телефон',
            profile.phoneNumber!,
          ),
        ],
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Про себе',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            bio,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.grey[800],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('Закрити'),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
