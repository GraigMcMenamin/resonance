import SwiftUI

extension Color {
    /// Background purple used by the app bars
    static let appBarPurple = Color(red: 0.15, green: 0.08, blue: 0.18)
    /// Play and review button purple on detail pages (matches the top bar)
    static let buttonPurple = appBarPurple
    /// Slightly lighter than the card purple so the mailbox play button stands out on it
    static let lighterButtonPurple = Color(red: 0.32, green: 0.20, blue: 0.40)
}

extension View {
    /// Paints the top safe area solid purple, since the system bar can render see-through over dark content.
    func solidPurpleTopBar() -> some View {
        self
            .toolbarBackground(Color.appBarPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Color.appBarPurple
                        .frame(height: geo.safeAreaInsets.top)
                        .offset(y: -geo.safeAreaInsets.top)
                }
                .allowsHitTesting(false)
            }
    }
}
