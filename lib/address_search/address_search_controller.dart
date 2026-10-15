import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'address_search_service.dart';

class AddressSearchState {
  const AddressSearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.error,
  });
  final String query;
  final bool loading;
  final List<AddressSuggestion> results;
  final String? error;
}

class AddressSearchController extends ValueNotifier<AddressSearchState> {
  AddressSearchController({required this.service, this.near})
    : super(const AddressSearchState());
  final AddressSearchService service;
  final LatLng? near;
  Timer? _debounce;
  int _revision = 0;
  bool _disposed = false;

  void queryChanged(String input) {
    final query = input.trim();
    _debounce?.cancel();
    final revision = ++_revision;
    value = AddressSearchState(query: query, loading: query.length >= 3);
    if (query.length < 3) return;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query, revision),
    );
  }

  void retry() {
    _debounce?.cancel();
    if (value.query.length >= 3) _search(value.query, ++_revision);
  }

  Future<void> _search(String query, int revision) async {
    value = AddressSearchState(query: query, loading: true);
    try {
      final results = await service.search(query, near: near);
      if (_disposed || revision != _revision) return;
      value = AddressSearchState(query: query, results: results);
    } catch (error) {
      if (_disposed || revision != _revision) return;
      value = AddressSearchState(
        query: query,
        error: error is AddressSearchException
            ? error.message
            : 'Không thể tìm địa chỉ. Kiểm tra kết nối và thử lại.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _debounce?.cancel();
    super.dispose();
  }
}
