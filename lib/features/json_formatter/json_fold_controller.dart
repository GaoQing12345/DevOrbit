import 'package:re_editor/re_editor.dart';

class JsonFoldController {
  static const _operationLimit = 10000;

  CodeLineEditingController? _editor;
  CodeChunkController? _chunks;

  void attach(CodeLineEditingController editor, CodeChunkController chunks) {
    _editor = editor;
    _chunks = chunks;
  }

  void collapseAll() {
    final chunks = _chunks;
    if (chunks == null) return;
    for (var count = 0; count < _operationLimit; count++) {
      final collapsible = chunks.value.where((chunk) => chunk.canCollapse);
      if (collapsible.isEmpty) return;
      chunks.collapse(collapsible.last.index);
    }
  }

  void expandAll() {
    final editor = _editor;
    final chunks = _chunks;
    if (editor == null || chunks == null) return;
    for (var count = 0; count < _operationLimit; count++) {
      final index = _firstCollapsedIndex(editor);
      if (index == null) return;
      chunks.expand(index);
    }
  }

  int? _firstCollapsedIndex(CodeLineEditingController editor) {
    for (var index = 0; index < editor.codeLines.length; index++) {
      if (editor.codeLines[index].chunkParent) return index;
    }
    return null;
  }
}
