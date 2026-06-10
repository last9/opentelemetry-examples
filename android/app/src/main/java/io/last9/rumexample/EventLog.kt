package io.last9.rumexample

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Global event log shared across every screen — mirrors the reference app's
 * `addLog` / `useLogs`. SDK calls and route changes append here, and the
 * Profile screen's debug-log modal renders the live list.
 *
 * Backed by a Compose [SnapshotStateList] so any composable reading [entries]
 * recomposes when a new entry is added. Newest entry is kept at index 0 and the
 * list is capped at 100 entries (same as the reference).
 */
object EventLog {
    data class Entry(val id: Long, val ts: String, val msg: String)

    private var nextId = 0L
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

    /** Observable, newest-first list of log entries. */
    val entries: SnapshotStateList<Entry> = mutableStateListOf()

    /** Append a log line. Safe to call from any thread (posts to the list). */
    @Synchronized
    fun add(msg: String) {
        val entry = Entry(id = ++nextId, ts = timeFormat.format(Date()), msg = msg)
        entries.add(0, entry)
        if (entries.size > 100) {
            // Drop oldest entries beyond the 100 cap.
            while (entries.size > 100) entries.removeAt(entries.size - 1)
        }
    }
}
