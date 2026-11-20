import SwiftUI
import SweepCore

@main
struct SweepApp: App {
    @State private var model = AppModel()
    @State private var library = PhotoLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .environment(library)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: library.refreshStatus()
            case .background, .inactive: model.saveNow()
            @unknown default: break
            }
        }
    }
}

/// Builds the Material palette for the current light/dark appearance.
private struct ThemedRoot: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = M3Theme(seed: Palette.defaultAccent, dark: colorScheme == .dark)
        RootView()
            .environment(\.m3, theme)
            .tint(theme.primary)
    }
}
