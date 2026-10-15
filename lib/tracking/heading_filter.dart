import 'heading_math.dart';

// angularThresholdDegrees = 10
// minUpdateInterval = Duration(milliseconds: 600)
// animationDuration = Duration(milliseconds: 500)
/// Tune compass responsiveness here, or pass settings to DeviceLocation.
class HeadingSettings {
  const HeadingSettings({
    this.angularThresholdDegrees = 5,
    this.minUpdateInterval = const Duration(milliseconds: 300),
    this.animationDuration = const Duration(milliseconds: 200),
  }) : assert(angularThresholdDegrees >= 0 && angularThresholdDegrees < 180);

  final double angularThresholdDegrees;
  final Duration minUpdateInterval;
  final Duration animationDuration;
}

/// Compare against the last accepted target, not each noisy sensor sample.
class HeadingFilter {
  HeadingFilter(this.settings) {
    if (!settings.angularThresholdDegrees.isFinite ||
        settings.angularThresholdDegrees < 0 ||
        settings.angularThresholdDegrees >= 180 ||
        settings.minUpdateInterval <= Duration.zero ||
        settings.animationDuration <= Duration.zero ||
        settings.animationDuration > settings.minUpdateInterval) {
      throw ArgumentError(
        'Heading threshold must be in [0, 180); durations must '
        'be positive and animation must finish before the next update.',
      );
    }
  }
  final HeadingSettings settings;
  double? _acceptedHeading;
  Duration? _acceptedAt;

  double? accept(double value, Duration elapsed) {
    if (!value.isFinite || value < 0) return null;
    final previous = _acceptedHeading;
    final normalized = value % 360;
    if (previous != null) {
      if (elapsed - _acceptedAt! < settings.minUpdateInterval) return null;
      final delta = headingDelta(previous, normalized);
      if (delta.abs() <= settings.angularThresholdDegrees) return null;
      _acceptedHeading = previous + delta;
    } else {
      _acceptedHeading = normalized;
    }
    _acceptedAt = elapsed;
    return _acceptedHeading;
  }

  void reset() {
    _acceptedHeading = null;
    _acceptedAt = null;
  }
}
