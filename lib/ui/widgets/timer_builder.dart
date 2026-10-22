import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds its child on a fixed interval.
///
/// The live "data age" readout is a clock, not a value that only moves when a
/// refresh lands: if nothing arrives, the age must keep counting up so a stalled
/// feed is visible. This keeps that ticking scoped to the one small widget
/// instead of rebuilding the whole screen.
class TimerBuilder extends StatefulWidget {
  final Duration interval;
  final Widget Function(BuildContext context) builder;

  const TimerBuilder({
    super.key,
    required this.interval,
    required this.builder,
  });

  @override
  State<TimerBuilder> createState() => _TimerBuilderState();
}

class _TimerBuilderState extends State<TimerBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(TimerBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
