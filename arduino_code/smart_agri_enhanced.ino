/*
 * Smart Agriculture ESP32 Mesh Network - Clean & Minimal
 * Self-healing mesh with sensor data sharing, HTTP/CoAP APIs
 * Based on painlessMesh library and Random Nerd Tutorials best practices
 */

#include <painlessMesh.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <SD.h>
#include <SPI.h>
#include <coap-simple.h>
#include <WiFiUDP.h>
#include <WebServer.h>
#include <map>
#include <vector>
#include <set>
#include <algorithm>

// Pin definitions
#define DHT_PIN         15
#define DHT_TYPE        DHT11
#define SOIL_PIN        34
#define PIR_PIN         13
#define TRIG_PIN        5
#define ECHO_PIN        18
#define BUZZER_PIN      4
#define SD_CS_PIN       22

// Mesh settings
#define MESH_PREFIX     "SmartAgriMesh"
#define MESH_PASSWORD   "agrimesh2024"
#define MESH_PORT       5555

// Server ports
#define HTTP_PORT       80
#define COAP_PORT       5683

// Global objects
Scheduler userScheduler;
painlessMesh mesh;
DHT dht(DHT_PIN, DHT_TYPE);
WebServer server(HTTP_PORT);
WiFiUDP udp;
Coap coap(udp);

// Simple sensor data structure
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

SensorData currentData;
std::vector<SensorData> receivedData;
String deviceName = "AgriNode"; // Default device name

// Relay system variables
std::map<String, String> relayResponses;
std::map<String, unsigned long> pendingRelayRequests;
std::map<String, unsigned long> processedRequests; // Track processed requests to prevent loops

// Node registry for discovered devices
struct DiscoveredNode {
  String nodeId;
  String deviceName;
  String stationIP;
  String apIP;
  unsigned long lastSeen;
  bool meshConnected;
};

std::vector<DiscoveredNode> nodeRegistry;
WiFiUDP discoveryUDP;

// Function prototypes
void readSensors();
void broadcastData();
void saveToSD();
void receivedCallback(uint32_t from, String &msg);
void newConnectionCallback(uint32_t nodeId);
void changedConnectionCallback();
void setupHTTP();
void setupCoAP();
String handleLocalApiRequest(String apiPath);
String handleLocalApiRequest(String apiPath, String postData);
void handleRelayRequest(String targetNodeId, String apiPath, String requestId, String originNodeId, String postData);
void handleRelayResponse(String requestId, String response);
void displayStatus();
void checkForDeviceName();
void monitorNetwork();
void broadcastDiscovery();
void handleDiscoveryUDP();
void updateNodeRegistry(String nodeId, String deviceName, String stationIP, String apIP, bool meshConnected);
void cleanupNodeRegistry();
void cleanupDisconnectedNodes();
void cleanupRelayRequests();
void checkSDCardStatus();
void saveSharedDataToSD();
String repeatChar(char c, int count);
String _getSubnetInfo();
bool _isDifferentSubnet(String clientIP);

// Helper function to repeat a character (Arduino String doesn't have repeat)
String repeatChar(char c, int count) {
  String result = "";
  for (int i = 0; i < count; i++) {
    result += c;
  }
  return result;
}

// Helper functions for network debugging
String _getSubnetInfo() {
  String stationIP = WiFi.localIP().toString();
  String apIP = WiFi.softAPIP().toString();
  
  if (stationIP != "0.0.0.0" && stationIP.length() > 7) {
    int lastDot = stationIP.lastIndexOf('.');
    return stationIP.substring(0, lastDot) + ".x (Station)";
  }
  
  if (apIP != "0.0.0.0" && apIP.length() > 7) {
    int lastDot = apIP.lastIndexOf('.');
    return apIP.substring(0, lastDot) + ".x (AP)";
  }
  
  return "Unknown subnet";
}

bool _isDifferentSubnet(String clientIP) {
  if (clientIP.length() < 7) return false;
  
  String stationIP = WiFi.localIP().toString();
  String apIP = WiFi.softAPIP().toString();
  
  // Extract subnet (first 3 octets) from client IP
  int lastDot = clientIP.lastIndexOf('.');
  if (lastDot == -1) return false;
  String clientSubnet = clientIP.substring(0, lastDot);
  
  // Check against station IP subnet
  if (stationIP != "0.0.0.0" && stationIP.length() > 7) {
    lastDot = stationIP.lastIndexOf('.');
    if (lastDot != -1) {
      String stationSubnet = stationIP.substring(0, lastDot);
      if (clientSubnet == stationSubnet) return false;
    }
  }
  
  // Check against AP IP subnet
  if (apIP != "0.0.0.0" && apIP.length() > 7) {
    lastDot = apIP.lastIndexOf('.');
    if (lastDot != -1) {
      String apSubnet = apIP.substring(0, lastDot);
      if (clientSubnet == apSubnet) return false;
    }
  }
  
  return true; // Different subnet
}

// Task definitions - following painlessMesh best practices
Task taskSensorRead(TASK_SECOND * 30, TASK_FOREVER, &readSensors);
Task taskBroadcast(TASK_SECOND * 60, TASK_FOREVER, &broadcastData);
Task taskSaveSD(TASK_SECOND * 120, TASK_FOREVER, &saveToSD);
Task taskSaveSharedData(TASK_SECOND * 180, TASK_FOREVER, &saveSharedDataToSD); // Save shared data every 3 minutes
Task taskDisplayStatus(TASK_SECOND * 10, TASK_FOREVER, &displayStatus);
Task taskCheckDeviceName(TASK_SECOND * 1, TASK_FOREVER, &checkForDeviceName);
Task taskMonitorNetwork(TASK_SECOND * 30, TASK_FOREVER, &monitorNetwork);
Task taskBroadcastDiscovery(TASK_SECOND * 45, TASK_FOREVER, &broadcastDiscovery);
Task taskCleanupRelay(TASK_SECOND * 60, TASK_FOREVER, &cleanupRelayRequests);
Task taskSDCardCheck(TASK_SECOND * 300, TASK_FOREVER, &checkSDCardStatus); // Check SD card every 5 minutes

void setup() {
  Serial.begin(115200);
  
  // Initialize pins
  pinMode(PIR_PIN, INPUT);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  
  // Initialize sensors
  dht.begin();
  
  // Initialize SD card with detailed debugging
  Serial.println("🔍 SD Card Initialization Debug:");
  Serial.println("  - CS Pin: " + String(SD_CS_PIN));
  Serial.println("  - Attempting SD.begin()...");
  
  if (SD.begin(SD_CS_PIN)) {
    Serial.println("  ✅ SD card initialized successfully");
    
    // Get card info
    uint64_t cardSize = SD.cardSize() / (1024 * 1024);
    Serial.println("  - Card Size: " + String((uint32_t)cardSize) + " MB");
    Serial.println("  - Card Type: " + String(SD.cardType()));
    
    // Check if data directory exists, create if not
    if (!SD.exists("/data")) {
      Serial.println("  - Creating /data directory...");
      if (SD.mkdir("/data")) {
        Serial.println("  ✅ /data directory created");
      } else {
        Serial.println("  ❌ Failed to create /data directory");
      }
    } else {
      Serial.println("  ✅ /data directory exists");
    }
    
    // Test write capability
    File testFile = SD.open("/data/test_write.txt", FILE_WRITE);
    if (testFile) {
      testFile.println("SD card test write - " + String(millis()));
      testFile.close();
      Serial.println("  ✅ SD card write test successful");
      
      // Test read capability
      testFile = SD.open("/data/test_write.txt", FILE_READ);
      if (testFile) {
        String testContent = testFile.readString();
        testFile.close();
        Serial.println("  ✅ SD card read test successful");
        Serial.println("  - Test content: " + testContent.substring(0, 50) + "...");
      } else {
        Serial.println("  ❌ SD card read test failed");
      }
    } else {
      Serial.println("  ❌ SD card write test failed");
    }
  } else {
    Serial.println("  ❌ SD card initialization failed!");
    Serial.println("  - Check connections:");
    Serial.println("    * CS pin " + String(SD_CS_PIN) + " connected?");
    Serial.println("    * MOSI, MISO, SCK connected?");
    Serial.println("    * Power supply sufficient?");
    Serial.println("    * SD card formatted (FAT32)?");
  }
  
  // Initialize mesh with a single SSID for all nodes
  mesh.setDebugMsgTypes(ERROR | STARTUP);
  mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT);
  mesh.onReceive(&receivedCallback);
  mesh.onNewConnection(&newConnectionCallback);
  mesh.onChangedConnections(&changedConnectionCallback);
  
  // Configure as mesh peer (no root)
  mesh.setRoot(false);
  mesh.setContainsRoot(false);
  
  // Set a single AP with the same SSID for all nodes
  WiFi.mode(WIFI_AP_STA); // Enable both AP and STA modes for mesh
  WiFi.softAP(MESH_PREFIX, MESH_PASSWORD); // Single SSID for all nodes
  Serial.println("📡 Node AP: " + String(MESH_PREFIX));
  Serial.println("📡 AP IP: " + WiFi.softAPIP().toString());
  
  // Wait for mesh to stabilize
  delay(5000); // Increased delay for mesh setup
  
  // Set device ID from mesh node ID
  currentData.nodeId = String(mesh.getNodeId());
  
  // Setup servers
  Serial.println("🔧 Starting server setup...");
  setupHTTP();
  setupCoAP();
  Serial.println("✅ Server setup complete!");
  
  // Setup UDP discovery
  discoveryUDP.begin(5554);
  Serial.println("📡 UDP Discovery listening on port 5554");
  
  // Add tasks to scheduler
  userScheduler.addTask(taskSensorRead);
  userScheduler.addTask(taskBroadcast);
  userScheduler.addTask(taskSaveSD);
  userScheduler.addTask(taskSaveSharedData);
  userScheduler.addTask(taskDisplayStatus);
  userScheduler.addTask(taskCheckDeviceName);
  userScheduler.addTask(taskMonitorNetwork);
  userScheduler.addTask(taskBroadcastDiscovery);
  userScheduler.addTask(taskCleanupRelay);
  userScheduler.addTask(taskSDCardCheck);
  
  // Enable tasks with delay to avoid conflicts
  taskSensorRead.enableDelayed();
  delay(1000);
  taskBroadcast.enableDelayed();
  delay(1000);
  taskSaveSD.enableDelayed();
  delay(1000);
  taskSaveSharedData.enableDelayed();
  delay(1000);
  taskDisplayStatus.enableDelayed();
  delay(1000);
  taskCheckDeviceName.enableDelayed();
  delay(1000);
  taskMonitorNetwork.enableDelayed();
  delay(1000);
  taskBroadcastDiscovery.enableDelayed();
  delay(1000);
  taskCleanupRelay.enableDelayed();
  delay(1000);
  taskSDCardCheck.enableDelayed();
  
  Serial.println("\n" + repeatChar('=', 50));
  Serial.println("🌱 SMART AGRICULTURE MESH PEER READY 🌱");
  Serial.println(repeatChar('=', 50));
  Serial.println("🔗 Pure Mesh Network - Single SSID: " + String(MESH_PREFIX));
  Serial.println("📱 Connect phone to: " + String(MESH_PREFIX));
  Serial.println("📝 Type a custom device name and press Enter");
  Serial.println("   (or wait 10 seconds to use default: " + deviceName + ")");
  Serial.println(repeatChar('=', 50));
  displayStatus(); // Show initial status
}

