import 'dart:convert';
import 'plural.dart';

/// Parsed BCP-47 style locale tag (`language[-Region]`).
final class LocaleCode {
  final String tag;
  final String language;
  final String? region;

  LocaleCode._(this.tag, this.language, this.region);

  factory LocaleCode.parse(String raw) {
    final cleaned = raw.trim().replaceAll('_', '-');
    if (cleaned.isEmpty) {
      return LocaleCode._('en', 'en', null);
    }
    final parts = cleaned.split('-');
    final lang = parts.first.toLowerCase();
    final region = parts.length > 1 && parts[1].isNotEmpty
        ? parts[1].toUpperCase()
        : null;
    final tag = region == null ? lang : '$lang-$region';
    return LocaleCode._(tag, lang, region);
  }

  /// Ordered lookup chain: `['pt-BR', 'pt', 'en']` when `fallback = 'en'`.
  List<String> fallbackChain([String fallbackTag = 'en']) {
    final chain = <String>[tag];
    if (region != null && !chain.contains(language)) {
      chain.add(language);
    }
    final fb = LocaleCode.parse(fallbackTag);
    if (!chain.contains(fb.tag)) chain.add(fb.tag);
    if (fb.region != null && !chain.contains(fb.language)) {
      chain.add(fb.language);
    }
    return chain;
  }

  @override
  String toString() => tag;
}

/// Holds localized translation entries per locale, supporting nested keys,
/// plural maps, parameter interpolation, CSV/JSON import, and glyph extraction.
final class LocalizationTable {
  final Map<String, Map<String, Object>> _locales = {};

  Set<String> get availableLocales => _locales.keys.toSet();

  Map<String, Object> _bucket(String localeTag) {
    final norm = LocaleCode.parse(localeTag).tag;
    return _locales.putIfAbsent(norm, () => {});
  }

  void setString(String localeTag, String key, String value) {
    _bucket(localeTag)[key] = value;
  }

  void setPlural(
    String localeTag,
    String key,
    Map<PluralCategory, String> forms,
  ) {
    _bucket(localeTag)[key] = Map<PluralCategory, String>.unmodifiable(forms);
  }

  void loadFlatMap(String localeTag, Map<String, Object?> entries) {
    final bucket = _bucket(localeTag);
    _flattenInto('', entries, bucket);
  }

