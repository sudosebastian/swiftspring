import Foundation
import GRDB

/// State shared by local scheduled sends and follow-up reminders. These records
/// never depend on a subscription or remote identity.
public enum LocalFeatureStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pending
    case processing
    case completed
    case cancelled
    case failed
}

public enum LocalActivityKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case messageSent
    case followUpDue
    case recipientReplied
    case messageOpened
    case linkClicked
}

public enum LocalFeatureError: Error, LocalizedError, Sendable {
    case messageNotFound
    case messageIsNotDraft
    case threadNotFound
    case invalidGatewayURL

    public var errorDescription: String? {
        switch self {
        case .messageNotFound: return "The message no longer exists."
        case .messageIsNotDraft: return "Only drafts can be scheduled for delivery."
        case .threadNotFound: return "The conversation no longer exists."
        case .invalidGatewayURL:
            return "A self-hosted gateway must use a public HTTPS URL."
        }
    }
}

public struct MailTemplate: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mailTemplate"

    public var id: EntityID
    public var name: String
    public var subject: String
    public var htmlBody: String
    public var plainBody: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: EntityID = EntityID(),
        name: String,
        subject: String = "",
        htmlBody: String = "",
        plainBody: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.plainBody = plainBody
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScheduledSend: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scheduledSend"

    public var id: EntityID
    public var accountId: EntityID
    public var messageId: EntityID
    public var sendAt: Date
    public var status: LocalFeatureStatus
    public var createdAt: Date
    public var completedAt: Date?
    public var errorMessage: String?

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        messageId: EntityID,
        sendAt: Date,
        status: LocalFeatureStatus = .pending,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.messageId = messageId
        self.sendAt = sendAt
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

public struct FollowUpReminder: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "followUpReminder"

    public var id: EntityID
    public var accountId: EntityID
    public var threadId: EntityID
    public var sentMessageId: EntityID?
    /// The newest inbound message when the reminder was created. A newer one
    /// means someone replied and the reminder should be dismissed.
    public var lastIncomingAt: Date
    public var remindAt: Date
    public var status: LocalFeatureStatus
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        threadId: EntityID,
        sentMessageId: EntityID? = nil,
        lastIncomingAt: Date,
        remindAt: Date,
        status: LocalFeatureStatus = .pending,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.threadId = threadId
        self.sentMessageId = sentMessageId
        self.lastIncomingAt = lastIncomingAt
        self.remindAt = remindAt
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct LocalActivityEvent: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "localActivityEvent"

    public var id: EntityID
    public var accountId: EntityID
    public var messageId: EntityID?
    public var threadId: EntityID?
    public var kind: LocalActivityKind
    public var occurredAt: Date
    public var metadataJSON: String

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        messageId: EntityID? = nil,
        threadId: EntityID? = nil,
        kind: LocalActivityKind,
        occurredAt: Date = Date(),
        metadataJSON: String = "{}"
    ) {
        self.id = id
        self.accountId = accountId
        self.messageId = messageId
        self.threadId = threadId
        self.kind = kind
        self.occurredAt = occurredAt
        self.metadataJSON = metadataJSON
    }
}

/// Configuration for an optional service operated by the user. It is only used
/// for features that must be reachable by other people (tracking and sharing).
public struct SelfHostedGateway: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "selfHostedGateway"
    public static let singletonID = EntityID(rawValue: "self-hosted-gateway")

    public var id: EntityID
    public var baseURL: String
    public var trackingEnabled: Bool
    public var sharingEnabled: Bool
    public var updatedAt: Date

    public init(
        id: EntityID = SelfHostedGateway.singletonID,
        baseURL: String,
        trackingEnabled: Bool = true,
        sharingEnabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.baseURL = baseURL
        self.trackingEnabled = trackingEnabled
        self.sharingEnabled = sharingEnabled
        self.updatedAt = updatedAt
    }
}

public enum GatewayCapability: String, Codable, Sendable, CaseIterable {
    case openTracking
    case linkTracking
    case threadSharing
}

