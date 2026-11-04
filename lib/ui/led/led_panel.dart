import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'led_clock.dart';
import 'led_font.dart';
import 'led_layout.dart';
import 'led_palette.dart';

/// The dark sign itself (handoff README §3): background, padding and edge,
/// with the dot grid inside. The board is dark in both themes; only its edge
/// changes. [cols] defaults to as many dots as fit the width.
class LedBoard extends StatelessWidget {
  final LedFont font;
  final String line;
  final String dest;
  final String? time;
  final bool blinkTime;
  final Color color;
  final bool marquee;
  final double pitch;
  final int? cols;
  final EdgeInsets padding;

  const LedBoard({
    super.key,
    required this.font,
    required this.line,
    required this.dest,
    required this.color,
    this.time,
    this.blinkTime = false,
    this.marquee = true,
    this.pitch = 2,
    this.cols,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = LayoutBuilder(
      builder: (context, constraints) {
        final n = cols ?? (constraints.maxWidth / pitch).floor();
        if (n <= 0) return const SizedBox.shrink();
        final layout = layoutLed(
          font,
          line: line,
          dest: dest,
          cols: n,
          time: time,
        );
        return LedPanel(
          layout: layout,
          cacheKey: '$line\u0000$dest\u0000$time\u0000$n',
          color: color,
          pitch: pitch,
          blinkTime: blinkTime,
          marquee: marquee,
        );
      },
    );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: LedPalette.board,
        borderRadius: BorderRadius.circular(6),
        boxShadow: dark
            ? const [
                BoxShadow(
                  color: Color(0x66000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ]
            : const [BoxShadow(color: Color(0x1F000000), spreadRadius: 1)],
      ),
      // Inner 1 dp edge in the dark theme, drawn on top so it takes no room
      // from the dot grid.
      foregroundDecoration: dark
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x12FFFFFF)),
            )
          : null,
      child: panel,
    );
  }
}

/// Paints one [LedLayout]: static dots from a cached image, the marquee
/// lines as pre-rendered strips moved one column at a time, and the time,
/// blinking for „STIŽE“. Animates only while [LedClockScope]'s clock runs.
class LedPanel extends StatefulWidget {
  final LedLayout layout;

  /// Identifies [layout]'s inputs for the image cache.
  final String cacheKey;
  final Color color;
  final double pitch;
  final bool blinkTime;
  final bool marquee;

  const LedPanel({
    super.key,
    required this.layout,
    required this.cacheKey,
    required this.color,
    this.pitch = 2,
    this.blinkTime = false,
    this.marquee = true,
  });

  /// Blink cycle of „STIŽE“: lit for the first 62 %, then at 12 % alpha.
  static const double blinkSeconds = 1.2;
  static const double blinkOnFraction = 0.62;
  static const double blinkOffAlpha = 0.12;

  @override
  State<LedPanel> createState() => _LedPanelState();
}

class _LedPanelState extends State<LedPanel> {
  final _LedFrame _frame = _LedFrame();
  LedClock? _clock;

  bool get _wantsClock =>
      widget.blinkTime || (widget.marquee && widget.layout.hasMarquee);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen(LedClockScope.of(context));
  }

  @override
  void didUpdateWidget(LedPanel old) {
    super.didUpdateWidget(old);
    _listen(LedClockScope.of(context));
    _onTick();
  }

  void _listen(LedClock? clock) {
    final next = _wantsClock ? clock : null;
    if (identical(next, _clock)) return;
    _clock?.removeListener(_onTick);
    _clock = next;
    _clock?.addListener(_onTick);
    _onTick();
  }

  /// Recomputes the discrete state; repaints only when a column or the
  /// blink actually changes (22 Hz at most, not every frame).
  void _onTick() {
    final clock = _clock;
    final running = clock != null && clock.enabled;
    final t = running ? clock.seconds : 0.0;
    final animateMarquee = running && widget.marquee;
    final offsets = [
      for (final m in widget.layout.marquees)
        animateMarquee ? m.offsetAt(t) : 0,
    ];
    final blinkOn =
        !(running && widget.blinkTime) ||
        (t % LedPanel.blinkSeconds) <
            LedPanel.blinkSeconds * LedPanel.blinkOnFraction;
    _frame.update(offsets, blinkOn, animateMarquee);
  }

  @override
  void dispose() {
    _clock?.removeListener(_onTick);
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layout;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(l.cols * widget.pitch, LedLayout.rows * widget.pitch),
        painter: _LedPainter(
          layout: l,
          cacheKey: widget.cacheKey,
          color: widget.color,
          pitch: widget.pitch,
          dpr: MediaQuery.devicePixelRatioOf(context),
          separateTime: widget.blinkTime,
          frame: _frame,
        ),
      ),
    );
  }
}

/// Current discrete animation state, shared with the painter.
class _LedFrame extends ChangeNotifier {
  List<int> offsets = const [];
  bool blinkOn = true;

  /// Whether the strips carry the seamless second copy.
  bool looping = false;

