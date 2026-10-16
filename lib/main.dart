import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_search/address_search_service.dart';
import 'address_search/address_search_sheet.dart';
import 'routing/route_controller.dart';
import 'routing/road_labels_layer.dart';
import 'routing/routing_service.dart';
import 'routing/transport_mode.dart';
import 'tracking/position_math.dart';
import 'tracking/device_location.dart';
import 'tracking/device_location_layer.dart';
import 'tracking/heading_math.dart';

void main() => runApp(const MyApp());

const _green = Color(0xFF087F5B);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Theo dõi giao hàng',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _green),
      scaffoldBackgroundColor: const Color(0xFFF6F8F7),
      useMaterial3: true,
    ),
    home: const TrackingPage(),
  );
}

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    this.loadTiles = true,
    this.deviceLocation,
    this.addressSearchService,
    this.routingService,
  });

  final AddressSearchService? addressSearchService;
  final RoutingService? routingService;

  final DeviceLocation? deviceLocation;

  /// Allows widget tests to exercise tracking without HTTP tile requests.
  final bool loadTiles;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _defaultZoom = 15.3;
  late final AnimationController _cameraAnimation;
  late LatLng _cameraFrom;
  late LatLng _cameraTarget;
  late double _cameraFromZoom;
  final _driverPosition = ValueNotifier<LatLng?>(null);
  late final AddressSearchService _addressSearch;
  final _destination = ValueNotifier<AddressSuggestion?>(null);
  final _transportMode = ValueNotifier<TransportMode>(
    TransportMode.fromApiValue(
      const String.fromEnvironment('ROUTING_MODE', defaultValue: 'motorcycle'),
    ),
  );
  late final RoutingService _routingService;
  late final RouteController _route;
  late final DeviceLocation _device;
  final _origin = ValueNotifier<LatLng?>(null);
  bool _followDevice = true;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_updateCamera);
    _addressSearch = widget.addressSearchService ?? GeoapifyAddressSearch();
    _routingService = widget.routingService ?? GeoapifyRoutingService();
    _route = RouteController(service: _routingService);
    _device = widget.deviceLocation ?? DeviceLocation();
    _device.position.addListener(_onDevicePosition);
    _route.addListener(_updateDriverPosition);
    _destination.addListener(_updateRoute);
    _transportMode.addListener(_updateRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _device.start();
    });
  }

  void _onDevicePosition() {
    _updateRoute();
    _updateDriverPosition();
    final position = _device.position.value;
    if (!mounted || position == null) return;
    if (_origin.value == null) {
      _origin.value = position;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(position, 16);
      });
    } else if (_followDevice) {
      _map.move(_driverPosition.value ?? position, _map.camera.zoom);
    }
  }

  void _updateDriverPosition() {
    final gps = _device.position.value;
    _driverPosition.value = gps == null
        ? null
        : _route.value.driverPosition ?? gps;
    if (gps == null) _cameraAnimation.stop();
  }

  void _updateRoute() {
    _route.updatePreferMainRoads(
      transportMode: _transportMode.value,
      from: _device.position.value,
      to: _destination.value?.position,
    );
  }

  Future<void> _openDirections() async {
    final selected = await showModalBottomSheet<AddressSuggestion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => AddressSearchSheet(
        service: _addressSearch,
        transportMode: _transportMode,
        near: _device.position.value ?? _origin.value,
      ),
    );
    if (!mounted || selected == null) return;
    _destination.value = selected;
    _animateCameraTo(selected.position);
  }

  void _animateToDriver() {
    final position = _driverPosition.value;
    if (position != null) _animateCameraTo(position);
  }

  void _animateCameraTo(LatLng target) {
    _followDevice = false;
    _cameraAnimation.stop();
    final camera = _map.camera;
    _cameraFrom = camera.center;
    _cameraFromZoom = camera.zoom;
    _cameraTarget = target;
    _cameraAnimation.forward(from: 0);
  }

  void _updateCamera() {
    final t = Curves.easeInOutCubic.transform(_cameraAnimation.value);
    _map.move(
      interpolatePosition(_cameraFrom, _cameraTarget, t),
      _cameraFromZoom + (_defaultZoom - _cameraFromZoom) * t,
    );
  }

  void _centerDevice() {
    final position = _device.position.value;
    if (position == null) return;
    _cameraAnimation.stop();
    _followDevice = true;
    _map.move(position, 17);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_device.enabled) _device.start(requestPermission: false);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cameraAnimation.stop();
      _device.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _device.position.removeListener(_onDevicePosition);
    if (widget.deviceLocation == null) _device.dispose();
    _route.removeListener(_updateDriverPosition);
    _driverPosition.dispose();
    _cameraAnimation.dispose();
    _map.dispose();
    _origin.dispose();
    _destination.removeListener(_updateRoute);
    _destination.dispose();
    _transportMode.removeListener(_updateRoute);
    _transportMode.dispose();
    _route.dispose();
    if (widget.routingService == null) _routingService.close();
    if (widget.addressSearchService == null) _addressSearch.close();
    super.dispose();
  }

  Widget _buildMap(LatLng origin) => RepaintBoundary(
    child: FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: origin,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) {
            _followDevice = false;
            _cameraAnimation.stop();
          }
        },
        initialZoom: _defaultZoom,
        minZoom: 3,
        maxZoom: 19,
      ),
      children: [
        if (widget.loadTiles)
          TileLayer(
            urlTemplate: const String.fromEnvironment(
              'TILE_URL',
              defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            userAgentPackageName: 'com.example.flutter_location',
            maxNativeZoom: 19,
          ),

        ValueListenableBuilder<RouteState>(
          valueListenable: _route,
          builder: (context, state, _) => PolylineLayer(
            key: const ValueKey('destination-polyline'),
            polylines: [
              for (final points in state.visibleLines)
                Polyline(points: points, color: _green, strokeWidth: 5),
            ],
          ),
        ),

        // Raster tile labels cannot be reordered. Draw route-name overlays
        // above the route line and below driver/destination markers.
        ValueListenableBuilder<RouteState>(
          valueListenable: _route,
          builder: (context, state, _) => RoadLabelsLayer(
            key: const ValueKey('route-road-labels'),
            labels: state.route?.roadLabels ?? const [],
          ),
        ),
        _DriverLayer(position: _driverPosition, device: _device),
        ValueListenableBuilder<AddressSuggestion?>(
          valueListenable: _destination,
          builder: (context, destination, _) => MarkerLayer(
            markers: [
              if (destination != null)
                Marker(
                  point: destination.position,
                  width: 44,
                  height: 44,
                  rotate: true,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 44,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Theo dõi giao hàng')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _origin,
                  builder: (context, origin, _) => origin == null
                      ? const Center(child: Text('Đang chờ vị trí thiết bị…'))
                      : _buildMap(origin),
                ),
                DeviceLocationControls(
                  device: _device,
                  onCenter: _centerDevice,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: ValueListenableBuilder<AddressSuggestion?>(
                    valueListenable: _destination,
                    builder: (context, destination, _) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    destination == null
                                        ? 'Chọn điểm đến để bắt đầu chỉ đường'
                                        : 'Điểm đến: ${destination.label}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (destination != null)
                                    ValueListenableBuilder<RouteState>(
                                      valueListenable: _route,
                                      builder: (context, state, _) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            state.offRoute && state.loading
                                                ? 'Lệch tuyến • Đang tìm đường mới…'
                                                : state.offRoute &&
                                                      state.error == null
                                                ? 'Lệch tuyến • Chờ cập nhật đường'
                                                : state.waitingForGps
                                                ? 'Đang chờ GPS để tìm đường'
                                                : state.loading
                                                ? 'Đang tìm tuyến đường…'
                                                : state.error ??
                                                      (state.route == null
                                                          ? 'Chưa có tuyến đường'
                                                          : 'Chiều dài tuyến: ${state.route!.kilometers.toStringAsFixed(2)} km'),
                                            key: const ValueKey(
                                              'destination-distance',
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          if (state.error != null)
                                            TextButton(
                                              onPressed: _route.retry,
                                              child: const Text(
                                                'Thử lại tuyến đường',
                                              ),
                                            ),
                                          if (state.route != null)
                                            Text(
                                              _route.preference ==
                                                      RoutingPreference
                                                          .mainRoads
                                                  ? '${_transportMode.value.label} • Ưu tiên đường chính • Geoapify'
                                                  : '${_transportMode.value.label} • Tuyến ngắn • Geoapify',
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (destination != null)
                              IconButton(
                                tooltip: 'Xóa điểm đến',
                                onPressed: () => _destination.value = null,
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 104,
                  child: ValueListenableBuilder<LatLng?>(
                    valueListenable: _origin,
                    builder: (context, origin, _) => FloatingActionButton.small(
                      heroTag: 'directions',
                      tooltip: 'Chỉ đường',
                      onPressed: origin == null ? null : _openDirections,
                      child: const Icon(Icons.directions),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 38,
                  child: ValueListenableBuilder<LatLng?>(
                    valueListenable: _driverPosition,
                    child: const Icon(Icons.my_location),
                    builder: (context, origin, child) =>
                        FloatingActionButton.small(
                          heroTag: 'center',
                          tooltip: 'Về vị trí tài xế',
                          onPressed: origin == null ? null : _animateToDriver,
                          child: child,
                        ),
                  ),
                ),
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
    ),
    child: Icon(icon, color: Colors.white, size: 23),
  );
}

/// Animation rebuilds only this layer, leaving tiles and order details alone.
class _DriverLayer extends StatefulWidget {
  const _DriverLayer({required this.position, required this.device});
  final ValueNotifier<LatLng?> position;
  final DeviceLocation device;

  @override
  State<_DriverLayer> createState() => _DriverLayerState();
}

class _DriverLayerState extends State<_DriverLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  LatLng? _from;
  LatLng? _to;
  late final Listenable _updates;
  LatLng? get _position => _from == null || _to == null
      ? null
      : interpolatePosition(_from!, _to!, _animation.value);

  @override
  void initState() {
    super.initState();
    _from = _to = widget.position.value;
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    widget.position.addListener(_onPosition);
    _updates = Listenable.merge([_animation, widget.position]);
  }

  void _onPosition() {
    final target = widget.position.value;
    if (target == null) {
      _animation.stop();
      _from = _to = null;
      return;
    }
    if (target == _to) return;
    _from = _position ?? target;
    _to = target;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _updates,
    builder: (context, child) => MarkerLayer(
      markers: [
        if (_position != null)
          Marker(
            width: 76,
            height: 76,
            point: _position!,
            // Heading is relative to north; the map applies its rotation once.
            rotate: false,
            child: child!,
          ),
      ],
    ),
    // Position frames reuse this subtree. Compass events rebuild only the arrow.
    child: RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox.square(
            dimension: 46,
            child: _MapPin(
              icon: Icons.delivery_dining,
              color: Color(0xFF2056B3),
            ),
          ),
          ValueListenableBuilder<double?>(
            valueListenable: widget.device.heading,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Icon(Icons.navigation, color: Color(0xFF2056B3), size: 18),
            ),
            builder: (context, heading, child) => heading == null
                ? const SizedBox.shrink()
                : TweenAnimationBuilder<double>(
                    tween: Tween(end: headingRadians(heading)),
                    duration: widget.device.headingSettings.animationDuration,
                    curve: Curves.easeInOutCubic,
                    child: child,
                    builder: (context, angle, child) => Transform.rotate(
                      key: const ValueKey('driver-heading-arrow'),
                      angle: angle,
                      child: child,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
