import 'package:flutter/material.dart';
import '../models/agri_node.dart';

class SensorCard extends StatelessWidget {
  final SensorData sensorData;

  const SensorCard({super.key, required this.sensorData});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1024;
    final isTablet = screenWidth > 600 && screenWidth <= 1024;

    return Card(
      elevation: isDesktop ? 4 : 1,
      margin: EdgeInsets.all(isDesktop ? 16 : 8),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isDesktop ? 12 : 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
                  ),
                  child: Icon(
                    Icons.sensors,
                    color: Theme.of(context).colorScheme.primary,
                    size: isDesktop ? 28 : 24,
                  ),
                ),
                SizedBox(width: isDesktop ? 16 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sensorData.deviceName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isDesktop ? 18 : null,
                            ),
                      ),
                      SizedBox(height: isDesktop ? 4 : 2),
                      Text(
                        'ID: ${sensorData.deviceId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: isDesktop ? 14 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sensorData.isLocal)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 12 : 8,
                      vertical: isDesktop ? 6 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
                    ),
                    child: Text(
                      'LOCAL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: isDesktop ? 12 : null,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: isDesktop ? 24 : 16),

            // Sensor readings grid - responsive layout
            _buildResponsiveGrid(context, isDesktop, isTablet),

            SizedBox(height: isDesktop ? 20 : 12),

            // Timestamp and IP info
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: isDesktop ? 18 : 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: isDesktop ? 6 : 4),
                Text(
                  _formatTimestamp(sensorData.timestamp),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: isDesktop ? 14 : null,
                  ),
                ),
                const Spacer(),
                if (sensorData.stationIP != null) ...[
                  Icon(
                    Icons.computer,
                    size: isDesktop ? 18 : 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: isDesktop ? 6 : 4),
                  Text(
                    sensorData.stationIP!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: isDesktop ? 14 : null,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(
    BuildContext context,
    bool isDesktop,
    bool isTablet,
  ) {
    final crossAxisCount = isDesktop ? 6 : (isTablet ? 3 : 3);
    final childAspectRatio = isDesktop ? 1.3 : (isTablet ? 1.2 : 1.2);
    final mainAxisSpacing = isDesktop ? 16.0 : 8.0;
    final crossAxisSpacing = isDesktop ? 16.0 : 8.0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      children: [
        _buildSensorReading(
          context,
          'Temperature',
          '${sensorData.temperature.toStringAsFixed(1)}°C',
          Icons.thermostat,
          Colors.orange,
          isDesktop,
        ),
        _buildSensorReading(
          context,
          'Humidity',
          '${sensorData.humidity.toStringAsFixed(1)}%',
          Icons.water_drop,
          Colors.blue,
          isDesktop,
        ),
        _buildSensorReading(
          context,
          'Soil',
          '${sensorData.soilMoisture}%',
          Icons.grass,
          Colors.green,
          isDesktop,
        ),
        _buildSensorReading(
          context,
          'Motion',
          sensorData.motionDetected ? 'Detected' : 'Clear',
          sensorData.motionDetected
              ? Icons.motion_photos_on
              : Icons.motion_photos_off,
          sensorData.motionDetected ? Colors.red : Colors.grey,
          isDesktop,
        ),
        _buildSensorReading(
          context,
          'Distance',
          '${sensorData.distance.toStringAsFixed(1)}cm',
          Icons.straighten,
          Colors.purple,
          isDesktop,
        ),
        _buildSensorReading(
          context,
          'Buzzer',
          sensorData.buzzerActive ? 'Active' : 'Off',
          sensorData.buzzerActive ? Icons.volume_up : Icons.volume_off,
          sensorData.buzzerActive ? Colors.red : Colors.grey,
          isDesktop,
        ),
      ],
    );
  }

  Widget _buildSensorReading(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDesktop,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.all(isDesktop ? 12 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
          ),
          child: Icon(icon, color: color, size: isDesktop ? 28 : 24),
        ),
        SizedBox(height: isDesktop ? 8 : 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: isDesktop ? 14 : null),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: isDesktop ? 16 : null,
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}
