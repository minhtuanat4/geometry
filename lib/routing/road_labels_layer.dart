import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'road_labels.dart';

/// Raster tiles do not expose their text positions. These are route-name
/// overlays, not detections of labels hidden inside tile pixels.
class RoadLabelsLayer extends StatelessWidget {
  const RoadLabelsLayer({
    super.key,
    required this.labels,
    this.minZoom = 14,
    this.labelGap = 12,
    this.maxVisibleLabels = 60,
  });

  final List<RoadLabel> labels;
  final double minZoom;
  final double labelGap;
  final int maxVisibleLabels;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < minZoom || labels.isEmpty) return const SizedBox.shrink();
    final viewport = Offset.zero & camera.nonRotatedSize;
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xFF263C34),
    );
    final textSizes = <String, Size>{};
    final occupied = <Rect>[];
    final markers = <Marker>[];
    for (final label in labels) {
      if (markers.length >= maxVisibleLabels) break;
      final screenPoint = camera.latLngToScreenOffset(label.position);
      if (!viewport.contains(screenPoint)) continue;
      final textSize = textSizes.putIfAbsent(label.name, () {
        final painter = TextPainter(
          text: TextSpan(text: label.name, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 180);
        final size = painter.size;
        painter.dispose();
        return size;
      });
      final box = Rect.fromCenter(
        center: screenPoint,
        width: textSize.width + 12,
        height: textSize.height + 6,
      );
      // Reject only collisions between our own labels, whose bounds are known.
      if (occupied.any((other) => other.overlaps(box.inflate(labelGap)))) {
        continue;
      }
      occupied.add(box);
      markers.add(
        Marker(
          point: label.position,
          width: box.width,
          height: box.height,
          rotate: true, // Stay readable as the map rotates.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF5FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                label.name,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    return IgnorePointer(
      child: RepaintBoundary(child: MarkerLayer(markers: markers)),
    );
  }
}
