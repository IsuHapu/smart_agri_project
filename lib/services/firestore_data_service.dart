import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/agri_node.dart';
import 'offline_storage_service.dart';

class FirestoreDataService {
  static FirestoreDataService? _instance;
  FirestoreDataService._();

  static FirestoreDataService get instance {
    _instance ??= FirestoreDataService._();
    return _instance!;
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  static const String _sensorDataCollection = 'sensor_data';
  static const String _nodesCollection = 'nodes';
  static const String _usersCollection = 'users';

  User? get currentUser => _auth.currentUser;
  String? get userId => currentUser?.uid;

  // Stream to track connection status
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  Timer? _connectionTimer;

  FirestoreDataService() {
    _startConnectionMonitoring();
  }

  void _startConnectionMonitoring() {
    _connectionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConnectionStatus();
    });
    _checkConnectionStatus(); // Initial check
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = !connectivityResult.contains(ConnectivityResult.none);

      if (isConnected) {
        // Try to read from Firestore to confirm actual connectivity
        await _firestore.collection(_sensorDataCollection).limit(1).get();
      }

      _connectionStatusController.add(isConnected);
    } catch (e) {
      _connectionStatusController.add(false);
    }
  }

  // Save sensor data with automatic offline/online handling
  Future<void> saveSensorData(SensorData sensorData) async {
    if (userId == null) {
      if (kDebugMode) {
        print('❌ Cannot save sensor data: User not authenticated');
      }
      return;
    }

    // Always save to offline storage first
    await OfflineStorageService.instance.saveSensorDataOffline(sensorData);

    try {
      final docData = {
        'userId': userId,
        'deviceId': sensorData.deviceId,
        'deviceName': sensorData.deviceName,
        'ipAddress': sensorData.stationIP ?? sensorData.apIP ?? '',
        'temperature': sensorData.temperature,
        'humidity': sensorData.humidity,
        'soilMoisture': sensorData.soilMoisture,
        'distance': sensorData.distance,
        'motionDetected': sensorData.motionDetected,
        'buzzerActive': sensorData.buzzerActive,
        'timestamp': Timestamp.fromDate(sensorData.timestamp),
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Firestore automatically handles offline caching and syncing
      await _firestore.collection(_sensorDataCollection).add(docData);

      // Removed aggressive debug logging - data is automatically handled
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving sensor data to Firestore: $e');
        print('✅ Data available offline via local storage');
      }
      // Firestore will automatically retry when connection is restored
    }
  }

  // Save node information
  Future<void> saveNode(AgriNode node) async {
    if (userId == null) return;

    try {
      final docData = {
        'userId': userId,
        'deviceId': node.deviceId,
        'deviceName': node.deviceName,
        'ipAddress': node.ipAddress,
        'isOnline': node.isOnline,
        'isLocal': node.isLocal,
        'lastSeen': Timestamp.fromDate(node.lastSeen),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection(_nodesCollection)
          .doc(node.deviceId)
          .set(docData, SetOptions(merge: true));

      if (kDebugMode) {
        print('📱 Node data saved: ${node.deviceName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving node: $e');
      }
    }
  }

  // Get sensor readings with real-time updates
  Stream<List<SensorReading>> getSensorReadingsStream({
    String? deviceId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) {
    if (userId == null) {
      if (kDebugMode) {
        print('❌ Cannot get sensor readings: User not authenticated');
      }
      return Stream.value([]);
    }

    if (kDebugMode) {
      print('📊 Querying sensor readings: deviceId=$deviceId, user=$userId');
      print(
        '   Date range (createdAt): ${startDate?.toIso8601String()} to ${endDate?.toIso8601String()}',
      );
      print('   Filtering by: createdAt (when data was synced to Firebase)');
    }

    Query query = _firestore
        .collection(_sensorDataCollection)
        .where('userId', isEqualTo: userId);

    if (deviceId != null && deviceId.isNotEmpty) {
      query = query.where('deviceId', isEqualTo: deviceId);
    }

    if (startDate != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }

    if (endDate != null) {
      query = query.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    query = query.orderBy('createdAt', descending: true);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map((snapshot) {
      if (kDebugMode) {
        print(
          '📊 Retrieved ${snapshot.docs.length} sensor readings from Firestore',
        );
      }
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SensorReading(
          temperature: (data['temperature'] ?? 0.0).toDouble(),
          humidity: (data['humidity'] ?? 0.0).toDouble(),
          soilMoisture: (data['soilMoisture'] ?? 0).toInt(),
          distance: (data['distance'] ?? 0.0).toDouble(),
          motionDetected: data['motionDetected'] ?? false,
          buzzerActive: data['buzzerActive'] ?? false,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
        );
      }).toList();
    });
  }

  // Debug method to get all sensor data without filtering
  Stream<List<SensorReading>> getAllSensorReadingsStream({String? deviceId}) {
    if (userId == null) {
      if (kDebugMode) {
        print('❌ Cannot get all sensor readings: User not authenticated');
      }
      return Stream.value([]);
    }

    Query query = _firestore
        .collection(_sensorDataCollection)
        .where('userId', isEqualTo: userId);

    if (deviceId != null && deviceId.isNotEmpty) {
      query = query.where('deviceId', isEqualTo: deviceId);
    }

    query = query.orderBy('createdAt', descending: true).limit(100);

    return query.snapshots().map((snapshot) {
      if (kDebugMode) {
        print(
          '📊 DEBUG: Retrieved ${snapshot.docs.length} total sensor readings',
        );
        if (snapshot.docs.isNotEmpty) {
          final firstDoc = snapshot.docs.first.data() as Map<String, dynamic>;
          print(
            '   First document: deviceId=${firstDoc['deviceId']}, createdAt=${firstDoc['createdAt']}',
          );
        }
      }
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SensorReading(
          temperature: (data['temperature'] ?? 0.0).toDouble(),
          humidity: (data['humidity'] ?? 0.0).toDouble(),
          soilMoisture: (data['soilMoisture'] ?? 0).toInt(),
          distance: (data['distance'] ?? 0.0).toDouble(),
          motionDetected: data['motionDetected'] ?? false,
          buzzerActive: data['buzzerActive'] ?? false,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
        );
      }).toList();
    });
  }

  // Get nodes with real-time updates
  Stream<List<AgriNode>> getNodesStream() {
    if (userId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection(_nodesCollection)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return AgriNode(
              deviceId: data['deviceId'] ?? '',
              deviceName: data['deviceName'] ?? 'Unknown Device',
              ipAddress: data['ipAddress'] ?? '',
              isOnline: data['isOnline'] ?? false,
              isLocal: data['isLocal'] ?? false,
              lastSeen: data['lastSeen'] != null
                  ? (data['lastSeen'] as Timestamp).toDate()
                  : DateTime.now(),
            );
          }).toList();
        });
  }

  // Get statistics about cached data
  Future<Map<String, int>> getDataStats() async {
    if (userId == null) {
      return {'totalSensorData': 0, 'totalNodes': 0, 'todayReadings': 0};
    }

    try {
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);

      // Use Firestore aggregation queries if available
      final sensorDataQuery = _firestore
          .collection(_sensorDataCollection)
          .where('userId', isEqualTo: userId);

      final todayQuery = sensorDataQuery.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
      );

      final nodesQuery = _firestore
          .collection(_nodesCollection)
          .where('userId', isEqualTo: userId);

      // Get counts (this works even offline with cached data)
      final futures = await Future.wait([
        sensorDataQuery.get(),
        todayQuery.get(),
        nodesQuery.get(),
      ]);

      return {
        'totalSensorData': futures[0].docs.length,
        'todayReadings': futures[1].docs.length,
        'totalNodes': futures[2].docs.length,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting data stats: $e');
      }
      return {'totalSensorData': 0, 'totalNodes': 0, 'todayReadings': 0};
    }
  }

  // Batch save historical data (with device context and duplication prevention)
  Future<void> saveHistoricalDataBatch(
    List<SensorReading> readings,
    String deviceId,
    String deviceName,
    String ipAddress,
  ) async {
    if (userId == null || readings.isEmpty) return;

    try {
      final batch = _firestore.batch();
      int duplicateCount = 0;
      int savedCount = 0;

      // Process readings in smaller chunks to avoid hitting Firestore limits
      const chunkSize = 100;

      for (int i = 0; i < readings.length; i += chunkSize) {
        final chunk = readings.skip(i).take(chunkSize).toList();

        // Create document IDs first to check for duplicates
        final docIds = <String>[];
        final docRefs = <DocumentReference>[];

        for (final reading in chunk) {
          // Create deterministic document ID to prevent duplicates
          final timestampMs = reading.timestamp.millisecondsSinceEpoch;
          final dataHash =
              '${reading.temperature}_${reading.humidity}_${reading.soilMoisture}'
                  .hashCode
                  .abs();
          final docId = '${userId}_${deviceId}_${timestampMs}_$dataHash';

          docIds.add(docId);
          docRefs.add(_firestore.collection(_sensorDataCollection).doc(docId));
        }

        // Check which documents already exist (batch operation)
        final existingDocs = await Future.wait(docRefs.map((ref) => ref.get()));

        // Create batch writes for new documents only
        for (int j = 0; j < chunk.length; j++) {
          final reading = chunk[j];
          final docRef = docRefs[j];
          final exists = existingDocs[j].exists;

          if (exists) {
            duplicateCount++;
            continue;
          }

          final docData = {
            'userId': userId,
            'deviceId': deviceId,
            'deviceName': deviceName,
            'ipAddress': ipAddress,
            'temperature': reading.temperature,
            'humidity': reading.humidity,
            'soilMoisture': reading.soilMoisture,
            'distance': reading.distance,
            'motionDetected': reading.motionDetected,
            'buzzerActive': reading.buzzerActive,
            'timestamp': Timestamp.fromDate(reading.timestamp),
            'createdAt': FieldValue.serverTimestamp(),
          };
          batch.set(docRef, docData);
          savedCount++;
        }

        // Commit this chunk
        if (savedCount > 0) {
          await batch.commit();
        }

        if (kDebugMode) {
          print(
            '📊 Processed chunk ${(i / chunkSize).floor() + 1}: $savedCount new, $duplicateCount duplicates',
          );
        }
      }

      if (kDebugMode) {
        print(
          '📊 Total batch results: $savedCount new readings saved, $duplicateCount duplicates skipped',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving historical data batch: $e');
      }
    }
  }

  // Force sync - mainly for UI feedback (Firestore handles sync automatically)
  Future<void> forceSyncToFirebase() async {
    try {
      // Enable network (in case it was disabled)
      await _firestore.enableNetwork();

      // Trigger a small write to force sync
      if (userId != null) {
        await _firestore.collection(_usersCollection).doc(userId).set({
          'lastSyncForced': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (kDebugMode) {
        print('🔄 Force sync triggered');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error forcing sync: $e');
      }
    }
  }

  // Get sensor data with offline fallback
  Future<List<SensorData>> getSensorDataWithOffline({
    DateTime? startDate,
    DateTime? endDate,
    String? deviceId,
    int? limit,
  }) async {
    try {
      // First try to get from Firestore
      if (userId != null) {
        Query query = _firestore
            .collection(_sensorDataCollection)
            .where('userId', isEqualTo: userId);

        if (deviceId != null && deviceId.isNotEmpty) {
          query = query.where('deviceId', isEqualTo: deviceId);
        }

        if (startDate != null) {
          query = query.where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          );
        }

        if (endDate != null) {
          query = query.where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          );
        }

        query = query.orderBy('timestamp', descending: true);

        if (limit != null) {
          query = query.limit(limit);
        }

        final snapshot = await query.get();

        if (snapshot.docs.isNotEmpty) {
          final sensorDataList = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return SensorData(
              deviceId: data['deviceId'] ?? '',
              deviceName: data['deviceName'] ?? 'Unknown',
              timestamp: (data['timestamp'] as Timestamp).toDate(),
              temperature: (data['temperature'] ?? 0.0).toDouble(),
              humidity: (data['humidity'] ?? 0.0).toDouble(),
              soilMoisture: (data['soilMoisture'] ?? 0).toInt(),
              distance: (data['distance'] ?? 0.0).toDouble(),
              motionDetected: data['motionDetected'] ?? false,
              buzzerActive: data['buzzerActive'] ?? false,
              stationIP: data['ipAddress'],
              apIP: data['ipAddress'],
              isLocal: false,
            );
          }).toList();

          if (kDebugMode) {
            print(
              '📊 Retrieved ${sensorDataList.length} records from Firestore',
            );
          }

          return sensorDataList;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting data from Firestore: $e');
        print('📱 Falling back to offline data');
      }
    }

    // Fallback to offline storage
    final offlineData = await OfflineStorageService.instance
        .getSensorDataOffline(
          startDate: startDate,
          endDate: endDate,
          deviceId: deviceId,
        );

    if (limit != null && offlineData.length > limit) {
      return offlineData.take(limit).toList();
    }

    if (kDebugMode) {
      print('📱 Retrieved ${offlineData.length} records from offline storage');
    }

    return offlineData;
  }

  // Get nodes with offline fallback
  Future<List<AgriNode>> getNodesWithOffline() async {
    try {
      // First try to get from Firestore
      if (userId != null) {
        final snapshot = await _firestore
            .collection(_nodesCollection)
            .where('userId', isEqualTo: userId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final nodes = snapshot.docs.map((doc) {
            final data = doc.data();
            return AgriNode(
              deviceId: data['deviceId'] ?? '',
              deviceName: data['deviceName'] ?? 'Unknown Device',
              ipAddress: data['ipAddress'] ?? '',
              isOnline: data['isOnline'] ?? false,
              isLocal: data['isLocal'] ?? false,
              lastSeen: data['lastSeen'] != null
                  ? (data['lastSeen'] as Timestamp).toDate()
                  : DateTime.now(),
            );
          }).toList();

          // Also save to offline storage for future offline access
          await OfflineStorageService.instance.saveNodesOffline(nodes);

          if (kDebugMode) {
            print('📱 Retrieved ${nodes.length} nodes from Firestore');
          }

          return nodes;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting nodes from Firestore: $e');
        print('📱 Falling back to offline data');
      }
    }

    // Fallback to offline storage
    final offlineNodes = await OfflineStorageService.instance.getNodesOffline();

    if (kDebugMode) {
      print('📱 Retrieved ${offlineNodes.length} nodes from offline storage');
    }

    return offlineNodes;
  }

  // Get unique device IDs with offline fallback
  Future<List<String>> getUniqueDeviceIdsWithOffline() async {
    try {
      // First try to get from Firestore
      if (userId != null) {
        final snapshot = await _firestore
            .collection(_sensorDataCollection)
            .where('userId', isEqualTo: userId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final deviceIds = snapshot.docs
              .map((doc) => doc.data()['deviceId'] as String)
              .toSet()
              .toList();

          if (kDebugMode) {
            print(
              '📱 Found ${deviceIds.length} unique device IDs from Firestore',
            );
          }

          return deviceIds;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting device IDs from Firestore: $e');
        print('📱 Falling back to offline data');
      }
    }

    // Fallback to offline storage
    final offlineDeviceIds = await OfflineStorageService.instance
        .getUniqueDeviceIds();

    if (kDebugMode) {
      print(
        '📱 Found ${offlineDeviceIds.length} unique device IDs from offline storage',
      );
    }

    return offlineDeviceIds;
  }

  // Save node and update offline storage
  Future<void> saveNodeWithOffline(AgriNode node) async {
    // Save to offline storage first
    await OfflineStorageService.instance.saveNodesOffline([node]);

    // Then save to Firestore
    await saveNode(node);
  }

  // Clean up resources
  void dispose() {
    _connectionTimer?.cancel();
    _connectionStatusController.close();
  }
}
