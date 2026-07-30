import Foundation
import GRDB
import Combine

public struct SearchService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func search(query: String) throws -> SearchResults {
        let threads = try repository.searchThreads(query: query)
        let messages = try repository.searchMessages(query: query)
        return SearchResults(threads: threads, messages: messages)
    }
}

public struct SearchResults: Sendable {
    public var threads: [Thread]
    public var messages: [Message]

    public init(threads: [Thread], messages: [Message]) {
        self.threads = threads
        self.messages = messages
    }
}

public struct SnoozeRecord: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "snooze"
    public var id: EntityID
    public var threadId: EntityID
    public var accountId: EntityID
    public var wakeAt: Date
    public var createdAt: Date

    public init(
        id: EntityID = EntityID(),
        threadId: EntityID,
        accountId: EntityID,
        wakeAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.accountId = accountId
        self.wakeAt = wakeAt
        self.createdAt = createdAt
    }
}

public struct SnoozeService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func snooze(threadId: EntityID, accountId: EntityID, until wakeAt: Date) throws {
        let record = SnoozeRecord(threadId: threadId, accountId: accountId, wakeAt: wakeAt)
        try repository.db.dbWriter.write { db in
            try record.save(db)
        }
    }

    public func dueSnoozes(now: Date = Date()) throws -> [SnoozeRecord] {
        try repository.db.dbWriter.read { db in
            try SnoozeRecord
                .filter(Column("wakeAt") <= now)
                .order(Column("wakeAt").asc)
                .fetchAll(db)
        }
    }

    public func clear(id: EntityID) throws {
        try repository.db.dbWriter.write { db in
            _ = try SnoozeRecord.deleteOne(db, key: id)
        }
    }
}

public struct MailRule: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mailRule"
    public var id: EntityID
    public var accountId: EntityID?
    public var name: String
    public var enabled: Bool
    public var conditionJSON: String
    public var actionJSON: String
    public var createdAt: Date

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID? = nil,
        name: String,
        enabled: Bool = true,
        conditionJSON: String,
        actionJSON: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.enabled = enabled
        self.conditionJSON = conditionJSON
        self.actionJSON = actionJSON
        self.createdAt = createdAt
    }
}

public struct MailRuleCondition: Codable, Sendable {
    public var fromContains: String?
    public var subjectContains: String?
    public var hasAttachment: Bool?

    public init(fromContains: String? = nil, subjectContains: String? = nil, hasAttachment: Bool? = nil) {
        self.fromContains = fromContains
        self.subjectContains = subjectContains
        self.hasAttachment = hasAttachment
    }
}

public struct MailRuleAction: Codable, Sendable {
    public var markRead: Bool?
    public var star: Bool?
    public var moveToRole: FolderRole?

    public init(markRead: Bool? = nil, star: Bool? = nil, moveToRole: FolderRole? = nil) {
        self.markRead = markRead
        self.star = star
        self.moveToRole = moveToRole
    }
}

public struct MailRulesService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func save(_ rule: MailRule) throws {
        try repository.db.dbWriter.write { db in
            try rule.save(db)
        }
    }

    public func allRules() throws -> [MailRule] {
        try repository.db.dbWriter.read { db in
            try MailRule.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func matchingRules(for message: Message) throws -> [MailRule] {
        let rules = try allRules().filter(\.enabled)
        return rules.filter { rule in
            guard let condition = try? MailTaskCodec.decode(MailRuleCondition.self, from: rule.conditionJSON) else {
                return false
            }
            if let fromContains = condition.fromContains?.lowercased(),
               !message.from.contains(where: { $0.email.contains(fromContains) || ($0.name?.lowercased().contains(fromContains) ?? false) }) {
                return false
            }
            if let subjectContains = condition.subjectContains?.lowercased(),
               !message.subject.lowercased().contains(subjectContains) {
                return false
            }
            if let hasAttachment = condition.hasAttachment, message.hasAttachments != hasAttachment {
                return false
            }
            return true
        }
    }
}

public struct Contact: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "contact"
    public var id: EntityID
    public var accountId: EntityID
    public var name: String?
    public var email: String
    public var source: String
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        name: String? = nil,
        email: String,
        source: String = "local",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.email = email.lowercased()
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct ContactService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func upsert(_ contact: Contact) throws {
        try repository.db.dbWriter.write { db in
            try contact.save(db)
        }
    }

    public func search(query: String, limit: Int = 20) throws -> [Contact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return try repository.db.dbWriter.read { db in
            try Contact
                .filter(Column("email").like("%\(trimmed)%") || Column("name").like("%\(trimmed)%"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func remember(from message: Message) throws {
        for address in message.from + message.to + message.cc {
            let contact = Contact(accountId: message.accountId, name: address.name, email: address.email, source: "mail")
            try upsert(contact)
        }
    }
}

@MainActor
public final class NotificationService: ObservableObject {
    @Published public private(set) var badgeCount: Int = 0

    public init() {}

    public func updateBadge(unreadThreads: Int) {
        badgeCount = unreadThreads
        #if canImport(UserNotifications)
        // Apps request authorization and set badge via UNUserNotificationCenter.
        #endif
    }

    public func notifyNewMail(subject: String, snippet: String) {
        status = "\(subject) — \(snippet)"
    }

    @Published public var status: String?
}
