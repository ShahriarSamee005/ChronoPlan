import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

const _kPresetColors = <int>[
  0xFF4E9AF1, 0xFF6BCB77, 0xFFFF6B6B, 0xFFC77DFF,
  0xFFFFD93D, 0xFFFF9F43, 0xFF4ECDC4, 0xFF74B9FF,
  0xFF55EFC4, 0xFFE17055, 0xFFA29BFE, 0xFFFF7675,
  0xFF00B894, 0xFFFD79A8, 0xFF636E72, 0xFFB2BEC3,
];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Categories',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            tooltip: 'New category',
            onPressed: () => _showCategorySheet(context, ref, null),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: catsAsync.when(
            data: (cats) => cats.isEmpty
                ? const Center(
                    child: Text('No categories yet.',
                        style: TextStyle(color: Colors.white54)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) =>
                        _CategoryTile(cat: cats[i], ref: ref),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e',
                  style: const TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showCategorySheet(
    BuildContext context,
    WidgetRef ref,
    Category? existing,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategorySheet(existing: existing, ref: ref),
    );
  }
}

// ── Category tile ────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final Category cat;
  final WidgetRef ref;

  const _CategoryTile({required this.cat, required this.ref});

  @override
  Widget build(BuildContext context) {
    final color = Color(cat.colorValue);
    return Dismissible(
      key: ValueKey(cat.id),
      direction: cat.isSystem
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.archive_rounded, color: Colors.redAccent),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Archive category?',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Existing entries keep their category. '
              '"${cat.name}" will no longer appear in the picker.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Archive',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) =>
          ref.read(appDatabaseProvider).categoriesDao.archive(cat.id),
      child: GestureDetector(
        onTap: () => CategoriesScreen._showCategorySheet(context, ref, cat),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 8)
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  cat.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (cat.isSystem)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('system',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 11)),
                )
              else
                const Icon(Icons.edit_rounded,
                    color: Colors.white30, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Create / edit sheet ──────────────────────────────────────────────────────

class _CategorySheet extends StatefulWidget {
  final Category? existing;
  final WidgetRef ref;

  const _CategorySheet({this.existing, required this.ref});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _nameCtrl;
  late int _selectedColor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedColor =
        widget.existing?.colorValue ?? _kPresetColors.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final dao = widget.ref.read(appDatabaseProvider).categoriesDao;
    if (widget.existing == null) {
      await dao.insertCategory(CategoriesCompanion.insert(
        name: name,
        colorValue: _selectedColor,
      ));
    } else {
      await dao.updateCategory(CategoriesCompanion(
        id: Value(widget.existing!.id),
        name: Value(name),
        colorValue: Value(_selectedColor),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForHour(DateTime.now().hour);
    final isEdit = widget.existing != null;
    final isSystem = widget.existing?.isSystem ?? false;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEdit ? 'Edit Category' : 'New Category',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            // Name field
            TextField(
              controller: _nameCtrl,
              enabled: !isSystem,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            const Text('Color',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            // Color grid
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _kPresetColors.map((c) {
                final selected = c == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color:
                                      Color(c).withValues(alpha: 0.6),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || isSystem ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        isEdit ? 'Save Changes' : 'Create Category',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
