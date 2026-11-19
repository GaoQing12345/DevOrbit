import 'package:material_ui/material_ui.dart';
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
  required Color textColor,
  required Color cursorLineColor,
  Color? selectionColor,
  Color? cursorColor,
  Color? backgroundColor,
}) {
  return CodeEditorStyle(
    fontSize: 14,
    fontHeight: 1.55,
    fontFamily: 'Menlo',
    fontFamilyFallback: const ['Consolas', 'monospace'],
    backgroundColor:
        backgroundColor ??
        (isDark ? const Color(0xFF111715) : const Color(0xFFFBFCFC)),
    // re_editor still builds against the bundled material library, so its own
    // `Theme.of` never sees this app's MaterialUi theme and would fall back to
    // a light default. Every colour the editor draws with is passed in
    // explicitly instead.
    textColor: textColor,
    selectionColor: selectionColor ?? cursorColor,
    cursorColor: cursorColor,
    cursorLineColor: cursorLineColor,
    codeTheme: CodeHighlightTheme(
      languages: {'json': CodeHighlightThemeMode(mode: langJson)},
      theme: isDark ? atomOneDarkTheme : jsonAtomOneLightTheme,
    ),
  );
}
