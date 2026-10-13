import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'toolbox_client.dart';

Future<File> stageSelectedFile(XFile selected) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/dania-upload-${newOperationId()}');
  try {
    await selected.saveTo(file.path);
    return file;
  } catch (_) {
    if (await file.exists()) await file.delete();
    rethrow;
  }
}
