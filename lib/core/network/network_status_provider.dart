import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> checkHasNetwork() async {
  try {
    final result = await InternetAddress.lookup('one.one.one.one')
        .timeout(const Duration(seconds: 2));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

final hasNetworkProvider = StreamProvider<bool>((ref) async* {
  yield await checkHasNetwork();
  await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
    yield await checkHasNetwork();
  }
});

bool isOnlineOnlyFeatureAvailable({
  required bool hasNetwork,
  bool offlineNavigation = false,
}) =>
    hasNetwork && !offlineNavigation;

bool isWeatherAvailable({
  required bool hasNetwork,
  bool offlineNavigation = false,
}) =>
    isOnlineOnlyFeatureAvailable(
      hasNetwork: hasNetwork,
      offlineNavigation: offlineNavigation,
    );
