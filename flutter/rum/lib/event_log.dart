import 'package:flutter/foundation.dart';

/// A single entry in the global event log.
class LogEntry {
  LogEntry(this.id, this.ts, this.msg);

  final int id;
  final String ts;
  final String msg;
}

/// Global, app-wide event log shared across every screen.
///
/// Mirrors the reference app's module-level `addLog` + `useLogs` pattern: SDK
/// calls, route changes, and network outcomes append here, and the Profile
/// tab's debug sheet renders the list reactively via the [ValueNotifier].
class EventLog {
  EventLog._();

  static final ValueNotifier<List<LogEntry>> entries =
      ValueNotifier<List<LogEntry>>(<LogEntry>[]);

  static int _nextId = 0;

  /// Append a message to the log (most-recent-first, capped at 100 entries).
  static void add(String msg) {
    final DateTime now = DateTime.now();
    final String ts =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    final LogEntry entry = LogEntry(++_nextId, ts, msg);
    final List<LogEntry> next = <LogEntry>[
      entry,
      ...entries.value.take(99),
    ];
    entries.value = next;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// Convenience top-level alias mirroring the reference's `addLog(...)`.
void addLog(String msg) => EventLog.add(msg);
