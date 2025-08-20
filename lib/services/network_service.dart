import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Add this for custom HttpClient
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/agri_node.dart';
import 'firestore_data_service.dart';

class NetworkService {
  static const String meshSSID = 'SmartAgriMesh';
  static const String meshPassword = 'agrimesh2024';
  static const int httpPort = 80;
  static const int coapPort = 5683;
  static const Duration timeoutDuration = Duration(seconds: 3); // Much faster

  // Custom HTTP client for better Windows networking
  HttpClient? _httpClient;

  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();

  Timer? _discoveryTimer;
  Timer? _dataFetchTimer;

  final StreamController<List<AgriNode>> _nodesController =
      StreamController<List<AgriNode>>.broadcast();
  final StreamController<Map<String, SensorData>> _sensorDataController =
      StreamController<Map<String, SensorData>>.broadcast();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  // 📡 Scanning state streams for UI indicators
  final StreamController<bool> _isDiscoveringController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _isFetchingDataController =
      StreamController<bool>.broadcast();

  Stream<List<AgriNode>> get nodesStream => _nodesController.stream;
  Stream<Map<String, SensorData>> get sensorDataStream =>
      _sensorDataController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  // 📡 Scanning state streams for UI indicators
  Stream<bool> get isDiscoveringStream => _isDiscoveringController.stream;
  Stream<bool> get isFetchingDataStream => _isFetchingDataController.stream;

  List<AgriNode> _discoveredNodes = [];
  Map<String, SensorData> _sensorDataCache = {};
  bool _isConnectedToMesh = false;

  // Data sync service for local storage
  final FirestoreDataService _firestoreService = FirestoreDataService.instance;

  // 🎯 Discovery control flags
  bool _isDiscovering = false;
  bool _isFetchingData = false;
  bool _hasRunInitialDiscovery =
      false; // Track if we've done the launch discovery

  // Initialize custom HTTP client with Windows-friendly settings

