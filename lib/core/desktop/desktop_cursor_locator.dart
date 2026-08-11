import 'dart:io';

import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';

abstract interface class DesktopCursorLocator {
  Future<Offset> getPosition();
}

class NativeDesktopCursorLocator implements DesktopCursorLocator {
  NativeDesktopCursorLocator({
    MethodChannel? channel,
    bool? isMacOS,
    Future<Offset> Function()? fallback,
  }) : _channel = channel ?? const MethodChannel('dev_orbit/cursor'),
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _fallback = fallback ?? screenRetriever.getCursorScreenPoint;

  final MethodChannel _channel;
  final bool _isMacOS;
  final Future<Offset> Function() _fallback;

  @override
  Future<Offset> getPosition() async {
    if (!_isMacOS) return _fallback();
    final point = await _channel.invokeMapMethod<String, dynamic>(
      'getCursorScreenPoint',
    );
    if (point == null) throw StateError('macOS cursor position is unavailable');
    return Offset(
      (point['dx'] as num).toDouble(),
      (point['dy'] as num).toDouble(),
    );
  }
}