public struct TemplateService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func save(_ template: MailTemplate) throws {
        var template = template
        template.updatedAt = Date()
        try repository.db.dbWriter.write { db in
            try template.save(db)
        }
    }

    public func all() throws -> [MailTemplate] {
        try repository.db.dbWriter.read { db in
            try MailTemplate.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func delete(id: EntityID) throws {
        try repository.db.dbWriter.write { db in
            _ = try MailTemplate.deleteOne(db, key: id)
        }
    }
}

public struct ScheduledSendService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    @discardableResult
    public func schedule(messageId: EntityID, at sendAt: Date) throws -> ScheduledSend {
        guard let message = try repository.message(id: messageId) else {
            throw LocalFeatureError.messageNotFound
        }
        guard message.draft else {
            throw LocalFeatureError.messageIsNotDraft
        }
        let scheduled = ScheduledSend(accountId: message.accountId, messageId: messageId, sendAt: sendAt)
        try repository.db.dbWriter.write { db in
            try scheduled.save(db)
        }
        return scheduled
    }

    public func scheduled(for messageId: EntityID) throws -> ScheduledSend? {
        try repository.db.dbWriter.read { db in
            try ScheduledSend.filter(Column("messageId") == messageId).fetchOne(db)
        }
    }

    public func cancel(messageId: EntityID) throws {
        try repository.db.dbWriter.write { db in
            guard var scheduled = try ScheduledSend.filter(Column("messageId") == messageId).fetchOne(db) else { return }
            scheduled.status = .cancelled
            scheduled.completedAt = Date()
            try scheduled.update(db)
        }
    }

    /// Atomically claims due rows so foreground and background processing can't
    /// submit the same draft twice.
    public func claimDue(now: Date = Date()) throws -> [ScheduledSend] {
        try repository.db.dbWriter.write { db in
            let records = try ScheduledSend
                .filter(Column("status") == LocalFeatureStatus.pending && Column("sendAt") <= now)
                .order(Column("sendAt").asc)
                .fetchAll(db)
            for var record in records {
                record.status = .processing
                try record.update(db)
            }
            return records
        }
    }

    public func complete(_ scheduled: ScheduledSend, at date: Date = Date()) throws {
        try update(scheduled, status: .completed, completedAt: date, errorMessage: nil)
    }

    public func fail(_ scheduled: ScheduledSend, error: Error, at date: Date = Date()) throws {
        try update(scheduled, status: .failed, completedAt: date, errorMessage: error.localizedDescription)
    }

    private func update(
        _ scheduled: ScheduledSend,
        status: LocalFeatureStatus,
        completedAt: Date?,
        errorMessage: String?
    ) throws {
        try repository.db.dbWriter.write { db in
            var updated = scheduled
            updated.status = status
            updated.completedAt = completedAt
            updated.errorMessage = errorMessage
            try updated.update(db)
        }
    }
}

public struct FollowUpReminderService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    @discardableResult
    public func schedule(threadId: EntityID, sentMessageId: EntityID? = nil, at remindAt: Date) throws -> FollowUpReminder {
        guard let thread = try repository.thread(id: threadId) else {
            throw LocalFeatureError.threadNotFound
        }
        let reminder = FollowUpReminder(
            accountId: thread.accountId,
            threadId: threadId,
            sentMessageId: sentMessageId,
            lastIncomingAt: thread.lastMessageReceivedAt,
            remindAt: remindAt
        )
        try repository.db.dbWriter.write { db in
            try reminder.save(db)
        }
        return reminder
    }

    public func claimDue(now: Date = Date()) throws -> [FollowUpReminder] {
        try repository.db.dbWriter.write { db in
            let records = try FollowUpReminder
                .filter(Column("status") == LocalFeatureStatus.pending && Column("remindAt") <= now)
                .order(Column("remindAt").asc)
                .fetchAll(db)
            for var record in records {
                record.status = .processing
                try record.update(db)
            }
            return records
        }
    }

    public func complete(_ reminder: FollowUpReminder, status: LocalFeatureStatus, at date: Date = Date()) throws {
        try repository.db.dbWriter.write { db in
            var updated = reminder
            updated.status = status
            updated.completedAt = date
            try updated.update(db)
        }
    }
}

public struct LocalActivityService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func record(_ event: LocalActivityEvent) throws {
        try repository.db.dbWriter.write { db in
            try event.save(db)
        }
    }

    public func events(accountId: EntityID, from start: Date, to end: Date) throws -> [LocalActivityEvent] {
        try repository.db.dbWriter.read { db in
            try LocalActivityEvent
                .filter(Column("accountId") == accountId && Column("occurredAt") >= start && Column("occurredAt") <= end)
                .order(Column("occurredAt").desc)
                .fetchAll(db)
        }
    }
}

