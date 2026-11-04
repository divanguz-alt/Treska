import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/ui/led/led_font.dart';
import 'package:zet2/ui/led/led_layout.dart';

final LedFont font = LedFont.fromJson(
  jsonDecode(File('assets/led_font.json').readAsStringSync())
      as Map<String, dynamic>,
);

Set<String> _set(Int32List flat) => {
  for (var i = 0; i < flat.length; i += 2) '${flat[i]},${flat[i + 1]}',
};

Set<String> _json(List<dynamic> pairs) => {
  for (final p in pairs) '${p[0]},${p[1]}',
};

/// Rows of the layout as text, for readable failures and shape checks.
String _ascii(LedLayout l) {
  final grid = List.generate(LedLayout.rows, (_) => List.filled(l.cols, '.'));
  void put(Int32List d, [int dx = 0]) {
    for (var i = 0; i < d.length; i += 2) {
      final x = d[i] + dx, y = d[i + 1];
      if (x >= 0 && x < l.cols && y >= 0 && y < LedLayout.rows) {
        grid[y][x] = '#';
      }
    }
  }

  put(l.dots);
  put(l.timeDots);
  return grid.map((r) => r.join()).join('\n');
}

void main() {
  group('README §6', () {
    test('6 Črnomerec: one tall line', () {
      final l = layoutLed(
        font,
        line: '6',
        dest: 'Črnomerec',
        cols: 176,
        time: 'STIŽE',
      );
      expect(l.marquees, isEmpty);
      // Tall script: every lit row comes in pairs, nothing uses the
      // small two-line rows, and the caron of Č sits in rows 0–3.
      final ys = {for (var i = 1; i < l.dots.length; i += 2) l.dots[i]};
      expect(ys.reduce((a, b) => a > b ? a : b), 17);
      expect(
        _ascii(l).split('\n')[0],
        contains('#'),
        reason: 'caron of Č / Ž drawn in the accent rows',
      );
    });

    test('220 Dugave: one tall line', () {
      final l = layoutLed(font, line: '220', dest: 'Dugave', cols: 150);
      expect(l.marquees, isEmpty);
      // Destination centred in the room right of the number.
      final nT = font.measure('220', LedScale.tall);
      final dT = font.measure('DUGAVE', LedScale.tall);
      final left = nT + 6 + (150 - nT - 6 - dT) ~/ 2;
      final xs = [
        for (var i = 0; i < l.dots.length; i += 2)
          if (l.dots[i] > nT) l.dots[i],
      ];
      expect(xs.reduce((a, b) => a < b ? a : b), left);
    });

    test('234 Glavni kolodvor - Kajzerica - Lanište: two lines', () {
      final split = splitDestination(
        font,
        'GLAVNI KOLODVOR - KAJZERICA - LANIŠTE'.replaceAll(
          RegExp(r'\s*-\s*'),
          '-',
        ),
      );
      expect(split, ['GLAVNI KOLODVOR-', 'KAJZERICA-LANIŠTE']);
      final l = layoutLed(
        font,
        line: '234',
        dest: 'Glavni kolodvor - Kajzerica - Lanište',
        cols: 150,
      );
      expect(l.marquees, isEmpty);
      // Big number: 2 × 2 pixels from row 2.
      expect(_ascii(l).split('\n')[2].substring(0, 5), contains('##'));
    });

    test(
      '132 Savski most - Goli breg - Brezovica: marquee on a narrow board',
      () {
        final l = layoutLed(
          font,
          line: '132',
          dest: 'Savski most - Goli breg - Brezovica',
          cols: 118,
        );
        expect(l.marquees, hasLength(2));
        for (final m in l.marquees) {
          expect(m.width, greaterThan(m.avail));
          expect(m.period, m.width + 14);
          expect(m.cycleSeconds, closeTo(1.5 + (m.width + 15) / 22, 1e-9));
          expect(m.offsetAt(0), 0);
          expect(m.offsetAt(1.49), 0, reason: 'stands still for 1.5 s');
          expect(m.offsetAt(1.5), 0);
          expect(m.offsetAt(1.5 + 1 / 22), 1, reason: 'one column at a time');
          expect(m.offsetAt(1.5 + 10.5 / 22), 10);
          expect(
            m.offsetAt(m.cycleSeconds - 0.001),
            m.period,
            reason: 'ends on the seamless copy',
          );
          expect(m.offsetAt(m.cycleSeconds + 0.1), 0, reason: 'loops');
        }
      },
    );
  });

  test('matches the reference layout dot for dot', () {
    final cases =
        jsonDecode(File('test/fixtures/led_golden.json').readAsStringSync())
            as List;
    expect(cases, hasLength(greaterThan(10)));
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final name = '${c['line']} ${c['dest']} @${c['cols']} ${c['time'] ?? ''}';
      final l = layoutLed(
        font,
        line: c['line'] as String,
        dest: c['dest'] as String,
        cols: c['cols'] as int,
        time: c['time'] as String?,
      );
      expect(_set(l.dots), _json(c['dots'] as List), reason: name);
      expect(_set(l.timeDots), _json(c['time_dots'] as List), reason: name);
      final ms = c['marquees'] as List;
      expect(l.marquees, hasLength(ms.length), reason: name);
      for (var i = 0; i < ms.length; i++) {
        final m = ms[i] as Map<String, dynamic>;
        expect(l.marquees[i].x0, m['x0'], reason: name);
        expect(l.marquees[i].y, m['y'], reason: name);
        expect(l.marquees[i].avail, m['avail'], reason: name);
        expect(
          _set(l.marquees[i].dots),
          _json(m['dots'] as List),
          reason: name,
        );
      }
    }
  });

  group('font', () {
    test('Č Ć Š Ž are composed, Đ has its own glyph', () {
      final c = font.glyph('C');
      expect(font.glyph('Č').rows.sublist(2), c.rows.sublist(2));
      expect(font.glyph('Č').rows.sublist(0, 2), ['.#.#.', '..#..']);
      expect(font.glyph('Ć').rows.sublist(0, 2), ['...#.', '..#..']);
      expect(font.glyph('Š').rows.sublist(0, 2), ['.#.#.', '..#..']);
      expect(font.glyph('Ž').rows.sublist(0, 2), ['.#.#.', '..#..']);
      expect(font.glyph('Đ').rows, isNot(font.glyph('D').rows));
      expect(font.glyph('Đ').rows[5], '###.#');
    });

    test('variable widths and the 1-column gap', () {
      expect(font.glyph('I').width, 3);
      expect(font.glyph(' ').width, 3);
      expect(font.glyph('-').width, 4);
      expect(font.glyph('.').width, 1);
      expect(font.glyph(':').width, 1);
      expect(font.measure('10:06', LedScale.small), 5 + 5 + 1 + 5 + 5 + 4);
      expect(font.measure('II', LedScale.big), 3 * 2 * 2 + 2);
    });

    test('unknown characters lose their accent, else become a space', () {
      expect(font.glyph('Ü').rows, font.glyph('U').rows);
      expect(font.glyph('É').rows, font.glyph('E').rows);
      expect(font.glyph('?').rows, font.glyph(' ').rows);
      expect(LedFont.upper('črnomerec'), 'ČRNOMEREC');
      expect(LedFont.upper('đurđekovec'), 'ĐURĐEKOVEC');
    });
  });
}
