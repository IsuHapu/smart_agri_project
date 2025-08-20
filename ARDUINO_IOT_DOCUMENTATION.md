# Smart Agriculture ESP32 IoT System - Arduino Code Documentation

## Table of Contents
1. [Overview](#overview)
2. [Hardware Architecture](#hardware-architecture) 
3. [IoT Protocols Implementation](#iot-protocols-implementation)
4. [UDP Communication System](#udp-communication-system)
5. [Relay System](#relay-system)
6. [Mesh Network Architecture](#mesh-network-architecture)
7. [Sensor Data Management](#sensor-data-management)
8. [HTTP REST API](#http-rest-api)
9. [CoAP Protocol Support](#coap-protocol-support)
10. [Data Persistence](#data-persistence)
11. [Network Discovery](#network-discovery)
12. [Code Structure](#code-structure)

## Overview

The Smart Agriculture ESP32 system implements a **self-healing mesh network** of IoT devices for agricultural monitoring and control. Each ESP32 node functions as both a sensor station and a communication relay, creating a robust distributed system that can operate independently of internet connectivity.

### Key Features
- **Mesh Networking**: Self-healing painlessMesh network topology
- **Multi-Protocol Communication**: HTTP REST API, CoAP, and UDP protocols
- **Cross-Network Discovery**: UDP broadcast for cross-subnet device discovery
- **Relay System**: Intelligent message forwarding between mesh nodes
- **Local Data Storage**: SD card logging with automatic failover
- **Real-time Monitoring**: Live sensor data streaming and remote control

## Hardware Architecture

### Pin Configuration
```cpp
#define DHT_PIN         15    // Temperature & Humidity sensor
#define DHT_TYPE        DHT11 // DHT11 sensor type
#define SOIL_PIN        34    // Soil moisture analog input
#define PIR_PIN         13    // Motion detection sensor
#define TRIG_PIN        5     // Ultrasonic sensor trigger
#define ECHO_PIN        18    // Ultrasonic sensor echo
#define BUZZER_PIN      4     // Buzzer/alarm output
#define SD_CS_PIN       22    // SD card chip select
```

### Sensors and Actuators
1. **DHT11**: Temperature and humidity monitoring
2. **Soil Moisture Sensor**: Analog soil wetness measurement (0-100%)
3. **PIR Motion Sensor**: Motion detection for security
4. **HC-SR04 Ultrasonic**: Distance measurement for proximity detection
5. **Buzzer**: Audio alarm system
6. **SD Card Module**: Local data logging and backup

### Intelligent Automation
The system includes built-in automation logic:
```cpp
// Automatic buzzer activation
if (currentData.motionDetected && currentData.distance > 0 && currentData.distance < 10) {
    digitalWrite(BUZZER_PIN, HIGH);
    currentData.buzzerActive = true;
} else {
    digitalWrite(BUZZER_PIN, LOW);
    currentData.buzzerActive = false;
}
```

## IoT Protocols Implementation

### 1. HTTP REST API (Primary Protocol)
The system implements a comprehensive REST API for device communication:

#### Device Information Endpoints
- `GET /api/device/info` - Complete device status and sensor data
- `GET /discover` - Device discovery and capability advertisement
- `GET /api/mesh/nodes` - Mesh topology and connected devices

#### Control Endpoints
- `POST /api/control/buzzer` - Remote buzzer control (on/off/toggle)
- `GET /api/data/history` - Historical sensor data retrieval

#### Debug and Monitoring
- `GET /api/debug/sdcard` - SD card status and health
- `POST /api/debug/sdcard/test` - SD card read/write testing
- `GET /ping` - Basic connectivity test
- `GET /debug` - Comprehensive system information

### 2. CoAP Protocol Support
```cpp
void setupCoAP() {
    coap.start();
    Serial.println("📡 CoAP server started on port " + String(COAP_PORT));
}
```
CoAP (Constrained Application Protocol) provides:
- **Lightweight**: UDP-based, ideal for IoT devices
- **RESTful**: Similar API structure to HTTP
- **Efficient**: Lower overhead than HTTP for resource-constrained devices

### 3. UDP Communication Layer
UDP is used for multiple purposes:
- **Mesh Communication**: painlessMesh library internal protocol
- **Discovery Broadcasting**: Cross-subnet device discovery
- **Real-time Data**: Low-latency sensor data streaming

## UDP Communication System

### Discovery Broadcasting
The system implements sophisticated UDP discovery for cross-subnet communication:

```cpp
void broadcastDiscovery() {
    DynamicJsonDocument doc(512);
    doc["type"] = "AgriNodeDiscover";
    doc["action"] = "announce";
    doc["nodeId"] = currentData.nodeId;
    doc["deviceName"] = deviceName;
    doc["stationIP"] = WiFi.localIP().toString();
    doc["apIP"] = WiFi.softAPIP().toString();
    doc["meshSSID"] = MESH_PREFIX;
    doc["timestamp"] = millis();
    
    String message;
    serializeJson(doc, message);
    
    // Broadcast to common subnet ranges
    String broadcastIPs[] = {"192.168.1.255", "192.168.0.255", "10.0.0.255", 
                            "10.255.255.255", "172.16.255.255"};
    
    for (String ip : broadcastIPs) {
        discoveryUDP.beginPacket(ip.c_str(), 5554);
        discoveryUDP.print(message);
        discoveryUDP.endPacket();
    }
}
```

### UDP Discovery Features
1. **Multi-Subnet Broadcasting**: Reaches devices across network boundaries
2. **Service Advertisement**: Announces device capabilities and endpoints
3. **Network Topology Mapping**: Discovers mesh structure
4. **Automatic Registration**: Updates node registry with discovered devices

### UDP Packet Handling
```cpp
void handleDiscoveryUDP() {
    int packetSize = discoveryUDP.parsePacket();
    if (packetSize) {
        char incomingPacket[512];
        int len = discoveryUDP.read(incomingPacket, 511);
        
        if (len > 0) {
            incomingPacket[len] = 0;
            DynamicJsonDocument doc(512);
            
            if (deserializeJson(doc, incomingPacket) == DeserializationError::Ok) {
                // Process discovery message
                updateNodeRegistry(nodeId, deviceName, stationIP, apIP, false);
            }
        }
    }
}
```

## Relay System

The relay system is a sophisticated message forwarding mechanism that enables communication between nodes that cannot directly reach each other.

### Relay Architecture
1. **Request Forwarding**: Messages are forwarded through the mesh to target nodes
2. **Response Routing**: Responses are routed back through the mesh to originating nodes
3. **Loop Prevention**: Processed request tracking prevents infinite message loops
4. **Timeout Handling**: Request cleanup and timeout management

### Relay Message Types
```cpp
// Relay Request Structure
{
    "type": "relay_request",
    "targetNodeId": "target_device_id",
    "apiPath": "/api/control/buzzer",
    "requestId": "unique_request_id",
    "originNodeId": "originating_device_id",
    "postData": "{\"action\":\"on\"}"
}

// Relay Response Structure
{
    "type": "relay_response", 
    "requestId": "unique_request_id",
    "response": "{\"status\":\"Buzzer turned ON\"}"
}
```

### Relay Processing Logic
```cpp
void handleRelayRequest(String targetNodeId, String apiPath, String requestId, 
                       String originNodeId, String postData) {
    // Check if this node is the target
    if (targetNodeId == currentData.nodeId) {
        // Handle API request locally
        String response = handleLocalApiRequest(apiPath, postData);
        
        // Send response back through mesh
        DynamicJsonDocument responseDoc(1024);
        responseDoc["type"] = "relay_response";
        responseDoc["requestId"] = requestId;
        responseDoc["response"] = response;
        responseDoc["targetNodeId"] = originNodeId;
        
        String responseMsg;
        serializeJson(responseDoc, responseMsg);
        mesh.sendBroadcast(responseMsg);
    } else {
        // Forward the request to other nodes
        // ... forwarding logic
    }
}
```

### Relay Endpoints
The system provides HTTP endpoints that utilize the relay system:

1. **Remote Buzzer Control**: `POST /api/relay/buzzer`
   ```json
   {
       "nodeId": "target_device_id",
       "action": "on|off|toggle"
   }
   ```

2. **Remote Data Retrieval**: `GET /api/relay/data?nodeId=target_device_id`

3. **Remote Historical Data**: `GET /api/relay/download?nodeId=target_device_id`

### Loop Prevention
```cpp
// Check if we've already processed this request to prevent loops
if (processedRequests.find(requestId) != processedRequests.end()) {
    return; // Skip already processed requests
}

// Mark request as processed
processedRequests[requestId] = millis();
```

### Cleanup and Timeout Management
```cpp
void cleanupRelayRequests() {
    unsigned long currentTime = millis();
    unsigned long maxAge = 30000; // 30 seconds timeout
    
    // Clean up old pending relay requests
    auto pendingIt = pendingRelayRequests.begin();
    while (pendingIt != pendingRelayRequests.end()) {
        if ((currentTime - pendingIt->second) > maxAge) {
            pendingIt = pendingRelayRequests.erase(pendingIt);
        } else {
            ++pendingIt;
        }
    }
}
```

## Mesh Network Architecture

### PainlessMesh Configuration
```cpp
// Mesh settings - Single SSID for all nodes
#define MESH_PREFIX     "SmartAgriMesh"
#define MESH_PASSWORD   "agrimesh2024"
#define MESH_PORT       5555

void setup() {
    // Initialize mesh network
    mesh.setDebugMsgTypes(ERROR | STARTUP);
    mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT);
    mesh.onReceive(&receivedCallback);
    mesh.onNewConnection(&newConnectionCallback);
    mesh.onChangedConnections(&changedConnectionCallback);
    
    // Configure as mesh peer (no root)
    mesh.setRoot(false);
    mesh.setContainsRoot(false);
    
    // Set single AP with same SSID for all nodes
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(MESH_PREFIX, MESH_PASSWORD);
}
```

### Mesh Communication
1. **Broadcast Messages**: Sensor data shared across entire mesh
2. **Targeted Messages**: Relay system for point-to-point communication
3. **Topology Discovery**: Dynamic mesh structure discovery
4. **Auto-healing**: Automatic reconnection when nodes join/leave

### Message Broadcasting
```cpp
void broadcastData() {
    DynamicJsonDocument doc(1024);
    doc["id"] = currentData.nodeId;
    doc["name"] = deviceName;
    doc["stationIP"] = currentData.stationIP;
    doc["apIP"] = currentData.apIP;
    doc["temp"] = currentData.temperature;
    doc["hum"] = currentData.humidity;
    doc["soil"] = currentData.soilMoisture;
    doc["motion"] = currentData.motionDetected;
    doc["dist"] = currentData.distance;
    doc["buzz"] = currentData.buzzerActive;
    doc["time"] = currentData.timestamp;
    
    String msg;
    serializeJson(doc, msg);
    mesh.sendBroadcast(msg);
}
```

## Sensor Data Management

### Data Structure
```cpp
struct SensorData {
    String nodeId;
    String deviceName;
    String stationIP;
    String apIP;
    float temperature;
    float humidity;
    int soilMoisture;
    bool motionDetected;
    float distance;
    bool buzzerActive;
    unsigned long timestamp;
};
```

### Sensor Reading Process
```cpp
void readSensors() {
    currentData.timestamp = millis();
    
    // DHT11 temperature & humidity
    currentData.temperature = dht.readTemperature();
    currentData.humidity = dht.readHumidity();
    if (isnan(currentData.temperature)) currentData.temperature = -999;
    if (isnan(currentData.humidity)) currentData.humidity = -999;
    
    // Soil moisture (0-100%)
    currentData.soilMoisture = map(analogRead(SOIL_PIN), 0, 4095, 0, 100);
    
    // PIR motion
    currentData.motionDetected = digitalRead(PIR_PIN);
    
    // Ultrasonic distance
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    long duration = pulseIn(ECHO_PIN, HIGH, 30000);
    currentData.distance = (duration == 0) ? -1 : duration * 0.034 / 2;
}
```

### Task Scheduling
The system uses the painlessMesh task scheduler for precise timing:
```cpp
Task taskSensorRead(TASK_SECOND * 30, TASK_FOREVER, &readSensors);
Task taskBroadcast(TASK_SECOND * 60, TASK_FOREVER, &broadcastData);
Task taskSaveSD(TASK_SECOND * 120, TASK_FOREVER, &saveToSD);
Task taskCleanupRelay(TASK_SECOND * 60, TASK_FOREVER, &cleanupRelayRequests);
```

## Data Persistence

### SD Card Integration
The system implements comprehensive SD card data logging:

#### File Structure
- `/data/node_{nodeId}.json` - Local sensor data
- `/data/received_{nodeId}.json` - Data from other mesh nodes
- `/data/mesh_summary.json` - Complete mesh topology
- `/data/shared_data_log.json` - Historical mesh activity

#### Data Saving Process
```cpp
void saveToSD() {
    String filename = "/data/node_" + currentData.nodeId + ".json";
    File file = SD.open(filename, FILE_APPEND);
    
    if (file) {
        DynamicJsonDocument doc(256);
        doc["id"] = currentData.nodeId;
        doc["name"] = deviceName;
        doc["temp"] = currentData.temperature;
        doc["hum"] = currentData.humidity;
        doc["soil"] = currentData.soilMoisture;
        doc["motion"] = currentData.motionDetected;
        doc["dist"] = currentData.distance;
        doc["buzz"] = currentData.buzzerActive;
        doc["time"] = currentData.timestamp;
        doc["stationIP"] = currentData.stationIP;
        doc["apIP"] = currentData.apIP;
        
        serializeJson(doc, file);
        file.println();
        file.close();
    }
}
```

#### SD Card Health Monitoring
```cpp
void checkSDCardStatus() {
    // Check card accessibility
    if (SD.cardType() == 0) {
        Serial.println("❌ SD card not detected!");
        // Attempt re-initialization
        if (SD.begin(SD_CS_PIN)) {
            Serial.println("✅ SD card re-initialized successfully!");
        }
        return;
    }
    
    // Monitor storage space
    uint64_t totalBytes = SD.totalBytes();
    uint64_t usedBytes = SD.usedBytes();
    uint64_t freeBytes = totalBytes - usedBytes;
    
    if (freeBytes < (10 * 1024 * 1024)) { // Less than 10MB free
        Serial.println("⚠️ WARNING: Low disk space");
    }
}
```

## Network Discovery

### Multi-Method Discovery
The system employs multiple discovery methods for maximum device visibility:

1. **Mesh Broadcasting**: Internal mesh message propagation
2. **UDP Broadcasting**: Cross-subnet discovery packets
3. **IP Range Scanning**: Systematic IP address probing
4. **Topology Mapping**: Mesh structure analysis

### Node Registry Management
```cpp
void updateNodeRegistry(String nodeId, String deviceName, String stationIP, 
                       String apIP, bool meshConnected) {
    // Remove existing entry for this node
    nodeRegistry.erase(
        std::remove_if(nodeRegistry.begin(), nodeRegistry.end(),
            [&nodeId](const DiscoveredNode& node) { 
                return node.nodeId == nodeId; 
            }),
        nodeRegistry.end()
    );
    
    // Add updated entry
    DiscoveredNode newNode;
    newNode.nodeId = nodeId;
    newNode.deviceName = deviceName;
    newNode.stationIP = stationIP;
    newNode.apIP = apIP;
    newNode.lastSeen = millis();
    newNode.meshConnected = meshConnected;
    
    nodeRegistry.push_back(newNode);
}
```

### Discovery Response Format
```json
{
    "type": "SmartAgriDevice",
    "deviceId": "esp32_node_id", 
    "deviceName": "Custom Device Name",
    "version": "v2.2.0",
    "endpoints": "HTTP and CoAP available",
    "meshSSID": "SmartAgriMesh",
    "localIP": "192.168.1.100",
    "apIP": "10.145.169.1",
    "meshNodes": 3,
    "discoveryMethods": "mesh,udp,broadcast"
}
```

## Code Structure

### Main Components
1. **Core Loop**: `loop()` - Mesh updates and request handling
2. **Initialization**: `setup()` - Hardware and network initialization
3. **Sensor Management**: `readSensors()` - Data collection
4. **Communication**: `broadcastData()` - Mesh data sharing
5. **HTTP Server**: `setupHTTP()` - REST API endpoints
6. **Relay System**: `handleRelayRequest()` - Message forwarding
7. **Data Persistence**: `saveToSD()` - Local storage
8. **Discovery**: `broadcastDiscovery()` - Network discovery

### Key Libraries
- **painlessMesh**: Mesh networking foundation
- **ArduinoJson**: JSON parsing and generation
- **DHT**: Temperature/humidity sensor interface
- **WiFiUDP**: UDP communication
- **WebServer**: HTTP server implementation
- **SD**: SD card file system
- **coap-simple**: CoAP protocol support

### Memory Management
- **Dynamic JSON Documents**: Efficient memory allocation
- **String Management**: Careful string handling to prevent fragmentation  
- **Collection Cleanup**: Regular cleanup of expired data structures
- **Stack Optimization**: Minimal recursion and large local variables

This Arduino implementation creates a robust, self-healing IoT mesh network capable of operating independently while providing comprehensive monitoring and control capabilities for smart agriculture applications.
