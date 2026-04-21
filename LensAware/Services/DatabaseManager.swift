import Foundation
import SQLite3

// MARK: - DatabaseManager
// SQLite persistence for multi-tenant health profiles (Phase 2).
// Tables are created on first launch; inserts are fire-and-forget from the actor.

actor DatabaseManager {

    private var db: OpaquePointer?
    private let dbURL: URL

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("LensAware", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("lensaware.sqlite")
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public write API

    func saveProfile(_ profile: Profile) {
        let sql = """
            INSERT OR REPLACE INTO profiles (id, tenant_id, profile_type, settings_json)
            VALUES (?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int(stmt, 1, Int32(profile.id))
        sqlite3_bind_text(stmt, 2, (profile.tenantId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (profile.profileType.rawValue as NSString).utf8String, -1, nil)
        if let json = profile.settingsJSON {
            sqlite3_bind_text(stmt, 4, (json as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func saveMeal(profileId: Int, analysis: HealthAnalysisResponse) {
        let food = analysis.foodAnalysis
        guard food.foodDetected else { return }

        let itemsData = (try? JSONEncoder().encode(food.items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let ctx = analysis.diningContext

        let sql = """
            INSERT INTO meals
              (profile_id, timestamp, food_items_json, total_calories, context, screen_visible, eating_alone, mindful_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return }
        sqlite3_bind_int(stmt,  1, Int32(profileId))
        sqlite3_bind_text(stmt, 2, (ISO8601DateFormatter().string(from: Date()) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (itemsData as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, Double(food.totalCalories))
        sqlite3_bind_text(stmt, 5, (ctx.location as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt,  6, ctx.screenVisible ? 1 : 0)
        sqlite3_bind_int(stmt,  7, ctx.eatingAlone   ? 1 : 0)
        sqlite3_bind_int(stmt,  8, Int32(ctx.mindfulEatingScore))
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
        sqlite3_bind_int(stmt,  1, Int32(profileId))
        sqlite3_bind_text(stmt, 2, (ISO8601DateFormatter().string(from: Date()) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (ergo.monitorPosition as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (ergo.assessment as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (ergo.suggestion as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Schema

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id           INTEGER PRIMARY KEY,
                tenant_id    TEXT NOT NULL,
                profile_type TEXT CHECK(profile_type IN ('health','care')),
                settings_json TEXT
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS meals (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id       INTEGER REFERENCES profiles(id),
                timestamp        TEXT NOT NULL,
                food_items_json  TEXT,
                total_calories   REAL,
                context          TEXT,
                screen_visible   INTEGER,
                eating_alone     INTEGER,
                mindful_score    INTEGER
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
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id        INTEGER REFERENCES profiles(id),
                date              DATE UNIQUE,
                total_calories    REAL,
                ergonomic_alerts  INTEGER,
                llm_summary       TEXT
            );
        """)
    }

    // MARK: - Helpers

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }
}
