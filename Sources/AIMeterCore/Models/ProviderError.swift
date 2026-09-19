import Foundation

/// Typed provider failures. One provider failing must never blank the dashboard,
/// so these are carried alongside the last good snapshot rather than thrown away.
public enum ProviderError: Error, Sendable, Hashable {
    case unauthorized
    case unavailable
    case malformedResponse(String)
    case executableNotFound(String)
    case processFailed(String)
    case timeout
    case configurationMissing(String)
    case unsupportedByInstalledVersion(String)
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Not authorized. Check the credential for this account."
        case .unavailable:
            "The provider is unreachable right now."
        case .malformedResponse(let detail):
            "Unexpected response from the provider: \(detail)"
        case .executableNotFound(let name):
            "Could not find the \(name) executable. Set its path in Settings."
        case .processFailed(let detail):
            "The provider process failed: \(detail)"
        case .timeout:
            "The provider did not respond in time."
        case .configurationMissing(let what):
            "Not configured yet: \(what)"
        case .unsupportedByInstalledVersion(let what):
            "\(what) is not available in the installed provider version."
        }
    }
}
