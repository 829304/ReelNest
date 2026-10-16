import 'dart:async';

/// A child engine can retire its reply channel while closing its native window.
/// Observe the window's disappearance instead of waiting out the IPC timeout.
/// A negative reply means the user kept the player open (e.g. a failed save).
Future<bool> requestChildWindowClose({
  required Future<Object?> Function() request,
  required Future<bool> Function() exists,
  void Function(Object, StackTrace)? onError,
  Duration budget = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  var declined = false;
  final deadline = Stopwatch()..start();
  unawaited(
    Future<Object?>.sync(request).then<void>(
      (result) {
        declined = result == false;
      },
      onError: (Object error, StackTrace stack) {
        // A disappearing engine may never acknowledge close; its HWND inventory is
        // authoritative. Handle late failures even after this helper has returned.
        onError?.call(error, stack);
      },
    ),
  );
  while (true) {
    if (!await exists()) return true;
    if (declined || deadline.elapsed >= budget) return false;
    await Future<void>.delayed(pollInterval);
  }
}
