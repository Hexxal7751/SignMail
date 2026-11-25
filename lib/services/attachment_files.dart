import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saving and opening downloaded attachments on Android, Windows and Linux.
class AttachmentFiles {
  const AttachmentFiles._();

  static String safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  static Future<String> _writeTemp(String name, Uint8List bytes) async {
    final base = await getTemporaryDirectory();
    final folder = Directory(
      '${base.path}${Platform.pathSeparator}signmail_attachments',
    );
    await folder.create(recursive: true);

    final file = File('${folder.path}${Platform.pathSeparator}${safeName(name)}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Opens the file in another app. Returns an error text, or null on success.
  static Future<String?> open(String name, Uint8List bytes) async {
    final path = await _writeTemp(name, bytes);
    final result = await OpenFilex.open(path);

    if (result.type == ResultType.done) {
      return null;
    }
    return result.message.isEmpty
        ? 'No app was found that can open this file.'
        : result.message;
  }

  /// Lets the user pick where to keep the file. Returns false if cancelled.
  static Future<bool> save(String name, Uint8List bytes) async {
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attachment',
      fileName: safeName(name),
      bytes: bytes,
    );

    if (target == null) {
      return false;
    }

    // Phones write the bytes themselves; desktop only returns the path.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(target).writeAsBytes(bytes, flush: true);
    }
    return true;
  }
}