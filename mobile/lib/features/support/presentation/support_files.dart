import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../messaging/data/chat_media.dart' show pickChatPhotos;
import '../data/support_repository.dart';

/// Image (compressed on the phone, metadata removed) or PDF, ≤ 10 MB, ≤ 3 per message.
Future<List<PickedFile>> pickSupportFiles(BuildContext context, {required int room}) async {
  final l = AppLocalizations.of(context);
  if (room <= 0) {
    showToast(context, l.supportMaxFiles('$kTicketFilesPerMessage'));
    return const [];
  }
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(l.attachPhoto), onTap: () => Navigator.pop(c, 'photo')),
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(l.attachCamera), onTap: () => Navigator.pop(c, 'camera')),
        ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(l.attachPdf), onTap: () => Navigator.pop(c, 'pdf')),
      ]),
    ),
  );
  if (kind == null) return const [];
  final out = <PickedFile>[];
  if (kind == 'pdf') {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], allowMultiple: true, withData: true);
    for (final f in (r?.files ?? const <PlatformFile>[]).take(room)) {
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) continue;
      if (bytes.length > kTicketFileMax) {
        if (context.mounted) showToast(context, l.supportFileTooLarge);
        continue;
      }
      out.add(PickedFile(name: f.name, mime: 'application/pdf', bytes: bytes));
    }
  } else {
    final photos = await pickChatPhotos(max: room, camera: kind == 'camera');
    for (final (i, p) in photos.indexed) {
      out.add(PickedFile(name: 'image_${DateTime.now().millisecondsSinceEpoch}_$i.jpg', mime: 'image/jpeg', bytes: Uint8List.fromList(p.bytes)));
    }
  }
  return out;
}

String fileSize(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// Picked files shown above the composer, removable before sending.
class PickedFilesStrip extends StatelessWidget {
  const PickedFilesStrip({super.key, required this.files, required this.onRemove});
  final List<PickedFile> files;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(start: 12, end: 12, top: 8),
        itemCount: files.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = files[i];
          return Stack(clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: OlfaRadius.all(12),
              child: SizedBox.square(
                dimension: 62,
                child: f.mime.startsWith('image/')
                    ? Image.memory(f.bytes, fit: BoxFit.cover)
                    : ColoredBox(color: OlfaColors.gray, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.picture_as_pdf_outlined, color: OlfaColors.primary), Text(fileSize(f.bytes.length), style: context.type.caption)])),
              ),
            ),
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Semantics(
                button: true,
                label: l.remove,
                child: InkWell(
                  onTap: () => onRemove(i),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: OlfaColors.black, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 15, color: OlfaColors.white),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
