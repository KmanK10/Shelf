import Foundation

public enum KavitaError: Error, Equatable {
    case invalidServerURL
    case unauthorized(String)
    case http(Int, String)
    case decoding(String)
    case transport(String)
}

extension KavitaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a Kavita server URL, such as https://kavita.example."
        case .unauthorized(let message):
            return message.isEmpty ? "Kavita rejected the sign-in." : message
        case .http(let code, let message):
            return message.isEmpty ? "Kavita returned HTTP \(code)." : message
        case .decoding(let message):
            return "Shelf could not read Kavita's response. \(message)"
        case .transport(let message):
            return message
        }
    }
}
