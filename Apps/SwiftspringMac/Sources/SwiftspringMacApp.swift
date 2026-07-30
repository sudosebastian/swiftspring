import SwiftUI
import SwiftspringKit
import SwiftspringUI

@main
struct SwiftspringMacApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        let env = (try? AppEnvironment.bootstrap(demo: true))
            ?? (try! AppEnvironment.preview())
        _environment = StateObject(wrappedValue: env)
    }

    var body: some Scene {
        SwiftspringAppScene(environment: environment)
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
                }
            }
    }
}
