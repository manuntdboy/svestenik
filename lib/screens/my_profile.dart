import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'my_profile_edit.dart';

final _fmtFull = DateFormat('d MMMM y', 'bg');
final _fmtDayMonth = DateFormat('d MMMM', 'bg');

String fmtDateFull(DateTime? d) => d == null ? 'Не е попълнено' : '${_fmtFull.format(d)} г.';

String fmtNameDay(ProfileDetails d) => d.hasNameDay
    ? _fmtDayMonth.format(DateTime(2000, d.nameDayMonth!, d.nameDayDay!))
    : 'Не е попълнено';

String daysLabel(int n) => n == 0
    ? 'днес'
    : n == 1
        ? 'утре'
        : 'след $n дни';

/// Избор на снимка от галерията или камерата и качване.
Future<void> pickAndUploadPhoto(BuildContext context) async {
  final s = AppScope.read(context);
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Избери от снимките', style: TextStyle(fontSize: 18)),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Снимай с камерата', style: TextStyle(fontSize: 18)),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        if (s.myPhoto != null)
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Премахни снимката', style: TextStyle(fontSize: 18)),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null || !context.mounted) return;
  try {
    if (source == 'remove') {
      await s.removePhoto();
      if (context.mounted) showMessage(context, 'Снимката е премахната.');
      return;
    }
    // Android показва своя избор на снимки – приложението вижда само
    // снимката, която изберете, без достъп до цялата галерия.
    final file = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (context.mounted) showMessage(context, 'Качване на снимката…');
    await s.uploadPhoto(bytes);
    if (context.mounted) showMessage(context, 'Снимката е сменена.');
  } on AppError catch (e) {
    if (context.mounted) showMessage(context, e.message);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Снимката не може да се отвори: $e');
  }
}

/// Кръгла снимка на профила (или празен силует).
class ProfilePhoto extends StatelessWidget {
  final double size;
  const ProfilePhoto({super.key, this.size = 132});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final photo = s.myPhoto;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.dark ? const Color(0xFF2A323B) : const Color(0xFFDCE3EA),
        border: Border.all(color: p.primary, width: 3),
        image: photo == null
            ? null
            : DecorationImage(image: MemoryImage(photo), fit: BoxFit.cover),
      ),
      child: photo == null
          ? Icon(Icons.person_outline_rounded, size: size * 0.5, color: p.textMuted)
          : null,
    );
  }
}

/// „Моят профил“ – по макета „Профил на свещеника“.
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final d = s.myDetails;
    final church = s.currentChurch;
    final role = church == null
        ? 'Свещеник'
        : s.isManagerOf(church.id)
            ? 'Председател'
            : (s.canSeeCash(church.id) ? 'Свещеник · касиер' : 'Свещеник');
    final days = d.daysToNameDay();
    final name = withRank(s.currentUser?.rank,
        d.threeNames.trim().isNotEmpty ? d.threeNames : (s.currentUser?.name ?? ''));

    Widget row(IconData icon, Color iconBg, Color iconFg, String label, String value,
            {Widget? trailing}) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconFg, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: p.textMuted)),
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (trailing != null) trailing,
            ]),
          ),
        );

    final blueBg = p.primary.withValues(alpha: p.dark ? 0.16 : 0.12);
    final yellowBg = Palette.yellow.withValues(alpha: p.dark ? 0.18 : 0.28);
    final yellowFg = p.dark ? Palette.yellow : const Color(0xFF7A5C00);
    Widget divider() => Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: p.border);

    return Scaffold(
      appBar: AppBar(title: const Text('Моят профил'), centerTitle: true),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                Center(
                  child: SizedBox(
                    width: 132,
                    height: 132,
                    child: Stack(clipBehavior: Clip.none, children: [
                      const ProfilePhoto(),
                      Positioned(
                        right: -2,
                        bottom: 2,
                        child: Material(
                          color: p.primary,
                          shape: CircleBorder(side: BorderSide(color: p.bg, width: 3)),
                          child: IconButton(
                            tooltip: 'Смени снимката',
                            onPressed: () => pickAndUploadPhoto(context),
                            icon: Icon(Icons.photo_camera_outlined, color: p.onPrimary, size: 22),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name.isEmpty ? 'Добавете трите си имена' : name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(role,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: p.textMuted)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(children: [
                    row(Icons.cake_outlined, blueBg, p.primary, 'Дата на раждане',
                        fmtDateFull(d.birthDate)),
                    divider(),
                    row(Icons.add_rounded, yellowBg, yellowFg, 'Дата на ръкоположение',
                        fmtDateFull(d.ordinationDate)),
                    divider(),
                    row(Icons.star_outline_rounded, blueBg, p.primary, 'Имен ден', fmtNameDay(d),
                        trailing: days == null
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: blueBg, borderRadius: BorderRadius.circular(12)),
                                child: Text(daysLabel(days),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: p.primary)),
                              )),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('Тези данни виждате само вие.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: p.textMuted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: FilledButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const MyProfileEditScreen())),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Редактирай профила'),
            ),
          ),
        ]),
      ),
    );
  }
}
