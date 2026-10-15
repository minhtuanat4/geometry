import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/routing/road_labels.dart';
import 'package:flutter_location/routing/road_labels_layer.dart';
import 'package:flutter_location/routing/routing_service.dart';

void main() {
  test(
    'Merges adjacent named steps and anchors along their actual geometry',
    () {
      final labels = buildRoadLabels(
        [
          {
            'steps': [
              {'name': 'Đường A', 'from_index': 0, 'to_index': 1},
              {'name': 'Đường A', 'from_index': 1, 'to_index': 2},
            ],
          },
        ],
        [
          [const LatLng(0, 0), const LatLng(0, .001), const LatLng(0, .002)],
        ],
      );
      expect(labels.length, 1);
      expect(labels.single.name, 'Đường A');
      expect(labels.single.position.longitude, closeTo(.001, .0000001));
    },
  );

  test(
    'Keeps leg-local indices, skips invalid names/indices and repeats long roads',
    () {
      final labels = buildRoadLabels(
        [
          {
            'steps': [
              {'name': 'Đường dài', 'from_index': 0, 'to_index': 1},
              {'name': 'Sai', 'from_index': 0, 'to_index': 999},
            ],
          },
          {
            'steps': [
              {'name': '', 'from_index': 0, 'to_index': 1},
              {'name': 'Đường B', 'from_index': 0, 'to_index': 1},
            ],
          },
        ],
        [
          [const LatLng(0, 0), const LatLng(0, .01)],
          [const LatLng(1, 1), const LatLng(1, 1.001)],
        ],
      );
      expect(labels.where((label) => label.name == 'Đường dài').length, 4);
      expect(labels.any((label) => label.name == 'Sai'), isFalse);
      expect(labels.last.name, 'Đường B');
      expect(labels.last.position.latitude, 1);
      expect(labels.last.position.longitude, closeTo(1.0005, .0000001));
      expect(buildRoadLabels(null, []), isEmpty);
    },
  );

  test('Routing parser retains provider names at the correct leg geometry', () {
    final route = GeoapifyRoutingService.parseRoute({
      'features': [
        {
          'properties': {
            'distance': 222,
            'legs': [
              {
                'steps': [
                  {'name': 'Đường kiểm thử', 'from_index': 0, 'to_index': 2},
                ],
              },
            ],
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [0.0, 0.0],
              [.001, 0.0],
              [.002, 0.0],
            ],
          },
        },
      ],
    });
    expect(route.roadLabels.single.name, 'Đường kiểm thử');
    expect(route.roadLabels.single.position.longitude, closeTo(.001, .0000001));
  });

  testWidgets(
    'Labels sit above the line, avoid each other and respond to zoom/rotation',
    (tester) async {
      final map = MapController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              mapController: map,
              options: const MapOptions(
                initialCenter: LatLng(0, .001),
                initialZoom: 16,
              ),
              children: [
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [const LatLng(0, 0), const LatLng(0, .004)],
                      color: Colors.green,
                      strokeWidth: 5,
                    ),
                  ],
                ),
                const RoadLabelsLayer(
                  labels: [
                    RoadLabel(name: 'Đường A', position: LatLng(0, .001)),
                    RoadLabel(name: 'Trùng vị trí', position: LatLng(0, .001)),
                    RoadLabel(name: 'Đường B', position: LatLng(0, .004)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Đường A'), findsOneWidget);
      expect(find.text('Trùng vị trí'), findsNothing);
      expect(find.text('Đường B'), findsOneWidget);
      final labels = tester
          .widgetList<MarkerLayer>(find.byType(MarkerLayer))
          .expand((layer) => layer.markers);
      expect(labels.every((marker) => marker.rotate == true), isTrue);
      map.rotate(90);
      await tester.pump();
      expect(find.text('Đường A'), findsOneWidget);
      expect(find.text('Đường B'), findsOneWidget);
      map.move(const LatLng(0, .001), 13);
      await tester.pump();
      expect(find.text('Đường A'), findsNothing);
      map.move(const LatLng(1, 1), 16);
      await tester.pump();
      expect(find.text('Đường A'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      map.dispose();
    },
  );
}
