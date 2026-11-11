import 'package:test/test.dart';
import 'package:voxloc/voxloc.dart';

void main() {
  group('LocaleCode & CLDR pluralization rules', () {
    test('builds regional fallback chain and resolves English/Polish/Russian/Japanese plurals', () {
      final ptBr = LocaleCode.parse('pt_br');
      expect(ptBr.fallbackChain('en'), ['pt-BR', 'pt', 'en']);

      expect(PluralRules.select('en', 1), PluralCategory.one);
      expect(PluralRules.select('en', 2), PluralCategory.other);
      expect(PluralRules.select('ja', 1), PluralCategory.other);

      // Russian / Slavic: 1 -> one, 2 -> few, 5 -> many, 21 -> one
      expect(PluralRules.select('ru', 1), PluralCategory.one);
      expect(PluralRules.select('ru', 2), PluralCategory.few);
      expect(PluralRules.select('ru', 5), PluralCategory.many);
      expect(PluralRules.select('ru', 21), PluralCategory.one);
    });
  });

  group('LocalizationTable CSV/JSON imports, interpolation & glyph extraction', () {
    test('parses nested JSON + CSV with quoted commas/plurals and extracts unique glyphs', () {
      final table = LocalizationTable()
        ..loadJsonString('en', '''
        {
          "menu": { "title": "Star {{Voyager}}", "greet": "Hello, {player.name}! HP: {hp:0.0}" }
        }
        ''')
        ..loadCsv('''
key,en,de,ru
ui.confirm,"Yes, proceed","Ja, weiter","Да, далее"
gems.count[one],"{count} gem","{count} Edelstein","{count} самоцвет"
gems.count[few],"{count} gems","{count} Edelsteine","{count} самоцвета"
gems.count[many],"{count} gems","{count} Edelsteine","{count} самоцветов"
gems.count[other],"{count} gems","{count} Edelsteine","{count} самоцвета"
''');

      final mgr = LocalizationManager(table: table, activeLocale: 'de', fallbackLocale: 'en');
      // Nested JSON fell back to 'en' when not in 'de'
      expect(
        mgr.tr('menu.greet', params: {'player': {'name': 'Nova'}, 'hp': 99.46}),
        'Hello, Nova! HP: 99.5',
      );
      expect(mgr.tr('menu.title'), 'Star {Voyager}');
      expect(mgr.tr('ui.confirm'), 'Ja, weiter');
      expect(mgr.trPlural('gems.count', 1), '1 Edelstein');
      expect(mgr.trPlural('gems.count', 4), '4 Edelsteine');

      mgr.setLocale('ru');
      expect(mgr.trPlural('gems.count', 2), '2 самоцвета');
      expect(mgr.trPlural('gems.count', 5), '5 самоцветов');

      final ruGlyphs = table.collectGlyphString(localeTag: 'ru');
      expect(ruGlyphs, contains('Д'));
      expect(ruGlyphs, contains('ц'));
    });

    test('fires locale switch listeners and records missing keys', () {
      final mgr = LocalizationManager(activeLocale: 'en');
      final events = <String>[];
      final unsub = mgr.addLocaleListener(events.add);

      expect(mgr.tr('missing.dialog', defaultValue: 'Fallback'), 'Fallback');
      expect(mgr.missingKeys, {'en:missing.dialog'});

      expect(mgr.setLocale('fr-CA'), isTrue);
      expect(events, ['fr-CA']);
      unsub();
      expect(mgr.setLocale('es'), isTrue);
      expect(events, ['fr-CA']);
    });
  });
}
