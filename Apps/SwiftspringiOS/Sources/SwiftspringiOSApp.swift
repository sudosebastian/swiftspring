import SwiftUI
import SwiftspringKit
import SwiftspringUI

@main
struct SwiftspringiOSApp: App {
    @StateObject private var environment: AppEnvironment
    @AppStorage("swiftspring.appearance") private var appearance = "system"

    init() {
        BackgroundSyncCoordinator.register()
        BackgroundSyncCoordinator.schedule()
        let env = (try? AppEnvironment.bootstrap(demo: true))
            ?? (try! AppEnvironment.preview())
        _environment = StateObject(wrappedValue: env)
    }

    var body: some Scene {
        WindowGroup {
            RootMailboxView(environment: environment)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    BackgroundSyncCoordinator.schedule()
                }
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
