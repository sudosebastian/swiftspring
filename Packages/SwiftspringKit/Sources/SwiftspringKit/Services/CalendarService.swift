import Foundation
import GRDB

/// Lightweight calendar event model for Phase 6 expansion (ICS / RSVP later).
public struct CalendarEvent: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "calendarEvent"

    public var id: EntityID
    public var accountId: EntityID
    public var title: String
    public var location: String?
    public var startAt: Date
    public var endAt: Date
    public var ics: String?
    public var messageId: EntityID?

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        title: String,
        location: String? = nil,
        startAt: Date,
        endAt: Date,
        ics: String? = nil,
        messageId: EntityID? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.title = title
        self.location = location
        self.startAt = startAt
        self.endAt = endAt
        self.ics = ics
        self.messageId = messageId
    }
}

public struct CalendarService: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func ensureSchema() throws {
        try repository.db.dbWriter.write { db in
            try db.create(table: "calendarEvent", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("location", .text)
                t.column("startAt", .datetime).notNull().indexed()
                t.column("endAt", .datetime).notNull()
                t.column("ics", .text)
                t.column("messageId", .text)
            }
        }
    }

    public func upsert(_ event: CalendarEvent) throws {
        try ensureSchema()
        try repository.db.dbWriter.write { db in
            try event.save(db)
        }
    }

    public func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        try ensureSchema()
        return try repository.db.dbWriter.read { db in
            try CalendarEvent
                .filter(Column("startAt") >= start && Column("startAt") <= end)
                .order(Column("startAt").asc)
                .fetchAll(db)
        }
    }
}
