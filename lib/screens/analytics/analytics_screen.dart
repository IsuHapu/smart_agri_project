import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../providers/app_providers.dart';
import '../../models/agri_node.dart';
import '../../services/ai_analysis_service.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isAIConnected = false;
  bool _isCheckingConnection = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAIConnection();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAIConnection() async {
    setState(() {
      _isCheckingConnection = true;
    });

    final isConnected = await AIAnalysisService.instance.testConnection();

    if (mounted) {
      setState(() {
        _isAIConnected = isConnected;
        _isCheckingConnection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSensorData = ref.watch(currentSensorDataProvider);
    final nodes = ref.watch(discoveredNodesProvider);

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(padding: const EdgeInsets.all(16), child: _buildHeader()),

          // Tab Bar with AI connection status
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'Local Analysis', icon: Icon(Icons.analytics)),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.psychology),
                      const SizedBox(width: 8),
                      const Text('AI Analysis'),
                      const SizedBox(width: 8),
                      if (_isCheckingConnection)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _isAIConnected ? Icons.cloud : Icons.cloud_off,
                          size: 16,
                          color: _isAIConnected ? Colors.green : Colors.red,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLocalAnalysisTab(currentSensorData, nodes),
                _buildAIAnalysisTab(currentSensorData, nodes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.psychology,
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
                    'AI Analytics Dashboard',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Smart insights and predictions for your agriculture system',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildLocalAnalysisTab(
    AsyncValue<Map<String, SensorData>> currentSensorData,
    AsyncValue<List<AgriNode>> nodes,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickInsights(currentSensorData),
          const SizedBox(height: 20),
          _buildEnvironmentAnalysis(currentSensorData),
          const SizedBox(height: 20),
          _buildSystemHealth(nodes),
        ],
      ),
    );
  }

  Widget _buildQuickInsights(
    AsyncValue<Map<String, SensorData>> sensorDataAsync,
  ) {
    return sensorDataAsync.when(
      data: (sensorDataMap) {
        if (sensorDataMap.isEmpty) {
          return _buildNoDataCard();
        }

        final insights = _generateQuickInsights(sensorDataMap);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Insights',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: insights.length,
              itemBuilder: (context, index) {
                final insight = insights[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          insight['icon'] as IconData,
                          color: insight['color'] as Color,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                insight['title'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                insight['description'] as String,
                                style: const TextStyle(fontSize: 10),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorCard(error.toString()),
    );
  }

  Widget _buildEnvironmentAnalysis(
    AsyncValue<Map<String, SensorData>> sensorDataAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Environment Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            sensorDataAsync.when(
              data: (sensorDataMap) {
                final analysis = _analyzeEnvironment(sensorDataMap);
                return Column(
                  children: [
                    _buildAnalysisItem('Temperature', analysis['temperature']),
                    _buildAnalysisItem('Humidity', analysis['humidity']),
                    _buildAnalysisItem('Soil Moisture', analysis['soil']),
                  ],
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => Text('Error: $error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemHealth(AsyncValue<List<AgriNode>> nodesAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'System Health',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            nodesAsync.when(
              data: (nodes) {
                final health = _analyzeSystemHealth(nodes);
                return Column(
                  children: [
                    _buildHealthItem(
                      'Network Connectivity',
                      health['connectivity'],
                      health['connectivityColor'],
                    ),
                    _buildHealthItem(
                      'Node Status',
                      health['nodeStatus'],
                      health['nodeStatusColor'],
                    ),
                    _buildHealthItem(
                      'Data Quality',
                      health['dataQuality'],
                      health['dataQualityColor'],
                    ),
                  ],
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => Text('Error: $error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisItem(String label, Map<String, dynamic> analysis) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            analysis['icon'] as IconData,
            color: analysis['color'] as Color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  analysis['status'] as String,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthItem(String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(status, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIAnalysisTab(
    AsyncValue<Map<String, SensorData>> currentSensorData,
    AsyncValue<List<AgriNode>> nodes,
  ) {
    if (!_isAIConnected) {
      return _buildAIConnectionError();
    }

    return _buildAIAnalysisContent(currentSensorData, nodes);
  }

  Widget _buildAIConnectionError() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Analysis Unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Cannot connect to the AI analysis server. Please check:',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Google Colab notebook is running'),
                  Text('• ngrok tunnel is active'),
                  Text('• ngrok URL is configured in settings'),
                  Text('• Internet connection is available'),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _checkAIConnection,
                child: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIAnalysisContent(
    AsyncValue<Map<String, SensorData>> currentSensorData,
    AsyncValue<List<AgriNode>> nodes,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Analysis Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.psychology, color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI-Powered Analysis',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Advanced machine learning insights from Google Colab',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.cloud_done, color: Colors.green, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // AI Analysis Results
          _buildAIAnalysisResults(currentSensorData, nodes),
        ],
      ),
    );
  }

  Widget _buildAIAnalysisResults(
    AsyncValue<Map<String, SensorData>> currentSensorData,
    AsyncValue<List<AgriNode>> nodes,
  ) {
    return currentSensorData.when(
      data: (sensorDataMap) => nodes.when(
        data: (nodesList) => FutureBuilder<Map<String, dynamic>?>(
          future: AIAnalysisService.instance.performAIAnalysis(
            sensorData: sensorDataMap.values.toList(),
            nodes: nodesList,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Performing AI analysis...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.error, color: Colors.orange, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'AI Analysis Failed',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Falling back to local analysis. The AI server may be temporarily unavailable.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          _tabController.animateTo(
                            0,
                          ); // Switch to local analysis
                        },
                        child: const Text('View Local Analysis'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final aiResults = snapshot.data!;
            return _buildAIResultsDisplay(aiResults);
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text('Error loading nodes: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error loading sensor data: $error'),
    );
  }

  Widget _buildAIResultsDisplay(Map<String, dynamic> aiResults) {
    final analysis = aiResults['analysis'] as Map<String, dynamic>?;

    if (analysis == null) {
      return _buildBasicAIResults(aiResults);
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Sri Lankan Agriculture Header
          Card(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.withValues(alpha: 0.1),
                    Colors.blue.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('🇱🇰', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sri Lankan Agriculture AI Analysis',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${analysis['farm_location'] ?? 'Unknown'} • ${analysis['climate_zone'] ?? 'Unknown Zone'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Current Conditions Overview
          _buildCurrentConditionsCard(analysis),

          const SizedBox(height: 16),

          // Yield Prediction and Harvest Forecast
          Row(
            children: [
              Expanded(child: _buildYieldPredictionCard(analysis)),
              const SizedBox(width: 8),
              Expanded(child: _buildHarvestForecastCard(analysis)),
            ],
          ),

          const SizedBox(height: 16),

          // Climate and Monsoon Analysis
          _buildClimateAnalysisCard(analysis),

          const SizedBox(height: 16),

          // Disease Risk Assessment
          _buildDiseaseRiskCard(analysis),

          const SizedBox(height: 16),

          // Weather Forecast
          _buildWeatherForecastCard(analysis),

          const SizedBox(height: 16),

          // Sri Lankan Specific Recommendations
          _buildSriLankanRecommendationsCard(analysis),

          const SizedBox(height: 16),

          // Alerts and Notifications
          _buildAlertsCard(analysis),
        ],
      ),
    );
  }

  Widget _buildBasicAIResults(Map<String, dynamic> aiResults) {
    return Column(
      children: [
        // AI Insights Summary
        if (aiResults['insights'] != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Insights',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...((aiResults['insights'] as List?) ?? []).map(
                    (insight) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb, color: Colors.amber, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(insight.toString())),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),

        // AI Recommendations
        if (aiResults['recommendations'] != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Recommendations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...((aiResults['recommendations'] as List?) ?? []).map(
                    (rec) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.recommend, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (rec['title'] != null)
                                  Text(
                                    rec['title'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (rec['description'] != null)
                                  Text(rec['description'].toString()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentConditionsCard(Map<String, dynamic> analysis) {
    final conditions = analysis['current_conditions'] as Map<String, dynamic>?;
    if (conditions == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thermostat, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Current Farm Conditions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildConditionItem(
                    '🌡️',
                    'Temperature',
                    '${conditions['average_temperature']?.toStringAsFixed(1) ?? 'N/A'}°C',
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildConditionItem(
                    '💧',
                    'Humidity',
                    '${conditions['average_humidity']?.toStringAsFixed(1) ?? 'N/A'}%',
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildConditionItem(
                    '🌱',
                    'Soil Moisture',
                    '${conditions['average_soil_moisture']?.toStringAsFixed(1) ?? 'N/A'}%',
                    Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionItem(
    String emoji,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildYieldPredictionCard(Map<String, dynamic> analysis) {
    final yieldPred = analysis['yield_prediction'] as Map<String, dynamic>?;
    if (yieldPred == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌾', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  'Yield Prediction',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${yieldPred['predicted_yield_per_acre']?.toStringAsFixed(1) ?? 'N/A'} ${yieldPred['yield_unit'] ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${yieldPred['yield_category'] ?? 'Unknown'} • ${yieldPred['confidence_percentage']?.toStringAsFixed(0) ?? 'N/A'}% confident',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (yieldPred['seed_variety'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Variety: ${yieldPred['seed_variety']}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHarvestForecastCard(Map<String, dynamic> analysis) {
    final harvestForecast =
        analysis['harvest_forecast'] as Map<String, dynamic>?;
    if (harvestForecast == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📅', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  'Harvest Forecast',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${harvestForecast['days_to_harvest'] ?? 'N/A'} days',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.purple[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${harvestForecast['growth_stage_name'] ?? 'Unknown stage'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (harvestForecast['harvest_season'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '${harvestForecast['harvest_season']}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClimateAnalysisCard(Map<String, dynamic> analysis) {
    final climateAnalysis =
        analysis['climate_analysis'] as Map<String, dynamic>?;
    final monsoonAnalysis =
        analysis['monsoon_analysis'] as Map<String, dynamic>?;

    if (climateAnalysis == null && monsoonAnalysis == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Climate & Monsoon Analysis',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (climateAnalysis != null) ...[
              _buildClimateInfo(
                'Climate Zone',
                climateAnalysis['climate_zone']?.toString() ?? 'Unknown',
              ),
              _buildClimateInfo(
                'Temperature Status',
                climateAnalysis['current_temperature_status']?.toString() ??
                    'Unknown',
              ),
              _buildClimateInfo(
                'Humidity Status',
                climateAnalysis['current_humidity_status']?.toString() ??
                    'Unknown',
              ),
            ],

            if (monsoonAnalysis != null) ...[
              const SizedBox(height: 12),
              _buildClimateInfo(
                'Active Monsoons',
                (monsoonAnalysis['active_monsoons'] as List?)?.join(', ') ??
                    'None',
              ),
              _buildClimateInfo(
                'Rainfall Level',
                monsoonAnalysis['expected_rainfall_level']?.toString() ??
                    'Unknown',
              ),
              if (monsoonAnalysis['is_peak_rainfall_period'] == true)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.water_drop, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Peak monsoon season active',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClimateInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildDiseaseRiskCard(Map<String, dynamic> analysis) {
    final diseaseRisk = analysis['disease_risk'] as Map<String, dynamic>?;
    if (diseaseRisk == null) return const SizedBox.shrink();

    final riskLevel = diseaseRisk['overall_risk_level'] ?? 0;
    final riskCategory = diseaseRisk['risk_category']?.toString() ?? 'Unknown';

    Color riskColor = Colors.green;
    if (riskLevel > 60) {
      riskColor = Colors.red;
    } else if (riskLevel > 30) {
      riskColor = Colors.orange;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, color: riskColor),
                const SizedBox(width: 8),
                Text(
                  'Disease Risk Assessment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$riskCategory Risk',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: riskColor,
                        ),
                      ),
                      Text('${riskLevel.toStringAsFixed(0)}% risk level'),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: LinearProgressIndicator(
                    value: riskLevel / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                  ),
                ),
              ],
            ),
            if (diseaseRisk['prevention_measures'] != null) ...[
              const SizedBox(height: 12),
              Text(
                'Prevention Measures:',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              ...((diseaseRisk['prevention_measures'] as List?) ?? []).map(
                (measure) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(measure.toString())),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherForecastCard(Map<String, dynamic> analysis) {
    final weatherForecast =
        analysis['weather_forecast'] as Map<String, dynamic>?;
    if (weatherForecast == null) return const SizedBox.shrink();

    final forecastDays = weatherForecast['forecast_days'] as List?;
    if (forecastDays == null || forecastDays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  '7-Day Weather Forecast',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: math.min(7, forecastDays.length),
                itemBuilder: (context, index) {
                  final day = forecastDays[index] as Map<String, dynamic>;
                  return Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateTime.parse(day['date'] ?? '').day.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day['temperature_celsius']?.toStringAsFixed(0) ?? 'N/A'}°C',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${day['humidity_percentage']?.toStringAsFixed(0) ?? 'N/A'}%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          '${day['rainfall_probability']?.toStringAsFixed(0) ?? 'N/A'}%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSriLankanRecommendationsCard(Map<String, dynamic> analysis) {
    final recommendations = analysis['recommendations'] as List?;
    if (recommendations == null || recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🇱🇰', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  'Sri Lankan Agriculture Recommendations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...recommendations.map((rec) {
              final recommendation = rec as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(
                              recommendation['priority']?.toString(),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            recommendation['priority']?.toString() ?? 'Normal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            recommendation['category']?.toString() ?? 'General',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(recommendation['action']?.toString() ?? ''),
                    if (recommendation['sri_lankan_context'] != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info,
                              size: 16,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                recommendation['sri_lankan_context'].toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.amber[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsCard(Map<String, dynamic> analysis) {
    final alerts = analysis['alerts'] as List?;
    if (alerts == null || alerts.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Alerts & Notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...alerts.map((alert) {
              final alertData = alert as Map<String, dynamic>;
              final alertType = alertData['type']?.toString() ?? 'Info';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getAlertColor(alertType).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getAlertColor(alertType).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getAlertIcon(alertType),
                      color: _getAlertColor(alertType),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alertData['message']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (alertData['action'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Action: ${alertData['action']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  Color _getAlertColor(String alertType) {
    switch (alertType.toLowerCase()) {
      case 'warning':
        return Colors.orange;
      case 'alert':
        return Colors.red;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getAlertIcon(String alertType) {
    switch (alertType.toLowerCase()) {
      case 'warning':
        return Icons.warning;
      case 'alert':
        return Icons.error;
      case 'info':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Widget _buildNoDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.sensors_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No sensor data available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to your smart agriculture devices to see analytics',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text('Error: $error')),
          ],
        ),
      ),
    );
  }

  // Analysis Logic Methods
  List<Map<String, dynamic>> _generateQuickInsights(
    Map<String, SensorData> sensorDataMap,
  ) {
    List<Map<String, dynamic>> insights = [];

    if (sensorDataMap.isEmpty) return insights;

    final allData = sensorDataMap.values.toList();

    // Temperature insights
    final avgTemp =
        allData.map((d) => d.temperature).reduce((a, b) => a + b) /
        allData.length;
    insights.add({
      'title': 'Avg Temperature',
      'description': '${avgTemp.toStringAsFixed(1)}°C',
      'icon': Icons.thermostat,
      'color': avgTemp > 30
          ? Colors.red
          : avgTemp < 15
          ? Colors.blue
          : Colors.green,
    });

    // Humidity insights
    final avgHumidity =
        allData.map((d) => d.humidity).reduce((a, b) => a + b) / allData.length;
    insights.add({
      'title': 'Avg Humidity',
      'description': '${avgHumidity.toStringAsFixed(1)}%',
      'icon': Icons.water_drop,
      'color': avgHumidity > 80
          ? Colors.blue
          : avgHumidity < 40
          ? Colors.orange
          : Colors.green,
    });

    // Soil moisture insights
    final avgSoil =
        allData.map((d) => d.soilMoisture).reduce((a, b) => a + b) /
        allData.length;
    insights.add({
      'title': 'Avg Soil Moisture',
      'description': '${avgSoil.toStringAsFixed(0)}%',
      'icon': Icons.grass,
      'color': avgSoil < 30
          ? Colors.red
          : avgSoil > 70
          ? Colors.blue
          : Colors.green,
    });

    // Active devices
    insights.add({
      'title': 'Active Devices',
      'description': '${allData.length} online',
      'icon': Icons.devices,
      'color': Colors.green,
    });

    return insights;
  }

  Map<String, dynamic> _analyzeEnvironment(
    Map<String, SensorData> sensorDataMap,
  ) {
    if (sensorDataMap.isEmpty) {
      return {
        'temperature': {
          'icon': Icons.thermostat,
          'color': Colors.grey,
          'status': 'No data',
        },
        'humidity': {
          'icon': Icons.water_drop,
          'color': Colors.grey,
          'status': 'No data',
        },
        'soil': {
          'icon': Icons.grass,
          'color': Colors.grey,
          'status': 'No data',
        },
      };
    }

    final allData = sensorDataMap.values.toList();
    final avgTemp =
        allData.map((d) => d.temperature).reduce((a, b) => a + b) /
        allData.length;
    final avgHumidity =
        allData.map((d) => d.humidity).reduce((a, b) => a + b) / allData.length;
    final avgSoil =
        allData.map((d) => d.soilMoisture).reduce((a, b) => a + b) /
        allData.length;

    return {
      'temperature': {
        'icon': Icons.thermostat,
        'color': avgTemp > 30
            ? Colors.red
            : avgTemp < 15
            ? Colors.blue
            : Colors.green,
        'status': _getTemperatureAnalysis(avgTemp),
      },
      'humidity': {
        'icon': Icons.water_drop,
        'color': avgHumidity > 80
            ? Colors.blue
            : avgHumidity < 40
            ? Colors.orange
            : Colors.green,
        'status': _getHumidityAnalysis(avgHumidity),
      },
      'soil': {
        'icon': Icons.grass,
        'color': avgSoil < 30
            ? Colors.red
            : avgSoil > 70
            ? Colors.blue
            : Colors.green,
        'status': _getSoilMoistureAnalysis(avgSoil),
      },
    };
  }

  Map<String, dynamic> _analyzeSystemHealth(List<AgriNode> nodes) {
    final onlineNodes = nodes.where((n) => n.isOnline).length;
    final totalNodes = nodes.length;

    return {
      'connectivity': totalNodes > 0 ? 'Good' : 'No devices',
      'connectivityColor': totalNodes > 0 ? Colors.green : Colors.red,
      'nodeStatus': '$onlineNodes/$totalNodes online',
      'nodeStatusColor': onlineNodes == totalNodes
          ? Colors.green
          : onlineNodes > 0
          ? Colors.orange
          : Colors.red,
      'dataQuality': 'Excellent',
      'dataQualityColor': Colors.green,
    };
  }

  String _getTemperatureAnalysis(double temp) {
    if (temp < 10) return 'Too cold for most crops';
    if (temp < 20) return 'Cool - suitable for cool season crops';
    if (temp < 30) return 'Optimal for most vegetables';
    return 'Hot - may stress plants, increase watering';
  }

  String _getHumidityAnalysis(double humidity) {
    if (humidity < 40) return 'Low - may need irrigation';
    if (humidity < 70) return 'Good - optimal for plant growth';
    if (humidity < 90) return 'High - monitor for fungal diseases';
    return 'Very high - risk of plant diseases';
  }

  String _getSoilMoistureAnalysis(double moisture) {
    if (moisture < 30) return 'Critical: Irrigation needed immediately';
    if (moisture < 50) return 'Good: Monitor and water as needed';
    if (moisture < 70) return 'Excellent: Optimal moisture levels';
    return 'Warning: Risk of root rot from overwatering';
  }
}
