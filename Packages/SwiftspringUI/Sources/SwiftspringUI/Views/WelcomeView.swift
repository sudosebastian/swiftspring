import SwiftUI
import SwiftspringKit

/// First-run brand surface — product name as the hero, one CTA path into the mailbox.
public struct WelcomeView: View {
    @ObservedObject var environment: AppEnvironment
    var onContinue: () -> Void

    @State private var phase = 0
    @State private var isBootstrapping = false
    @State private var errorMessage: String?

    public init(environment: AppEnvironment, onContinue: @escaping () -> Void) {
        self.environment = environment
        self.onContinue = onContinue
    }

    public var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                SwiftspringWordmark(size: 56, showTagline: true)
                    .swiftspringAppear(delay: 0.05)

                Text("A calm inbox for Mac & iPhone.\nLocal sync. Native speed. Your credentials stay on device.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(SwiftspringBrand.ink.opacity(0.75))
                    .padding(.top, 28)
                    .frame(maxWidth: 420, alignment: .leading)
                    .swiftspringAppear(delay: 0.15)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow("tray.full", "Unified inbox across accounts")
                    featureRow("lock.shield", "Keychain-backed credentials")
                    featureRow("bolt.horizontal", "In-process sync — no Electron tax")
                }
                .padding(.top, 36)
                .swiftspringAppear(delay: 0.25)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Task { await startDemo() }
                    } label: {
                        HStack {
                            if isBootstrapping {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text(isBootstrapping ? "Opening inbox…" : "Open demo inbox")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SwiftspringBrand.spruce, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBootstrapping)

                    Button {
                        onContinue()
                    } label: {
                        Text("Add account")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(SwiftspringBrand.spruce)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(SwiftspringBrand.spruce.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBootstrapping)
                }
                .swiftspringAppear(delay: 0.35)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(SwiftspringBrand.coral)
                        .padding(.top, 10)
                }

                Text("macOS 14 · iOS 17 · GPLv3")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 560)
        }
        .preferredColorScheme(.light)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SwiftspringBrand.spruceBright)
                .frame(width: 28, height: 28)
                .background(SwiftspringBrand.spruceBright.opacity(0.12), in: Circle())
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(SwiftspringBrand.ink.opacity(0.85))
        }
    }

    @MainActor
    private func startDemo() async {
        isBootstrapping = true
        errorMessage = nil
        defer { isBootstrapping = false }
        do {
            let accountId: EntityID?
            if environment.accounts.accounts.isEmpty {
                accountId = try await environment.accounts.addDemoAccount().id
            } else {
                accountId = environment.accounts.accounts.first?.id
            }
            environment.mail.loadFolders(accountId: accountId)
            await environment.syncEngine.startAll()
            onContinue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
