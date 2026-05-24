import 'package:flutter/foundation.dart';

void appLog(String message, [Object? error, StackTrace? stack]) {
  if (!kDebugMode) return;
  if (error != null) {
    debugPrint('$message: $error');
    if (stack != null) debugPrint(stack.toString());
  } else {
    debugPrint(message);
  }
}
