import SwiftUI

enum Theme {
    static let accent = Color(red: 0.06, green: 0.72, blue: 0.51)
    static let accentDeep = Color(red: 0.02, green: 0.56, blue: 0.42)
    static let blue = Color(red: 0.18, green: 0.49, blue: 0.96)
    static let gold = Color(red: 0.93, green: 0.62, blue: 0.10)
    static let purple = Color(red: 0.55, green: 0.34, blue: 0.96)
    static let pink = Color(red: 0.93, green: 0.32, blue: 0.52)

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedBackground = Color(uiColor: .tertiarySystemGroupedBackground)

    static let heroGradient = LinearGradient(
        colors: [accent, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let vipGradient = LinearGradient(
        colors: [Color(red: 0.15, green: 0.16, blue: 0.26), Color(red: 0.28, green: 0.20, blue: 0.48)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }

    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
