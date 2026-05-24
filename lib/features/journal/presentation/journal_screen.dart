import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/validation/form_validators.dart';
import '../../../core/widgets/app_text_form_field.dart';

final journalProvider = FutureProvider((ref) async {
  ref.keepAlive();
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final data = await Supabase.instance.client
      .from('journal_entries')
      .select('*, routes(title, difficulty), journal_photos(photo_url)')
      .eq('user_id', userId)
      .order('date', ascending: false);
  return data as List;
});

final journalStatsProvider = FutureProvider((ref) async {
  ref.keepAlive();
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final data = await Supabase.instance.client
      .from('profile_stats')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  return data;
});

class _JournalTheme {
  static const background = Color(0xFFF3F5F2);
  static const primary = Color(0xFF2E7D32);
}

Color _difficultyChipColor(String? difficulty) {
  return switch (difficulty) {
    'easy' => const Color(0xFF4CAF50),
    'medium' => const Color(0xFFFF9800),
    'hard' => const Color(0xFFF44336),
    _ => const Color(0xFF4CAF50),
  };
}

String? _difficultyShortLabel(String? difficulty) {
  return switch (difficulty) {
    'easy' => 'Легка',
    'medium' => 'Середня',
    'hard' => 'Важка',
    _ => null,
  };
}

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final Set<String> _expandedEntries = {};
  final ImagePicker _imagePicker = ImagePicker();

  List<String> _extractImageUrls(Map<String, dynamic> entry) {
    final photos = entry['journal_photos'];
    if (photos is List) {
      return photos
          .whereType<Map>()
          .map((photo) => photo['photo_url'])
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
    }

    final dynamic value = entry['image_urls'] ?? entry['image_url'];
    if (value is List) {
      return value
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
    }
    if (value is! String || value.trim().isEmpty) return [];

    final trimmed = value.trim();
    if (!trimmed.startsWith('[')) return [trimmed];

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((url) => url.trim())
            .where((url) => url.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return [trimmed];
    }
    return [];
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedEntries.contains(id)) {
        _expandedEntries.remove(id);
      } else {
        _expandedEntries.add(id);
      }
    });
  }

  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, dynamic entryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити запис'),
        content: const Text('Ви впевнені, що хочете видалити цей запис?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: _JournalTheme.primary),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .from('journal_entries')
          .delete()
          .eq('id', entryId);
      ref.invalidate(journalProvider);
      ref.invalidate(journalStatsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запис видалено')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка видалення: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalAsync = ref.watch(journalProvider);
    final statsAsync = ref.watch(journalStatsProvider);

    return Scaffold(
      backgroundColor: _JournalTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Назад до профілю',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: const Text(
          'Журнал',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Фіксуй маршрути, враження та спогади',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showEntryDialog(context, ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _JournalTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Запис',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  statsAsync.when(
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                    data: (stats) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _JournalStat(
                            value: '${stats?['total_hikes'] ?? 0}',
                            label: 'Походів',
                          ),
                          Container(
                              width: 1,
                              height: 44,
                              color: Colors.grey[300]),
                          _JournalStat(
                            value: '${stats?['total_distance_km'] ?? 0}',
                            label: 'Км\nпройдено',
                          ),
                          Container(
                              width: 1,
                              height: 44,
                              color: Colors.grey[300]),
                          _JournalStat(
                            value: _formatAscent(stats?['total_ascent_m']),
                            label: 'М вгору',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Останні записи',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          journalAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Помилка: $e'),
                    ],
                  ),
                ),
              ),
            ),
            data: (entries) => entries.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          children: [
                            Icon(Icons.book_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Журнал порожній',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Натисніть «Запис» щоб додати перший',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entries[index];
                          final entryId =
                              entry['id']?.toString() ?? index.toString();
                          return _JournalCard(
                            entry: entry,
                            expanded: _expandedEntries.contains(entryId),
                            onToggle: () => _toggleExpanded(entryId),
                            onEdit: () =>
                                _showEntryDialog(context, ref, entry: entry),
                            onDelete: () =>
                                _deleteEntry(context, ref, entry['id']),
                          );
                        },
                        childCount: entries.length,
                      ),
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  String _formatAscent(dynamic value) {
    if (value == null) return '0';
    final double parsed = (value as num).toDouble();
    if (parsed >= 1000) return '${(parsed / 1000).toStringAsFixed(1)}k';
    return parsed.toStringAsFixed(0);
  }

  void _showEntryDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? entry}) {
    final titleController = TextEditingController(text: entry?['title'] ?? '');
    final notesController = TextEditingController(text: entry?['notes'] ?? '');
    final distanceController = TextEditingController(
        text: entry?['actual_distance_km']?.toString() ?? '');
    final durationController = TextEditingController(
        text: entry?['actual_duration_h']?.toString() ?? '');
    final ascentController = TextEditingController(
        text: entry?['actual_ascent_m']?.toString() ?? '');
    DateTime selectedDate =
        entry != null ? DateTime.parse(entry['date']) : DateTime.now();
    final isEditing = entry != null;
    final existingImageUrls = entry != null ? _extractImageUrls(entry) : <String>[];
    final selectedImages = <File>[];
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        Future<void> pickImage() async {
          if (existingImageUrls.length + selectedImages.length >= 5) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Можна додати максимум 5 фото')),
              );
            }
            return;
          }

          final result = await _imagePicker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 70,
          );
          if (result != null) {
            setModalState(() {
              selectedImages.add(File(result.path));
            });
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _JournalTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.terrain,
                        color: _JournalTheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEditing ? 'Редагувати запис' : 'Новий запис',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: titleController,
                  validator: FormValidators.title,
                  decoration: _inputDecoration('Назва походу *'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    '${selectedDate.day}.${selectedDate.month}.${selectedDate.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _JournalTheme.primary,
                    side: const BorderSide(color: _JournalTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setModalState(() => selectedDate = date);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextFormField(
                        controller: distanceController,
                        keyboardType: TextInputType.number,
                        validator: FormValidators.journalDistance,
                        decoration: _inputDecoration('Відстань (км)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextFormField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        validator: FormValidators.journalDuration,
                        decoration: _inputDecoration('Тривалість (год)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: ascentController,
                  keyboardType: TextInputType.number,
                  validator: FormValidators.journalAscent,
                  decoration: _inputDecoration('Перепад висот (м)'),
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: notesController,
                  maxLines: 3,
                  validator: FormValidators.notes,
                  decoration: _inputDecoration('Нотатки'),
                ),
                const SizedBox(height: 16),
                if (existingImageUrls.isNotEmpty || selectedImages.isNotEmpty) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 8.0;
                      final tileSize = (constraints.maxWidth - (spacing * 4)) / 5;
                      return Row(
                        children: [
                          for (var index = 0; index < existingImageUrls.length; index++) ...[
                            _PhotoTile(
                              size: tileSize,
                              image: Image.network(
                                existingImageUrls[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: _JournalTheme.background,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.broken_image,
                                      color: Colors.grey[500]),
                                ),
                              ),
                              onRemove: () => setModalState(() {
                                existingImageUrls.removeAt(index);
                              }),
                            ),
                            if (index != existingImageUrls.length - 1 ||
                                selectedImages.isNotEmpty)
                              const SizedBox(width: spacing),
                          ],
                          for (var index = 0; index < selectedImages.length; index++) ...[
                            _PhotoTile(
                              size: tileSize,
                              image: Image.file(selectedImages[index], fit: BoxFit.cover),
                              onRemove: () => setModalState(() {
                                selectedImages.removeAt(index);
                              }),
                            ),
                            if (index != selectedImages.length - 1)
                              const SizedBox(width: spacing),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: (existingImageUrls.length + selectedImages.length) >= 5
                      ? null
                      : pickImage,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    'Додати фото (${existingImageUrls.length + selectedImages.length}/5)',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _JournalTheme.primary,
                    side: const BorderSide(color: _JournalTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _JournalTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    try {
                      final userId =
                          Supabase.instance.client.auth.currentUser!.id;
                      final uploadedImageUrls = <String>[...existingImageUrls];

                      for (final image in selectedImages) {
                        final fileName =
                            '$userId/journal/${DateTime.now().millisecondsSinceEpoch}-${uploadedImageUrls.length}.jpg';
                        await Supabase.instance.client.storage
                            .from('journal')
                            .upload(
                              fileName,
                              image,
                              fileOptions: const FileOptions(
                                contentType: 'image/jpeg',
                                upsert: true,
                              ),
                            );
                        uploadedImageUrls.add(
                          Supabase.instance.client.storage
                              .from('journal')
                              .getPublicUrl(fileName),
                        );
                      }

                      final data = {
                        'title': titleController.text.trim(),
                        'date': selectedDate.toIso8601String().split('T')[0],
                        'notes': notesController.text.trim(),
                        'actual_distance_km':
                            double.tryParse(distanceController.text),
                        'actual_duration_h':
                            double.tryParse(durationController.text),
                        'actual_ascent_m': int.tryParse(ascentController.text),
                      };

                      late final String entryId;
                      if (isEditing) {
                        entryId = entry['id'].toString();
                        await Supabase.instance.client
                            .from('journal_entries')
                            .update(data)
                            .eq('id', entryId);
                        await Supabase.instance.client
                            .from('journal_photos')
                            .delete()
                            .eq('entry_id', entryId);
                      } else {
                        final insertedEntry = await Supabase.instance.client
                            .from('journal_entries')
                            .insert({
                          ...data,
                          'user_id': userId,
                        }).select('id').single();
                        entryId = insertedEntry['id'].toString();
                      }

                      if (uploadedImageUrls.isNotEmpty) {
                        await Supabase.instance.client
                            .from('journal_photos')
                            .insert(
                              uploadedImageUrls
                                  .map(
                                    (url) => {
                                      'entry_id': entryId,
                                      'photo_url': url,
                                    },
                                  )
                                  .toList(),
                            );
                      }
                      ref.invalidate(journalProvider);
                      ref.invalidate(journalStatsProvider);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Помилка: $e')),
                        );
                      }
                    }
                  },
                  child: Text(isEditing ? 'Зберегти зміни' : 'Зберегти запис'),
                ),
              ],
            ),
            ),
          ),
        );
      }),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class _JournalStat extends StatelessWidget {
  final String value;
  final String label;

  const _JournalStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _JournalTheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _JournalThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _JournalThumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: _JournalTheme.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.terrain, color: _JournalTheme.primary, size: 26),
      ),
    );
    return SizedBox(
      width: 52,
      height: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

class _JournalStatChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _JournalStatChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
      ],
    );
  }
}

