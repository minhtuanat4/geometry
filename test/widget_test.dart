import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_location/main.dart';
import 'package:flutter_location/routing/routing_service.dart';
import 'package:flutter_location/routing/road_labels.dart';
import 'package:flutter_location/routing/road_labels_layer.dart';
import 'package:flutter_location/routing/transport_mode.dart';
import 'package:flutter_location/address_search/address_search_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/tracking/device_location.dart';
import 'package:flutter_location/tracking/heading_filter.dart';

class FakeDeviceLocation extends DeviceLocation {
  FakeDeviceLocation({super.headingSettings});
  int starts = 0;

  @override
  Future<void> start({bool requestPermission = true}) async {
    starts++;
    enabled = true;
  }
}

class FakeAddressSearch implements AddressSearchService {
  @override
  Future<List<AddressSuggestion>> search(String query, {LatLng? near}) async =>
      const [
        AddressSuggestion(
          id: 'sample',
          label: 'Điểm đến thử nghiệm',
          position: LatLng(21.04, 105.86),
        ),
      ];
  @override
  void close() {}
}

class FakeRoutingService implements RoutingService {
  final requests = <({TransportMode? mode, RoutingPreference preference})>[];
  @override
  Future<RoadRoute> findRoute(
    LatLng from,
    LatLng to, {
    RoutingPreference preference = RoutingPreference.shortest,
    TransportMode? transportMode,
  }) async {
    requests.add((mode: transportMode, preference: preference));
    return RoadRoute(
      lines: [
        [from, LatLng(from.latitude, to.longitude), to],
      ],
      distanceMeters: 2400,
      roadLabels: [RoadLabel(name: 'Đường kiểm thử', position: to)],
    );
  }

  @override
  void close() {}
}