void loop() {
  mesh.update(); // Essential - keeps mesh running
  server.handleClient(); // Handle HTTP requests
  coap.loop();
  handleDiscoveryUDP(); // Handle UDP discovery packets
}

// Read all sensors
void readSensors() {
  currentData.timestamp = millis();
  
  // Update IP addresses
  currentData.stationIP = WiFi.localIP().toString();
  currentData.apIP = WiFi.softAPIP().toString();
  
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
  
  // Buzzer control
  if (currentData.motionDetected && currentData.distance > 0 && currentData.distance < 10) {
    digitalWrite(BUZZER_PIN, HIGH);
    currentData.buzzerActive = true;
  } else {
    digitalWrite(BUZZER_PIN, LOW);
    currentData.buzzerActive = false;
  }
  
  Serial.printf("Sensors: T=%.1f°C H=%.1f%% S=%d%% M=%s D=%.1fcm [%s/%s]\n",
               currentData.temperature, currentData.humidity, currentData.soilMoisture,
               currentData.motionDetected ? "Y" : "N", currentData.distance,
               currentData.stationIP.c_str(), currentData.apIP.c_str());
}

// Broadcast sensor data to mesh
void broadcastData() {
  // Update current data with latest IP addresses
  currentData.stationIP = WiFi.localIP().toString();
  currentData.apIP = WiFi.softAPIP().toString();
  
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
  mesh.sendBroadcast(msg); // Mesh broadcast
  Serial.println("📡 Data broadcasted to mesh from " + deviceName + " (" + currentData.stationIP + "/" + currentData.apIP + ")");
}

// Save current data to SD card with debugging
void saveToSD() {
  Serial.println("🔍 SD Save Debug - Local Data:");
  Serial.println("  - Node ID: " + currentData.nodeId);
  Serial.println("  - Device: " + deviceName);
  Serial.println("  - Timestamp: " + String(currentData.timestamp));
  
  String filename = "/data/node_" + currentData.nodeId + ".json";
  Serial.println("  - Filename: " + filename);
  
  File file = SD.open(filename, FILE_APPEND);
  if (!file) {
    Serial.println("  ❌ Failed to open file for writing: " + filename);
    Serial.println("  - SD card status: " + String(SD.cardType() > 0 ? "Connected" : "Disconnected"));
    Serial.println("  - Free space: " + String(SD.totalBytes() - SD.usedBytes()) + " bytes");
    return;
  }
  
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
  
  size_t bytesWritten = serializeJson(doc, file);
  file.println();
  file.close();
  
  Serial.println("  ✅ Local data saved (" + String(bytesWritten) + " bytes)");
}

// Save all shared data (from all nodes) to SD card
void saveSharedDataToSD() {
  Serial.println("🔍 SD Save Debug - All Shared Data:");
  
  if (SD.cardType() == 0) {
    Serial.println("  ❌ SD card not available for shared data save");
    return;
  }
  
  // Save summary of all nodes
  String summaryFile = "/data/mesh_summary.json";
  File file = SD.open(summaryFile, FILE_WRITE); // Overwrite each time
  
  if (!file) {
    Serial.println("  ❌ Failed to open summary file: " + summaryFile);
    return;
  }
  
  DynamicJsonDocument summaryDoc(2048);
  summaryDoc["timestamp"] = millis();
  summaryDoc["localNodeId"] = currentData.nodeId;
  summaryDoc["deviceName"] = deviceName;
  summaryDoc["meshPeers"] = mesh.getNodeList().size();
  summaryDoc["totalKnownNodes"] = receivedData.size() + 1; // +1 for local node
  
  JsonArray nodes = summaryDoc.createNestedArray("allNodes");
  
  // Add local node
  JsonObject localNode = nodes.createNestedObject();
  localNode["nodeId"] = currentData.nodeId;
  localNode["deviceName"] = deviceName;
  localNode["temperature"] = currentData.temperature;
  localNode["humidity"] = currentData.humidity;
  localNode["soilMoisture"] = currentData.soilMoisture;
  localNode["motionDetected"] = currentData.motionDetected;
  localNode["distance"] = currentData.distance;
  localNode["buzzerActive"] = currentData.buzzerActive;
  localNode["stationIP"] = currentData.stationIP;
  localNode["apIP"] = currentData.apIP;
  localNode["timestamp"] = currentData.timestamp;
  localNode["dataSource"] = "local";
  
  // Add received data from other nodes
  for (const auto& data : receivedData) {
    JsonObject node = nodes.createNestedObject();
    node["nodeId"] = data.nodeId;
    node["deviceName"] = data.deviceName;
    node["temperature"] = data.temperature;
    node["humidity"] = data.humidity;
    node["soilMoisture"] = data.soilMoisture;
    node["motionDetected"] = data.motionDetected;
    node["distance"] = data.distance;
    node["buzzerActive"] = data.buzzerActive;
    node["stationIP"] = data.stationIP;
    node["apIP"] = data.apIP;
    node["timestamp"] = data.timestamp;
    node["dataSource"] = "mesh";
  }
  
  size_t bytesWritten = serializeJson(summaryDoc, file);
  file.close();
  
  Serial.println("  ✅ Shared data summary saved (" + String(bytesWritten) + " bytes)");
  Serial.println("  - Local node: " + currentData.nodeId);
  Serial.println("  - Remote nodes: " + String(receivedData.size()));
  Serial.println("  - File: " + summaryFile);
  
  // Also save individual timestamped entries
  String sharedLogFile = "/data/shared_data_log.json";
  File logFile = SD.open(sharedLogFile, FILE_APPEND);
  if (logFile) {
    DynamicJsonDocument logEntry(512);
    logEntry["logTimestamp"] = millis();
    logEntry["totalNodes"] = receivedData.size() + 1;
    logEntry["meshPeers"] = mesh.getNodeList().size();
    
    JsonArray nodeIds = logEntry.createNestedArray("activeNodes");
    nodeIds.add(currentData.nodeId); // Local node
    for (const auto& data : receivedData) {
      nodeIds.add(data.nodeId);
    }
    
    serializeJson(logEntry, logFile);
    logFile.println();
    logFile.close();
    Serial.println("  ✅ Shared data log entry added");
  } else {
    Serial.println("  ❌ Failed to open shared log file");
  }
}

