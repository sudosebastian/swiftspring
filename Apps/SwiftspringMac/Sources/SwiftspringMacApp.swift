import SwiftUI
import SwiftspringKit
import SwiftspringUI

@main
struct SwiftspringMacApp: App {
    @StateObject private var environment: AppEnvironment
    @AppStorage("swiftspring.appearance") private var appearance = "system"

    init() {
        let env = (try? AppEnvironment.bootstrap(demo: true))
            ?? (try! AppEnvironment.preview())
        _environment = StateObject(wrappedValue: env)
    }

    var body: some Scene {
        WindowGroup {
            RootMailboxView(environment: environment)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    if let account = environment.accounts.accounts.first {
                        _ = try? environment.compose.newDraft(from: account)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Mailbox") {
                Button("Sync All") {
                    Task { await environment.syncEngine.startAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Mark All Read") {
                    let ids = environment.mail.threads.filter(\.unread).map(\.id)
                    Task { try? await environment.mail.setUnread(threadIds: ids, unread: false) }
                }
            }
            CommandGroup(after: .help) {
                Button("Reset Welcome Screen") {
                    UserDefaults.standard.set(false, forKey: "swiftspring.hasLaunched")
                }
            }
        }

        Settings {
            PreferencesView(environment: environment)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
