import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateRangePicker extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final String? helpText;

  const DateRangePicker({
    super.key,
    this.initialDateRange,
    this.firstDate,
    this.lastDate,
    required this.onDateRangeChanged,
    this.helpText,
  });

  @override
  State<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends State<DateRangePicker> {
  DateTimeRange? _selectedDateRange;
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  @override
  void initState() {
    super.initState();
    _selectedDateRange = widget.initialDateRange;
  }

  @override
  void didUpdateWidget(DateRangePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDateRange != oldWidget.initialDateRange) {
      _selectedDateRange = widget.initialDateRange;
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: widget.firstDate ?? DateTime(2020),
      lastDate: widget.lastDate ?? DateTime.now(),
      initialDateRange: _selectedDateRange,
      helpText: widget.helpText ?? 'Select Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      saveText: 'Apply',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      widget.onDateRangeChanged(picked);
    }
  }

  void _clearDateRange() {
    setState(() {
      _selectedDateRange = null;
    });
    widget.onDateRangeChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Date Range Filter',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_selectedDateRange != null)
                  IconButton(
                    onPressed: _clearDateRange,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear date range',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _selectedDateRange != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'From: ${_dateFormat.format(_selectedDateRange!.start)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'To: ${_dateFormat.format(_selectedDateRange!.end)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            )
                          : Text(
                              'Tap to select date range',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                    ),
                    Icon(
                      Icons.calendar_today,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedDateRange != null) ...[
              const SizedBox(height: 8),
              Text(
                'Duration: ${_selectedDateRange!.duration.inDays + 1} days',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class QuickDateRangeSelector extends StatelessWidget {
  final ValueChanged<DateTimeRange?> onDateRangeChanged;

  const QuickDateRangeSelector({super.key, required this.onDateRangeChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Select',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _QuickSelectChip(
                  label: 'Today',
                  onTap: () => onDateRangeChanged(
                    DateTimeRange(
                      start: today,
                      end: today.add(const Duration(days: 1, milliseconds: -1)),
                    ),
                  ),
                ),
                _QuickSelectChip(
                  label: 'Yesterday',
                  onTap: () {
                    final yesterday = today.subtract(const Duration(days: 1));
                    onDateRangeChanged(
                      DateTimeRange(
                        start: yesterday,
                        end: yesterday.add(
                          const Duration(days: 1, milliseconds: -1),
                        ),
                      ),
                    );
                  },
                ),
                _QuickSelectChip(
                  label: 'Last 7 days',
                  onTap: () => onDateRangeChanged(
                    DateTimeRange(
                      start: today.subtract(const Duration(days: 6)),
                      end: today.add(const Duration(days: 1, milliseconds: -1)),
                    ),
                  ),
                ),
                _QuickSelectChip(
                  label: 'Last 30 days',
                  onTap: () => onDateRangeChanged(
                    DateTimeRange(
                      start: today.subtract(const Duration(days: 29)),
                      end: today.add(const Duration(days: 1, milliseconds: -1)),
                    ),
                  ),
                ),
                _QuickSelectChip(
                  label: 'This month',
                  onTap: () {
                    final firstDayOfMonth = DateTime(now.year, now.month, 1);
                    onDateRangeChanged(
                      DateTimeRange(
                        start: firstDayOfMonth,
                        end: today.add(
                          const Duration(days: 1, milliseconds: -1),
                        ),
                      ),
                    );
                  },
                ),
                _QuickSelectChip(
                  label: 'All time',
                  onTap: () => onDateRangeChanged(null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSelectChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickSelectChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
