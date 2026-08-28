import Foundation

public enum EvidenceAvailability<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case available(Value)
    case unavailable(String)
    case unsupported(String)
    case permissionDenied(String)
    case failed(String)

    public var value: Value? {
        if case let .available(value) = self { return value }
        return nil
    }

    public var explanation: String? {
        switch self {
        case .available: nil
        case let .unavailable(message), let .unsupported(message), let .permissionDenied(message), let .failed(message): message
        }
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
