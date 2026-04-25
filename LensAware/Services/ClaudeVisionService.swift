import Foundation
import UIKit

// MARK: - Errors

enum VisionServiceError: Error, LocalizedError {
    case imageResizeFailed
    case promptLoadFailed
    case apiError(statusCode: Int, message: String)
    case parseError(String)
    case maxRetriesExceeded

    var errorDescription: String? {
        switch self {
        case .imageResizeFailed:               return "Image resize failed."
        case .promptLoadFailed:                return "Could not load analysis prompt from bundle."
        case .apiError(let code, let msg):     return "API error \(code): \(msg)"
        case .parseError(let detail):          return "Parse error: \(detail)"
        case .maxRetriesExceeded:              return "Request failed after maximum retries."
        }
    }
}

// MARK: - ClaudeVisionService

actor ClaudeVisionService {

    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    // MARK: - Init

    init() throws {
        guard
            let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
            let config     = NSDictionary(contentsOfFile: configPath),
            let key        = config["GeminiAPIKey"] as? String,
            !key.isEmpty
        else {
            throw VisionServiceError.apiError(statusCode: 0, message: "GeminiAPIKey missing from Config.plist")
        }
        self.apiKey = key
    }

    // MARK: - 1. loadPrompt

    func loadPrompt() -> String {
        guard
            let url  = Bundle.main.url(forResource: "combined_analysis", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("combined_analysis.txt not found in bundle")
        }
        return text
    }

    // MARK: - 2. resizeImage

    func resizeImage(_ data: Data, maxDimension: Int = 1568) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        let targetSize: CGSize
        if longest <= CGFloat(maxDimension) {
            targetSize = CGSize(width: w, height: h)
        } else {
            let scale = CGFloat(maxDimension) / longest
            targetSize = CGSize(width: w * scale, height: h * scale)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized  = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    // MARK: - 3. analyze

    func analyze(imageData: Data) async throws -> LensAnalysis {
        guard let resized = resizeImage(imageData) else {
            throw VisionServiceError.imageResizeFailed
        }

        let prompt  = loadPrompt()
        let base64  = resized.base64EncodedString()
        let payload = GeminiRequest(
            contents: [GeminiContent(parts: [
                .inlineData(mimeType: "image/jpeg", base64: base64),
                .text(prompt)
            ])],
            generationConfig: .healthAnalysis
        )

        let body = try JSONEncoder().encode(payload)

        var urlRequest        = URLRequest(url: URL(string: "\(endpoint)?key=\(apiKey)")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody   = body

        let maxAttempts = 3   // 1 initial + 2 retries
        var lastError: Error  = VisionServiceError.maxRetriesExceeded

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 1_000_000_000)   // 1 s between retries
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)

                guard let http = response as? HTTPURLResponse else {
                    lastError = VisionServiceError.parseError("Non-HTTP response")
                    continue
                }
                guard http.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "(empty)"
                    lastError = VisionServiceError.apiError(statusCode: http.statusCode, message: body)
                    continue
                }
                return try parseGeminiResponse(data)

            } catch let e as VisionServiceError {
                if case .parseError = e { throw e }   // parse failure is not retryable
                lastError = e
            } catch {
                lastError = error
            }
        }

        throw VisionServiceError.maxRetriesExceeded
    }

    // MARK: - 4. parseGeminiResponse

    private func parseGeminiResponse(_ data: Data) throws -> LensAnalysis {
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let gemini = try JSONDecoder().decode(Response.self, from: data)

        guard
            let text     = gemini.candidates.first?.content.parts.first?.text,
            let jsonData = text.data(using: .utf8)
        else {
            throw VisionServiceError.parseError("No text content in Gemini response")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(LensAnalysis.self, from: jsonData)
        } catch {
            throw VisionServiceError.parseError(error.localizedDescription)
        }
    }
}

// MARK: - Gemini request types (private)

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private enum GeminiPart: Encodable {
    case inlineData(mimeType: String, base64: String)
    case text(String)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inlineData(let mimeType, let data):
            var nested = c.nestedContainer(keyedBy: InlineKeys.self, forKey: .inlineData)
            try nested.encode(mimeType, forKey: .mimeType)
            try nested.encode(data,     forKey: .data)
        case .text(let t):
            try c.encode(t, forKey: .text)
        }
    }

    enum CodingKeys:  String, CodingKey { case inlineData = "inline_data", text }
    enum InlineKeys:  String, CodingKey { case mimeType = "mime_type", data }
}

private struct GeminiGenerationConfig: Encodable {
    let responseMimeType: String
    let responseSchema: GeminiSchema
}

// Gemini structured-output schema for LensAnalysis.
// Forces the model to emit exactly the fields we decode, preventing hallucinated keys.
private struct GeminiSchema: Encodable {
    let type = "object"
    let properties: [String: GeminiSchemaNode]
    let required: [String]
}

indirect enum GeminiSchemaNode: Encodable {
    case primitive(type: String)
    case object(properties: [String: GeminiSchemaNode], required: [String])
    case array(items: GeminiSchemaNode)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .primitive(let t):
            try c.encode(t, forKey: .type)
        case .object(let props, let req):
            try c.encode("object", forKey: .type)
            try c.encode(props,    forKey: .properties)
            try c.encode(req,      forKey: .required)
        case .array(let items):
            try c.encode("array",  forKey: .type)
            try c.encode(items,    forKey: .items)
        }
    }
    enum K: String, CodingKey { case type, properties, required, items }
}

private extension GeminiGenerationConfig {
    static var healthAnalysis: GeminiGenerationConfig {
        let foodItem = GeminiSchemaNode.object(
            properties: [
                "name":      .primitive(type: "string"),
                "calories":  .primitive(type: "integer"),
                "protein_g": .primitive(type: "number"),
                "carbs_g":   .primitive(type: "number"),
                "fat_g":     .primitive(type: "number"),
            ],
            required: ["name", "calories", "protein_g", "carbs_g", "fat_g"]
        )
        let schema = GeminiSchema(
            properties: [
                "food_analysis": .object(
                    properties: [
                        "food_detected":  .primitive(type: "boolean"),
                        "meal_type":      .primitive(type: "string"),
                        "items":          .array(items: foodItem),
                        "total_calories": .primitive(type: "integer"),
                    ],
                    required: ["food_detected", "meal_type", "items", "total_calories"]
                ),
                "dining_context": .object(
                    properties: [
                        "location":            .primitive(type: "string"),
                        "screen_visible":      .primitive(type: "boolean"),
                        "eating_alone":        .primitive(type: "boolean"),
                        "mindful_eating_score": .primitive(type: "integer"),
                    ],
                    required: ["location", "screen_visible", "eating_alone", "mindful_eating_score"]
                ),
                "ergonomics": .object(
                    properties: [
                        "monitor_position": .primitive(type: "string"),
                        "assessment":       .primitive(type: "string"),
                        "suggestion":       .primitive(type: "string"),
                    ],
                    required: ["monitor_position", "assessment", "suggestion"]
                ),
            ],
            required: ["food_analysis", "dining_context", "ergonomics"]
        )
        return GeminiGenerationConfig(responseMimeType: "application/json", responseSchema: schema)
    }
}
