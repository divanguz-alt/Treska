import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One frame clock for every ZET zaslon sign on screen (marquee and the
/// blinking „STIŽE“), instead of a timer per row. It only ticks while at
/// least one visible sign listens, and never while animations are off.
class LedClock extends ChangeNotifier {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  int _listeners = 0;
  bool _enabled = true;

  /// Seconds since the clock started; signs derive their state from it.
  double get seconds => _elapsed.inMicroseconds / 1e6;

  /// False when animations are off (system or setting): signs stand still.
  bool get enabled => _enabled;

  void _attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker((elapsed) {
      _elapsed = elapsed;
      notifyListeners();
    });
    _sync();
  }

  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _sync();
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listeners++;
    _sync();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners--;
    _sync();
  }

  void _sync() {
    final t = _ticker;
    if (t == null) return;
    final run = _enabled && _listeners > 0;
    if (run && !t.isActive) {
      t.start();
    } else if (!run && t.isActive) {
      t.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Provides the [LedClock] and keeps [LedClock.enabled] in step with the
/// system: Flutter's own flag follows Android's transition scale, so the
/// animator scale (`ANIMATOR_DURATION_SCALE`, what the handoff names) is read
/// from the platform as well, again whenever the app comes back.
class LedClockScope extends StatefulWidget {
  final Widget child;
  const LedClockScope({super.key, required this.child});

  static LedClock? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LedClockInherited>()?.clock;

  @override
  State<LedClockScope> createState() => _LedClockScopeState();
}

class _LedClockScopeState extends State<LedClockScope>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('hr.zet.zet2/updates');

  final LedClock _clock = LedClock();
  bool _animatorsOn = true;

  @override
  void initState() {
    super.initState();
    _clock._attach(this);
    WidgetsBinding.instance.addObserver(this);
    _readAnimatorScale();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readAnimatorScale();
  }

  Future<void> _readAnimatorScale() async {
    bool on = true;
    try {
      on = await _channel.invokeMethod<bool>('animatorsEnabled') ?? true;
    } catch (_) {
      // Not on Android (tests, desktop): rely on Flutter's flag alone.
    }
    if (!mounted || on == _animatorsOn) return;
    setState(() => _animatorsOn = on);
  }

  @override
  Widget build(BuildContext context) {
    _clock.enabled = _animatorsOn && !MediaQuery.disableAnimationsOf(context);
    return _LedClockInherited(clock: _clock, child: widget.child);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }
}

class _LedClockInherited extends InheritedWidget {
  final LedClock clock;
  const _LedClockInherited({required this.clock, required super.child});

  @override
  bool updateShouldNotify(_LedClockInherited old) => old.clock != clock;
}
