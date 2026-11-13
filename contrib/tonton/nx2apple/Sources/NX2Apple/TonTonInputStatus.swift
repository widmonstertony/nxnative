import Foundation

/// A read-only diagnostic for an unbound catalog entry. Once a replacement is
/// associated, the builder validates those new files instead of this history.
struct TonTonInputStatus: Decodable {
    let kind: String
    let version: String

    static func read(titleID: String) -> Self? {
        guard GameboxCloud.enabled,
              titleID.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = support.appendingPathComponent("TonTon Gamebox/input-status/\(titleID).json")
        guard let data = try? Data(contentsOf: file), let status = try? JSONDecoder().decode(Self.self, from: data),
              status.kind == "damaged-update" else { return nil }
        return status
    }
}
