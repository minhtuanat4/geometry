import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_search/address_search_service.dart';
import 'address_search/address_search_sheet.dart';
import 'routing/route_controller.dart';
import 'routing/road_labels_layer.dart';
import 'routing/routing_service.dart';
import 'routing/transport_mode.dart';
import 'tracking/demo_tracking.dart';
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
  final _tracking = DemoTracking();
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
  bool _resumeOnForeground = false;
  final LayerHitNotifier<Object> hitNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(_updateCamera);
    hitNotifier.addListener(() {
      // final LayerHitResult<String>? result = hitNotifier.value;
      debugPrint("asdasdasd");
    });
    _addressSearch = widget.addressSearchService ?? GeoapifyAddressSearch();
    _routingService = widget.routingService ?? GeoapifyRoutingService();
    _route = RouteController(service: _routingService);
    _device = widget.deviceLocation ?? DeviceLocation();
    _device.position.addListener(_onDevicePosition);
    _destination.addListener(_updateRoute);
    _transportMode.addListener(_updateRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _device.start();
    });
  }

  void _onDevicePosition() {
    _updateRoute();
    final position = _device.position.value;
    if (!mounted || position == null) return;
    if (_origin.value == null) {
      _tracking.initialize(position);
      _origin.value = position;
      _tracking.start();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(position, 16);
      });
    } else if (_followDevice) {
      _map.move(position, _map.camera.zoom);
    }
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
    if (!_tracking.ready) return;
    _animateCameraTo(_tracking.position);
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
      if (_resumeOnForeground) _tracking.start();
      _resumeOnForeground = false;
      if (_device.enabled) _device.start(requestPermission: false);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_tracking.running) {
        _resumeOnForeground = true;
        _tracking.pause();
      }
      _cameraAnimation.stop();
      _device.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _device.position.removeListener(_onDevicePosition);
    if (widget.deviceLocation == null) _device.dispose();
    hitNotifier.dispose();
    _tracking.dispose();
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

        ValueListenableBuilder<AddressSuggestion?>(
          valueListenable: _destination,
          builder: (context, destination, _) => PolylineLayer(
            hitNotifier: hitNotifier,
            polylines: [
              if (destination == null)
                Polyline(
                  points: _tracking.route,
                  color: _green,
                  strokeWidth: 5,
                ),
            ],
          ),
        ),

        ValueListenableBuilder<RouteState>(
          valueListenable: _route,
          builder: (context, state, _) => PolylineLayer(
            key: const ValueKey('destination-polyline'),
            polylines: [
              for (final points in state.route?.lines ?? <List<LatLng>>[])
                Polyline(points: points, color: _green, strokeWidth: 5),
            ],
          ),
        ),

        ValueListenableBuilder<RouteState>(
          valueListenable: _route,
          builder: (context, state, _) => RoadLabelsLayer(
            key: const ValueKey('destination-road-labels'),
            labels: state.route?.roadLabels ?? const [],
          ),
        ),

        MarkerLayer(
          markers: [
            Marker(
              point: _tracking.route.first,
              child: const _MapPin(
                icon: Icons.restaurant,
                color: Colors.orange,
              ),
            ),
            Marker(
              point: _tracking.route.last,
              child: const _MapPin(icon: Icons.home_rounded, color: _green),
            ),
          ],
        ),

        _DriverLayer(tracking: _tracking, device: _device),
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
    appBar: AppBar(
      title: const Text('Theo dõi giao hàng'),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: Chip(label: Text('DEMO')),
        ),
      ],
    ),
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
                                        ? 'Tuyến demo quanh vị trí thiết bị'
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
                                            state.waitingForGps
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
                    valueListenable: _origin,
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bữa ngon đang trên đường',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('Tài xế Minh • Đơn thử nghiệm #DEMO01'),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _tracking,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !_tracking.ready
                            ? 'Chờ GPS để bắt đầu mô phỏng'
                            : _tracking.completed
                            ? 'Đã đến điểm giao mô phỏng'
                            : '${_tracking.running ? "Đang di chuyển" : "Đã tạm dừng"} • Còn ${_tracking.remainingSeconds}s mô phỏng',
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: _tracking.progress,
                        color: _green,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Nhận ${_tracking.packets} điểm • 1 điểm/giây • Nội suy marker',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: !_tracking.ready || _tracking.completed
                                  ? null
                                  : () {
                                      if (_tracking.running) {
                                        _tracking.pause();
                                      } else {
                                        _tracking.start();
                                      }
                                    },
                              icon: Icon(
                                _tracking.running
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                _tracking.running ? 'Tạm dừng' : 'Tiếp tục',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _tracking.ready
                                ? _tracking.restart
                                : null,
                            icon: const Icon(Icons.replay),
                            label: const Text('Chạy lại'),
                          ),
                        ],
                      ),
                    ],
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
  const _DriverLayer({required this.tracking, required this.device});
  final DemoTracking tracking;
  final DeviceLocation device;

  @override
  State<_DriverLayer> createState() => _DriverLayerState();
}

class _DriverLayerState extends State<_DriverLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late LatLng _from;
  late LatLng _to;
  int _lastPacket = 0;
  LatLng get _position => interpolatePosition(_from, _to, _animation.value);

  @override
  void initState() {
    super.initState();
    _from = _to = widget.tracking.position;
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    widget.tracking.addListener(_onPacket);
  }

  void _onPacket() {
    final source = widget.tracking;
    if (source.packets < _lastPacket) {
      _from = _to = source.position;
      _animation.value = 1;
    } else if (source.packets != _lastPacket) {
      _from = _position;
      _to = source.position;
      _animation.forward(from: 0);
    } else if (!source.running) {
      _animation.stop();
    } else if (_animation.value < 1) {
      _animation.forward();
    }
    _lastPacket = source.packets;
  }

  @override
  void dispose() {
    widget.tracking.removeListener(_onPacket);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) => MarkerLayer(
      markers: [
        Marker(
          width: 76,
          height: 76,
          point: _position,
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
