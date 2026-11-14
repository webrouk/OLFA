import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

typedef PickedPhoto = ({Uint8List bytes, String mimeType});

/// Picks and compresses a photo on-device (≤2048 px, JPEG ~85%) before upload,
/// so originals stay small and full-resolution files never leave the phone.
class PhotoPicker {
  final _picker = ImagePicker();

  Future<PickedPhoto?> pick() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85, requestFullMetadata: false);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final name = x.name.toLowerCase();
    final mime = x.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : name.endsWith('.heic')
                    ? 'image/heic'
                    : 'image/jpeg');
    return (bytes: bytes, mimeType: mime);
  }
}

final photoPickerProvider = Provider<PhotoPicker>((_) => PhotoPicker());
