import Foundation
import SQLite3

// MARK: - DatabaseManager
// SQLite persistence for multi-tenant health profiles.
// Actor serialises all public writes. Internal state is nonisolated(unsafe)
// because it is only ever touched from init (before the actor is shared) and
// from actor-isolated public methods (serialised by the executor) — making
// concurrent access structurally impossible.

actor DatabaseManager {

    // nonisolated(unsafe): C pointer managed manually; actor isolation on all
    // public methods guarantees single-threaded access after init.
    nonisolated(unsafe) private var db: OpaquePointer?
    nonisolated private let dbURL: URL

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("LensAware", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("lensaware.sqlite")
        openDatabase()   // nonisolated — safe to call from sync init
        createTables()   // nonisolated — safe to call from sync init
    }

    deinit {
        sqlite3_close(db)  // nonisolated(unsafe) db is accessible here
    }

    // MARK: - Public write API

    func saveProfile(_ profile: Profile) {
        let sql = """
            INSERT OR REPLACE INTO profiles (id, tenant_id, profile_type, settings_json)
            VALUES (?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int(stmt, 1, Int32(profile.id))
        bind(stmt, 2, profile.tenantId)
        bind(stmt, 3, profile.profileType.rawValue)
        if let json = profile.settingsJSON { bind(stmt, 4, json) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func saveMeal(profileId: Int, analysis: HealthAnalysisResponse) {
        let food = analysis.foodAnalysis
        guard food.foodDetected else { return }

        let itemsJSON = (try? JSONEncoder().encode(food.items))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let ctx = analysis.diningContext

        let sql = """
            INSERT INTO meals
              (profile_id, timestamp, food_items_json, total_calories,
               context, screen_visible, eating_alone, mindful_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int(stmt, 1, Int32(profileId))
        bind(stmt, 2, ISO8601DateFormatter().string(from: Date()))
        bind(stmt, 3, itemsJSON)
        sqlite3_bind_double(stmt, 4, Double(food.totalCalories))
        bind(stmt, 5, ctx.location)
        sqlite3_bind_int(stmt, 6, ctx.screenVisible ? 1 : 0)
        sqlite3_bind_int(stmt, 7, ctx.eatingAlone   ? 1 : 0)
        sqlite3_bind_int(stmt, 8, Int32(ctx.mindfulEatingScore))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func saveErgonomicEvent(profileId: Int, analysis: HealthAnalysisResponse) {
        let ergo = analysis.ergonomics
        guard ergo.assessment == "needs_adjustment" else { return }

        let sql = """
            INSERT INTO ergonomic_events
              (profile_id, timestamp, monitor_position, assessment, recommendation)
            VALUES (?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int(stmt, 1, Int32(profileId))
        bind(stmt, 2, ISO8601DateFormatter().string(from: Date()))
        bind(stmt, 3, ergo.monitorPosition)
        bind(stmt, 4, ergo.assessment)
        bind(stmt, 5, ergo.suggestion)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Schema (nonisolated — called only from init before actor is shared)

    private nonisolated func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id            INTEGER PRIMARY KEY,
                tenant_id     TEXT NOT NULL,
                profile_type  TEXT CHECK(profile_type IN ('health','care')),
                settings_json TEXT
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS meals (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id      INTEGER REFERENCES profiles(id),
                timestamp       TEXT NOT NULL,
                food_items_json TEXT,
                total_calories  REAL,
                context         TEXT,
                screen_visible  INTEGER,
                eating_alone    INTEGER,
                mindful_score   INTEGER
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS ergonomic_events (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id       INTEGER REFERENCES profiles(id),
                timestamp        TEXT NOT NULL,
                monitor_position TEXT,
                assessment       TEXT,
                recommendation   TEXT
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS daily_summaries (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id       INTEGER REFERENCES profiles(id),
                date             DATE UNIQUE,
                total_calories   REAL,
                ergonomic_alerts INTEGER,
                llm_summary      TEXT
            );
        """)
    }

    // MARK: - Helpers (nonisolated — access db via nonisolated(unsafe))

    private nonisolated func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private nonisolated func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // actor-isolated variant used by public write methods
    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }
}
