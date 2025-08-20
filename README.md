# Smart Agriculture IoT Management App

A comprehensive Flutter application for managing ESP32-based Smart Agriculture mesh networks (SmartAgriMesh) with real-time sensor monitoring, data visualization, and AI analytics.

## 📚 Documentation

- **[Arduino IoT System Documentation](ARDUINO_IOT_DOCUMENTATION.md)** - Detailed technical documentation of the ESP32 Arduino code, IoT protocols (HTTP, CoAP, UDP), relay system, and mesh networking architecture
- **[Flutter App Documentation](FLUTTER_APP_DOCUMENTATION.md)** - Comprehensive guide to the Flutter application functionality, architecture, state management, and features

## Features

### Network Management
- **Automatic Mesh Network Discovery**: Connects to SmartAgriMesh WiFi and auto-discovers ESP32 nodes
- **Cross-Subnet Communication**: Advanced relay functionality for nodes across different network subnets
- **Real-time Node Status**: Live monitoring of node connectivity and mesh network health  
- **Network Diagnostics**: WiFi status, mesh topology visualization, and connection troubleshooting
- **UDP Discovery Broadcasting**: Cross-network device discovery using UDP broadcast packets

### 📊 Sensor Data Monitoring
- **Live Data Streaming**: Real-time sensor readings from all connected nodes with automatic updates
- **Multi-Sensor Support**: Temperature, humidity, soil moisture, motion detection, distance measurement
- **Historical Data Analysis**: Interactive charts and trend analysis for historical sensor data
- **Data Export**: CSV export and local storage capabilities with Firebase cloud sync
- **Intelligent Automation**: Built-in sensor logic for automated responses (e.g., motion-triggered alarms)

### 💾 SD Card Management
- **Remote File Access**: Browse, download, and manage data files from node SD cards via HTTP API
- **Storage Health Monitoring**: Real-time SD card capacity, usage, file counts, and health status
- **Bulk Data Download**: Download historical sensor logs from multiple nodes simultaneously
- **File Management**: Organize, delete, and manage stored sensor data with automatic cleanup
- **Data Integrity**: SD card health checks, re-initialization, and error recovery

### 🤖 AI Analytics Panel
- **Smart Insights**: AI-powered analysis of sensor patterns and trends
- **Predictive Alerts**: Early warning system for potential issues
- **Recommendations**: Actionable suggestions for optimal agricultural conditions
- **Custom Reports**: Detailed analysis reports with visualizations

### ☁️ Firebase Integration
- **User Authentication**: Secure email/password authentication
- **Cloud Storage**: Automatic data backup to Firebase Firestore
- **Offline Support**: Local data storage with cloud synchronization
- **Multi-Device Sync**: Access data across multiple devices

### 🎨 Modern UI/UX
- **Material Design 3**: Clean, modern interface following Material 3 guidelines
- **Dark/Light Theme**: Adaptive theming support
- **Responsive Design**: Works on phones, tablets, and desktop
- **Interactive Charts**: Beautiful data visualizations with FL Chart

## System Architecture

### ESP32 Mesh Network
- **Mesh Technology**: Uses painlessMesh library for self-healing mesh networks
- **Communication Protocols**: HTTP REST APIs, CoAP, and UDP for multi-protocol communication
- **Relay System**: Intelligent message forwarding between mesh nodes for cross-subnet communication
- **Sensor Integration**: DHT11 (temperature/humidity), soil moisture, PIR motion, ultrasonic distance
- **Data Storage**: Local SD card storage with automatic logging and health monitoring

📖 **[Read detailed Arduino/ESP32 documentation →](ARDUINO_IOT_DOCUMENTATION.md)**

### Flutter Application  
- **State Management**: Riverpod for reactive state management and dependency injection
- **Navigation**: GoRouter for type-safe navigation with deep linking
- **Network Layer**: Multi-protocol HTTP/UDP client with automatic retry and error handling
- **Local Storage**: Firestore integration for offline-first data persistence
- **Cross-Platform**: Supports Android, Windows

📖 **[Read detailed Flutter app documentation →](FLUTTER_APP_DOCUMENTATION.md)**

## Quick Start

### Prerequisites
- Flutter SDK (latest stable version)
- Android/iOS development environment
- ESP32 devices with SmartAgri firmware
- Firebase project (optional, for cloud features)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd smart_agri_project
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase** (Optional)
   - Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Update Firebase configuration in `lib/firebase_options.dart`

4. **Run the app**
   ```bash
   flutter run
   ```

### ESP32 Setup

1. **Flash the Arduino firmware**
   - Upload `arduino_code/smart_agri_enhanced.ino` to your ESP32 devices
   - Install required libraries: painlessMesh, ArduinoJson, DHT, SD, coap-simple

2. **Connect to mesh network**
   - WiFi SSID: `SmartAgriMesh`
   - Password: `agrimesh2024`

3. **Verify connectivity**
   - Check serial monitor for node discovery
   - Test HTTP endpoints (e.g., `http://node-ip/discover`)

## Usage Guide

