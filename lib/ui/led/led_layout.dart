import 'dart:math' as math;
import 'dart:typed_data';

import 'led_font.dart';

/// Where every dot of one sign goes. A pure function of its inputs; ported
/// 1:1 from `panel()` in the design handoff's `led_reference.js`
/// (kept as `tool/led_reference.js`, checked dot for dot by
/// `test/led_layout_test.dart`).
class LedLayout {
  /// The sign is always 18 dots tall.
  static const int rows = 18;

  final int cols;

  /// Line number and destination parts that fit, as x, y pairs.
  final Int32List dots;

  /// The time at the right edge, as x, y pairs (it may blink on its own).
  final Int32List timeDots;

  /// Destination lines too wide for their space: clipped, and sliding when
  /// the marquee is on.
  final List<LedMarquee> marquees;

  const LedLayout._(this.cols, this.dots, this.timeDots, this.marquees);

  bool get hasMarquee => marquees.isNotEmpty;
}

/// One clipped destination line. Its [dots] start at x = 0 and are drawn
/// shifted by [x0] minus the current [offsetAt], inside [x0, x0 + avail).
class LedMarquee {
  /// Pause before the line starts to slide.
  static const double pauseSeconds = 1.5;

  /// Columns per second, one column at a time.
  static const double speed = 22;

  /// Empty columns before the line repeats.
  static const int gap = 14;

  final int x0;
  final int y;
  final int avail;

  /// Width of the line in columns.
  final int width;
  final Int32List dots;

  const LedMarquee(this.x0, this.y, this.avail, this.width, this.dots);

  /// Line + gap: the copy drawn at this distance makes the loop seamless.
  int get period => width + gap;

  /// `1.5 + (w + 15) / 22` s.
  double get cycleSeconds => pauseSeconds + (period + 1) / speed;

  /// Columns the line has moved left at [seconds] since the sign appeared.
  int offsetAt(double seconds) {
    final t = seconds % cycleSeconds;
    if (t < pauseSeconds) return 0;
    // The epsilon keeps a step boundary (1.5 + k / 22 s) on step k.
    return math.min(period, ((t - pauseSeconds) * speed + 1e-9).floor());
  }
}

/// Lays out the sign for line [line] to [dest] on a board [cols] dots wide,
/// with [time] (e.g. `STIŽE`, `3 MIN`, `10:06`) right-aligned when given.
LedLayout layoutLed(
  LedFont font, {
  required String line,
  required String dest,
  required int cols,
  String? time,
}) {
  final lit = <int>[];
  final timeDots = <int>[];
  final marquees = <LedMarquee>[];
  final d = LedFont.upper(dest);
  final n = LedFont.upper(line);

  var content = cols;
  if (time != null && time.isNotEmpty) {
    final t = LedFont.upper(time);
    final tw = font.measure(t, LedScale.tall);
    content = cols - tw - 6;
    font.draw(timeDots, t, cols - tw, 0, LedScale.tall);
  }

  final nT = font.measure(n, LedScale.tall);
  final dT = font.measure(d, LedScale.tall);
  if (nT + 6 + dT <= content) {
    font.draw(lit, n, 0, 0, LedScale.tall);
    font.draw(
      lit,
      d,
      nT + 6 + _floorDiv(content - nT - 6 - dT, 2),
      0,
      LedScale.tall,
    );
  } else {
    final nB = font.measure(n, LedScale.big);
    font.draw(lit, n, 0, 2, LedScale.big);
    final x0 = nB + 5;
    final avail = content - x0;
    final lines = splitDestination(font, d.replaceAll(RegExp(r'\s*-\s*'), '-'));
    for (var i = 0; i < lines.length; i++) {
      final ln = lines[i];
      final y = lines.length == 1 ? 4 : i * 9;
      final w = font.measure(ln, LedScale.small);
      if (w <= avail) {
        font.draw(lit, ln, x0 + _floorDiv(avail - w, 2), y, LedScale.small);
        continue;
      }
      marquees.add(
        LedMarquee(x0, y, avail, w, font.dots(ln, 0, y, LedScale.small)),
      );
    }
  }
  return LedLayout._(
    cols,
    Int32List.fromList(lit),
    Int32List.fromList(timeDots),
    List.unmodifiable(marquees),
  );
}

/// Breaks [s] in two where the longer half is narrowest: at a space (which
/// is dropped) or after a hyphen (which stays at the end of the first line).
/// No break that helps → one line.
List<String> splitDestination(LedFont font, String s) {
  var best = [s];
  var bw = font.measure(s, LedScale.small);
  final chars = [for (final r in s.runes) String.fromCharCode(r)];
  for (var i = 0; i < chars.length; i++) {
    final String a, b;
    if (chars[i] == ' ') {
      a = chars.sublist(0, i).join();
      b = chars.sublist(i + 1).join();
    } else if (chars[i] == '-') {
      a = chars.sublist(0, i + 1).join();
      b = chars.sublist(i + 1).join();
    } else {
      continue;
    }
    final w = math.max(
      font.measure(a, LedScale.small),
      font.measure(b, LedScale.small),
    );
    if (w < bw) {
      bw = w;
      best = [a, b];
    }
  }
  return best;
}

/// `Math.floor(a / b)` for a possibly negative [a].
int _floorDiv(int a, int b) => (a / b).floor();
