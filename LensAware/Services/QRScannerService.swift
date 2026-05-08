import Foundation
import Vision
import UIKit

// MARK: - QRResult

struct QRResult: Codable, Sendable {
    let rawValue: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - QRAction

struct QRAction: Sendable {
    let qrValue: String
    let audioResponse: String
    let actionTaken: String  // "url_fetched" | "local_lookup" | "read_aloud"
    let success: Bool
}

// MARK: - QRScannerService

struct QRScannerService: Sendable {

    // MARK: - 1. detectQRCodes

    func detectQRCodes(in imageData: Data) async throws -> [QRResult] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = UIImage(data: imageData)?.cgImage else {
                    continuation.resume(returning: [])
                    return
                }
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let results = (request.results ?? []).compactMap { obs -> QRResult? in
                        guard let payload = obs.payloadStringValue else { return nil }
                        return QRResult(
                            rawValue: payload,
                            confidence: obs.confidence,
                            boundingBox: obs.boundingBox
                        )
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 2. processQRResult

    func processQRResult(_ result: QRResult, profile: LensProfile) async -> QRAction {
        let raw = result.rawValue

        switch profile.datasetType {
        case .urlLookup:
            guard let url = URL(string: raw),
                  url.scheme == "https" || url.scheme == "http" else {
                return readAloud(raw)
            }
            let title = (try? await fetchURLContent(url)) ?? url.host ?? raw
            let domain = url.host ?? raw
            return QRAction(
                qrValue: raw,
                audioResponse: "QR code detected. \(title). Opening \(domain).",
                actionTaken: "url_fetched",
                success: true
            )

        case .localJSON:
            let filename = catalogueFilename(from: profile.datasetConfigJSON)
            if let desc = searchLocalCatalogue(code: raw, filename: filename) {
                return QRAction(qrValue: raw, audioResponse: desc, actionTaken: "local_lookup", success: true)
            }
            return readAloud(raw)

        case .cloudAPI:
            guard let endpoint = cloudAPIEndpoint(from: profile.datasetConfigJSON) else {
                return readAloud(raw)
            }
            let auth = cloudAPIAuthHeader(from: profile.datasetConfigJSON)
            let service = APILookupService()
            if let response = await service.query(endpoint: endpoint, authHeader: auth, context: raw) {
                return QRAction(qrValue: raw, audioResponse: response, actionTaken: "api_lookup", success: true)
            }
            return readAloud(raw)

        default:
            // .llmOnly and everything else — read raw value aloud, no network
            return readAloud(raw)
        }
    }

    // MARK: - 3. fetchURLContent

    func fetchURLContent(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            return url.host ?? url.absoluteString
        }
        if let range = html.range(of: #"<title[^>]*>([^<]+)</title>"#, options: .regularExpression) {
            let tag = String(html[range])
            let stripped = tag
                .replacingOccurrences(of: #"<title[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty { return stripped }
        }
        return url.host ?? url.absoluteString
    }

    // MARK: - 4. searchLocalCatalogue

    func searchLocalCatalogue(code: String, filename: String) -> String? {
        let data = catalogueData(filename: filename)
        guard let data,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        for entry in entries {
            let entryId   = entry["id"]   as? String ?? ""
            let entryCode = entry["code"] as? String ?? ""
            guard entryId == code || entryCode == code else { continue }
            let name = entry["name"]        as? String ?? ""
            let desc = entry["description"] as? String ?? ""
            let combined = [name, desc].filter { !$0.isEmpty }.joined(separator: ". ")
            return combined.isEmpty ? nil : combined
        }
        return nil
    }

    // Checks user-uploaded catalogues in Documents first, then falls back to bundle.
    private func catalogueData(filename: String) -> Data? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let userFile = docs.appendingPathComponent("catalogues/\(filename).json")
        if let data = try? Data(contentsOf: userFile) { return data }
        if let url = Bundle.main.url(forResource: filename, withExtension: "json"),
           let data = try? Data(contentsOf: url) { return data }
        return nil
    }

    // MARK: - Private helpers

    private func readAloud(_ raw: String) -> QRAction {
        QRAction(
            qrValue: raw,
            audioResponse: "QR code says: \(raw).",
            actionTaken: "read_aloud",
            success: true
        )
    }

    private func cloudAPIEndpoint(from configJSON: String?) -> String? {
        guard let cfg = configJSON,
              let data = cfg.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let ep = dict["endpoint"], !ep.isEmpty
        else { return nil }
        return ep
    }

    private func cloudAPIAuthHeader(from configJSON: String?) -> String? {
        guard let cfg = configJSON,
              let data = cfg.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let auth = dict["auth_header"], !auth.isEmpty
        else { return nil }
        return auth
    }

    private func catalogueFilename(from configJSON: String?) -> String {
        guard let cfg = configJSON,
              let data = cfg.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let f = dict["filename"], !f.isEmpty
        else { return "catalogue" }
        return f
    }
}
