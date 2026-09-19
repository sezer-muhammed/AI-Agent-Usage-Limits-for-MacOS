import Foundation

/// Loads the sanitized fixtures. Every provider decoder is tested against these,
/// so the suite runs with no credentials and no network.
enum Fixture {
    static func data(_ path: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: nil)
        guard let url else {
            throw NSError(
                domain: "Fixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing fixture: \(path)"]
            )
        }
        return try Data(contentsOf: url)
    }
}
