import 'dart:async';

import 'package:flutter/material.dart';

const _weekdayNames = <String>[
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

const _monthNames = <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// A compact real-time clock bar showing the current weekday, date and time.
///
/// It updates every second with a per-second [Timer] (ticking the whole widget
/// only, so the rest of the screen is never rebuilt), so a cashier can always
/// see the current time at a glance. Place it at the top-left of a page by
/// aligning it to the start of a [Row] / [Column].
class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final scheme = Theme.of(context).colorScheme;
    final dateText = '${_weekdayNames[now.weekday - 1]}, '
        '${now.day} ${_monthNames[now.month - 1]} ${now.year}';
    final timeText =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(Icons.watch_later_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              dateText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            timeText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}