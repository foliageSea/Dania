import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';
import 'core/logging.dart';
import 'core/settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLogging();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger('main').severe('Flutter error', details.exception, details.stack);
  };
  final bootstrap = ProviderContainer();
  AppSettings settings;
  try {
    settings = await bootstrap.read(settingsRepositoryProvider).load();
  } catch (_) {
    settings = const AppSettings();
  }
  bootstrap.dispose();
  runApp(
    ProviderScope(
      overrides: [initialSettingsProvider.overrideWithValue(settings)],
      child: const DaniaApp(),
    ),
  );
}
