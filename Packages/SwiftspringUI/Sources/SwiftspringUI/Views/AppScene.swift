import SwiftUI
import SwiftspringKit

public struct SwiftspringAppScene: Scene {
    @ObservedObject var environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some Scene {
        WindowGroup {
            RootMailboxView(environment: environment)
        }
        #if os(macOS)
        Settings {
            PreferencesView(environment: environment)
        }
        #endif
    }
}
