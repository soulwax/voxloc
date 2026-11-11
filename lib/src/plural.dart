/// Grammatical plural categories modeled after Unicode CLDR.
enum PluralCategory {
  zero,
  one,
  two,
  few,
  many,
  other,
}

typedef PluralSelector = PluralCategory Function(num count);

/// Built-in & extensible cardinal plural-form selectors indexed by ISO 639-1 language code.
final class PluralRules {
  static final Map<String, PluralSelector> _customRules = {};

  static void registerRule(String languageCode, PluralSelector selector) {
    _customRules[_normalizeLang(languageCode)] = selector;
  }

  static void clearCustomRules() => _customRules.clear();

  static String _normalizeLang(String localeOrLang) {
    final normalized = localeOrLang.trim().replaceAll('_', '-').toLowerCase();
    final idx = normalized.indexOf('-');
    return idx == -1 ? normalized : normalized.substring(0, idx);
  }

  /// Resolves the plural category for [count] under [localeOrLang].
  static PluralCategory select(String localeOrLang, num count) {
    final lang = _normalizeLang(localeOrLang);
    final custom = _customRules[lang];
    if (custom != null) return custom(count);

    final absVal = count.abs();
    final isInt = absVal == absVal.truncateToDouble();
    final n = absVal.truncate();

    switch (lang) {
      case 'ja':
      case 'zh':
      case 'ko':
      case 'vi':
      case 'th':
      case 'id':
        return PluralCategory.other;

      case 'fr':
      case 'hi':
        // French: 0 and 1 are singular
        if (absVal >= 0 && absVal < 2 && isInt) return PluralCategory.one;
        return PluralCategory.other;

      case 'ru':
      case 'uk':
      case 'sr':
      case 'hr':
        if (!isInt) return PluralCategory.other;
        final mod10 = n % 10;
        final mod100 = n % 100;
        if (mod10 == 1 && mod100 != 11) return PluralCategory.one;
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
          return PluralCategory.few;
        }
        return PluralCategory.many;

      case 'pl':
        if (!isInt) return PluralCategory.other;
        if (n == 1) return PluralCategory.one;
        final mod10 = n % 10;
        final mod100 = n % 100;
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
          return PluralCategory.few;
        }
        return PluralCategory.many;

      case 'ar':
        if (!isInt) return PluralCategory.other;
        if (n == 0) return PluralCategory.zero;
        if (n == 1) return PluralCategory.one;
        if (n == 2) return PluralCategory.two;
        final mod100 = n % 100;
        if (mod100 >= 3 && mod100 <= 10) return PluralCategory.few;
        if (mod100 >= 11 && mod100 <= 99) return PluralCategory.many;
        return PluralCategory.other;

      default:
        // Germanic/Romance standard (en, de, es, it, pt, nl, etc.)
        return (isInt && n == 1) ? PluralCategory.one : PluralCategory.other;
    }
  }
}
