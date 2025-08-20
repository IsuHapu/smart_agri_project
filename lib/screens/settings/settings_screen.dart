import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_providers.dart';
import '../../models/agri_node.dart';
import '../../services/offline_storage_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User Profile Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User Profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(
                        (user?.displayName?.isNotEmpty ?? false)
                            ? user!.displayName![0].toUpperCase()
                            : user?.email?[0].toUpperCase() ?? 'U',
                        style: TextStyle(
                          fontSize: 24,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Unknown User',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            user?.email ?? 'No email',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Network Settings
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Network Settings'),
                subtitle: const Text('WiFi and mesh configuration'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showNetworkSettings(context, ref);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Data Sync'),
                subtitle: const Text('Sync data with Firebase'),
                trailing: Switch(
                  value: true,
                  onChanged: (value) {
                    // Implement sync toggle
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // App Settings
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notifications'),
                subtitle: const Text('Alert preferences'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showNotificationSettings(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Dark Mode'),
                trailing: Switch(
                  value: Theme.of(context).brightness == Brightness.dark,
                  onChanged: (value) {
                    // Implement theme toggle
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Data Retention'),
                subtitle: const Text('Keep data for 30 days'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showDataRetentionSettings(context);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // AI Analysis Settings
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.psychology),
                title: const Text('AI Analysis Server'),
                subtitle: const Text('Configure Google Colab ngrok URL'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showAIAnalysisSettings(context, ref);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.agriculture),
                title: const Text('Farm Configuration'),
                subtitle: const Text(
                  'Field size, crop type, and other details',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showFarmConfiguration(context, ref);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // About & Help
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('About'),
                subtitle: const Text('App version and info'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showAboutDialog(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help & Support'),
                subtitle: const Text('Get help and documentation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showHelpDialog(context);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sign Out
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => _signOut(context, ref),
          ),
        ),
      ],
    );
  }

  void _showNetworkSettings(BuildContext context, WidgetRef ref) {
    final networkService = ref.read(networkServiceProvider);
    final nodesAsync = ref.watch(discoveredNodesProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Network Settings'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Network Status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Network Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            networkService.isConnectedToMesh
                                ? Icons.wifi
                                : Icons.wifi_off,
                            color: networkService.isConnectedToMesh
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            networkService.isConnectedToMesh
                                ? 'Connected to SmartAgri Mesh'
                                : 'Not connected to mesh',
                          ),
                        ],
                      ),
                      nodesAsync.when(
                        data: (nodes) => Text(
                          '${nodes.length} nodes discovered',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        loading: () => Text(
                          'Discovering nodes...',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        error: (error, _) => Text(
                          'Error: $error',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'WiFi: SmartAgriMesh',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Password: agrimesh2024',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // SD Card Management
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SD Card Management',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: nodesAsync.when(
                            data: (nodes) => nodes.isEmpty
                                ? const Center(
                                    child: Text('No nodes discovered'),
                                  )
                                : ListView.builder(
                                    itemCount: nodes.length,
                                    itemBuilder: (context, index) {
                                      final node = nodes[index];
                                      return ListTile(
                                        leading: const Icon(Icons.sd_card),
                                        title: Text(node.deviceName),
                                        subtitle: Text(node.ipAddress),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.download),
                                              onPressed: () =>
                                                  _downloadSDCardData(
                                                    context,
                                                    ref,
                                                    node,
                                                  ),
                                              tooltip: 'Download SD Card Data',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.info),
                                              onPressed: () => _showSDCardInfo(
                                                context,
                                                ref,
                                                node,
                                              ),
                                              tooltip: 'SD Card Info',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) =>
                                Center(child: Text('Error: $error')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await networkService.discoverNodes();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Refresh'),
          ),
          TextButton(
            onPressed: () async {
              // Debug network connectivity for Android issues
              await networkService.debugNetworkReachability();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Network debug complete - check debug console',
                    ),
                  ),
                );
              }
            },
            child: const Text('Debug Network'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Settings'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: Text('Motion Detection Alerts'),
              value: true,
              onChanged: null,
            ),
            CheckboxListTile(
              title: Text('Temperature Warnings'),
              value: true,
              onChanged: null,
            ),
            CheckboxListTile(
              title: Text('Low Soil Moisture'),
              value: false,
              onChanged: null,
            ),
          ],
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

  void _showDataRetentionSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Retention'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose how long to keep sensor data:'),
            SizedBox(height: 16),
            RadioListTile<int>(
              title: Text('7 days'),
              value: 7,
              groupValue: 30,
              onChanged: null,
            ),
            RadioListTile<int>(
              title: Text('30 days'),
              value: 30,
              groupValue: 30,
              onChanged: null,
            ),
            RadioListTile<int>(
              title: Text('90 days'),
              value: 90,
              groupValue: 30,
              onChanged: null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Smart Agriculture',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.agriculture, size: 48),
      children: const [
        Text('IoT Network Management for Smart Agriculture'),
        SizedBox(height: 8),
        Text('Features:'),
        Text('• Real-time sensor monitoring'),
        Text('• Mesh network discovery'),
        Text('• Data synchronization'),
        Text('• Firebase integration'),
      ],
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Getting Started:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Connect to SmartAgriMesh WiFi'),
              Text('2. App will auto-discover nodes'),
              Text('3. View live sensor data'),
              Text('4. Data syncs to Firebase'),
              SizedBox(height: 16),
              Text(
                'Troubleshooting:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Check WiFi connection'),
              Text('• Ensure nodes are powered on'),
              Text('• Try refreshing node list'),
              Text('• Check internet for Firebase sync'),
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

  void _signOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(firebaseServiceProvider).signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _downloadSDCardData(
    BuildContext context,
    WidgetRef ref,
    AgriNode node,
  ) async {
    final networkService = ref.read(networkServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Getting available files...'),
          ],
        ),
      ),
    );

    try {
      final files = await networkService.getAvailableDataFilesOptimized(
        node.ipAddress,
      );

      if (context.mounted) Navigator.of(context).pop();

      if (files.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data files found on SD card')),
          );
        }
        return;
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Download from ${node.deviceName}'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final fileName = files[index];
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(fileName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () =>
                              _downloadFile(context, ref, node, fileName),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () =>
                              _deleteFile(context, ref, node, fileName),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () => _downloadAllFiles(context, ref, node, files),
                icon: const Icon(Icons.download_for_offline),
                label: const Text('Download All'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _downloadFile(
    BuildContext context,
    WidgetRef ref,
    AgriNode node,
    String fileName,
  ) async {
    final networkService = ref.read(networkServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('Downloading $fileName...'),
          ],
        ),
      ),
    );

    try {
      final fileContent = await networkService.downloadDataFileSmart(
        node.ipAddress,
        fileName,
      );

      if (context.mounted) Navigator.of(context).pop();

      if (fileContent != null) {
        // TODO: Save file to local storage or process the data
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded $fileName successfully')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download $fileName')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error downloading file: $e')));
      }
    }
  }

  void _downloadAllFiles(
    BuildContext context,
    WidgetRef ref,
    AgriNode node,
    List<String> files,
  ) async {
    if (files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No files to download')));
      return;
    }

    final networkService = ref.read(networkServiceProvider);

    // Close the file list dialog first
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Downloading from ${node.deviceName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Downloading ${files.length} files...'),
              ],
            ),
          );
        },
      ),
    );

    try {
      if (kDebugMode) {
        print(
          '📦 Starting optimized batch download of ${files.length} files from ${node.deviceName}',
        );
      }

      // Use the new batch download method for better performance
      final downloadResults = await networkService.downloadAllDataFilesBatch(
        node.ipAddress,
        files,
      );

      List<String> downloadedFiles = downloadResults.keys.toList();
      List<String> failedFiles = files
          .where((f) => !downloadResults.containsKey(f))
          .toList();

      Map<String, dynamic> allData = {
        'nodeId': node.deviceId,
        'deviceName': node.deviceName,
        'downloadedAt': DateTime.now().toIso8601String(),
        'files': <String, dynamic>{},
      };

      // Process downloaded files
      for (final entry in downloadResults.entries) {
        final fileName = entry.key;
        final fileContent = entry.value;

        // Parse JSON content and store it
        try {
          final jsonData = json.decode(fileContent);
          allData['files'][fileName] = jsonData;
        } catch (e) {
          // If JSON parsing fails, store as raw content
          allData['files'][fileName] = fileContent;
        }
      }

      if (context.mounted) Navigator.of(context).pop();

      // Sync all collected data to local storage and Firebase
      final dataList = <Map<String, dynamic>>[];
      final filesData = allData['files'] as Map<String, dynamic>?;
      if (filesData != null) {
        for (final entry in filesData.entries) {
          final fileName = entry.key;
          final fileData = entry.value;

          if (kDebugMode) {
            print(
              'Processing file: $fileName, data type: ${fileData.runtimeType}',
            );
          }

          if (fileData is String) {
            // Handle line-by-line JSON format (common in SD card files)
            final lines = fileData.split('\n');
            for (final line in lines) {
              if (line.trim().isNotEmpty) {
                try {
                  final lineData = json.decode(line.trim());
                  if (lineData is Map<String, dynamic>) {
                    dataList.add(lineData);
                  }
                } catch (e) {
                  // Skip invalid lines
                  continue;
                }
              }
            }
          } else if (fileData is Map<String, dynamic>) {
            // Handle single JSON object
            dataList.add(fileData);
          } else if (fileData is List) {
            // Handle array of JSON objects
            for (final item in fileData) {
              if (item is Map<String, dynamic>) {
                dataList.add(item);
              }
            }
          }
        }
      }

      if (kDebugMode) {
        print('Total data items to process: ${dataList.length}');
      }
      await _syncDownloadedDataToStorage(dataList, node.deviceId, ref);

      // Show summary to user
      if (context.mounted) {
        String message;
        if (downloadedFiles.isNotEmpty) {
          message =
              'Downloaded ${downloadedFiles.length} files from ${node.deviceName}';
          if (failedFiles.isNotEmpty) {
            message += '\n${failedFiles.length} files failed to download';
          }

          // Show option to view downloaded data
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Download Complete'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  Text(
                    'Downloaded files:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ...downloadedFiles.map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• $file'),
                    ),
                  ),
                  if (failedFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Failed downloads:',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Colors.red),
                    ),
                    ...failedFiles.map(
                      (file) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(
                          '• $file',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showDownloadedData(context, allData);
                  },
                  child: const Text('View Data'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to download any files from ${node.deviceName}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error downloading files: $e')));
      }
    }
  }

  void _showDownloadedData(BuildContext context, Map<String, dynamic> allData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Data from ${allData['deviceName']}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloaded at: ${allData['downloadedAt']}'),
                const SizedBox(height: 16),
                Text('Files:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...((allData['files'] as Map<String, dynamic>).entries.map((
                  entry,
                ) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              json.encode(entry.value).length > 200
                                  ? '${json.encode(entry.value).substring(0, 200)}...'
                                  : json.encode(entry.value),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                })),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              // TODO: Implement data export functionality
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Export functionality coming soon!'),
                ),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _deleteFile(
    BuildContext context,
    WidgetRef ref,
    AgriNode node,
    String fileName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete $fileName from ${node.deviceName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final networkService = ref.read(networkServiceProvider);

      try {
        final success = await networkService.deleteDataFile(
          node.ipAddress,
          fileName,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Deleted $fileName successfully'
                    : 'Failed to delete $fileName',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting file: $e')));
        }
      }
    }
  }

  void _showSDCardInfo(
    BuildContext context,
    WidgetRef ref,
    AgriNode node,
  ) async {
    final networkService = ref.read(networkServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Getting SD card info...'),
          ],
        ),
      ),
    );

    try {
      final info = await networkService.getSDCardInfoSmart(node.ipAddress);

      if (context.mounted) Navigator.of(context).pop();

      if (info != null) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${node.deviceName} SD Card'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Size: ${info['totalSize'] ?? 'Unknown'}'),
                  Text('Used Space: ${info['usedSpace'] ?? 'Unknown'}'),
                  Text('Free Space: ${info['freeSpace'] ?? 'Unknown'}'),
                  const SizedBox(height: 8),
                  Text('Files: ${info['fileCount'] ?? 0}'),
                  Text('Status: ${info['status'] ?? 'Unknown'}'),
                ],
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
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to get SD card info')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAIAnalysisSettings(BuildContext context, WidgetRef ref) {
    final TextEditingController ngrokController = TextEditingController();

    // Load current ngrok URL from SharedPreferences
    _loadNgrokUrl().then((url) {
      ngrokController.text = url;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Analysis Server Settings'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Google Colab ngrok URL:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ngrokController,
                decoration: const InputDecoration(
                  labelText: 'ngrok URL',
                  hintText: 'https://your-ngrok-url.ngrok.io',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Instructions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Run the AI analysis notebook in Google Colab\n'
                '2. Start ngrok tunnel\n'
                '3. Copy the HTTPS URL here\n'
                '4. The app will use AI analysis when online',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Falls back to local analysis when offline',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _saveNgrokUrl(ngrokController.text.trim());
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI Analysis server URL saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showFarmConfiguration(BuildContext context, WidgetRef ref) {
    final TextEditingController fieldSizeController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController plantingDateController =
        TextEditingController();
    final TextEditingController expectedHarvestController =
        TextEditingController();
    final TextEditingController previousYieldController =
        TextEditingController();

    // Dropdown values - these will be populated from current configuration
    String? selectedClimateZone;
    String? selectedCropType;
    String? selectedSeedVariety;
    String? selectedSoilType;
    String? selectedIrrigationMethod;
    String? selectedFertilizerType;
    String? selectedRainfallPattern;

    // Valid options for dropdowns (case-sensitive)
    final List<String> climateZones = [
      'Wet Zone',
      'Dry Zone',
      'Intermediate Zone',
    ];
    final List<String> cropTypes = [
      'Rice',
      'Tea',
      'Rubber',
      'Coconut',
      'Vegetables',
      'Spices',
      'Fruits',
    ];
    final Map<String, List<String>> cropVarieties = {
      'Rice': [
        'BG 352',
        'AT 362',
        'BG 300',
        'H-4',
        'BG 94-1',
        'AT 405',
        'BG 450',
      ],
      'Tea': ['TRI 2025', 'TRI 2043', 'TRI 3055', 'TRI 4006', 'PBIG 1'],
      'Rubber': ['RRIC 100', 'RRIC 110', 'RRIC 121', 'PB 235', 'GT 1'],
      'Coconut': ['Dwarf', 'Tall', 'Hybrid'],
      'Vegetables': ['Tomato', 'Cabbage', 'Carrot', 'Bean', 'Onion'],
      'Spices': ['Cinnamon', 'Cardamom', 'Pepper', 'Cloves', 'Nutmeg'],
      'Fruits': ['Mango', 'Banana', 'Papaya', 'Avocado', 'Jackfruit'],
    };
    final List<String> soilTypes = [
      'Red Earth',
      'Alluvial',
      'Laterite',
      'Peat',
      'Clay',
      'Sandy',
      'Clay Loam',
      'Sandy Loam',
    ];
    final List<String> irrigationMethods = [
      'Drip',
      'Sprinkler',
      'Flood',
      'Rain-fed',
      'Tank irrigation',
      'Micro-sprinkler',
      'Drip Irrigation',
      'Sprinkler Irrigation',
      'Flood Irrigation',
      'Canal Irrigation',
      'Well Irrigation',
    ];
    final List<String> fertilizerTypes = [
      'Organic',
      'Inorganic',
      'Mixed',
      'Traditional',
      'NPK',
      'Compost',
      'Organic Compost',
      'Chemical Fertilizer',
      'Bio-fertilizer',
      'Vermicompost',
      'Green Manure',
      'Mixed (Organic + Chemical)',
    ];
    final List<String> rainfallPatterns = [
      'Southwest Monsoon',
      'Northeast Monsoon',
      'Inter-monsoon',
      'High',
      'Medium',
      'Low',
      'Variable',
      'Seasonal',
    ];

    // Load current farm configuration
    _loadFarmConfiguration().then((config) {
      fieldSizeController.text = config['fieldSize'] ?? '';
      locationController.text = config['location'] ?? '';
      plantingDateController.text = config['plantingDate'] ?? '';
      expectedHarvestController.text = config['expectedHarvest'] ?? '';
      previousYieldController.text = config['previousYield'] ?? '';

      // Set dropdown values from configuration - validate against available options
      final climateZoneValue = config['climateZone']?.toString().trim();
      selectedClimateZone =
          climateZoneValue?.isNotEmpty == true &&
              climateZones.contains(climateZoneValue)
          ? climateZoneValue
          : null;

      final cropTypeValue = config['cropType']?.toString().trim();
      selectedCropType =
          cropTypeValue?.isNotEmpty == true && cropTypes.contains(cropTypeValue)
          ? cropTypeValue
          : null;

      final seedVarietyValue = config['seedVariety']?.toString().trim();
      selectedSeedVariety =
          seedVarietyValue?.isNotEmpty == true &&
              selectedCropType != null &&
              cropVarieties[selectedCropType]?.contains(seedVarietyValue) ==
                  true
          ? seedVarietyValue
          : null;

      final soilTypeValue = config['soilType']?.toString().trim();
      selectedSoilType =
          soilTypeValue?.isNotEmpty == true && soilTypes.contains(soilTypeValue)
          ? soilTypeValue
          : null;

      final irrigationMethodValue = config['irrigationMethod']
          ?.toString()
          .trim();
      selectedIrrigationMethod =
          irrigationMethodValue?.isNotEmpty == true &&
              irrigationMethods.contains(irrigationMethodValue)
          ? irrigationMethodValue
          : null;

      final fertilizerTypeValue = config['fertilizerType']?.toString().trim();
      selectedFertilizerType =
          fertilizerTypeValue?.isNotEmpty == true &&
              fertilizerTypes.contains(fertilizerTypeValue)
          ? fertilizerTypeValue
          : null;

      final rainfallPatternValue = config['rainfallPattern']?.toString().trim();
      selectedRainfallPattern =
          rainfallPatternValue?.isNotEmpty == true &&
              rainfallPatterns.contains(rainfallPatternValue)
          ? rainfallPatternValue
          : null;
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('🇱🇰 Sri Lankan Farm Configuration'),
          content: SizedBox(
            width: double.maxFinite,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic Information
                  Text(
                    'Basic Farm Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fieldSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Field Size (acres)',
                      hintText: 'e.g., 2.5',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'District/Province',
                      hintText: 'e.g., Colombo, Kandy, Galle, Anuradhapura',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Climate Zone Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedClimateZone,
                    decoration: const InputDecoration(
                      labelText: '🌍 Climate Zone',
                      border: OutlineInputBorder(),
                      helperText: 'Required for accurate analysis',
                    ),
                    hint: const Text('Select Climate Zone'),
                    items: climateZones
                        .map(
                          (zone) =>
                              DropdownMenuItem(value: zone, child: Text(zone)),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedClimateZone = value;
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  // Crop Information
                  Text(
                    'Crop Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Crop Type Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedCropType,
                    decoration: const InputDecoration(
                      labelText: '🌾 Crop Type',
                      border: OutlineInputBorder(),
                      helperText: 'Required for yield predictions',
                    ),
                    hint: const Text('Select Crop Type'),
                    items: cropTypes
                        .map(
                          (crop) =>
                              DropdownMenuItem(value: crop, child: Text(crop)),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedCropType = value;
                        selectedSeedVariety =
                            null; // Reset variety when crop changes
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Seed Variety Dropdown (filtered by crop type)
                  DropdownButtonFormField<String>(
                    value: selectedSeedVariety,
                    decoration: const InputDecoration(
                      labelText: '🌱 Seed/Plant Variety',
                      border: OutlineInputBorder(),
                      helperText: 'Select crop type first',
                    ),
                    hint: const Text('Select Variety'),
                    items:
                        selectedCropType != null &&
                            cropVarieties.containsKey(selectedCropType)
                        ? cropVarieties[selectedCropType]!
                              .map(
                                (variety) => DropdownMenuItem(
                                  value: variety,
                                  child: Text(variety),
                                ),
                              )
                              .toList()
                        : [],
                    onChanged: selectedCropType != null
                        ? (value) {
                            setState(() {
                              selectedSeedVariety = value;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: plantingDateController,
                    decoration: const InputDecoration(
                      labelText: 'Planting Date',
                      hintText: 'e.g., 2024-03-15 or Yala/Maha season',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: expectedHarvestController,
                    decoration: const InputDecoration(
                      labelText: 'Expected Harvest Date',
                      hintText: 'e.g., 2024-07-15 or harvest month',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Agricultural Practices
                  Text(
                    'Agricultural Practices',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Soil Type Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedSoilType,
                    decoration: const InputDecoration(
                      labelText: '💧 Soil Type',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Soil Type'),
                    items: soilTypes
                        .map(
                          (soil) =>
                              DropdownMenuItem(value: soil, child: Text(soil)),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedSoilType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Irrigation Method Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedIrrigationMethod,
                    decoration: const InputDecoration(
                      labelText: '🚿 Irrigation Method',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Irrigation Method'),
                    items: irrigationMethods
                        .map(
                          (method) => DropdownMenuItem(
                            value: method,
                            child: Text(method),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedIrrigationMethod = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Fertilizer Type Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedFertilizerType,
                    decoration: const InputDecoration(
                      labelText: '🌿 Fertilizer Program',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Fertilizer Type'),
                    items: fertilizerTypes
                        .map(
                          (fertilizer) => DropdownMenuItem(
                            value: fertilizer,
                            child: Text(fertilizer),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedFertilizerType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Rainfall Pattern Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedRainfallPattern,
                    decoration: const InputDecoration(
                      labelText: '🌧️ Rainfall Pattern',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Rainfall Pattern'),
                    items: rainfallPatterns
                        .map(
                          (pattern) => DropdownMenuItem(
                            value: pattern,
                            child: Text(pattern),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedRainfallPattern = value;
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  // Performance Data
                  Text(
                    'Historical Performance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: previousYieldController,
                    decoration: const InputDecoration(
                      labelText: 'Previous Season Yield',
                      hintText: 'e.g., 4.5 tons/acre, 15 bags/acre',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🌾 Sri Lankan Agriculture AI',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'This information helps provide accurate analysis for Sri Lankan climate, soil conditions, and traditional farming practices. AI will consider monsoon patterns, local crop varieties, and regional agricultural practices.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final config = {
                  'fieldSize': fieldSizeController.text.trim(),
                  'cropType': selectedCropType ?? '',
                  'location': locationController.text.trim(),
                  'soilType': selectedSoilType ?? '',
                  'plantingDate': plantingDateController.text.trim(),
                  'seedVariety': selectedSeedVariety ?? '',
                  'expectedHarvest': expectedHarvestController.text.trim(),
                  'climateZone': selectedClimateZone ?? '',
                  'rainfallPattern': selectedRainfallPattern ?? '',
                  'irrigationMethod': selectedIrrigationMethod ?? '',
                  'fertilizerType': selectedFertilizerType ?? '',
                  'previousYield': previousYieldController.text.trim(),
                };
                await _saveFarmConfiguration(config);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sri Lankan farm configuration saved'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _loadNgrokUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('ai_ngrok_url') ?? '';
    } catch (e) {
      return '';
    }
  }

  Future<void> _saveNgrokUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_ngrok_url', url);
    } catch (e) {
      // Handle error silently
    }
  }

  Future<Map<String, String>> _loadFarmConfiguration() async {
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
      };
    } catch (e) {
      return {};
    }
  }

  Future<void> _saveFarmConfiguration(Map<String, String> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('farm_field_size', config['fieldSize'] ?? '');
      await prefs.setString('farm_crop_type', config['cropType'] ?? '');
      await prefs.setString('farm_location', config['location'] ?? '');
      await prefs.setString('farm_soil_type', config['soilType'] ?? '');
      await prefs.setString('farm_planting_date', config['plantingDate'] ?? '');
      await prefs.setString('farm_seed_variety', config['seedVariety'] ?? '');
      await prefs.setString(
        'farm_expected_harvest',
        config['expectedHarvest'] ?? '',
      );
      await prefs.setString('farm_climate_zone', config['climateZone'] ?? '');
      await prefs.setString(
        'farm_rainfall_pattern',
        config['rainfallPattern'] ?? '',
      );
      await prefs.setString(
        'farm_irrigation_method',
        config['irrigationMethod'] ?? '',
      );
      await prefs.setString(
        'farm_fertilizer_type',
        config['fertilizerType'] ?? '',
      );
      await prefs.setString(
        'farm_previous_yield',
        config['previousYield'] ?? '',
      );
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _syncDownloadedDataToStorage(
    List<Map<String, dynamic>> downloadedData,
    String nodeId,
    WidgetRef ref,
  ) async {
    try {
      final firestoreService = ref.read(firestoreDataServiceProvider);
      final offlineStorage = OfflineStorageService.instance;

      if (kDebugMode) {
        print('Syncing ${downloadedData.length} data items from node: $nodeId');
      }

      // Process each downloaded data object
      for (final data in downloadedData) {
        await _processSensorDataFromFile(
          data,
          nodeId,
          offlineStorage,
          firestoreService,
        );
      }

      if (kDebugMode) {
        print('Completed syncing all data items');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing downloaded data to storage: $e');
      }
    }
  }

  Future<void> _processSensorDataFromFile(
    Map<String, dynamic> data,
    String nodeId,
    dynamic offlineStorage,
    dynamic firestoreService,
  ) async {
    try {
      // Extract sensor data from JSON data
      final sensorData = _extractSensorDataFromJson(data, nodeId);
      if (sensorData != null) {
        // Store to offline storage
        await offlineStorage.saveSensorDataOffline(sensorData);

        // Store to Firebase if connected
        await firestoreService.saveSensorData(sensorData);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing sensor data from file: $e');
      }
    }
  }

  SensorData? _extractSensorDataFromJson(
    Map<String, dynamic> json,
    String nodeId,
  ) {
    try {
      // Handle different JSON structures
      Map<String, dynamic> data = json;

      // If the JSON has a 'data' field, use it
      if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
        data = json['data'] as Map<String, dynamic>;
      }

      // Extract device ID with same priority as node control card
      final extractedDeviceId =
          data['id'] ??
          data['nodeId'] ??
          data['deviceId'] ??
          nodeId; // Use actual device ID from data if available

      // Skip processing if deviceId is null, empty, or invalid
      if (extractedDeviceId == null ||
          extractedDeviceId.toString().isEmpty ||
          extractedDeviceId.toString() == 'null' ||
          extractedDeviceId.toString() == '0') {
        return null;
      }

      return SensorData(
        deviceId: extractedDeviceId.toString(),
        deviceName: data['deviceName'] ?? data['name'] ?? 'Unknown Node',
        timestamp: json.containsKey('timestamp')
            ? DateTime.parse(json['timestamp'].toString())
            : (json.containsKey('time')
                  ? DateTime.parse(json['time'].toString())
                  : DateTime.now()),
        temperature: _parseDouble(data['temperature'] ?? data['temp']) ?? 0.0,
        humidity: _parseDouble(data['humidity'] ?? data['hum']) ?? 0.0,
        soilMoisture:
            _parseInt(
              data['soil_moisture'] ?? data['soil'] ?? data['soilMoisture'],
            ) ??
            0,
        motionDetected:
            _parseBool(data['motion'] ?? data['motionDetected']) ??
            _parseBool(data['pir_status'] ?? data['pirStatus']) ??
            false,
        distance: _parseDouble(data['distance'] ?? data['dist']) ?? 0.0,
        buzzerActive:
            _parseBool(data['buzzer_active'] ?? data['buzzerActive']) ??
            _parseBool(data['buzzer_status'] ?? data['buzzerStatus']) ??
            false,
        isLocal: true, // Data from SD card is considered local
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting sensor data from JSON: $e');
      }
      return null;
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return null;
  }
}