// Mesh callback functions
void receivedCallback(uint32_t from, String &msg) {
  Serial.println("📨 Received from " + String(from));
  
  DynamicJsonDocument doc(1024);
  if (deserializeJson(doc, msg) == DeserializationError::Ok) {
    
    // Check if this is a relay message
    if (doc.containsKey("type")) {
      String messageType = doc["type"];
      
      if (messageType == "relay_request") {
        String targetNodeId = doc["targetNodeId"];
        String apiPath = doc["apiPath"];
        String requestId = doc["requestId"];
        String originNodeId = doc["originNodeId"];
        String postData = doc["postData"] | "";
        
        // Check if we've already processed this request to prevent loops
        if (processedRequests.find(requestId) != processedRequests.end()) {
          // Skip already processed requests
          return;
        }
        
        // Mark request as processed
        processedRequests[requestId] = millis();
        
        Serial.println("   🔄 Relay request: " + apiPath + " -> " + targetNodeId);
        handleRelayRequest(targetNodeId, apiPath, requestId, originNodeId, postData);
        return;
      }
      
      if (messageType == "relay_response") {
        String requestId = doc["requestId"];
        String response = doc["response"];
        
        Serial.println("   ✅ Relay response for request: " + requestId);
        handleRelayResponse(requestId, response);
        return;
      }
    }
    
    // Handle normal sensor data message
    SensorData data;
    data.nodeId = doc["id"].as<String>();
    data.deviceName = doc["name"].as<String>();
    if (data.deviceName.length() == 0) data.deviceName = "Unknown";
    data.stationIP = doc["stationIP"].as<String>();
    data.apIP = doc["apIP"].as<String>();
    data.temperature = doc["temp"];
    data.humidity = doc["hum"];
    data.soilMoisture = doc["soil"];
    data.motionDetected = doc["motion"];
    data.distance = doc["dist"];
    data.buzzerActive = doc["buzz"];
    data.timestamp = doc["time"];
    
    Serial.println("   📋 From: " + data.deviceName + " (Node: " + data.nodeId + ")");
    Serial.println("   🌐 IPs: Station=" + data.stationIP + ", AP=" + data.apIP);
    Serial.println("   🌡️ " + String(data.temperature) + "°C, 💧 " + String(data.humidity) + "%");
    
    // Store received data (remove old data from same node first)
    receivedData.erase(
      std::remove_if(receivedData.begin(), receivedData.end(),
        [&data](const SensorData& existing) { return existing.nodeId == data.nodeId; }),
      receivedData.end()
    );
    receivedData.push_back(data);
    if (receivedData.size() > 50) receivedData.erase(receivedData.begin());
    
    // Clean up data from disconnected nodes periodically
    static unsigned long lastCleanup = 0;
    if (millis() - lastCleanup > 30000) { // Clean every 30 seconds
      cleanupDisconnectedNodes();
      lastCleanup = millis();
    }
    
    // Save received data to SD card with debugging
    Serial.println("🔍 SD Save Debug - Received Data:");
    Serial.println("  - From Node: " + data.nodeId + " (" + data.deviceName + ")");
    
    String receivedFilename = "/data/received_" + data.nodeId + ".json";
    Serial.println("  - Filename: " + receivedFilename);
    
    File file = SD.open(receivedFilename, FILE_APPEND);
    if (file) {
      DynamicJsonDocument saveDoc(512);
      saveDoc["id"] = data.nodeId;
      saveDoc["name"] = data.deviceName;
      saveDoc["temp"] = data.temperature;
      saveDoc["hum"] = data.humidity;
      saveDoc["soil"] = data.soilMoisture;
      saveDoc["motion"] = data.motionDetected;
      saveDoc["dist"] = data.distance;
      saveDoc["buzz"] = data.buzzerActive;
      saveDoc["time"] = data.timestamp;
      saveDoc["stationIP"] = data.stationIP;
      saveDoc["apIP"] = data.apIP;
      saveDoc["receivedAt"] = millis();
      saveDoc["receivedBy"] = currentData.nodeId;
      
      size_t bytesWritten = serializeJson(saveDoc, file);
      file.println();
      file.close();
      Serial.println("  ✅ Received data saved (" + String(bytesWritten) + " bytes)");
    } else {
      Serial.println("  ❌ Failed to open file for received data: " + receivedFilename);
      Serial.println("  - SD card status: " + String(SD.cardType() > 0 ? "Connected" : "Disconnected"));
      
      // Try to diagnose SD card issues
      if (SD.cardType() == 0) {
        Serial.println("  - SD card not detected - check connections");
      } else {
        uint64_t totalBytes = SD.totalBytes();
        uint64_t usedBytes = SD.usedBytes();
        Serial.println("  - SD card detected but file open failed");
        Serial.println("  - Total: " + String((uint32_t)(totalBytes/1024/1024)) + " MB");
        Serial.println("  - Used: " + String((uint32_t)(usedBytes/1024/1024)) + " MB");
        Serial.println("  - Free: " + String((uint32_t)((totalBytes-usedBytes)/1024/1024)) + " MB");
      }
    }
    
    // Update node registry with received node information
    updateNodeRegistry(data.nodeId, data.deviceName, data.stationIP, data.apIP, true);
  }
}

void newConnectionCallback(uint32_t nodeId) {
  Serial.println("New node: " + String(nodeId));
}

void changedConnectionCallback() {
  Serial.println("Mesh changed, nodes: " + String(mesh.getNodeList().size()));
  // Clean up disconnected nodes when mesh topology changes
  cleanupDisconnectedNodes();
}

// Enhanced discovery functions
void broadcastDiscovery() {
  // Send UDP broadcast for cross-subnet discovery
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
  String broadcastIPs[] = {"192.168.1.255", "192.168.0.255", "10.0.0.255", "10.255.255.255", "172.16.255.255"};
  
  for (String ip : broadcastIPs) {
    discoveryUDP.beginPacket(ip.c_str(), 5554);
    discoveryUDP.print(message);
    discoveryUDP.endPacket();
  }
  
  // Also send mesh discovery request
  DynamicJsonDocument meshDoc(256);
  meshDoc["type"] = "discoveryRequest";
  meshDoc["requestId"] = String(millis());
  meshDoc["originNode"] = currentData.nodeId;
  
  String meshMessage;
  serializeJson(meshDoc, meshMessage);
  mesh.sendBroadcast(meshMessage);
  
  Serial.println("📡 Discovery broadcast sent");
}

void handleDiscoveryUDP() {
  int packetSize = discoveryUDP.parsePacket();
  if (packetSize) {
    char incomingPacket[512];
    int len = discoveryUDP.read(incomingPacket, 511);
    if (len > 0) {
      incomingPacket[len] = 0;
      
      DynamicJsonDocument doc(512);
      DeserializationError error = deserializeJson(doc, incomingPacket);
      
      if (!error && doc["type"] == "AgriNodeDiscover") {
        String action = doc["action"];
        
        if (action == "announce") {
          // Another node is announcing itself
          String nodeId = doc["nodeId"];
          String deviceName = doc["deviceName"];
          String stationIP = doc["stationIP"];
          String apIP = doc["apIP"];
          
          if (nodeId != currentData.nodeId) {
            updateNodeRegistry(nodeId, deviceName, stationIP, apIP, false);
            Serial.println("📍 UDP Discovery: Found " + deviceName + " (" + nodeId + ") at " + stationIP);
          }
        } else if (action == "query") {
          // Someone is asking for nodes, respond with our info
          broadcastDiscovery();
        }
      }
    }
  }
}

