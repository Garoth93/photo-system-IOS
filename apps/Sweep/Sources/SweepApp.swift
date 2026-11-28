import BackgroundTasks
import SwiftUI
import SweepCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Background refresh: iCloud backup every ~6 hours (iOS picks the moment).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: CloudBackupService.refreshTaskID, using: nil) { task in
            let work = Task { @MainActor in
                await CloudBackupService.shared.runBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        MainActor.assumeIsolated { _ = CloudBackupService.shared }
        return true
    }
}

@main
struct SweepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @State private var library = PhotoLibrary.shared
    @State private var cloud = CloudBackupService.shared
    @State private var scanner = SimilarScanner.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .environment(library)
                .environment(cloud)
                .environment(scanner)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.refreshStatus()
            case .inactive:
                model.saveNow()
            case .background:
                model.saveNow()
                cloud.appDidEnterBackground()
            @unknown default:
                break
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
