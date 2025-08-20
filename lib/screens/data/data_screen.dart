import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../providers/app_providers.dart';
import '../../widgets/sensor_card.dart';
import '../../widgets/date_range_picker.dart';
import '../../models/agri_node.dart';
import '../../services/firestore_data_service.dart';
import '../../services/offline_storage_service.dart';

class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange? _selectedDateRange;
  String? _selectedDeviceId;
  List<SensorData> _historicalData = [];
  List<String> _availableDeviceIds = [];
  bool _isLoadingHistorical = false;
  bool _isSyncing = false;
  int _historyViewIndex = 0; // 0: Cards, 1: Table, 2: Chart
  bool _isFilterExpanded = false; // For collapsible filters

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAvailableDevices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableDevices() async {
    try {
      // Get device IDs from both Firestore and offline storage
      final Set<String> allDeviceIds = <String>{};

      // Get from offline storage first (always available)
      List<String> offlineDeviceIds = [];
      try {
        offlineDeviceIds = await OfflineStorageService.instance
            .getUniqueDeviceIds();
        allDeviceIds.addAll(offlineDeviceIds);
      } catch (e) {
        if (kDebugMode) {
          print('Could not load device IDs from offline storage: $e');
        }
      }

      // Get from Firestore using a broader query approach
      List<String> firestoreDeviceIds = [];
      try {
        // Query a reasonable time range to get most device IDs
        final now = DateTime.now();
        final threeMonthsAgo = now.subtract(const Duration(days: 90));

        // Get data without device filter to see all devices
        final firestoreData = await FirestoreDataService.instance
            .getSensorDataWithOffline(
              startDate: threeMonthsAgo,
              endDate: now,
              limit: 5000, // Large limit to get representative sample
            );

        firestoreDeviceIds = firestoreData
            .map((data) => data.deviceId)
            .toSet()
            .toList();
        allDeviceIds.addAll(firestoreDeviceIds);
      } catch (e) {
        if (kDebugMode) {
          print('Could not load device IDs from Firestore: $e');
        }
      }

      if (mounted) {
        setState(() {
          _availableDeviceIds = allDeviceIds.toList()..sort();
        });

        // Debug output
        if (kDebugMode) {
          print('Available device IDs: $_availableDeviceIds');
        }
        if (kDebugMode) {
          print('Offline device IDs count: ${offlineDeviceIds.length}');
        }
        if (kDebugMode) {
          print('Firestore device IDs count: ${firestoreDeviceIds.length}');
        }
        if (offlineDeviceIds.isNotEmpty) {
          if (kDebugMode) {
            print('Offline devices: $offlineDeviceIds');
          }
        }
        if (firestoreDeviceIds.isNotEmpty) {
          if (kDebugMode) {
            print('Firestore devices: $firestoreDeviceIds');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading devices: $e')));
      }
    }
  }

  Future<void> _loadHistoricalData() async {
    setState(() {
      _isLoadingHistorical = true;
    });

    try {
      // Get data from both Firestore and offline storage, then combine and deduplicate
      final List<SensorData> allData = <SensorData>[];

      // Get from Firestore
      try {
        final firestoreData = await FirestoreDataService.instance
            .getSensorDataWithOffline(
              startDate: _selectedDateRange?.start,
              endDate: _selectedDateRange?.end,
              deviceId: _selectedDeviceId,
              limit: 1000,
            );
        allData.addAll(firestoreData);
      } catch (e) {
        if (kDebugMode) {
          print('Error loading Firestore data: $e');
        }
      }

      // Get from offline storage
      try {
        final offlineData = await OfflineStorageService.instance
            .getSensorDataOffline(
              startDate: _selectedDateRange?.start,
              endDate: _selectedDateRange?.end,
              deviceId: _selectedDeviceId,
            );
        allData.addAll(offlineData);
      } catch (e) {
        if (kDebugMode) {
          print('Error loading offline data: $e');
        }
      }

      // Deduplicate based on deviceId + timestamp combination
      final Map<String, SensorData> uniqueData = {};
      for (final data in allData) {
        final key = '${data.deviceId}_${data.timestamp.millisecondsSinceEpoch}';
        uniqueData[key] = data;
      }

      // Convert to list and sort by timestamp (newest first)
      final sortedData = uniqueData.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _historicalData = sortedData;
          _isLoadingHistorical = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistorical = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading historical data: $e')),
        );
      }
    }
  }

  void _onDateRangeChanged(DateTimeRange? dateRange) {
    setState(() {
      _selectedDateRange = dateRange;
    });
    _loadHistoricalData();
  }

  void _onDeviceChanged(String? deviceId) {
    setState(() {
      _selectedDeviceId = deviceId;
    });
    _loadHistoricalData();
  }

  Future<void> _manualSync() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      // Force refresh providers to get latest data from Firebase
      ref.invalidate(currentSensorDataProvider);

      // Reload available devices and historical data
      await _loadAvailableDevices();
      if (_selectedDateRange != null) {
        await _loadHistoricalData();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data synced successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Live Data', icon: Icon(Icons.sensors)),
              Tab(text: 'History', icon: Icon(Icons.history)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildLiveDataTab(), _buildHistoryTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveDataTab() {
    final currentSensorData = ref.watch(currentSensorDataProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentSensorDataProvider);
      },
      child: currentSensorData.when(
        data: (sensorDataMap) {
          if (sensorDataMap.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors_off, size: 64),
                  SizedBox(height: 16),
                  Text('No Live Data Available'),
                  SizedBox(height: 8),
                  Text('Connect to SmartAgriMesh to view sensor data'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sensorDataMap.length,
            itemBuilder: (context, index) {
              final entry = sensorDataMap.entries.elementAt(index);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SensorCard(sensorData: entry.value),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(currentSensorDataProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Control bar with sync button and view switcher - optimized for mobile
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  // Manual sync button - smaller for mobile
                  FilledButton.icon(
                    onPressed: _isSyncing ? null : _manualSync,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: Text(_isSyncing ? 'Syncing...' : 'Sync'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 6),
              // View switcher - full width for mobile
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  selected: {_historyViewIndex},
                  onSelectionChanged: (Set<int> selection) {
                    setState(() {
                      _historyViewIndex = selection.first;
                    });
                  },
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      icon: Icon(Icons.view_agenda, size: 16),
                      label: Text('Cards', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      icon: Icon(Icons.table_chart, size: 16),
                      label: Text('Table', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<int>(
                      value: 2,
                      icon: Icon(Icons.show_chart, size: 16),
                      label: Text('Chart', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Date range picker and device selector - collapsible for mobile
        Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _isFilterExpanded = !_isFilterExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_list,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (_selectedDateRange != null ||
                          _selectedDeviceId != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Active',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Icon(
                        _isFilterExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isFilterExpanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date range picker
                      DateRangePicker(
                        initialDateRange: _selectedDateRange,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        onDateRangeChanged: _onDateRangeChanged,
                        helpText: 'Select date range',
                      ),
                      const SizedBox(height: 8),
                      // Quick date range selector
                      QuickDateRangeSelector(
                        onDateRangeChanged: _onDateRangeChanged,
                      ),
                      const SizedBox(height: 8),
                      // Device selector
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Device Filter',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                '${_availableDeviceIds.length} device(s)',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                      fontSize: 11,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (_availableDeviceIds.isNotEmpty)
                            DropdownButtonFormField<String>(
                              value: _selectedDeviceId,
                              decoration: const InputDecoration(
                                labelText: 'Select Device',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 13),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Devices'),
                                ),
                                ..._availableDeviceIds.map((deviceId) {
                                  return DropdownMenuItem<String>(
                                    value: deviceId,
                                    child: FutureBuilder<String>(
                                      future: OfflineStorageService.instance
                                          .getDeviceNameById(deviceId),
                                      builder: (context, snapshot) {
                                        final deviceName =
                                            snapshot.data ?? deviceId;
                                        return Text('$deviceName ($deviceId)');
                                      },
                                    ),
                                  );
                                }),
                              ],
                              onChanged: _onDeviceChanged,
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.devices_other,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'No devices found',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Download data from nodes or sync to see available devices',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                          fontSize: 11,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Offline status indicator - compact for mobile
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Consumer(
            builder: (context, ref, child) {
              final connectionStatus = ref.watch(connectionStatusProvider);
              return connectionStatus.when(
                data: (isConnected) => Row(
                  children: [
                    Icon(
                      isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: isConnected ? Colors.green : Colors.orange,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isConnected
                            ? 'Online - Firebase & Local'
                            : 'Offline - Local Only',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Checking...',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                error: (error, stackTrace) => Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Connection unknown',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Historical data content
        Expanded(
          child: _isLoadingHistorical
              ? const Center(child: CircularProgressIndicator())
              : _historicalData.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Historical Data',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedDateRange != null
                            ? 'No data found for the selected date range'
                            : 'Select a date range to view historical data',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            _selectedDateRange = null;
                            _selectedDeviceId = null;
                          });
                          _loadHistoricalData();
                        },
                        child: const Text('Reset Filters'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistoricalData,
                  child: _buildHistoryDataView(),
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryDataView() {
    return Column(
      children: [
        // Data summary - compact for mobile
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_historicalData.length} records${_selectedDateRange != null ? ' in range' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (_historicalData.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _selectedDeviceId != null
                      ? 'Device: $_selectedDeviceId'
                      : '${_historicalData.map((d) => d.deviceId).toSet().length} device(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),

        // View content based on selected view
        Expanded(
          child: switch (_historyViewIndex) {
            0 => _buildCardsView(),
            1 => _buildTableView(),
            2 => _buildChartView(),
            _ => _buildCardsView(),
          },
        ),
      ],
    );
  }

  Widget _buildCardsView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _historicalData.length,
      itemBuilder: (context, index) {
        final sensorData = _historicalData[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SensorCard(sensorData: sensorData),
        );
      },
    );
  }

  Widget _buildTableView() {
    if (_historicalData.isEmpty) {
      return const Center(child: Text('No data to display'));
    }

    final dateFormat = DateFormat('MMM dd, HH:mm');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          columnSpacing: 12,
          horizontalMargin: 12,
          headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          dataTextStyle: const TextStyle(fontSize: 11),
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Device')),
            DataColumn(label: Text('Temp (°C)')),
            DataColumn(label: Text('Humidity (%)')),
            DataColumn(label: Text('Moisture (%)')),
            DataColumn(label: Text('Distance (cm)')),
            DataColumn(label: Text('Motion')),
          ],
          rows: _historicalData.map((data) {
            return DataRow(
              cells: [
                DataCell(Text(dateFormat.format(data.timestamp))),
                DataCell(
                  Text(data.deviceId, style: const TextStyle(fontSize: 10)),
                ),
                DataCell(Text(data.temperature.toStringAsFixed(1))),
                DataCell(Text(data.humidity.toStringAsFixed(1))),
                DataCell(Text(data.soilMoisture.toString())),
                DataCell(Text(data.distance.toStringAsFixed(1))),
                DataCell(
                  Icon(
                    data.motionDetected ? Icons.check : Icons.close,
                    color: data.motionDetected ? Colors.green : Colors.red,
                    size: 14,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChartView() {
    if (_historicalData.isEmpty) {
      return const Center(child: Text('No data to display'));
    }

    // Group data by device ID for multiple lines
    final Map<String, List<SensorData>> deviceData = {};
    for (final data in _historicalData) {
      final deviceId = data.deviceId;
      deviceData.putIfAbsent(deviceId, () => []).add(data);
    }

    // Sort each device's data by timestamp
    for (final data in deviceData.values) {
      data.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelStyle: const TextStyle(fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: const [
              Tab(text: 'Temperature'),
              Tab(text: 'Humidity'),
              Tab(text: 'Soil Moisture'),
              Tab(text: 'Distance'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildLineChart(
                  'Temperature',
                  '°C',
                  (data) => data.temperature,
                ),
                _buildLineChart('Humidity', '%', (data) => data.humidity),
                _buildLineChart(
                  'Soil Moisture',
                  '%',
                  (data) => data.soilMoisture.toDouble(),
                ),
                _buildLineChart('Distance', 'cm', (data) => data.distance),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(
    String title,
    String unit,
    double? Function(SensorData) getValue,
  ) {
    final deviceData = <String, List<SensorData>>{};
    for (final data in _historicalData) {
      final deviceId = data.deviceId;
      deviceData.putIfAbsent(deviceId, () => []).add(data);
    }

    for (final data in deviceData.values) {
      data.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    final lines = deviceData.entries.map((entry) {
      final deviceId = entry.key;
      final data = entry.value;
      final colorIndex =
          deviceData.keys.toList().indexOf(deviceId) % colors.length;

      final spots = data
          .where((d) => getValue(d) != null)
          .toList()
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), getValue(e.value)!))
          .toList();

      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: colors[colorIndex],
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            '$title ($unit)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 9),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 25,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _historicalData.length) {
                          final format = DateFormat('HH:mm');
                          return Text(
                            format.format(_historicalData[index].timestamp),
                            style: const TextStyle(fontSize: 9),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: lines,
              ),
            ),
          ),
          if (deviceData.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: deviceData.keys.map((deviceId) {
                final colorIndex =
                    deviceData.keys.toList().indexOf(deviceId) % colors.length;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: colors[colorIndex]),
                    const SizedBox(width: 4),
                    Text(deviceId, style: const TextStyle(fontSize: 10)),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