void updateNodeRegistry(String nodeId, String deviceName, String stationIP, String apIP, bool meshConnected) {
  // Remove existing entry for this node
  nodeRegistry.erase(
    std::remove_if(nodeRegistry.begin(), nodeRegistry.end(),
      [&nodeId](const DiscoveredNode& node) { return node.nodeId == nodeId; }),
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
  
  // Limit registry size
  if (nodeRegistry.size() > 100) {
    nodeRegistry.erase(nodeRegistry.begin());
  }
}

void cleanupNodeRegistry() {
  unsigned long currentTime = millis();
  unsigned long maxAge = 300000; // 5 minutes
  
  nodeRegistry.erase(
    std::remove_if(nodeRegistry.begin(), nodeRegistry.end(),
      [currentTime, maxAge](const DiscoveredNode& node) { 
        return (currentTime - node.lastSeen) > maxAge; 
      }),
    nodeRegistry.end()
  );
}

void cleanupDisconnectedNodes() {
  // Get current mesh node list
  std::list<uint32_t> meshNodes = mesh.getNodeList();
  std::set<String> connectedNodeIds;
  
  // Convert mesh node IDs to strings for comparison
  for (auto nodeId : meshNodes) {
    connectedNodeIds.insert(String(nodeId));
  }
  
  // Always include local node as connected
  connectedNodeIds.insert(currentData.nodeId);
  
  // Remove nodes from receivedData that are no longer in mesh
  auto dataIt = receivedData.begin();
  while (dataIt != receivedData.end()) {
    if (connectedNodeIds.find(dataIt->nodeId) == connectedNodeIds.end()) {
      Serial.println("🧹 Removing disconnected node from data: " + dataIt->deviceName + " (" + dataIt->nodeId + ")");
      dataIt = receivedData.erase(dataIt);
    } else {
      ++dataIt;
    }
  }
  
  // Update mesh connectivity status in node registry
  for (auto& regNode : nodeRegistry) {
    bool wasConnected = regNode.meshConnected;
    regNode.meshConnected = (connectedNodeIds.find(regNode.nodeId) != connectedNodeIds.end());
    
    if (wasConnected && !regNode.meshConnected) {
      Serial.println("🔄 Node disconnected from mesh: " + regNode.deviceName + " (" + regNode.nodeId + ")");
    } else if (!wasConnected && regNode.meshConnected) {
      Serial.println("🔄 Node reconnected to mesh: " + regNode.deviceName + " (" + regNode.nodeId + ")");
      regNode.lastSeen = millis(); // Update last seen time for reconnected nodes
    }
  }
  
  Serial.println("🔍 Cleanup complete - Active mesh nodes: " + String(connectedNodeIds.size()) + ", Data nodes: " + String(receivedData.size()));
}

void cleanupRelayRequests() {
  unsigned long currentTime = millis();
  unsigned long maxAge = 30000; // 30 seconds timeout for relay requests
  
  // Clean up old pending relay requests
  auto pendingIt = pendingRelayRequests.begin();
  while (pendingIt != pendingRelayRequests.end()) {
    if ((currentTime - pendingIt->second) > maxAge) {
      Serial.println("🧹 Cleaning up expired relay request: " + pendingIt->first);
      pendingIt = pendingRelayRequests.erase(pendingIt);
    } else {
      ++pendingIt;
    }
  }
  
  // Clean up old relay responses
  auto responseIt = relayResponses.begin();
  while (responseIt != relayResponses.end()) {
    // Remove responses that don't have corresponding pending requests
    if (pendingRelayRequests.find(responseIt->first) == pendingRelayRequests.end()) {
      Serial.println("🧹 Cleaning up orphaned relay response: " + responseIt->first);
      responseIt = relayResponses.erase(responseIt);
    } else {
      ++responseIt;
    }
  }
  
  // Clean up old processed requests to prevent infinite memory growth
  auto processedIt = processedRequests.begin();
  while (processedIt != processedRequests.end()) {
    if ((currentTime - processedIt->second) > maxAge) {
      Serial.println("🧹 Cleaning up old processed request: " + processedIt->first);
      processedIt = processedRequests.erase(processedIt);
    } else {
      ++processedIt;
    }
  }
  
  // Log current status
  if (pendingRelayRequests.size() > 0 || relayResponses.size() > 0 || processedRequests.size() > 0) {
    Serial.println("📊 Relay cleanup: " + String(pendingRelayRequests.size()) + 
                   " pending, " + String(relayResponses.size()) + " responses, " +
                   String(processedRequests.size()) + " processed");
  }
}

// HTTP server setup - display data from all nodes
void setupHTTP() {
  Serial.println("🔧 Setting up HTTP server...");
  
  // Serve minimal sensor data page with all nodes' data
  server.on("/", HTTP_GET, [](){
    String html = "<!DOCTYPE html><html><head><title>All Nodes - SmartAgriMesh</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
    html += "<style>body{font-family:Arial;margin:20px;background:#f5f5f5;text-align:center;}";
    html += ".node{padding:15px;margin:10px;border:1px solid #ccc;background:#fff;}";
    html += ".reading{padding:5px;}</style></head><body><h1>🌱 SmartAgriMesh - All Nodes</h1>";
    
    // Add local node data
    html += "<div class='node'><h2>Local Node: " + String(currentData.nodeId) + " (" + deviceName + ")</h2>";
    html += "<div class='reading'>📍 Station IP: " + WiFi.localIP().toString() + "</div>";
    html += "<div class='reading'>📡 AP IP: " + WiFi.softAPIP().toString() + "</div>";
    html += "<div class='reading'>🌡️ Temperature: " + String(currentData.temperature) + "°C</div>";
    html += "<div class='reading'>💧 Humidity: " + String(currentData.humidity) + "%</div>";
    html += "<div class='reading'>🌱 Soil Moisture: " + String(currentData.soilMoisture) + "%</div>";
    html += "<div class='reading'>👁️ Motion: " + String(currentData.motionDetected ? "Detected" : "Clear") + "</div>";
    html += "<div class='reading'>📏 Distance: " + String(currentData.distance) + "cm</div>";
    html += "<div class='reading'>🔊 Buzzer: " + String(currentData.buzzerActive ? "On" : "Off") + "</div>";
    html += "</div>";
    
    // Add received data from other nodes
    for (const auto& data : receivedData) {
      if (data.nodeId != currentData.nodeId) { // Avoid duplicating local data
        html += "<div class='node'><h2>Node: " + data.nodeId + " (" + data.deviceName + ")</h2>";
        html += "<div class='reading'>🌐 Station IP: " + data.stationIP + "</div>";
        html += "<div class='reading'>📡 AP IP: " + data.apIP + "</div>";
        html += "<div class='reading'>🌡️ Temperature: " + String(data.temperature) + "°C</div>";
        html += "<div class='reading'>💧 Humidity: " + String(data.humidity) + "%</div>";
        html += "<div class='reading'>🌱 Soil Moisture: " + String(data.soilMoisture) + "%</div>";
        html += "<div class='reading'>👁️ Motion: " + String(data.motionDetected ? "Detected" : "Clear") + "</div>";
        html += "<div class='reading'>📏 Distance: " + String(data.distance) + "cm</div>";
        html += "<div class='reading'>🔊 Buzzer: " + String(data.buzzerActive ? "On" : "Off") + "</div>";
        html += "</div>";
      }
    }
    
    // Add registry-only nodes
    for (const auto& regNode : nodeRegistry) {
      if (regNode.nodeId != currentData.nodeId) {
        bool alreadyShown = false;
        for (const auto& data : receivedData) {
          if (data.nodeId == regNode.nodeId) {
            alreadyShown = true;
            break;
          }
        }
        
        if (!alreadyShown) {
          html += "<div class='node'><h2>Registry Node: " + regNode.nodeId + " (" + regNode.deviceName + ")</h2>";
          html += "<div class='reading'>🌐 Station IP: " + regNode.stationIP + "</div>";
          html += "<div class='reading'>📡 AP IP: " + regNode.apIP + "</div>";
          html += "<div class='reading'>📶 Status: " + String(regNode.meshConnected ? "Mesh Connected" : "UDP Discovery") + "</div>";
          html += "</div>";
        }
      }
    }
    
    html += "</body></html>";
    server.send(200, "text/html", html);
  });
  Serial.println("  ✅ Root endpoint configured");

  // API endpoint for device information - main endpoint for device discovery
  server.on("/api/device/info", HTTP_GET, [](){
    String clientIP = server.client().remoteIP().toString();
    bool crossSubnet = _isDifferentSubnet(clientIP);
    
    Serial.println("🔍 DEBUG - /api/device/info accessed from: " + clientIP);
    Serial.println("🔍 DEBUG - Cross-subnet request: " + String(crossSubnet));
    Serial.println("🔍 DEBUG - Node ID: " + currentData.nodeId + ", Device: " + deviceName);
    Serial.println("🔍 DEBUG - Our IPs - Station: " + WiFi.localIP().toString() + ", AP: " + WiFi.softAPIP().toString());
    Serial.println("🔍 DEBUG - Subnet info: " + _getSubnetInfo());
    
    DynamicJsonDocument doc(1024);
    doc["deviceId"] = currentData.nodeId;
    doc["deviceName"] = deviceName;
    doc["stationIP"] = WiFi.localIP().toString();
    doc["apIP"] = WiFi.softAPIP().toString();
    doc["temperature"] = currentData.temperature;
    doc["humidity"] = currentData.humidity;
    doc["soilMoisture"] = currentData.soilMoisture;
    doc["motionDetected"] = currentData.motionDetected;
    doc["distance"] = currentData.distance;
    doc["buzzerActive"] = currentData.buzzerActive;
    doc["timestamp"] = currentData.timestamp;
    doc["meshNodes"] = mesh.getNodeList().size();
    doc["registryNodes"] = nodeRegistry.size();
    
    String response;
    serializeJson(doc, response);
    Serial.println("🔍 DEBUG - Sending response (" + String(response.length()) + " bytes): " + response.substring(0, 100) + "...");
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
    Serial.println("🔍 DEBUG - Response sent successfully to " + clientIP + (crossSubnet ? " (cross-subnet)" : " (same subnet)"));
  });
  Serial.println("  ✅ Device info endpoint configured");

  // Discovery endpoint for device scanning
  server.on("/discover", HTTP_GET, [](){
    DynamicJsonDocument doc(512);
    doc["type"] = "SmartAgriDevice";
    doc["deviceId"] = currentData.nodeId;
    doc["deviceName"] = deviceName;
    doc["version"] = "v2.2.0";
    doc["endpoints"] = "HTTP and CoAP available";
    doc["meshSSID"] = MESH_PREFIX;
    doc["localIP"] = WiFi.localIP().toString();
    doc["apIP"] = WiFi.softAPIP().toString();
    doc["meshNodes"] = mesh.getNodeList().size();
    doc["discoveryMethods"] = "mesh,udp,broadcast";
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });
  Serial.println("  ✅ Discovery endpoint configured");

  // Enhanced mesh nodes endpoint with registry data
  server.on("/api/mesh/nodes", HTTP_GET, [](){
    cleanupNodeRegistry(); // Clean old entries first
    cleanupDisconnectedNodes(); // Clean disconnected mesh nodes
    
    DynamicJsonDocument doc(4096);
    JsonArray nodes = doc.createNestedArray("nodes");
    
    // Get current mesh node list for real-time connectivity check
    std::list<uint32_t> meshNodes = mesh.getNodeList();
    std::set<String> connectedNodeIds;
    for (auto nodeId : meshNodes) {
      connectedNodeIds.insert(String(nodeId));
    }
    connectedNodeIds.insert(currentData.nodeId); // Always include local node
    
    // Add local node
    JsonObject localNode = nodes.createNestedObject();
    localNode["nodeId"] = currentData.nodeId;
    localNode["deviceName"] = deviceName;
    String localStationIP = WiFi.localIP().toString();
    String localApIP = WiFi.softAPIP().toString();
    localNode["stationIP"] = localStationIP;
    localNode["apIP"] = localApIP;
    localNode["ipAddress"] = (localStationIP != "0.0.0.0" && localStationIP.length() > 0) ? localStationIP : localApIP;
    localNode["isLocal"] = true;
    localNode["meshConnected"] = true;
    localNode["lastSeen"] = currentData.timestamp / 1000;
    localNode["discoveryMethod"] = "local";
    
    // Add nodes from mesh data (receivedData)
    for (const auto& data : receivedData) {
      if (data.nodeId != currentData.nodeId) {
        JsonObject node = nodes.createNestedObject();
        node["nodeId"] = data.nodeId;
        node["deviceName"] = data.deviceName;
        String stationIP = (data.stationIP.length() > 0) ? data.stationIP : "0.0.0.0";
        String apIP = (data.apIP.length() > 0) ? data.apIP : "0.0.0.0";
        node["stationIP"] = stationIP;
        node["apIP"] = apIP;
        node["ipAddress"] = (stationIP != "0.0.0.0" && stationIP.length() > 7) ? stationIP : apIP;
        node["isLocal"] = false;
        // Double-check mesh connectivity in real-time
        node["meshConnected"] = (connectedNodeIds.find(data.nodeId) != connectedNodeIds.end());
        node["lastSeen"] = data.timestamp / 1000;
        node["discoveryMethod"] = "mesh";
        node["discoveryMethod"] = "mesh";
      }
    }
    
    // Add nodes from UDP discovery registry (that might not be mesh-connected)
    for (const auto& regNode : nodeRegistry) {
      if (regNode.nodeId != currentData.nodeId) {
        // Check if this node is already added from mesh data
        bool alreadyAdded = false;
        for (const auto& data : receivedData) {
          if (data.nodeId == regNode.nodeId) {
            alreadyAdded = true;
            break;
          }
        }
        
        if (!alreadyAdded) {
          JsonObject node = nodes.createNestedObject();
          node["nodeId"] = regNode.nodeId;
          node["deviceName"] = regNode.deviceName;
          node["stationIP"] = regNode.stationIP;
          node["apIP"] = regNode.apIP;
          node["ipAddress"] = (regNode.stationIP != "0.0.0.0" && regNode.stationIP.length() > 7) ? regNode.stationIP : regNode.apIP;
          node["isLocal"] = false;
          // Use real-time mesh connectivity check for registry nodes
          bool realTimeMeshConnected = (connectedNodeIds.find(regNode.nodeId) != connectedNodeIds.end());
          node["meshConnected"] = realTimeMeshConnected;
          node["lastSeen"] = regNode.lastSeen / 1000;
          node["discoveryMethod"] = realTimeMeshConnected ? "mesh" : "udp";
        }
      }
    }
    
    doc["totalNodes"] = nodes.size();
    doc["meshSSID"] = MESH_PREFIX;
    doc["meshPassword"] = "****";
    doc["localNodeId"] = currentData.nodeId;
    doc["connectedMeshPeers"] = mesh.getNodeList().size();
    doc["registryNodes"] = nodeRegistry.size();
    doc["discoveryMethods"] = "mesh,udp,broadcast";
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });
  Serial.println("  ✅ Mesh nodes endpoint configured");

  // Trigger discovery endpoint
  server.on("/api/discover/trigger", HTTP_POST, [](){
    broadcastDiscovery();
    
    DynamicJsonDocument doc(256);
    doc["status"] = "Discovery broadcast sent";
    doc["timestamp"] = millis();
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });
  Serial.println("  ✅ Discovery trigger endpoint configured");
  Serial.println("  🔧 Setting up relay endpoints...");

  // Relay endpoint - Control buzzer on remote node
  server.on("/api/relay/buzzer", HTTP_POST, [](){
    if (!server.hasArg("plain")) {
      server.send(400, "application/json", "{\"error\":\"No body\"}");
      return;
    }
    
    String body = server.arg("plain");
    DynamicJsonDocument requestDoc(512);
    
    if (deserializeJson(requestDoc, body) != DeserializationError::Ok) {
      server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
      return;
    }
    
    if (!requestDoc.containsKey("nodeId") || !requestDoc.containsKey("action")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId or action\"}");
      return;
    }
    
    String targetNodeId = requestDoc["nodeId"];
    String action = requestDoc["action"]; // "on", "off", or "toggle"
    String requestId = "buzzer_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/control/buzzer";
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    relayDoc["postData"] = body;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 5 seconds)
    unsigned long startTime = millis();
    while (millis() - startTime < 5000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // Relay endpoint - Get data from remote node
  server.on("/api/relay/data", HTTP_GET, [](){
    if (!server.hasArg("nodeId")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId parameter\"}");
      return;
    }
    
    String targetNodeId = server.arg("nodeId");
    String requestId = "data_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/device/info";
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 5 seconds)
    unsigned long startTime = millis();
    while (millis() - startTime < 5000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // Relay endpoint - Download historical data from remote node
  server.on("/api/relay/download", HTTP_GET, [](){
    if (!server.hasArg("nodeId")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId parameter\"}");
      return;
    }
    
    String targetNodeId = server.arg("nodeId");
    String requestId = "download_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/data/history";
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 10 seconds for larger data)
    unsigned long startTime = millis();
    while (millis() - startTime < 10000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // Relay endpoint - Get available SD card files from remote node
  server.on("/api/relay/sdcard/files", HTTP_GET, [](){
    if (!server.hasArg("nodeId")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId parameter\"}");
      return;
    }
    
    String targetNodeId = server.arg("nodeId");
    String requestId = "files_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/sdcard/files";
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 5 seconds)
    unsigned long startTime = millis();
    while (millis() - startTime < 5000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // Relay endpoint - Download specific SD card file from remote node
  server.on("/api/relay/sdcard/download", HTTP_GET, [](){
    if (!server.hasArg("nodeId") || !server.hasArg("file")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId or file parameter\"}");
      return;
    }
    
    String targetNodeId = server.arg("nodeId");
    String fileName = server.arg("file");
    String requestId = "file_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/sdcard/download?file=" + fileName;
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 15 seconds for file downloads)
    unsigned long startTime = millis();
    while (millis() - startTime < 15000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.sendHeader("Content-Type", "application/json");
        server.sendHeader("Content-Disposition", "attachment; filename=" + fileName);
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // Relay endpoint - Get SD card info from remote node
  server.on("/api/relay/sdcard/info", HTTP_GET, [](){
    if (!server.hasArg("nodeId")) {
      server.send(400, "application/json", "{\"error\":\"Missing nodeId parameter\"}");
      return;
    }
    
    String targetNodeId = server.arg("nodeId");
    String requestId = "info_" + String(millis());
    
    // Store pending request
    pendingRelayRequests[requestId] = millis();
    
    // Create relay request
    DynamicJsonDocument relayDoc(512);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = "/api/debug/sdcard"; // Use debug endpoint for info
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = currentData.nodeId;
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    // Wait for response (timeout after 5 seconds)
    unsigned long startTime = millis();
    while (millis() - startTime < 5000) {
      mesh.update();
      if (relayResponses.find(requestId) != relayResponses.end()) {
        String response = relayResponses[requestId];
        relayResponses.erase(requestId);
        pendingRelayRequests.erase(requestId);
        
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.send(200, "application/json", response);
        return;
      }
      delay(10);
    }
    
    // Timeout
    pendingRelayRequests.erase(requestId);
    server.send(408, "application/json", "{\"error\":\"Request timeout\",\"targetNode\":\"" + targetNodeId + "\"}");
  });

  // CORS preflight handling for relay endpoints
  server.on("/api/relay/buzzer", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/relay/data", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/relay/download", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/relay/sdcard/files", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/relay/sdcard/download", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/relay/sdcard/info", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });
  Serial.println("  ✅ All relay endpoints configured");
  Serial.println("  🔧 Setting up local control endpoints...");

  // Local buzzer control endpoint
  server.on("/api/control/buzzer", HTTP_POST, [](){
    if (!server.hasArg("plain")) {
      server.send(400, "application/json", "{\"error\":\"No body\"}");
      return;
    }
    
    String response = handleLocalApiRequest("/api/control/buzzer", server.arg("plain"));
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });

  // Local data history endpoint
  server.on("/api/data/history", HTTP_GET, [](){
    String response = handleLocalApiRequest("/api/data/history");
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });

  // CORS preflight for local endpoints
  server.on("/api/control/buzzer", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/data/history", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });
  Serial.println("  ✅ Local control endpoints configured");
  Serial.println("  🔧 Setting up SD card debug endpoints...");

  // SD Card debug endpoint
  server.on("/api/debug/sdcard", HTTP_GET, [](){
    DynamicJsonDocument doc(1024);
    
    if (SD.cardType() == 0) {
      doc["status"] = "disconnected";
      doc["error"] = "SD card not detected";
    } else {
      doc["status"] = "connected";
      doc["cardType"] = SD.cardType();
      
      uint64_t totalBytes = SD.totalBytes();
      uint64_t usedBytes = SD.usedBytes();
      uint64_t freeBytes = totalBytes - usedBytes;
      
      doc["totalBytes"] = (uint32_t)totalBytes;
      doc["usedBytes"] = (uint32_t)usedBytes;
      doc["freeBytes"] = (uint32_t)freeBytes;
      doc["totalMB"] = (uint32_t)(totalBytes / 1024 / 1024);
      doc["usedMB"] = (uint32_t)(usedBytes / 1024 / 1024);
      doc["freeMB"] = (uint32_t)(freeBytes / 1024 / 1024);
      doc["freePercent"] = (uint32_t)((freeBytes * 100) / totalBytes);
      
      // Count data files
      JsonArray files = doc.createNestedArray("dataFiles");
      File dataDir = SD.open("/data");
      if (dataDir) {
        File entry = dataDir.openNextFile();
        int fileCount = 0;
        uint32_t totalDataSize = 0;
        
        while (entry && fileCount < 20) { // Limit to prevent overflow
          if (!entry.isDirectory()) {
            JsonObject fileInfo = files.createNestedObject();
            fileInfo["name"] = String(entry.name());
            fileInfo["size"] = entry.size();
            totalDataSize += entry.size();
            fileCount++;
          }
          entry.close();
          entry = dataDir.openNextFile();
        }
        dataDir.close();
        
        doc["fileCount"] = fileCount;
        doc["totalDataSize"] = totalDataSize;
      } else {
        doc["fileCount"] = 0;
        doc["error"] = "Cannot access /data directory";
      }
    }
    
    doc["csPin"] = SD_CS_PIN;
    doc["timestamp"] = millis();
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });

  // SD Card test endpoint
  server.on("/api/debug/sdcard/test", HTTP_POST, [](){
    DynamicJsonDocument doc(512);
    doc["timestamp"] = millis();
    
    if (SD.cardType() == 0) {
      doc["status"] = "failed";
      doc["error"] = "SD card not detected";
    } else {
      // Perform write test
      String testFile = "/data/api_test_" + String(millis()) + ".tmp";
      File file = SD.open(testFile, FILE_WRITE);
      
      if (file) {
        String testData = "API test write at " + String(millis());
        file.println(testData);
        file.close();
        
        // Try to read it back
        file = SD.open(testFile, FILE_READ);
        if (file) {
          String readData = file.readString();
          file.close();
          SD.remove(testFile); // Clean up
          
          doc["status"] = "success";
          doc["writeTest"] = "passed";
          doc["readTest"] = "passed";
          doc["testData"] = testData;
          doc["readData"] = readData.substring(0, testData.length()); // Remove newline
        } else {
          doc["status"] = "partial";
          doc["writeTest"] = "passed";
          doc["readTest"] = "failed";
          SD.remove(testFile); // Try to clean up
        }
      } else {
        doc["status"] = "failed";
        doc["writeTest"] = "failed";
        doc["error"] = "Cannot open file for writing";
      }
    }
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });
  Serial.println("  ✅ SD card debug endpoints configured");
  Serial.println("  🔧 Setting up SD card file management endpoints...");

  // SD Card file listing endpoint
  server.on("/api/sdcard/files", HTTP_GET, [](){
    DynamicJsonDocument doc(2048);
    doc["timestamp"] = millis();
    
    if (SD.cardType() == 0) {
      doc["status"] = "error";
      doc["error"] = "SD card not detected";
      doc["files"] = JsonArray();
    } else {
      doc["status"] = "success";
      JsonArray files = doc.createNestedArray("files");
      
      File dataDir = SD.open("/data");
      if (dataDir) {
        File entry = dataDir.openNextFile();
        while (entry) {
          if (!entry.isDirectory() && String(entry.name()).endsWith(".json")) {
            files.add(String(entry.name()));
          }
          entry.close();
          entry = dataDir.openNextFile();
        }
        dataDir.close();
      }
    }
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", response);
  });

  // SD Card file download endpoint
  server.on("/api/sdcard/download", HTTP_GET, [](){
    if (!server.hasArg("file")) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(400, "application/json", "{\"error\":\"No filename provided\"}");
      return;
    }
    
    String fileName = server.arg("file");
    
    // Security check - only allow .json files from /data directory
    if (!fileName.endsWith(".json")) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(400, "application/json", "{\"error\":\"Only JSON files are allowed\"}");
      return;
    }
    
    String filePath = "/data/" + fileName;
    
    // Retry logic for files that might be locked (especially received_*.json)
    int maxRetries = fileName.startsWith("received_") ? 3 : 1;
    File file;
    String content;
    bool success = false;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      file = SD.open(filePath, FILE_READ);
      
      if (file) {
        content = file.readString();
        file.close();
        success = true;
        break;
      } else if (attempt < maxRetries) {
        Serial.println("⏳ File access failed for " + fileName + " (attempt " + String(attempt) + "/" + String(maxRetries) + "), retrying...");
        delay(100); // Small delay to let any write operations complete
      }
    }
    
    if (!success) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(404, "application/json", "{\"error\":\"File not found or locked\"}");
      return;
    }
    
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Content-Type", "application/json");
    server.sendHeader("Content-Disposition", "attachment; filename=" + fileName);
    server.send(200, "application/json", content);
  });

  // SD Card file deletion endpoint
  server.on("/api/sdcard/delete", HTTP_DELETE, [](){
    if (!server.hasArg("file")) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(400, "application/json", "{\"error\":\"No filename provided\"}");
      return;
    }
    
    String fileName = server.arg("file");
    
    // Security check - only allow .json files from /data directory
    if (!fileName.endsWith(".json")) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(400, "application/json", "{\"error\":\"Only JSON files are allowed\"}");
      return;
    }
    
    String filePath = "/data/" + fileName;
    bool success = SD.remove(filePath);
    
    DynamicJsonDocument doc(256);
    doc["success"] = success;
    doc["fileName"] = fileName;
    doc["timestamp"] = millis();
    
    if (success) {
      doc["message"] = "File deleted successfully";
    } else {
      doc["error"] = "Failed to delete file";
    }
    
    String response;
    serializeJson(doc, response);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(success ? 200 : 500, "application/json", response);
  });

  // CORS preflight for SD card endpoints
  server.on("/api/sdcard/files", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/sdcard/download", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  server.on("/api/sdcard/delete", HTTP_OPTIONS, [](){
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "DELETE, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200);
  });

  Serial.println("  ✅ SD card file management endpoints configured");
  Serial.println("  🔧 Setting up debug endpoints...");

  // Debug: Print server status and IP information
  Serial.println("🔍 DEBUG - HTTP Server Status:");
  Serial.println("  - Server listening on port: " + String(HTTP_PORT));
  Serial.println("  - Station IP: " + WiFi.localIP().toString());
  Serial.println("  - AP IP: " + WiFi.softAPIP().toString());
  Serial.println("  - Mesh Node ID: " + String(mesh.getNodeId()));
  Serial.println("  - Device Name: " + deviceName);
  Serial.println("  - Subnet: " + _getSubnetInfo());
  
  // Enhanced debug endpoints for any node
  server.on("/ping", HTTP_GET, []() {
    String clientIP = server.client().remoteIP().toString();
    Serial.println("🔍 DEBUG - Ping endpoint accessed from: " + clientIP);
    Serial.println("🔍 DEBUG - Cross-subnet request: " + String(_isDifferentSubnet(clientIP)));
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "text/plain", "pong from " + deviceName + " (" + String(mesh.getNodeId()) + ")");
  });
  
  server.on("/debug", HTTP_GET, []() {
    String clientIP = server.client().remoteIP().toString();
    Serial.println("🔍 DEBUG - Debug endpoint accessed from: " + clientIP);
    
    String debugInfo = "Node ID: " + String(mesh.getNodeId()) + "\n";
    debugInfo += "Device Name: " + deviceName + "\n";
    debugInfo += "Station IP: " + WiFi.localIP().toString() + "\n";
    debugInfo += "AP IP: " + WiFi.softAPIP().toString() + "\n";
    debugInfo += "HTTP Port: " + String(HTTP_PORT) + "\n";
    debugInfo += "Mesh Peers: " + String(mesh.getNodeList().size()) + "\n";
    debugInfo += "Client IP: " + clientIP + "\n";
    debugInfo += "Cross-subnet: " + String(_isDifferentSubnet(clientIP)) + "\n";
    debugInfo += "Subnet Info: " + _getSubnetInfo() + "\n";
    debugInfo += "WiFi Status: " + String(WiFi.status()) + "\n";
    debugInfo += "AP Status: " + String(WiFi.softAPgetStationNum()) + " clients\n";
    
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "text/plain", debugInfo);
  });
  Serial.println("  ✅ Debug endpoints configured");

  server.begin();
  Serial.println("🌐 HTTP server started on port " + String(HTTP_PORT));
  Serial.println("📍 Access via Station IP: http://" + WiFi.localIP().toString());
  Serial.println("📍 Access via AP IP: http://" + WiFi.softAPIP().toString());
  Serial.println("✅ HTTP server setup complete!");
}