  // Custom HTTP GET method using dart:io HttpClient with Android-friendly settings
  Future<String> _customHttpGet(String url) async {
    if (_httpClient == null) {
      _httpClient = HttpClient();
      // Configure for better Android compatibility
      _httpClient!.connectionTimeout = const Duration(seconds: 10);
      _httpClient!.idleTimeout = const Duration(seconds: 15);
      // Allow insecure connections for local network ESP32 devices
      _httpClient!.badCertificateCallback = (cert, host, port) => true;
    }

    final uri = Uri.parse(url);

    try {
      final request = await _httpClient!.getUrl(uri).timeout(timeoutDuration);

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'SmartAgriApp/1.0');
      request.headers.set('Accept', 'application/json');
      request.headers.set(
        'Connection',
        'close',
      ); // Avoid connection pooling issues

      final response = await request.close().timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        return responseBody;
      } else {
        throw HttpException(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Custom HTTP GET failed for $url: $e');
      }
      rethrow;
    }
  }

  Future<void> init() async {
    if (kDebugMode) {
      print('Initializing NetworkService...');
    }

    // Initialize scanning state streams with false
    _isDiscoveringController.add(false);
    _isFetchingDataController.add(false);

    // Debug network reachability on Android
    if (kDebugMode) {
      await debugNetworkReachability();
    }

    // Only check mesh connection - NO automatic discovery
    await _checkMeshConnection();

    // Start ONLY data fetching timer (no discovery timer)
    _startPeriodicDataFetch();

    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    if (kDebugMode) {
      print('NetworkService initialized - automatic discovery DISABLED');
      print('💡 Use manual refresh to discover nodes when needed');
    }
  }

  void dispose() {
    _discoveryTimer?.cancel();
    _dataFetchTimer?.cancel();
    _nodesController.close();
    _sensorDataController.close();
    _connectionStatusController.close();
    _isDiscoveringController.close();
    _isFetchingDataController.close();
  }

  Future<void> _checkMeshConnection() async {
    try {
      if (kDebugMode) {
        print('⚡ Checking mesh connection...');
      }

      // First check if we're on WiFi and get network info
      final connectivityResult = await _connectivity.checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        if (kDebugMode) {
          print('Not connected to WiFi');
        }
        _isConnectedToMesh = false;
        _connectionStatusController.add(false);
        return;
      }

      // Get current WiFi info
      final wifiName = await _networkInfo.getWifiName();
      final wifiIP = await _networkInfo.getWifiIP();

      if (kDebugMode) {
        print('WiFi: $wifiName, IP: $wifiIP');
      }

      // Set initial connection status optimistically
      _isConnectedToMesh = true;
      _connectionStatusController.add(true);

      // SINGLE automatic discovery on app launch only (once per app session)
      if (!_hasRunInitialDiscovery) {
        _hasRunInitialDiscovery = true;

        if (kDebugMode) {
          print('🚀 Running ONE-TIME automatic discovery on app launch...');
        }

        final discoveredNodes = await discoverNodes();
        if (discoveredNodes.isNotEmpty) {
          if (kDebugMode) {
            print(
              '✅ Launch discovery successful: ${discoveredNodes.length} nodes found',
            );
            print('💡 Future discoveries will be manual only');
          }
          // Start fetching data after a brief delay to let nodes settle
          Timer(Duration(seconds: 2), () async {
            if (_discoveredNodes.isNotEmpty) {
              await fetchAllSensorData();
            }
          });
        } else {
          if (kDebugMode) {
            print(
              '⚠️ Launch discovery found no nodes - use manual refresh to discover',
            );
          }
        }
      } else {
        if (kDebugMode) {
          print(
            '📡 Connection check complete - initial discovery already done',
          );
          print('💡 Use manual refresh for additional discoveries');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during network check: $e');
      }
      _isConnectedToMesh = false;
      _connectionStatusController.add(false);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      _checkMeshConnection();
    } else {
      _isConnectedToMesh = false;
      _connectionStatusController.add(false);
      _discoveredNodes.clear();
      _sensorDataCache.clear();
      _nodesController.add([]);
      _sensorDataController.add({});
    }
  }

  void _startPeriodicDataFetch() {
    _dataFetchTimer = Timer.periodic(Duration(seconds: 10), (_) async {
      // Slower, more ESP32-friendly interval
      if (_discoveredNodes.isNotEmpty && !_isFetchingData) {
        if (kDebugMode) {
          print('📡 Fetching data from ${_discoveredNodes.length} nodes...');
        }
        await fetchAllSensorData();
      }
    });
  }

  Future<List<AgriNode>> discoverNodes() async {
    // 🎯 Prevent multiple concurrent discoveries
    if (_isDiscovering) {
      if (kDebugMode) {
        print('⏳ Discovery already in progress, skipping...');
      }
      return _discoveredNodes;
    }

    _isDiscovering = true;
    _isDiscoveringController.add(true); // 📡 Notify UI about discovery start

    if (kDebugMode) {
      print('🔍 Starting controlled node discovery...');
    }

    List<AgriNode> discoveredNodes = [];

    try {
      // Show existing nodes immediately while discovering
      if (_discoveredNodes.isNotEmpty) {
        _nodesController.add(_discoveredNodes);
        if (kDebugMode) {
          print(
            '📡 Showing ${_discoveredNodes.length} existing nodes while discovering...',
          );
        }
      }

      // Method 1: Try enhanced mesh discovery with Android fallback
      final meshNodes = await _discoverMeshNodesEnhanced();
      discoveredNodes.addAll(meshNodes);

      // Remove duplicates based on deviceId
      final uniqueNodes = <String, AgriNode>{};
      for (final node in discoveredNodes) {
        uniqueNodes[node.deviceId] = node;
      }
      discoveredNodes = uniqueNodes.values.toList();

      // Update discovered nodes and immediately notify UI
      _discoveredNodes = discoveredNodes;
      _nodesController.add(_discoveredNodes);

      // Automatically save discovered nodes to Firestore
      if (_discoveredNodes.isNotEmpty) {
        for (final node in _discoveredNodes) {
          await _firestoreService.saveNode(node);
        }
      }

      if (kDebugMode) {
        print('✅ Discovery completed: ${discoveredNodes.length} nodes found');
        for (final node in discoveredNodes) {
          print(
            '  - ${node.deviceName} (${node.deviceId}) at ${node.ipAddress}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error during node discovery: $e');
      }
    } finally {
      _isDiscovering = false;
      _isDiscoveringController.add(false); // 📡 Notify UI about discovery end
    }

    return discoveredNodes;
  }

  Future<List<AgriNode>> _discoverMeshNodes() async {
    final List<AgriNode> nodes = [];

    try {
      // Try to get current WiFi IP to find potential gateways
      final wifiIP = await _networkInfo.getWifiIP();

      // List of potential gateway/node IPs to try
      final potentialIPs = <String>[];

      // PRIORITY 1: Add known good IPs from previous discoveries FIRST
      final knownGoodIPs = _discoveredNodes.map((n) => n.ipAddress).toList();
      for (final ip in knownGoodIPs) {
        if (!potentialIPs.contains(ip)) {
          potentialIPs.insert(
            0,
            ip,
          ); // Insert at beginning for highest priority
        }
      }

      if (wifiIP != null) {
        final ipParts = wifiIP.split('.');
        if (ipParts.length == 4) {
          final networkPrefix = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';
          potentialIPs.addAll([
            '$networkPrefix.1', // Common gateway
            '$networkPrefix.2', // Alternative gateway
            '$networkPrefix.100', // Common device IP
            wifiIP, // Current IP (might be a node)
          ]);
        }
      }

      // Add your specific working IPs with high priority
      final priorityIPs = [
        '10.145.169.1',
        '10.145.169.2',
        '10.35.17.1',
        '10.35.17.3',
        '192.168.4.1',
        '192.168.1.1',
      ];
      for (final ip in priorityIPs) {
        if (!potentialIPs.contains(ip)) {
          potentialIPs.add(ip);
        }
      }

      // Add broader IP ranges to scan for ESP32 nodes dynamically
      // ESP32 mesh can assign IPs in various ranges
      final commonNetworkPrefixes = [
        '10.145.169', // Observed working range
        '10.35.17', // Observed mesh range
        '10.76.77', // Observed mesh range
        '192.168.4', // Common ESP32 AP range
        '192.168.1', // Common router range
        '192.168.0', // Common router range
      ];

      // Add gateway IPs and a few common device IPs for each range
      for (final prefix in commonNetworkPrefixes) {
        potentialIPs.addAll([
          '$prefix.1', // Gateway
          '$prefix.2', // Common device
          '$prefix.100', // Common device range
        ]);
      }

      if (kDebugMode) {
        print(
          'Trying ${potentialIPs.length} potential IPs: ${potentialIPs.take(5).join(", ")}...',
        );
      }

      // FAST PARALLEL discovery - try more IPs simultaneously
      final futures = potentialIPs
          .take(20) // Increased from 10 to 20 for faster discovery
          .map((ip) => _probeNode(ip))
          .toList();

      if (kDebugMode) {
        print('🚀 Fast parallel probe on ${futures.length} IPs...');
      }

      final results = await Future.wait(futures);

      // Collect all successful probes
      for (final node in results) {
        if (node != null) {
          nodes.add(node);
        }
      }

      // If we found any responsive node, try to get mesh topology
      if (nodes.isNotEmpty) {
        final firstNode = nodes.first;
        try {
          if (kDebugMode) {
            print('Getting mesh topology from ${firstNode.ipAddress}...');
          }
          final meshInfo = await _getMeshTopology(firstNode.ipAddress);

          // Probe additional nodes found in mesh topology
          for (final nodeInfo in meshInfo) {
            // Get IP address with null checks and priority
            String? nodeIP = nodeInfo['ipAddress'] as String?;
            if (nodeIP == null || nodeIP.isEmpty || nodeIP == "0.0.0.0") {
              nodeIP = nodeInfo['stationIP'] as String?;
              if (nodeIP == null || nodeIP.isEmpty || nodeIP == "0.0.0.0") {
                nodeIP = nodeInfo['apIP'] as String?;
              }
            }

            // Get node ID and skip if null/empty
            final nodeId = nodeInfo['nodeId'] as String?;
            if (nodeId == null || nodeId.isEmpty || nodeId == 'null') {
              if (kDebugMode) {
                print('  Skipping mesh node with null/empty ID');
              }
              continue;
            }

            if (nodeIP != null &&
                nodeIP != firstNode.ipAddress &&
                nodeIP != "0.0.0.0" &&
                nodeIP.isNotEmpty) {
              // Try to probe the node directly
              final probeResult = await _probeNode(nodeIP);

              if (probeResult != null) {
                // Node is directly accessible
                nodes.add(probeResult);
                if (kDebugMode) {
                  print(
                    '  Added responsive node: ${probeResult.deviceName} (${probeResult.deviceId})',
                  );
                }
              } else {
                // Create a mesh-only node entry with valid nodeId
                final meshOnlyNode = AgriNode(
                  deviceId: nodeId,
                  deviceName: nodeInfo['deviceName'] ?? 'Mesh Node $nodeId',
                  ipAddress: nodeInfo['apIP'] ?? nodeIP, // Prioritize AP IP
                  apIP: nodeInfo['apIP'],
                  stationIP: nodeInfo['stationIP'] ?? nodeIP,
                  isOnline: nodeInfo['meshConnected'] ?? false,
                  isLocal: false,
                  lastSeen: nodeInfo['lastSeen'] != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          (nodeInfo['lastSeen'] * 1000).toInt(),
                        )
                      : DateTime.now(),
                  deviceType: 'Smart Agriculture ESP32 (Mesh Only)',
                  firmwareVersion: 'v2.x',
                  meshNodeCount: 0,
                  availableEndpoints: ['Mesh Relay'],
                );
                nodes.add(meshOnlyNode);

                if (kDebugMode) {
                  print(
                    '  Added mesh-only node: ${meshOnlyNode.deviceName} (${meshOnlyNode.deviceId}) AP:${nodeInfo['apIP']} Station:${nodeInfo['stationIP']}',
                  );
                }
              }
            } else if (nodeId.isNotEmpty) {
              // No valid IP, but we have a valid node ID - create a mesh entry
              final meshOnlyNode = AgriNode(
                deviceId: nodeId,
                deviceName:
                    nodeInfo['deviceName'] ?? 'Unknown Mesh Node $nodeId',
                ipAddress:
                    nodeInfo['apIP'] ?? nodeInfo['stationIP'] ?? '0.0.0.0',
                apIP: nodeInfo['apIP'],
                stationIP: nodeInfo['stationIP'],
                isOnline: nodeInfo['meshConnected'] ?? false,
                isLocal: false,
                lastSeen: nodeInfo['lastSeen'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (nodeInfo['lastSeen'] * 1000).toInt(),
                      )
                    : DateTime.now(),
                deviceType: 'Smart Agriculture ESP32 (Mesh Only)',
                firmwareVersion: 'v2.x',
                meshNodeCount: 0,
                availableEndpoints: ['Mesh Relay'],
              );
              nodes.add(meshOnlyNode);

              if (kDebugMode) {
                print(
                  '  Added mesh-only node (no IP): ${meshOnlyNode.deviceName} (${meshOnlyNode.deviceId}) AP:${nodeInfo['apIP']} Station:${nodeInfo['stationIP']}',
                );
              }
            }
          }

          if (kDebugMode) {
            print(
              'Found ${meshInfo.length} nodes in mesh topology, ${nodes.length} total nodes added (responsive + mesh-only)',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print(
              'Failed to get mesh topology from ${firstNode.ipAddress}: $e',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in mesh discovery: $e');
      }
    }

    return nodes;
  }

  Future<List<Map<String, dynamic>>> _getMeshTopology(String nodeIP) async {
    try {
      if (kDebugMode) {
        print('Attempting to get mesh topology from $nodeIP...');
      }

      // Use the custom HTTP client for better cross-platform compatibility
      final responseBody = await _customHttpGet(
        'http://$nodeIP:$httpPort/api/mesh/nodes',
      );

      final data = json.decode(responseBody);
      final nodesList = List<Map<String, dynamic>>.from(data['nodes'] ?? []);

      if (kDebugMode) {
        print('📡 Mesh topology response: ${nodesList.length} nodes');
        for (var node in nodesList) {
          print(
            '  - ${node['deviceName'] ?? 'Unknown'} (${node['deviceId']}) AP:${node['apIP']} Station:${node['stationIP']}',
          );
        }
      }

      return nodesList;
    } on SocketException catch (e) {
      if (kDebugMode) {
        print('Network error getting mesh topology from $nodeIP: ${e.message}');
        if (e.message.contains('Network is unreachable')) {
          print(
            '  This is likely an Android routing issue - trying alternative discovery...',
          );
        }
      }
    } on HttpException catch (e) {
      if (kDebugMode) {
        print('HTTP error getting mesh topology from $nodeIP: ${e.message}');
      }
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        print('Timeout getting mesh topology from $nodeIP: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get mesh topology from $nodeIP: $e');
      }
    }

    return [];
  }

  Future<AgriNode?> _probeNode(String ip) async {
    try {
      // Try the discovery endpoint first
      final responseBody = await _customHttpGet(
        'http://$ip:$httpPort/discover',
      );

      final data = json.decode(responseBody);
      if (data['type'] == 'SmartAgriDevice') {
        return AgriNode(
          deviceId: data['deviceId'] ?? ip,
          deviceName: data['deviceName'] ?? 'Unknown Device',
          ipAddress: ip,
          apIP: data['apIP'],
          stationIP: data['localIP'],
          isOnline: true,
          isLocal: data['localIP'] == await _networkInfo.getWifiIP(),
          lastSeen: DateTime.now(),
          deviceType: 'Smart Agriculture ESP32',
          firmwareVersion: data['version'],
          meshNodeCount: data['meshNodes'],
          availableEndpoints:
              data['discoveryMethods']?.split(',') ?? ['HTTP', 'CoAP'],
        );
      }
    } catch (e) {
      // Ignore timeout/connection errors for non-existent nodes
    }

    // Fallback: try the device info endpoint
    try {
      final responseBody = await _customHttpGet(
        'http://$ip:$httpPort/api/device/info',
      );
      final data = json.decode(responseBody);
      return AgriNode(
        deviceId: data['deviceId'] ?? ip,
        deviceName: data['deviceName'] ?? 'Unknown Device',
        ipAddress: ip,
        apIP: data['apIP'],
        stationIP: data['stationIP'],
        isOnline: true,
        isLocal: false,
        lastSeen: DateTime.now(),
        deviceType: 'Smart Agriculture ESP32',
        firmwareVersion: 'v2.x',
        meshNodeCount: data['meshNodes'],
        availableEndpoints: ['HTTP', 'CoAP'],
      );
    } catch (e) {
      // Ignore timeout/connection errors
    }

    return null;
  }

  Future<void> fetchAllSensorData() async {
    // 🎯 Prevent multiple concurrent data fetches
    if (_isFetchingData) {
      if (kDebugMode) {
        print('⏳ Data fetch already in progress, skipping...');
      }
      return;
    }

    _isFetchingData = true;
    _isFetchingDataController.add(true); // 📡 Notify UI about data fetch start

    try {
      // Show cached data first for instant UI response
      if (_sensorDataCache.isNotEmpty) {
        _sensorDataController.add(_sensorDataCache);
      }

      Map<String, SensorData> newSensorData = {};

      if (kDebugMode) {
        print(
          '📡 Fetching sensor data from ${_discoveredNodes.length} nodes...',
        );
      }

      for (final node in _discoveredNodes) {
        try {
          // Skip nodes with invalid deviceId
          if (node.deviceId.isEmpty || node.deviceId == 'null') {
            if (kDebugMode) {
              print(
                '  ⚠️ Skipping node with invalid deviceId: ${node.deviceName} (${node.deviceId})',
              );
            }
            continue;
          }

          if (kDebugMode) {
            print(
              '  📊 Getting data from: ${node.deviceName} (${node.deviceId}) at ${node.ipAddress}',
            );
          }

          SensorData? sensorData;

          // Try direct connection first for all nodes (faster and more reliable)
          // Use validated IP for mesh communication, fallback to AP then Station IP
          String? communicationIP;

          if (kDebugMode) {
            print(
              '    Finding best communication IP for: ${node.deviceName} (${node.deviceId})',
            );
          }

          // For cross-subnet nodes, validate connectivity before attempting requests
          final isIsolatedNode = await _isNodeOnDifferentSubnet(node.ipAddress);
          if (isIsolatedNode ||
              (node.apIP?.isNotEmpty == true && node.apIP != '0.0.0.0')) {
            communicationIP = await _findBestReachableIP(node);
          } else {
            // For same-subnet nodes, use existing priority logic
            communicationIP = node.apIP?.isNotEmpty == true
                ? node.apIP!
                : node.ipAddress;
          }

          if (kDebugMode && communicationIP != null) {
            if (kDebugMode) {
              print(
                '    Using validated IP for ${node.deviceName}: $communicationIP ${isIsolatedNode ? '(cross-subnet)' : '(same-subnet)'}',
              );
            }
          }

          // Skip direct connection if no valid IP found
          if (communicationIP != null &&
              communicationIP != '0.0.0.0' &&
              communicationIP.isNotEmpty) {
            sensorData = await _getNodeDataDirect(communicationIP);
          } else {
            if (kDebugMode) {
              print(
                '    Skipping direct connection - no reachable IP found for ${node.deviceName}',
              );
            }
          }

          // If direct fails and we have other nodes, try relay as fallback
          if (sensorData == null && _discoveredNodes.length > 1) {
            // Find a different node to use as relay (prefer directly accessible nodes)
            AgriNode? relayNode;

            // First try to find a responsive node that's not the target
            relayNode = _discoveredNodes
                .where(
                  (n) =>
                      n.deviceId != node.deviceId &&
                      !n.availableEndpoints.contains('Mesh Relay'),
                )
                .cast<AgriNode?>()
                .firstWhere((n) => n != null, orElse: () => null);

            // If no direct responsive node, try any other node
            relayNode ??= _discoveredNodes
                .where((n) => n.deviceId != node.deviceId)
                .cast<AgriNode?>()
                .firstWhere((n) => n != null, orElse: () => null);

            if (relayNode != null) {
              // Get validated IP for relay node
              final relayIP = await _findBestReachableIP(relayNode);

              if (relayIP != null &&
                  relayIP != '0.0.0.0' &&
                  relayIP.isNotEmpty) {
                if (kDebugMode) {
                  print(
                    '    Direct failed, trying relay via ${relayNode.deviceName} ($relayIP) for: ${node.deviceName}',
                  );
                }
                sensorData = await _getNodeDataRelay(relayIP, node.deviceId);
              } else {
                if (kDebugMode) {
                  print(
                    '    No reachable relay node found for: ${node.deviceName}',
                  );
                }
              }
            } else {
              if (kDebugMode) {
                print(
                  '    No suitable relay node available for: ${node.deviceName}',
                );
              }
            }
          }

          if (sensorData != null) {
            newSensorData[node.deviceId] = sensorData;
            if (kDebugMode) {
              print(
                '  ✅ Got data from ${node.deviceName}: T=${sensorData.temperature}°C, H=${sensorData.humidity}%',
              );
            }
          } else {
            if (kDebugMode) {
              print('  ❌ No data from ${node.deviceName}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print(
              '  ❌ Failed to fetch sensor data from ${node.deviceName}: $e',
            );
          }
        }
      }

      if (kDebugMode) {
        print(
          '📊 Sensor data fetch complete: ${newSensorData.length}/${_discoveredNodes.length} nodes responded',
        );
      }

      _sensorDataCache = newSensorData;
      _sensorDataController.add(_sensorDataCache);

      // NOTE: Live data is NOT saved to Firebase
      // Only historical data from SD cards should be synced to Firebase
    } finally {
      _isFetchingData = false;
      _isFetchingDataController.add(false); // 📡 Notify UI about data fetch end
    }
  }

  Future<SensorData?> fetchSensorData(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/device/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SensorData.fromJson(data);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch sensor data from $nodeIP: $e');
      }
    }

    return null;
  }

  Future<SensorData?> fetchSensorDataCoAP(String nodeIP) async {
    try {
      if (kDebugMode) {
        print('Attempting CoAP request to $nodeIP:$coapPort');
      }

      // For now, implement a simple UDP-based CoAP-like request
      // This is a basic implementation - a full CoAP client would be more complex

      // Fall back to HTTP if CoAP fails
      if (kDebugMode) {
        print('CoAP implementation basic - falling back to HTTP for $nodeIP');
      }
      return await fetchSensorData(nodeIP);
    } catch (e) {
      if (kDebugMode) {
        print('CoAP request failed, using HTTP fallback for $nodeIP: $e');
      }
      return await fetchSensorData(nodeIP);
    }
  }

  Future<NetworkStatus?> fetchNetworkStatus(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/network/status'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return NetworkStatus.fromJson(data);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch network status from $nodeIP: $e');
      }
    }

    return null;
  }

  // Fetch historical data from SD card via /api/data/history endpoint
  Future<List<SensorReading>> fetchHistoricalData(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/data/history'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 15)); // Longer timeout for historical data

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle different possible response formats
        List<dynamic> sensorDataList;
        if (data is List) {
          sensorDataList = data;
        } else if (data is Map && data.containsKey('history')) {
          // This is the correct format for /api/data/history
          sensorDataList = data['history'] as List;
        } else if (data is Map && data.containsKey('sensorData')) {
          sensorDataList = data['sensorData'] as List;
        } else if (data is Map && data.containsKey('data')) {
          sensorDataList = data['data'] as List;
        } else {
          if (kDebugMode) {
            print('Unexpected historical data format from $nodeIP: $data');
          }
          return [];
        }

        if (kDebugMode) {
          print(
            '📋 Parsing ${sensorDataList.length} historical readings from $nodeIP',
          );
        }

        return sensorDataList.map((item) {
          // Handle timestamp conversion from seconds to DateTime
          var timestamp = item['timestamp'] ?? 0;
          DateTime dateTime;

          if (timestamp is int) {
            // Timestamp appears to be in seconds since some reference point
            // Convert to actual DateTime by treating as seconds since Unix epoch
            // But the values like 125275 seem to be relative seconds, so we'll
            // create timestamps relative to now, going backwards
            final now = DateTime.now();
            dateTime = now.subtract(Duration(seconds: timestamp));
          } else {
            dateTime = DateTime.now();
          }

          return SensorReading(
            temperature: (item['temperature'] ?? 0.0).toDouble(),
            humidity: (item['humidity'] ?? 0.0).toDouble(),
            soilMoisture: (item['soilMoisture'] ?? 0).toInt(),
            distance: (item['distance'] ?? 0.0).toDouble(),
            motionDetected: item['motionDetected'] ?? false,
            buzzerActive: item['buzzerActive'] ?? false,
            timestamp: dateTime,
          );
        }).toList();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch historical data from $nodeIP: $e');
      }
    }

    return [];
  }

  // Enhanced buzzer control with relay support
  Future<bool> controlBuzzer(String nodeId, String action) async {
    if (kDebugMode) {
      print('🔊 BUZZER DEBUG: Starting buzzer control request');
      print('  Target Node ID: $nodeId');
      print('  Action: $action');
      print('  Available nodes: ${_discoveredNodes.length}');
    }

    try {
      // Find the home node (first available node to act as relay)
      if (_discoveredNodes.isEmpty) {
        if (kDebugMode) {
          print('❌ BUZZER DEBUG: No nodes available for buzzer control');
        }
        return false;
      }

      final homeNode = _discoveredNodes.first;
      if (kDebugMode) {
        print('  Home node: ${homeNode.deviceName} (${homeNode.deviceId})');
        print('  Home node IP: ${homeNode.ipAddress}');
        print('  Is target same as home: ${nodeId == homeNode.deviceId}');
      }

      // Check if we're controlling the home node directly
      if (nodeId == homeNode.deviceId) {
        if (kDebugMode) {
          print('  Using direct control for home node');
        }
        return await _controlBuzzerDirect(homeNode.ipAddress, action);
      } else {
        if (kDebugMode) {
          print('  Using relay control for remote node');
        }
        return await _controlBuzzerRelay(homeNode.ipAddress, nodeId, action);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ BUZZER DEBUG: Failed to control buzzer: $e');
        print('  Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }

  // Direct buzzer control (when controlling the home node)
  Future<bool> _controlBuzzerDirect(String nodeIP, String action) async {
    if (kDebugMode) {
      print('🔊 BUZZER DIRECT: Starting direct buzzer control');
      print('  Target IP: $nodeIP');
      print('  Action: $action');
    }

    try {
      final requestBody = {'action': action};
      final url = 'http://$nodeIP:$httpPort/api/control/buzzer';

      if (kDebugMode) {
        print('  Request URL: $url');
        print('  Request body: ${json.encode(requestBody)}');
      }

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(timeoutDuration);

      if (kDebugMode) {
        print('  Response status: ${response.statusCode}');
        print('  Response body: ${response.body}');
        print('  Response headers: ${response.headers}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final success = !data.containsKey('error');
        if (kDebugMode) {
          print('  Success: $success');
          if (data.containsKey('error')) {
            print('  Error from device: ${data['error']}');
          }
        }
        return success;
      } else {
        if (kDebugMode) {
          print('❌ BUZZER DIRECT: HTTP error ${response.statusCode}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ BUZZER DIRECT: Exception occurred: $e');
        print('  Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }

  // Relay buzzer control (when controlling remote nodes through home node)
  Future<bool> _controlBuzzerRelay(
    String homeNodeIP,
    String targetNodeId,
    String action,
  ) async {
    if (kDebugMode) {
      print('🔊 BUZZER RELAY: Starting relay buzzer control');
      print('  Home node IP: $homeNodeIP');
      print('  Target node ID: $targetNodeId');
      print('  Action: $action');
    }

    try {
      final requestBody = {'nodeId': targetNodeId, 'action': action};
      final url = 'http://$homeNodeIP:$httpPort/api/relay/buzzer';

      if (kDebugMode) {
        print('  Request URL: $url');
        print('  Request body: ${json.encode(requestBody)}');
      }

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(Duration(seconds: 10)); // Longer timeout for relay

      if (kDebugMode) {
        print('  Response status: ${response.statusCode}');
        print('  Response body: ${response.body}');
        print('  Response headers: ${response.headers}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final success = !data.containsKey('error');
        if (kDebugMode) {
          print('  Success: $success');
          if (data.containsKey('error')) {
            print('  Error from relay: ${data['error']}');
          }
        }
        return success;
      } else if (response.statusCode == 408) {
        if (kDebugMode) {
          print('⏰ BUZZER RELAY: Timeout for node $targetNodeId');
        }
        return false;
      } else {
        if (kDebugMode) {
          print('❌ BUZZER RELAY: HTTP error ${response.statusCode}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ BUZZER RELAY: Exception occurred: $e');
        print('  Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }

  // Enhanced relay request with support for different API endpoints
  Future<SensorData?> relayRequest(String targetNodeId, String apiPath) async {
    // Find a node to send the relay request through
    if (_discoveredNodes.isEmpty) return null;

    final relayNode = _discoveredNodes.first;

    try {
      final response = await http
          .get(
            Uri.parse(
              'http://${relayNode.ipAddress}:$httpPort/api/relay/data?nodeId=$targetNodeId',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 10)); // Longer timeout for relay

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SensorData.fromJson(data);
      } else if (response.statusCode == 408) {
        if (kDebugMode) {
          print('Relay request timeout for node $targetNodeId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Relay request failed: $e');
      }
    }

    return null;
  }

  // Get live sensor data from any node (direct or via relay)
  Future<SensorData?> getLiveNodeData(String nodeId) async {
    try {
      // Find the home node
      if (_discoveredNodes.isEmpty) return null;

      final homeNode = _discoveredNodes.first;
      final homeNodeIP = homeNode.apIP?.isNotEmpty == true
          ? homeNode.apIP!
          : homeNode.ipAddress;

      // Check if we're getting data from the home node directly
      if (nodeId == homeNode.deviceId) {
        return await _getNodeDataDirect(homeNodeIP);
      } else {
        return await _getNodeDataRelay(homeNodeIP, nodeId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get live node data: $e');
      }
      return null;
    }
  }

  // Direct data fetch (from home node)
  Future<SensorData?> _getNodeDataDirect(String nodeIP) async {
    try {
      if (kDebugMode) {
        print('    Direct request to: $nodeIP');

        // Dynamic debugging for cross-subnet communication issues
        // Check if this IP is on a different subnet than our gateway nodes
        final isIsolatedNode = await _isNodeOnDifferentSubnet(nodeIP);
        if (isIsolatedNode) {
          print(
            '    🔍 DEBUG: Cross-subnet node detected ($nodeIP), testing connectivity...',
          );
          await _performConnectivityTests(nodeIP);
        }
      }

      final responseBody = await _customHttpGet(
        'http://$nodeIP:$httpPort/api/device/info',
      );

      if (kDebugMode) {
        print('    Direct response received successfully');
      }

      final data = json.decode(responseBody);

      // Check if the response has the expected sensor data fields
      if (data.containsKey('deviceId') && data.containsKey('temperature')) {
        if (kDebugMode) {
          print('    Creating SensorData from: ${data.keys}');
          print(
            '    Sample values: deviceId=${data['deviceId']}, temp=${data['temperature']}, humidity=${data['humidity']}',
          );
        }

        try {
          final sensorData = SensorData.fromJson(data);
          if (kDebugMode) {
            print(
              '    ✅ SensorData created successfully: ${sensorData.deviceName}',
            );
          }
          return sensorData;
        } catch (e) {
          if (kDebugMode) {
            print('    ❌ Failed to create SensorData: $e');
            print('    Raw data: $data');
          }
          return null;
        }
      } else {
        if (kDebugMode) {
          print(
            '    Response missing expected sensor data fields: ${data.keys}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('    Direct request failed for $nodeIP: $e');
      }
    }
    return null;
  }

  // Relay data fetch (from remote nodes through home node)
  Future<SensorData?> _getNodeDataRelay(
    String homeNodeIP,
    String targetNodeId,
  ) async {
    try {
      if (kDebugMode) {
        print('    Relay request: $homeNodeIP -> $targetNodeId');
      }

      final responseBody = await _customHttpGet(
        'http://$homeNodeIP:$httpPort/api/relay/data?nodeId=$targetNodeId',
      );

      if (kDebugMode) {
        print('    Relay response received successfully');
      }

      final data = json.decode(responseBody);

      // Check if the response contains an error
      if (data.containsKey('error')) {
        if (kDebugMode) {
          print('    Relay returned error: ${data['error']}');
        }
        return null;
      }

      if (kDebugMode) {
        print('    Relay response data keys: ${data.keys}');
        print(
          '    Sample relay values: deviceId=${data['deviceId']}, temp=${data['temperature']}',
        );
      }

      try {
        final sensorData = SensorData.fromJson(data);
        if (kDebugMode) {
          print('    ✅ Relay SensorData created: ${sensorData.deviceName}');
        }
        return sensorData;
      } catch (e) {
        if (kDebugMode) {
          print('    ❌ Failed to create SensorData from relay: $e');
          print('    Raw relay data: $data');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('    Failed to get data via relay for $targetNodeId: $e');
      }
    }
    return null;
  }

  // Download historical data from any node (direct or via relay)
  Future<Map<String, dynamic>?> downloadHistoricalData(String nodeId) async {
    try {
      // Find the home node
      if (_discoveredNodes.isEmpty) return null;

      final homeNode = _discoveredNodes.first;

      // Check if we're downloading from the home node directly
      if (nodeId == homeNode.deviceId) {
        return await _downloadHistoricalDataDirect(homeNode.ipAddress);
      } else {
        return await _downloadHistoricalDataRelay(homeNode.ipAddress, nodeId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to download historical data: $e');
      }
      return null;
    }
  }

  // Direct historical data download (from home node)
  Future<Map<String, dynamic>?> _downloadHistoricalDataDirect(
    String nodeIP,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/data/history'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 15)); // Longer timeout for historical data

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to download historical data directly from $nodeIP: $e');
      }
    }
    return null;
  }

  // Relay historical data download (from remote nodes through home node)
  Future<Map<String, dynamic>?> _downloadHistoricalDataRelay(
    String homeNodeIP,
    String targetNodeId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$homeNodeIP:$httpPort/api/relay/download?nodeId=$targetNodeId',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 408) {
        if (kDebugMode) {
          print('Historical data download timeout for node $targetNodeId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to download historical data via relay: $e');
      }
    }
    return null;
  }

  // Download historical data from SD card and save to Firebase
  Future<void> downloadAndSaveHistoricalData(String nodeIP) async {
    try {
      if (kDebugMode) {
        print('📥 Downloading historical data from $nodeIP...');
      }

      // Try to get historical data from the node's SD card
      final historicalReadings = await fetchHistoricalData(nodeIP);

      if (historicalReadings.isNotEmpty) {
        // Find the node to get its device ID
        final node = _discoveredNodes.firstWhere(
          (node) => node.ipAddress == nodeIP,
          orElse: () => AgriNode(
            deviceId: nodeIP,
            deviceName: 'Unknown Device',
            ipAddress: nodeIP,
            isOnline: true,
            isLocal: false,
            lastSeen: DateTime.now(),
          ),
        );

        // Save historical readings to Firebase in batches
        if (kDebugMode) {
          print(
            '💾 Saving ${historicalReadings.length} historical readings to Firebase for device ${node.deviceId}',
          );
        }

        // Save readings in batches of 50 to avoid Firestore limits
        const batchSize = 50;
        for (int i = 0; i < historicalReadings.length; i += batchSize) {
          final batch = historicalReadings.skip(i).take(batchSize).toList();
          await _firestoreService.saveHistoricalDataBatch(
            batch,
            node.deviceId,
            node.deviceName,
            node.ipAddress,
          );

          if (kDebugMode) {
            print(
              '✅ Saved batch ${(i / batchSize).floor() + 1}/${(historicalReadings.length / batchSize).ceil()}',
            );
          }
        }

        if (kDebugMode) {
          print(
            '✅ Successfully synced all historical data from ${node.deviceName}',
          );
        }
      } else {
        if (kDebugMode) {
          print('📭 No historical data available from $nodeIP');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error downloading historical data from $nodeIP: $e');
      }
    }
  }

  Future<bool> syncAllHistoricalData() async {
    bool success = true;

    for (final node in _discoveredNodes) {
      try {
        await downloadAndSaveHistoricalData(node.ipAddress);
      } catch (e) {
        if (kDebugMode) {
          print('Failed to sync data from ${node.deviceName}: $e');
        }
        success = false;
      }
    }

    return success;
  }

  // SD Card Data Download - with automatic relay fallback
  Future<List<String>> getAvailableDataFiles(String nodeIP) async {
    // First try direct access
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/files'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['files'] ?? []);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Direct access failed for SD card files from $nodeIP: $e');
        print('Attempting relay access...');
      }
    }

    // If direct access fails, try relay through discovered home nodes
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == nodeIP) {
        continue; // Skip if this is the home node
      }

      // Find the target node by IP
      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.ipAddress == nodeIP,
        orElse: () => AgriNode(
          deviceId: '',
          deviceName: 'Unknown',
          ipAddress: nodeIP,
          lastSeen: DateTime.now(),
          isOnline: false,
          isLocal: false,
        ),
      );

      if (targetNode.deviceId.isNotEmpty) {
        final relayFiles = await getAvailableDataFilesRelay(
          homeNode.ipAddress,
          targetNode.deviceId,
        );
        if (relayFiles.isNotEmpty) {
          if (kDebugMode) {
            print(
              '✅ Successfully got SD card files via relay from ${homeNode.ipAddress}',
            );
          }
          return relayFiles;
        }
      }
    }

    if (kDebugMode) {
      print(
        '❌ Failed to get SD card files from $nodeIP via both direct and relay access',
      );
    }
    return [];
  }

  // Get available SD card files via relay (for remote nodes)
  Future<List<String>> getAvailableDataFilesRelay(
    String homeNodeIP,
    String targetNodeId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$homeNodeIP:$httpPort/api/relay/sdcard/files?nodeId=$targetNodeId',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['files'] ?? []);
      } else if (response.statusCode == 408) {
        if (kDebugMode) {
          print(
            'Timeout getting SD card files from node $targetNodeId via relay',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get SD card files via relay from $targetNodeId: $e');
      }
    }

    return [];
  }

  Future<String?> downloadDataFile(String nodeIP, String fileName) async {
    // First try direct access
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$nodeIP:$httpPort/api/sdcard/download?file=$fileName',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 30)); // Longer timeout for file downloads

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Direct access failed for file $fileName from $nodeIP: $e');
        print('Attempting relay access...');
      }
    }

    // If direct access fails, try relay through discovered home nodes
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == nodeIP) {
        continue; // Skip if this is the home node
      }

      // Find the target node by IP
      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.ipAddress == nodeIP,
        orElse: () => AgriNode(
          deviceId: '',
          deviceName: 'Unknown',
          ipAddress: nodeIP,
          lastSeen: DateTime.now(),
          isOnline: false,
          isLocal: false,
        ),
      );

      if (targetNode.deviceId.isNotEmpty) {
        final relayContent = await downloadDataFileRelay(
          homeNode.ipAddress,
          targetNode.deviceId,
          fileName,
        );
        if (relayContent != null) {
          if (kDebugMode) {
            print(
              '✅ Successfully downloaded file via relay from ${homeNode.ipAddress}',
            );
          }
          return relayContent;
        }
      }
    }

    if (kDebugMode) {
      print(
        '❌ Failed to download file $fileName from $nodeIP via both direct and relay access',
      );
    }
    return null;
  }

  // Download SD card file via relay (for remote nodes)
  Future<String?> downloadDataFileRelay(
    String homeNodeIP,
    String targetNodeId,
    String fileName,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$homeNodeIP:$httpPort/api/relay/sdcard/download?nodeId=$targetNodeId&file=$fileName',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 30)); // Longer timeout for file downloads

      if (response.statusCode == 200) {
        return response.body;
      } else if (response.statusCode == 408) {
        if (kDebugMode) {
          print(
            'Timeout downloading file $fileName from node $targetNodeId via relay',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          'Failed to download file $fileName via relay from $targetNodeId: $e',
        );
      }
    }

    return null;
  }

  Future<bool> deleteDataFile(String nodeIP, String fileName) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
              'http://$nodeIP:$httpPort/api/sdcard/delete?file=$fileName',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to delete data file $fileName from $nodeIP: $e');
      }
    }

    return false;
  }

  Future<Map<String, dynamic>?> getSDCardInfo(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get SD card info from $nodeIP: $e');
      }
    }

    return null;
  }

  // Smart SD card info that tries direct then relay access
  Future<Map<String, dynamic>?> getSDCardInfoSmart(String nodeIP) async {
    // Try direct access first
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (kDebugMode) {
          print('✅ Direct SD card info access successful for $nodeIP');
        }
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Direct SD card info access failed for $nodeIP: $e');
        print('🔄 Attempting relay access for SD card info...');
      }
    }

    // If direct access fails, try relay through discovered home nodes
    // Note: This assumes the relay endpoints support the /api/sdcard/info path
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == nodeIP) continue;

      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.ipAddress == nodeIP,
        orElse: () => AgriNode(
          deviceId: '',
          deviceName: 'Unknown',
          ipAddress: nodeIP,
          lastSeen: DateTime.now(),
          isOnline: false,
          isLocal: false,
        ),
      );

      if (targetNode.deviceId.isNotEmpty) {
        try {
          // Use the relay sdcard info endpoint
          final response = await http
              .get(
                Uri.parse(
                  'http://${homeNode.ipAddress}:$httpPort/api/relay/sdcard/info?nodeId=${targetNode.deviceId}',
                ),
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(Duration(seconds: 10));

          if (response.statusCode == 200) {
            if (kDebugMode) {
              print(
                '✅ Successfully got SD card info via relay from ${homeNode.ipAddress}',
              );
            }
            return json.decode(response.body);
          }
        } catch (e) {
          if (kDebugMode) {
            print(
              '❌ Relay SD card info failed through ${homeNode.ipAddress}: $e',
            );
          }
        }
      }
    }

    if (kDebugMode) {
      print(
        '❌ Failed to get SD card info from $nodeIP via both direct and relay access',
      );
    }
    return null;
  }

  // Smart SD card operations that automatically choose direct or relay access
  Future<List<String>> getAvailableDataFilesSmart(String nodeIP) async {
    // Try direct access first
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/files'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 5)); // Shorter timeout for direct check

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          print('✅ Direct SD card access successful for $nodeIP');
        }
        return List<String>.from(data['files'] ?? []);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Direct SD card access failed for $nodeIP: $e');
        print('🔄 Attempting relay access through discovered nodes...');
      }
    }

    // If direct access fails, try relay through discovered home nodes
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == nodeIP) {
        continue; // Skip if this is the home node
      }

      // Find the target node by IP
      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.ipAddress == nodeIP,
        orElse: () => AgriNode(
          deviceId: '',
          deviceName: 'Unknown',
          ipAddress: nodeIP,
          lastSeen: DateTime.now(),
          isOnline: false,
          isLocal: false,
        ),
      );

      if (targetNode.deviceId.isNotEmpty) {
        if (kDebugMode) {
          print(
            '🔄 Trying relay through ${homeNode.ipAddress} for target ${targetNode.deviceId}',
          );
        }

        final relayFiles = await getAvailableDataFilesRelay(
          homeNode.ipAddress,
          targetNode.deviceId,
        );
        if (relayFiles.isNotEmpty) {
          if (kDebugMode) {
            print(
              '✅ Successfully got ${relayFiles.length} SD card files via relay from ${homeNode.ipAddress}',
            );
          }
          return relayFiles;
        }
      }
    }

    if (kDebugMode) {
      print(
        '❌ Failed to get SD card files from $nodeIP via both direct and relay access',
      );
    }
    return [];
  }

  Future<String?> downloadDataFileSmart(String nodeIP, String fileName) async {
    // Try direct access first
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$nodeIP:$httpPort/api/sdcard/download?file=$fileName',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 10)); // Shorter timeout for direct check

      if (response.statusCode == 200) {
        if (kDebugMode) {
          print('✅ Direct file download successful for $fileName from $nodeIP');
        }
        return response.body;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Direct file download failed for $fileName from $nodeIP: $e');
        print('🔄 Attempting relay download through discovered nodes...');
      }
    }

    // If direct access fails, try relay through discovered home nodes
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == nodeIP) {
        continue; // Skip if this is the home node
      }

      // Find the target node by IP
      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.ipAddress == nodeIP,
        orElse: () => AgriNode(
          deviceId: '',
          deviceName: 'Unknown',
          ipAddress: nodeIP,
          lastSeen: DateTime.now(),
          isOnline: false,
          isLocal: false,
        ),
      );

      if (targetNode.deviceId.isNotEmpty) {
        if (kDebugMode) {
          print(
            '🔄 Trying relay file download through ${homeNode.ipAddress} for target ${targetNode.deviceId}',
          );
        }

        final relayContent = await downloadDataFileRelay(
          homeNode.ipAddress,
          targetNode.deviceId,
          fileName,
        );
        if (relayContent != null) {
          if (kDebugMode) {
            print(
              '✅ Successfully downloaded file $fileName via relay from ${homeNode.ipAddress}',
            );
          }
          return relayContent;
        }
      }
    }

    if (kDebugMode) {
      print(
        '❌ Failed to download file $fileName from $nodeIP via both direct and relay access',
      );
    }
    return null;
  }

  // Device Control Functions
  Future<bool> resetDevice(String nodeIP) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$nodeIP:$httpPort/api/control/reset'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to reset device $nodeIP: $e');
      }
    }

    return false;
  }

  Future<bool> updateFirmware(String nodeIP, String firmwareUrl) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$nodeIP:$httpPort/api/control/update'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'firmwareUrl': firmwareUrl}),
          )
          .timeout(Duration(minutes: 5)); // Long timeout for firmware updates

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to update firmware on $nodeIP: $e');
      }
    }

    return false;
  }

  Future<Map<String, dynamic>?> getDeviceInfo(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/device/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get device info from $nodeIP: $e');
      }
    }

    return null;
  }

  // Configuration Functions
  Future<bool> updateSensorConfig(
    String nodeIP,
    Map<String, dynamic> config,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$nodeIP:$httpPort/api/config/sensors'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(config),
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to update sensor config on $nodeIP: $e');
      }
    }

    return false;
  }

  Future<Map<String, dynamic>?> getSensorConfig(String nodeIP) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/config/sensors'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get sensor config from $nodeIP: $e');
      }
    }

    return null;
  }

  // Public methods for manual refresh
  Future<void> refreshConnection() async {
    if (kDebugMode) {
      print('Manual connection refresh requested');
    }
    await _checkMeshConnection();
  }

  Future<void> refreshNodes() async {
    if (kDebugMode) {
      print('Manual node refresh requested');
    }
    await quickDiscovery();
  }

  Future<void> triggerGlobalDiscovery() async {
    if (kDebugMode) {
      print('Triggering global discovery across all known nodes...');
    }

    // Trigger discovery on all known nodes
    final futures = _discoveredNodes.map((node) async {
      try {
        await http
            .post(
              Uri.parse(
                'http://${node.ipAddress}:$httpPort/api/discover/trigger',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(Duration(seconds: 3));

        if (kDebugMode) {
          print('Triggered discovery on ${node.deviceName}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to trigger discovery on ${node.deviceName}: $e');
        }
      }
    });

    await Future.wait(futures);

    // Wait a moment for nodes to process and broadcast
    await Future.delayed(Duration(seconds: 2));

    // Re-discover nodes
    await discoverNodes();
  }

  Future<void> forceFullDiscovery() async {
    if (kDebugMode) {
      print('Starting forced full discovery...');
    }

    _discoveredNodes.clear();
    _sensorDataCache.clear();
    _nodesController.add([]);
    _sensorDataController.add({});

    await discoverNodes();
  }

  // Force a fresh discovery of all nodes
  Future<void> forceDiscovery() async {
    if (kDebugMode) {
      print('🔄 Force discovery triggered by user');
    }

    // Clear existing nodes temporarily
    _discoveredNodes.clear();
    _sensorDataCache.clear();
    _nodesController.add([]);
    _sensorDataController.add({});

    // Trigger fresh discovery
    await discoverNodes();
    await fetchAllSensorData();

    if (kDebugMode) {
      print(
        '🔄 Force discovery completed: ${_discoveredNodes.length} nodes found',
      );
    }
  }

  // 🔄 Manual refresh methods for user control
  Future<void> manualRefreshNodes() async {
    if (kDebugMode) {
      print('🔄 Manual node refresh triggered by user...');
    }

    // Clear existing discovery state
    _discoveredNodes.clear();
    _sensorDataCache.clear();

    // Notify UI about cleared state
    _nodesController.add([]);
    _sensorDataController.add({});

    // Start fresh discovery
    await discoverNodes();

    // If nodes found, fetch their data
    if (_discoveredNodes.isNotEmpty) {
      await fetchAllSensorData();
    }
  }

  Future<void> manualRefreshData() async {
    if (kDebugMode) {
      print('🔄 Manual data refresh triggered by user...');
    }

    if (_discoveredNodes.isEmpty) {
      if (kDebugMode) {
        print(
          '⚠️ No nodes available for data refresh. Try refreshing nodes first.',
        );
      }
      return;
    }

    await fetchAllSensorData();
  }

  // Convenience methods for UI
  List<AgriNode> get discoveredNodes => List.unmodifiable(_discoveredNodes);
  Map<String, SensorData> get currentSensorData =>
      Map.unmodifiable(_sensorDataCache);
  bool get isConnectedToMesh => _isConnectedToMesh;

  // 📊 State getters for UI to check current status
  bool get isDiscovering => _isDiscovering;
  bool get isFetchingData => _isFetchingData;

  // Get the home node (first node that acts as relay gateway)
  AgriNode? get homeNode =>
      _discoveredNodes.isNotEmpty ? _discoveredNodes.first : null;

  // Refresh data for all nodes
  Future<void> refreshAllData() async {
    if (kDebugMode) {
      print('Refreshing all data...');
    }
    await quickDiscovery();
    await fetchAllSensorData();
  }

  // Convenience methods for UI actions
  Future<bool> turnBuzzerOn(String nodeId) async {
    return await controlBuzzer(nodeId, 'on');
  }

  Future<bool> turnBuzzerOff(String nodeId) async {
    return await controlBuzzer(nodeId, 'off');
  }

  Future<bool> toggleBuzzer(String nodeId) async {
    return await controlBuzzer(nodeId, 'toggle');
  }

  // Get real-time data for a specific node
  Future<SensorData?> getNodeLiveData(String nodeId) async {
    return await getLiveNodeData(nodeId);
  }

  // Download and return historical data for a specific node
  Future<List<Map<String, dynamic>>?> getNodeHistoricalData(
    String nodeId,
  ) async {
    final result = await downloadHistoricalData(nodeId);
    if (result != null && result.containsKey('history')) {
      final historyData = List<Map<String, dynamic>>.from(result['history']);

      // Automatically save to Firestore
      if (historyData.isNotEmpty) {
        final node = findNodeById(nodeId);
        if (node != null) {
          final readings = historyData
              .map((data) => SensorReading.fromJson(data))
              .toList();
          await _firestoreService.saveHistoricalDataBatch(
            readings,
            node.deviceId,
            node.deviceName,
            node.ipAddress,
          );
        }
      }

      return historyData;
    }
    return null;
  }

  // Find a node by ID
  AgriNode? findNodeById(String nodeId) {
    try {
      return _discoveredNodes.firstWhere((node) => node.deviceId == nodeId);
    } catch (e) {
      return null;
    }
  }

  // Get the latest sensor data for a specific node
  SensorData? getLatestSensorData(String nodeId) {
    return _sensorDataCache[nodeId];
  }

  // Quick discovery for immediate UI response
  Future<void> quickDiscovery() async {
    if (kDebugMode) {
      print('Performing quick discovery...');
    }

    // Immediately update UI with any existing nodes
    if (_discoveredNodes.isNotEmpty) {
      _nodesController.add(_discoveredNodes);
      _connectionStatusController.add(true);
    }

    // Try quick discovery of known good IPs first
    final quickNodes = <AgriNode>[];

    // Try previously discovered nodes first
    for (final existingNode in _discoveredNodes) {
      try {
        final node = await _probeNode(existingNode.ipAddress);
        if (node != null) {
          quickNodes.add(node);
        }
      } catch (e) {
        // Continue to next node
      }
    }

    // If we found nodes quickly, update UI immediately
    if (quickNodes.isNotEmpty) {
      final uniqueNodes = <String, AgriNode>{};
      for (final node in quickNodes) {
        uniqueNodes[node.deviceId] = node;
      }
      _discoveredNodes = uniqueNodes.values.toList();
      _nodesController.add(_discoveredNodes);
      _connectionStatusController.add(true);

      // Save quick discovered nodes to Firestore
      for (final node in _discoveredNodes) {
        await _firestoreService.saveNode(node);
      }

      if (kDebugMode) {
        print('Quick discovery found ${quickNodes.length} nodes');
      }
    }

    // Continue with full discovery in background
    discoverNodes();
  }

  // Test method to debug sensor data issues
  Future<void> testSensorDataFetch() async {
    if (_discoveredNodes.isEmpty) {
      if (kDebugMode) {
        print('🔍 No nodes to test');
      }
      return;
    }

    final homeNode = _discoveredNodes.first;
    if (kDebugMode) {
      print(
        '🔍 Testing sensor data fetch from home node: ${homeNode.deviceName} (${homeNode.ipAddress})',
      );
    }

    // Test direct API call
    try {
      final response = await http
          .get(
            Uri.parse('http://${homeNode.ipAddress}:$httpPort/api/device/info'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeoutDuration);

      if (kDebugMode) {
        print('🔍 Direct API response status: ${response.statusCode}');
        print('🔍 Direct API response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          print('🔍 Parsed JSON keys: ${data.keys}');
          print(
            '🔍 Sample values: deviceId=${data['deviceId']}, temp=${data['temperature']}',
          );
        }

        try {
          final sensorData = SensorData.fromJson(data);
          if (kDebugMode) {
            print(
              '🔍 ✅ SensorData created successfully: ${sensorData.deviceName}, ${sensorData.temperature}°C',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('🔍 ❌ Failed to create SensorData: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔍 ❌ Direct API call failed: $e');
      }
    }
  }

  // Debug method to test network reachability on Android
  Future<void> debugNetworkReachability() async {
    if (kDebugMode) {
      print('🔍 Debugging network reachability...');

      // Check current network info
      final wifiName = await _networkInfo.getWifiName();
      final wifiIP = await _networkInfo.getWifiIP();
      final gatewayIP = await _networkInfo.getWifiGatewayIP();

      print('  📶 WiFi: $wifiName');
      print('  📍 Local IP: $wifiIP');
      print('  🚪 Gateway: $gatewayIP');

      // Test connectivity to known problematic IPs
      final testIPs = ['10.145.169.1', '10.35.17.1', '192.168.4.1'];

      for (final ip in testIPs) {
        try {
          print('  🔄 Testing $ip...');

          // Test basic connectivity (ping-like)
          final socket = await Socket.connect(
            ip,
            httpPort,
            timeout: Duration(seconds: 5),
          );
          socket.destroy();
          print('  ✅ $ip is reachable');

          // Test HTTP connection
          final httpResponse = await _customHttpGet(
            'http://$ip:$httpPort/discover',
          ).timeout(Duration(seconds: 5));
          print('  ✅ $ip HTTP response: ${httpResponse.length} bytes');
        } on SocketException catch (e) {
          print('  ❌ $ip socket error: ${e.message}');
        } on TimeoutException catch (e) {
          print('  ⏰ $ip timeout: ${e.message}');
        } catch (e) {
          print('  ❌ $ip error: $e');
        }
      }
    }
  }

  // Helper method to detect if a node is on a different subnet
  Future<bool> _isNodeOnDifferentSubnet(String nodeIP) async {
    try {
      // Get our gateway nodes' IPs to compare subnets
      final gatewayIPs = _discoveredNodes
          .where(
            (node) => node.ipAddress != '0.0.0.0' && node.ipAddress.isNotEmpty,
          )
          .map((node) => node.ipAddress)
          .toList();

      if (gatewayIPs.isEmpty) return false;

      // Extract subnet (first 3 octets) from node IP
      final nodeParts = nodeIP.split('.');
      if (nodeParts.length != 4) return false;
      final nodeSubnet = '${nodeParts[0]}.${nodeParts[1]}.${nodeParts[2]}';

      // Check if any gateway node is on the same subnet
      for (final gatewayIP in gatewayIPs) {
        final gatewayParts = gatewayIP.split('.');
        if (gatewayParts.length == 4) {
          final gatewaySubnet =
              '${gatewayParts[0]}.${gatewayParts[1]}.${gatewayParts[2]}';
          if (nodeSubnet == gatewaySubnet) {
            return false; // Same subnet
          }
        }
      }

      return true; // Different subnet
    } catch (e) {
      return false; // Default to false on error
    }
  }

  // Helper method to perform connectivity tests for cross-subnet nodes
  Future<void> _performConnectivityTests(String nodeIP) async {
    try {
      // Test basic connectivity with a simple ping endpoint
      final pingUrl = 'http://$nodeIP:$httpPort/ping';
      final pingRequest = await _httpClient!.getUrl(Uri.parse(pingUrl));
      final pingResponse = await pingRequest.close().timeout(
        Duration(seconds: 5),
      );
      if (kDebugMode) {
        print('    🔍 DEBUG: Ping endpoint status: ${pingResponse.statusCode}');
      }
    } catch (pingError) {
      if (kDebugMode) {
        print('    🔍 DEBUG: Ping endpoint failed: $pingError');
      }
    }

    try {
      // Test if web server root is accessible
      final testUrl = 'http://$nodeIP:$httpPort/';
      final testRequest = await _httpClient!.getUrl(Uri.parse(testUrl));
      final testResponse = await testRequest.close().timeout(
        Duration(seconds: 5),
      );
      if (kDebugMode) {
        print('    🔍 DEBUG: Root endpoint status: ${testResponse.statusCode}');
      }
    } catch (testError) {
      if (kDebugMode) {
        print('    🔍 DEBUG: Root endpoint failed: $testError');
      }
    }

    try {
      // Test debug endpoint for detailed node info
      final debugUrl = 'http://$nodeIP:$httpPort/debug';
      final debugRequest = await _httpClient!.getUrl(Uri.parse(debugUrl));
      final debugResponse = await debugRequest.close().timeout(
        Duration(seconds: 5),
      );
      if (debugResponse.statusCode == 200) {
        final debugBody = await debugResponse.transform(utf8.decoder).join();
        if (kDebugMode) {
          print(
            '    🔍 DEBUG: Node debug info: ${debugBody.substring(0, 100)}...',
          );
        }
      }
    } catch (debugError) {
      if (kDebugMode) {
        print('    🔍 DEBUG: Debug endpoint failed: $debugError');
      }
    }
  }

  // Helper method to validate if an IP address is actually reachable
  Future<bool> _validateNodeConnectivity(
    String nodeIP, {
    int timeoutSeconds = 3,
  }) async {
    try {
      final testUrl = 'http://$nodeIP:$httpPort/ping';
      final request = await _httpClient!.getUrl(Uri.parse(testUrl));
      final response = await request.close().timeout(
        Duration(seconds: timeoutSeconds),
      );
      await response.drain(); // Consume the response

      if (kDebugMode) {
        print('    ✅ IP $nodeIP is reachable (status: ${response.statusCode})');
      }
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print(
          '    ❌ IP $nodeIP is not reachable: ${e.toString().substring(0, 50)}...',
        );
      }
      return false;
    }
  }

  // Helper method to find the best reachable IP for a node
  Future<String?> _findBestReachableIP(AgriNode node) async {
    // List of potential IPs to test, prioritizing AP IP but including Station IP as fallback
    final candidateIPs = <String>[];

    if (node.apIP?.isNotEmpty == true && node.apIP != '0.0.0.0') {
      candidateIPs.add(node.apIP!);
    }

    if (node.stationIP?.isNotEmpty == true && node.stationIP != '0.0.0.0') {
      candidateIPs.add(node.stationIP!);
    }

    if (node.ipAddress.isNotEmpty && node.ipAddress != '0.0.0.0') {
      candidateIPs.add(node.ipAddress);
    }

    if (kDebugMode) {
      print(
        '    🔍 Testing connectivity for ${node.deviceName} (${node.deviceId}):',
      );
      print('      Candidate IPs: ${candidateIPs.join(', ')}');
    }

    // Test each IP and return the first reachable one
    for (final ip in candidateIPs) {
      if (await _validateNodeConnectivity(ip)) {
        if (kDebugMode) {
          print('      ✅ Best IP for ${node.deviceName}: $ip');
        }
        return ip;
      }
    }

    if (kDebugMode) {
      print('      ❌ No reachable IP found for ${node.deviceName}');
    }
    return null;
  }

  // Fallback Android-compatible discovery method
  Future<List<AgriNode>> _discoverNodesAndroidFallback() async {
    final List<AgriNode> nodes = [];

    if (kDebugMode) {
      print('Running Android fallback discovery...');
    }

    // Try known problematic IPs with individual probes
    final targetIPs = [
      '10.145.169.1',
      '10.35.17.1',
      '10.35.17.3',
      '10.76.77.1',
      '192.168.4.1',
      '192.168.1.1',
      '192.168.0.1',
    ];

    for (final ip in targetIPs) {
      try {
        if (kDebugMode) {
          print('  Probing $ip...');
        }

        final node = await _probeNode(ip);
        if (node != null) {
          nodes.add(node);
          if (kDebugMode) {
            print('  ✅ Found node at $ip: ${node.deviceName}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('  ❌ Failed to probe $ip: $e');
        }
      }
    }

    return nodes;
  }

  // Enhanced mesh discovery with Android fallback
  Future<List<AgriNode>> _discoverMeshNodesEnhanced() async {
    // First try the regular mesh discovery
    final regularNodes = await _discoverMeshNodes();

    if (regularNodes.isNotEmpty) {
      return regularNodes;
    }

    if (kDebugMode) {
      print('Regular mesh discovery failed, trying Android fallback...');
    }

    // If that fails, try the Android-specific fallback
    return await _discoverNodesAndroidFallback();
  }

  // Debug method to test buzzer endpoint connectivity
  Future<Map<String, dynamic>> testBuzzerConnectivity(String nodeId) async {
    final result = <String, dynamic>{
      'nodeId': nodeId,
      'timestamp': DateTime.now().toIso8601String(),
      'success': false,
      'details': <String, dynamic>{},
    };

    try {
      if (_discoveredNodes.isEmpty) {
        result['error'] = 'No nodes available';
        return result;
      }

      final targetNode = _discoveredNodes.firstWhere(
        (node) => node.deviceId == nodeId,
        orElse: () => _discoveredNodes.first,
      );

      result['details']['targetNode'] = {
        'deviceName': targetNode.deviceName,
        'deviceId': targetNode.deviceId,
        'ipAddress': targetNode.ipAddress,
        'apIP': targetNode.apIP,
        'stationIP': targetNode.stationIP,
        'isOnline': targetNode.isOnline,
      };

      // Test ping endpoint first
      try {
        final pingUrl = 'http://${targetNode.ipAddress}:$httpPort/ping';
        final pingResponse = await http
            .get(Uri.parse(pingUrl))
            .timeout(timeoutDuration);
        result['details']['pingTest'] = {
          'url': pingUrl,
          'status': pingResponse.statusCode,
          'body': pingResponse.body,
          'success': pingResponse.statusCode == 200,
        };
      } catch (e) {
        result['details']['pingTest'] = {
          'error': e.toString(),
          'success': false,
        };
      }

      // Test buzzer endpoint
      try {
        final buzzerUrl =
            'http://${targetNode.ipAddress}:$httpPort/api/control/buzzer';
        final testBody = {'action': 'test'};
        final buzzerResponse = await http
            .post(
              Uri.parse(buzzerUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(testBody),
            )
            .timeout(timeoutDuration);

        result['details']['buzzerTest'] = {
          'url': buzzerUrl,
          'requestBody': testBody,
          'status': buzzerResponse.statusCode,
          'responseBody': buzzerResponse.body,
          'success': buzzerResponse.statusCode == 200,
        };
      } catch (e) {
        result['details']['buzzerTest'] = {
          'error': e.toString(),
          'success': false,
        };
      }

      // Check if this is a relay scenario
      final homeNode = _discoveredNodes.first;
      if (nodeId != homeNode.deviceId) {
        result['details']['relayScenario'] = true;
        result['details']['homeNode'] = {
          'deviceName': homeNode.deviceName,
          'deviceId': homeNode.deviceId,
          'ipAddress': homeNode.ipAddress,
        };

        // Test relay endpoint
        try {
          final relayUrl =
              'http://${homeNode.ipAddress}:$httpPort/api/relay/buzzer';
          final relayBody = {'nodeId': nodeId, 'action': 'test'};
          final relayResponse = await http
              .post(
                Uri.parse(relayUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(relayBody),
              )
              .timeout(Duration(seconds: 10));

          result['details']['relayTest'] = {
            'url': relayUrl,
            'requestBody': relayBody,
            'status': relayResponse.statusCode,
            'responseBody': relayResponse.body,
            'success': relayResponse.statusCode == 200,
          };
        } catch (e) {
          result['details']['relayTest'] = {
            'error': e.toString(),
            'success': false,
          };
        }
      }

      result['success'] = true;
    } catch (e) {
      result['error'] = e.toString();
      result['stackTrace'] = StackTrace.current.toString();
    }

    if (kDebugMode) {
      print('🔍 BUZZER CONNECTIVITY TEST RESULT:');

      print(JsonEncoder.withIndent('  ').convert(result));
    }

    return result;
  }

  // Sync historical data from a single node's SD card
  Future<bool> syncNodeHistoricalData(String nodeId) async {
    try {
      final node = _discoveredNodes.firstWhere(
        (node) => node.deviceId == nodeId,
        orElse: () => throw Exception('Node $nodeId not found'),
      );

      await downloadAndSaveHistoricalData(node.ipAddress);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to sync historical data for node $nodeId: $e');
      }
      return false;
    }
  }

  // OPTIMIZED SD CARD OPERATIONS WITH SMART RELAY PATH SELECTION

  // Find the best relay path for a target node
  Future<String?> _findBestRelayPath(String targetNodeIP) async {
    if (kDebugMode) {
      print('🔍 Finding best relay path for $targetNodeIP...');
    }

    // Find the target node in discovered nodes
    final targetNode = _discoveredNodes.firstWhere(
      (node) => node.ipAddress == targetNodeIP,
      orElse: () => AgriNode(
        deviceId: '',
        deviceName: 'Unknown',
        ipAddress: targetNodeIP,
        lastSeen: DateTime.now(),
        isOnline: false,
        isLocal: false,
      ),
    );

    if (targetNode.deviceId.isEmpty) {
      if (kDebugMode) {
        print('❌ Target node $targetNodeIP not found in discovered nodes');
      }
      return null;
    }

    // Test potential relay nodes by trying a simple data request
    for (final homeNode in _discoveredNodes) {
      if (homeNode.ipAddress == targetNodeIP) {
        continue; // Skip if this is the target node
      }

      if (kDebugMode) {
        print(
          '🧪 Testing relay path through ${homeNode.ipAddress} for target ${targetNode.deviceId}',
        );
      }

      try {
        // Test with a simple device info request first
        final response = await http
            .get(
              Uri.parse(
                'http://${homeNode.ipAddress}:$httpPort/api/relay/data?nodeId=${targetNode.deviceId}',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(Duration(seconds: 3)); // Short timeout for testing

        if (response.statusCode == 200) {
          if (kDebugMode) {
            print(
              '✅ Relay path confirmed: ${homeNode.ipAddress} -> ${targetNode.deviceId}',
            );
          }
          return homeNode.ipAddress;
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Relay test failed through ${homeNode.ipAddress}: $e');
        }
        continue;
      }
    }

    if (kDebugMode) {
      print('❌ No working relay path found for $targetNodeIP');
    }
    return null;
  }

  // Optimized SD card operations using pre-selected relay path
  Future<List<String>> getAvailableDataFilesOptimized(String nodeIP) async {
    // Try direct access first with short timeout
    try {
      final response = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/files'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 3)); // Short timeout

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          print('✅ Direct SD card access successful for $nodeIP');
        }
        return List<String>.from(data['files'] ?? []);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Direct access failed for $nodeIP, finding relay path...');
      }
    }

    // Find the best relay path
    final relayNodeIP = await _findBestRelayPath(nodeIP);
    if (relayNodeIP == null) {
      return [];
    }

    // Use the confirmed relay path
    final targetNode = _discoveredNodes.firstWhere(
      (node) => node.ipAddress == nodeIP,
    );

    try {
      final response = await http
          .get(
            Uri.parse(
              'http://$relayNodeIP:$httpPort/api/relay/sdcard/files?nodeId=${targetNode.deviceId}',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 8)); // Reasonable timeout

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          print(
            '✅ Got ${data['files']?.length ?? 0} files via relay $relayNodeIP',
          );
        }
        return List<String>.from(data['files'] ?? []);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Relay SD card files request failed: $e');
      }
    }

    return [];
  }

  Future<String?> downloadDataFileOptimized(
    String nodeIP,
    String fileName, {
    String? relayNodeIP,
  }) async {
    // Try direct access first if no relay specified
    if (relayNodeIP == null) {
      try {
        final response = await http
            .get(
              Uri.parse(
                'http://$nodeIP:$httpPort/api/sdcard/download?file=$fileName',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(Duration(seconds: 5)); // Short timeout

        if (response.statusCode == 200) {
          if (kDebugMode) {
            print('✅ Direct download successful for $fileName');
          }
          return response.body;
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Direct download failed for $fileName, finding relay...');
        }
      }

      // Find relay path if not provided
      relayNodeIP = await _findBestRelayPath(nodeIP);
      if (relayNodeIP == null) {
        return null;
      }
    }

    // Use the relay path
    final targetNode = _discoveredNodes.firstWhere(
      (node) => node.ipAddress == nodeIP,
    );

    // Retry logic for received files that might be locked
    int maxRetries = fileName.startsWith('received_') ? 3 : 1;
    int timeoutSeconds = fileName.startsWith('received_') ? 25 : 15;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .get(
              Uri.parse(
                'http://$relayNodeIP:$httpPort/api/relay/sdcard/download?nodeId=${targetNode.deviceId}&file=$fileName',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(Duration(seconds: timeoutSeconds));

        if (response.statusCode == 200) {
          if (kDebugMode) {
            print(
              '✅ Downloaded $fileName via relay $relayNodeIP (${response.body.length} chars)${attempt > 1 ? " on attempt $attempt" : ""}',
            );
          }
          return response.body;
        } else if (response.statusCode == 408 && attempt < maxRetries) {
          if (kDebugMode) {
            print(
              '⏳ Timeout downloading $fileName (attempt $attempt/$maxRetries), retrying...',
            );
          }
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            '❌ Relay download failed for $fileName (attempt $attempt/$maxRetries): $e',
          );
        }
        if (attempt < maxRetries &&
            (e.toString().contains('timeout') ||
                e.toString().contains('TimeoutException'))) {
          if (kDebugMode) {
            print('🔄 Retrying $fileName after timeout...');
          }
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
      }
      break; // Exit loop if not retrying
    }

    return null;
  }

  // Batch download all files efficiently using the same relay path
  Future<Map<String, String>> downloadAllDataFilesBatch(
    String nodeIP,
    List<String> fileNames,
  ) async {
    final Map<String, String> results = {};

    if (fileNames.isEmpty) {
      return results;
    }

    if (kDebugMode) {
      print(
        '📦 Starting batch download of ${fileNames.length} files from $nodeIP',
      );
    }

    // Find the best relay path once
    String? relayNodeIP;

    // Try direct access for first file to test connectivity
    try {
      final testResponse = await http
          .get(
            Uri.parse('http://$nodeIP:$httpPort/api/sdcard/files'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 3));

      if (testResponse.statusCode == 200) {
        if (kDebugMode) {
          print('✅ Using direct access for batch download');
        }
        // Direct access works, use it for all files
        for (final fileName in fileNames) {
          try {
            final response = await http
                .get(
                  Uri.parse(
                    'http://$nodeIP:$httpPort/api/sdcard/download?file=$fileName',
                  ),
                  headers: {'Content-Type': 'application/json'},
                )
                .timeout(Duration(seconds: 10));

            if (response.statusCode == 200) {
              results[fileName] = response.body;
              if (kDebugMode) {
                print(
                  '✅ Downloaded $fileName (${results.length}/${fileNames.length})',
                );
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ Failed to download $fileName: $e');
            }
          }
        }
        return results;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Direct access failed, finding relay path...');
      }
    }

    // Find relay path
    relayNodeIP = await _findBestRelayPath(nodeIP);
    if (relayNodeIP == null) {
      if (kDebugMode) {
        print('❌ No relay path found for batch download');
      }
      return results;
    }

    if (kDebugMode) {
      print('✅ Using relay path $relayNodeIP for batch download');
    }

    // Download all files using the same relay path
    for (final fileName in fileNames) {
      final content = await downloadDataFileOptimized(
        nodeIP,
        fileName,
        relayNodeIP: relayNodeIP,
      );

      if (content != null) {
        results[fileName] = content;
        if (kDebugMode) {
          print(
            '✅ Downloaded $fileName (${results.length}/${fileNames.length})',
          );
        }
      } else {
        if (kDebugMode) {
          print('❌ Failed to download $fileName via relay');
        }
      }
    }

    if (kDebugMode) {
      print(
        '📦 Batch download complete: ${results.length}/${fileNames.length} files successful',
      );
    }

    return results;
  }
}
