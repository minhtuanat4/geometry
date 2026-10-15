import 'package:latlong2/latlong.dart';

class RoadLabel {
  const RoadLabel({required this.name, required this.position});
  final String name;
  final LatLng position;
}

/// Build geographic anchors once per route, never on compass/animation frames.
/// Geoapify step indices are local to each leg's geometry.
List<RoadLabel> buildRoadLabels(
  dynamic legs,
  List<List<LatLng>> lines, {
  double spacingMeters = 250,
  int maxLabels = 2000,
}) {
  if (!spacingMeters.isFinite || spacingMeters <= 0 || maxLabels < 1) {
    throw ArgumentError('Label spacing and limit must be positive');
  }
  if (legs is! List) return const [];
  const distance = Distance(roundResult: false);
  final labels = <RoadLabel>[];
  for (
    var legIndex = 0;
    legIndex < legs.length && legIndex < lines.length;
    legIndex++
  ) {
    final leg = legs[legIndex];
    if (leg is! Map || leg['steps'] is! List) continue;
    final line = lines[legIndex];
    String? currentName;
    var start = 0;
    var end = 0;

    void flush() {
      if (currentName == null || labels.length >= maxLabels) return;
      final lengths = <double>[];
      var total = 0.0;
      for (var index = start; index < end; index++) {
        final length = distance(line[index], line[index + 1]);
        lengths.add(length);
        total += length;
      }
      if (total <= 0) return;
      var target = total <= spacingMeters ? total / 2 : spacingMeters / 2;
      var segment = 0;
      var traversed = 0.0;
      while (target < total && labels.length < maxLabels) {
        while (segment < lengths.length - 1 &&
            traversed + lengths[segment] < target) {
          traversed += lengths[segment++];
        }
        final length = lengths[segment];
        if (length > 0) {
          final from = line[start + segment];
          final to = line[start + segment + 1];
          final t = ((target - traversed) / length).clamp(0.0, 1.0);
          final longitudeDelta =
              (to.longitude - from.longitude + 540) % 360 - 180;
          labels.add(
            RoadLabel(
              name: currentName,
              position: LatLng(
                from.latitude + (to.latitude - from.latitude) * t,
                (from.longitude + longitudeDelta * t + 540) % 360 - 180,
              ),
            ),
          );
        }
        target += spacingMeters;
      }
    }

    for (final step in leg['steps'] as List) {
      final name = step is Map ? step['name'] : null;
      final from = step is Map ? step['from_index'] : null;
      final to = step is Map ? step['to_index'] : null;
      if (name is! String ||
          name.trim().isEmpty ||
          from is! int ||
          to is! int ||
          from < 0 ||
          to >= line.length ||
          to <= from) {
        flush();
        currentName = null;
        continue;
      }
      final normalized = name.trim();
      if (currentName == normalized && from == end) {
        end = to; // Merge adjacent steps on the same road.
      } else {
        flush();
        currentName = normalized;
        start = from;
        end = to;
      }
    }
    flush();
    if (labels.length >= maxLabels) break;
  }
  return List.unmodifiable(labels);
}