void setupCoAP() {
  coap.start();
  Serial.println("📡 CoAP server started on port " + String(COAP_PORT));
}

// Status display
void displayStatus() {
  Serial.println("\n" + repeatChar('-', 50));
  Serial.println("🌱 " + deviceName + " (" + currentData.nodeId + ") Status");
  Serial.println("📍 Station IP: " + WiFi.localIP().toString());
  Serial.println("📡 AP IP: " + WiFi.softAPIP().toString());
  Serial.println("🔗 Mesh peers: " + String(mesh.getNodeList().size()));
  Serial.println("📊 Data nodes (active): " + String(receivedData.size()));
  Serial.println("📋 Registry nodes (total): " + String(nodeRegistry.size()));
  
  // Show connectivity status breakdown
  int meshConnectedCount = 0;
  int udpOnlyCount = 0;
  for (const auto& regNode : nodeRegistry) {
    if (regNode.meshConnected) meshConnectedCount++;
    else udpOnlyCount++;
  }
  if (nodeRegistry.size() > 0) {
    Serial.println("🔌 Connectivity: " + String(meshConnectedCount) + " mesh + " + String(udpOnlyCount) + " UDP-only");
  }
  
  Serial.println("🌡️ " + String(currentData.temperature) + "°C, 💧 " + String(currentData.humidity) + "%");
  
  // SD Card status in display
  if (SD.cardType() > 0) {
    uint64_t totalBytes = SD.totalBytes();
    uint64_t usedBytes = SD.usedBytes();
    uint32_t freePercent = (uint32_t)(((totalBytes - usedBytes) * 100) / totalBytes);
    Serial.println("💾 SD Card: " + String((uint32_t)(totalBytes/1024/1024)) + "MB (" + String(freePercent) + "% free)");
    
    // Count data files
    File dataDir = SD.open("/data");
    if (dataDir) {
      int fileCount = 0;
      File entry = dataDir.openNextFile();
      while (entry) {
        if (!entry.isDirectory()) fileCount++;
        entry.close();
        entry = dataDir.openNextFile();
      }
      dataDir.close();
      Serial.println("📁 Data files: " + String(fileCount));
    } else {
      Serial.println("📁 Data files: Error reading directory");
    }
  } else {
    Serial.println("💾 SD Card: ❌ Not detected");
  }
  
  Serial.println(repeatChar('-', 50));
}

