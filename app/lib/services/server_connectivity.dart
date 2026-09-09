import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'settings_store.dart';

final serverReachableProvider =
    StateNotifierProvider<ServerReachabilityNotifier, bool>((ref) {
  return ServerReachabilityNotifier(ref);
});

class ServerReachabilityNotifier extends StateNotifier<bool> {
  ServerReachabilityNotifier(this.ref) : super(false);

  final Ref ref;

  Future<bool> refresh() async {
    if (!ref.read(settingsStoreProvider).hasServerUrl) {
      state = false;
      return false;
    }
    final up = await ref.read(apiProvider).ping();
    state = up;
    return up;
  }
}

Future<bool> ensureServerReachable(WidgetRef ref) async {
  if (ref.read(serverReachableProvider)) return true;
  return ref.read(serverReachableProvider.notifier).refresh();
}
