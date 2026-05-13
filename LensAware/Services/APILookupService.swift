import Foundation

// MARK: - ImageUploadFormat

enum ImageUploadFormat: String {
    case base64Json = "base64_json"
    case multipart  = "multipart"
}

// MARK: - APILookupService

struct APILookupService: Sendable {

    // Sends context (and optionally an image) to a user-configured endpoint.
    //
    // image_format "base64_json" (default): {"image": "data:image/jpeg;base64,...", "query": "..."}
    // image_format "multipart": multipart/form-data with image bytes + query field
    //
    // response_key: dot-notation JSONPath to the response string, e.g.
    //   "choices[0].message.content"           — OpenAI
    //   "content[0].text"                      — Claude
    //   "candidates[0].content.parts[0].text"  — Gemini
    //   "results[0].species.scientificNameWithoutAuthor" — PlantNet
    // If nil, the raw response body is returned as plain text.
    func query(endpoint: String,
               authHeader: String?,
               context: String,
               imageData: Data? = nil,
               imageFormat: ImageUploadFormat = .base64Json,
               imageField: String = "image",
               responseKey: String? = nil) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        if let auth = authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        if let imageData {
            switch imageFormat {
            case .base64Json:
                let base64 = "data:image/jpeg;base64," + imageData.base64EncodedString()
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONEncoder().encode([imageField: base64, "query": context])

            case .multipart:
                let boundary = "LensAware-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = buildMultipartBody(imageData: imageData,
                                                      imageField: imageField,
                                                      boundary: boundary)
            }
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["query": context])
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            print("[LensAware] APILookupService — request failed (no response)")
            return nil
        }
        print("[LensAware] APILookupService — HTTP \(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[LensAware] APILookupService — error body: \(body.prefix(200))")
            return nil
        }

        let json = try? JSONSerialization.jsonObject(with: data)

        // If a response key is configured, only use JSONPath — never fall back to raw body
        if let key = responseKey {
            let value = json.flatMap { resolveJSONPath(key, in: $0) }
            print("[LensAware] APILookupService — responseKey '\(key)' resolved to: \(value ?? "nil")")
            return value
        }

        // No key configured — return raw plain-text body
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    // MARK: - JSONPath resolver
    // Supports dot-notation with array indices: "choices[0].message.content"

    private func resolveJSONPath(_ path: String, in json: Any) -> String? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            if let bracketStart = component.firstIndex(of: "["),
               let bracketEnd = component.firstIndex(of: "]") {
                let key = String(component[component.startIndex..<bracketStart])
                let idxStr = String(component[component.index(after: bracketStart)..<bracketEnd])
                guard let idx = Int(idxStr) else { return nil }

                if key.isEmpty {
                    guard let arr = current as? [Any], idx < arr.count else { return nil }
                    current = arr[idx]
                } else {
                    guard let dict = current as? [String: Any],
                          let arr = dict[key] as? [Any],
                          idx < arr.count else { return nil }
                    current = arr[idx]
                }
            } else {
                guard let dict = current as? [String: Any],
                      let next = dict[component] else { return nil }
                current = next
            }
        }

        if let str = current as? String { return str }
        if let num = current as? NSNumber { return num.stringValue }
        return nil
    }

    // MARK: - Multipart builder

    private func buildMultipartBody(imageData: Data,
                                    imageField: String,
                                    boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"\(imageField)\"; filename=\"image.jpg\"\(crlf)")
        body.append("Content-Type: image/jpeg\(crlf)\(crlf)")
        body.append(imageData)
        body.append(crlf)

        body.append("--\(boundary)--\(crlf)")
        return body
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