### Initial Setup
1. **Connect to WiFi**: Connect your device to the SmartAgriMesh network
2. **Create Account**: Register with email/password or sign in
3. **Discover Nodes**: App automatically discovers ESP32 nodes on the network
4. **Verify Sensors**: Check that sensor data is being received

### Daily Operations
1. **Monitor Dashboard**: View real-time sensor readings and quick stats
2. **Check Node Status**: Monitor node connectivity and health
3. **Review Analytics**: Check AI insights and recommendations
4. **Download Data**: Export historical data for analysis

### Advanced Features
1. **SD Card Management**: Access stored data files on ESP32 nodes
2. **Cross-Subnet Communication**: Use relay functionality for distant nodes
3. **Custom Alerts**: Set up notifications for specific conditions
4. **Data Synchronization**: Sync data between local storage and Firebase

## API Documentation

### ESP32 HTTP Endpoints

#### Device Information
- `GET /discover` - Device discovery and basic info
- `GET /api/device/info` - Detailed device information and sensor data
- `GET /api/mesh/nodes` - Mesh topology and connected devices
- `GET /api/debug/sdcard` - SD card status and health information

#### Sensor Data & Control
- `GET /api/sensors/current` - Current sensor readings
- `GET /api/data/history` - Historical sensor data from SD card
- `POST /api/control/buzzer` - Control buzzer (on/off/toggle)

#### Relay System (Cross-Node Communication)
- `POST /api/relay/buzzer` - Control buzzer on remote nodes via mesh relay
- `GET /api/relay/data?nodeId={id}` - Get data from remote nodes
- `GET /api/relay/download?nodeId={id}` - Download historical data from remote nodes

#### Network Discovery
- `POST /api/discover/trigger` - Trigger network-wide device discovery
- UDP Port 5554 - Cross-subnet discovery broadcasting

### CoAP Endpoints
- `coap://node-ip:5683/sensors` - Current sensor data (lightweight, UDP-based)

**📖 For complete API documentation and IoT protocol details, see [Arduino IoT Documentation](ARDUINO_IOT_DOCUMENTATION.md)**

## Troubleshooting

### Common Issues

**App can't discover nodes:**
- Ensure device is connected to SmartAgriMesh WiFi
- Check ESP32 serial monitor for mesh connectivity
- Try refreshing node list in Settings > Network Settings

**Sensor data not updating:**
- Verify ESP32 sensors are properly connected
- Check network connectivity between nodes
- Restart ESP32 devices if needed

**Firebase sync issues:**
- Verify internet connectivity
- Check Firebase configuration
- Review authentication status

**SD card access problems:**
- Ensure SD card is properly inserted in ESP32
- Check SD card format (FAT32 recommended)
- Verify file permissions

### Network Configuration

**Mesh Network Settings:**
- SSID: SmartAgriMesh
- Password: agrimesh2024
- Mesh Port: 5555
- HTTP Port: 80
- CoAP Port: 5683

**Firewall Configuration:**
- Allow HTTP traffic on port 80
- Allow UDP traffic on port 5683 (CoAP)
- Enable mDNS for device discovery

## Development

### Project Structure
```
lib/
├── main.dart                 # App entry point and routing
├── models/                   # Data models and entities  
│   └── agri_node.dart       # Core data structures
├── providers/               # Riverpod state management
│   └── app_providers.dart   # Application-wide providers
├── screens/                 # UI presentation layer
│   ├── auth/                # Authentication screens
│   ├── home/                # Dashboard and overview
│   ├── nodes/               # Device management
│   ├── data/                # Data visualization  
│   ├── analytics/           # Advanced analytics
│   └── settings/            # Configuration
├── services/                # Business logic layer
│   ├── network_service.dart # IoT device communication
│   ├── firebase_service.dart # Cloud authentication
│   └── firestore_data_service.dart # Data persistence
├── widgets/                 # Reusable UI components
└── firebase_options.dart    # Firebase configuration

arduino_code/
└── smart_agri_enhanced.ino  # ESP32 mesh network firmware
```

**📖 For detailed architecture and code explanations:**
- **[Flutter App Documentation](FLUTTER_APP_DOCUMENTATION.md)** - Complete app architecture, state management, and UI details
- **[Arduino IoT Documentation](ARDUINO_IOT_DOCUMENTATION.md)** - ESP32 code structure, networking protocols, and hardware integration

### Building for Production

**Android:**
```bash
flutter build apk --release
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

**Windows:**
```bash
flutter build windows --release
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, please:
1. Check the troubleshooting section above
2. Review the **[Arduino IoT Documentation](ARDUINO_IOT_DOCUMENTATION.md)** for ESP32/hardware issues
3. Review the **[Flutter App Documentation](FLUTTER_APP_DOCUMENTATION.md)** for app-related issues
4. Search existing GitHub issues
5. Create a new issue with detailed information

## Acknowledgments

- **painlessMesh**: ESP32 mesh networking library for self-healing mesh networks
- **Flutter**: Cross-platform UI framework with excellent performance
- **Firebase**: Backend-as-a-Service platform for authentication and data storage
- **Material Design**: Google's design system for modern, consistent UI
- **Riverpod**: Reactive state management for Flutter applications
- **fl_chart**: Beautiful and performant charts for data visualization
