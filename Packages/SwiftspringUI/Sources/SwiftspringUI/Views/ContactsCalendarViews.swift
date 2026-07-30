import SwiftUI
import SwiftspringKit

/// Phase 6 contacts browser (local + remembered from mail).
public struct ContactsView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var query = ""
    @State private var results: [Contact] = []

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        List(results) { contact in
            VStack(alignment: .leading) {
                Text(contact.name ?? contact.email)
                    .font(.headline)
                if contact.name != nil {
                    Text(contact.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query)
        .onChange(of: query) { _, newValue in
            results = (try? environment.contacts.search(query: newValue)) ?? []
        }
        .navigationTitle("Contacts")
    }
}

/// Phase 6 calendar list placeholder backed by CalendarService.
public struct CalendarListView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var events: [CalendarEvent] = []

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        List(events) { event in
            VStack(alignment: .leading) {
                Text(event.title).font(.headline)
                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = event.location {
                    Text(location).font(.caption2)
                }
            }
        }
        .navigationTitle("Calendar")
        .task {
            let start = Date()
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            events = (try? environment.calendar.events(from: start, to: end)) ?? []
        }
        .toolbar {
            Button("Sample Event") {
                guard let account = environment.accounts.accounts.first else { return }
                let event = CalendarEvent(
                    accountId: account.id,
                    title: "Swiftspring planning",
                    location: "Native",
                    startAt: Date().addingTimeInterval(86400),
                    endAt: Date().addingTimeInterval(90000)
                )
                try? environment.calendar.upsert(event)
                let start = Date()
                let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
                events = (try? environment.calendar.events(from: start, to: end)) ?? []
            }
        }
    }
}