  void update(List<int> next, bool blink, bool loop) {
    if (blink == blinkOn && loop == looping && _same(next, offsets)) return;
    offsets = next;
    blinkOn = blink;
    looping = loop;
    notifyListeners();
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _LedPainter extends CustomPainter {
  final LedLayout layout;
  final String cacheKey;
  final Color color;
  final double pitch;
  final double dpr;
  final bool separateTime;
  final _LedFrame frame;

  _LedPainter({
    required this.layout,
    required this.cacheKey,
    required this.color,
    required this.pitch,
    required this.dpr,
    required this.separateTime,
    required this.frame,
  }) : super(repaint: frame);

  String get _key => '$cacheKey|${color.toARGB32()}|$pitch|$dpr|$separateTime';

  @override
  void paint(Canvas canvas, Size size) {
    final key = _key;
    final base = _LedImages.get('$key|base', () {
      return _LedImages.render(
        cols: layout.cols,
        rows: LedLayout.rows,
        pitch: pitch,
        dpr: dpr,
        color: color,
        grid: true,
        dots: [layout.dots, if (!separateTime) layout.timeDots],
      );
    });
    _draw(canvas, base, Offset.zero);

    for (var i = 0; i < layout.marquees.length; i++) {
      final m = layout.marquees[i];
      final loop = frame.looping;
      final strip = _LedImages.get('$key|m$i|$loop', () {
        final shifted = Int32List.fromList(m.dots);
        for (var k = 1; k < shifted.length; k += 2) {
          shifted[k] -= m.y;
        }
        return _LedImages.render(
          cols: loop ? m.period + m.width : m.width,
          rows: LedFont.rowCount,
          pitch: pitch,
          dpr: dpr,
          color: color,
          grid: false,
          dots: [shifted],
          copyEvery: loop ? m.period : 0,
        );
      });
      final off = i < frame.offsets.length ? frame.offsets[i] : 0;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          m.x0 * pitch,
          m.y * pitch,
          m.avail * pitch,
          LedFont.rowCount * pitch,
        ),
      );
      _draw(canvas, strip, Offset((m.x0 - off) * pitch, m.y * pitch));
      canvas.restore();
    }

    if (separateTime && layout.timeDots.isNotEmpty) {
      final time = _LedImages.get('$key|time', () {
        return _LedImages.render(
          cols: layout.cols,
          rows: LedLayout.rows,
          pitch: pitch,
          dpr: dpr,
          color: color,
          grid: false,
          dots: [layout.timeDots],
        );
      });
      _draw(
        canvas,
        time,
        Offset.zero,
        alpha: frame.blinkOn ? 1 : LedPanel.blinkOffAlpha,
      );
    }
  }

  void _draw(Canvas canvas, ui.Image image, Offset at, {double alpha = 1}) {
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromRGBO(0, 0, 0, alpha);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(at.dx, at.dy, image.width / dpr, image.height / dpr),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LedPainter old) =>
      old._key != _key || !identical(old.frame, frame);
}

/// Rendered dot images, most recently used last. Static dots are drawn once
/// (with the blur glow) and then only blitted, so a ticking marquee costs a
/// clipped image copy per step instead of a blur per dot per frame.
class _LedImages {
  static const int _max = 96;
  static final LinkedHashMap<String, ui.Image> _cache =
      LinkedHashMap<String, ui.Image>();

  static ui.Image get(String key, ui.Image Function() build) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final image = build();
    _cache[key] = image;
    // Evicted images are left to the garbage collector: a painter from the
    // previous frame may still hold one.
    while (_cache.length > _max) {
      _cache.remove(_cache.keys.first);
    }
    return image;
  }

  /// [cols] × [rows] dots at [pitch] dp: the unlit grid (alpha 0.09) when
  /// [grid], then each lit dot twice, blurred (σ ≈ 0.55 × pitch) and sharp
  /// (diameter 0.8 × pitch). With [copyEvery] > 0 the dots repeat once that
  /// many columns to the right, for a seamless marquee loop.
  static ui.Image render({
    required int cols,
    required int rows,
    required double pitch,
    required double dpr,
    required Color color,
    required bool grid,
    required List<Int32List> dots,
    int copyEvery = 0,
  }) {
    final px = pitch * dpr;
    final width = (cols * px).ceil().clamp(1, 1 << 14);
    final height = (rows * px).ceil().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dot = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.8 * px;

    if (grid) {
      final all = Float32List(cols * rows * 2);
      var i = 0;
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          all[i++] = (x + 0.5) * px;
          all[i++] = (y + 0.5) * px;
        }
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        all,
        dot..color = color.withValues(alpha: 0.09),
      );
    }

    var count = 0;
    for (final d in dots) {
      count += d.length;
    }
    final copies = copyEvery > 0 ? 2 : 1;
    final lit = Float32List(count * copies);
    var j = 0;
    for (var c = 0; c < copies; c++) {
      final dx = c * copyEvery;
      for (final d in dots) {
        for (var k = 0; k < d.length; k += 2) {
          lit[j++] = (d[k] + dx + 0.5) * px;
          lit[j++] = (d[k + 1] + 0.5) * px;
        }
      }
    }
    if (lit.isNotEmpty) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        lit,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.8 * px
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.55 * px),
      );
      canvas.drawRawPoints(ui.PointMode.points, lit, dot..color = color);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }
}
