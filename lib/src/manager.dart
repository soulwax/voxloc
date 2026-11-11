import 'table.dart';

/// Runtime locale state controller wrapping [LocalizationTable], active/fallback
/// resolution, missing-key telemetry, and reactive language-switch listeners.
final class LocalizationManager {
  final LocalizationTable table;
  LocaleCode _activeLocale;
  LocaleCode _fallbackLocale;

  final List<void Function(String newLocale)> _listeners = [];
  final Set<String> _missingKeys = {};

  String Function(String locale, String key)? onMissingKey;

  LocalizationManager({
    LocalizationTable? table,
    String activeLocale = 'en',
    String fallbackLocale = 'en',
    this.onMissingKey,
  })  : table = table ?? LocalizationTable(),
        _activeLocale = LocaleCode.parse(activeLocale),
        _fallbackLocale = LocaleCode.parse(fallbackLocale);

  String get activeLocale => _activeLocale.tag;
  String get fallbackLocale => _fallbackLocale.tag;
  List<String> get fallbackChain =>
      _activeLocale.fallbackChain(_fallbackLocale.tag);
  Set<String> get missingKeys => Set.unmodifiable(_missingKeys);

  bool setLocale(String localeTag) {
    final next = LocaleCode.parse(localeTag);
    if (next.tag == _activeLocale.tag) return false;
    _activeLocale = next;
    for (final listener in List.of(_listeners)) {
      listener(next.tag);
    }
    return true;
  }

  void setFallbackLocale(String localeTag) {
    _fallbackLocale = LocaleCode.parse(localeTag);
  }

  /// Subscribes to active locale changes and returns an unsubscribe closure.
  void Function() addLocaleListener(void Function(String newLocale) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  String tr(
    String key, {
    String? localeOverride,
    Map<String, Object?> params = const {},
    String? defaultValue,
  }) {
    final chain = localeOverride != null
        ? LocaleCode.parse(localeOverride).fallbackChain(_fallbackLocale.tag)
        : fallbackChain;
    final res = table.resolveRaw(key, chain: chain);
    if (res.text != null) {
      return LocalizationTable.format(res.text!, params);
    }
    final locTag = localeOverride ?? activeLocale;
    _missingKeys.add('$locTag:$key');
    final hook = onMissingKey;
    if (hook != null) return hook(locTag, key);
    return defaultValue ?? key;
  }

  String trPlural(
    String key,
    num count, {
    String? localeOverride,
    Map<String, Object?> params = const {},
    String? defaultValue,
  }) {
    final merged = <String, Object?>{'count': count, ...params};
    final chain = localeOverride != null
        ? LocaleCode.parse(localeOverride).fallbackChain(_fallbackLocale.tag)
        : fallbackChain;
    final res = table.resolveRaw(key, chain: chain, pluralCount: count);
    if (res.text != null) {
      return LocalizationTable.format(res.text!, merged);
    }
    final locTag = localeOverride ?? activeLocale;
    _missingKeys.add('$locTag:$key');
    final hook = onMissingKey;
    if (hook != null) return hook(locTag, key);
    return defaultValue ?? key;
  }

  void clearMissingKeys() => _missingKeys.clear();
}
