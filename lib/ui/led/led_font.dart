import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Glyph scales of the sign (handoff README §4).
enum LedScale {
  /// 1 × 1, all 9 rows: a destination written in two lines.
  small(1, 1, 0),

  /// 1 × 2, all 9 rows: one-line sign and the time.
  tall(1, 2, 0),

  /// 2 × 2 without the 2 accent rows: the line number next to two lines.
  big(2, 2, 2);

  final int sx;
  final int sy;
  final int firstRow;
  const LedScale(this.sx, this.sy, this.firstRow);
}

/// One glyph with its 2 accent rows on top: 9 strings of [width] chars, `#`
/// is a lit dot.
class LedGlyph {
  final int width;
  final List<String> rows;
  const LedGlyph(this.width, this.rows);
}

/// The 5×7 bitmap font from `assets/led_font.json`, with variable glyph
/// widths and Č Ć Š Ž composed from a base letter and an accent.
class LedFont {
  static const int rowCount = 9;

  final Map<String, LedGlyph> _glyphs;
  final LedGlyph _space;
  final int charGap;

  LedFont._(this._glyphs, this.charGap) : _space = _glyphs[' ']!;

  factory LedFont.fromJson(Map<String, dynamic> json) {
    final accentRows = json['accentRows'] as int;
    final base = <String, List<String>>{
      for (final e in (json['glyphs'] as Map<String, dynamic>).entries)
        e.key: [for (final r in e.value as List) r as String],
    };
    final accents = <String, List<String>>{
      for (final e in (json['accents'] as Map<String, dynamic>).entries)
        e.key: [for (final r in e.value as List) r as String],
    };
    final glyphs = <String, LedGlyph>{
      for (final e in base.entries)
        e.key: LedGlyph(e.value.first.length, [
          for (var i = 0; i < accentRows; i++) '.' * e.value.first.length,
          ...e.value,
        ]),
    };
    for (final e in (json['composed'] as Map<String, dynamic>).entries) {
      final parts = e.value as List;
      final b = base[parts[0] as String]!;
      glyphs[e.key] = LedGlyph(b.first.length, [...accents[parts[1]]!, ...b]);
    }
    return LedFont._(glyphs, json['charGap'] as int? ?? 1);
  }

  static LedFont? _loaded;

  /// The app's font once [load] has finished, else null.
  static LedFont? get instance => _loaded;

  static Future<LedFont> load() async {
    final cached = _loaded;
    if (cached != null) return cached;
    final text = await rootBundle.loadString('assets/led_font.json');
    return _loaded = LedFont.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  /// Glyph for one upper-case character. Characters outside the font lose
  /// their diacritic first (Ü → U); if that does not help either, a space.
  LedGlyph glyph(String ch) =>
      _glyphs[ch] ?? _glyphs[_fold[ch] ?? ''] ?? _space;

  /// Sign text: upper case (Croatian has no special case mappings among the
  /// letters the font draws).
  static String upper(String s) => s.toUpperCase();

  /// Width in columns of [s] at [scale], gaps included.
  int measure(String s, LedScale scale) {
    var w = 0;
    var n = 0;
    for (final r in s.runes) {
      w += glyph(String.fromCharCode(r)).width * scale.sx;
      n++;
    }
    return w + (n > 0 ? (n - 1) * charGap * scale.sx : 0);
  }

  /// Appends the lit dots of [s] at ([x], [y]) to [out] as x, y pairs.
  void draw(List<int> out, String s, int x, int y, LedScale scale) {
    final sx = scale.sx, sy = scale.sy;
    for (final r in s.runes) {
      final g = glyph(String.fromCharCode(r));
      for (var row = scale.firstRow; row < rowCount; row++) {
        final bits = g.rows[row];
        for (var k = 0; k < g.width; k++) {
          if (bits.codeUnitAt(k) != 0x23) continue; // '#'
          for (var i = 0; i < sx; i++) {
            for (var j = 0; j < sy; j++) {
              out
                ..add(x + k * sx + i)
                ..add(y + (row - scale.firstRow) * sy + j);
            }
          }
        }
      }
      x += (g.width + charGap) * sx;
    }
  }

  /// Dots of [s] as a typed list, for callers that keep them.
  Int32List dots(String s, int x, int y, LedScale scale) {
    final out = <int>[];
    draw(out, s, x, y, scale);
    return Int32List.fromList(out);
  }

  /// NFD-style fallback: the base letter of accented capitals the font lacks.
  static const Map<String, String> _fold = {
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'Ą': 'A',
    'Ç': 'C',
    'Č': 'C',
    'Ć': 'C',
    'Ď': 'D',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Ě': 'E',
    'Ę': 'E',
    'Ğ': 'G',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'İ': 'I',
    'Ľ': 'L',
    'Ĺ': 'L',
    'Ł': 'L',
    'Ñ': 'N',
    'Ń': 'N',
    'Ň': 'N',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'Ø': 'O',
    'Ő': 'O',
    'Ŕ': 'R',
    'Ř': 'R',
    'Ś': 'S',
    'Ş': 'S',
    'Š': 'S',
    'Ť': 'T',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ů': 'U',
    'Ű': 'U',
    'Ý': 'Y',
    'Ÿ': 'Y',
    'Ź': 'Z',
    'Ż': 'Z',
    'Ž': 'Z',
    '–': '-',
    '—': '-',
  };
}
