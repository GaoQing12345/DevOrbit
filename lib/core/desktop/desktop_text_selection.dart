import 'package:flutter/foundation.dart';

/// A UTF-16 selection shared with the browser editor bridge.
@immutable
class NativeTextSelection {
  const NativeTextSelection({
    required this.baseOffset,
    required this.extentOffset,
  });

  final int baseOffset;
  final int extentOffset;

  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;

  @override
  bool operator ==(Object other) {
    return other is NativeTextSelection &&
        other.baseOffset == baseOffset &&
        other.extentOffset == extentOffset;
  }

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);
}
