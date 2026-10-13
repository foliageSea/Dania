import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import 'models.dart';
import 'toolbox_client.dart';

final shizukuProvider = FutureProvider<ShizukuStatus>(
  (ref) => ref.watch(toolboxProvider).status(),
);

final devicesProvider = AsyncNotifierProvider<DevicesController, List<Device>>(
  DevicesController.new,
);

class DevicesController extends AsyncNotifier<List<Device>> {
  @override
  Future<List<Device>> build() => ref.watch(toolboxProvider).devices();
  Future<void> refresh() async {
    final client = ref.read(toolboxProvider);
    final value = await client.devices();
    if (ref.mounted) state = AsyncData(value);
  }
}

final selectedDeviceProvider = NotifierProvider<SelectedDevice, String?>(
  SelectedDevice.new,
);

class SelectedDevice extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final activeDeviceProvider = Provider<Device?>((ref) {
  final devices = ref.watch(devicesProvider).asData?.value ?? [];
  final selected = ref.watch(selectedDeviceProvider);
  for (final device in devices) {
    if (device.id == selected) return device;
  }
  return null;
});

final toolboxEventsProvider = Provider<void>((ref) {
  final subscription = ref
      .watch(toolboxProvider)
      .events
      .listen(
        (event) {
          if (event['type'] == 'shizuku') ref.invalidate(shizukuProvider);
          if (event['type'] == 'devices' || event['type'] == 'shizuku') {
            unawaited(
              ref
                  .read(devicesProvider.notifier)
                  .refresh()
                  .catchError((Object _) {}),
            );
          }
        },
        onError: (Object _) {
          ref.invalidate(shizukuProvider);
        },
      );
  ref.onDispose(subscription.cancel);
});

class SavedEndpoint {
  const SavedEndpoint(this.host, this.port);
  final String host;
  final int port;
  String get address => '$host:$port';
  Map<String, Object> toJson() => {'host': host, 'port': port};
}

final endpointsProvider =
    AsyncNotifierProvider<EndpointsController, List<SavedEndpoint>>(
      EndpointsController.new,
    );

class EndpointsController extends AsyncNotifier<List<SavedEndpoint>> {
  static const _key = 'dania.endpoints.v1';
  @override
  Future<List<SavedEndpoint>> build() async {
    final raw = await ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (value) => SavedEndpoint(
              value['host'] as String,
              (value['port'] as num).toInt(),
            ),
          )
          .where(
            (value) =>
                value.host.isNotEmpty && value.port > 0 && value.port <= 65535,
          )
          .take(10)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(SavedEndpoint endpoint) async {
    final current = state.asData?.value ?? await future;
    final next = [
      endpoint,
      ...current.where((item) => item.address != endpoint.address),
    ].take(10).toList();
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(next.map((item) => item.toJson()).toList()),
        );
    if (ref.mounted) state = AsyncData(next);
  }

  Future<void> remove(SavedEndpoint endpoint) async {
    final next = (state.asData?.value ?? [])
        .where((item) => item.address != endpoint.address)
        .toList();
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(next.map((item) => item.toJson()).toList()),
        );
    if (ref.mounted) state = AsyncData(next);
  }
}
