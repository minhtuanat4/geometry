/// Travel profiles supported by the app's transport filter.
enum TransportMode {
  motorcycle('motorcycle', 'Xe máy'),
  car('drive', 'Ô tô'),
  walking('walk', 'Đi bộ'),
  bus('bus', 'Xe bus');

  const TransportMode(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static TransportMode fromApiValue(String value) => values.firstWhere(
    (mode) => mode.apiValue == value,
    orElse: () => motorcycle,
  );
}
