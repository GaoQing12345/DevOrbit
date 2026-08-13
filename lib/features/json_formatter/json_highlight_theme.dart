import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

const _jsonWarmRed = TextStyle(color: Color(0xFFA31515));

final jsonAtomOneLightTheme = <String, TextStyle>{
  ...atomOneLightTheme,
  'attr': _jsonWarmRed,
  'variable': _jsonWarmRed,
  'template-variable': _jsonWarmRed,
  'type': _jsonWarmRed,
  'selector-class': _jsonWarmRed,
  'selector-attr': _jsonWarmRed,
  'selector-pseudo': _jsonWarmRed,
  'number': _jsonWarmRed,
};

CodeEditorStyle buildJsonEditorStyle({
  required bool isDark,
  required Color cursorLineColor,
}) {
  return CodeEditorStyle(
    fontSize: 14,
    fontHeight: 1.55,
    fontFamily: 'Menlo',
    fontFamilyFallback: const ['Consolas', 'monospace'],
    backgroundColor: isDark ? const Color(0xFF111715) : const Color(0xFFFBFCFC),
    cursorLineColor: cursorLineColor,
    codeTheme: CodeHighlightTheme(
      languages: {'json': CodeHighlightThemeMode(mode: langJson)},
      theme: isDark ? atomOneDarkTheme : jsonAtomOneLightTheme,
    ),
  );
}
