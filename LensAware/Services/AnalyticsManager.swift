import Foundation

// MARK: - TraceEvent

struct TraceEvent: Sendable {
    let id: UUID
    let timestamp: Date
    let stage: String          // capture | transfer | api | parse | audio
    let durationMs: Int
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    let success: Bool
    let errorMessage: String?
}

// MARK: - AnalyticsManager

actor AnalyticsManager {

    // ── Gemini 1.5 Flash pricing ──────────────────────────────────────
    // Input:  $0.075  per 1M tokens
    // Output: $0.30   per 1M tokens
    // Image:  ~1,600 tokens per 1568px JPEG (billed as input tokens)
    //
    // Claude Haiku 4.5 pricing (swap when switching to Claude):
    //   Input:  $0.80 / 1M   Output: $4.00 / 1M   Image: ~1,600 tokens
    private static let inputCostPerToken:  Double = 0.075  / 1_000_000   // Gemini 1.5 Flash
    private static let outputCostPerToken: Double = 0.30   / 1_000_000   // Gemini 1.5 Flash
    // private static let inputCostPerToken:  Double = 0.80  / 1_000_000 // Claude Haiku 4.5
    // private static let outputCostPerToken: Double = 4.00  / 1_000_000 // Claude Haiku 4.5
    static let imageTokens: Int = 1_600

    private let dbManager: DatabaseManager

    // Pending start times keyed by "\(uuid)-\(stage)"
    private var inFlight: [String: Date] = [:]

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Trace lifecycle

    /// Records the start of a pipeline stage.
    func startTrace(id: UUID, stage: String) {
        inFlight[key(id, stage)] = Date()
    }

    /// Closes a stage, builds a TraceEvent, and persists it.
    /// Pass `error:` to mark the event as failed.
    func endTrace(id: UUID,
                  stage: String,
                  tokens: (input: Int, output: Int)? = nil,
                  error: String? = nil) {
        let traceKey = key(id, stage)
        guard let start = inFlight.removeValue(forKey: traceKey) else { return }

        let durationMs    = Int(Date().timeIntervalSince(start) * 1_000)
        let inputTokens   = tokens?.input  ?? 0
        let outputTokens  = tokens?.output ?? 0
        let cost          = estimateCost(inputTokens: inputTokens, outputTokens: outputTokens)

        let event = TraceEvent(
            id:               id,
            timestamp:        start,
            stage:            stage,
            durationMs:       durationMs,
            inputTokens:      inputTokens,
            outputTokens:     outputTokens,
            estimatedCostUSD: cost,
            success:          error == nil,
            errorMessage:     error
        )

        Task { await dbManager.saveTraceEvent(event) }
    }

    // MARK: - Pipeline summary

    /// Prints per-stage breakdown, total latency, and total cost to the console.
    func logFullPipeline(events: [TraceEvent]) {
        let sorted     = events.sorted { $0.timestamp < $1.timestamp }
        let totalMs    = sorted.map(\.durationMs).reduce(0, +)
        let totalCost  = sorted.map(\.estimatedCostUSD).reduce(0.0, +)
        let okCount    = sorted.filter(\.success).count

        print("──── LensAware Pipeline Trace ────────────────────────────")
        for e in sorted {
            let flag    = e.success ? "✓" : "✗"
            let tokens  = e.inputTokens > 0 || e.outputTokens > 0
                ? " | \(e.inputTokens)in / \(e.outputTokens)out tok"
                : ""
            let costStr = e.estimatedCostUSD > 0
                ? " | $\(String(format: "%.6f", e.estimatedCostUSD))"
                : ""
            let errStr  = e.errorMessage.map { " [\($0)]" } ?? ""
            print("[\(flag)] \(e.stage.padding(toLength: 10, withPad: " ", startingAt: 0))"
                  + " \(String(format: "%4d", e.durationMs))ms\(tokens)\(costStr)\(errStr)")
        }
        print("──────────────────────────────────────────────────────────")
        let latencyFlag = totalMs < 3_000 ? "✓" : "⚠ OVER BUDGET"
        print("Total  \(totalMs)ms \(latencyFlag)"
              + " | Cost $\(String(format: "%.6f", totalCost))"
              + " | \(okCount)/\(sorted.count) stages ok")
        print("──────────────────────────────────────────────────────────")
    }

    // MARK: - Cost queries

    /// Returns total Gemini API spend logged today (persisted, survives app restart).
    func todaysCost() async -> Double {
        await dbManager.fetchTodayTotalCost()
    }

    // MARK: - Private helpers

    private func key(_ id: UUID, _ stage: String) -> String {
        "\(id.uuidString)-\(stage)"
    }

    private func estimateCost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(inputTokens)  * Self.inputCostPerToken
        + Double(outputTokens) * Self.outputCostPerToken
    }
}
