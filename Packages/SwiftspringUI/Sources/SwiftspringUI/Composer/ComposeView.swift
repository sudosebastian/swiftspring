import SwiftUI
import SwiftspringKit
import UniformTypeIdentifiers

public struct ComposeView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var toText = ""
    @State private var ccText = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var errorMessage: String?
    @State private var showImporter = false

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("To", text: $toText)
                TextField("Cc", text: $ccText)
                TextField("Subject", text: $subject)
                TextEditor(text: $bodyText)
                    .frame(minHeight: 200)
                if !environment.compose.attachmentURLs.isEmpty {
                    Section("Attachments") {
                        ForEach(environment.compose.attachmentURLs, id: \.self) { url in
                            Text(url.lastPathComponent)
                        }
                    }
                }
                if environment.compose.undoSecondsRemaining > 0 {
                    Text("Sending in \(environment.compose.undoSecondsRemaining)…")
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Attach", systemImage: "paperclip")
                    }
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(toText.isEmpty || environment.compose.isSending)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    environment.compose.attachmentURLs.append(contentsOf: urls)
                }
            }
            .onAppear {
                if let draft = environment.compose.draft {
                    toText = draft.to.map(\.email).joined(separator: ", ")
                    ccText = draft.cc.map(\.email).joined(separator: ", ")
                    subject = draft.subject
                    bodyText = environment.compose.plainBody
                } else if let account = environment.accounts.accounts.first {
                    _ = try? environment.compose.newDraft(from: account)
                }
            }
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
                .split(separator: "\n")
                .map { "<p>\(String($0))</p>" }
                .joined()
            try await environment.compose.send(undoDelaySeconds: 3)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseAddresses(_ raw: String) -> [EmailAddress] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { EmailAddress(email: String($0)) }
    }
}

public struct PreferencesView: View {
    @ObservedObject var environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        TabView {
            AccountSetupView(environment: environment)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            Form {
                Section("Search") {
                    Text("Local FTS5 indexes subjects, participants, and message bodies.")
                        .foregroundStyle(.secondary)
                }
                Section("Sync") {
                    Text("macOS keeps IMAP sessions warm. iOS uses background app refresh.")
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            MailRulesPreferences(environment: environment)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 400)
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
            }
            Section("Rules") {
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
