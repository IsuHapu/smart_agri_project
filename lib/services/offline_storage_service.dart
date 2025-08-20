import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/agri_node.dart';

class OfflineStorageService {
  static OfflineStorageService? _instance;
  OfflineStorageService._();

  static OfflineStorageService get instance {
    _instance ??= OfflineStorageService._();
    return _instance!;
  }

  static const String _sensorDataKey = 'offline_sensor_data';
  static const String _nodesKey = 'offline_nodes';
  static const String _nodeIdsKey = 'known_node_ids';

  // Save sensor data locally
  Future<void> saveSensorDataOffline(SensorData sensorData) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing data
      final existingDataJson = prefs.getString(_sensorDataKey) ?? '[]';
      final List<dynamic> existingData = jsonDecode(existingDataJson);

      // Add new data
      existingData.add(sensorData.toJson());

      // Keep only last 1000 records to prevent storage overflow
      if (existingData.length > 1000) {
        existingData.removeRange(0, existingData.length - 1000);
      }

      // Save back to storage
      await prefs.setString(_sensorDataKey, jsonEncode(existingData));

      // Removed aggressive debug logging for offline saves
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving sensor data offline: $e');
      }
    }
  }

  // Get sensor data from local storage
  Future<List<SensorData>> getSensorDataOffline({
    DateTime? startDate,
    DateTime? endDate,
    String? deviceId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataJson = prefs.getString(_sensorDataKey) ?? '[]';
      final List<dynamic> dataList = jsonDecode(dataJson);

      List<SensorData> sensorDataList = dataList
          .map((json) => SensorData.fromJson(json))
          .toList();

      // Filter by date range if provided
      if (startDate != null || endDate != null) {
        sensorDataList = sensorDataList.where((data) {
          if (startDate != null && data.timestamp.isBefore(startDate)) {
            return false;
          }
          if (endDate != null && data.timestamp.isAfter(endDate)) {
            return false;
          }
          return true;
        }).toList();
      }

      // Filter by device ID if provided
      if (deviceId != null) {
        sensorDataList = sensorDataList
            .where((data) => data.deviceId == deviceId)
            .toList();
      }

      // Sort by timestamp (newest first)
      sensorDataList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return sensorDataList;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting sensor data offline: $e');
      }
      return [];
    }
  }

  // Save nodes information locally
  Future<void> saveNodesOffline(List<AgriNode> nodes) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final nodesJson = nodes.map((node) => node.toJson()).toList();
      await prefs.setString(_nodesKey, jsonEncode(nodesJson));

      // Also save unique node IDs for offline reference
      final nodeIds = nodes.map((node) => node.deviceId).toSet().toList();
      await saveKnownNodeIds(nodeIds);

      if (kDebugMode) {
        print('📱 ${nodes.length} nodes saved offline');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving nodes offline: $e');
      }
    }
  }

  // Get nodes from local storage
  Future<List<AgriNode>> getNodesOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nodesJson = prefs.getString(_nodesKey) ?? '[]';
      final List<dynamic> nodesList = jsonDecode(nodesJson);

      return nodesList.map((json) => AgriNode.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting nodes offline: $e');
      }
      return [];
    }
  }

  // Save known node IDs (for showing node names even when offline)
  Future<void> saveKnownNodeIds(List<String> nodeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_nodeIdsKey, nodeIds);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving known node IDs: $e');
      }
    }
  }

  // Get known node IDs
  Future<List<String>> getKnownNodeIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_nodeIdsKey) ?? [];
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting known node IDs: $e');
      }
      return [];
    }
  }

  // Get all unique device IDs from stored sensor data
  Future<List<String>> getUniqueDeviceIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataJson = prefs.getString(_sensorDataKey) ?? '[]';
      final List<dynamic> dataList = jsonDecode(dataJson);

      final Set<String> deviceIds = dataList
          .map((json) => json['deviceId'] as String?)
          .where(
            (deviceId) =>
                deviceId != null &&
                deviceId.isNotEmpty &&
                deviceId != 'null' &&
                deviceId != '0',
          )
          .cast<String>()
          .toSet();

      return deviceIds.toList();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting unique device IDs: $e');
      }
      return [];
    }
  }

  // Get device name by ID (from stored data)
  Future<String> getDeviceNameById(String deviceId) async {
    try {
      // First try to get from nodes
      final nodes = await getNodesOffline();
      final node = nodes.where((n) => n.deviceId == deviceId).firstOrNull;
      if (node != null) {
        return node.deviceName;
      }

      // Fallback to sensor data
      final prefs = await SharedPreferences.getInstance();
      final dataJson = prefs.getString(_sensorDataKey) ?? '[]';
      final List<dynamic> dataList = jsonDecode(dataJson);

      for (final json in dataList) {
        if (json['deviceId'] == deviceId) {
          return json['deviceName'] ?? 'Unknown Device';
        }
      }

      return 'Unknown Device';
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting device name: $e');
      }
      return 'Unknown Device';
    }
  }

  // Clear all offline data
  Future<void> clearOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sensorDataKey);
      await prefs.remove(_nodesKey);
      await prefs.remove(_nodeIdsKey);

      if (kDebugMode) {
        print('🗑️ All offline data cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing offline data: $e');
      }
    }
  }

  // Get storage statistics
  Future<Map<String, int>> getStorageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final sensorDataJson = prefs.getString(_sensorDataKey) ?? '[]';
      final nodesJson = prefs.getString(_nodesKey) ?? '[]';

      final sensorDataCount = (jsonDecode(sensorDataJson) as List).length;
      final nodesCount = (jsonDecode(nodesJson) as List).length;
      final nodeIdsCount = (prefs.getStringList(_nodeIdsKey) ?? []).length;

      return {
        'sensorDataCount': sensorDataCount,
        'nodesCount': nodesCount,
        'knownNodeIdsCount': nodeIdsCount,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting storage stats: $e');
      }
      return {'sensorDataCount': 0, 'nodesCount': 0, 'knownNodeIdsCount': 0};
    }
  }
}
