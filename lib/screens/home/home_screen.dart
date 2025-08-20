import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../models/agri_node.dart';
import '../../widgets/sensor_card.dart';
import '../../widgets/node_status_card.dart';
import '../../widgets/scanning_indicators.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // NO automatic discovery on screen load
    // User must manually refresh to discover nodes
  }

  void _triggerManualRefresh() async {
    final networkService = ref.read(networkServiceProvider);
    // Manual discovery triggered by user action only
    await networkService.manualRefreshNodes();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final allNodes = ref.watch(allNodesProvider);
    final currentSensorData = ref.watch(currentSensorDataProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Use manual refresh for better ESP32-friendly behavior
        final networkService = ref.read(networkServiceProvider);
        await networkService.manualRefreshNodes();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome section
            _buildWelcomeSection(context, ref),
            const SizedBox(height: 24),

            // 📡 Scanning indicators
            const ScanningIndicators(showCompact: true),
            const SizedBox(height: 16),

            // Network status
            _buildNetworkStatus(context, connectionStatus, allNodes.length),
            const SizedBox(height: 24),

            // Quick stats
            _buildQuickStats(context, allNodes, currentSensorData),
            const SizedBox(height: 24),

            // Active nodes
            _buildActiveNodes(context, allNodes, currentSensorData),
            const SizedBox(height: 24),

            // Recent sensor data
            _buildRecentSensorData(context, currentSensorData),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final timeOfDay = _getTimeOfDay();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getTimeIcon(),
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$timeOfDay ${user?.displayName ?? 'User'}!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor your smart agriculture network',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkStatus(
    BuildContext context,
    AsyncValue<bool> connectionStatus,
    int nodeCount,
  ) {
    return connectionStatus.when(
      data: (isConnected) => Card(
        color: isConnected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: isConnected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? 'Connected to SmartAgriMesh'
                          : 'Not Connected',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isConnected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    Text(
                      isConnected
                          ? '$nodeCount nodes discovered'
                          : 'Connect to SmartAgriMesh WiFi network',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  _triggerManualRefresh();
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Manual node discovery',
              ),
            ],
          ),
        ),
      ),
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Checking network status...'),
            ],
          ),
        ),
      ),
      error: (error, stack) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Network error: ${error.toString()}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStats(
    BuildContext context,
    List<AgriNode> nodes,
    AsyncValue<Map<String, SensorData>> sensorData,
  ) {
    return sensorData.when(
      data: (data) {
        final onlineNodes = nodes.where((node) => node.isOnline).length;
        final avgTemperature = data.isNotEmpty
            ? data.values.map((s) => s.temperature).reduce((a, b) => a + b) /
                  data.length
            : 0.0;
        final avgHumidity = data.isNotEmpty
            ? data.values.map((s) => s.humidity).reduce((a, b) => a + b) /
                  data.length
            : 0.0;

        return Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                'Online Nodes',
                '$onlineNodes/${nodes.length}',
                Icons.device_hub,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                context,
                'Avg Temperature',
                '${avgTemperature.toStringAsFixed(1)}°C',
                Icons.thermostat,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                context,
                'Avg Humidity',
                '${avgHumidity.toStringAsFixed(1)}%',
                Icons.water_drop,
                Colors.blue,
              ),
            ),
          ],
        );
      },
      loading: () => const Row(
        children: [
          Expanded(child: _StatCardSkeleton()),
          SizedBox(width: 8),
          Expanded(child: _StatCardSkeleton()),
          SizedBox(width: 8),
          Expanded(child: _StatCardSkeleton()),
        ],
      ),
      error: (error, stack) => Container(),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveNodes(
    BuildContext context,
    List<AgriNode> nodes,
    AsyncValue<Map<String, SensorData>> sensorData,
  ) {
    if (nodes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.device_hub_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No Nodes Discovered',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to SmartAgriMesh WiFi to discover IoT nodes',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final onlineNodes = nodes.where((node) => node.isOnline).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Active Nodes', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => context.go('/nodes'),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...onlineNodes.map(
          (node) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NodeStatusCard(
              node: node,
              sensorData: sensorData.when(
                data: (data) => data[node.deviceId],
                loading: () => null,
                error: (_, _) => null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSensorData(
    BuildContext context,
    AsyncValue<Map<String, SensorData>> sensorData,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Live Sensor Data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () => context.go('/data'),
              child: const Text('View History'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        sensorData.when(
          data: (data) {
            if (data.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.sensors_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Sensor Data',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sensor data will appear here when nodes are connected',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: data.entries.take(2).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SensorCard(sensorData: entry.value),
                );
              }).toList(),
            );
          },
          loading: () => Column(
            children: [
              const _SensorCardSkeleton(),
              const SizedBox(height: 8),
              const _SensorCardSkeleton(),
            ],
          ),
          error: (error, stack) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading sensor data: $error'),
            ),
          ),
        ),
      ],
    );
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  IconData _getTimeIcon() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return Icons.wb_sunny;
    } else if (hour < 17) {
      return Icons.wb_sunny_outlined;
    } else {
      return Icons.nightlight_round;
    }
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorCardSkeleton extends StatelessWidget {
  const _SensorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 80,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