void checkForDeviceName() {
  static unsigned long startTime = millis();
  static bool nameSet = false;
  
  if (!nameSet && Serial.available()) {
    String newName = Serial.readStringUntil('\n');
    newName.trim();
    
    if (newName.length() > 0 && newName.length() <= 20) {
      deviceName = newName;
      nameSet = true;
      Serial.println("✅ Device name set to: " + deviceName);
      Serial.println("🔄 Broadcasting updated name to mesh...");
      broadcastData();
      taskCheckDeviceName.disable();
    }
  }
  
  if (!nameSet && (millis() - startTime) > 10000) {
    nameSet = true;
    Serial.println("⏰ Using default device name: " + deviceName);
    taskCheckDeviceName.disable();
  }
}

void monitorNetwork() {
  cleanupNodeRegistry();
  cleanupDisconnectedNodes(); // Clean up disconnected mesh nodes
  
  Serial.println("🔍 Network Monitor:");
  Serial.println("  Mesh peers: " + String(mesh.getNodeList().size()));
  Serial.println("  Known data nodes: " + String(receivedData.size()));
  Serial.println("  Registry nodes: " + String(nodeRegistry.size()));
  
  if (nodeRegistry.size() > 0) {
    Serial.println("  Registry details:");
    for (const auto& node : nodeRegistry) {
      String status = node.meshConnected ? "mesh" : "udp";
      Serial.println("    - " + node.deviceName + " (" + node.nodeId + ") [" + status + "] " + node.stationIP);
    }
  }
}

