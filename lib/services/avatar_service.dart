import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarProfile {
  final String? imagePath;
  final String iconKey;

  const AvatarProfile({
    required this.imagePath,
    required this.iconKey,
  });

  bool get hasImage => imagePath != null && imagePath!.trim().isNotEmpty;
}

class AvatarService {
  AvatarService._();

  static const String _kImagePath = 'setting_avatar_image_path';
  static const String _kIconKey = 'setting_avatar_icon_key';

  static Future<AvatarProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString(_kImagePath);
    final iconKey = prefs.getString(_kIconKey) ?? 'cat';

    if (imagePath != null && imagePath.trim().isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) {
        return AvatarProfile(imagePath: imagePath, iconKey: iconKey);
      }
      await prefs.remove(_kImagePath);
    }

    return AvatarProfile(imagePath: null, iconKey: iconKey);
  }

  static Future<void> saveIcon(String iconKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIconKey, iconKey);
    await prefs.remove(_kImagePath);
  }

  static Future<void> savePickedImage(XFile pickedFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(appDir.path, 'avatars'));
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }

    final ext = p.extension(pickedFile.path).toLowerCase();
    final safeExt = ext.isEmpty ? '.jpg' : ext;
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final target = File(p.join(avatarDir.path, fileName));
    await File(pickedFile.path).copy(target.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kImagePath, target.path);
  }

  static Future<void> clearImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kImagePath);
  }
}
