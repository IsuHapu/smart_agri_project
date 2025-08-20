import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../services/firebase_service.dart';
import '../services/firestore_data_service.dart';
import '../models/agri_node.dart';

// Service providers
final networkServiceProvider = Provider<NetworkService>((ref) {
  final service = NetworkService();
  ref.onDispose(() => service.dispose());

  // Initialize the service immediately
  service.init();

  return service;
});

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

// Authentication providers
final authStateProvider = StreamProvider<User?>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) => user,
    loading: () => null,
    error: (_, _) => null,
  );
});

// Network providers
final connectionStatusProvider = StreamProvider<bool>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return networkService.connectionStatusStream;
});

final discoveredNodesProvider = StreamProvider<List<AgriNode>>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return networkService.nodesStream;
});

final currentSensorDataProvider = StreamProvider<Map<String, SensorData>>((
  ref,
) {
  final networkService = ref.watch(networkServiceProvider);
  return networkService.sensorDataStream;
});

// 📡 Scanning state providers for UI indicators
final isDiscoveringProvider = StreamProvider<bool>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return networkService.isDiscoveringStream;
});

final isFetchingDataProvider = StreamProvider<bool>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return networkService.isFetchingDataStream;
});

// Firebase data providers
final savedNodesProvider = StreamProvider<List<AgriNode>>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.getNodesStream();
});

final sensorDataHistoryProvider =
    StreamProvider.family<List<SensorData>, SensorDataQuery>((ref, query) {
      final firebaseService = ref.watch(firebaseServiceProvider);
      return firebaseService.getSensorDataStream(
        nodeId: query.nodeId,
        startDate: query.startDate,
        endDate: query.endDate,
        limit: query.limit,
      );
    });

// Combined data provider
final allNodesProvider = Provider<List<AgriNode>>((ref) {
  final discoveredNodes = ref.watch(discoveredNodesProvider);
  final savedNodes = ref.watch(savedNodesProvider);

  return discoveredNodes.when(
    data: (discovered) => savedNodes.when(
      data: (saved) {
        // Merge discovered and saved nodes, prioritizing discovered (live) data
        final Map<String, AgriNode> nodeMap = {};

        // Add saved nodes first
        for (final node in saved) {
          nodeMap[node.deviceId] = node;
        }

        // Override with discovered nodes (live data)
        for (final node in discovered) {
          nodeMap[node.deviceId] = node;
        }

        return nodeMap.values.toList();
      },
      loading: () => discovered,
      error: (_, _) => discovered,
    ),
    loading: () => savedNodes.when(
      data: (saved) => saved,
      loading: () => <AgriNode>[],
      error: (_, _) => <AgriNode>[],
    ),
    error: (_, _) => savedNodes.when(
      data: (saved) => saved,
      loading: () => <AgriNode>[],
      error: (_, _) => <AgriNode>[],
    ),
  );
});

// Initialization provider
final initializationProvider = FutureProvider<void>((ref) async {
  final networkService = ref.watch(networkServiceProvider);
  await networkService.init();
});

// Data query class
class SensorDataQuery {
  final String? nodeId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int limit;

  const SensorDataQuery({
    this.nodeId,
    this.startDate,
    this.endDate,
    this.limit = 100,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorDataQuery &&
        other.nodeId == nodeId &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.limit == limit;
  }

  @override
  int get hashCode {
    return nodeId.hashCode ^
        startDate.hashCode ^
        endDate.hashCode ^
        limit.hashCode;
  }
}

// UI state providers
final selectedNodeProvider = StateProvider<AgriNode?>((ref) => null);

final dateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  // Extended range for historical data - 30 days should cover most SD card sync scenarios
  return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
});

final historicalDataProvider =
    StreamProvider.family<List<SensorReading>, String>((ref, nodeId) {
      if (nodeId.isEmpty) {
        return Stream.value(<SensorReading>[]);
      }

      final firebaseService = ref.watch(firebaseServiceProvider);
      final dateRange = ref.watch(dateRangeProvider);

      return firebaseService.getSensorReadingsStream(
        nodeId: nodeId,
        startDate: dateRange.start,
        endDate: dateRange.end,
      );
    });

// Firestore data service provider
final firestoreDataServiceProvider = Provider<FirestoreDataService>((ref) {
  return FirestoreDataService.instance;
});

// Enhanced historical data provider that uses Firestore data
final enhancedHistoricalDataProvider =
    StreamProvider.family<List<SensorReading>, String>((ref, nodeId) {
      if (nodeId.isEmpty) {
        return Stream.value(<SensorReading>[]);
      }

      final firestoreService = ref.watch(firestoreDataServiceProvider);
      final dateRange = ref.watch(dateRangeProvider);

      // Return Firestore data stream with automatic offline/online handling
      return firestoreService.getSensorReadingsStream(
        deviceId: nodeId,
        startDate: dateRange.start,
        endDate: dateRange.end,
        limit: 1000,
      );
    });

// Debug provider to check all data without date filtering
final debugAllDataProvider = StreamProvider.family<List<SensorReading>, String>(
  (ref, nodeId) {
    if (nodeId.isEmpty) {
      return Stream.value(<SensorReading>[]);
    }

    final firestoreService = ref.watch(firestoreDataServiceProvider);
    return firestoreService.getAllSensorReadingsStream(deviceId: nodeId);
  },
);

// Connection status provider for UI feedback
final connectionStatusFirestoreProvider = StreamProvider<bool>((ref) {
  final firestoreService = ref.watch(firestoreDataServiceProvider);
  return firestoreService.connectionStatusStream;
});

// Data stats provider
final dataStatsProvider = FutureProvider<Map<String, int>>((ref) {
  final firestoreService = ref.watch(firestoreDataServiceProvider);
  return firestoreService.getDataStats();
});

// Manual sync provider for UI force sync button
final manualSyncProvider = FutureProvider<bool>((ref) async {
  final firestoreService = ref.watch(firestoreDataServiceProvider);
  await firestoreService.forceSyncToFirebase();
  return true;
});

// Network management provider
final networkManagementProvider = Provider<NetworkManagementService>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  final firestoreService = ref.watch(firestoreDataServiceProvider);
  return NetworkManagementService(networkService, firestoreService);
});

class NetworkManagementService {
  final NetworkService _networkService;
  final FirestoreDataService _firestoreService;

  NetworkManagementService(this._networkService, this._firestoreService);

  Future<bool> forceSyncAllData() async {
    try {
      // Force sync trigger (Firestore handles actual syncing)
      await _firestoreService.forceSyncToFirebase();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Force sync failed: $e');
      }
      return false;
    }
  }

  Future<bool> controlNodeBuzzer(String nodeId, bool turnOn) async {
    // Convert boolean to action string for the new relay system
    final action = turnOn ? 'on' : 'off';
    return await _networkService.controlBuzzer(nodeId, action);
  }

  Future<NetworkStatus?> getNodeNetworkStatus(String nodeId) async {
    final node = _networkService.discoveredNodes.firstWhere(
      (n) => n.deviceId == nodeId,
      orElse: () => throw Exception('Node not found'),
    );

    return await _networkService.fetchNetworkStatus(node.ipAddress);
  }
}