// Relay system implementation
void handleRelayRequest(String targetNodeId, String apiPath, String requestId, String originNodeId, String postData) {
  // Check if this node is the target
  if (targetNodeId == currentData.nodeId) {
    // This node is the target, handle the API request locally
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
    
    Serial.println("   ✅ Handled relay request locally: " + apiPath);
  } else {
    // Forward the request to other nodes
    DynamicJsonDocument relayDoc(1024);
    relayDoc["type"] = "relay_request";
    relayDoc["targetNodeId"] = targetNodeId;
    relayDoc["apiPath"] = apiPath;
    relayDoc["requestId"] = requestId;
    relayDoc["originNodeId"] = originNodeId;
    if (postData.length() > 0) {
      relayDoc["postData"] = postData;
    }
    
    String relayMsg;
    serializeJson(relayDoc, relayMsg);
    mesh.sendBroadcast(relayMsg);
    
    Serial.println("   🔄 Forwarded relay request: " + apiPath + " -> " + targetNodeId);
  }
}

void handleRelayResponse(String requestId, String response) {
  // Store the relay response for retrieval
  relayResponses[requestId] = response;
  
  // Remove from pending requests
  pendingRelayRequests.erase(requestId);
  
  Serial.println("   📥 Stored relay response for request: " + requestId);
}

// Local API request handler
String handleLocalApiRequest(String apiPath) {
  return handleLocalApiRequest(apiPath, "");
}

String handleLocalApiRequest(String apiPath, String postData) {
  DynamicJsonDocument responseDoc(1024);
  
  if (apiPath == "/api/control/buzzer") {
    // Handle buzzer control
    if (postData.length() > 0) {
      DynamicJsonDocument postDoc(256);
      if (deserializeJson(postDoc, postData) == DeserializationError::Ok) {
        String action = postDoc["action"];
        
        if (action == "on") {
          digitalWrite(BUZZER_PIN, HIGH);
          currentData.buzzerActive = true;
          responseDoc["status"] = "Buzzer turned ON";
        } else if (action == "off") {
          digitalWrite(BUZZER_PIN, LOW);
          currentData.buzzerActive = false;
          responseDoc["status"] = "Buzzer turned OFF";
        } else if (action == "toggle") {
          bool newState = !currentData.buzzerActive;
          digitalWrite(BUZZER_PIN, newState ? HIGH : LOW);
          currentData.buzzerActive = newState;
          responseDoc["status"] = newState ? "Buzzer turned ON" : "Buzzer turned OFF";
        } else {
          responseDoc["error"] = "Invalid action. Use 'on', 'off', or 'toggle'";
        }
        
        responseDoc["buzzerActive"] = currentData.buzzerActive;
        responseDoc["nodeId"] = currentData.nodeId;
        responseDoc["deviceName"] = deviceName;
        responseDoc["timestamp"] = millis();
      } else {
        responseDoc["error"] = "Invalid JSON in request body";
      }
    } else {
      responseDoc["error"] = "Missing request body";
    }
  }
  else if (apiPath == "/api/data/history") {
    // Handle historical data request
    responseDoc["nodeId"] = currentData.nodeId;
    responseDoc["deviceName"] = deviceName;
    responseDoc["dataType"] = "historical";
    
    // Try to read historical data from SD card
    JsonArray historyArray = responseDoc.createNestedArray("history");
    
    File file = SD.open("/data/node_" + currentData.nodeId + ".json", FILE_READ);
    if (file) {
      int recordCount = 0;
      String line;
      
      // Read up to last 50 records
      while (file.available() && recordCount < 50) {
        line = file.readStringUntil('\n');
        line.trim();
        
        if (line.length() > 0) {
          DynamicJsonDocument recordDoc(256);
          if (deserializeJson(recordDoc, line) == DeserializationError::Ok) {
            JsonObject record = historyArray.createNestedObject();
            record["temperature"] = recordDoc["temp"];
            record["humidity"] = recordDoc["hum"];
            record["soilMoisture"] = recordDoc["soil"];
            record["motionDetected"] = recordDoc["motion"];
            record["distance"] = recordDoc["dist"];
            record["buzzerActive"] = recordDoc["buzz"];
            record["timestamp"] = recordDoc["time"];
            recordCount++;
          }
        }
      }
      file.close();
      
      responseDoc["recordCount"] = recordCount;
      responseDoc["status"] = "Historical data retrieved";
    } else {
      responseDoc["recordCount"] = 0;
      responseDoc["status"] = "No historical data available";
      responseDoc["error"] = "Could not open data file";
    }
    
    // Also include current live data
    JsonObject currentRecord = responseDoc.createNestedObject("current");
    currentRecord["temperature"] = currentData.temperature;
    currentRecord["humidity"] = currentData.humidity;
    currentRecord["soilMoisture"] = currentData.soilMoisture;
    currentRecord["motionDetected"] = currentData.motionDetected;
    currentRecord["distance"] = currentData.distance;
    currentRecord["buzzerActive"] = currentData.buzzerActive;
    currentRecord["timestamp"] = currentData.timestamp;
  }
  else if (apiPath == "/api/device/info") {
    responseDoc["deviceId"] = currentData.nodeId;
    responseDoc["deviceName"] = deviceName;
    responseDoc["stationIP"] = WiFi.localIP().toString();
    responseDoc["apIP"] = WiFi.softAPIP().toString();
    responseDoc["temperature"] = currentData.temperature;
    responseDoc["humidity"] = currentData.humidity;
    responseDoc["soilMoisture"] = currentData.soilMoisture;
    responseDoc["motionDetected"] = currentData.motionDetected;
    responseDoc["distance"] = currentData.distance;
    responseDoc["buzzerActive"] = currentData.buzzerActive;
    responseDoc["timestamp"] = currentData.timestamp;
    responseDoc["meshNodes"] = mesh.getNodeList().size();
    responseDoc["registryNodes"] = nodeRegistry.size();
  } 
  else if (apiPath == "/discover") {
    responseDoc["type"] = "SmartAgriDevice";
    responseDoc["deviceId"] = currentData.nodeId;
    responseDoc["deviceName"] = deviceName;
    responseDoc["version"] = "v2.2.0";
    responseDoc["endpoints"] = "HTTP and CoAP available";
    responseDoc["meshSSID"] = MESH_PREFIX;
    responseDoc["localIP"] = WiFi.localIP().toString();
    responseDoc["apIP"] = WiFi.softAPIP().toString();
    responseDoc["meshNodes"] = mesh.getNodeList().size();
    responseDoc["discoveryMethods"] = "mesh,udp,broadcast";
  }
  else if (apiPath == "/api/mesh/nodes") {
    cleanupNodeRegistry();
    
    JsonArray nodes = responseDoc.createNestedArray("nodes");
    
    // Add local node
    JsonObject localNode = nodes.createNestedObject();
    localNode["nodeId"] = currentData.nodeId;
    localNode["deviceName"] = deviceName;
    String localStationIP = WiFi.localIP().toString();
    String localApIP = WiFi.softAPIP().toString();
    localNode["stationIP"] = localStationIP;
    localNode["apIP"] = localApIP;
    localNode["ipAddress"] = (localStationIP != "0.0.0.0" && localStationIP.length() > 0) ? localStationIP : localApIP;
    localNode["isLocal"] = true;
    localNode["meshConnected"] = true;
    localNode["lastSeen"] = currentData.timestamp / 1000;
    localNode["discoveryMethod"] = "local";
    
    // Add nodes from mesh data
    for (const auto& data : receivedData) {
      if (data.nodeId != currentData.nodeId) {
        JsonObject node = nodes.createNestedObject();
        node["nodeId"] = data.nodeId;
        node["deviceName"] = data.deviceName;
        String stationIP = (data.stationIP.length() > 0) ? data.stationIP : "0.0.0.0";
        String apIP = (data.apIP.length() > 0) ? data.apIP : "0.0.0.0";
        node["stationIP"] = stationIP;
        node["apIP"] = apIP;
        node["ipAddress"] = (stationIP != "0.0.0.0" && stationIP.length() > 7) ? stationIP : apIP;
        node["isLocal"] = false;
        node["meshConnected"] = true;
        node["lastSeen"] = data.timestamp / 1000;
        node["discoveryMethod"] = "mesh";
      }
    }
    
    // Add nodes from registry
    for (const auto& regNode : nodeRegistry) {
      if (regNode.nodeId != currentData.nodeId) {
        bool alreadyAdded = false;
        for (const auto& data : receivedData) {
          if (data.nodeId == regNode.nodeId) {
            alreadyAdded = true;
            break;
          }
        }
        
        if (!alreadyAdded) {
          JsonObject node = nodes.createNestedObject();
          node["nodeId"] = regNode.nodeId;
          node["deviceName"] = regNode.deviceName;
          node["stationIP"] = regNode.stationIP;
          node["apIP"] = regNode.apIP;
          node["ipAddress"] = (regNode.stationIP != "0.0.0.0" && regNode.stationIP.length() > 7) ? regNode.stationIP : regNode.apIP;
          node["isLocal"] = false;
          node["meshConnected"] = regNode.meshConnected;
          node["lastSeen"] = regNode.lastSeen / 1000;
          node["discoveryMethod"] = regNode.meshConnected ? "mesh" : "udp";
        }
      }
    }
    
    responseDoc["totalNodes"] = nodes.size();
    responseDoc["meshSSID"] = MESH_PREFIX;
    responseDoc["localNodeId"] = currentData.nodeId;
    responseDoc["connectedMeshPeers"] = mesh.getNodeList().size();
    responseDoc["registryNodes"] = nodeRegistry.size();
    responseDoc["discoveryMethods"] = "mesh,udp,broadcast";
  }
  else if (apiPath == "/api/discover/trigger") {
    broadcastDiscovery();
    responseDoc["status"] = "Discovery broadcast sent";
    responseDoc["timestamp"] = millis();
  }
  else if (apiPath == "/api/sdcard/files") {
    // Handle SD card file listing
    responseDoc["timestamp"] = millis();
    
    if (SD.cardType() == 0) {
      responseDoc["status"] = "error";
      responseDoc["error"] = "SD card not detected";
      responseDoc["files"] = JsonArray();
    } else {
      responseDoc["status"] = "success";
      JsonArray files = responseDoc.createNestedArray("files");
      
      File dataDir = SD.open("/data");
      if (dataDir) {
        File entry = dataDir.openNextFile();
        while (entry) {
          if (!entry.isDirectory() && String(entry.name()).endsWith(".json")) {
            files.add(String(entry.name()));
          }
          entry.close();
          entry = dataDir.openNextFile();
        }
        dataDir.close();
      }
    }
  }
  else if (apiPath.startsWith("/api/sdcard/download?file=")) {
    // Handle SD card file download
    String fileName = apiPath.substring(apiPath.indexOf("file=") + 5);
    
    // Security check - only allow .json files from /data directory
    if (!fileName.endsWith(".json")) {
      responseDoc["error"] = "Only JSON files are allowed";
      responseDoc["status"] = "error";
    } else {
      String filePath = "/data/" + fileName;
      
      // Retry logic for files that might be locked (especially received_*.json)
      int maxRetries = fileName.startsWith("received_") ? 3 : 1;
      File file;
      String content;
      bool success = false;
      
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        file = SD.open(filePath, FILE_READ);
        
        if (file) {
          content = file.readString();
          file.close();
          success = true;
          break;
        } else if (attempt < maxRetries) {
          Serial.println("⏳ Relay file access failed for " + fileName + " (attempt " + String(attempt) + "/" + String(maxRetries) + "), retrying...");
          delay(100); // Small delay to let any write operations complete
        }
      }
      
      if (!success) {
        responseDoc["error"] = "File not found or locked";
        responseDoc["status"] = "error";
      } else {
        // Return raw file content for SD card downloads
        return content;
      }
    }
  }
  else if (apiPath == "/api/debug/sdcard") {
    // Handle SD card debug/info request
    responseDoc["timestamp"] = millis();
    
    if (SD.cardType() == 0) {
      responseDoc["status"] = "disconnected";
      responseDoc["error"] = "SD card not detected";
    } else {
      responseDoc["status"] = "connected";
      responseDoc["cardType"] = SD.cardType();
      
      uint64_t totalBytes = SD.totalBytes();
      uint64_t usedBytes = SD.usedBytes();
      uint64_t freeBytes = totalBytes - usedBytes;
      
      responseDoc["totalBytes"] = (uint32_t)totalBytes;
      responseDoc["usedBytes"] = (uint32_t)usedBytes;
      responseDoc["freeBytes"] = (uint32_t)freeBytes;
      responseDoc["totalMB"] = (uint32_t)(totalBytes / 1024 / 1024);
      responseDoc["usedMB"] = (uint32_t)(usedBytes / 1024 / 1024);
      responseDoc["freeMB"] = (uint32_t)(freeBytes / 1024 / 1024);
      responseDoc["freePercent"] = (uint32_t)((freeBytes * 100) / totalBytes);
      
      // Count data files
      JsonArray files = responseDoc.createNestedArray("dataFiles");
      File dataDir = SD.open("/data");
      if (dataDir) {
        File entry = dataDir.openNextFile();
        int fileCount = 0;
        uint32_t totalDataSize = 0;
        
        while (entry && fileCount < 20) { // Limit to prevent overflow
          if (!entry.isDirectory()) {
            JsonObject fileInfo = files.createNestedObject();
            fileInfo["name"] = String(entry.name());
            fileInfo["size"] = entry.size();
            totalDataSize += entry.size();
            fileCount++;
          }
          entry.close();
          entry = dataDir.openNextFile();
        }
        dataDir.close();
        
        responseDoc["fileCount"] = fileCount;
        responseDoc["totalDataSize"] = totalDataSize;
      } else {
        responseDoc["fileCount"] = 0;
        responseDoc["error"] = "Cannot access /data directory";
      }
    }
    
    responseDoc["csPin"] = SD_CS_PIN;
  }
  else {
    // Unknown API path
    responseDoc["error"] = "Unknown API path: " + apiPath;
    responseDoc["status"] = "error";
  }
  
  String response;
  serializeJson(responseDoc, response);
  return response;
}

