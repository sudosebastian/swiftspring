import Foundation

public struct Account: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var name: String
    public var emailAddress: String
    public var provider: MailProvider
    public var label: String
    public var colorHex: String
    public var imap: ServerSettings
    public var smtp: ServerSettings
    public var aliases: [String]
    public var defaultAlias: String?
    public var syncState: SyncState
    public var syncErrorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        name: String,
        emailAddress: String,
        provider: MailProvider,
        label: String? = nil,
        colorHex: String = "#4A90E2",
        imap: ServerSettings,
        smtp: ServerSettings,
        aliases: [String] = [],
        defaultAlias: String? = nil,
        syncState: SyncState = .ok,
        syncErrorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emailAddress = emailAddress.lowercased()
        self.provider = provider
        self.label = label ?? emailAddress
        self.colorHex = colorHex
        self.imap = imap
        self.smtp = smtp
        self.aliases = aliases
        self.defaultAlias = defaultAlias
        self.syncState = syncState
        self.syncErrorMessage = syncErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MailFolder: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var path: String
    public var name: String
    public var role: FolderRole
    public var delimiter: String
    public var uidValidity: Int64?
    public var uidNext: Int64?
    public var highestModSeq: Int64?
    public var totalCount: Int
    public var unreadCount: Int

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        path: String,
        name: String,
        role: FolderRole = .none,
        delimiter: String = "/",
        uidValidity: Int64? = nil,
        uidNext: Int64? = nil,
        highestModSeq: Int64? = nil,
        totalCount: Int = 0,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.accountId = accountId
        self.path = path
        self.name = name
        self.role = role
        self.delimiter = delimiter
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.highestModSeq = highestModSeq
        self.totalCount = totalCount
        self.unreadCount = unreadCount
    }
}

public struct MailLabel: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var path: String
    public var name: String
    public var role: FolderRole

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        path: String,
        name: String,
        role: FolderRole = .none
    ) {
        self.id = id
        self.accountId = accountId
        self.path = path
        self.name = name
        self.role = role
    }
}
