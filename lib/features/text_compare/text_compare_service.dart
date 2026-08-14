import 'dart:isolate';

import 'text_compare_engine.dart';
import 'text_compare_models.dart';

abstract interface class TextCompareService {
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  });
}

class IsolateTextCompareService implements TextCompareService {
  const IsolateTextCompareService();

  @override
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) {
    return Isolate.run(
      () => const TextCompareEngine().compare(
        left: left,
        right: right,
        options: options,
      ),
    );
  }
}
