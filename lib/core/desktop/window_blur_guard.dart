typedef WindowFocusProbe = Future<bool> Function();

class WindowBlurGuard {
  WindowBlurGuard({
    required this.isFocused,
    this.settleDelay = const Duration(milliseconds: 120),
  });

  final WindowFocusProbe isFocused;
  final Duration settleDelay;

  int _generation = 0;

  void handleFocus() {
    _generation++;
  }

  Future<bool> shouldDismissAfterBlur() async {
    final generation = ++_generation;
    await Future<void>.delayed(settleDelay);
    if (generation != _generation) return false;

    final focused = await isFocused();
    return generation == _generation && !focused;
  }
}
