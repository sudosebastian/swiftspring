import Foundation

public enum MailTaskStatus: String, Codable, Sendable {
    case local
    case remote
    case complete
    case cancelled
    case failed
}

public enum MailTaskKind: String, Codable, Sendable {
    case syncbackDraft
    case destroyDraft
    case sendDraft
    case changeUnread
    case changeStarred
    case changeFolder
    case changeLabels
    case fetchBody
    case syncFolder
}

public struct MailTask: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var kind: MailTaskKind
    public var status: MailTaskStatus
    public var payloadJSON: String
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        kind: MailTaskKind,
        status: MailTaskStatus = .local,
        payloadJSON: String = "{}",
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.kind = kind
        self.status = status
        self.payloadJSON = payloadJSON
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChangeUnreadPayload: Codable, Sendable {
    public var messageIds: [EntityID]
    public var threadIds: [EntityID]
    public var unread: Bool

    public init(messageIds: [EntityID] = [], threadIds: [EntityID] = [], unread: Bool) {
        self.messageIds = messageIds
        self.threadIds = threadIds
        self.unread = unread
    }
}

public struct ChangeStarredPayload: Codable, Sendable {
    public var messageIds: [EntityID]
    public var threadIds: [EntityID]
    public var starred: Bool

    public init(messageIds: [EntityID] = [], threadIds: [EntityID] = [], starred: Bool) {
        self.messageIds = messageIds
        self.threadIds = threadIds
        self.starred = starred
    }
}

public struct ChangeFolderPayload: Codable, Sendable {
    public var threadIds: [EntityID]
    public var messageIds: [EntityID]
    public var folderId: EntityID

    public init(threadIds: [EntityID] = [], messageIds: [EntityID] = [], folderId: EntityID) {
        self.threadIds = threadIds
        self.messageIds = messageIds
        self.folderId = folderId
    }
}

public struct ChangeLabelsPayload: Codable, Sendable {
    public var threadIds: [EntityID]
    public var labelsToAdd: [EntityID]
    public var labelsToRemove: [EntityID]

    public init(threadIds: [EntityID], labelsToAdd: [EntityID] = [], labelsToRemove: [EntityID] = []) {
        self.threadIds = threadIds
        self.labelsToAdd = labelsToAdd
        self.labelsToRemove = labelsToRemove
    }
}

public struct SendDraftPayload: Codable, Sendable {
    public var messageId: EntityID
    public var undoDelaySeconds: Int

    public init(messageId: EntityID, undoDelaySeconds: Int = 5) {
        self.messageId = messageId
        self.undoDelaySeconds = undoDelaySeconds
    }
}

public struct FetchBodyPayload: Codable, Sendable {
    public var messageId: EntityID

    public init(messageId: EntityID) {
        self.messageId = messageId
    }
}

public struct SyncFolderPayload: Codable, Sendable {
    public var folderId: EntityID

    public init(folderId: EntityID) {
        self.folderId = folderId
    }
}

public enum MailTaskCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return try decoder.decode(type, from: data)
    }
}
