import 'package:flutter/foundation.dart';

/// Логи лише в debug-збірці; у release не викликається (tree-shaking + kDebugMode).
void appLog(String message, [Object? error, StackTrace? stack]) {
  if (!kDebugMode) return;
  if (error != null) {
    debugPrint('$message: $error');
    if (stack != null) debugPrint(stack.toString());
  } else {
    debugPrint(message);
  }
}
