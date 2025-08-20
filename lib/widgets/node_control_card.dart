import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agri_node.dart';
import '../providers/app_providers.dart';
import '../services/offline_storage_service.dart';

class NodeControlCard extends ConsumerStatefulWidget {
  final AgriNode node;
  final SensorData? sensorData;

  const NodeControlCard({super.key, required this.node, this.sensorData});

  @override
  ConsumerState<NodeControlCard> createState() => _NodeControlCardState();
}

class _NodeControlCardState extends ConsumerState<NodeControlCard> {
  bool _isControlling = false;
  Map<String, dynamic>? _lastDebugInfo;

  @override
  Widget build(BuildContext context) {
    final networkService = ref.read(networkServiceProvider);
    final isHomeNode =
        widget.node.deviceId == networkService.homeNode?.deviceId;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  isHomeNode ? Icons.home : Icons.device_hub,
                  color: isHomeNode ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.node.deviceName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isHomeNode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'HOME NODE',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Node Info
            Text(
              'Node ID: ${widget.node.deviceId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'IP: ${widget.node.ipAddress}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.node.availableEndpoints.contains('Mesh Relay'))
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Relay Only',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Sensor Data
            if (widget.sensorData != null) ...[
              const Text(
                'Live Sensor Data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildSensorDataRow(
                'Temperature',
                '${widget.sensorData!.temperature.toStringAsFixed(1)}°C',
              ),
              _buildSensorDataRow(
                'Humidity',
                '${widget.sensorData!.humidity.toStringAsFixed(1)}%',
              ),
              _buildSensorDataRow(
                'Soil Moisture',
                '${widget.sensorData!.soilMoisture}%',
              ),
              _buildSensorDataRow(
                'Motion',
                widget.sensorData!.motionDetected ? 'Detected' : 'Clear',
              ),
              _buildSensorDataRow(
                'Distance',
                '${widget.sensorData!.distance.toStringAsFixed(1)}cm',
              ),
              _buildSensorDataRow(
                'Buzzer',
                widget.sensorData!.buzzerActive ? 'ON' : 'OFF',
              ),
              const SizedBox(height: 12),
            ],

            // Control Buttons
            Row(
              children: [
                // Buzzer Controls
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Buzzer Control:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _buildControlButton(
                              'ON',
                              Icons.volume_up,
                              Colors.green,
                              () => _controlBuzzer('on'),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildControlButton(
                              'OFF',
                              Icons.volume_off,
                              Colors.red,
                              () => _controlBuzzer('off'),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildControlButton(
                              'TOGGLE',
                              Icons.toggle_on,
                              Colors.orange,
                              () => _controlBuzzer('toggle'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isControlling ? null : _refreshData,
                    icon: _isControlling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isControlling ? null : _testBuzzerConnectivity,
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Debug'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: 'Download all JSON files from SD card',
                    child: ElevatedButton.icon(
                      onPressed: _isControlling ? null : _downloadHistory,
                      icon: const Icon(Icons.download),
                      label: const Text('Download All'),
                    ),
                  ),
                ),
              ],
            ),

            // Debug Information Section
            if (_lastDebugInfo != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.grey[100],
                child: ExpansionTile(
                  title: Row(
                    children: [
                      Icon(
                        _lastDebugInfo!['success'] == true
                            ? Icons.check_circle
                            : Icons.error,
                        color: _lastDebugInfo!['success'] == true
                            ? Colors.green
                            : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Buzzer Debug Info',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_buildDebugInfoDisplay()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: _isControlling ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
      ),
    );
  }

  Future<void> _controlBuzzer(String action) async {
    setState(() {
      _isControlling = true;
    });

    try {
      final networkService = ref.read(networkServiceProvider);
      final success = await networkService.controlBuzzer(
        widget.node.deviceId,
        action,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Buzzer $action command sent successfully!'
                  : 'Failed to send buzzer $action command',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );

        // Refresh data after control action
        if (success) {
          await _refreshData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error controlling buzzer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isControlling = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isControlling = true;
    });

    try {
      final networkService = ref.read(networkServiceProvider);
      final sensorData = await networkService.getNodeLiveData(
        widget.node.deviceId,
      );

      if (mounted) {
        if (sensorData != null) {
          // Trigger a rebuild with fresh data
          ref.invalidate(currentSensorDataProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data refreshed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to refresh data'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isControlling = false;
        });
      }
    }
  }

  Future<void> _downloadHistory() async {
    setState(() {
      _isControlling = true;
    });

    try {
      final networkService = ref.read(networkServiceProvider);

      // First, try to get all available files from SD card using optimized method
      final files = await networkService.getAvailableDataFilesOptimized(
        widget.node.ipAddress,
      );

      if (files.isNotEmpty) {
        // Download all files from SD card
        await _downloadAllSDCardFiles(files);
      } else {
        // Fallback to historical data endpoint if SD card files not available
        final historyData = await networkService.getNodeHistoricalData(
          widget.node.deviceId,
        );

        if (mounted) {
          if (historyData != null && historyData.isNotEmpty) {
            _showHistoryDialog(historyData);

            // Show notification that data was saved locally
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '💾 Downloaded ${historyData.length} records from history endpoint and saved locally. Check Data tab!',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No data available from any source'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isControlling = false;
        });
      }
    }
  }

  Future<void> _downloadAllSDCardFiles(List<String> files) async {
    final networkService = ref.read(networkServiceProvider);
    final firestoreService = ref.read(firestoreDataServiceProvider);
    final offlineService = OfflineStorageService.instance;

    if (kDebugMode) {
      print(
        '📦 Starting optimized batch download of ${files.length} files from ${widget.node.deviceName}',
      );
    }

    // Use the new batch download method for better performance
    final downloadResults = await networkService.downloadAllDataFilesBatch(
      widget.node.ipAddress,
      files,
    );

    List<String> downloadedFiles = downloadResults.keys.toList();
    List<String> failedFiles = files
        .where((f) => !downloadResults.containsKey(f))
        .toList();

    Map<String, dynamic> allData = {
      'nodeId': widget.node.deviceId,
      'deviceName': widget.node.deviceName,
      'downloadedAt': DateTime.now().toIso8601String(),
      'files': <String, dynamic>{},
    };

    // Track all sensor readings for storage
    List<SensorReading> allSensorReadings = [];
    List<SensorData> allSensorDataPoints = [];

    // Process downloaded files
    for (final entry in downloadResults.entries) {
      final fileName = entry.key;
      final fileContent = entry.value;

      if (kDebugMode) {
        print(
          'Processing downloaded file: $fileName, content length: ${fileContent.length}',
        );
      }

      // Parse JSON content and store it
      try {
        final jsonData = json.decode(fileContent);
        allData['files'][fileName] = jsonData;

        // Process different file types and extract sensor data
        await _processSensorDataFromFile(
          fileName,
          jsonData,
          allSensorReadings,
          allSensorDataPoints,
        );
      } catch (e) {
        // If JSON parsing fails, try line-by-line processing for SD card files
        allData['files'][fileName] = fileContent;

        if (kDebugMode) {
          print(
            'Single JSON parse failed for $fileName, trying line-by-line format...',
          );
        }

        // Handle line-by-line JSON format (common in SD card files)
        final lines = fileContent.split('\n');
        bool foundValidData = false;

        for (final line in lines) {
          if (line.trim().isNotEmpty) {
            try {
              final lineData = json.decode(line.trim());
              if (lineData is Map<String, dynamic>) {
                foundValidData = true;

                // Process this line as sensor data
                await _processSensorDataFromFile(
                  fileName,
                  lineData,
                  allSensorReadings,
                  allSensorDataPoints,
                );
              }
            } catch (lineError) {
              // Skip invalid lines, continue processing
              continue;
            }
          }
        }

        if (!foundValidData && kDebugMode) {
          if (kDebugMode) {
            print(
              'No valid JSON data found in $fileName after line-by-line processing',
            );
          }
        }
      }
    }

    // Save all collected sensor data to offline storage and Firebase
    if (allSensorReadings.isNotEmpty || allSensorDataPoints.isNotEmpty) {
      try {
        // Save individual sensor data points to offline storage
        for (final sensorData in allSensorDataPoints) {
          await offlineService.saveSensorDataOffline(sensorData);
        }

        // Save historical readings batch to Firebase (when online)
        if (allSensorReadings.isNotEmpty) {
          await firestoreService.saveHistoricalDataBatch(
            allSensorReadings,
            widget.node.deviceId,
            widget.node.deviceName,
            widget.node.ipAddress,
          );
        }

        // Save individual sensor data points to Firebase as well
        for (final sensorData in allSensorDataPoints) {
          await firestoreService.saveSensorData(sensorData);
        }

        if (kDebugMode) {
          print(
            '💾 Synced ${allSensorReadings.length} readings and ${allSensorDataPoints.length} data points to storage',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error syncing downloaded data: $e');
        }
      }
    }

    if (mounted) {
      String message;
      if (downloadedFiles.isNotEmpty) {
        message = '💾 Downloaded ${downloadedFiles.length} SD card files';
        if (allSensorReadings.isNotEmpty || allSensorDataPoints.isNotEmpty) {
          message +=
              ' and synced ${allSensorReadings.length + allSensorDataPoints.length} data points';
        }
        if (failedFiles.isNotEmpty) {
          message += ' (${failedFiles.length} failed)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showAllDataDialog(allData),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to download any files from ${widget.node.deviceName}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processSensorDataFromFile(
    String fileName,
    dynamic jsonData,
    List<SensorReading> allSensorReadings,
    List<SensorData> allSensorDataPoints,
  ) async {
    try {
      if (fileName.startsWith('node_') || fileName.startsWith('received_')) {
        // These files contain line-by-line sensor data
        if (jsonData is String) {
          // Handle line-by-line JSON format
          final lines = jsonData.split('\n');
          for (final line in lines) {
            if (line.trim().isNotEmpty) {
              try {
                final lineData = json.decode(line.trim());
                _extractSensorReadingFromJson(
                  lineData,
                  allSensorReadings,
                  allSensorDataPoints,
                );
              } catch (e) {
                // Skip invalid lines
                continue;
              }
            }
          }
        } else if (jsonData is Map) {
          // Handle single JSON object
          _extractSensorReadingFromJson(
            Map<String, dynamic>.from(jsonData),
            allSensorReadings,
            allSensorDataPoints,
          );
        } else if (jsonData is List) {
          // Handle array of JSON objects
          for (final item in jsonData) {
            if (item is Map) {
              _extractSensorReadingFromJson(
                Map<String, dynamic>.from(item),
                allSensorReadings,
                allSensorDataPoints,
              );
            }
          }
        }
      } else if (fileName == 'mesh_summary.json') {
        // Process mesh summary which contains data from all nodes
        if (jsonData is Map && jsonData.containsKey('allNodes')) {
          final allNodes = jsonData['allNodes'] as List;
          for (final nodeData in allNodes) {
            if (nodeData is Map) {
              _extractSensorReadingFromJson(
                Map<String, dynamic>.from(nodeData),
                allSensorReadings,
                allSensorDataPoints,
              );
            }
          }
        }
      } else if (fileName == 'shared_data_log.json') {
        // Process shared data log entries
        if (jsonData is String) {
          final lines = jsonData.split('\n');
          for (final line in lines) {
            if (line.trim().isNotEmpty) {
              try {
                final lineData = json.decode(line.trim());
                if (lineData is Map && lineData.containsKey('activeNodes')) {
                  // This is a log entry, can be used for network analysis but not sensor data
                  continue;
                }
              } catch (e) {
                continue;
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing file $fileName: $e');
      }
    }
  }

  void _extractSensorReadingFromJson(
    Map<String, dynamic> data,
    List<SensorReading> allSensorReadings,
    List<SensorData> allSensorDataPoints,
  ) {
    try {
      // Extract timestamp
      DateTime timestamp;
      final timeValue = data['time'] ?? data['timestamp'] ?? data['receivedAt'];
      if (timeValue is int) {
        // Convert from milliseconds or seconds
        if (timeValue > 1000000000000) {
          // Milliseconds
          timestamp = DateTime.fromMillisecondsSinceEpoch(timeValue);
        } else {
          // Seconds - convert from Arduino millis() to actual timestamp
          // Note: Arduino millis() is time since device boot, not epoch time
          // We'll use current time minus some offset as approximation
          timestamp = DateTime.now().subtract(
            Duration(
              milliseconds: DateTime.now().millisecondsSinceEpoch - timeValue,
            ),
          );
        }
      } else {
        timestamp = DateTime.now(); // Fallback
      }

      // Extract device info
      final deviceId =
          data['id'] ??
          data['nodeId'] ??
          data['deviceId'] ??
          widget.node.deviceId;
      final deviceName =
          data['name'] ?? data['deviceName'] ?? widget.node.deviceName;

      // Skip processing if deviceId is null, empty, or invalid
      if (deviceId == null ||
          deviceId.toString().isEmpty ||
          deviceId.toString() == 'null' ||
          deviceId.toString() == '0') {
        return;
      }

      // Extract sensor values with proper conversion
      final temperature = (data['temp'] ?? data['temperature'] ?? 0.0)
          .toDouble();
      final humidity = (data['hum'] ?? data['humidity'] ?? 0.0).toDouble();
      final soilMoisture = (data['soil'] ?? data['soilMoisture'] ?? 0).toInt();
      final motionDetected = data['motion'] ?? data['motionDetected'] ?? false;
      final distance = (data['dist'] ?? data['distance'] ?? 0.0).toDouble();
      final buzzerActive = data['buzz'] ?? data['buzzerActive'] ?? false;

      // Create SensorReading for Firebase historical data
      final sensorReading = SensorReading(
        timestamp: timestamp,
        temperature: temperature,
        humidity: humidity,
        soilMoisture: soilMoisture,
        motionDetected: motionDetected,
        distance: distance,
        buzzerActive: buzzerActive,
      );
      allSensorReadings.add(sensorReading);

      // Create SensorData for compatibility with existing systems
      final sensorData = SensorData(
        deviceId: deviceId.toString(),
        deviceName: deviceName.toString(),
        timestamp: timestamp,
        temperature: temperature,
        humidity: humidity,
        soilMoisture: soilMoisture,
        motionDetected: motionDetected,
        distance: distance,
        buzzerActive: buzzerActive,
        stationIP: data['stationIP']?.toString() ?? widget.node.ipAddress,
        apIP: data['apIP']?.toString() ?? widget.node.ipAddress,
        isLocal: false, // SD card data is historical, not live
      );
      allSensorDataPoints.add(sensorData);
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting sensor data: $e');
      }
    }
  }

  void _showAllDataDialog(Map<String, dynamic> allData) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.storage,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SD Card Data: ${allData['deviceName']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Downloaded: ${allData['downloadedAt']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...((allData['files'] as Map<String, dynamic>).entries
                          .map((entry) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                leading: Icon(
                                  Icons.insert_drive_file,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  _getFileDescription(entry.key),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Text(
                                        _formatJsonData(entry.value),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // TODO: Implement save to device functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Save to device functionality coming soon!',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save to Device'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFileDescription(String fileName) {
    if (fileName.startsWith('node_')) {
      return 'Local sensor data from this node';
    } else if (fileName.startsWith('received_')) {
      return 'Sensor data received from mesh network';
    } else if (fileName == 'mesh_summary.json') {
      return 'Complete mesh network topology';
    } else if (fileName == 'shared_data_log.json') {
      return 'Historical mesh activity log';
    }
    return 'JSON data file';
  }

  String _formatJsonData(dynamic data) {
    try {
      // Pretty print JSON with indentation
      final encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
    }
  }

  void _showHistoryDialog(List<Map<String, dynamic>> historyData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historical Data - ${widget.node.deviceName}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: historyData.length,
            itemBuilder: (context, index) {
              final record = historyData[index];
              final timestamp = DateTime.fromMillisecondsSinceEpoch(
                (record['timestamp'] * 1000).toInt(),
              );

              return Card(
                child: ListTile(
                  title: Text(
                    '${timestamp.hour.toString().padLeft(2, '0')}:'
                    '${timestamp.minute.toString().padLeft(2, '0')}:'
                    '${timestamp.second.toString().padLeft(2, '0')}',
                  ),
                  subtitle: Text(
                    'T: ${record['temperature']?.toStringAsFixed(1)}°C, '
                    'H: ${record['humidity']?.toStringAsFixed(1)}%, '
                    'S: ${record['soilMoisture']}%',
                  ),
                  trailing: Icon(
                    record['buzzerActive'] == true
                        ? Icons.volume_up
                        : Icons.volume_off,
                    color: record['buzzerActive'] == true
                        ? Colors.red
                        : Colors.grey,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _testBuzzerConnectivity() async {
    setState(() {
      _isControlling = true;
    });

    try {
      final networkService = ref.read(networkServiceProvider);
      final debugInfo = await networkService.testBuzzerConnectivity(
        widget.node.deviceId,
      );

      if (mounted) {
        setState(() {
          _lastDebugInfo = debugInfo;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              debugInfo['success'] == true
                  ? 'Connectivity test completed successfully!'
                  : 'Connectivity test found issues - check debug info below',
            ),
            backgroundColor: debugInfo['success'] == true
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastDebugInfo = {
            'success': false,
            'error': e.toString(),
            'timestamp': DateTime.now().toIso8601String(),
          };
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Debug test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isControlling = false;
        });
      }
    }
  }

  Widget _buildDebugInfoDisplay() {
    if (_lastDebugInfo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Test Time: ${_lastDebugInfo!['timestamp']}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),

        if (_lastDebugInfo!['error'] != null) ...[
          _buildDebugSection('Error', _lastDebugInfo!['error'], Colors.red),
          const SizedBox(height: 8),
        ],

        if (_lastDebugInfo!['details'] != null) ...[
          _buildDebugDetailsSection(_lastDebugInfo!['details']),
        ],
      ],
    );
  }

  Widget _buildDebugSection(String title, dynamic content, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content.toString(),
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugDetailsSection(Map<String, dynamic> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details['targetNode'] != null) ...[
          _buildDebugSection(
            'Target Node',
            _formatNodeInfo(details['targetNode']),
            Colors.blue,
          ),
          const SizedBox(height: 8),
        ],

        if (details['pingTest'] != null) ...[
          _buildTestResultSection('Ping Test', details['pingTest']),
          const SizedBox(height: 8),
        ],

        if (details['buzzerTest'] != null) ...[
          _buildTestResultSection(
            'Buzzer Endpoint Test',
            details['buzzerTest'],
          ),
          const SizedBox(height: 8),
        ],

        if (details['relayScenario'] == true) ...[
          const Text(
            'Relay Scenario Detected',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 4),
          if (details['homeNode'] != null) ...[
            _buildDebugSection(
              'Home Node',
              _formatNodeInfo(details['homeNode']),
              Colors.green,
            ),
            const SizedBox(height: 8),
          ],
          if (details['relayTest'] != null) ...[
            _buildTestResultSection('Relay Test', details['relayTest']),
          ],
        ],
      ],
    );
  }

  Widget _buildTestResultSection(String title, Map<String, dynamic> test) {
    final success = test['success'] == true;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: (success ? Colors.green : Colors.red).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
        color: (success ? Colors.green : Colors.red).withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: success ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (test['url'] != null) ...[
            Text('URL: ${test['url']}', style: const TextStyle(fontSize: 10)),
          ],
          if (test['status'] != null) ...[
            Text(
              'Status: ${test['status']}',
              style: const TextStyle(fontSize: 10),
            ),
          ],
          if (test['error'] != null) ...[
            Text(
              'Error: ${test['error']}',
              style: const TextStyle(fontSize: 10, color: Colors.red),
            ),
          ],
          if (test['responseBody'] != null) ...[
            Text(
              'Response: ${test['responseBody']}',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  String _formatNodeInfo(Map<String, dynamic> node) {
    return '''Name: ${node['deviceName']}
ID: ${node['deviceId']}
IP: ${node['ipAddress']}
AP IP: ${node['apIP']}
Station IP: ${node['stationIP']}
Online: ${node['isOnline']}''';
  }
}
