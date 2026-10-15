import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'heading_filter.dart';

enum LocationAction { retry, appSettings, locationSettings }

class DeviceLocation extends ChangeNotifier {
  DeviceLocation({this.headingSettings = const HeadingSettings()})
    : _headingFilter = HeadingFilter(headingSettings);

  final HeadingSettings headingSettings;
  final HeadingFilter _headingFilter;
  final position = ValueNotifier<LatLng?>(null);
  final heading = ValueNotifier<double?>(null);
  StreamSubscription<Position>? _gps;
  StreamSubscription<CompassEvent>? _compass;
  final _clock = Stopwatch()..start();
  int _generation = 0;
  bool enabled = false;
  bool busy = false;
  bool _disposed = false;
  double? accuracy;
  String status = 'Bật vị trí để xem thiết bị của bạn';
  String compassStatus = 'Chưa bật la bàn';
  LocationAction action = LocationAction.retry;

  bool _current(int generation) => !_disposed && generation == _generation;

  void _cancel() {
    _generation++;
    unawaited(_gps?.cancel());
    unawaited(_compass?.cancel());
    _gps = null;
    _compass = null;
    heading.value = null;
    _headingFilter.reset();
  }

  Future<void> start({bool requestPermission = true}) async {
    if (_disposed || busy) return;
    enabled = true;
    _cancel();
    final generation = _generation;
    busy = true;
    position.value = null;
    accuracy = null;
    action = LocationAction.retry;
    status = 'Đang kiểm tra GPS và quyền vị trí…';
    notifyListeners();
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_current(generation)) return;
      if (!serviceEnabled) {
        action = LocationAction.locationSettings;
        status = 'GPS đang tắt. Hãy bật dịch vụ vị trí.';
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!_current(generation)) return;
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (!_current(generation)) return;
      if (permission == LocationPermission.deniedForever) {
        action = LocationAction.appSettings;
        status = 'Quyền vị trí bị khóa. Hãy mở cài đặt ứng dụng.';
        return;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        status = 'Chưa có quyền truy cập vị trí.';
        return;
      }
      status = 'Đang chờ vị trí GPS…';
      final LocationSettings settings =
          defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
              intervalDuration: const Duration(seconds: 1),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            );
      _gps = Geolocator.getPositionStream(locationSettings: settings).listen(
        (value) {
          if (!_current(generation)) return;
          if (!value.latitude.isFinite ||
              !value.longitude.isFinite ||
              value.latitude.abs() > 90 ||
              value.longitude.abs() > 180) {
            return;
          }
          position.value = LatLng(value.latitude, value.longitude);
          accuracy = value.accuracy;
          status = 'Vị trí thiết bị • ±${value.accuracy.round()} m';
          notifyListeners();
        },
        onError: (Object error) {
          if (!_current(generation)) return;
          _cancel();
          position.value = null;
          status = 'Mất vị trí GPS. Kiểm tra quyền/GPS rồi thử lại.';
          notifyListeners();
        },
      );
      _startCompass(generation);
    } catch (_) {
      if (_current(generation)) {
        status = 'Không thể đọc vị trí trên thiết bị này. Hãy thử lại.';
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _startCompass(int generation) {
    try {
      final events = FlutterCompass.events;
      if (events == null) {
        compassStatus = 'Thiết bị không hỗ trợ la bàn';
        return;
      }
      compassStatus = 'Đang chờ la bàn';
      _compass = events.listen(
        (event) {
          if (!_current(generation)) return;
          final value = event.heading;
          if (value == null || !value.isFinite || value < 0) {
            heading.value = null;
            _headingFilter.reset();
            if (compassStatus != 'Không có dữ liệu la bàn') {
              compassStatus = 'Không có dữ liệu la bàn';
              notifyListeners();
            }
            return;
          }
          final accepted = _headingFilter.accept(value, _clock.elapsed);
          if (accepted == null) return;
          heading.value = accepted;
          if (compassStatus != 'La bàn đang hoạt động') {
            compassStatus = 'La bàn đang hoạt động';
            notifyListeners();
          }
        },
        onError: (Object error) {
          if (!_current(generation)) return;
          heading.value = null;
          _headingFilter.reset();
          compassStatus = 'Không đọc được la bàn';
          notifyListeners();
        },
      );
    } catch (_) {
      compassStatus = 'Thiết bị không hỗ trợ la bàn';
    }
  }

  void suspend() {
    if (_disposed) return;
    _cancel();
    busy = false;
    position.value = null;
    status = 'Đã dừng cảm biến khi ứng dụng vào nền';
    notifyListeners();
  }

  Future<void> openSettings() async {
    try {
      if (action == LocationAction.appSettings) {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.openLocationSettings();
      }
    } catch (_) {
      if (!_disposed) {
        status = 'Hãy mở cài đặt vị trí của điện thoại để cấp quyền.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _cancel();
    _disposed = true;
    _clock.stop();
    position.dispose();
    heading.dispose();
    super.dispose();
  }
}
