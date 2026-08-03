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
    @State private var showSchedulePopover = false
    @State private var scheduledAt = Date().addingTimeInterval(60 * 60)
    @State private var templates: [MailTemplate] = []
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
                    Menu {
                        if templates.isEmpty {
                            Text("No local templates yet")
                        } else {
                            ForEach(templates) { template in
                                Button(template.name) { apply(template) }
                            }
                        }
                        Divider()
                        Button("Save as Template") { saveAsTemplate() }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Local templates")

                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .help("Attach files")

                    Button {
                        showSchedulePopover = true
                    } label: {
                        Image(systemName: "clock")
                    }
                    .help("Send later")
                    .disabled(toText.isEmpty || environment.compose.isSending)
                    .popover(isPresented: $showSchedulePopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Send later")
                                .font(.headline)
                            DatePicker(
                                "Deliver on",
                                selection: $scheduledAt,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            HStack {
                                Button("Cancel") { showSchedulePopover = false }
                                Spacer()
                                Button("Schedule") {
                                    Task { await scheduleSend() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .frame(minWidth: 300)
                    }

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
                templates = (try? environment.templates.all()) ?? []
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
        errorMessage = nil
        do {
            try prepareDraft()
            try await environment.compose.send(undoDelaySeconds: 3)
            environment.notifications.status = "Message sent"
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSend() async {
        errorMessage = nil
        do {
            try prepareDraft()
            guard let draft = environment.compose.draft else { return }
            _ = try environment.scheduledSends.schedule(messageId: draft.id, at: scheduledAt)
            environment.notifications.status = "Scheduled for \(scheduledAt.formatted(date: .abbreviated, time: .shortened))"
            showSchedulePopover = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareDraft() throws {
        guard let account = environment.accounts.accounts.first else { return }
        if environment.compose.draft == nil {
            _ = try environment.compose.newDraft(from: account)
        }
        try environment.compose.updateRecipients(to: parseAddresses(toText), cc: parseAddresses(ccText))
        try environment.compose.updateSubject(subject)
        environment.compose.plainBody = bodyText
        environment.compose.htmlBody = bodyText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = String(line)
                return trimmed.isEmpty ? "<br>" : "<p>\(trimmed)</p>"
            }
            .joined()
        try environment.compose.saveDraft()
    }

    private func saveAsTemplate() {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled template"
            : subject
        let template = MailTemplate(
            name: name,
            subject: subject,
            htmlBody: environment.compose.htmlBody,
            plainBody: bodyText
        )
        do {
            try environment.templates.save(template)
            templates = try environment.templates.all()
            environment.notifications.status = "Saved local template"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ template: MailTemplate) {
        subject = template.subject
        bodyText = template.plainBody
        environment.compose.htmlBody = template.htmlBody
        environment.compose.plainBody = template.plainBody
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

            LocalFeaturesPreferences(environment: environment)
                .tabItem { Label("Local Features", systemImage: "externaldrive") }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
        #endif
    }
}

struct LocalFeaturesPreferences: View {
    @ObservedObject var environment: AppEnvironment
    @State private var gatewayURL = ""
    @State private var trackingEnabled = true
    @State private var sharingEnabled = true
    @State private var languageToolURL = ""
    @State private var translationURL = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section("On this device") {
                Label("Templates, scheduled send, snooze, reminders, contacts, and activity are stored locally.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Label("Scheduled messages send the next time this device is running if it was asleep at their scheduled time.", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }

            Section("Self-hosted gateway") {
                Text("Read receipts, link tracking, and shareable links need a public HTTPS service you operate. Swiftspring never uses a Mailspring ID or server.")
                    .foregroundStyle(.secondary)
                TextField("https://mail.example.com", text: $gatewayURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Toggle("Enable read receipts and link tracking", isOn: $trackingEnabled)
                Toggle("Enable shared conversation links", isOn: $sharingEnabled)
                HStack {
                    Button("Remove gateway", role: .destructive) {
                        do {
                            try environment.gateway.remove()
                            gatewayURL = ""
                            status = "Gateway removed"
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                    .disabled(gatewayURL.isEmpty)
                    Spacer()
                    Button("Save gateway") { saveGateway() }
                        .buttonStyle(.borderedProminent)
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Local language services") {
                Text("Grammar and translation text stays on this device when these endpoints point to services on localhost.")
                    .foregroundStyle(.secondary)
                TextField("LanguageTool URL (for example, http://127.0.0.1:8081/v2/check)", text: $languageToolURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                TextField("LibreTranslate URL (for example, http://127.0.0.1:5000/translate)", text: $translationURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Button("Save local text services") { saveTextServices() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: loadGateway)
    }

    private func loadGateway() {
        guard let gateway = try? environment.gateway.current() else { return }
        gatewayURL = gateway.baseURL
        trackingEnabled = gateway.trackingEnabled
        sharingEnabled = gateway.sharingEnabled
        let configuredTextServices = (try? environment.localTextServices.current()) ?? nil
        if let textServices = configuredTextServices {
            languageToolURL = textServices.languageToolURL ?? ""
            translationURL = textServices.translationURL ?? ""
        }
    }

    private func saveGateway() {
        do {
            try environment.gateway.save(SelfHostedGateway(
                baseURL: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines),
                trackingEnabled: trackingEnabled,
                sharingEnabled: sharingEnabled
            ))
            status = "Gateway saved"
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveTextServices() {
        do {
            try environment.localTextServices.save(LocalTextServiceConfiguration(
                languageToolURL: languageToolURL.nilIfBlank,
                translationURL: translationURL.nilIfBlank
            ))
            status = "Local text services saved"
        } catch {
            status = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
