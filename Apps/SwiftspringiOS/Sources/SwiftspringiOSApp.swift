import SwiftUI
import SwiftspringKit
import SwiftspringUI

@main
struct SwiftspringiOSApp: App {
    @StateObject private var environment: AppEnvironment

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
                .onAppear {
                    BackgroundSyncCoordinator.schedule()
                }
        }
    }
}
