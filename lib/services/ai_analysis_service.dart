import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agri_node.dart';

class AIAnalysisService {
  static final AIAnalysisService _instance = AIAnalysisService._internal();
  factory AIAnalysisService() => _instance;
  AIAnalysisService._internal();

  static AIAnalysisService get instance => _instance;

  Future<String?> _getNgrokUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('ai_ngrok_url');
      return url?.isNotEmpty == true ? url : null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, String>> _getFarmConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'fieldSize': prefs.getString('farm_field_size') ?? '',
        'cropType': prefs.getString('farm_crop_type') ?? '',
        'location': prefs.getString('farm_location') ?? '',
        'soilType': prefs.getString('farm_soil_type') ?? '',
        'plantingDate': prefs.getString('farm_planting_date') ?? '',
        'seedVariety': prefs.getString('farm_seed_variety') ?? '',
        'expectedHarvest': prefs.getString('farm_expected_harvest') ?? '',
        'climateZone': prefs.getString('farm_climate_zone') ?? '',
        'rainfallPattern': prefs.getString('farm_rainfall_pattern') ?? '',
        'irrigationMethod': prefs.getString('farm_irrigation_method') ?? '',
        'fertilizerType': prefs.getString('farm_fertilizer_type') ?? '',
        'previousYield': prefs.getString('farm_previous_yield') ?? '',
        'country': 'Sri Lanka', // Always set for Sri Lankan context
      };
    } catch (e) {
      return {'country': 'Sri Lanka'};
    }
  }

  Future<Map<String, dynamic>?> performAIAnalysis({
    required List<SensorData> sensorData,
    required List<AgriNode> nodes,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final ngrokUrl = await _getNgrokUrl();
      if (ngrokUrl == null || ngrokUrl.isEmpty) {
        return null; // Fallback to local analysis
      }

      final farmConfig = await _getFarmConfiguration();

      // Prepare data for AI analysis
      final requestData = {
        'sensor_data': sensorData
            .map(
              (data) => {
                'device_id': data.deviceId,
                'device_name': data.deviceName,
                'timestamp': data.timestamp.millisecondsSinceEpoch,
                'temperature': data.temperature,
                'humidity': data.humidity,
                'soil_moisture': data.soilMoisture,
                'motion_detected': data.motionDetected,
                'distance': data.distance,
                'buzzer_active': data.buzzerActive,
                'is_local': data.isLocal,
              },
            )
            .toList(),
        'nodes': nodes
            .map(
              (node) => {
                'device_id': node.deviceId,
                'device_name': node.deviceName,
                'ip_address': node.ipAddress,
                'is_online': node.isOnline,
                'is_local': node.isLocal,
                'last_seen': node.lastSeen.millisecondsSinceEpoch,
                'device_type': node.deviceType,
                'firmware_version': node.firmwareVersion,
                'status': node.status,
              },
            )
            .toList(),
        'farm_config': farmConfig,
        'analysis_timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await http
          .post(
            Uri.parse('$ngrokUrl/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestData),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        if (kDebugMode) {
          if (kDebugMode) {
            if (kDebugMode) {
              print(
                'AI Analysis API Error: ${response.statusCode} - ${response.body}',
              );
            }
          }
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('AI Analysis Error: $e');
      }
      return null; // Fallback to local analysis
    }
  }

  Future<Map<String, dynamic>?> getAIRecommendations({
    required List<SensorData> sensorData,
    required Map<String, String> farmConfig,
  }) async {
    try {
      final ngrokUrl = await _getNgrokUrl();
      if (ngrokUrl == null || ngrokUrl.isEmpty) {
        return null;
      }

      final requestData = {
        'sensor_data': sensorData
            .map(
              (data) => {
                'device_id': data.deviceId,
                'temperature': data.temperature,
                'humidity': data.humidity,
                'soil_moisture': data.soilMoisture,
                'timestamp': data.timestamp.millisecondsSinceEpoch,
              },
            )
            .toList(),
        'farm_config': farmConfig,
      };

      final response = await http
          .post(
            Uri.parse('$ngrokUrl/recommendations'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestData),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('AI Recommendations Error: $e');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPredictiveAlerts({
    required List<SensorData> sensorData,
    required Map<String, String> farmConfig,
  }) async {
    try {
      final ngrokUrl = await _getNgrokUrl();
      if (ngrokUrl == null || ngrokUrl.isEmpty) {
        return null;
      }

      final requestData = {
        'sensor_data': sensorData
            .map(
              (data) => {
                'device_id': data.deviceId,
                'temperature': data.temperature,
                'humidity': data.humidity,
                'soil_moisture': data.soilMoisture,
                'timestamp': data.timestamp.millisecondsSinceEpoch,
              },
            )
            .toList(),
        'farm_config': farmConfig,
      };

      final response = await http
          .post(
            Uri.parse('$ngrokUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestData),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('AI Predictions Error: $e');
      }
      return null;
    }
  }

  Future<bool> testConnection() async {
    try {
      final ngrokUrl = await _getNgrokUrl();
      if (ngrokUrl == null || ngrokUrl.isEmpty) {
        return false;
      }

      final response = await http
          .get(Uri.parse('$ngrokUrl/health'))
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
