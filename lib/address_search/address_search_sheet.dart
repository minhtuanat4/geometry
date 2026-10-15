import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../routing/transport_mode.dart';
import 'address_search_controller.dart';
import 'address_search_service.dart';

class AddressSearchSheet extends StatefulWidget {
  const AddressSearchSheet({
    super.key,
    required this.service,
    required this.transportMode,
    this.near,
  });
  final AddressSearchService service;
  final ValueNotifier<TransportMode> transportMode;
  final LatLng? near;

  @override
  State<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<AddressSearchSheet> {
  late final AddressSearchController _search;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search = AddressSearchController(
      service: widget.service,
      near: widget.near,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _text.dispose();
    super.dispose();
  }

  IconData _modeIcon(TransportMode mode) => switch (mode) {
    TransportMode.motorcycle => Icons.two_wheeler,
    TransportMode.car => Icons.directions_car,
    TransportMode.walking => Icons.directions_walk,
    TransportMode.bus => Icons.directions_bus,
  };

  Widget _results(AddressSearchState state) {
    if (state.query.length < 3) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Nhập ít nhất 3 ký tự để tìm địa chỉ.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            TextButton(onPressed: _search.retry, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    if (state.results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Chưa có kết quả phù hợp. Thử thêm tên đường, quận hoặc tỉnh.',
        ),
      );
    }
    return Column(
      children: [
        for (final address in state.results) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: Text(address.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, address),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        // Scroll the entire sheet so the filters/results stay accessible with a keyboard.
        child: ListView(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tìm điểm đến',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng tìm kiếm',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('Tìm địa chỉ tại Việt Nam, ưu tiên gần vị trí của bạn.'),
            const SizedBox(height: 12),
            ValueListenableBuilder<TransportMode>(
              valueListenable: widget.transportMode,
              builder: (context, selected, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final mode in TransportMode.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('transport-mode-${mode.name}'),
                              avatar: Icon(_modeIcon(mode), size: 18),
                              label: Text(mode.label),
                              selected: selected == mode,
                              onSelected: (_) =>
                                  widget.transportMode.value = mode,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected == TransportMode.bus)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Xe bus: tính đường cho xe bus, chưa gồm số tuyến và lịch chạy.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('destination-search-field'),
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _search.queryChanged,
              onSubmitted: (_) => _search.retry(),
              decoration: InputDecoration(
                hintText: 'Nhập địa chỉ hoặc tên địa điểm',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Xóa tìm kiếm',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _text.clear();
                    _search.queryChanged('');
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<AddressSearchState>(
              valueListenable: _search,
              builder: (context, state, _) => _results(state),
            ),
            const SizedBox(height: 12),
            const Text(
              'Powered by Geoapify • Chọn điểm đến để đánh dấu trên bản đồ.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
