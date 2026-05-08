import Foundation

// MARK: - APILookupService

struct APILookupService: Sendable {

    // Posts a JSON body to the user's configured endpoint and returns a spoken string.
    // Accepts both JSON responses (looks for "response", "message", or "text" key)
    // and plain-text responses.
    func query(endpoint: String,
               authHeader: String?,
               context: String) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }

        let body = try? JSONEncoder().encode(["query": context])
        var request        = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        // Try JSON first
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["response", "message", "text", "result", "answer"] {
                if let text = dict[key] as? String, !text.isEmpty {
                    return text
                }
            }
        }

        // Fall back to plain text
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return nil
    }
}