class _JournalCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _JournalCard({
    required this.entry,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(entry['date']);
    final difficulty = entry['routes']?['difficulty'] as String?;
    final diffLabel = _difficultyShortLabel(difficulty);
    final diffColor = _difficultyChipColor(difficulty);

    final routeTitle = entry['routes']?['title'] as String?;
    final notes = entry['notes'] as String?;
    final imageUrls = _extractImageUrls(entry);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _JournalThumbnail(imageUrl: imageUrls.isNotEmpty ? imageUrls.first : null),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry['title'] ?? 'Похід',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (diffLabel != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: diffColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: diffColor.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    diffLabel,
                                    style: TextStyle(
                                      color: diffColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (routeTitle != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.alt_route, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    routeTitle,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                '${date.day} ${_monthName(date.month)} ${date.year}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                              if (!expanded && notes != null && notes.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Text('•', style: TextStyle(color: Colors.grey)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    notes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey[600],
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (entry['actual_distance_km'] != null)
                      _JournalStatChip(
                        icon: Icons.straighten,
                        text: '${entry['actual_distance_km']} км',
                      ),
                    if (entry['actual_duration_h'] != null) ...[
                      const SizedBox(width: 16),
                      _JournalStatChip(
                        icon: Icons.schedule,
                        text: '${entry['actual_duration_h']} год',
                      ),
                    ],
                    if (entry['actual_ascent_m'] != null) ...[
                      const SizedBox(width: 16),
                      _JournalStatChip(
                        icon: Icons.trending_up,
                        text: '${entry['actual_ascent_m']} м',
                      ),
                    ],
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (expanded && notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          notes,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (expanded) ...[
                        const SizedBox(height: 14),
                        if (imageUrls.isNotEmpty) ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              const spacing = 8.0;
                              final tileSize =
                                  (constraints.maxWidth - (spacing * 4)) / 5;
                              final previewUrls = imageUrls.take(5).toList();
                              return Row(
                                children: [
                                  for (var index = 0; index < previewUrls.length; index++) ...[
                                    SizedBox(
                                      width: tileSize,
                                      height: tileSize,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          previewUrls[index],
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              Container(
                                            color: _JournalTheme.background,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.broken_image,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (index != previewUrls.length - 1)
                                      const SizedBox(width: spacing),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Редагувати',
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined),
                              color: _JournalTheme.primary,
                            ),
                            IconButton(
                              tooltip: 'Видалити',
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.grey[700],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '',
      'січня',
      'лютого',
      'березня',
      'квітня',
      'травня',
      'червня',
      'липня',
      'серпня',
      'вересня',
      'жовтня',
      'листопада',
      'грудня'
    ];
    return months[month];
  }

  List<String> _extractImageUrls(Map<String, dynamic> entry) {
    final photos = entry['journal_photos'];
    if (photos is List) {
      return photos
          .whereType<Map>()
          .map((photo) => photo['photo_url'])
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
    }

    final dynamic value = entry['image_urls'] ?? entry['image_url'];
    if (value is List) {
      return value
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
    }
    if (value is! String || value.trim().isEmpty) {
      return [];
    }

    final trimmed = value.trim();
    if (!trimmed.startsWith('[')) {
      return [trimmed];
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((url) => url.trim())
            .where((url) => url.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return [trimmed];
    }

    return [];
  }
}

class _PhotoTile extends StatelessWidget {
  final double size;
  final Widget image;
  final VoidCallback onRemove;

  const _PhotoTile({
    required this.size,
    required this.image,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox.expand(child: image),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF424242),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

