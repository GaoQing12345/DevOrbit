import 'package:flutter/material.dart';
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
