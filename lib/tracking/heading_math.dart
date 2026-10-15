import 'dart:math' as math;

/// Signed shortest turn, so crossing 359° -> 1° moves two degrees.
double headingDelta(double from, double to) => (to - from + 540) % 360 - 180;

double headingRadians(double degrees) => degrees * math.pi / 180;
