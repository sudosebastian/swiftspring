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
        ZStack {
            AtmosphereBackground().opacity(0.4)
            Group {
                if results.isEmpty && query.isEmpty {
                    ContentUnavailableView(
                        "People you mail",
                        systemImage: "person.2",
                        description: Text("Search remembered contacts, or open a thread to learn addresses.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { contact in
                        HStack(spacing: 12) {
                            AvatarView(name: contact.name ?? contact.email, size: 36)
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
                        .padding(.vertical, 4)
                    }
                    #if os(iOS)
                    .listStyle(.plain)
                    #endif
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .searchable(text: $query, prompt: "Name or email")
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
        ZStack {
            AtmosphereBackground().opacity(0.4)
            Group {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No upcoming events", systemImage: "calendar")
                    } description: {
                        Text("ICS RSVP sync lands later — add a sample to preview the layout.")
                    } actions: {
                        Button("Add sample event") { addSample() }
                            .buttonStyle(.borderedProminent)
                            .tint(SwiftspringBrand.spruceBright)
                    }
                } else {
                    List(events) { event in
                        HStack(spacing: 14) {
                            VStack {
                                Text(event.startAt.formatted(.dateTime.month(.abbreviated)))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(SwiftspringBrand.spruceBright)
                                Text(event.startAt.formatted(.dateTime.day()))
                                    .font(.system(.title2, design: .rounded).weight(.semibold))
                            }
                            .frame(width: 48)
                            .padding(.vertical, 8)
                            .background(SwiftspringBrand.mist, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.headline)
                                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let location = event.location {
                                    Label(location, systemImage: "mappin.and.ellipse")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Calendar")
        .task { reload() }
        .toolbar {
            Button("Sample", action: addSample)
        }
    }

    private func addSample() {
        guard let account = environment.accounts.accounts.first else { return }
        let event = CalendarEvent(
            accountId: account.id,
            title: "SwiftSpring planning",
            location: "Native",
            startAt: Date().addingTimeInterval(86400),
            endAt: Date().addingTimeInterval(90000)
        )
        try? environment.calendar.upsert(event)
        reload()
    }

    private func reload() {
        let start = Date()
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        events = (try? environment.calendar.events(from: start, to: end)) ?? []
    }
}
