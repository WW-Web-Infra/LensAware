import Foundation
import Vision
import UIKit

// MARK: - OCRService

struct OCRService: Sendable {

    // Returns all recognised text joined into one string, or nil if nothing found.
    func recognizeText(in imageData: Data) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = UIImage(data: imageData)?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let strings = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    continuation.resume(returning: strings.isEmpty ? nil : strings.joined(separator: " "))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
