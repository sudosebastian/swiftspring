import SwiftUI
import SwiftspringKit

/// Swiftspring visual language — spruce teal, mist atmosphere, serif wordmark.
public enum SwiftspringBrand {
    public static let name = "Swiftspring"
    public static let tagline = "Mail that feels native."

    public static let spruce = Color(red: 0.06, green: 0.24, blue: 0.24)       // #0F3D3E
    public static let spruceBright = Color(red: 0.12, green: 0.45, blue: 0.42) // #1E7370
    public static let mist = Color(red: 0.93, green: 0.96, blue: 0.95)         // #EDF5F3
    public static let ink = Color(red: 0.08, green: 0.12, blue: 0.14)          // #141F23
    public static let sand = Color(red: 0.96, green: 0.93, blue: 0.88)         // #F5EEE0
    public static let coral = Color(red: 0.86, green: 0.37, blue: 0.29)        // #DB5E4A
    public static let unreadDot = Color(red: 0.12, green: 0.45, blue: 0.42)

    public static var accent: Color { spruceBright }
}

public struct SwiftspringWordmark: View {
    var size: CGFloat = 36
    var showTagline: Bool = false

    public init(size: CGFloat = 36, showTagline: Bool = false) {
        self.size = size
        self.showTagline = showTagline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SwiftspringBrand.name)
                .font(.system(size: size, weight: .semibold, design: .serif))
                .foregroundStyle(SwiftspringBrand.spruce)
                .tracking(-0.5)
            if showTagline {
                Text(SwiftspringBrand.tagline)
                    .font(.system(size: max(13, size * 0.38), weight: .medium, design: .rounded))
                    .foregroundStyle(SwiftspringBrand.spruce.opacity(0.7))
            }
        }
    }
}

public struct AtmosphereBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SwiftspringBrand.mist,
                    Color.white,
                    SwiftspringBrand.sand.opacity(0.55),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(SwiftspringBrand.spruceBright.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 60)
                .offset(x: 180, y: -220)
            Circle()
                .fill(SwiftspringBrand.coral.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: -160, y: 260)
        }
        .ignoresSafeArea()
    }
}

public struct AvatarView: View {
    let name: String
    var size: CGFloat = 36

    public init(name: String, size: CGFloat = 36) {
        self.name = name
        self.size = size
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first.map(String.init) }
        if !chars.isEmpty { return chars.joined().uppercased() }
        return String(name.prefix(1)).uppercased()
    }

    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 360) / 360.0
    }

    public var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 0.35, brightness: 0.55),
                                SwiftspringBrand.spruceBright,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .accessibilityLabel(name)
    }
}

public struct SyncStatusBar: View {
    let accounts: [Account]
    let isSyncing: Bool
    var message: String?

    public init(accounts: [Account], isSyncing: Bool, message: String? = nil) {
        self.accounts = accounts
        self.isSyncing = isSyncing
        self.message = message
    }

    public var body: some View {
        HStack(spacing: 10) {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
            } else if let error = accounts.first(where: { $0.syncState == .error || $0.syncState == .authFailed }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SwiftspringBrand.coral)
                Text(error.syncErrorMessage ?? "Account needs attention")
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SwiftspringBrand.spruceBright)
                Text(message ?? (accounts.isEmpty ? "No accounts" : "Up to date"))
            }
            Spacer()
            Text(accounts.count == 1 ? accounts[0].emailAddress : "\(accounts.count) accounts")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct AppearModifier: ViewModifier {
    @State private var shown = false
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func swiftspringAppear(delay: Double = 0) -> some View {
        modifier(AppearModifier(delay: delay))
    }
}
