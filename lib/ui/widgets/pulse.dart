import 'package:flutter/widgets.dart';

/// A single 1.4 s pulse shared by every blinking element.
///
/// ZET 1 created one [AnimationController] per arrival row (and one per map
/// dot). Here the whole screen shares one ticker, so blinking costs one frame
/// callback instead of dozens.
class PulseScope extends InheritedWidget {
  final Animation<double> animation;
  const PulseScope({super.key, required this.animation, required super.child});

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PulseScope>()?.animation;

  @override
  bool updateShouldNotify(PulseScope oldWidget) =>
      oldWidget.animation != animation;
}

class PulseDot extends StatelessWidget {
  final double size;
  final Color color;
  final double minOpacity;

  const PulseDot({
    super.key,
    this.size = 6,
    required this.color,
    this.minOpacity = 0.25,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = PulseScope.maybeOf(context);
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    if (pulse == null) return dot;
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Opacity(
        opacity: minOpacity + (1 - minOpacity) * pulse.value,
        child: child,
      ),
      child: dot,
    );
  }
}
