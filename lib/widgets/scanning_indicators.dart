import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

/// 📡 Reusable scanning indicators widget for discovery and data fetching states
class ScanningIndicators extends ConsumerWidget {
  final bool showCompact;
  final EdgeInsetsGeometry? margin;

  const ScanningIndicators({super.key, this.showCompact = false, this.margin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDiscovering = ref.watch(isDiscoveringProvider);
    final isFetchingData = ref.watch(isFetchingDataProvider);

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Discovery indicator
          isDiscovering.when(
            data: (discovering) => discovering
                ? _buildIndicator(
                    context: context,
                    icon: '🔍',
                    title: showCompact ? 'Discovering...' : 'Discovering Nodes',
                    subtitle: showCompact
                        ? null
                        : 'Scanning ESP32 mesh network...',
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    isCompact: showCompact,
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Data fetching indicator
          isFetchingData.when(
            data: (fetching) => fetching
                ? Container(
                    margin: isDiscovering.value == true
                        ? const EdgeInsets.only(top: 8)
                        : null,
                    child: _buildIndicator(
                      context: context,
                      icon: '📡',
                      title: showCompact
                          ? 'Fetching...'
                          : 'Fetching Sensor Data',
                      subtitle: showCompact
                          ? null
                          : 'Reading from all active nodes...',
                      color: Theme.of(context).colorScheme.secondary,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      isCompact: showCompact,
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator({
    required BuildContext context,
    required String icon,
    required String title,
    String? subtitle,
    required Color color,
    required Color backgroundColor,
    required bool isCompact,
  }) {
    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              '$icon $title',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$icon $title',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 📱 Compact version for app bars and small spaces
class CompactScanningIndicator extends StatelessWidget {
  const CompactScanningIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScanningIndicators(
      showCompact: true,
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
