import '../data/models.dart';

/// One line+direction on the board, with its next few arrivals.
///
/// The handoff groups the departure list by line and headsign (up to 12 groups,
/// sorted by the first arrival) instead of printing one row per vehicle. This is
/// that grouping, computed from the engine's flat arrival list.
class ArrivalGroup {
  final String routeShortName;
  final String headsign;
  final int routeType;
  final List<Arrival> arrivals;

  const ArrivalGroup({
    required this.routeShortName,
    required this.headsign,
    required this.routeType,
    required this.arrivals,
  });

  Arrival get next => arrivals.first;
  bool get isTram => routeType == kRouteTypeTram;

  /// True when any arrival in the group is a live GPS prediction.
  bool get hasRealtime => arrivals.any((a) => a.isRealtime);

  /// The mode badge the status dot reflects: the best source in the group.
  ArrivalSource get bestSource {
    if (arrivals.any((a) => a.isRealtime)) return ArrivalSource.realtime;
    if (arrivals.any((a) => a.isEstimated)) return ArrivalSource.estimated;
    return ArrivalSource.scheduled;
  }
}

/// Groups [arrivals] by route + headsign, keeping at most [maxGroups].
///
/// Within a group arrivals stay time-ordered, and only [perGroup] are kept so
/// the "zatim" line has something to show without bloating the snapshot.
List<ArrivalGroup> groupArrivals(
  List<Arrival> arrivals, {
  int maxGroups = 12,
  int perGroup = 3,
}) {
  final byKey = <String, List<Arrival>>{};
  final meta = <String, Arrival>{};

  final sorted = [...arrivals]..sort((a, b) => a.time.compareTo(b.time));
  for (final a in sorted) {
    final key = '${a.routeShortName}\u0000${a.headsign}';
    (byKey[key] ??= []).add(a);
    meta.putIfAbsent(key, () => a);
  }

  final groups = <ArrivalGroup>[];
  for (final entry in byKey.entries) {
    final first = meta[entry.key]!;
    groups.add(ArrivalGroup(
      routeShortName: first.routeShortName,
      headsign: first.headsign,
      routeType: first.routeType,
      arrivals: entry.value.take(perGroup).toList(growable: false),
    ));
  }

  groups.sort((a, b) => a.next.time.compareTo(b.next.time));
  return groups.take(maxGroups).toList(growable: false);
}
