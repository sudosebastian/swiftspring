import SwiftUI
import SwiftspringKit

public struct SwiftspringAppScene: Scene {
    @ObservedObject var environment: AppEnvironment
    @AppStorage("swiftspring.appearance") private var appearance = "system"

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some Scene {
        WindowGroup {
            RootMailboxView(environment: environment)
                .preferredColorScheme(colorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        Settings {
            PreferencesView(environment: environment)
        }
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
