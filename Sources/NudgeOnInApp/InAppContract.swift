import Foundation
import CryptoKit

public struct InAppAction: Codable, Sendable {
    public let type: String
    public let url: String?
    public let text: String?
}
struct InAppManifest: Codable, Sendable {
    struct Display: Codable, Sendable { let type: String; let backdrop_opacity: Double }
    let format_version: Int
    let bridge_version: Int
    let display: Display
    let actions: [String: InAppAction]
}
struct InAppArtifact: Codable, Sendable {
    let id: String
    let revision_id: String
    let expires_at: String
    let html: String
    let artifact_sha256: String
    let manifest: InAppManifest
    func validate() throws {
        guard html.utf8.count <= 30 * 1024 * 1024,
              manifest.format_version == 1, manifest.bridge_version == 1,
              (0...0.7).contains(manifest.display.backdrop_opacity),
              Self.sha256(html) == artifact_sha256 else { throw InAppError.invalidArtifact }
    }
    static func sha256(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
public enum InAppError: Error { case invalidArtifact, invalidServer, sessionClosed, server(Int), hostBlocked }
public struct InAppPairing: Codable, Sendable {
    public let id: String
    public let confirmation_code: String
    public let expires_at: String
    let credential: String
}
struct InAppCommands: Decodable {
    struct Run: Decodable { let id: String; let state: String }
    let state: String
    let run: Run?
}
