class TranslationLanguage {
  const TranslationLanguage(this.code, this.label);

  final String code;
  final String label;
}

const translationLanguages = <TranslationLanguage>[
  TranslationLanguage('ZH-HANS', '简体中文'),
  TranslationLanguage('ZH-HANT', '繁体中文'),
  TranslationLanguage('EN-US', '英语（美式）'),
  TranslationLanguage('EN-GB', '英语（英式）'),
  TranslationLanguage('JA', '日语'),
  TranslationLanguage('KO', '韩语'),
  TranslationLanguage('DE', '德语'),
  TranslationLanguage('FR', '法语'),
  TranslationLanguage('ES', '西班牙语'),
  TranslationLanguage('IT', '意大利语'),
  TranslationLanguage('PT-BR', '葡萄牙语（巴西）'),
  TranslationLanguage('RU', '俄语'),
];

String translationLanguageLabel(String code) {
  for (final language in translationLanguages) {
    if (language.code == code) return language.label;
  }
  return switch (code) {
    'ZH' => '中文',
    'EN' => '英语',
    'JA' => '日语',
    'KO' => '韩语',
    'DE' => '德语',
    'FR' => '法语',
    'ES' => '西班牙语',
    'IT' => '意大利语',
    'PT' => '葡萄牙语',
    'RU' => '俄语',
    _ => code,
  };
}

String? sourceCodeFor(String targetCode) {
  if (targetCode.startsWith('EN-')) return 'EN';
  if (targetCode.startsWith('ZH-')) return 'ZH';
  return targetCode;
}

String targetCodeForDetectedSource(String sourceCode) {
  switch (sourceCode) {
    case 'EN':
      return 'EN-US';
    case 'ZH':
      return 'ZH-HANS';
    default:
      return sourceCode;
  }
}