void main() {
  testWidgets('Driver arrow follows compass without rebuilding the map', (
    tester,
  ) async {
    final device = FakeDeviceLocation(
      headingSettings: const HeadingSettings(
        minUpdateInterval: Duration(seconds: 1),
        animationDuration: Duration(milliseconds: 800),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: TrackingPage(loadTiles: false, deviceLocation: device)),
    );
    device.position.value = const LatLng(21.0285, 105.8542);
    await tester.pump();
    final mapWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final arrow = find.byKey(const ValueKey('driver-heading-arrow'));
    expect(arrow, findsNothing);
    expect(find.byIcon(Icons.delivery_dining), findsOneWidget);

    device.heading.value = 0;
    await tester.pump();
    expect(arrow, findsOneWidget);
    final headingAnimation = tester.widget<TweenAnimationBuilder<double>>(
      find.ancestor(
        of: arrow,
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
    );
    expect(headingAnimation.duration, device.headingSettings.animationDuration);
    expect(headingAnimation.curve, Curves.easeInOutCubic);
    device.heading.value = 90;
    await tester.pump();
    await tester.pump(device.headingSettings.animationDuration);
    var transform = tester.widget<Transform>(arrow).transform;
    expect(transform.storage[0], closeTo(0, 0.00001));
    expect(transform.storage[1], closeTo(1, 0.00001));
    expect(
      identical(tester.widget<FlutterMap>(find.byType(FlutterMap)), mapWidget),
      isTrue,
    );

    // The map adds its own rotation; heading stays north-relative.
    mapWidget.mapController!.rotate(45);
    await tester.pump();
    transform = tester.widget<Transform>(arrow).transform;
    expect(transform.storage[1], closeTo(1, 0.00001));
    final driverMarker = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers)
        .singleWhere((marker) => marker.width == 76);
    expect(driverMarker.rotate, isFalse);

    device.heading.value = null;
    await tester.pump();
    expect(arrow, findsNothing);
    expect(find.byIcon(Icons.delivery_dining), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    device.dispose();
  });

  testWidgets(
    'Center button animates from current camera to default zoom in 2s',
    (tester) async {
      final device = FakeDeviceLocation();
      await tester.pumpWidget(
        MaterialApp(
          home: TrackingPage(loadTiles: false, deviceLocation: device),
        ),
      );
      const origin = LatLng(21.0285, 105.8542);
      device.position.value = origin;
      await tester.pump();
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      const away = LatLng(21.035, 105.860);
      map.move(away, 18);
      await tester.tap(find.byTooltip('Về vị trí tài xế'));
      await tester.pump();
      expect(map.camera.zoom, 18);
      expect(map.camera.center, away);
      await tester.pump(const Duration(seconds: 1));
      expect(map.camera.zoom, greaterThan(15.3));
      expect(map.camera.zoom, lessThan(18));
      expect(map.camera.center.latitude, greaterThan(origin.latitude));
      expect(map.camera.center.latitude, lessThan(away.latitude));
      await tester.pump(const Duration(seconds: 1));
      expect(map.camera.zoom, 15.3);
      expect(map.camera.center, origin);

      // Repeated taps restart smoothly from the current camera, including zoom-in.
      map.move(away, 12);
      await tester.tap(find.byTooltip('Về vị trí tài xế'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final intermediateZoom = map.camera.zoom;
      expect(intermediateZoom, greaterThan(12));
      expect(intermediateZoom, lessThan(15.3));
      await tester.tap(find.byTooltip('Về vị trí tài xế'));
      await tester.pump();
      expect(map.camera.zoom, closeTo(intermediateZoom, 0.00001));
      await tester.pump(const Duration(seconds: 2));
      expect(map.camera.zoom, 15.3);

      // A gesture cancels automatic camera movement.
      map.move(away, 18);
      await tester.tap(find.byTooltip('Về vị trí tài xế'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.dragFrom(
        tester.getTopRight(find.byType(FlutterMap)) + const Offset(-100, 100),
        const Offset(70, 0),
      );
      final interruptedZoom = map.camera.zoom;
      await tester.pump(const Duration(seconds: 2));
      expect(map.camera.zoom, closeTo(interruptedZoom, 0.00001));
      expect(map.camera.zoom, greaterThan(15.3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      device.dispose();
    },
  );

  testWidgets('Directions opens search and marks the selected destination', (
    tester,
  ) async {
    final device = FakeDeviceLocation();
    final routing = FakeRoutingService();
    await tester.pumpWidget(
      MaterialApp(
        home: TrackingPage(
          loadTiles: false,
          deviceLocation: device,
          addressSearchService: FakeAddressSearch(),
          routingService: routing,
        ),
      ),
    );
    device.position.value = const LatLng(21.0285, 105.8542);
    await tester.pump();
    await tester.tap(find.byTooltip('Chỉ đường'));
    await tester.pumpAndSettle();
    expect(find.text('Tìm điểm đến'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('transport-mode-motorcycle')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('transport-mode-car')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'địa chỉ',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('Điểm đến thử nghiệm'));
    await tester.pumpAndSettle();
    expect(find.text('Tìm điểm đến'), findsNothing);
    expect(find.text('Điểm đến: Điểm đến thử nghiệm'), findsOneWidget);
    final labels = tester.widget<RoadLabelsLayer>(
      find.byKey(const ValueKey('route-road-labels')),
    );
    expect(labels.labels.single.name, 'Đường kiểm thử');
    expect(find.text('Đường kiểm thử'), findsOneWidget);
    final map = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    expect(map.camera.center, const LatLng(21.04, 105.86));
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    final connection = find.byKey(const ValueKey('destination-polyline'));
    var line = tester.widget<PolylineLayer>(connection).polylines.single;
    expect(line.points, [
      const LatLng(21.0285, 105.8542),
      const LatLng(21.0285, 105.86),
      const LatLng(21.04, 105.86),
    ]);
    expect(line.color, const Color(0xFF087F5B));
    expect(find.text('Chiều dài tuyến: 2.40 km'), findsOneWidget);
    expect(routing.requests.last.mode, TransportMode.car);

    final mapWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
    device.position.value = const LatLng(21.039, 105.86);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Chiều dài tuyến: 2.40 km'), findsOneWidget);
    line = tester.widget<PolylineLayer>(connection).polylines.single;
    expect(line.points.first, const LatLng(21.039, 105.86));
    expect(
      identical(tester.widget<FlutterMap>(find.byType(FlutterMap)), mapWidget),
      isTrue,
    );

    await tester.tap(find.byTooltip('Chỉ đường'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('transport-mode-car')))
          .selected,
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('transport-mode-walking')),
    );
    await tester.tap(find.byKey(const ValueKey('transport-mode-walking')));
    await tester.pump();
    expect(routing.requests.last.mode, TransportMode.walking);
    expect(routing.requests.last.preference, RoutingPreference.shortest);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transport-mode-bus')),
    );
    await tester.tap(find.byKey(const ValueKey('transport-mode-bus')));
    await tester.pump();
    expect(find.textContaining('chưa gồm số tuyến'), findsOneWidget);
    expect(routing.requests.last.mode, TransportMode.bus);
    expect(routing.requests.last.preference, RoutingPreference.mainRoads);
    await tester.tap(find.byTooltip('Đóng tìm kiếm'));
    await tester.pumpAndSettle();
    device.position.value = null;
    await tester.pump();
    expect(tester.widget<PolylineLayer>(connection).polylines, isEmpty);
    expect(find.text('Đang chờ GPS để tìm đường'), findsOneWidget);
    device.position.value = const LatLng(21.04, 105.86);
    await tester.pump();
    expect(find.text('Chiều dài tuyến: 0.00 km'), findsOneWidget);

    await tester.tap(find.byTooltip('Xóa điểm đến'));
    await tester.pump();
    expect(find.byIcon(Icons.location_on), findsNothing);
    expect(tester.widget<PolylineLayer>(connection).polylines, isEmpty);
    expect(find.byKey(const ValueKey('destination-distance')), findsNothing);
    expect(
      tester
          .widget<RoadLabelsLayer>(
            find.byKey(const ValueKey('route-road-labels')),
          )
          .labels,
      isEmpty,
    );
    expect(find.text('Đường kiểm thử'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    device.dispose();
  });

  testWidgets('Driver uses only GPS and hides on loss or background', (
    tester,
  ) async {
    final device = FakeDeviceLocation();
    await tester.pumpWidget(
      MaterialApp(home: TrackingPage(loadTiles: false, deviceLocation: device)),
    );
    expect(find.text('Đang chờ vị trí thiết bị…'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('DEMO'), findsNothing);
    expect(find.text('Tạm dừng'), findsNothing);
    expect(find.text('Chạy lại'), findsNothing);
    expect(find.byIcon(Icons.restaurant), findsNothing);
    expect(find.byIcon(Icons.home_rounded), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(FlutterMap), findsNothing);
    const origin = LatLng(21.0285, 105.8542);
    device.position.value = origin;
    await tester.pump();
    final mapWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final map = mapWidget.mapController!;
    LatLng markerPosition() => tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .expand((layer) => layer.markers)
        .singleWhere((marker) => marker.width == 76)
        .point;
    expect(markerPosition(), origin);
    expect(map.camera.center, origin);
    await tester.pump(const Duration(seconds: 10));
    expect(markerPosition(), origin); // No synthetic movement over time.
    expect(
      tester
          .widget<PolylineLayer>(
            find.byKey(const ValueKey('destination-polyline')),
          )
          .polylines,
      isEmpty,
    );

    const next = LatLng(21.029, 105.855);
    device.position.value = next;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(markerPosition(), next);
    expect(map.camera.center, next);
    expect(
      identical(tester.widget<FlutterMap>(find.byType(FlutterMap)), mapWidget),
      isTrue,
    );
    await tester.dragFrom(
      tester.getTopRight(find.byType(FlutterMap)) + const Offset(-100, 100),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    final selectedCenter = map.camera.center;
    const movedAgain = LatLng(21.030, 105.856);
    device.position.value = movedAgain;
    device.notifyListeners();
    await tester.pump();
    expect(map.camera.center, selectedCenter);
    await tester.tap(find.byTooltip('Về vị trí của tôi'));
    await tester.pump();
    expect(map.camera.center, movedAgain);
    final starts = device.starts;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byIcon(Icons.delivery_dining), findsNothing);
    expect(
      tester
          .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
          .singleWhere((button) => button.heroTag == 'center')
          .onPressed,
      isNull,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(device.starts, starts + 1);
    expect(find.byIcon(Icons.delivery_dining), findsNothing);
    device.position.value = movedAgain;
    await tester.pump();
    expect(markerPosition(), movedAgain);
    device.position.value = null;
    await tester.pump();
    expect(find.byIcon(Icons.delivery_dining), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    device.dispose();
  });
}
