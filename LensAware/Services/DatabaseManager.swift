import Foundation
import SQLite3

// MARK: - DatabaseManager
//
// Actor serialises all public API. `db` and `dbURL` are nonisolated so they
// can be touched in init() (a nonisolated context in Swift 6) and in deinit.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor DatabaseManager {

    nonisolated(unsafe) private var db: OpaquePointer?
    nonisolated         private let dbURL: URL

    // MARK: - Init / deinit

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir     = support.appendingPathComponent("LensAware", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("lensaware.sqlite")
        openDB()
        createAllTables()   // nonisolated — safe to call from nonisolated init
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 1. setupDatabase (public, idempotent)

    func setupDatabase() {
        createAllTables()   // actor-isolated calling nonisolated is always allowed
    }

    // MARK: - 2. saveProfile

    @discardableResult
    func saveProfile(_ profile: Profile) -> Int64 {
        let sql = """
            INSERT INTO profiles (tenant_id, name, profile_type, settings_json)
            VALUES (?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return 0 }
        bindText(stmt, 1, profile.tenantId)
        bindText(stmt, 2, profile.name)
        bindText(stmt, 3, profile.profileType.rawValue)
        if let json = profile.settingsJSON { bindText(stmt, 4, json) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - 3. saveMeal

    func saveMeal(_ meal: MealRecord) {
        let sql = """
            INSERT INTO meals
              (profile_id, timestamp, meal_type, food_items_json, total_calories,
               context, screen_visible, eating_alone, mindful_score, confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int64(stmt, 1, meal.profileId)
        bindText(stmt,          2, iso.string(from: meal.timestamp))
        bindText(stmt,          3, meal.mealType)
        bindText(stmt,          4, meal.foodItemsJSON)
        sqlite3_bind_double(stmt, 5, meal.totalCalories)
        bindText(stmt,          6, meal.context)
        sqlite3_bind_int(stmt,  7, meal.screenVisible ? 1 : 0)
        sqlite3_bind_int(stmt,  8, meal.eatingAlone   ? 1 : 0)
        sqlite3_bind_int(stmt,  9, Int32(meal.mindfulScore))
        sqlite3_bind_double(stmt, 10, meal.confidence)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - 4. saveErgonomicEvent

    func saveErgonomicEvent(_ event: ErgonomicEvent) {
        let sql = """
            INSERT INTO ergonomic_events
              (profile_id, timestamp, monitor_position, assessment, recommendation)
            VALUES (?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int64(stmt, 1, event.profileId)
        bindText(stmt,          2, iso.string(from: event.timestamp))
        bindText(stmt,          3, event.monitorPosition)
        bindText(stmt,          4, event.assessment)
        bindText(stmt,          5, event.recommendation)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - 5. fetchTodayMeals

    func fetchTodayMeals(profileId: Int64) -> [MealRecord] {
        let sql = """
            SELECT id, profile_id, timestamp, meal_type, food_items_json,
                   total_calories, context, screen_visible, eating_alone,
                   mindful_score, confidence
            FROM   meals
            WHERE  profile_id = ? AND date(timestamp) = ?
            ORDER  BY timestamp ASC;
        """
        guard let stmt = prepare(sql) else { return [] }
        sqlite3_bind_int64(stmt, 1, profileId)
        bindText(stmt,          2, todayString())

        var rows: [MealRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(MealRecord(
                id:            sqlite3_column_int64(stmt, 0),
                profileId:     sqlite3_column_int64(stmt, 1),
                timestamp:     iso.date(from: colString(stmt, 2)) ?? Date(),
                mealType:      colString(stmt, 3),
                foodItemsJSON: colString(stmt, 4),
                totalCalories: sqlite3_column_double(stmt, 5),
                context:       colString(stmt, 6),
                screenVisible: sqlite3_column_int(stmt, 7) != 0,
                eatingAlone:   sqlite3_column_int(stmt, 8) != 0,
                mindfulScore:  Int(sqlite3_column_int(stmt, 9)),
                confidence:    sqlite3_column_double(stmt, 10)
            ))
        }
        sqlite3_finalize(stmt)
        return rows
    }

    // MARK: - 6. fetchTodaySummary

    func fetchTodaySummary(profileId: Int64) -> DailySummary? {
        let sql = """
            SELECT id, profile_id, date, total_calories, meal_count,
                   ergonomic_alerts, llm_summary
            FROM   daily_summaries
            WHERE  profile_id = ? AND date = ?;
        """
        guard let stmt = prepare(sql) else { return nil }
        sqlite3_bind_int64(stmt, 1, profileId)
        bindText(stmt,          2, todayString())

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            return nil
        }
        let summary = DailySummary(
            id:               sqlite3_column_int64(stmt, 0),
            profileId:        sqlite3_column_int64(stmt, 1),
            date:             colString(stmt, 2),
            totalCalories:    sqlite3_column_double(stmt, 3),
            mealCount:        Int(sqlite3_column_int(stmt, 4)),
            ergonomicAlerts:  Int(sqlite3_column_int(stmt, 5)),
            llmSummary:       colStringOrNil(stmt, 6)
        )
        sqlite3_finalize(stmt)
        return summary
    }

    // MARK: - 7. upsertDailySummary

    func upsertDailySummary(_ summary: DailySummary) {
        // ON CONFLICT ... DO UPDATE requires SQLite 3.24+ (iOS 12+ ships 3.28+)
        let sql = """
            INSERT INTO daily_summaries
              (profile_id, date, total_calories, meal_count, ergonomic_alerts, llm_summary)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(profile_id, date) DO UPDATE SET
                total_calories   = excluded.total_calories,
                meal_count       = excluded.meal_count,
                ergonomic_alerts = excluded.ergonomic_alerts,
                llm_summary      = excluded.llm_summary;
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int64(stmt, 1, summary.profileId)
        bindText(stmt,          2, summary.date)
        sqlite3_bind_double(stmt, 3, summary.totalCalories)
        sqlite3_bind_int(stmt,  4, Int32(summary.mealCount))
        sqlite3_bind_int(stmt,  5, Int32(summary.ergonomicAlerts))
        if let llm = summary.llmSummary { bindText(stmt, 6, llm) } else { sqlite3_bind_null(stmt, 6) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - 8. saveTraceEvent

    func saveTraceEvent(_ event: TraceEvent) {
        deleteStaleTraceEvents()   // enforce 7-day rolling window on every write
        let sql = """
            INSERT OR REPLACE INTO trace_events
              (id, timestamp, stage, duration_ms, input_tokens, output_tokens,
               estimated_cost_usd, success, error_message, date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        bindText(stmt, 1,  event.id.uuidString)
        bindText(stmt, 2,  iso.string(from: event.timestamp))
        bindText(stmt, 3,  event.stage)
        sqlite3_bind_int(stmt,    4, Int32(event.durationMs))
        sqlite3_bind_int(stmt,    5, Int32(event.inputTokens))
        sqlite3_bind_int(stmt,    6, Int32(event.outputTokens))
        sqlite3_bind_double(stmt, 7, event.estimatedCostUSD)
        sqlite3_bind_int(stmt,    8, event.success ? 1 : 0)
        if let msg = event.errorMessage { bindText(stmt, 9, msg) } else { sqlite3_bind_null(stmt, 9) }
        bindText(stmt, 10, datePart(of: event.timestamp))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - 9. fetchTodayTotalCost

    func fetchTodayTotalCost() -> Double {
        let sql = """
            SELECT COALESCE(SUM(estimated_cost_usd), 0.0)
            FROM   trace_events
            WHERE  date = ? AND success = 1;
        """
        guard let stmt = prepare(sql) else { return 0 }
        bindText(stmt, 1, todayString())
        let cost = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_double(stmt, 0) : 0.0
        sqlite3_finalize(stmt)
        return cost
    }

    // MARK: - Schema (nonisolated — called from init and from setupDatabase)

    private nonisolated func createAllTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                tenant_id    TEXT NOT NULL,
                name         TEXT NOT NULL,
                profile_type TEXT CHECK(profile_type IN ('health','care')),
                settings_json TEXT,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS meals (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id      INTEGER REFERENCES profiles(id),
                timestamp       TIMESTAMP NOT NULL,
                meal_type       TEXT,
                food_items_json TEXT,
                total_calories  REAL,
                context         TEXT,
                screen_visible  INTEGER,
                eating_alone    INTEGER,
                mindful_score   INTEGER,
                confidence      REAL
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS ergonomic_events (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id       INTEGER REFERENCES profiles(id),
                timestamp        TIMESTAMP NOT NULL,
                monitor_position TEXT,
                assessment       TEXT,
                recommendation   TEXT
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS daily_summaries (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id       INTEGER REFERENCES profiles(id),
                date             DATE NOT NULL,
                total_calories   REAL,
                meal_count       INTEGER,
                ergonomic_alerts INTEGER,
                llm_summary      TEXT,
                UNIQUE(profile_id, date)
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS trace_events (
                id                  TEXT PRIMARY KEY,
                timestamp           TIMESTAMP NOT NULL,
                stage               TEXT NOT NULL,
                duration_ms         INTEGER NOT NULL,
                input_tokens        INTEGER NOT NULL,
                output_tokens       INTEGER NOT NULL,
                estimated_cost_usd  REAL NOT NULL,
                success             INTEGER NOT NULL,
                error_message       TEXT,
                date                DATE NOT NULL
            );
        """)
    }

    // MARK: - Private helpers

    private nonisolated func openDB() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK { db = nil }
    }

    private nonisolated func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        return sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK ? stmt : nil
    }

    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private func colString(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    private func colStringOrNil(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: ptr)
    }

    // ISO8601 formatter for timestamp columns
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    // "yyyy-MM-dd" string for today — used in WHERE date(...) = ? queries
    private func todayString() -> String {
        datePart(of: Date())
    }

    private func datePart(of date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func deleteStaleTraceEvents() {
        execute("DELETE FROM trace_events WHERE date < date('now', '-7 days');")
    }
}
