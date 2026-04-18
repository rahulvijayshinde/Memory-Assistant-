package com.example.memory_assistant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.util.Locale
import java.util.UUID

/**
 * MemoryDatabase — Android-native SQLite storage for the Memory Assistant.
 *
 * Schema mirrors the Python storage/db.py schema so data is compatible.
 * This provides REAL data persistence for the MethodChannel bridge,
 * replacing the stub responses that never saved anything.
 *
 * Tables: conversations, events, summaries
 */
class MemoryDatabase(private val appContext: Context) : SQLiteOpenHelper(
    appContext, "memory.db", null, DB_VERSION
) {
    companion object {
        const val TAG = "WBrain.DB"
        const val DB_VERSION = 4

        fun newId(): String = UUID.randomUUID().toString()
    }

    override fun onCreate(db: SQLiteDatabase) {
        Log.i(TAG, "Creating database tables...")

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS conversations (
                id          TEXT PRIMARY KEY,
                timestamp   TEXT NOT NULL,
                raw_text    TEXT,
                audio_path  TEXT,
                location_name TEXT,
                location_lat  REAL,
                location_lon  REAL,
                source      TEXT DEFAULT 'text'
            )
        """)

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS events (
                id              TEXT PRIMARY KEY,
                conversation_id TEXT,
                type            TEXT NOT NULL,
                description     TEXT,
                raw_date        TEXT,
                raw_time        TEXT,
                event_datetime  TEXT,
                recorded_at     TEXT DEFAULT CURRENT_TIMESTAMP,
                location_name   TEXT,
                has_schedule    INTEGER DEFAULT 0,
                person          TEXT,
                importance      INTEGER DEFAULT 0,
                fingerprint     TEXT UNIQUE,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            )
        """)

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS summaries (
                id              TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                summary         TEXT,
                key_points      TEXT,
                created_at      TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            )
        """)

        db.execSQL("CREATE INDEX IF NOT EXISTS idx_events_conv ON events(conversation_id)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_events_type ON events(type)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_events_dt   ON events(event_datetime)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_events_fp   ON events(fingerprint)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_summaries_conv ON summaries(conversation_id)")

        Log.i(TAG, "Database tables created ✓")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE events ADD COLUMN event_datetime TEXT")
            db.execSQL("ALTER TABLE events ADD COLUMN recorded_at TEXT DEFAULT CURRENT_TIMESTAMP")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_events_dt ON events(event_datetime)")

            db.execSQL(
                """
                UPDATE events
                SET event_datetime = CASE
                    WHEN raw_date IS NOT NULL AND TRIM(raw_date) != ''
                         AND raw_time IS NOT NULL AND TRIM(raw_time) != ''
                    THEN TRIM(raw_date) || ' ' || TRIM(raw_time)
                    WHEN raw_date IS NOT NULL AND TRIM(raw_date) != ''
                    THEN TRIM(raw_date) || ' 09:00'
                    ELSE strftime('%Y-%m-%d %H:%M', 'now', 'localtime')
                END
                WHERE event_datetime IS NULL OR TRIM(event_datetime) = ''
                """.trimIndent()
            )

            db.execSQL(
                """
                UPDATE events
                SET recorded_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')
                WHERE recorded_at IS NULL OR TRIM(recorded_at) = ''
                """.trimIndent()
            )
        }

        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE conversations ADD COLUMN location_name TEXT")
            db.execSQL("ALTER TABLE conversations ADD COLUMN location_lat REAL")
            db.execSQL("ALTER TABLE conversations ADD COLUMN location_lon REAL")
            db.execSQL("ALTER TABLE events ADD COLUMN location_name TEXT")

            // Best-effort backfill: attach each event to its conversation location.
            db.execSQL(
                """
                UPDATE events
                SET location_name = (
                    SELECT c.location_name
                    FROM conversations c
                    WHERE c.id = events.conversation_id
                )
                WHERE location_name IS NULL OR TRIM(location_name) = ''
                """.trimIndent()
            )
        }

        if (oldVersion < 4) {
            db.execSQL("ALTER TABLE events ADD COLUMN has_schedule INTEGER DEFAULT 0")

            // Best-effort backfill: events with recognizable explicit date/time cues become scheduled.
            db.execSQL(
                """
                UPDATE events
                SET has_schedule = CASE
                    WHEN (raw_date IS NOT NULL AND TRIM(raw_date) != '')
                      OR (raw_time IS NOT NULL AND TRIM(raw_time) != '')
                    THEN 1
                    ELSE 0
                END
                """.trimIndent()
            )
        }
    }

    private fun nowDate(): String {
        return java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            .format(java.util.Date())
    }

    private fun nowTime(): String {
        return java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
            .format(java.util.Date())
    }

    private fun nowIsoDateTime(): String {
        return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())
    }

    // ── Save ─────────────────────────────────────────────────

    fun saveConversation(
        text: String,
        source: String = "text",
        locationName: String? = null,
        locationLat: Double? = null,
        locationLon: Double? = null,
    ): String {
        val id = newId()
        val timestamp = java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US
        ).format(java.util.Date())

        val values = ContentValues().apply {
            put("id", id)
            put("timestamp", timestamp)
            put("raw_text", text)
            put("location_name", locationName)
            put("location_lat", locationLat)
            put("location_lon", locationLon)
            put("source", source)
        }
        writableDatabase.insertWithOnConflict(
            "conversations", null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
        Log.i(TAG, "✓ Saved conversation ${id.take(8)}... (${text.length} chars, source=$source)")
        return id
    }

    fun saveEvent(
        convId: String, type: String, description: String,
        date: String? = null,
        time: String? = null,
        person: String? = null,
        locationName: String? = null,
    ): String? {
        val providedDate = date?.trim().takeUnless { it.isNullOrBlank() }
        val providedTime = time?.trim().takeUnless { it.isNullOrBlank() }
        val hintedDate = extractDateHint(description)
        val hintedTime = extractTimeHint(description)

        val effectiveDate = providedDate
            ?: hintedDate
            ?: nowDate()
        val effectiveTime = providedTime
            ?: hintedTime
            ?: nowTime()
        val effectivePerson = person?.trim().takeUnless { it.isNullOrBlank() }
            ?: extractPersonHint(description)
        val effectiveDateTime = "$effectiveDate $effectiveTime"
        val hasExplicitSchedule = (providedDate != null || providedTime != null || hintedDate != null || hintedTime != null)

        // Deduplicate by fingerprint
        val fp = "$type|${description.lowercase().trim()}|$effectiveDate|$effectiveTime|${effectivePerson ?: ""}"
            .hashCode().toString(16)

        val existing = readableDatabase.rawQuery(
            "SELECT id FROM events WHERE fingerprint = ?", arrayOf(fp)
        )
        if (existing.moveToFirst()) {
            existing.close()
            Log.d(TAG, "  Duplicate skipped: ${description.take(50)}")
            return null
        }
        existing.close()

        val id = newId()
        val values = ContentValues().apply {
            put("id", id)
            put("conversation_id", convId)
            put("type", type)
            put("description", description)
            put("raw_date", effectiveDate)
            put("raw_time", effectiveTime)
            put("event_datetime", effectiveDateTime)
            put("recorded_at", nowIsoDateTime())
            put("location_name", locationName)
            put("has_schedule", if (hasExplicitSchedule) 1 else 0)
            put("person", effectivePerson)
            put("fingerprint", fp)
        }
        writableDatabase.insertWithOnConflict(
            "events", null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
        Log.i(TAG, "  ✓ Saved event: [$type] ${description.take(60)}")
        return id
    }

    fun saveSummary(convId: String, summary: String, keyPoints: String = "") {
        val id = newId()
        val values = ContentValues().apply {
            put("id", id)
            put("conversation_id", convId)
            put("summary", summary)
            put("key_points", keyPoints)
        }
        writableDatabase.insertWithOnConflict(
            "summaries", null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
        Log.i(TAG, "  ✓ Saved summary for conv ${convId.take(8)}")
    }

    // ── Legacy Query (used by queryMemory MethodChannel) ─────

    fun queryMemory(question: String): Map<String, Any> {
        Log.i(TAG, "⤷ queryMemory: '$question'")

        if (question.isBlank()) {
            return mapOf(
                "answer" to "Please ask a specific question about your memory.",
                "results" to emptyList<Map<String, Any>>(),
                "method" to "intent"
            )
        }

        // Use the intent-aware engine so answers stay concise and question-focused.
        val chat = chatWithMemory(question)
        val conciseAnswer = (chat["answer"] as? String)?.trim().orEmpty()

        // Provide structured evidence list for UI/debug without dumping full transcript text.
        val related = collectRelatedMemory(question, limit = 6)

        return mapOf(
            "answer" to conciseAnswer,
            "results" to related,
            "method" to "intent",
            "confidence" to (chat["confidence"] ?: "medium"),
            "mode" to (chat["mode"] ?: "local")
        )
    }

    private fun collectRelatedMemory(question: String, limit: Int = 6): List<Map<String, Any?>> {
        val stopWords = setOf(
            "what", "when", "where", "who", "how", "is", "are", "was", "were",
            "do", "did", "does", "the", "a", "an", "i", "my", "me", "have",
            "has", "had", "about", "for", "any", "tell", "show", "find",
            "can", "you", "please", "know", "memory", "remember"
        )
        val keywords = question.lowercase()
            .split(Regex("[\\s,;.!?]+"))
            .filter { it.length > 2 && it !in stopWords }

        if (keywords.isEmpty()) return emptyList()

        val rows = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()

        for (kw in keywords) {
            // Event hits
            val ev = readableDatabase.rawQuery(
                """SELECT type, description, raw_date, raw_time, person
                   FROM events
                   WHERE description LIKE ? OR type LIKE ? OR person LIKE ?
                   ORDER BY rowid DESC LIMIT 10""",
                arrayOf("%$kw%", "%$kw%", "%$kw%")
            )
            while (ev.moveToNext()) {
                val desc = ev.getString(1) ?: ""
                val key = "e:${cleanDesc(desc).lowercase()}"
                if (desc.isNotBlank() && key !in seen) {
                    seen.add(key)
                    rows.add(
                        mapOf(
                            "source" to "event",
                            "type" to (ev.getString(0) ?: ""),
                            "description" to desc,
                            "raw_date" to ev.getString(2),
                            "raw_time" to ev.getString(3),
                            "person" to ev.getString(4)
                        )
                    )
                }
            }
            ev.close()

            // Summary hits
            val sm = readableDatabase.rawQuery(
                """SELECT summary
                   FROM summaries
                   WHERE summary LIKE ?
                   ORDER BY created_at DESC LIMIT 5""",
                arrayOf("%$kw%")
            )
            while (sm.moveToNext()) {
                val summary = sm.getString(0) ?: ""
                val key = "s:${summary.take(80).lowercase()}"
                if (summary.isNotBlank() && key !in seen) {
                    seen.add(key)
                    rows.add(
                        mapOf(
                            "source" to "summary",
                            "description" to cleanDesc(summary)
                        )
                    )
                }
            }
            sm.close()

            // Conversation raw text hits (snippet only)
            val cv = readableDatabase.rawQuery(
                """SELECT raw_text, timestamp
                   FROM conversations
                   WHERE raw_text LIKE ?
                   ORDER BY rowid DESC LIMIT 5""",
                arrayOf("%$kw%")
            )
            while (cv.moveToNext()) {
                val raw = cv.getString(0) ?: ""
                val key = "c:${raw.take(80).lowercase()}"
                if (raw.isNotBlank() && key !in seen) {
                    seen.add(key)
                    val firstSentence = raw
                        .split(Regex("[.!?\\n]+"))
                        .map { it.trim() }
                        .firstOrNull { it.isNotBlank() }
                        ?.take(160)
                        ?: raw.take(160)
                    rows.add(
                        mapOf(
                            "source" to "conversation",
                            "description" to firstSentence,
                            "timestamp" to cv.getString(1)
                        )
                    )
                }
            }
            cv.close()

            if (rows.size >= limit) break
        }

        return rows.take(limit)
    }

    // ── Stats ────────────────────────────────────────────────

    fun getStats(): Map<String, Any> {
        val convCount = countTable("conversations")
        val eventCount = countTable("events")
        val summaryCount = countTable("summaries")
        Log.i(TAG, "Stats: $convCount convs, $eventCount events, $summaryCount summaries")
        return mapOf(
            "total_conversations" to convCount,
            "total_events" to eventCount,
            "total_summaries" to summaryCount,
            "config" to mapOf("simplified_mode" to false, "low_resource_mode" to false)
        )
    }

    fun getMemoryCount(): Int {
        val count = countTable("conversations") + countTable("events")
        Log.i(TAG, "Memory count: $count")
        return count
    }

    fun getAllEvents(typeFilter: String? = null): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val query = if (typeFilter != null) "SELECT * FROM events WHERE type = ? ORDER BY rowid DESC"
                    else "SELECT * FROM events ORDER BY rowid DESC"
        val args = if (typeFilter != null) arrayOf(typeFilter) else null

        val cursor = readableDatabase.rawQuery(query, args)
        while (cursor.moveToNext()) {
            results.add(mapOf(
                "id" to cursor.getString(cursor.getColumnIndexOrThrow("id")),
                "type" to cursor.getString(cursor.getColumnIndexOrThrow("type")),
                "description" to cursor.getString(cursor.getColumnIndexOrThrow("description")),
                "raw_date" to cursor.getString(cursor.getColumnIndexOrThrow("raw_date")),
                "raw_time" to cursor.getString(cursor.getColumnIndexOrThrow("raw_time")),
                "event_datetime" to cursor.getString(cursor.getColumnIndexOrThrow("event_datetime")),
                "recorded_at" to cursor.getString(cursor.getColumnIndexOrThrow("recorded_at")),
                "location_name" to cursor.getString(cursor.getColumnIndexOrThrow("location_name")),
                "has_schedule" to cursor.getInt(cursor.getColumnIndexOrThrow("has_schedule")),
                "person" to cursor.getString(cursor.getColumnIndexOrThrow("person"))
            ))
        }
        cursor.close()
        return results
    }

    private fun countTable(table: String): Int {
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $table", null)
        cursor.moveToFirst()
        val count = cursor.getInt(0)
        cursor.close()
        return count
    }

    fun getUrgentItems(hours: Int = 48): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val cursor = readableDatabase.rawQuery(
            """SELECT * FROM events
               WHERE type IN ('medication', 'meeting', 'appointment')
               AND importance >= 3
               ORDER BY importance DESC, rowid DESC
               LIMIT 10""", null
        )
        while (cursor.moveToNext()) {
            results.add(mapOf(
                "id" to cursor.getString(cursor.getColumnIndexOrThrow("id")),
                "type" to cursor.getString(cursor.getColumnIndexOrThrow("type")),
                "description" to cursor.getString(cursor.getColumnIndexOrThrow("description")),
                "raw_date" to cursor.getString(cursor.getColumnIndexOrThrow("raw_date")),
                "raw_time" to cursor.getString(cursor.getColumnIndexOrThrow("raw_time")),
                "event_datetime" to cursor.getString(cursor.getColumnIndexOrThrow("event_datetime")),
                "recorded_at" to cursor.getString(cursor.getColumnIndexOrThrow("recorded_at")),
                "location_name" to cursor.getString(cursor.getColumnIndexOrThrow("location_name")),
                "has_schedule" to cursor.getInt(cursor.getColumnIndexOrThrow("has_schedule")),
                "person" to cursor.getString(cursor.getColumnIndexOrThrow("person")),
                "importance" to cursor.getInt(cursor.getColumnIndexOrThrow("importance"))
            ))
        }
        cursor.close()
        Log.i(TAG, "getUrgentItems($hours h) → ${results.size} results")
        return results
    }

    // ═══════════════════════════════════════════════════════════
    //  INTENT-AWARE CHAT WITH DETERMINISTIC REASONING
    // ═══════════════════════════════════════════════════════════

    data class StructuredResult(
        val answer: String,
        val items: List<Map<String, String>>,
        val confidence: String = "medium"
    )

    fun chatWithMemory(question: String): Map<String, Any> {
        Log.i(TAG, "━━━ chatWithMemory (Reasoning) ━━━━━━━━")
        Log.i(TAG, "  Q: '$question'")

        if (countTable("events") == 0 && countTable("conversations") == 0) {
            return mapOf(
                "answer" to "I don't have any memories stored yet. Try recording a conversation first using the Record tab!",
                "related_events" to emptyList<Any>(),
                "confidence" to "high", "mode" to "empty-db"
            )
        }

        // 1. Detect intent
        val intent = detectIntent(question)
        Log.i(TAG, "  Intent: $intent")

        // 2. Execute deterministic logic
        val rawResult = executeIntent(intent, question)
        val result = if (intent == "DAILY_SUMMARY" || intent == "COUNT_EVENTS") {
            rawResult
        } else {
            rawResult.copy(answer = forceSpecificAnswer(question, rawResult))
        }
        Log.i(TAG, "  Items: ${result.items.size}, Answer: ${result.answer.take(50)}...")

        // 3. Try LLM reformat (optional)
        try {
            val llm = formatWithLLM(question, result)
            if (llm != null) {
                Log.i(TAG, "  LLM formatted ✓")
                Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return llm + mapOf("intent" to intent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "  LLM skip: ${e.message}")
        }

        // 4. Use deterministic answer directly (always clean)
        Log.i(TAG, "  Local answer ✓")
        Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        return mapOf(
            "answer" to result.answer,
            "related_events" to emptyList<Any>(),
            "confidence" to result.confidence,
            "mode" to "local", "intent" to intent
        )
    }

    // ── Intent Detection ────────────────────────────────────

    private fun detectIntent(q: String): String {
        val lower = q.lowercase().trim()

        // Count queries
        if (lower.contains("how many") || lower.contains("count") || lower.contains("number of")) {
            if (lower.contains("appointment") || lower.contains("meeting"))
                return "COUNT_APPOINTMENTS"
            return "COUNT_EVENTS"
        }

        // Events on a specific day
        val days = listOf("monday","tuesday","wednesday","thursday","friday","saturday","sunday","tomorrow","today","yesterday")
        val matched = days.firstOrNull { lower.contains(it) }
        if (matched != null && !lower.contains("summary") && !lower.contains("happened")) {
            return "EVENTS_ON_DATE"
        }

        // Summary
        val sumPat = listOf("summary","summarize","what happened","happened today","daily brief","recap","my day","overview","catch me up","update me","brief me")
        if (sumPat.any { lower.contains(it) }) return "DAILY_SUMMARY"

        // Appointment
        val apPat = listOf("appointment","meeting","doctor","visit","schedule","when is my","clinic","hospital","checkup")
        if (apPat.any { lower.contains(it) }) return "APPOINTMENT"

        // Specific time question (prefer direct answer over long lists)
        val timePat = listOf("what time", "when does", "when is it", "start time", "at what time")
        if (timePat.any { lower.contains(it) }) return "TIME_QUERY"

        // Medication
        val medPat = listOf("medicine","medication","pill","tablet","prescription","pharmacy","refill")
        if (medPat.any { lower.contains(it) }) return "MEDICATION"

        // Reminder
        val remPat = listOf("remind","reminder","task","todo","upcoming","don't forget")
        if (remPat.any { lower.contains(it) }) return "REMINDER"

        return "GENERAL"
    }

    // ── Execute Intent (deterministic logic) ────────────────

    private fun executeIntent(intent: String, question: String): StructuredResult = when (intent) {
        "COUNT_APPOINTMENTS" -> intentCountAppointments(question)
        "COUNT_EVENTS"       -> intentCountEvents()
        "EVENTS_ON_DATE"     -> intentEventsOnDate(question)
        "DAILY_SUMMARY"      -> intentDailySummary()
        "TIME_QUERY"         -> intentTimeQuery(question)
        "APPOINTMENT"        -> intentListAppointments()
        "MEDICATION"         -> intentListMedications()
        "REMINDER"           -> intentListReminders()
        else                 -> intentGeneralQuery(question)
    }

    // ── TIME_QUERY ────────────────────────────────────────

    private fun intentTimeQuery(question: String): StructuredResult {
        val q = question.lowercase()
        val stopWords = setOf(
            "what", "when", "time", "does", "is", "it", "start", "at", "the", "a", "an",
            "my", "me", "to", "for", "of", "on", "in", "about", "please"
        )
        val kws = q.split(Regex("[\\s,;.!?]+"))
            .filter { it.length > 2 && it !in stopWords }

        val items = mutableListOf<Map<String, String>>()

        fun collectRows(cursor: android.database.Cursor) {
            while (cursor.moveToNext()) {
                val desc = cursor.getString(0) ?: ""
                val date = cursor.getString(1) ?: ""
                val time = cursor.getString(2) ?: ""
                val person = cursor.getString(3) ?: ""
                val location = cursor.getString(4) ?: ""
                if (time.isNotBlank()) {
                    items.add(
                        mapOf(
                            "description" to desc,
                            "date" to date,
                            "time" to time,
                            "person" to person,
                            "location" to location,
                        )
                    )
                }
            }
        }

        for (kw in kws) {
            val cur = readableDatabase.rawQuery(
                """SELECT description, raw_date, raw_time, person, location_name
                   FROM events
                   WHERE raw_time IS NOT NULL AND trim(raw_time) != ''
                   AND (description LIKE ? OR type LIKE ? OR person LIKE ?)
                   ORDER BY rowid DESC LIMIT 5""",
                arrayOf("%$kw%", "%$kw%", "%$kw%")
            )
            collectRows(cur)
            cur.close()
            if (items.isNotEmpty()) break
        }

        if (items.isEmpty()) {
            val cur = readableDatabase.rawQuery(
                """SELECT description, raw_date, raw_time, person, location_name
                   FROM events
                   WHERE raw_time IS NOT NULL AND trim(raw_time) != ''
                   AND type IN ('meeting','appointment','task','note')
                   ORDER BY rowid DESC LIMIT 1""",
                null
            )
            collectRows(cur)
            cur.close()
        }

        val top = items.firstOrNull()
        val answer = if (top == null) {
            "I couldn't find a specific time in your saved memories yet."
        } else {
            val time = top["time"].orEmpty()
            val date = top["date"].orEmpty()
            val location = top["location"].orEmpty()
            val desc = cleanDesc(top["description"].orEmpty())
            val datePart = if (date.isNotBlank()) " on $date" else ""
            val locationPart = if (location.isNotBlank()) " in $location" else ""
            if (desc.isNotBlank()) "It is at $time$datePart$locationPart for: $desc." else "It is at $time$datePart$locationPart."
        }

        return StructuredResult(answer, items, if (top != null) "high" else "low")
    }

    // ── COUNT_APPOINTMENTS ──────────────────────────────────

    private fun intentCountAppointments(q: String): StructuredResult {
        val items = fetchEvents("meeting")
        val count = items.size
        val answer = if (count == 0) {
            "You don't have any appointments scheduled right now."
        } else {
            val list = formatItemList(items.distinctBy { cleanDesc(it["description"]?:"").take(40) })
            "You have $count appointment${if (count != 1) "s" else ""}:\n\n$list"
        }
        return StructuredResult(answer, items, if (count > 0) "high" else "low")
    }

    private fun intentCountEvents(): StructuredResult {
        val e = countTable("events"); val c = countTable("conversations")
        return StructuredResult("You have $e events from $c conversations stored.", emptyList(), "high")
    }

    // ── EVENTS_ON_DATE ──────────────────────────────────────

    private fun intentEventsOnDate(question: String): StructuredResult {
        val q = question.lowercase()
        val days = listOf("monday","tuesday","wednesday","thursday","friday","saturday","sunday","tomorrow","today","yesterday")
        val target = days.firstOrNull { q.contains(it) } ?: return StructuredResult(
            "I'm not sure which day you mean. Could you say Monday, Sunday, or tomorrow?", emptyList(), "low"
        )

        val items = mutableListOf<Map<String, String>>()
        val cursor = readableDatabase.rawQuery(
            """SELECT description, raw_date, raw_time, person, type, location_name FROM events
               WHERE lower(raw_date) LIKE ? OR lower(description) LIKE ?
               ORDER BY rowid DESC LIMIT 10""",
            arrayOf("%$target%", "%$target%")
        )
        while (cursor.moveToNext()) {
            items.add(mapOf(
                "description" to (cursor.getString(0) ?: ""),
                "date" to (cursor.getString(1) ?: ""),
                "time" to (cursor.getString(2) ?: ""),
                "person" to (cursor.getString(3) ?: ""),
                "location" to (cursor.getString(5) ?: "")
            ))
        }
        cursor.close()

        val dayLabel = target.replaceFirstChar { it.uppercase() }
        val unique = items.distinctBy { cleanDesc(it["description"] ?: "").take(40) }

        val answer = if (unique.isEmpty()) {
            "I don't have anything scheduled for $dayLabel."
        } else {
            "Here's what I have for $dayLabel:\n\n${formatItemList(unique)}"
        }
        return StructuredResult(answer, items, if (items.isNotEmpty()) "high" else "low")
    }

    // ── DAILY_SUMMARY ───────────────────────────────────────

    private fun intentDailySummary(): StructuredResult {
        val appointments = mutableListOf<Map<String, String>>()
        val medications = mutableListOf<Map<String, String>>()
        val tasks = mutableListOf<Map<String, String>>()
        val people = mutableSetOf<String>()
        val items = mutableListOf<Map<String, String>>()

        fun buildSummaryLine(e: Map<String, String>): String {
            val desc = cleanDesc(e["description"].orEmpty())
            val time = e["time"].orEmpty().trim()
            val date = e["date"].orEmpty().trim()
            val location = e["location"].orEmpty().trim()
            val person = e["person"].orEmpty().trim()

            val meta = mutableListOf<String>()
            if (time.isNotEmpty()) meta.add("at $time")
            if (date.isNotEmpty()) meta.add("on $date")
            if (location.isNotEmpty()) meta.add("in $location")
            if (person.isNotEmpty()) meta.add("with $person")

            val suffix = if (meta.isNotEmpty()) " (${meta.joinToString(" ")})" else ""
            return "$desc$suffix"
        }

        val cur = readableDatabase.rawQuery(
            "SELECT type, description, raw_date, raw_time, person, location_name FROM events ORDER BY rowid DESC LIMIT 15", null
        )
        while (cur.moveToNext()) {
            val type = cur.getString(0) ?: ""
            val desc = cleanDesc(cur.getString(1) ?: "")
            val date = cur.getString(2) ?: ""
            val time = cur.getString(3) ?: ""
            val person = cur.getString(4) ?: ""
            val location = cur.getString(5) ?: ""

            val entry = mapOf(
                "type" to type,
                "description" to desc,
                "date" to date,
                "time" to time,
                "person" to person,
                "location" to location,
            )

            if (person.isNotEmpty()) people.add(person)
            when (type) {
                "meeting" -> appointments.add(entry)
                "medication" -> medications.add(entry)
                else -> tasks.add(entry)
            }
            items.add(entry)
        }
        cur.close()

        if (appointments.isEmpty() && medications.isEmpty() && tasks.isEmpty()) {
            return StructuredResult("I don't have enough details for a summary yet. Try recording a conversation first!", emptyList(), "low")
        }

        val sb = StringBuilder("Daily memory brief:\n")
        sb.append("- ${appointments.size} appointment(s)\n")
        sb.append("- ${medications.size} medication item(s)\n")
        sb.append("- ${tasks.size} task/note item(s)\n")

        if (appointments.isNotEmpty()) {
            sb.append("\nAppointments:\n")
            appointments
                .distinctBy { cleanDesc(it["description"].orEmpty()).take(40) }
                .take(4)
                .forEach { sb.append("- ${buildSummaryLine(it)}\n") }
        }
        if (medications.isNotEmpty()) {
            sb.append("\nMedications:\n")
            medications
                .distinctBy { cleanDesc(it["description"].orEmpty()).take(40) }
                .take(4)
                .forEach { sb.append("- ${buildSummaryLine(it)}\n") }
        }
        if (tasks.isNotEmpty()) {
            sb.append("\nTasks and notes:\n")
            tasks
                .distinctBy { cleanDesc(it["description"].orEmpty()).take(40) }
                .take(4)
                .forEach { sb.append("- ${buildSummaryLine(it)}\n") }
        }
        if (people.isNotEmpty()) sb.append("\nPeople mentioned: ${people.joinToString(", ")}\n")
        sb.append("\nIf you want more detail, ask about a person, date, or place.")

        return StructuredResult(sb.toString(), items, "high")
    }

    // ── APPOINTMENT / MEDICATION / REMINDER ──────────────────

    private fun intentListAppointments(): StructuredResult {
        val items = fetchEvents("meeting")
        val unique = items.distinctBy { cleanDesc(it["description"]?:"").take(40) }
        val answer = if (unique.isEmpty()) "I don't have any appointments stored. Record a conversation mentioning your appointments and I'll remember them."
        else "Here are your appointments:\n\n${formatItemList(unique)}"
        return StructuredResult(answer, items, if (items.isNotEmpty()) "high" else "low")
    }

    private fun intentListMedications(): StructuredResult {
        val items = fetchEvents("medication")
        val unique = items.distinctBy { cleanDesc(it["description"]?:"").take(40) }
        val answer = if (unique.isEmpty()) "I don't have any medication information stored yet."
        else "Here are your medications:\n\n${formatItemList(unique)}"
        return StructuredResult(answer, items, if (items.isNotEmpty()) "high" else "low")
    }

    private fun intentListReminders(): StructuredResult {
        val items = mutableListOf<Map<String, String>>()
        val cur = readableDatabase.rawQuery(
            "SELECT description, raw_date, raw_time, person, location_name FROM events WHERE type IN ('task','meeting','medication') ORDER BY rowid DESC LIMIT 10", null
        )
        while (cur.moveToNext()) {
            items.add(
                mapOf(
                    "description" to (cur.getString(0) ?: ""),
                    "date" to (cur.getString(1) ?: ""),
                    "time" to (cur.getString(2) ?: ""),
                    "person" to (cur.getString(3) ?: ""),
                    "location" to (cur.getString(4) ?: ""),
                )
            )
        }
        cur.close()
        val unique = items.distinctBy { cleanDesc(it["description"]?:"").take(40) }
        val answer = if (unique.isEmpty()) "You don't have any upcoming reminders."
        else "Here's what you need to remember:\n\n${formatItemList(unique)}"
        return StructuredResult(answer, items, if (items.isNotEmpty()) "high" else "low")
    }

    // ── GENERAL QUERY ───────────────────────────────────────

    private fun intentGeneralQuery(question: String): StructuredResult {
        val items = mutableListOf<Map<String, String>>()
        val seen = mutableSetOf<String>()
        val stops = setOf("what","when","where","who","how","is","are","was","were","do","did","does","the","a","an","i","my","me","have","has","had","about","for","any","tell","show","find","can","you","please","know","give")
        val kws = question.lowercase().split(Regex("[\\s,;.!?]+")).filter { it.length > 2 && it !in stops }

        for (kw in kws) {
            val cur = readableDatabase.rawQuery(
                "SELECT description, raw_date, raw_time, person, location_name FROM events WHERE description LIKE ? OR person LIKE ? ORDER BY rowid DESC LIMIT 10",
                arrayOf("%$kw%", "%$kw%")
            )
            while (cur.moveToNext()) {
                val d = cur.getString(0) ?: ""
                val key = cleanDesc(d).take(40).lowercase()
                if (key !in seen && key.isNotEmpty()) {
                    seen.add(key)
                    items.add(
                        mapOf(
                            "description" to d,
                            "date" to (cur.getString(1) ?: ""),
                            "time" to (cur.getString(2) ?: ""),
                            "person" to (cur.getString(3) ?: ""),
                            "location" to (cur.getString(4) ?: ""),
                        )
                    )
                }
            }
            cur.close()
            if (items.size >= 5) break
        }

        // Also check summaries
        try {
            val cur = readableDatabase.rawQuery("SELECT summary FROM summaries ORDER BY created_at DESC LIMIT 2", null)
            while (cur.moveToNext()) {
                val s = cur.getString(0) ?: ""
                if (s.isNotEmpty() && s.take(40).lowercase() !in seen) {
                    seen.add(s.take(40).lowercase())
                    items.add(mapOf("description" to s))
                }
            }
            cur.close()
        } catch (_: Exception) {}

        val unique = items.distinctBy { cleanDesc(it["description"]?:"").take(40) }
        val answer = if (unique.isEmpty()) {
            "I couldn't find anything specific about that yet."
        } else {
            val top = cleanDesc(unique.first()["description"].orEmpty())
            if (top.isBlank()) {
                "I found related memory details."
            } else if (unique.size == 1) {
                "I found this in your memory: $top"
            } else {
                "I found ${unique.size} related memory items. The most relevant one is: $top"
            }
        }
        return StructuredResult(answer, items, if (items.isNotEmpty()) "high" else "low")
    }

    // ═══════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════

    private fun fetchEvents(type: String): List<Map<String, String>> {
        val items = mutableListOf<Map<String, String>>()
        val cur = readableDatabase.rawQuery(
            "SELECT description, raw_date, raw_time, person, location_name FROM events WHERE type = ? ORDER BY rowid DESC LIMIT 10",
            arrayOf(type)
        )
        while (cur.moveToNext()) {
            items.add(mapOf(
                "description" to (cur.getString(0) ?: ""),
                "date" to (cur.getString(1) ?: ""),
                "time" to (cur.getString(2) ?: ""),
                "person" to (cur.getString(3) ?: ""),
                "location" to (cur.getString(4) ?: "")
            ))
        }
        cur.close()
        return items
    }

    private fun formatItemList(items: List<Map<String, String>>): String {
        return items.take(5).mapIndexed { i, item ->
            val desc = cleanDesc(item["description"] ?: "")
            val time = item["time"]?.let { if (it.isNotEmpty()) " at $it" else "" } ?: ""
            val date = item["date"]?.let { if (it.isNotEmpty()) " on $it" else "" } ?: ""
            val person = item["person"]?.let { if (it.isNotEmpty()) " with $it" else "" } ?: ""
            val location = item["location"]?.let { if (it.isNotEmpty()) " in $it" else "" } ?: ""
            "${i + 1}. $desc$time$date$location$person"
        }.joinToString("\n")
    }

    /** Aggressively clean ASR transcript artifacts */
    private fun cleanDesc(raw: String): String {
        var text = raw.trim()
        // Remove common ASR fillers
        val fillers = listOf(
            "hello my name is my name is", "my name is my name is",
            "hello my name is", "my name is"
        )
        for (f in fillers) {
            text = text.replace(Regex(f, RegexOption.IGNORE_CASE), "").trim()
        }
        // Remove repeated consecutive words
        val words = text.split(" ").filter { it.isNotBlank() }
        val cleaned = mutableListOf<String>()
        for (w in words) {
            if (cleaned.isEmpty() || cleaned.last().lowercase() != w.lowercase()) cleaned.add(w)
        }
        // Remove repeated consecutive phrases (2-3 word groups)
        text = cleaned.joinToString(" ")
        text = text.replace(Regex("(\\b\\w+(?:\\s+\\w+){0,2})\\s+\\1", RegexOption.IGNORE_CASE), "$1")
        return text.take(120).trim()
    }

    private fun extractTimeHint(text: String): String? {
        if (text.isBlank()) return null
        val m = Regex("\\b\\d{1,2}(?::\\d{2})?\\s?(?:AM|PM|am|pm)\\b").find(text)
        return m?.value?.trim()
    }

    private fun extractDateHint(text: String): String? {
        if (text.isBlank()) return null
        val rel = Regex("\\b(today|tomorrow|yesterday|this weekend|next week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b", RegexOption.IGNORE_CASE)
            .find(text)
            ?.value
            ?.trim()
        if (!rel.isNullOrBlank()) return rel

        val abs = Regex("\\b(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\\s+\\d{1,2}(?:,\\s*\\d{4})?\\b", RegexOption.IGNORE_CASE)
            .find(text)
            ?.value
            ?.trim()
        return abs
    }

    private fun extractPersonHint(text: String): String? {
        if (text.isBlank()) return null

        // Prefer explicit doctor-name patterns first.
        val dr = Regex("\\bDr\\.?\\s+[A-Z][a-z]+\\b").find(text)?.value?.trim()
        if (!dr.isNullOrBlank()) return dr

        // Safer generic person cue patterns.
        val cue = Regex("\\b(?:with|from|for|by)\\s+([A-Z][a-z]{2,}(?:\\s+[A-Z][a-z]{2,})?)\\b").find(text)
        return cue?.groupValues?.getOrNull(1)?.trim()
    }

    private fun detectAnswerStyle(question: String): String {
        val q = question.lowercase()
        return when {
            q.contains("json") -> "json"
            q.contains("bullet") || q.contains("points") || q.contains("list") -> "bullet"
            q.contains("numbered") || q.contains("steps") -> "numbered"
            q.startsWith("is ") || q.startsWith("are ") || q.startsWith("do ") || q.startsWith("does ") ||
                q.startsWith("did ") || q.startsWith("can ") || q.startsWith("was ") || q.startsWith("were ") ||
                q.startsWith("have ") || q.startsWith("has ") -> "yes_no"
            q.contains("short") || q.contains("brief") || q.contains("one line") -> "brief"
            else -> "direct"
        }
    }

    private fun styleInstruction(style: String): String {
        return when (style) {
            "json" -> "Return valid compact JSON only: {\"answer\":\"...\",\"confidence\":\"high|medium|low\"}."
            "bullet" -> "Return 2 to 5 bullet points using '- ' prefix."
            "numbered" -> "Return 2 to 5 numbered lines (1., 2., 3.)."
            "yes_no" -> "Start with 'Yes' or 'No' when possible, then one short clarification sentence."
            "brief" -> "Return one short sentence only."
            else -> "Return 1 to 3 short direct sentences."
        }
    }

    private fun applyStyleFallback(answer: String, style: String, confidence: String): String {
        val clean = answer
            .replace("\r", " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        if (clean.isBlank()) return clean

        return when (style) {
            "json" -> {
                val safe = clean.replace("\"", "'")
                "{\"answer\":\"$safe\",\"confidence\":\"$confidence\"}"
            }
            "bullet" -> clean
                .split(Regex("(?<=[.!?])\\s+|\\n+"))
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(4)
                .joinToString("\n") { "- $it" }
            "numbered" -> clean
                .split(Regex("(?<=[.!?])\\s+|\\n+"))
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(4)
                .mapIndexed { idx, s -> "${idx + 1}. $s" }
                .joinToString("\n")
            "brief" -> clean
                .split(Regex("(?<=[.!?])\\s+"))
                .firstOrNull()
                ?.trim()
                ?: clean
            else -> clean
                .split(Regex("(?<=[.!?])\\s+|\\n+"))
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(2)
                .joinToString(" ")
        }
    }

    private fun makeFriendlyAnswer(answer: String, lang: String, style: String): String {
        if (answer.isBlank()) return answer
        if (lang != "en" || style == "json") return answer

        var out = answer
            .replace("From your memory,", "Got you - from your memory,")
            .replace("I found this in your memory:", "Got it. Here's the key thing I found:")
            .replace("Here are your appointments:", "Quick heads-up, your appointments:")
            .replace("Here are your medications:", "Quick med update:")
            .replace("Here's what you need to remember:", "Here's your quick reminder list:")
            .replace("Here's your summary:", "Quick recap:")
            .replace("I couldn't find anything specific about that yet.", "I couldn't find a clear match for that yet.")

        // Keep replies friendly and concise (avoid long raw-looking dumps).
        if (style == "direct" && out.length > 260) {
            out = out
                .split(Regex("(?<=[.!?])\\s+"))
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(2)
                .joinToString(" ")
        }

        if (style == "direct" && !out.endsWith(".") && !out.endsWith("!") && !out.endsWith("?")) {
            out += "."
        }

        return out
    }

    private fun isLikelyRelevant(question: String, answer: String): Boolean {
        val stops = setOf(
            "what", "when", "where", "who", "how", "is", "are", "was", "were", "do", "does", "did",
            "a", "an", "the", "to", "for", "of", "in", "on", "my", "me", "you", "please", "about"
        )
        val qWords = question.lowercase().split(Regex("[\\s,;.!?]+"))
            .filter { it.length > 2 && it !in stops }
            .toSet()
        if (qWords.isEmpty()) return true

        val aWords = answer.lowercase().split(Regex("[\\s,;.!?]+"))
            .filter { it.length > 2 }
            .toSet()
        val overlap = qWords.count { it in aWords }
        val minOverlap = if (qWords.size >= 4) 2 else 1
        return overlap >= minOverlap ||
            answer.lowercase().contains("don't have") ||
            answer.lowercase().contains("couldn't find") ||
            answer.lowercase().contains("no specific")
    }

    private fun questionKeywords(question: String): Set<String> {
        val stops = setOf(
            "what", "when", "where", "who", "how", "is", "are", "was", "were", "do", "does", "did",
            "a", "an", "the", "to", "for", "of", "in", "on", "my", "me", "you", "please", "about",
            "tell", "show", "find", "give", "any", "have", "has", "had"
        )

        return question.lowercase(Locale.US)
            .split(Regex("[\\s,;.!?]+"))
            .map { it.trim() }
            .filter { it.length > 2 && it !in stops }
            .toSet()
    }

    private fun itemRelevanceScore(item: Map<String, String>, keywords: Set<String>): Int {
        if (keywords.isEmpty()) return 1
        val bag = listOf(
            item["description"].orEmpty(),
            item["person"].orEmpty(),
            item["location"].orEmpty(),
            item["date"].orEmpty(),
            item["time"].orEmpty(),
        ).joinToString(" ").lowercase(Locale.US)

        return keywords.count { kw -> bag.contains(kw) }
    }

    private fun composeSpecificItemAnswer(item: Map<String, String>): String {
        val desc = cleanDesc(item["description"].orEmpty())
        val time = item["time"].orEmpty().trim()
        val date = item["date"].orEmpty().trim()
        val location = item["location"].orEmpty().trim()
        val person = item["person"].orEmpty().trim()

        val meta = mutableListOf<String>()
        if (time.isNotEmpty()) meta.add("at $time")
        if (date.isNotEmpty()) meta.add("on $date")
        if (location.isNotEmpty()) meta.add("in $location")
        if (person.isNotEmpty()) meta.add("with $person")

        val suffix = if (meta.isNotEmpty()) " (${meta.joinToString(" ")})" else ""
        return if (desc.isNotBlank()) {
            "Got it. The most relevant memory is: $desc$suffix."
        } else {
            "I found a relevant memory$suffix."
        }
    }

    private fun noSpecificMatchAnswer(question: String): String {
        val focus = questionKeywords(question).take(3).joinToString(", ")
        return if (focus.isNotBlank()) {
            "I couldn't find a specific memory for: $focus. Try adding a person, date, or place."
        } else {
            "I couldn't find a specific memory for that question. Try adding a person, date, or place."
        }
    }

    private fun forceSpecificAnswer(question: String, result: StructuredResult): String {
        val base = result.answer.trim()
        val keywords = questionKeywords(question)

        if (result.items.isEmpty()) {
            return if (base.isNotBlank() && isLikelyRelevant(question, base)) base else noSpecificMatchAnswer(question)
        }

        val best = result.items.maxByOrNull { itemRelevanceScore(it, keywords) }
        val score = if (best != null) itemRelevanceScore(best, keywords) else 0

        val minimum = if (keywords.size >= 3) 2 else 1
        if (best == null || score < minimum) {
            return noSpecificMatchAnswer(question)
        }

        if (base.isNotBlank() && isLikelyRelevant(question, base) && score >= 2) {
            return base
        }

        return composeSpecificItemAnswer(best)
    }

    private fun collectSpeakerEvidence(limitTurns: Int = 8): List<String> {
        val out = mutableListOf<String>()
        val c = readableDatabase.rawQuery(
            "SELECT raw_text, timestamp FROM conversations ORDER BY rowid DESC LIMIT 4",
            null
        )
        val linePattern = Regex("^([^:\\n]{2,30}):\\s*(.+)$")
        while (c.moveToNext()) {
            val raw = c.getString(0) ?: continue
            val ts = c.getString(1) ?: ""
            raw.split("\n").forEach { line ->
                val m = linePattern.find(line.trim()) ?: return@forEach
                val speaker = m.groupValues[1].trim()
                val text = cleanDesc(m.groupValues[2].trim())
                if (speaker.isNotBlank() && text.isNotBlank()) {
                    out.add("speaker=$speaker | text=$text${if (ts.isNotBlank()) " | time=$ts" else ""}")
                }
            }
            if (out.size >= limitTurns) break
        }
        c.close()
        return out.take(limitTurns)
    }

    private fun removeTranscriptArtifacts(text: String): String {
        if (text.isBlank()) return text

        var cleaned = text
            .replace(Regex("(?im)^\\s*(speaker[_\\s-]*\\d+|spk\\s*\\d+)\\s*:\\s*"), "")
            .replace(Regex("(?im)^\\s*[-*]\\s*"), "")
            .replace(Regex("\\s+"), " ")
            .trim()

        if (cleaned.startsWith("[") && cleaned.endsWith("]") && cleaned.length > 2) {
            cleaned = cleaned.removePrefix("[").removeSuffix("]").trim()
        }
        return cleanDesc(cleaned)
    }

    private fun polishAnswer(question: String, result: StructuredResult): String {
        val base = removeTranscriptArtifacts(result.answer)
        if (base.isBlank()) return base

        val topItem = result.items.firstOrNull()
        if (topItem == null) return base

        val topDesc = removeTranscriptArtifacts(topItem["description"].orEmpty())
        if (topDesc.isBlank()) return base

        val isRawEcho = base.equals(topDesc, ignoreCase = true)
        val isTooShort = base.length < 20
        if (!isRawEcho && !isTooShort) return base

        val time = topItem["time"].orEmpty().trim()
        val date = topItem["date"].orEmpty().trim()
        val location = topItem["location"].orEmpty().trim()
        val person = topItem["person"].orEmpty().trim()

        val parts = mutableListOf<String>()
        if (time.isNotEmpty()) parts.add("at $time")
        if (date.isNotEmpty()) parts.add("on $date")
        if (location.isNotEmpty()) parts.add("in $location")
        if (person.isNotEmpty()) parts.add("with $person")

        val detail = if (parts.isNotEmpty()) " (${parts.joinToString(" ")})" else ""

        val lowerQ = question.lowercase(Locale.US)
        val intro = if (
            lowerQ.startsWith("what") ||
            lowerQ.startsWith("when") ||
            lowerQ.startsWith("who") ||
            lowerQ.startsWith("where") ||
            lowerQ.startsWith("how")
        ) {
            "From your memory,"
        } else {
            "I found this in your memory:"
        }

        return "$intro $topDesc$detail"
    }

    private fun detectLanguage(question: String): String {
        if (question.isBlank()) return "en"
        val q = question.trim()

        if (q.any { it.code in 0x0600..0x06FF }) return "ar"
        if (q.any { it.code in 0x0900..0x097F }) return "hi"

        val lower = q.lowercase(Locale.US)
        return when {
            Regex("\\b(que|cuando|donde|tengo|recuerdo|medicina|cita)\\b").containsMatchIn(lower) -> "es"
            Regex("\\b(quoi|quand|ou|rappel|medicament|rendez-vous)\\b").containsMatchIn(lower) -> "fr"
            Regex("\\b(apa|kapan|dimana|ingat|obat|janji)\\b").containsMatchIn(lower) -> "id"
            else -> "en"
        }
    }

    private fun localizeBoilerplate(answer: String, lang: String): String {
        if (answer.isBlank()) return answer

        return when (lang) {
            "ar" -> answer
                .replace("From your memory,", "من ذاكرتي،")
                .replace("I found this in your memory:", "وجدت هذا في ذاكرتي:")
                .replace("I couldn't find anything specific about that yet.", "لم أجد شيئاً محدداً عن ذلك حتى الآن.")
                .replace("I don't have any memories stored yet. Try recording a conversation first using the Record tab!", "لا توجد ذكريات محفوظة بعد. جرب تسجيل محادثة أولاً من تبويب التسجيل.")
            "hi" -> answer
                .replace("From your memory,", "आपकी यादों के अनुसार,")
                .replace("I found this in your memory:", "मुझे आपकी यादों में यह मिला:")
                .replace("I couldn't find anything specific about that yet.", "मुझे अभी इसके बारे में कुछ खास नहीं मिला।")
                .replace("I don't have any memories stored yet. Try recording a conversation first using the Record tab!", "अभी कोई यादें सेव नहीं हैं। पहले रिकॉर्ड टैब से बातचीत रिकॉर्ड करें।")
            "es" -> answer
                .replace("From your memory,", "Según tu memoria,")
                .replace("I found this in your memory:", "Encontré esto en tu memoria:")
                .replace("I couldn't find anything specific about that yet.", "Todavía no pude encontrar algo específico sobre eso.")
                .replace("I don't have any memories stored yet. Try recording a conversation first using the Record tab!", "Aún no tengo recuerdos guardados. Intenta grabar una conversación primero desde la pestaña de grabación.")
            "fr" -> answer
                .replace("From your memory,", "D'après ta mémoire,")
                .replace("I found this in your memory:", "J'ai trouvé ceci dans ta mémoire :")
                .replace("I couldn't find anything specific about that yet.", "Je n'ai rien trouvé de précis à ce sujet pour le moment.")
                .replace("I don't have any memories stored yet. Try recording a conversation first using the Record tab!", "Je n'ai pas encore de souvenirs enregistrés. Essaie d'abord d'enregistrer une conversation depuis l'onglet Enregistrer.")
            "id" -> answer
                .replace("From your memory,", "Dari memori Anda,")
                .replace("I found this in your memory:", "Saya menemukan ini di memori Anda:")
                .replace("I couldn't find anything specific about that yet.", "Saya belum menemukan hal yang spesifik tentang itu.")
                .replace("I don't have any memories stored yet. Try recording a conversation first using the Record tab!", "Belum ada memori tersimpan. Coba rekam percakapan dulu dari tab Rekam.")
            else -> answer
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  ON-DEVICE FORMATTING (fully offline, no network)
    // ═══════════════════════════════════════════════════════════

    private fun formatWithLLM(question: String, result: StructuredResult): Map<String, Any>? {
        val style = detectAnswerStyle(question)
        val conf = result.confidence.ifBlank { "high" }
        val lang = detectLanguage(question)
        val polished = polishAnswer(question, result)
        val localized = localizeBoilerplate(polished, lang)
        val friendly = makeFriendlyAnswer(localized, lang, style)
        val msg = applyStyleFallback(friendly, style, conf)
        if (!isLikelyRelevant(question, msg)) return null
        return mapOf(
            "answer" to msg,
            "related_events" to emptyList<Any>(),
            "confidence" to conf,
            "mode" to "on_device",
            "language" to lang,
        )
    }
}