// SD Card status monitoring function
void checkSDCardStatus() {
  Serial.println("🔍 SD Card Status Check:");
  
  // Check if SD card is still accessible
  if (SD.cardType() == 0) {
    Serial.println("  ❌ SD card not detected!");
    Serial.println("  - Possible issues:");
    Serial.println("    * Loose connection on CS pin " + String(SD_CS_PIN));
    Serial.println("    * Power supply insufficient");
    Serial.println("    * SD card removed or corrupted");
    Serial.println("  - Attempting re-initialization...");
    
    // Try to re-initialize
    if (SD.begin(SD_CS_PIN)) {
      Serial.println("  ✅ SD card re-initialized successfully!");
    } else {
      Serial.println("  ❌ SD card re-initialization failed");
      return;
    }
  }
  
  // Get card information
  uint64_t totalBytes = SD.totalBytes();
  uint64_t usedBytes = SD.usedBytes();
  uint64_t freeBytes = totalBytes - usedBytes;
  
  Serial.println("  ✅ SD card is accessible");
  Serial.println("  - Card Type: " + String(SD.cardType()));
  Serial.println("  - Total Space: " + String((uint32_t)(totalBytes/1024/1024)) + " MB");
  Serial.println("  - Used Space: " + String((uint32_t)(usedBytes/1024/1024)) + " MB");
  Serial.println("  - Free Space: " + String((uint32_t)(freeBytes/1024/1024)) + " MB");
  Serial.println("  - Free %: " + String((uint32_t)((freeBytes * 100) / totalBytes)) + "%");
  
  // Check if data directory exists
  if (!SD.exists("/data")) {
    Serial.println("  ⚠️ /data directory missing - creating...");
    if (SD.mkdir("/data")) {
      Serial.println("  ✅ /data directory created");
    } else {
      Serial.println("  ❌ Failed to create /data directory");
    }
  }
  
  // List data files and their sizes
  File dataDir = SD.open("/data");
  if (dataDir) {
    Serial.println("  📁 Data directory contents:");
    File entry = dataDir.openNextFile();
    int fileCount = 0;
    uint32_t totalDataSize = 0;
    
    while (entry) {
      if (!entry.isDirectory()) {
        uint32_t fileSize = entry.size();
        totalDataSize += fileSize;
        fileCount++;
        Serial.println("    - " + String(entry.name()) + " (" + String(fileSize) + " bytes)");
      }
      entry.close();
      entry = dataDir.openNextFile();
    }
    dataDir.close();
    
    Serial.println("  📊 Total: " + String(fileCount) + " files, " + String(totalDataSize) + " bytes");
    
    if (fileCount == 0) {
      Serial.println("  ⚠️ No data files found - check if saving is working");
    }
  } else {
    Serial.println("  ❌ Cannot open /data directory");
  }
  
  // Test write capability
  String testFile = "/data/health_check_" + String(millis()) + ".tmp";
  File file = SD.open(testFile, FILE_WRITE);
  if (file) {
    file.println("SD health check at " + String(millis()));
    file.close();
    
    // Try to read it back
    file = SD.open(testFile, FILE_READ);
    if (file) {
      String content = file.readString();
      file.close();
      SD.remove(testFile); // Clean up test file
      Serial.println("  ✅ SD card read/write test passed");
    } else {
      Serial.println("  ❌ SD card read test failed");
    }
  } else {
    Serial.println("  ❌ SD card write test failed");
    Serial.println("  - Check if card is write-protected");
    Serial.println("  - Check if card is full");
  }
  
  // Low space warning
  if (freeBytes < (10 * 1024 * 1024)) { // Less than 10MB free
    Serial.println("  ⚠️ WARNING: Low disk space (" + String((uint32_t)(freeBytes/1024/1024)) + " MB free)");
  }
}