import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

final toolboxProvider = Provider<ToolboxClient>((ref) => ToolboxClient());

class ToolboxException implements Exception {
  const ToolboxException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class ToolboxClient {
  static const _methods = MethodChannel('dania/toolbox');
  static const _events = EventChannel('dania/toolbox/events');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Stream<Map<Object?, Object?>>? _stream;
  Stream<Map<Object?, Object?>> get events => _stream ??= supported
      ? _events
            .receiveBroadcastStream()
            .map((value) => Map<Object?, Object?>.from(value as Map))
            .asBroadcastStream()
      : const Stream.empty();

  Future<T?> invoke<T>(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    if (!supported)
      throw const ToolboxException('unsupported', 'Android is required');
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ToolboxException(error.code, error.message ?? error.code);
    } on MissingPluginException {
      throw const ToolboxException(
        'unavailable',
        'Android toolbox is unavailable',
      );
    }
  }

  Future<ShizukuStatus> status() async => supported
      ? ShizukuStatus.fromMap((await invoke<Map>('status'))!)
      : const ShizukuStatus(supported: false);
  Future<List<Device>> devices() async => supported
      ? (await invoke<List>('devices'))!
            .map((value) => Device.fromMap(value as Map))
            .toList()
      : [];
  Future<void> authorize() => invoke<void>('authorize');
  Future<void> openShizuku() => invoke<void>('openShizuku');
  Future<String> connectLocal() async =>
      (await invoke<String>('connectLocal'))!;
  Future<void> pair(String host, int port, String code) =>
      invoke<void>('pair', {'host': host, 'pairPort': port, 'code': code});
  Future<String> connect(String host, int port) async =>
      (await invoke<String>('connect', {'host': host, 'port': port}))!;
  Future<void> disconnect(String id) =>
      invoke<void>('disconnect', {'deviceId': id});
  Future<String> info(String id) async =>
      (await invoke<String>('info', {'deviceId': id}))!;
  Future<void> command(String device, String id, String command) =>
      invoke<void>('command', {
        'deviceId': device,
        'operationId': id,
        'command': command,
      });
  Future<void> cancel(String id) => invoke<void>('cancel', {'operationId': id});
  Future<List<InstalledApp>> apps(String id) async => (await invoke<List>(
    'apps',
    {'deviceId': id},
  ))!.map((value) => InstalledApp.fromMap(value as Map)).toList();
  Future<String> appAction(
    String id,
    String packageName,
    String action, {
    String? permission,
  }) async => (await invoke<String>('appAction', {
    'deviceId': id,
    'packageName': packageName,
    'action': action,
    if (permission != null) 'permission': permission,
  }))!;
  Future<List<RemoteFile>> files(String id, String path) async =>
      (await invoke<List>('files', {
        'deviceId': id,
        'path': path,
      }))!.map((value) => RemoteFile.fromMap(value as Map)).toList();
  Future<void> fileAction(
    String id,
    String path,
    String action, {
    String? destination,
  }) => invoke<void>('fileAction', {
    'deviceId': id,
    'path': path,
    'action': action,
    if (destination != null) 'destination': destination,
  });
  Future<void> upload(
    String device,
    String operation,
    String local,
    String remote,
  ) => invoke<void>('upload', {
    'deviceId': device,
    'operationId': operation,
    'localPath': local,
    'path': remote,
  });
  Future<String> download(
    String device,
    String operation,
    String remote,
  ) async => (await invoke<String>('download', {
    'deviceId': device,
    'operationId': operation,
    'path': remote,
  }))!;
  Future<bool> exportFile(String path, String name) async =>
      (await invoke<bool>('exportFile', {'localPath': path, 'name': name}))!;
  Future<String> install(String device, String operation, String local) async =>
      (await invoke<String>('install', {
        'deviceId': device,
        'operationId': operation,
        'localPath': local,
      }))!;
  Future<MirrorInfo> startMirror(
    String device, {
    required String mirrorId,
    int maxSize = 1280,
    int bitRate = 4000000,
  }) async => MirrorInfo.fromMap(
    (await invoke<Map>('startMirror', {
      'deviceId': device,
      'mirrorId': mirrorId,
      'maxSize': maxSize,
      'bitRate': bitRate,
    }))!,
  );
  Future<void> stopMirror(String device, {String? mirrorId}) => invoke<void>(
    'stopMirror',
    {'deviceId': device, if (mirrorId != null) 'mirrorId': mirrorId},
  );
  Future<void> mirrorTouch(
    String device, {
    required int action,
    required int pointer,
    required int x,
    required int y,
    required int width,
    required int height,
  }) => invoke<void>('mirrorTouch', {
    'deviceId': device,
    'action': action,
    'pointer': pointer,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  });
  Future<void> mirrorKey(String device, int key) =>
      invoke<void>('mirrorKey', {'deviceId': device, 'keyCode': key});
  Future<void> resetIdentity() => invoke<void>('resetIdentity');
}

int _sequence = 0;
String newOperationId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
