import Foundation

/// Stable identifier used across accounts, threads, messages, and tasks.
public struct EntityID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString.lowercased()
    }

    public var description: String { rawValue }
}

public enum MailProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case gmail
    case office365
    case outlook
    case icloud
    case fastmail
    case yahoo
    case gmx
    case yandex
    case imap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .office365: return "Microsoft 365"
        case .outlook: return "Outlook.com"
        case .icloud: return "iCloud"
        case .fastmail: return "Fastmail"
        case .yahoo: return "Yahoo"
        case .gmx: return "GMX"
        case .yandex: return "Yandex"
        case .imap: return "IMAP / SMTP"
        }
    }

    public var usesOAuth: Bool {
        switch self {
        case .gmail, .office365, .outlook: return true
        default: return false
        }
    }
}

public enum FolderRole: String, Codable, Sendable, CaseIterable {
    case inbox
    case sent
    case drafts
    case trash
    case spam
    case archive
    case all
    case important
    case starred
    case none
}

public enum SyncState: String, Codable, Sendable {
    case ok
    case authenticating
    case syncing
    case authFailed
    case offline
    case error
}

public enum MailSecurity: String, Codable, Sendable {
    case sslTLS
    case startTLS
    case none
}

public struct ServerSettings: Codable, Sendable, Equatable {
    public var host: String
    public var port: Int
    public var username: String
    public var security: MailSecurity
    public var allowInsecureSSL: Bool

    public init(
        host: String,
        port: Int,
        username: String,
        security: MailSecurity = .sslTLS,
        allowInsecureSSL: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.security = security
        self.allowInsecureSSL = allowInsecureSSL
    }
}

public struct EmailAddress: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(name ?? "")<\(email)>" }
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var displayString: String {
        if let name, !name.isEmpty {
            return "\(name) <\(email)>"
        }
        return email
    }
}
