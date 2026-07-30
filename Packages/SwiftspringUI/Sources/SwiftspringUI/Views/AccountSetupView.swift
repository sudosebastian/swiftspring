import SwiftUI
import SwiftspringKit
import AuthenticationServices

#if os(macOS)
import AppKit
#endif

public struct AccountSetupView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var provider: MailProvider = .imap
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var smtpHost = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $provider) {
                        ForEach(MailProvider.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .onChange(of: provider) { _, newValue in
                        applyPresets(newValue)
                    }
                }

                if provider.usesOAuth {
                    Section("Sign in") {
                        Text("Connect with \(provider.displayName) using secure browser authentication.")
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await startOAuth() }
                        } label: {
                            Label("Continue with \(provider.displayName)", systemImage: "person.badge.key")
                        }
                        .disabled(isWorking || oauthClientMissing)
                        if oauthClientMissing {
                            Text("Set SWIFTSPRING_GOOGLE_CLIENT_ID / SWIFTSPRING_MICROSOFT_CLIENT_ID to enable OAuth.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Section("Account") {
                        TextField("Name", text: $name)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                        SecureField("Password / App Password", text: $password)
                    }
                    Section("Servers") {
                        TextField("IMAP host", text: $imapHost)
                        TextField("SMTP host", text: $smtpHost)
                    }
                    Button {
                        Task { await addPasswordAccount() }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Add Account")
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isWorking)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section("Existing") {
                    ForEach(environment.accounts.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                Text(account.emailAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(account.syncState.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteAccounts)
                }

                Section {
                    Button("Add Demo Account") {
                        Task {
                            _ = try? await environment.accounts.addDemoAccount()
                            environment.mail.loadFolders(accountId: environment.accounts.accounts.first?.id)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { applyPresets(provider) }
        }
    }

    private var oauthClientMissing: Bool {
        switch provider {
        case .gmail: return environment.accounts.googleClientId.isEmpty
        case .office365, .outlook: return environment.accounts.microsoftClientId.isEmpty
        default: return false
        }
    }

    private func applyPresets(_ provider: MailProvider) {
        let presets = ProviderPresets.settings(for: provider, email: email.isEmpty ? "user@example.com" : email)
        imapHost = presets.imap.host
        smtpHost = presets.smtp.host
    }

    private func addPasswordAccount() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            var imap = ProviderPresets.settings(for: provider, email: email).imap
            var smtp = ProviderPresets.settings(for: provider, email: email).smtp
            if !imapHost.isEmpty { imap.host = imapHost }
            if !smtpHost.isEmpty { smtp.host = smtpHost }
            _ = try await environment.accounts.addIMAPAccount(
                name: name.isEmpty ? email : name,
                email: email,
                provider: provider,
                password: password,
                imap: imap,
                smtp: smtp
            )
            environment.mail.loadFolders(accountId: environment.accounts.accounts.first?.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startOAuth() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let url = try environment.accounts.authorizationURL(for: provider)
            let callback = try await OAuthPresenter.present(url: url, callbackScheme: "swiftspring")
            guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw OAuthError.missingCode
            }
            _ = try await environment.accounts.completeOAuth(provider: provider, code: code)
            environment.mail.loadFolders(accountId: environment.accounts.accounts.first?.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            let account = environment.accounts.accounts[index]
            try? environment.accounts.removeAccount(account)
        }
    }
}

@MainActor
enum OAuthPresenter {
    static func present(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: OAuthError.missingCode)
                }
            }
            #if os(macOS)
            session.presentationContextProvider = OAuthContext.shared
            #endif
            session.prefersEphemeralWebBrowserSession = true
            guard session.start() else {
                continuation.resume(throwing: OAuthError.invalidAuthorizationURL)
                return
            }
            OAuthContext.shared.session = session
        }
    }
}

#if os(macOS)
final class OAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthContext()
    var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
#endif