public struct SelfHostedGatewayService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func current() throws -> SelfHostedGateway? {
        try repository.db.dbWriter.read { db in
            try SelfHostedGateway.fetchOne(db, key: SelfHostedGateway.singletonID)
        }
    }

    public func save(_ gateway: SelfHostedGateway) throws {
        guard Self.isPublicHTTPSURL(gateway.baseURL) else {
            throw LocalFeatureError.invalidGatewayURL
        }
        var gateway = gateway
        gateway.id = SelfHostedGateway.singletonID
        gateway.updatedAt = Date()
        try repository.db.dbWriter.write { db in
            try gateway.save(db)
        }
    }

    public func remove() throws {
        try repository.db.dbWriter.write { db in
            _ = try SelfHostedGateway.deleteOne(db, key: SelfHostedGateway.singletonID)
        }
    }

    public func isEnabled(_ capability: GatewayCapability) throws -> Bool {
        guard let gateway = try current() else { return false }
        switch capability {
        case .openTracking, .linkTracking: return gateway.trackingEnabled
        case .threadSharing: return gateway.sharingEnabled
        }
    }

    private static func isPublicHTTPSURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else { return false }
        return host != "localhost"
            && host != "::1"
            && !host.hasPrefix("127.")
            && !host.hasSuffix(".local")
    }
}

public struct LocalFeatureRunResult: Sendable, Equatable {
    public var sentMessageIDs: [EntityID]
    public var dueReminderThreadIDs: [EntityID]
    public var unsnoozedThreadIDs: [EntityID]

    public init(
        sentMessageIDs: [EntityID] = [],
        dueReminderThreadIDs: [EntityID] = [],
        unsnoozedThreadIDs: [EntityID] = []
    ) {
        self.sentMessageIDs = sentMessageIDs
        self.dueReminderThreadIDs = dueReminderThreadIDs
        self.unsnoozedThreadIDs = unsnoozedThreadIDs
    }
}

/// Runs when the app is active and from the platform's background refresh hook.
/// Delivery is local-first: if the device is not running at the target time, it
/// is sent on the next run rather than silently delegated to a vendor server.
public actor LocalFeatureScheduler {
    private let repository: MailRepository
    private let syncEngine: SyncEngine
    private let scheduledSends: ScheduledSendService
    private let reminders: FollowUpReminderService
    private let activity: LocalActivityService
    private let snooze: SnoozeService

    public init(repository: MailRepository, syncEngine: SyncEngine) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.scheduledSends = ScheduledSendService(repository: repository)
        self.reminders = FollowUpReminderService(repository: repository)
        self.activity = LocalActivityService(repository: repository)
        self.snooze = SnoozeService(repository: repository)
    }

    public func processDue(now: Date = Date()) async -> LocalFeatureRunResult {
        var result = LocalFeatureRunResult()

        for scheduled in (try? scheduledSends.claimDue(now: now)) ?? [] {
            do {
                guard let draft = try repository.message(id: scheduled.messageId) else {
                    throw LocalFeatureError.messageNotFound
                }
                guard draft.draft else {
                    try scheduledSends.complete(scheduled, at: now)
                    continue
                }
                let task = MailTask(
                    accountId: scheduled.accountId,
                    kind: .sendDraft,
                    payloadJSON: try MailTaskCodec.encode(SendDraftPayload(messageId: scheduled.messageId, undoDelaySeconds: 0))
                )
                try repository.enqueue(task)
                try await syncEngine.processTasks(accountId: scheduled.accountId)
                guard let sent = try repository.message(id: scheduled.messageId), !sent.draft else {
                    throw MailTransportError.operationFailed("The scheduled SMTP delivery did not complete.")
                }
                try scheduledSends.complete(scheduled, at: now)
                try activity.record(LocalActivityEvent(
                    accountId: scheduled.accountId,
                    messageId: scheduled.messageId,
                    threadId: sent.threadId,
                    kind: .messageSent,
                    occurredAt: now
                ))
                result.sentMessageIDs.append(scheduled.messageId)
            } catch {
                try? scheduledSends.fail(scheduled, error: error, at: now)
            }
        }

        for reminder in (try? reminders.claimDue(now: now)) ?? [] {
            guard let thread = try? repository.thread(id: reminder.threadId) else {
                try? reminders.complete(reminder, status: .cancelled, at: now)
                continue
            }
            // New inbound mail is a reply, so this follow-up is no longer useful.
            guard thread.lastMessageReceivedAt <= reminder.lastIncomingAt else {
                try? reminders.complete(reminder, status: .cancelled, at: now)
                continue
            }
            try? reminders.complete(reminder, status: .completed, at: now)
            try? activity.record(LocalActivityEvent(
                accountId: reminder.accountId,
                messageId: reminder.sentMessageId,
                threadId: reminder.threadId,
                kind: .followUpDue,
                occurredAt: now
            ))
            result.dueReminderThreadIDs.append(reminder.threadId)
        }

        for record in (try? snooze.dueSnoozes(now: now)) ?? [] {
            guard var thread = try? repository.thread(id: record.threadId) else {
                try? snooze.clear(id: record.id)
                continue
            }
            thread.unread = true
            try? repository.upsertThread(thread)
            try? snooze.clear(id: record.id)
            result.unsnoozedThreadIDs.append(record.threadId)
        }
        return result
    }
}
