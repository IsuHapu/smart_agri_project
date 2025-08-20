class AgriNode {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final String? apIP;
  final String? stationIP;
  final bool isOnline;
  final bool isLocal;
  final DateTime lastSeen;
  final String? deviceType;
  final String? firmwareVersion;
  final String? status;
  final int? meshNodeCount;
  final List<String> availableEndpoints;

  const AgriNode({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    this.apIP,
    this.stationIP,
    required this.isOnline,
    required this.isLocal,
    required this.lastSeen,
    this.deviceType,
    this.firmwareVersion,
    this.status,
    this.meshNodeCount,
    this.availableEndpoints = const [],
  });

  factory AgriNode.fromJson(Map<String, dynamic> json) {
    return AgriNode(
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? 'Unknown',
      ipAddress: json['ipAddress'] ?? json['stationIP'] ?? json['apIP'] ?? '',
      apIP: json['apIP'],
      stationIP: json['stationIP'],
      isOnline: json['isOnline'] ?? true,
      isLocal: json['isLocal'] ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['lastSeen'] * 1000).toInt(),
            )
          : DateTime.now(),
      deviceType: json['deviceType'],
      firmwareVersion: json['firmwareVersion'],
      status: json['status'],
      meshNodeCount: json['meshNodeCount'],
      availableEndpoints: List<String>.from(json['availableEndpoints'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'ipAddress': ipAddress,
      'apIP': apIP,
      'stationIP': stationIP,
      'isOnline': isOnline,
      'isLocal': isLocal,
      'lastSeen': lastSeen.millisecondsSinceEpoch ~/ 1000,
      'deviceType': deviceType,
      'firmwareVersion': firmwareVersion,
      'status': status,
      'meshNodeCount': meshNodeCount,
      'availableEndpoints': availableEndpoints,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgriNode &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;

  @override
  String toString() =>
      'AgriNode(deviceId: $deviceId, deviceName: $deviceName, ipAddress: $ipAddress)';
}

class SensorData {
  final String deviceId;
  final String deviceName;
  final DateTime timestamp;
  final double temperature;
  final double humidity;
  final int soilMoisture;
  final bool motionDetected;
  final double distance;
  final bool buzzerActive;
  final String? stationIP;
  final String? apIP;
  final bool isLocal;

  const SensorData({
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.motionDetected,
    required this.distance,
    required this.buzzerActive,
    this.stationIP,
    this.apIP,
    required this.isLocal,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      deviceId: json['deviceId'] ?? json['id'] ?? '',
      deviceName: json['deviceName'] ?? json['name'] ?? 'Unknown',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] * 1000).toInt(),
            )
          : DateTime.now(),
      temperature: (json['temperature'] ?? json['temp'] ?? 0.0).toDouble(),
      humidity: (json['humidity'] ?? json['hum'] ?? 0.0).toDouble(),
      soilMoisture: (json['soilMoisture'] ?? json['soil'] ?? 0).toInt(),
      motionDetected:
          json['motionDetected'] == true ||
          json['pirStatus'] == 1 ||
          json['motion'] == true,
      distance: (json['distance'] ?? json['dist'] ?? 0.0).toDouble(),
      buzzerActive:
          json['buzzerActive'] == true ||
          json['buzzerStatus'] == 1 ||
          json['buzz'] == true,
      stationIP: json['stationIP'],
      apIP: json['apIP'],
      isLocal: json['isLocal'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'temperature': temperature,
      'humidity': humidity,
      'soilMoisture': soilMoisture,
      'pirStatus': motionDetected ? 1 : 0,
      'distance': distance,
      'buzzerStatus': buzzerActive ? 1 : 0,
      'stationIP': stationIP,
      'apIP': apIP,
      'isLocal': isLocal,
    };
  }
}

class NetworkStatus {
  final String nodeId;
  final String deviceName;
  final String stationIP;
  final String apIP;
  final int meshNodes;
  final int wifiStatus;
  final int signalStrength;
  final int uptime;
  final int freeHeap;

  const NetworkStatus({
    required this.nodeId,
    required this.deviceName,
    required this.stationIP,
    required this.apIP,
    required this.meshNodes,
    required this.wifiStatus,
    required this.signalStrength,
    required this.uptime,
    required this.freeHeap,
  });

  factory NetworkStatus.fromJson(Map<String, dynamic> json) {
    return NetworkStatus(
      nodeId: json['nodeId'] ?? '',
      deviceName: json['deviceName'] ?? 'Unknown',
      stationIP: json['stationIP'] ?? '',
      apIP: json['apIP'] ?? '',
      meshNodes: json['meshNodes'] ?? 0,
      wifiStatus: json['wifiStatus'] ?? 0,
      signalStrength: json['signalStrength'] ?? 0,
      uptime: json['uptime'] ?? 0,
      freeHeap: json['freeHeap'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'deviceName': deviceName,
      'stationIP': stationIP,
      'apIP': apIP,
      'meshNodes': meshNodes,
      'wifiStatus': wifiStatus,
      'signalStrength': signalStrength,
      'uptime': uptime,
      'freeHeap': freeHeap,
    };
  }
}

class SensorReading {
  final DateTime timestamp;
  final double temperature;
  final double humidity;
  final int soilMoisture;
  final bool motionDetected;
  final double distance;
  final bool buzzerActive;

  const SensorReading({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.soilMoisture,
    required this.motionDetected,
    required this.distance,
    required this.buzzerActive,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] * 1000).toInt(),
            )
          : DateTime.now(),
      temperature: (json['temperature'] ?? json['temp'] ?? 0.0).toDouble(),
      humidity: (json['humidity'] ?? json['hum'] ?? 0.0).toDouble(),
      soilMoisture: (json['soilMoisture'] ?? json['soil'] ?? 0).toInt(),
      motionDetected: json['pirStatus'] == 1 || json['motion'] == true,
      distance: (json['distance'] ?? json['dist'] ?? 0.0).toDouble(),
      buzzerActive: json['buzzerStatus'] == 1 || json['buzz'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'temperature': temperature,
      'humidity': humidity,
      'soilMoisture': soilMoisture,
      'pirStatus': motionDetected ? 1 : 0,
      'distance': distance,
      'buzzerStatus': buzzerActive ? 1 : 0,
    };
  }
}

enum NodeConnectionStatus { connecting, connected, disconnected, error }

enum SensorType {
  temperature,
  humidity,
  soilMoisture,
  motion,
  distance,
  buzzer,
}
