import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

/// A simple test widget to demonstrate buzzer control functionality
/// This can be used to test buzzer controls without the full node discovery
class BuzzerTestWidget extends ConsumerStatefulWidget {
  const BuzzerTestWidget({super.key});

  @override
  ConsumerState<BuzzerTestWidget> createState() => _BuzzerTestWidgetState();
}

class _BuzzerTestWidgetState extends ConsumerState<BuzzerTestWidget> {
  final TextEditingController _nodeIdController = TextEditingController();
  bool _isControlling = false;
  String _lastResult = '';

  @override
  void dispose() {
    _nodeIdController.dispose();
    super.dispose();
  }

  Future<void> _testBuzzerControl(String action) async {
    final nodeId = _nodeIdController.text.trim();
    if (nodeId.isEmpty) {
      setState(() {
        _lastResult = 'Error: Please enter a node ID';
      });
      return;
    }

    setState(() {
      _isControlling = true;
      _lastResult = 'Sending $action command to $nodeId...';
    });

    try {
      final networkService = ref.read(networkServiceProvider);
      final success = await networkService.controlBuzzer(nodeId, action);

      setState(() {
        _lastResult = success
            ? '✅ Successfully sent $action command to $nodeId'
            : '❌ Failed to send $action command to $nodeId';
      });
    } catch (e) {
      setState(() {
        _lastResult = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isControlling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buzzer Control Test'),
        backgroundColor: Colors.orange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buzzer Control Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This widget allows you to test buzzer control by sending commands directly to ESP32 nodes.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Node ID Input
            TextField(
              controller: _nodeIdController,
              decoration: const InputDecoration(
                labelText: 'Node ID',
                hintText: 'Enter ESP32 node ID (e.g., 123456789)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.device_hub),
              ),
              enabled: !_isControlling,
            ),

            const SizedBox(height: 16),

            // Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isControlling
                        ? null
                        : () => _testBuzzerControl('on'),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('ON'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isControlling
                        ? null
                        : () => _testBuzzerControl('off'),
                    icon: const Icon(Icons.volume_off),
                    label: const Text('OFF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isControlling
                        ? null
                        : () => _testBuzzerControl('toggle'),
                    icon: const Icon(Icons.toggle_on),
                    label: const Text('TOGGLE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status Display
            Card(
              color: _lastResult.startsWith('✅')
                  ? Colors.green.withValues(alpha: 0.1)
                  : _lastResult.startsWith('❌')
                  ? Colors.red.withValues(alpha: .1)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isControlling ? Icons.hourglass_empty : Icons.info,
                          color: _lastResult.startsWith('✅')
                              ? Colors.green
                              : _lastResult.startsWith('❌')
                              ? Colors.red
                              : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Status',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isControlling)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Sending command...'),
                        ],
                      )
                    else
                      Text(
                        _lastResult.isEmpty
                            ? 'Ready to send commands'
                            : _lastResult,
                        style: TextStyle(
                          color: _lastResult.startsWith('✅')
                              ? Colors.green
                              : _lastResult.startsWith('❌')
                              ? Colors.red
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Instructions
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instructions:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Ensure your ESP32 nodes are powered on and connected',
                    ),
                    Text('2. Enter the target node ID in the field above'),
                    Text(
                      '3. Use the control buttons to test buzzer functionality',
                    ),
                    Text('4. Check the status display for command results'),
                    SizedBox(height: 8),
                    Text(
                      'Note: The system automatically handles direct vs relay control based on node availability.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.invalidate(discoveredNodesProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Refreshing node discovery...'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Nodes'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _nodeIdController.clear();
                        _lastResult = '';
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
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
