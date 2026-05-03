import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final journalProvider = FutureProvider((ref) async {
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final data = await Supabase.instance.client
      .from('journal_entries')
      .select('*, routes(title, difficulty), journal_photos(photo_url)')
      .eq('user_id', userId)
      .order('date', ascending: false);
  return data as List;
});

final journalStatsProvider = FutureProvider((ref) async {
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final data = await Supabase.instance.client
      .from('profile_stats')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  return data;
});

class _JournalColors {
  static const background = Color(0xFFF1F6EE);
  static const surface = Color(0xFFFFFDFC);
  static const primary = Color(0xFF6F8B4E);
  static const primaryDark = Color(0xFF4F6736);
  static const accent = Color(0xFFD99058);
  static const textMain = Color(0xFF35271F);
  static const textSecondary = Color(0xFF6E5849);
  static const success = Color(0xFF6F8B4E);
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
            style: TextButton.styleFrom(foregroundColor: _JournalColors.primary),
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
      ref.refresh(journalProvider);
      ref.refresh(journalStatsProvider);
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
      backgroundColor: _JournalColors.background,
      appBar: AppBar(
        backgroundColor: _JournalColors.success,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Журнал',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Мій журнал',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Фіксуй маршрути, враження та спогади',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _JournalColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showEntryDialog(context, ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _JournalColors.primary,
                          foregroundColor: _JournalColors.surface,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'Запис',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
                        color: _JournalColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _JournalColors.primary.withOpacity(0.28)),
                        boxShadow: [
                          BoxShadow(
                            color: _JournalColors.success.withOpacity(0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 18,
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
                              color: _JournalColors.textSecondary.withOpacity(0.2)),
                          _JournalStat(
                            value: '${stats?['total_distance_km'] ?? 0}',
                            label: 'Км\nпройдено',
                          ),
                          Container(
                              width: 1,
                              height: 44,
                              color: _JournalColors.textSecondary.withOpacity(0.2)),
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
                      fontSize: 20,
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
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Помилка: $e')),
            ),
            data: (entries) => entries.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.book_outlined,
                                size: 64,
                                color: _JournalColors.textSecondary.withOpacity(0.35)),
                            const SizedBox(height: 16),
                            Text(
                              'Журнал порожній',
                              style: TextStyle(
                                color: _JournalColors.textSecondary.withOpacity(0.8),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _JournalColors.surface,
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
                        color: _JournalColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.terrain,
                        color: _JournalColors.primary,
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
                TextField(
                  controller: titleController,
                  decoration: _inputDecoration('Назва походу *'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    '${selectedDate.day}.${selectedDate.month}.${selectedDate.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      child: TextField(
                        controller: distanceController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Відстань (км)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Тривалість (год)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ascentController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('Перепад висот (м)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
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
                                  color: _JournalColors.background,
                                  alignment: Alignment.center,
                                  child: Icon(Icons.broken_image,
                                      color: _JournalColors.textSecondary.withOpacity(0.7)),
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
                    foregroundColor: _JournalColors.primary,
                    side: const BorderSide(color: _JournalColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _JournalColors.primary,
                    foregroundColor: _JournalColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Введіть назву')),
                      );
                      return;
                    }
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
                      ref.refresh(journalProvider);
                      ref.refresh(journalStatsProvider);
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
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: _JournalColors.textSecondary.withOpacity(0.9),
          ),
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

    String? diffLabel;
    Color? diffColor;
    if (difficulty == 'easy') {
      diffLabel = 'Легка';
      diffColor = _JournalColors.success;
    } else if (difficulty == 'medium') {
      diffLabel = 'Середня';
      diffColor = _JournalColors.accent;
    } else if (difficulty == 'hard') {
      diffLabel = 'Важка';
      diffColor = _JournalColors.primaryDark;
    }

    final routeTitle = entry['routes']?['title'] as String?;
    final notes = entry['notes'] as String?;
    final imageUrls = _extractImageUrls(entry);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _JournalColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _JournalColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: _JournalColors.success.withOpacity(0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: const Color(0x00000000),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: imageUrls.isNotEmpty
                            ? Image.network(
                                imageUrls.first,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        _JournalColors.accent,
                                        _JournalColors.primary
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.terrain,
                                    color: _JournalColors.surface,
                                    size: 28,
                                  ),
                                ),
                              )
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _JournalColors.accent,
                                      _JournalColors.primary
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.terrain,
                                  color: _JournalColors.surface,
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['title'] ?? 'Похід',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (routeTitle != null) ...[
                            Text(
                              routeTitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: _JournalColors.textSecondary.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 12,
                                color: _JournalColors.textSecondary.withOpacity(0.8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${date.day} ${_monthName(date.month)} ${date.year}',
                                style: TextStyle(
                                  color: _JournalColors.textSecondary.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                              if (!expanded &&
                                  notes != null &&
                                  notes.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Text('•',
                                    style:
                                        TextStyle(color: _JournalColors.textSecondary)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    notes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _JournalColors.textSecondary.withOpacity(0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (diffLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: diffColor!.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              diffLabel,
                              style: TextStyle(
                                color: diffColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: _JournalColors.textSecondary.withOpacity(0.9),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (entry['actual_distance_km'] != null)
                      _MiniStat(
                        value: '${entry['actual_distance_km']}',
                        label: 'км',
                      ),
                    if (entry['actual_duration_h'] != null) ...[
                      const SizedBox(width: 12),
                      _MiniStat(
                        value: '${entry['actual_duration_h']}',
                        label: 'год',
                      ),
                    ],
                    if (entry['actual_ascent_m'] != null) ...[
                      const SizedBox(width: 12),
                      _MiniStat(
                        value: '${entry['actual_ascent_m']}',
                        label: 'м ↑',
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
                        const SizedBox(height: 18),
                        Text(
                          notes,
                          style: TextStyle(
                            color: _JournalColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (expanded) ...[
                        const SizedBox(height: 16),
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
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        child: Image.network(
                                          previewUrls[index],
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                            color: _JournalColors.background,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.broken_image,
                                              color: _JournalColors.textSecondary
                                                  .withOpacity(0.75),
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
                          const SizedBox(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _CardActionIconButton(
                              icon: Icons.edit_rounded,
                              tooltip: 'Редагувати',
                              foregroundColor: _JournalColors.primaryDark,
                              backgroundColor:
                                  _JournalColors.success.withOpacity(0.22),
                              hoverColor: _JournalColors.success.withOpacity(0.33),
                              onTap: onEdit,
                            ),
                            const SizedBox(width: 10),
                            _CardActionIconButton(
                              icon: Icons.delete_outline_rounded,
                              tooltip: 'Видалити',
                              foregroundColor: _JournalColors.primaryDark,
                              backgroundColor:
                                  _JournalColors.primary.withOpacity(0.16),
                              hoverColor: _JournalColors.primary.withOpacity(0.28),
                              onTap: onDelete,
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

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;

  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _JournalColors.success.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$value $label'.trim(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _JournalColors.textMain,
        ),
      ),
    );
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
                  color: _JournalColors.primaryDark.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.close, size: 14, color: _JournalColors.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _CardActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: hoverColor,
          splashColor: foregroundColor.withOpacity(0.12),
          highlightColor: foregroundColor.withOpacity(0.08),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: foregroundColor, size: 22),
          ),
        ),
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final Color color;
  final double width;

  const _MiniProgressBar({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (width * 100).round(),
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final Color color;

  const _ImagePreview({required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
