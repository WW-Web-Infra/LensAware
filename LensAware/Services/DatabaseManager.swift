import Foundation
import SQLite3

// MARK: - DatabaseManager
//
// Actor serialises all public API. `db` and `dbURL` are nonisolated so they
// can be touched in init() (a nonisolated context in Swift 6) and in deinit.

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - DatabaseError

enum DatabaseError: Error, LocalizedError {
    case systemProfileCannotBeDeleted
    case profileNotFound
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .systemProfileCannotBeDeleted: return "Built-in profiles cannot be deleted."
        case .profileNotFound:              return "Profile not found."
        case .writeError(let msg):          return "Database write error: \(msg)"
        }
    }
}

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

    // MARK: - 8. saveProfile (LensProfile)

    func saveProfile(_ profile: LensProfile) throws {
        let sql = """
            INSERT OR REPLACE INTO lens_profiles
              (id, tenant_id, name, description, trigger_type, dataset_type,
               dataset_config_json, tone, is_active, is_system, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else {
            throw DatabaseError.writeError("Could not prepare lens_profiles insert")
        }
        bindText(stmt, 1,  profile.id.uuidString)
        bindText(stmt, 2,  profile.tenantId)
        bindText(stmt, 3,  profile.name)
        bindText(stmt, 4,  profile.description)
        bindText(stmt, 5,  profile.triggerType.rawValue)
        bindText(stmt, 6,  profile.datasetType.rawValue)
        if let cfg = profile.datasetConfigJSON { bindText(stmt, 7, cfg) } else { sqlite3_bind_null(stmt, 7) }
        bindText(stmt, 8,  profile.tone.rawValue)
        sqlite3_bind_int(stmt, 9,  profile.isActive ? 1 : 0)
        sqlite3_bind_int(stmt, 10, profile.isSystem ? 1 : 0)
        bindText(stmt, 11, iso.string(from: profile.createdAt))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        for rule in profile.rules { try saveRule(rule) }
    }

    // MARK: - 9. fetchAllProfiles

    func fetchAllProfiles(tenantId: String) -> [LensProfile] {
        let sql = """
            SELECT id, tenant_id, name, description, trigger_type, dataset_type,
                   dataset_config_json, tone, is_active, is_system, created_at
            FROM   lens_profiles
            WHERE  tenant_id = ?
            ORDER  BY is_system DESC, created_at ASC;
        """
        guard let stmt = prepare(sql) else { return [] }
        bindText(stmt, 1, tenantId)
        var profiles: [LensProfile] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: colString(stmt, 0)) else { continue }
            profiles.append(LensProfile(
                id:               id,
                tenantId:         colString(stmt, 1),
                name:             colString(stmt, 2),
                description:      colString(stmt, 3),
                triggerType:      TriggerType(rawValue: colString(stmt, 4))  ?? .visionAI,
                datasetType:      DatasetType(rawValue: colString(stmt, 5))  ?? .llmOnly,
                datasetConfigJSON: colStringOrNil(stmt, 6),
                tone:             ToneType(rawValue: colString(stmt, 7))     ?? .coach,
                isActive:         sqlite3_column_int(stmt, 8)  != 0,
                isSystem:         sqlite3_column_int(stmt, 9)  != 0,
                createdAt:        iso.date(from: colString(stmt, 10))        ?? Date(),
                rules:            fetchRules(profileId: id)
            ))
        }
        sqlite3_finalize(stmt)
        return profiles
    }

    // MARK: - 10. fetchActiveProfile

    func fetchActiveProfile(tenantId: String) -> LensProfile? {
        let sql = """
            SELECT id, tenant_id, name, description, trigger_type, dataset_type,
                   dataset_config_json, tone, is_active, is_system, created_at
            FROM   lens_profiles
            WHERE  tenant_id = ? AND is_active = 1
            LIMIT  1;
        """
        guard let stmt = prepare(sql) else { return nil }
        bindText(stmt, 1, tenantId)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let id = UUID(uuidString: colString(stmt, 0)) else {
            sqlite3_finalize(stmt)
            return nil
        }
        let profile = LensProfile(
            id:               id,
            tenantId:         colString(stmt, 1),
            name:             colString(stmt, 2),
            description:      colString(stmt, 3),
            triggerType:      TriggerType(rawValue: colString(stmt, 4))  ?? .visionAI,
            datasetType:      DatasetType(rawValue: colString(stmt, 5))  ?? .llmOnly,
            datasetConfigJSON: colStringOrNil(stmt, 6),
            tone:             ToneType(rawValue: colString(stmt, 7))     ?? .coach,
            isActive:         sqlite3_column_int(stmt, 8)  != 0,
            isSystem:         sqlite3_column_int(stmt, 9)  != 0,
            createdAt:        iso.date(from: colString(stmt, 10))        ?? Date(),
            rules:            fetchRules(profileId: id)
        )
        sqlite3_finalize(stmt)
        return profile
    }

    // MARK: - 11. setActiveProfile (atomic swap)

    func setActiveProfile(id: UUID, tenantId: String) throws {
        execute("BEGIN TRANSACTION;")
        let deactivate = "UPDATE lens_profiles SET is_active = 0 WHERE tenant_id = ?;"
        guard let s1 = prepare(deactivate) else {
            execute("ROLLBACK;")
            throw DatabaseError.writeError("Could not prepare deactivate statement")
        }
        bindText(s1, 1, tenantId)
        sqlite3_step(s1); sqlite3_finalize(s1)

        let activate = "UPDATE lens_profiles SET is_active = 1 WHERE id = ? AND tenant_id = ?;"
        guard let s2 = prepare(activate) else {
            execute("ROLLBACK;")
            throw DatabaseError.writeError("Could not prepare activate statement")
        }
        bindText(s2, 1, id.uuidString)
        bindText(s2, 2, tenantId)
        sqlite3_step(s2); sqlite3_finalize(s2)
        execute("COMMIT;")
    }

    // MARK: - 12. deleteProfile

    func deleteProfile(id: UUID) throws {
        let checkSQL = "SELECT is_system FROM lens_profiles WHERE id = ?;"
        guard let check = prepare(checkSQL) else { throw DatabaseError.profileNotFound }
        bindText(check, 1, id.uuidString)
        guard sqlite3_step(check) == SQLITE_ROW else {
            sqlite3_finalize(check)
            throw DatabaseError.profileNotFound
        }
        let isSystem = sqlite3_column_int(check, 0) != 0
        sqlite3_finalize(check)
        guard !isSystem else { throw DatabaseError.systemProfileCannotBeDeleted }

        let del = "DELETE FROM lens_profiles WHERE id = ?;"
        guard let stmt = prepare(del) else {
            throw DatabaseError.writeError("Could not prepare delete statement")
        }
        bindText(stmt, 1, id.uuidString)
        sqlite3_step(stmt); sqlite3_finalize(stmt)
    }

    // MARK: - 13. saveRule

    func saveRule(_ rule: Rule) throws {
        let sql = """
            INSERT OR REPLACE INTO profile_rules
              (id, profile_id, tenant_id, trigger, action_type,
               action_config_json, response_template, priority, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else {
            throw DatabaseError.writeError("Could not prepare profile_rules insert")
        }
        bindText(stmt, 1, rule.id.uuidString)
        bindText(stmt, 2, rule.profileId.uuidString)
        bindText(stmt, 3, rule.tenantId)
        bindText(stmt, 4, rule.trigger)
        bindText(stmt, 5, rule.actionType.rawValue)
        if let cfg = rule.actionConfigJSON   { bindText(stmt, 6, cfg)  } else { sqlite3_bind_null(stmt, 6) }
        if let tmpl = rule.responseTemplate  { bindText(stmt, 7, tmpl) } else { sqlite3_bind_null(stmt, 7) }
        sqlite3_bind_int(stmt, 8, Int32(rule.priority))
        sqlite3_bind_int(stmt, 9, rule.isActive ? 1 : 0)
        sqlite3_step(stmt); sqlite3_finalize(stmt)
    }

    // MARK: - 14. fetchRules

    func fetchRules(profileId: UUID) -> [Rule] {
        let sql = """
            SELECT id, profile_id, tenant_id, trigger, action_type,
                   action_config_json, response_template, priority, is_active
            FROM   profile_rules
            WHERE  profile_id = ?
            ORDER  BY priority ASC;
        """
        guard let stmt = prepare(sql) else { return [] }
        bindText(stmt, 1, profileId.uuidString)
        var rules: [Rule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let id  = UUID(uuidString: colString(stmt, 0)),
                let pid = UUID(uuidString: colString(stmt, 1)),
                let at  = ActionType(rawValue: colString(stmt, 4))
            else { continue }
            rules.append(Rule(
                id:               id,
                profileId:        pid,
                tenantId:         colString(stmt, 2),
                trigger:          colString(stmt, 3),
                actionType:       at,
                actionConfigJSON: colStringOrNil(stmt, 5),
                responseTemplate: colStringOrNil(stmt, 6),
                priority:         Int(sqlite3_column_int(stmt, 7)),
                isActive:         sqlite3_column_int(stmt, 8) != 0
            ))
        }
        sqlite3_finalize(stmt)
        return rules
    }

    // MARK: - 15. deleteRule

    func deleteRule(id: UUID) throws {
        let sql = "DELETE FROM profile_rules WHERE id = ?;"
        guard let stmt = prepare(sql) else {
            throw DatabaseError.writeError("Could not prepare delete rule statement")
        }
        bindText(stmt, 1, id.uuidString)
        sqlite3_step(stmt); sqlite3_finalize(stmt)
    }

    // MARK: - 16. saveTraceEvent

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

    // MARK: - 17. saveQRScan

    func saveQRScan(_ scan: QRScan) {
        let sql = """
            INSERT INTO qr_scans (timestamp, raw_value, url)
            VALUES (?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        bindText(stmt, 1, iso.string(from: scan.timestamp))
        bindText(stmt, 2, scan.rawValue)
        if let url = scan.url { bindText(stmt, 3, url) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - 18. fetchTodayErgonomicEvents

    func fetchTodayErgonomicEvents() -> [ErgonomicEvent] {
        let sql = """
            SELECT id, profile_id, timestamp, monitor_position, assessment, recommendation
            FROM   ergonomic_events
            WHERE  date(timestamp) = ?
            ORDER  BY timestamp DESC;
        """
        guard let stmt = prepare(sql) else { return [] }
        bindText(stmt, 1, todayString())
        var rows: [ErgonomicEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(ErgonomicEvent(
                id:              sqlite3_column_int64(stmt, 0),
                profileId:       sqlite3_column_int64(stmt, 1),
                timestamp:       iso.date(from: colString(stmt, 2)) ?? Date(),
                monitorPosition: colString(stmt, 3),
                assessment:      colString(stmt, 4),
                recommendation:  colString(stmt, 5)
            ))
        }
        sqlite3_finalize(stmt)
        return rows
    }

    // MARK: - 19. fetchRecentQRScans

    func fetchRecentQRScans(limit: Int = 20) -> [QRScan] {
        let sql = """
            SELECT id, timestamp, raw_value, url
            FROM   qr_scans
            ORDER  BY timestamp DESC
            LIMIT  ?;
        """
        guard let stmt = prepare(sql) else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var rows: [QRScan] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(QRScan(
                id:        sqlite3_column_int64(stmt, 0),
                timestamp: iso.date(from: colString(stmt, 1)) ?? Date(),
                rawValue:  colString(stmt, 2),
                url:       colStringOrNil(stmt, 3)
            ))
        }
        sqlite3_finalize(stmt)
        return rows
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
            CREATE TABLE IF NOT EXISTS lens_profiles (
                id                  TEXT PRIMARY KEY,
                tenant_id           TEXT NOT NULL,
                name                TEXT NOT NULL,
                description         TEXT,
                trigger_type        TEXT NOT NULL,
                dataset_type        TEXT NOT NULL,
                dataset_config_json TEXT,
                tone                TEXT NOT NULL,
                is_active           INTEGER DEFAULT 1,
                is_system           INTEGER DEFAULT 0,
                created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS profile_rules (
                id                  TEXT PRIMARY KEY,
                profile_id          TEXT NOT NULL
                    REFERENCES lens_profiles(id) ON DELETE CASCADE,
                tenant_id           TEXT NOT NULL,
                trigger             TEXT NOT NULL,
                action_type         TEXT NOT NULL,
                action_config_json  TEXT,
                response_template   TEXT,
                priority            INTEGER DEFAULT 0,
                is_active           INTEGER DEFAULT 1
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
        execute("""
            CREATE TABLE IF NOT EXISTS qr_scans (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TIMESTAMP NOT NULL,
                raw_value TEXT NOT NULL,
                url       TEXT
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
