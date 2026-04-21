import Foundation

// MARK: - Errors

enum ClaudeVisionError: Error, LocalizedError {
    case missingAPIKey
    case missingConfig(String)
    case missingPrompt
    case httpError(Int, String)
    case noToolUseBlock
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:          return "Claude API key not found in Config.plist."
        case .missingConfig(let key): return "Config.plist missing key: \(key)."
        case .missingPrompt:          return "combined_analysis.txt not found in bundle."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .noToolUseBlock:         return "Claude response contained no tool_use block."
        case .decodingFailed(let e):  return "Failed to decode analysis: \(e)"
        }
    }
}

// MARK: - Claude API request / response types

private struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let tools: [ClaudeTool]
    let toolChoice: ToolChoice
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens  = "max_tokens"
        case tools
        case toolChoice = "tool_choice"
        case messages
    }
}

private struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

private struct ToolChoice: Encodable {
    let type: String
    let name: String
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: [MessageContent]
}

private enum MessageContent: Encodable {
    case image(mediaType: String, base64Data: String)
    case text(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            var sourceContainer = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try sourceContainer.encode("base64", forKey: .type)
            try sourceContainer.encode(mediaType, forKey: .mediaType)
            try sourceContainer.encode(data, forKey: .data)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    enum CodingKeys: String, CodingKey { case type, source, text }
    enum SourceCodingKeys: String, CodingKey { case type, mediaType = "media_type", data }
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
}

private struct ContentBlock: Decodable {
    let type: String
    let name: String?
    let input: JSONValue?
}

// MARK: - JSONValue (arbitrary JSON for schema + tool input parsing)

enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { self = .bool(v); return }
        if let v = try? container.decode(Int.self)    { self = .int(v);  return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    // Convert to raw Foundation object for JSONSerialization round-trip into Decodable
    func toDecodableData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - ClaudeVisionService

actor ClaudeVisionService {

    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let prompt: String

    // MARK: - Init

    init() throws {
        guard let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath) else {
            throw ClaudeVisionError.missingConfig("Config.plist")
        }
        guard let key = config["ClaudeAPIKey"] as? String, !key.isEmpty, key != "YOUR_CLAUDE_API_KEY_HERE" else {
            throw ClaudeVisionError.missingAPIKey
        }
        guard let mdl = config["ClaudeModel"] as? String else {
            throw ClaudeVisionError.missingConfig("ClaudeModel")
        }
        guard let url = config["ClaudeAPIBaseURL"] as? String else {
            throw ClaudeVisionError.missingConfig("ClaudeAPIBaseURL")
        }

        guard let promptURL = Bundle.main.url(
            forResource: "combined_analysis",
            withExtension: "txt",
            subdirectory: "Prompts/health"
        ), let promptText = try? String(contentsOf: promptURL, encoding: .utf8) else {
            throw ClaudeVisionError.missingPrompt
        }

        self.apiKey  = key
        self.model   = mdl
        self.baseURL = url
        self.prompt  = promptText
    }

    // MARK: - Public

    func analyze(imageData: Data) async throws -> HealthAnalysisResponse {
        let base64 = imageData.base64EncodedString()

        let request = ClaudeRequest(
            model: model,
            maxTokens: 1024,
            tools: [healthAnalysisTool],
            toolChoice: ToolChoice(type: "tool", name: "analyze_health"),
            messages: [
                ClaudeMessage(role: "user", content: [
                    .image(mediaType: "image/jpeg", base64Data: base64),
                    .text(prompt)
                ])
            ]
        )

        let body = try JSONEncoder().encode(request)

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeVisionError.httpError(http.statusCode, body)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let toolBlock = claudeResponse.content.first(where: { $0.type == "tool_use" }),
              let inputValue = toolBlock.input else {
            throw ClaudeVisionError.noToolUseBlock
        }

        do {
            let inputData = try inputValue.toDecodableData()
            return try JSONDecoder().decode(HealthAnalysisResponse.self, from: inputData)
        } catch {
            throw ClaudeVisionError.decodingFailed(error)
        }
    }

    // MARK: - Tool schema

    private var healthAnalysisTool: ClaudeTool {
        ClaudeTool(
            name: "analyze_health",
            description: "Analyse the image and return food, dining context, and ergonomics data.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("food_analysis"), .string("dining_context"), .string("ergonomics")]),
                "properties": .object([
                    "food_analysis": .object([
                        "type": .string("object"),
                        "required": .array([.string("food_detected"), .string("items"), .string("total_calories")]),
                        "properties": .object([
                            "food_detected":  .object(["type": .string("boolean")]),
                            "total_calories": .object(["type": .string("integer")]),
                            "items": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("object"),
                                    "required": .array([.string("name"), .string("calories"), .string("protein_g"), .string("carbs_g"), .string("fat_g")]),
                                    "properties": .object([
                                        "name":      .object(["type": .string("string")]),
                                        "calories":  .object(["type": .string("integer")]),
                                        "protein_g": .object(["type": .string("number")]),
                                        "carbs_g":   .object(["type": .string("number")]),
                                        "fat_g":     .object(["type": .string("number")])
                                    ])
                                ])
                            ])
                        ])
                    ]),
                    "dining_context": .object([
                        "type": .string("object"),
                        "required": .array([.string("location"), .string("screen_visible"), .string("eating_alone"), .string("mindful_eating_score")]),
                        "properties": .object([
                            "location":             .object(["type": .string("string")]),
                            "screen_visible":       .object(["type": .string("boolean")]),
                            "eating_alone":         .object(["type": .string("boolean")]),
                            "mindful_eating_score": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(5)])
                        ])
                    ]),
                    "ergonomics": .object([
                        "type": .string("object"),
                        "required": .array([.string("monitor_position"), .string("assessment"), .string("suggestion")]),
                        "properties": .object([
                            "monitor_position": .object(["type": .string("string")]),
                            "assessment":       .object(["type": .string("string")]),
                            "suggestion":       .object(["type": .string("string")])
                        ])
                    ])
                ])
            ])
        )
    }
}
