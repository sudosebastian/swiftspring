import SwiftUI
import SwiftspringKit
import UniformTypeIdentifiers

public struct ComposeView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var toText = ""
    @State private var ccText = ""
    @State private var showCc = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var errorMessage: String?
    @State private var showImporter = false
    @FocusState private var focusedField: Field?

    private enum Field { case to, subject, body }

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerFields
                Divider()
                TextEditor(text: $bodyText)
                    .font(.system(size: 15, design: .rounded))
                    .padding(16)
                    .focused($focusedField, equals: .body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !environment.compose.attachmentURLs.isEmpty {
                    attachmentStrip
                }

                if environment.compose.undoSecondsRemaining > 0 {
                    undoBanner
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SwiftspringBrand.coral)
                        .padding(8)
                }
            }
            .background(AtmosphereBackground().opacity(0.35))
            .navigationTitle(environment.compose.draft?.replyToHeaderMessageId == nil ? "New Message" : "Reply")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .help("Attach files")

                    Button {
                        Task { await send() }
                    } label: {
                        if environment.compose.isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(toText.isEmpty || environment.compose.isSending)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    environment.compose.attachmentURLs.append(contentsOf: urls)
                }
            }
            .onAppear {
                populateFromDraft()
                focusedField = toText.isEmpty ? .to : .body
            }
        }
    }

    private var headerFields: some View {
        VStack(spacing: 0) {
            composeField("To") {
                TextField("recipients@example.com", text: $toText)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .to)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Divider().padding(.leading, 72)
            if showCc {
                composeField("Cc") {
                    TextField("optional", text: $ccText)
                }
                Divider().padding(.leading, 72)
            } else {
                HStack {
                    Spacer()
                    Button("Cc") { withAnimation { showCc = true } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftspringBrand.spruceBright)
                        .padding(.trailing, 16)
                        .padding(.vertical, 6)
                }
            }
            composeField("Subject") {
                TextField("Subject", text: $subject)
                    .focused($focusedField, equals: .subject)
            }
        }
        .background(.background.opacity(0.85))
    }

    private func composeField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            content()
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(environment.compose.attachmentURLs, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SwiftspringBrand.mist, in: Capsule())
                }
            }
            .padding(12)
        }
        .background(.ultraThinMaterial)
    }

    private var undoBanner: some View {
        HStack {
            Image(systemName: "paperplane.circle.fill")
                .foregroundStyle(SwiftspringBrand.spruceBright)
            Text("Sending in \(environment.compose.undoSecondsRemaining)…")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(12)
        .background(SwiftspringBrand.sand)
    }

    private func populateFromDraft() {
        if let draft = environment.compose.draft {
            toText = draft.to.map(\.email).joined(separator: ", ")
            ccText = draft.cc.map(\.email).joined(separator: ", ")
            showCc = !ccText.isEmpty
            subject = draft.subject
            bodyText = environment.compose.plainBody
        } else if let account = environment.accounts.accounts.first {
            _ = try? environment.compose.newDraft(from: account)
        }
    }

    private func send() async {
        guard let account = environment.accounts.accounts.first else { return }
        errorMessage = nil
        do {
            if environment.compose.draft == nil {
                _ = try environment.compose.newDraft(from: account)
            }
            let to = parseAddresses(toText)
            let cc = parseAddresses(ccText)
            try environment.compose.updateRecipients(to: to, cc: cc)
            try environment.compose.updateSubject(subject)
            environment.compose.plainBody = bodyText
            environment.compose.htmlBody = bodyText
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    let trimmed = String(line)
                    return trimmed.isEmpty ? "<br>" : "<p>\(trimmed)</p>"
                }
                .joined()
            try await environment.compose.send(undoDelaySeconds: 3)
            environment.notifications.status = "Message sent"
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseAddresses(_ raw: String) -> [EmailAddress] {
        raw.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { EmailAddress(email: String($0)) }
    }
}

public struct PreferencesView: View {
    @ObservedObject var environment: AppEnvironment
    @AppStorage("swiftspring.appearance") private var appearance = "system"

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        TabView {
            AccountSetupView(environment: environment)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light mist").tag("light")
                        Text("Dim spruce").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        SwiftspringWordmark(size: 28, showTagline: true)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Search") {
                    Text("Local FTS5 indexes subjects, participants, and message bodies.")
                        .foregroundStyle(.secondary)
                }

                Section("Sync") {
                    Text("macOS keeps IMAP sessions warm. iOS uses background app refresh.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Accounts", value: "\(environment.accounts.accounts.count)")
                    LabeledContent("Badge", value: "\(environment.notifications.badgeCount) unread")
                }

                Section("About") {
                    LabeledContent("Version", value: SwiftspringKitInfo.version)
                    Text(SwiftspringBrand.tagline)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("General", systemImage: "gear") }

            MailRulesPreferences(environment: environment)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
        #endif
    }
}

struct MailRulesPreferences: View {
    @ObservedObject var environment: AppEnvironment
    @State private var rules: [MailRule] = []
    @State private var name = "Star newsletters"
    @State private var fromContains = "news"

    var body: some View {
        Form {
            Section("New rule") {
                TextField("Name", text: $name)
                TextField("From contains", text: $fromContains)
                Button("Add Rule") {
                    let condition = MailRuleCondition(fromContains: fromContains)
                    let action = MailRuleAction(star: true)
                    if let rule = try? MailRule(
                        name: name,
                        conditionJSON: MailTaskCodec.encode(condition),
                        actionJSON: MailTaskCodec.encode(action)
                    ) {
                        try? environment.rules.save(rule)
                        rules = (try? environment.rules.allRules()) ?? []
                    }
                }
                .tint(SwiftspringBrand.spruceBright)
            }
            Section("Rules") {
                if rules.isEmpty {
                    Text("No rules yet — automate stars, reads, and moves.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    Toggle(rule.name, isOn: Binding(
                        get: { rule.enabled },
                        set: { enabled in
                            var updated = rule
                            updated.enabled = enabled
                            try? environment.rules.save(updated)
                            rules = (try? environment.rules.allRules()) ?? []
                        }
                    ))
                }
            }
        }
        .onAppear {
            rules = (try? environment.rules.allRules()) ?? []
        }
    }
}
