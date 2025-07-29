// In fsu_utils.dart


double? calculateFSU(double startGravity, double endGravity, Duration difference) {
  // Calculate days as a decimal value for more precision
  final double days = difference.inMilliseconds / Duration.millisecondsPerDay;

  if (days <= 0) return null;

  final delta = startGravity - endGravity;
  if (delta <= 0) return null;

  final fsu = (delta * 100000) / days;
  return double.parse(fsu.toStringAsFixed(1));
}