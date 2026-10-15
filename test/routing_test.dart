import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/routing/route_controller.dart';
import 'package:flutter_location/routing/routing_service.dart';
import 'package:flutter_location/routing/transport_mode.dart';

Map<String, dynamic> routeResponse() => {
  'features': [
    {
      'properties': {'distance': 1800, 'distance_units': 'Meters'},
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [105.85, 21.03],
            [105.86, 21.03],
            [105.86, 21.04],
          ],
          [
            [105.87, 21.04],
            [105.88, 21.04],
          ],
        ],
      },
    },
  ],
};

class PendingRouting implements RoutingService {
  final requests =
      <
        ({
          LatLng from,
          LatLng to,
          RoutingPreference preference,
          TransportMode? transportMode,
          Completer<RoadRoute> response,
        })
      >[];
  @override
  Future<RoadRoute> findRoute(
    LatLng from,
    LatLng to, {
    RoutingPreference preference = RoutingPreference.shortest,
    TransportMode? transportMode,
  }) {
    final response = Completer<RoadRoute>();
    requests.add((
      from: from,
      to: to,
      preference: preference,
      transportMode: transportMode,
      response: response,
    ));
    return response.future;
  }

  @override
  void close() {}
}

void main() {
  test('Transport filters map to the correct API profiles', () async {
    for (final mode in TransportMode.values) {
      final service = GeoapifyRoutingService(
        apiKey: 'test',
        client: MockClient((request) async {
          expect(request.url.queryParameters['mode'], mode.apiValue);
          return http.Response(jsonEncode(routeResponse()), 200);
        }),
      );
      await service.findRoute(
        const LatLng(21, 105),
        const LatLng(22, 106),
        transportMode: mode,
      );
      service.close();
    }
    expect(TransportMode.car.apiValue, 'drive');
    expect(TransportMode.walking.apiValue, 'walk');
    expect(TransportMode.bus.apiValue, 'bus');
  });

  testWidgets(
    'Changing only transport recalculates and ignores the old mode response',
    (tester) async {
      final service = PendingRouting();
      final controller = RouteController(service: service);
      const from = LatLng(21, 105);
      const to = LatLng(22, 106);
      controller.updatePreferMainRoads(
        from: from,
        to: to,
        transportMode: TransportMode.motorcycle,
      );
      controller.updatePreferMainRoads(
        from: from,
        to: to,
        transportMode: TransportMode.car,
      );
      expect(service.requests.length, 2);
      expect(service.requests.last.transportMode, TransportMode.car);
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1234,
        ),
      );
      await tester.pump();
      service.requests.first.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 9999,
        ),
      );
      await tester.pump();
      expect(controller.value.route!.distanceMeters, 1234);
      controller.updatePreferMainRoads(
        from: const LatLng(21.001, 105),
        to: to,
        transportMode: TransportMode.car,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(service.requests.last.transportMode, TransportMode.car);
      controller.dispose();
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1000,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Main-road preference compares actual road classes and keeps motorcycle mode',
    () async {
      final types = <String>[];
      final service = GeoapifyRoutingService(
        apiKey: 'test',
        client: MockClient((request) async {
          final type = request.url.queryParameters['type']!;
          types.add(type);
          expect(request.url.queryParameters['mode'], 'motorcycle');
          expect(request.url.queryParameters['details'], 'route_details');
          final data = routeResponse();
          data['features'][0]['properties'] = {
            'distance': type == 'balanced' ? 1800 : 1000,
            'legs': [
              {
                'steps': type == 'balanced'
                    ? [
                        {'distance': 1500, 'road_class': 'primary'},
                        {'distance': 300, 'road_class': 'residential'},
                      ]
                    : [
                        {'distance': 1000, 'road_class': 'residential'},
                      ],
              },
            ],
          };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final route = await service.findRoute(
        const LatLng(21, 105),
        const LatLng(22, 106),
        preference: RoutingPreference.mainRoads,
      );
      expect(types, unorderedEquals(['balanced', 'short']));
      expect(route.distanceMeters, 1800);
      expect(route.mainRoadMeters, 1500);
      expect(route.classifiedRoadMeters, 1800);
      expect(route.mainRoadScore(3), 2400);
      service.close();
    },
  );

  test(
    'Main-road penalty is configurable; missing classes retain balanced',
    () async {
      var includeClasses = true;
      final service = GeoapifyRoutingService(
        apiKey: 'test',
        minorRoadPenalty: 1,
        client: MockClient((request) async {
          final balanced = request.url.queryParameters['type'] == 'balanced';
          final data = routeResponse();
          data['features'][0]['properties'] = {
            'distance': balanced ? 1800 : 1000,
            if (includeClasses)
              'legs': [
                {
                  'steps': [
                    {
                      'distance': balanced ? 1800 : 1000,
                      'road_class': balanced ? 'primary' : 'residential',
                    },
                  ],
                },
              ],
          };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final shorter = await service.findRoute(
        const LatLng(21, 105),
        const LatLng(22, 106),
        preference: RoutingPreference.mainRoads,
      );
      expect(shorter.distanceMeters, 1000);
      includeClasses = false;
      final fallback = await service.findRoute(
        const LatLng(21, 105),
        const LatLng(22, 106),
        preference: RoutingPreference.mainRoads,
      );
      expect(fallback.distanceMeters, 1800);
      service.close();
    },
  );

  test(
    'One unavailable candidate does not discard the other valid route',
    () async {
      final service = GeoapifyRoutingService(
        apiKey: 'test',
        client: MockClient((request) async {
          if (request.url.queryParameters['type'] == 'balanced') {
            return http.Response('', 503);
          }
          return http.Response(jsonEncode(routeResponse()), 200);
        }),
      );
      final route = await service.findRoute(
        const LatLng(21, 105),
        const LatLng(22, 106),
        preference: RoutingPreference.mainRoads,
      );
      expect(route.distanceMeters, 1800);
      service.close();
    },
  );

  testWidgets(
    'Switching preference reroutes; retry and GPS retain the new choice',
    (tester) async {
      final service = PendingRouting();
      final controller = RouteController(service: service);
      const from = LatLng(21, 105);
      const to = LatLng(22, 106);
      controller.update(from: from, to: to);
      expect(service.requests.first.preference, RoutingPreference.shortest);
      controller.updatePreferMainRoads(from: from, to: to);
      expect(service.requests.length, 2);
      expect(service.requests.last.preference, RoutingPreference.mainRoads);
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1800,
        ),
      );
      await tester.pump();
      service.requests.first.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1000,
        ),
      );
      await tester.pump();
      expect(controller.value.route!.distanceMeters, 1800);
      controller.updatePreferMainRoads(from: const LatLng(21.001, 105), to: to);
      await tester.pump(const Duration(seconds: 10));
      expect(service.requests.length, 3);
      expect(service.requests.last.preference, RoutingPreference.mainRoads);
      service.requests.last.response.completeError(
        const RoutingException('Test failure'),
      );
      await tester.pump();
      controller.retry();
      await tester.pump(const Duration(seconds: 10));
      expect(service.requests.length, 4);
      expect(service.requests.last.preference, RoutingPreference.mainRoads);
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1800,
        ),
      );
      await tester.pump();
      controller.update(from: from, to: to);
      expect(service.requests.last.preference, RoutingPreference.shortest);
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 1000,
        ),
      );
      await tester.pump();
      expect(controller.value.route!.distanceMeters, 1000);
      controller.dispose();
    },
  );

  test(
    'Requests shortest motorcycle route and maps GeoJSON without bridging parts',
    () async {
      final service = GeoapifyRoutingService(
        apiKey: 'test',
        client: MockClient((request) async {
          expect(
            request.url.queryParameters['waypoints'],
            '21.03,105.85|21.04,105.86',
          );
          expect(request.url.queryParameters['mode'], 'motorcycle');
          expect(request.url.queryParameters['type'], 'short');
          expect(request.url.queryParameters['units'], 'metric');
          return http.Response(jsonEncode(routeResponse()), 200);
        }),
      );
      final route = await service.findRoute(
        const LatLng(21.03, 105.85),
        const LatLng(21.04, 105.86),
      );
      expect(route.kilometers, 1.8);
      expect(route.lines, [
        [
          const LatLng(21.03, 105.85),
          const LatLng(21.03, 105.86),
          const LatLng(21.04, 105.86),
        ],
        [const LatLng(21.04, 105.87), const LatLng(21.04, 105.88)],
      ]);
      service.close();
    },
  );

  test(
    'Rejects missing or invalid geometry rather than drawing a straight fallback',
    () {
      expect(
        () => GeoapifyRoutingService.parseRoute({'features': []}),
        throwsA(isA<RoutingException>()),
      );
      final bad = routeResponse();
      bad['features'][0]['geometry']['coordinates'][0][1][1] = 999.0;
      expect(
        () => GeoapifyRoutingService.parseRoute(bad),
        throwsA(isA<RoutingException>()),
      );
    },
  );

  test('Reports missing key and routing quota errors', () async {
    final missing = GeoapifyRoutingService(apiKey: '');
    await expectLater(
      missing.findRoute(const LatLng(21, 105), const LatLng(22, 106)),
      throwsA(isA<RoutingException>()),
    );
    missing.close();
    final limited = GeoapifyRoutingService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response('', 429)),
    );
    await expectLater(
      limited.findRoute(const LatLng(21, 105), const LatLng(22, 106)),
      throwsA(
        isA<RoutingException>().having(
          (e) => e.message,
          'message',
          contains('hạn mức'),
        ),
      ),
    );
    limited.close();
  });

  testWidgets('GPS movement is throttled and reroutes from the latest fix', (
    tester,
  ) async {
    final service = PendingRouting();
    final controller = RouteController(service: service);
    const from = LatLng(21.03, 105.85);
    const to = LatLng(21.04, 105.86);
    controller.update(from: from, to: to);
    service.requests.first.response.complete(
      GeoapifyRoutingService.parseRoute(routeResponse()),
    );
    await tester.pump();
    controller.update(from: const LatLng(21.03001, 105.85), to: to);
    await tester.pump(const Duration(seconds: 5));
    expect(service.requests.length, 1);
    controller.update(from: const LatLng(21.031, 105.85), to: to);
    controller.update(from: const LatLng(21.032, 105.85), to: to);
    await tester.pump(const Duration(seconds: 5));
    expect(service.requests.length, 2);
    expect(service.requests.last.from, const LatLng(21.032, 105.85));
    controller.update(from: null, to: to);
    service.requests.last.response.complete(
      GeoapifyRoutingService.parseRoute(routeResponse()),
    );
    await tester.pump();
    expect(controller.value.route, isNull);
    expect(controller.value.waitingForGps, isTrue);
    controller.dispose();
  });

  testWidgets(
    'Changing destination and clearing prevents old route responses from winning',
    (tester) async {
      final service = PendingRouting();
      final controller = RouteController(service: service);
      controller.update(from: const LatLng(21, 105), to: const LatLng(22, 106));
      controller.update(from: const LatLng(21, 105), to: const LatLng(23, 107));
      expect(service.requests.length, 2);
      service.requests.last.response.complete(
        RoadRoute(
          lines: [
            [const LatLng(21, 105), const LatLng(23, 107)],
          ],
          distanceMeters: 1234,
        ),
      );
      await tester.pump();
      service.requests.first.response.complete(
        GeoapifyRoutingService.parseRoute(routeResponse()),
      );
      await tester.pump();
      expect(controller.value.route!.distanceMeters, 1234);
      controller.update(from: const LatLng(21, 105), to: null);
      expect(controller.value.route, isNull);
      controller.update(from: const LatLng(21, 105), to: const LatLng(21, 105));
      expect(controller.value.route!.kilometers, 0);
      expect(service.requests.length, 2);
      controller.dispose();
      await tester.pump(const Duration(seconds: 20));
      expect(tester.takeException(), isNull);
    },
  );
}
