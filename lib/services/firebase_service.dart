import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/agri_node.dart';
import '../utils/firestore_debug_helper.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collections
  static const String usersCollection = 'users';
  static const String nodesCollection = 'nodes';
  static const String sensorDataCollection = 'sensor_data';
  static const String historicalDataCollection = 'historical_data';

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

  // Authentication
  Future<UserCredential?> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update user document
      if (credential.user != null) {
        await _updateUserDocument(credential.user!);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('Sign in error: ${e.code} - ${e.message}');
      }
      rethrow;
    }
  }

  Future<UserCredential?> registerWithEmailPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update user profile
      if (credential.user != null) {
        await credential.user!.updateDisplayName(displayName);
        await _createUserDocument(credential.user!, displayName);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('Registration error: ${e.code} - ${e.message}');
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('Password reset error: ${e.code} - ${e.message}');
      }
      rethrow;
    }
  }

  // User document management
  Future<void> _createUserDocument(User user, String displayName) async {
    final userDoc = _firestore.collection(usersCollection).doc(user.uid);

    await userDoc.set({
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName,
      'photoURL': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'settings': {
        'notifications': true,
        'autoSync': true,
        'dataRetentionDays': 30,
      },
    });
  }

  Future<void> _updateUserDocument(User user) async {
    final userDoc = _firestore.collection(usersCollection).doc(user.uid);

    await userDoc.update({'lastLoginAt': FieldValue.serverTimestamp()});
  }

  // Node management
  Future<void> saveNode(AgriNode node) async {
    if (!isLoggedIn) return;

    final nodeDoc = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(nodesCollection)
        .doc(node.deviceId);

    await nodeDoc.set({
      'deviceId': node.deviceId,
      'deviceName': node.deviceName,
      'ipAddress': node.ipAddress,
      'apIP': node.apIP,
      'stationIP': node.stationIP,
      'deviceType': node.deviceType,
      'firmwareVersion': node.firmwareVersion,
      'isLocal': node.isLocal,
      'lastSeen': Timestamp.fromDate(node.lastSeen),
      'savedAt': FieldValue.serverTimestamp(),
      'availableEndpoints': node.availableEndpoints,
    }, SetOptions(merge: true));
  }

  Future<void> saveNodes(List<AgriNode> nodes) async {
    if (!isLoggedIn) return;

    final batch = _firestore.batch();

    for (final node in nodes) {
      final nodeDoc = _firestore
          .collection(usersCollection)
          .doc(currentUser!.uid)
          .collection(nodesCollection)
          .doc(node.deviceId);

      batch.set(nodeDoc, {
        'deviceId': node.deviceId,
        'deviceName': node.deviceName,
        'ipAddress': node.ipAddress,
        'apIP': node.apIP,
        'stationIP': node.stationIP,
        'deviceType': node.deviceType,
        'firmwareVersion': node.firmwareVersion,
        'isLocal': node.isLocal,
        'lastSeen': Timestamp.fromDate(node.lastSeen),
        'savedAt': FieldValue.serverTimestamp(),
        'availableEndpoints': node.availableEndpoints,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Stream<List<AgriNode>> getNodesStream() {
    if (!isLoggedIn) return Stream.value([]);

    return _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(nodesCollection)
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return AgriNode(
              deviceId: data['deviceId'] ?? '',
              deviceName: data['deviceName'] ?? 'Unknown',
              ipAddress: data['ipAddress'] ?? '',
              apIP: data['apIP'],
              stationIP: data['stationIP'],
              isOnline: false, // Will be updated by network service
              isLocal: data['isLocal'] ?? false,
              lastSeen:
                  (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
              deviceType: data['deviceType'],
              firmwareVersion: data['firmwareVersion'],
              availableEndpoints: List<String>.from(
                data['availableEndpoints'] ?? [],
              ),
            );
          }).toList();
        });
  }

  // Sensor data management
  Future<void> saveSensorData(String nodeId, SensorData sensorData) async {
    if (!isLoggedIn) return;

    final dataDoc = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(sensorDataCollection)
        .doc('${nodeId}_${sensorData.timestamp.millisecondsSinceEpoch}');

    await dataDoc.set({
      'deviceId': sensorData.deviceId,
      'deviceName': sensorData.deviceName,
      'timestamp': Timestamp.fromDate(sensorData.timestamp),
      'temperature': sensorData.temperature,
      'humidity': sensorData.humidity,
      'soilMoisture': sensorData.soilMoisture,
      'motionDetected': sensorData.motionDetected,
      'distance': sensorData.distance,
      'buzzerActive': sensorData.buzzerActive,
      'stationIP': sensorData.stationIP,
      'apIP': sensorData.apIP,
      'isLocal': sensorData.isLocal,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveSensorDataBatch(
    Map<String, SensorData> sensorDataMap,
  ) async {
    if (!isLoggedIn || sensorDataMap.isEmpty) return;

    final batch = _firestore.batch();

    for (final entry in sensorDataMap.entries) {
      final nodeId = entry.key;
      final sensorData = entry.value;

      final dataDoc = _firestore
          .collection(usersCollection)
          .doc(currentUser!.uid)
          .collection(sensorDataCollection)
          .doc('${nodeId}_${sensorData.timestamp.millisecondsSinceEpoch}');

      batch.set(dataDoc, {
        'deviceId': sensorData.deviceId,
        'deviceName': sensorData.deviceName,
        'timestamp': Timestamp.fromDate(sensorData.timestamp),
        'temperature': sensorData.temperature,
        'humidity': sensorData.humidity,
        'soilMoisture': sensorData.soilMoisture,
        'motionDetected': sensorData.motionDetected,
        'distance': sensorData.distance,
        'buzzerActive': sensorData.buzzerActive,
        'stationIP': sensorData.stationIP,
        'apIP': sensorData.apIP,
        'isLocal': sensorData.isLocal,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Stream<List<SensorData>> getSensorDataStream({
    String? nodeId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) {
    if (!isLoggedIn) return Stream.value([]);

    Query query = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(sensorDataCollection);

    if (nodeId != null) {
      query = query.where('deviceId', isEqualTo: nodeId);
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

    query = query.orderBy('timestamp', descending: true).limit(limit);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SensorData(
          deviceId: data['deviceId'] ?? '',
          deviceName: data['deviceName'] ?? 'Unknown',
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          temperature: (data['temperature'] ?? 0.0).toDouble(),
          humidity: (data['humidity'] ?? 0.0).toDouble(),
          soilMoisture: (data['soilMoisture'] ?? 0).toInt(),
          motionDetected: data['motionDetected'] ?? false,
          distance: (data['distance'] ?? 0.0).toDouble(),
          buzzerActive: data['buzzerActive'] ?? false,
          stationIP: data['stationIP'],
          apIP: data['apIP'],
          isLocal: data['isLocal'] ?? false,
        );
      }).toList();
    });
  }

  // Historical data management
  Future<void> saveHistoricalData(
    String nodeId,
    List<SensorReading> readings,
  ) async {
    if (!isLoggedIn || readings.isEmpty) return;

    final historyDoc = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(historicalDataCollection)
        .doc('${nodeId}_${DateTime.now().millisecondsSinceEpoch}');

    await historyDoc.set({
      'deviceId': nodeId,
      'readings': readings
          .map(
            (reading) => {
              'timestamp': Timestamp.fromDate(reading.timestamp),
              'temperature': reading.temperature,
              'humidity': reading.humidity,
              'soilMoisture': reading.soilMoisture,
              'motionDetected': reading.motionDetected,
              'distance': reading.distance,
              'buzzerActive': reading.buzzerActive,
            },
          )
          .toList(),
      'savedAt': FieldValue.serverTimestamp(),
      'readingCount': readings.length,
    });
  }

  // Data export
  Future<List<SensorData>> exportSensorData({
    DateTime? startDate,
    DateTime? endDate,
    String? nodeId,
  }) async {
    if (!isLoggedIn) return [];

    Query query = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(sensorDataCollection);

    if (nodeId != null) {
      query = query.where('deviceId', isEqualTo: nodeId);
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

    query = query.orderBy('timestamp', descending: false);

    final snapshot = await query.get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return SensorData(
        deviceId: data['deviceId'] ?? '',
        deviceName: data['deviceName'] ?? 'Unknown',
        timestamp:
            (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        temperature: (data['temperature'] ?? 0.0).toDouble(),
        humidity: (data['humidity'] ?? 0.0).toDouble(),
        soilMoisture: (data['soilMoisture'] ?? 0).toInt(),
        motionDetected: data['motionDetected'] ?? false,
        distance: (data['distance'] ?? 0.0).toDouble(),
        buzzerActive: data['buzzerActive'] ?? false,
        stationIP: data['stationIP'],
        apIP: data['apIP'],
        isLocal: data['isLocal'] ?? false,
      );
    }).toList();
  }

  // File upload (for SD card data)
  Future<String?> uploadFile(String fileName, List<int> bytes) async {
    if (!isLoggedIn) return null;

    try {
      final ref = _storage
          .ref()
          .child('users')
          .child(currentUser!.uid)
          .child('uploads')
          .child(fileName);

      final uploadTask = ref.putData(Uint8List.fromList(bytes));
      final snapshot = await uploadTask;

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) {
        print('File upload error: $e');
      }
      return null;
    }
  }

  // Clean up old data
  Future<void> cleanupOldData({int retentionDays = 30}) async {
    if (!isLoggedIn) return;

    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));

    final query = _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(sensorDataCollection)
        .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate));

    final snapshot = await query.get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    if (kDebugMode) {
      print('Cleaned up ${snapshot.docs.length} old sensor data records');
    }
  }

  Stream<List<SensorReading>> getSensorReadingsStream({
    required String nodeId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    if (!isLoggedIn || nodeId.isEmpty) {
      return Stream.value(<SensorReading>[]);
    }

    // Log the query for debugging
    FirestoreDebugHelper.logQuery('getSensorReadingsStream', {
      'nodeId': nodeId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'collection': historicalDataCollection,
    });

    // Alternative approach: Use only deviceId filter and handle date filtering in app
    return _firestore
        .collection(usersCollection)
        .doc(currentUser!.uid)
        .collection(historicalDataCollection)
        .where('deviceId', isEqualTo: nodeId)
        .orderBy('savedAt', descending: false)
        .snapshots()
        .handleError((error) {
          FirestoreDebugHelper.logQueryResult(
            'getSensorReadingsStream',
            0,
            error: error.toString(),
          );

          if (error.toString().contains('index')) {
            FirestoreDebugHelper.logIndexRequirement(historicalDataCollection, [
              'deviceId',
              'savedAt',
            ], 'where + orderBy');
          }
        })
        .map((snapshot) {
          // Filter results by date range in the app
          final filteredDocs = snapshot.docs.where((doc) {
            final data = doc.data();
            final savedAt = (data['savedAt'] as Timestamp?)?.toDate();
            if (savedAt == null) return false;
            return savedAt.isAfter(startDate.subtract(Duration(days: 1))) &&
                savedAt.isBefore(endDate.add(Duration(days: 1)));
          }).toList();

          List<SensorReading> allReadings = [];

          for (final doc in filteredDocs) {
            final data = doc.data();
            final readings = data['readings'] as List<dynamic>? ?? [];

            for (final reading in readings) {
              allReadings.add(
                SensorReading(
                  timestamp: (reading['timestamp'] as Timestamp).toDate(),
                  temperature: (reading['temperature'] ?? 0.0).toDouble(),
                  humidity: (reading['humidity'] ?? 0.0).toDouble(),
                  soilMoisture: (reading['soilMoisture'] ?? 0).toInt(),
                  motionDetected: reading['motionDetected'] ?? false,
                  distance: (reading['distance'] ?? 0.0).toDouble(),
                  buzzerActive: reading['buzzerActive'] ?? false,
                ),
              );
            }
          }

          FirestoreDebugHelper.logQueryResult(
            'getSensorReadingsStream',
            allReadings.length,
          );

          return allReadings;
        });
  }
}
