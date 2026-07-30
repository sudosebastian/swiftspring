import Foundation

public enum MailTransportError: Error, LocalizedError, Sendable {
    case notConnected
    case authenticationFailed(String)
    case connectionFailed(String)
    case operationFailed(String)
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the mail server."
        case .authenticationFailed(let message): return "Authentication failed: \(message)"
        case .connectionFailed(let message): return "Connection failed: \(message)"
        case .operationFailed(let message): return message
        case .unsupported: return "This operation is not supported by the current transport."
        }
    }
}

public struct RemoteFolder: Sendable, Equatable {
    public var path: String
    public var name: String
    public var delimiter: String
    public var flags: [String]

    public init(path: String, name: String, delimiter: String = "/", flags: [String] = []) {
        self.path = path
        self.name = name
        self.delimiter = delimiter
        self.flags = flags
    }
}

public struct RemoteMessageHeader: Sendable, Equatable {
    public var uid: Int64
    public var headerMessageId: String?
    public var subject: String
    public var snippet: String
    public var from: [EmailAddress]
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var date: Date
    public var unread: Bool
    public var starred: Bool
    public var hasAttachments: Bool
    public var references: [String]

    public init(
        uid: Int64,
        headerMessageId: String? = nil,
        subject: String,
        snippet: String = "",
        from: [EmailAddress] = [],
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        date: Date = Date(),
        unread: Bool = true,
        starred: Bool = false,
        hasAttachments: Bool = false,
        references: [String] = []
    ) {
        self.uid = uid
        self.headerMessageId = headerMessageId
        self.subject = subject
        self.snippet = snippet
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.unread = unread
        self.starred = starred
        self.hasAttachments = hasAttachments
        self.references = references
    }
}

public struct RemoteMessageBody: Sendable, Equatable {
    public var html: String?
    public var plainText: String?
    public var attachments: [RemoteAttachment]

    public init(html: String? = nil, plainText: String? = nil, attachments: [RemoteAttachment] = []) {
        self.html = html
        self.plainText = plainText
        self.attachments = attachments
    }
}

public struct RemoteAttachment: Sendable, Equatable {
    public var filename: String
    public var contentType: String
    public var size: Int64
    public var contentId: String?
    public var isInline: Bool
    public var data: Data?

    public init(
        filename: String,
        contentType: String,
        size: Int64,
        contentId: String? = nil,
        isInline: Bool = false,
        data: Data? = nil
    ) {
        self.filename = filename
        self.contentType = contentType
        self.size = size
        self.contentId = contentId
        self.isInline = isInline
        self.data = data
    }
}

public struct OutgoingMessage: Sendable {
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var htmlBody: String?
    public var plainTextBody: String?
    public var attachments: [RemoteAttachment]
    public var inReplyTo: String?
    public var references: [String]

    public init(
        from: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String,
        htmlBody: String? = nil,
        plainTextBody: String? = nil,
        attachments: [RemoteAttachment] = [],
        inReplyTo: String? = nil,
        references: [String] = []
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainTextBody = plainTextBody
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
    }
}

/// Abstraction over MailCore2 (or any IMAP/SMTP backend).
public protocol MailTransport: Actor {
    func connectIMAP(settings: ServerSettings, credentials: AccountCredentials) async throws
    func connectSMTP(settings: ServerSettings, credentials: AccountCredentials) async throws
    func disconnect() async
    func testConnection(imap: ServerSettings, smtp: ServerSettings, credentials: AccountCredentials) async throws
    func listFolders() async throws -> [RemoteFolder]
    func fetchHeaders(folderPath: String, startUID: Int64?, limit: Int) async throws -> [RemoteMessageHeader]
    func fetchBody(folderPath: String, uid: Int64) async throws -> RemoteMessageBody
    func setFlags(folderPath: String, uids: [Int64], unread: Bool?, starred: Bool?) async throws
    func move(folderPath: String, uids: [Int64], toFolderPath: String) async throws
    func send(_ message: OutgoingMessage) async throws
}

/// Factory that prefers MailCore2 when linked; otherwise uses the mock transport for development.
public enum MailTransportFactory {
    public static func make() -> any MailTransport {
        #if canImport(MailCore)
        return MailCoreTransport()
        #else
        return InMemoryMailTransport()
        #endif
    }
}
