import Foundation
import GRDB

extension EntityID: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        rawValue.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> EntityID? {
        String.fromDatabaseValue(dbValue).map { EntityID(rawValue: $0) }
    }
}
extension MailProvider: DatabaseValueConvertible {}
extension FolderRole: DatabaseValueConvertible {}
extension SyncState: DatabaseValueConvertible {}
extension MailTaskStatus: DatabaseValueConvertible {}
extension MailTaskKind: DatabaseValueConvertible {}

private enum JSONCoding {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> String {
        (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "[]"
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T {
        guard let data = string.data(using: .utf8),
              let value = try? decoder.decode(type, from: data) else {
            if T.self == [EmailAddress].self {
                return ([] as [EmailAddress]) as! T
            }
            if T.self == [EntityID].self {
                return ([] as [EntityID]) as! T
            }
            if T.self == [String].self {
                return ([] as [String]) as! T
            }
            fatalError("Failed to decode JSON for \(T.self)")
        }
        return value
    }

    static func encodeSettings(_ settings: ServerSettings) -> String {
        encode(settings)
    }

    static func decodeSettings(_ string: String) -> ServerSettings {
        decode(ServerSettings.self, from: string)
    }
}

extension Account: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "account"

    public init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        emailAddress = row["emailAddress"]
        provider = row["provider"]
        label = row["label"]
        colorHex = row["colorHex"]
        imap = JSONCoding.decodeSettings(row["imapJSON"])
        smtp = JSONCoding.decodeSettings(row["smtpJSON"])
        aliases = JSONCoding.decode([String].self, from: row["aliasesJSON"])
        defaultAlias = row["defaultAlias"]
        syncState = row["syncState"]
        syncErrorMessage = row["syncErrorMessage"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["emailAddress"] = emailAddress
        container["provider"] = provider
        container["label"] = label
        container["colorHex"] = colorHex
        container["imapJSON"] = JSONCoding.encodeSettings(imap)
        container["smtpJSON"] = JSONCoding.encodeSettings(smtp)
        container["aliasesJSON"] = JSONCoding.encode(aliases)
        container["defaultAlias"] = defaultAlias
        container["syncState"] = syncState
        container["syncErrorMessage"] = syncErrorMessage
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

extension MailFolder: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "folder"

    public init(row: Row) throws {
        id = row["id"]
        accountId = row["accountId"]
        path = row["path"]
        name = row["name"]
        role = row["role"]
        delimiter = row["delimiter"]
        uidValidity = row["uidValidity"]
        uidNext = row["uidNext"]
        highestModSeq = row["highestModSeq"]
        totalCount = row["totalCount"]
        unreadCount = row["unreadCount"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["accountId"] = accountId
        container["path"] = path
        container["name"] = name
        container["role"] = role
        container["delimiter"] = delimiter
        container["uidValidity"] = uidValidity
        container["uidNext"] = uidNext
        container["highestModSeq"] = highestModSeq
        container["totalCount"] = totalCount
        container["unreadCount"] = unreadCount
    }
}

extension MailLabel: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "label"

    public init(row: Row) throws {
        id = row["id"]
        accountId = row["accountId"]
        path = row["path"]
        name = row["name"]
        role = row["role"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["accountId"] = accountId
        container["path"] = path
        container["name"] = name
        container["role"] = role
    }
}

extension Thread: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread"

    public init(row: Row) throws {
        id = row["id"]
        accountId = row["accountId"]
        subject = row["subject"]
        snippet = row["snippet"]
        unread = row["unread"]
        starred = row["starred"]
        participants = JSONCoding.decode([EmailAddress].self, from: row["participantsJSON"])
        folderIds = JSONCoding.decode([EntityID].self, from: row["folderIdsJSON"])
        labelIds = JSONCoding.decode([EntityID].self, from: row["labelIdsJSON"])
        attachmentCount = row["attachmentCount"]
        messageCount = row["messageCount"]
        firstMessageAt = row["firstMessageAt"]
        lastMessageReceivedAt = row["lastMessageReceivedAt"]
        lastMessageSentAt = row["lastMessageSentAt"]
        inAllMail = row["inAllMail"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["accountId"] = accountId
        container["subject"] = subject
        container["snippet"] = snippet
        container["unread"] = unread
        container["starred"] = starred
        container["participantsJSON"] = JSONCoding.encode(participants)
        container["folderIdsJSON"] = JSONCoding.encode(folderIds)
        container["labelIdsJSON"] = JSONCoding.encode(labelIds)
        container["attachmentCount"] = attachmentCount
        container["messageCount"] = messageCount
        container["firstMessageAt"] = firstMessageAt
        container["lastMessageReceivedAt"] = lastMessageReceivedAt
        container["lastMessageSentAt"] = lastMessageSentAt
        container["inAllMail"] = inAllMail
    }
}

extension Message: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"

    public init(row: Row) throws {
        id = row["id"]
        accountId = row["accountId"]
        threadId = row["threadId"]
        folderId = row["folderId"]
        imapUID = row["imapUID"]
        headerMessageId = row["headerMessageId"]
        replyToHeaderMessageId = row["replyToHeaderMessageId"]
        subject = row["subject"]
        snippet = row["snippet"]
        from = JSONCoding.decode([EmailAddress].self, from: row["fromJSON"])
        to = JSONCoding.decode([EmailAddress].self, from: row["toJSON"])
        cc = JSONCoding.decode([EmailAddress].self, from: row["ccJSON"])
        bcc = JSONCoding.decode([EmailAddress].self, from: row["bccJSON"])
        replyTo = JSONCoding.decode([EmailAddress].self, from: row["replyToJSON"])
        date = row["date"]
        unread = row["unread"]
        starred = row["starred"]
        draft = row["draft"]
        pristine = row["pristine"]
        hasAttachments = row["hasAttachments"]
        bodyFetched = row["bodyFetched"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["accountId"] = accountId
        container["threadId"] = threadId
        container["folderId"] = folderId
        container["imapUID"] = imapUID
        container["headerMessageId"] = headerMessageId
        container["replyToHeaderMessageId"] = replyToHeaderMessageId
        container["subject"] = subject
        container["snippet"] = snippet
        container["fromJSON"] = JSONCoding.encode(from)
        container["toJSON"] = JSONCoding.encode(to)
        container["ccJSON"] = JSONCoding.encode(cc)
        container["bccJSON"] = JSONCoding.encode(bcc)
        container["replyToJSON"] = JSONCoding.encode(replyTo)
        container["date"] = date
        container["unread"] = unread
        container["starred"] = starred
        container["draft"] = draft
        container["pristine"] = pristine
        container["hasAttachments"] = hasAttachments
        container["bodyFetched"] = bodyFetched
    }
}

extension MessageBody: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "messageBody"

    public init(row: Row) throws {
        messageId = row["messageId"]
        html = row["html"]
        plainText = row["plainText"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["messageId"] = messageId
        container["html"] = html
        container["plainText"] = plainText
    }
}

extension AttachmentFile: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment"

    public init(row: Row) throws {
        id = row["id"]
        messageId = row["messageId"]
        accountId = row["accountId"]
        filename = row["filename"]
        contentType = row["contentType"]
        size = row["size"]
        contentId = row["contentId"]
        isInline = row["isInline"]
        localPath = row["localPath"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["messageId"] = messageId
        container["accountId"] = accountId
        container["filename"] = filename
        container["contentType"] = contentType
        container["size"] = size
        container["contentId"] = contentId
        container["isInline"] = isInline
        container["localPath"] = localPath
    }
}

extension MailTask: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mailTask"

    public init(row: Row) throws {
        id = row["id"]
        accountId = row["accountId"]
        kind = row["kind"]
        status = row["status"]
        payloadJSON = row["payloadJSON"]
        errorMessage = row["errorMessage"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["accountId"] = accountId
        container["kind"] = kind
        container["status"] = status
        container["payloadJSON"] = payloadJSON
        container["errorMessage"] = errorMessage
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