  void loadJsonString(String localeTag, String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is Map<String, Object?>) {
      loadFlatMap(localeTag, decoded);
    } else if (decoded is Map) {
      loadFlatMap(localeTag, decoded.cast<String, Object?>());
    } else {
      throw const FormatException('Localization JSON root must be an object.');
    }
  }

  /// Loads an RFC-4180 CSV string (`key,en,de,fr` header row).
  /// Supports plural keys using suffix notation e.g. `items.count[one]`, `items.count[other]`.
  void loadCsv(String csvContent, {String keyColumnName = 'key'}) {
    final rows = _parseCsvRows(csvContent);
    if (rows.isEmpty) return;
    final header = rows.first;
    final keyIdx = header.indexWhere(
      (h) => h.trim().toLowerCase() == keyColumnName.toLowerCase(),
    );
    final effectiveKeyIdx = keyIdx == -1 ? 0 : keyIdx;

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (effectiveKeyIdx >= row.length) continue;
      final rawKey = row[effectiveKeyIdx].trim();
      if (rawKey.isEmpty) continue;

      final pluralMatch = RegExp(r'^(.*)\[(zero|one|two|few|many|other)\]$')
          .firstMatch(rawKey);

      for (int c = 0; c < header.length; c++) {
        if (c == effectiveKeyIdx || c >= row.length) continue;
        final localeTag = header[c].trim();
        if (localeTag.isEmpty) continue;
        final cellValue = row[c];
        if (cellValue.isEmpty) continue;

        final bucket = _bucket(localeTag);
        if (pluralMatch != null) {
          final baseKey = pluralMatch.group(1)!;
          final catName = pluralMatch.group(2)!;
          final cat = PluralCategory.values.firstWhere((p) => p.name == catName);
          final existing = bucket[baseKey];
          final map = existing is Map<PluralCategory, String>
              ? Map<PluralCategory, String>.from(existing)
              : <PluralCategory, String>{};
          map[cat] = cellValue;
          bucket[baseKey] = Map<PluralCategory, String>.unmodifiable(map);
        } else {
          bucket[rawKey] = cellValue;
        }
      }
    }
  }

  /// Looks up [key] following [fallbackChain] (`[locale, lang, fallback]`).
  ({String? text, String? resolvedLocale}) resolveRaw(
    String key, {
    required List<String> chain,
    num? pluralCount,
  }) {
    for (final loc in chain) {
      final entry = _locales[loc]?[key];
      if (entry == null) continue;
      if (entry is String) {
        return (text: entry, resolvedLocale: loc);
      }
      if (entry is Map<PluralCategory, String>) {
        final cat = PluralRules.select(loc, pluralCount ?? 0);
        final resolved = entry[cat] ??
            entry[PluralCategory.other] ??
            (entry.values.isNotEmpty ? entry.values.first : null);
        if (resolved != null) {
          return (text: resolved, resolvedLocale: loc);
        }
      }
    }
    return (text: null, resolvedLocale: null);
  }

  /// Replaces `{token}`, `{nested.path}`, `{val:0.0}`, and unescapes `{{` / `}}`.
  static String format(
    String template, [
    Map<String, Object?> params = const {},
  ]) {
    if (template.isEmpty) return template;
    final out = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final ch = template[i];
      if (ch == '{') {
        if (i + 1 < template.length && template[i + 1] == '{') {
          out.write('{');
          i += 2;
          continue;
        }
        final close = template.indexOf('}', i + 1);
        if (close == -1) {
          out.write(template.substring(i));
          break;
        }
        final expr = template.substring(i + 1, close);
        final colon = expr.indexOf(':');
        final keyPath = colon == -1 ? expr : expr.substring(0, colon);
        final fmtHint = colon == -1 ? null : expr.substring(colon + 1);
        final resolved = _lookupParam(params, keyPath.trim());
        if (resolved == null) {
          out.write('{$expr}');
        } else {
          out.write(_formatParamValue(resolved, fmtHint));
        }
        i = close + 1;
      } else if (ch == '}' && i + 1 < template.length && template[i + 1] == '}') {
        out.write('}');
        i += 2;
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  /// Collects unique sorted Unicode code points present in [localeTag] (or all locales if omitted)
  /// so GPU font atlases can prewarm exact glyphs cleanly.
  Set<int> collectGlyphCodePoints({String? localeTag}) {
    final glyphs = <int>{};
    void collectBucket(Map<String, Object>? bucket) {
      if (bucket == null) return;
      for (final val in bucket.values) {
        if (val is String) {
          glyphs.addAll(val.runes);
        } else if (val is Map<PluralCategory, String>) {
          for (final text in val.values) {
            glyphs.addAll(text.runes);
          }
        }
      }
    }

    if (localeTag != null) {
      collectBucket(_locales[LocaleCode.parse(localeTag).tag]);
    } else {
      for (final bucket in _locales.values) {
        collectBucket(bucket);
      }
    }
    return glyphs;
  }

  String collectGlyphString({String? localeTag}) {
    final sorted = collectGlyphCodePoints(localeTag: localeTag).toList()..sort();
    return String.fromCharCodes(sorted);
  }

  List<String> keysForLocale(String localeTag) =>
      _locales[LocaleCode.parse(localeTag).tag]?.keys.toList() ?? const [];

  static Object? _lookupParam(Map<String, Object?> params, String path) {
    if (params.containsKey(path)) return params[path];
    Object? curr = params;
    for (final part in path.split('.')) {
      if (curr is Map && curr.containsKey(part)) {
        curr = curr[part];
      } else {
        return null;
      }
    }
    return curr;
  }

  static String _formatParamValue(Object val, String? fmtHint) {
    if (val is num && fmtHint != null) {
      final dot = fmtHint.indexOf('.');
      if (dot != -1) {
        final decimals = fmtHint.length - dot - 1;
        return val.toStringAsFixed(decimals);
      }
    }
    return val.toString();
  }

  void _flattenInto(
    String prefix,
    Map<String, Object?> src,
    Map<String, Object> out,
  ) {
    for (final entry in src.entries) {
      final fullKey = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final val = entry.value;
      if (val is String) {
        out[fullKey] = val;
      } else if (val is Map) {
        final m = val.cast<String, Object?>();
        if (_looksLikePluralMap(m)) {
          final parsed = <PluralCategory, String>{};
          for (final p in m.entries) {
            final match = PluralCategory.values
                .where((c) => c.name == p.key)
                .firstOrNull;
            if (match != null && p.value != null) {
              parsed[match] = p.value.toString();
            }
          }
          out[fullKey] = Map<PluralCategory, String>.unmodifiable(parsed);
        } else {
          _flattenInto(fullKey, m, out);
        }
      } else if (val != null) {
        out[fullKey] = val.toString();
      }
    }
  }

  static bool _looksLikePluralMap(Map<String, Object?> map) {
    if (map.isEmpty) return false;
    const valid = {'zero', 'one', 'two', 'few', 'many', 'other'};
    return map.keys.every(valid.contains) && map.values.every((v) => v is String);
  }

  static List<List<String>> _parseCsvRows(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var i = 0;

    while (i < input.length) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
        } else {
          cell.write(ch);
          i++;
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
          i++;
        } else if (ch == ',') {
          row.add(cell.toString());
          cell.clear();
          i++;
        } else if (ch == '\r' || ch == '\n') {
          if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
            i++;
          }
          row.add(cell.toString());
          cell.clear();
          if (row.any((c) => c.isNotEmpty)) rows.add(row);
          row = <String>[];
          i++;
        } else {
          cell.write(ch);
          i++;
        }
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
    }
    return rows;
  }
}
