import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../widgets/node_status_card.dart';
import '../../widgets/node_control_card.dart';
import '../../services/offline_storage_service.dart';

class NodesScreen extends ConsumerStatefulWidget {
  const NodesScreen({super.key});

  @override
  ConsumerState<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends ConsumerState<NodesScreen> {
  bool _showControlView = false;
  List<String> _knownNodeIds = [];

  @override
  void initState() {
    super.initState();
    _loadKnownNodes();
  }

  Future<void> _loadKnownNodes() async {
    final knownIds = await OfflineStorageService.instance.getKnownNodeIds();
    if (mounted) {
      setState(() {
        _knownNodeIds = knownIds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final discoveredNodes = ref.watch(discoveredNodesProvider);
    final currentSensorData = ref.watch(currentSensorDataProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final networkService = ref.read(networkServiceProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Use manual refresh instead of invalidating providers
        await networkService.manualRefreshNodes();

        // Save discovered nodes to offline storage if available
        discoveredNodes.whenData((nodes) async {
          if (nodes.isNotEmpty) {
            await OfflineStorageService.instance.saveNodesOffline(nodes);
            await _loadKnownNodes(); // Refresh known nodes list
          }
        });
      },
      child: discoveredNodes.when(
        data: (nodes) =>
            _buildNodesView(nodes, currentSensorData, connectionStatus),
        loading: () => _buildLoadingView(),
        error: (error, _) => _buildErrorView(error, networkService),
      ),
    );
  }

  Widget _buildNodesView(
    List<dynamic> nodes,
    AsyncValue<Map<String, dynamic>> currentSensorData,
    AsyncValue<bool> connectionStatus,
  ) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text(_showControlView ? 'Node Control' : 'Network Nodes'),
          floating: true,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String action) async {
                switch (action) {
                  case 'toggle_view':
                    setState(() {
                      _showControlView = !_showControlView;
                    });
                    break;
                  case 'trigger_discovery':
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🔍 Starting manual node discovery...'),
                      ),
                    );
                    await ref.read(networkServiceProvider).forceFullDiscovery();
                    break;
                  case 'clear_cache':
                    await OfflineStorageService.instance.clearOfflineData();
                    await _loadKnownNodes();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Offline data cleared')),
                      );
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_view',
                  child: Row(
                    children: [
                      Icon(
                        _showControlView ? Icons.visibility : Icons.settings,
                      ),
                      const SizedBox(width: 8),
                      Text(_showControlView ? 'View Status' : 'View Controls'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'trigger_discovery',
                  child: Row(
                    children: [
                      Icon(Icons.wifi_find),
                      SizedBox(width: 8),
                      Text('Full Subnet Scan'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_cache',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all),
                      SizedBox(width: 8),
                      Text('Clear Offline Data'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        // Connection status indicator
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: connectionStatus.when(
              data: (isConnected) => _buildConnectionStatus(isConnected),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),

        // Offline nodes indicator
        if (_knownNodeIds.isNotEmpty)
          SliverToBoxAdapter(child: _buildOfflineNodesCard()),

        // Nodes list or empty state
        if (nodes.isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final node = nodes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: currentSensorData.when(
                    data: (sensorData) => _showControlView
                        ? NodeControlCard(
                            node: node,
                            sensorData: sensorData[node.deviceId],
                          )
                        : NodeStatusCard(
                            node: node,
                            sensorData: sensorData[node.deviceId],
                          ),
                    loading: () => _showControlView
                        ? NodeControlCard(node: node)
                        : NodeStatusCard(node: node),
                    error: (_, _) => _showControlView
                        ? NodeControlCard(node: node)
                        : NodeStatusCard(node: node),
                  ),
                );
              }, childCount: nodes.length),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return const CustomScrollView(
      slivers: [
        SliverAppBar(title: Text('Network Nodes'), floating: true),
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Scanning for nodes...'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(Object error, dynamic networkService) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(title: const Text('Network Nodes'), floating: true),
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error scanning for nodes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(discoveredNodesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(bool isConnected) {
    return Card(
      color: isConnected
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              color: isConnected ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isConnected
                    ? 'Online - Real-time node discovery active'
                    : 'Offline - Showing cached nodes',
                style: TextStyle(
                  color: isConnected ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineNodesCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Offline Node Data',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Found ${_knownNodeIds.length} known node IDs in offline storage.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<dynamic>>(
                future: OfflineStorageService.instance.getNodesOffline(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cached Nodes:',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        ...snapshot.data!
                            .take(5)
                            .map(
                              (node) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  top: 2,
                                ),
                                child: Text(
                                  '• ${node.deviceName} (${node.deviceId})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                        if (snapshot.data!.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 2),
                            child: Text(
                              '• and ${snapshot.data!.length - 5} more...',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.device_hub_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No Nodes Found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Nodes can be on different subnets\n(10.145.169.x, 10.35.17.x, etc.)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  ref.invalidate(discoveredNodesProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Quick Scan'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Starting full subnet scan...'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  await ref.read(networkServiceProvider).forceFullDiscovery();
                },
                icon: const Icon(Icons.wifi_find),
                label: const Text('Full Scan'),
              ),
            ],
          ),
          // Show offline nodes if available
          if (_knownNodeIds.isNotEmpty) ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () async {
                final offlineNodes = await OfflineStorageService.instance
                    .getNodesOffline();
                if (offlineNodes.isNotEmpty && mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Offline Nodes'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'These nodes were previously discovered:',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            ...offlineNodes.map(
                              (node) => ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.device_hub,
                                  color: Colors.grey,
                                ),
                                title: Text(node.deviceName),
                                subtitle: Text(
                                  '${node.deviceId} • ${node.ipAddress}',
                                ),
                                trailing: const Text(
                                  'Offline',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
              },
              icon: const Icon(Icons.storage),
              label: Text('View ${_knownNodeIds.length} Cached Nodes'),
            ),
          ],
        ],
      ),
    );
  }
}
